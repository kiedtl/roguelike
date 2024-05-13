const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const RexMap = @import("rexpaint").RexMap;

const colors = @import("../colors.zig");
const display = @import("../display.zig");
const err = @import("../err.zig");
const state = @import("../state.zig");
const types = @import("../types.zig");
const ui = @import("../ui.zig");
const utils = @import("../utils.zig");

const Coord = types.Coord;
const Rect = types.Rect;
const Direction = types.Direction;

const Generator = @import("../generators.zig").Generator;
const GeneratorCtx = @import("../generators.zig").GeneratorCtx;
const StackBuffer = @import("../buffer.zig").StackBuffer;

pub const Self = @This();

alloc: mem.Allocator,
heap_inited: bool = false,
grid: []display.Cell,
width: usize,
height: usize,
subconsoles: Subconsole.AList,
default_transparent: bool = false,
mouse_triggers: MouseTrigger.AList,

// some state to make adding mouse triggers less painful
last_text_startx: usize = 0,
last_text_starty: usize = 0,
last_text_endx: usize = 0,
last_text_endy: usize = 0,

// more state to make handling mouse triggers less painful
rendered_offset_x: usize = 0,
rendered_offset_y: usize = 0,

recorded_mouse_area: ?Rect = null,
_reveal_animation: ?*Generator(ui.animationReveal) = null,
_reveal_animation_layer: ?*Self = null,

pub const AList = std.ArrayList(Self);

pub const MouseTrigger = struct {
    kind: Kind,
    rect: Rect,
    action: Action,

    pub const Kind = enum {
        Click,
        Hover,
        Wheel,
    };

    pub const Action = union(enum) {
        Coord,
        Signal: usize,
        ExamineScreen: struct {
            starting_focus: ?ui.ExamineTileFocus = null,
            start_coord: ?Coord = null,
        },
        RecordElem: *Self,
        DescriptionScreen: struct {
            title: StackBuffer(u8, 64),
            id: StackBuffer(u8, 64),
        },
        OpenLogWindow,
    };

    pub const AList = std.ArrayList(@This());
};

pub const MouseEventHandleResult = union(enum) { Unhandled, Outside, Coord: Coord, Signal: usize, Void };

pub const Subconsole = struct {
    console: *Self,
    x: usize = 0,
    y: usize = 0,

    pub const AList = std.ArrayList(@This());
};

pub fn init(alloc: mem.Allocator, width: usize, height: usize) Self {
    const self = .{
        .alloc = alloc,
        .grid = alloc.alloc(display.Cell, width * height) catch err.wat(),
        .width = width,
        .height = height,
        .subconsoles = Subconsole.AList.init(alloc),
        .mouse_triggers = MouseTrigger.AList.init(alloc),
    };
    mem.set(display.Cell, self.grid, .{ .ch = ' ', .fg = 0, .bg = colors.BG });
    return self;
}

pub fn initHeap(alloc: mem.Allocator, width: usize, height: usize) *Self {
    const s = Self.init(alloc, width, height);
    const p = alloc.create(Self) catch err.oom();
    p.* = s;
    p.heap_inited = true;
    return p;
}

pub fn deinit(self: *Self) void {
    self.alloc.free(self.grid);
    for (self.subconsoles.items) |*subconsole|
        subconsole.console.deinit();
    self.subconsoles.deinit();
    self.mouse_triggers.deinit();
    if (self._reveal_animation) |a|
        self.alloc.destroy(a);
    if (self.heap_inited)
        self.alloc.destroy(self);
}

pub fn dimensionsRect(self: *const Self) Rect {
    return Rect.new(Coord.new(0, 0), self.width, self.height);
}

pub fn addSubconsole(self: *Self, subconsole: *Self, x: usize, y: usize) void {
    self.subconsoles.append(.{ .console = subconsole, .x = x, .y = y }) catch err.wat();
}

// Utility function for centering subconsoles
pub fn centerY(self: *const Self, subheight: usize) usize {
    return (self.height / 2) - (subheight / 2);
}

// Utility function for centering subconsoles
pub fn centerX(self: *const Self, subwidth: usize) usize {
    return (self.width / 2) - (subwidth / 2);
}

pub fn changeHeight(self: *Self, new_height: usize) void {
    const new_grid = self.alloc.alloc(display.Cell, self.width * new_height) catch err.wat();
    mem.set(display.Cell, new_grid, .{ .ch = ' ', .fg = 0, .bg = colors.BG });

    // Copy old grid to new grid
    var y: usize = 0;
    while (y < new_height and y < self.height) : (y += 1) {
        var x: usize = 0;
        while (x < self.width) : (x += 1) {
            new_grid[self.width * y + x] = self.grid[self.width * y + x];
        }
    }

    self.alloc.free(self.grid);

    self.height = new_height;
    self.grid = new_grid;
}

pub fn addClickableLine(self: *Self, kind: MouseTrigger.Kind, action: MouseTrigger.Action) void {
    assert(self.last_text_endy == self.last_text_starty);
    self.addMouseTrigger(Rect.new(Coord.new(self.last_text_startx, self.last_text_starty), self.width - 1, 0), kind, action);
}

pub fn addTooltipForText(self: *Self, comptime title_fmt: []const u8, title_args: anytype, comptime id_fmt: []const u8, id_args: anytype) void {
    self.addClickableText(.Hover, .{ .RecordElem = self });
    self.addClickableText(.Click, .{ .DescriptionScreen = .{
        .title = StackBuffer(u8, 64).initFmt(title_fmt, title_args),
        .id = StackBuffer(u8, 64).initFmt(id_fmt, id_args),
    } });
}

pub fn addTooltipForRect(self: *Self, rect: Rect, comptime title_fmt: []const u8, title_args: anytype, comptime id_fmt: []const u8, id_args: anytype) void {
    self.addMouseTrigger(rect, .Hover, .{ .RecordElem = self });
    self.addMouseTrigger(rect, .Click, .{ .DescriptionScreen = .{
        .title = StackBuffer(u8, 64).initFmt(title_fmt, title_args),
        .id = StackBuffer(u8, 64).initFmt(id_fmt, id_args),
    } });
}

pub fn addClickableTextBoth(self: *Self, click_action: MouseTrigger.Action) void {
    self.addClickableText(.Hover, .{ .RecordElem = self });
    self.addClickableText(.Click, click_action);
}

pub fn addClickableText(self: *Self, kind: MouseTrigger.Kind, action: MouseTrigger.Action) void {
    self.addMouseTrigger(Rect.new(
        Coord.new(self.last_text_startx, self.last_text_starty),
        self.last_text_endx - self.last_text_startx,
        self.last_text_endy - self.last_text_starty,
    ), kind, action);
}

pub fn addMouseTrigger(self: *Self, rect: Rect, kind: MouseTrigger.Kind, action: MouseTrigger.Action) void {
    self.mouse_triggers.append(.{ .rect = rect, .kind = kind, .action = action }) catch err.oom();
}

fn _handleMouseEvent(self: *Self, abscoord: Coord, kind: MouseTrigger.Kind, dim: Rect) MouseEventHandleResult {
    self.recorded_mouse_area = null;

    const coord = abscoord.asRect();
    if (!dim.intersects(&coord, 0))
        return .Outside;
    for (self.subconsoles.items) |*subconsole| {
        const r = Rect.new(Coord.new(dim.start.x + subconsole.x, dim.start.y + subconsole.y), subconsole.console.width, subconsole.console.height);
        const res = _handleMouseEvent(subconsole.console, abscoord, kind, r);
        // std.log.debug("HANDLED abscoord={}, r={}, res={}, subconsole: {},{}", .{ abscoord, r, res, subconsole.console.width, subconsole.console.height });
        if (res != .Outside and res != .Unhandled)
            return res;
    }
    for (self.mouse_triggers.items) |t| {
        // std.log.debug("HANDLING abscoord={}, kind={}, dim={}, coord={}, coordrel={}, tkind={}, trect={}", .{ abscoord, kind, dim, coord, coord.relTo(dim), t.kind, t.rect });
        if (t.kind == kind and t.rect.intersects(&coord.relTo(dim), 1)) {
            switch (t.action) {
                .Signal => |s| return .{ .Signal = s },
                .Coord => return .{ .Coord = abscoord },
                .ExamineScreen => |o| {
                    const did_anything = ui.drawExamineScreen(o.starting_focus, o.start_coord);
                    assert(!did_anything);
                    return .Void;
                },
                .RecordElem => {
                    self.recorded_mouse_area = t.rect;
                    return .Void;
                },
                .DescriptionScreen => |info| {
                    if (state.descriptions.get(info.id.constSlice())) |desc| {
                        ui.drawTextModal("$c{s}$.\n\n{s}", .{ info.title.constSlice(), desc });
                    } else {
                        err.ensure(false, "Missing description {s}", .{info.id.constSlice()}) catch {};
                    }
                    return .Void;
                },
                .OpenLogWindow => {
                    ui.drawMessagesScreen();
                    return .Void;
                },
            }
        }
    }
    return .Unhandled;
}

pub fn handleMouseEvent(self: *Self, abscoord: Coord, kind: MouseTrigger.Kind) MouseEventHandleResult {
    const r = Rect.new(Coord.new(self.rendered_offset_x, self.rendered_offset_y), self.width, self.height);
    return _handleMouseEvent(self, abscoord, kind, r);
}

pub fn clearMouseTriggers(self: *Self) void {
    self.mouse_triggers.clearRetainingCapacity();
}

pub fn clearTo(self: *const Self, to: display.Cell) void {
    mem.set(display.Cell, self.grid, to);
}

pub fn clearColumnTo(self: *const Self, starty: usize, endy: usize, x: usize, cell: display.Cell) void {
    var y = starty;
    while (y <= endy) : (y += 1)
        self.grid[y * self.width + x] = cell;
}

pub fn clearLineTo(self: *const Self, startx: usize, endx: usize, y: usize, cell: display.Cell) void {
    var x = startx;
    while (x <= endx) : (x += 1)
        self.grid[y * self.width + x] = cell;
}

pub fn clearLine(self: *const Self, startx: usize, endx: usize, y: usize) void {
    self.clearLineTo(startx, endx, y, .{ .ch = ' ', .fg = 0, .bg = colors.BG, .trans = self.default_transparent });
}

pub fn highlightMouseArea(self: *const Self, color: u32) void {
    if (self.recorded_mouse_area) |area| {
        var y = area.start.y;
        while (y <= area.end().y) : (y += 1) {
            var x = area.start.x;
            while (x <= area.end().x) : (x += 1)
                if (y < self.height and x < self.width and
                    self.grid[y * self.width + x].bg == colors.BG or
                    self.grid[y * self.width + x].bg == colors.ABG)
                {
                    self.grid[y * self.width + x].bg = color;
                    self.grid[y * self.width + x].sbg = color;
                };
        }
    }
}

pub fn setBorder(self: *const Self) void {
    _ = self.clearLineTo(0, self.width - 1, 0, .{ .ch = '▄', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
    _ = self.clearLineTo(0, self.width - 1, self.height - 1, .{ .ch = '▀', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
    _ = self.clearColumnTo(1, self.height - 2, 0, .{ .ch = '█', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
    _ = self.clearColumnTo(1, self.height - 2, self.width - 1, .{ .ch = '█', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });

    // _ = self.setCell(0, 0, .{ .ch = '▗', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
    // _ = self.setCell(0, self.height - 1, .{ .ch = '▙', .bg = colors.LIGHT_STEEL_BLUE, .fg = colors.BG });
    // _ = self.setCell(self.width - 1, 0, .{ .ch = '▖', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
    // _ = self.setCell(self.width - 1, self.height - 1, .{ .ch = '▘', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
}

pub fn clear(self: *const Self) void {
    self.clearTo(.{ .ch = ' ', .fg = 0, .bg = colors.BG, .trans = self.default_transparent });
}

pub fn renderAreaAt(self: *Self, offset_x: usize, offset_y: usize, begin_x: usize, begin_y: usize, end_x: usize, end_y: usize) void {
    self.rendered_offset_x = offset_x;
    self.rendered_offset_y = offset_y;

    var dy: usize = offset_y;
    var y: usize = begin_y;
    while (y < end_y) : (y += 1) {
        //_clear_line(offset_x, offset_x + (end_x - begin_x), dy);
        var dx: usize = offset_x;
        var x: usize = begin_x;
        while (x < end_x) : (x += 1) {
            const cell = self.grid[self.width * y + x];
            if (!cell.trans) {
                display.setCell(dx, dy, cell);
            }
            dx += 1;
        }
        dy += 1;
    }

    for (self.subconsoles.items) |subconsole| {
        var i: usize = 0;
        var sdy: usize = subconsole.y -| begin_y;
        while (i < subconsole.console.height) : (i += 1) {
            const sy = subconsole.y + i;
            const sx = subconsole.x;
            if (sy < begin_y or sy > end_y or sx < begin_x or sx > end_x)
                continue;
            const sdx = offset_x + sx;
            subconsole.console.renderAreaAt(sdx, offset_y + sdy, 0, i, subconsole.console.width, i + 1);
            sdy += 1;
        }
        subconsole.console.rendered_offset_y = subconsole.y; // XXX: is this even correct?
    }
}

pub fn renderFully(self: *Self, offset_x: usize, offset_y: usize) void {
    self.renderAreaAt(offset_x, offset_y, 0, 0, self.width, self.height);
}

pub fn renderFullyW(self: *Self, win: ui.DisplayWindow) void {
    const d = ui.dimensions(win);
    self.renderAreaAt(d.startx, d.starty, 0, 0, self.width, self.height);
}

pub fn getCell(self: *const Self, x: usize, y: usize) display.Cell {
    return self.grid[self.width * y + x];
}

pub fn setCell(self: *const Self, x: usize, y: usize, c: display.Cell) void {
    if (x >= self.width or y >= self.height)
        return;
    self.grid[self.width * y + x] = c;
}

pub fn addRevealAnimation(self: *Self, opts: ui.RevealAnimationOpts) void {
    if (self._reveal_animation_layer == null) {
        const a = Self.initHeap(self.alloc, self.width, self.height);
        a.default_transparent = true;
        a.clear();
        self._reveal_animation_layer = a;
        self.addSubconsole(a, 0, 0);
    } else {
        assert(self._reveal_animation_layer.?.default_transparent);
        self._reveal_animation_layer.?.clear();
    }

    if (self._reveal_animation) |oldanim| {
        state.gpa.allocator().destroy(oldanim);
    }

    self._reveal_animation = self.alloc.create(Generator(ui.animationReveal)) catch err.oom();
    self._reveal_animation.?.* = Generator(ui.animationReveal).init(.{ .main_layer = self, .anim_layer = self._reveal_animation_layer.?, .opts = opts });
}

pub fn stepRevealAnimation(self: *Self) void {
    _ = self._reveal_animation.?.next();
}

pub fn drawOutlineAround(self: *const Self, coord: Coord, style: display.Cell) void {
    const f: isize = if (style.fl.wide) 2 else 1;
    const c = [_]struct { x: isize, y: isize, ch: u21 }{
        // zig fmt: off
        .{ .x = -f, .y = -1, .ch = '╭' },
        .{ .x =  0, .y = -1, .ch = '─' },
        .{ .x =  f, .y = -1, .ch = '╮' },
        .{ .x = -f, .y =  0, .ch = '│' },
        .{ .x =  f, .y =  0, .ch = '│' },
        .{ .x = -f, .y =  1, .ch = '╰' },
        .{ .x =  0, .y =  1, .ch = '─' },
        .{ .x =  f, .y =  1, .ch = '╯' },
        // zig fmt: on
    };
    for (c) |i| {
        var cell = style;
        cell.ch = i.ch;
        const dx = @intCast(isize, coord.x) + i.x;
        const dy = @intCast(isize, coord.y) + i.y;
        if (dx < 0 or dy < 0) continue;
        self.setCell(@intCast(usize, dx), @intCast(usize, dy), cell);
    }
}

// TODO: draw multiple layers as needed
pub fn drawXP(self: *const Self, map: *const RexMap, startx: usize, starty: usize, pmrect: ?Rect, wide: bool) void {
    const mrect = pmrect orelse Rect.new(Coord.new(0, 0), map.width, map.height);
    var dy: usize = starty;
    var y: usize = mrect.start.y;
    while (y < map.height and y < mrect.end().y and dy < self.height) : ({
        y += 1;
        dy += 1;
    }) {
        var dx: usize = startx;
        var x: usize = mrect.start.x;
        while (x < map.width and x < mrect.end().x and dx < self.width) : ({
            x += 1;
            dx += 1;
        }) {
            const tile = map.get(x, y);

            if (tile.bg.r == 255 and tile.bg.g == 0 and tile.bg.b == 255) {
                if (wide) {
                    self.setCell(dx, dy, .{ .fl = .{ .wide = true } });
                    dx += 1;
                    self.setCell(dx, dy, .{ .fl = .{ .skip = true } });
                }
                continue;
            }

            const bg = tile.bg.asU32();

            self.setCell(dx, dy, .{
                .ch = RexMap.DEFAULT_TILEMAP[tile.ch],
                .fg = tile.fg.asU32(),
                .bg = if (bg == 0) colors.BG else bg,
                .fl = .{ .wide = wide },
            });

            if (wide) {
                dx += 1;
                self.setCell(dx, dy, .{ .fl = .{ .skip = true } });
            }
        }
    }
}

pub fn drawCapturedDisplay(self: *const Self, startx: usize, starty: usize) void {
    var y: usize = 0;
    var dy: usize = starty;
    while (y < self.height) : ({
        y += 1;
        dy += 1;
    }) {
        var x: usize = 0;
        var dx: usize = startx;
        while (x < self.width) : ({
            x += 1;
            dx += 1;
        }) {
            self.setCell(x, y, display.getCell(dx, dy));
        }
    }
}

pub fn drawTextAtf(self: *Self, startx: usize, starty: usize, comptime format: []const u8, args: anytype, opts: ui.DrawStrOpts) usize {
    const str = std.fmt.allocPrint(state.gpa.allocator(), format, args) catch err.oom();
    defer state.gpa.allocator().free(str);
    return self.drawTextAt(startx, starty, str, opts);
}

// Re-implementation of _drawStr
//
// Returns lines/rows used
pub fn drawTextAt(self: *Self, startx: usize, starty: usize, str: []const u8, opts: ui.DrawStrOpts) usize {
    self.last_text_startx = startx;
    self.last_text_starty = starty;
    self.last_text_endx = startx;

    var x = startx;
    var y = starty;
    var skipped: usize = 0; // TODO: remove
    var no_incr_y = false;

    var fg = opts.fg;
    var bg: ?u32 = opts.bg;

    var fibuf = StackBuffer(u8, 4096).init(null);
    var fold_iter = utils.FoldedTextIterator.init(str, self.width + 1);
    main: while (fold_iter.next(&fibuf)) |line| : ({
        y += 1;
        if (no_incr_y) {
            y -= 1;
            no_incr_y = false;
        }
        if (x > self.last_text_endx + 1)
            self.last_text_endx = x -| 1;
        if (opts.xptr) |xptr|
            xptr.* = x;
        x = startx;
    }) {
        if (skipped < opts.skip_lines) {
            skipped += 1;
            no_incr_y = true; // Stay on the same line
            continue;
        }

        if (y >= self.height or (opts.endy != null and y >= opts.endy.?)) {
            break;
        }

        var utf8 = (std.unicode.Utf8View.init(line) catch err.bug("bad utf8", .{})).iterator();
        while (utf8.nextCodepointSlice()) |encoded_codepoint| {
            const codepoint = std.unicode.utf8Decode(encoded_codepoint) catch err.bug("bad utf8", .{});
            if (y * self.width + x >= self.width * self.height)
                break :main;
            const def_bg = self.grid[y * self.width + x].bg;

            switch (codepoint) {
                '\n' => {
                    y += 1;
                    if (x > self.last_text_endx + 1) self.last_text_endx = x -| 1;
                    x = startx;
                    continue;
                },
                '\r' => err.bug("Bad character found in string.", .{}),
                '$' => {
                    const next_encoded_codepoint = utf8.nextCodepointSlice() orelse
                        err.bug("Found incomplete escape sequence", .{});
                    const next_codepoint = std.unicode.utf8Decode(next_encoded_codepoint) catch err.bug("bad utf8", .{});
                    switch (next_codepoint) {
                        '.' => {
                            fg = opts.fg;
                            bg = opts.bg;
                        },
                        '~' => {
                            const t = fg;
                            fg = bg orelse def_bg;
                            bg = t;
                        },
                        'g' => fg = colors.GREY,
                        'G' => fg = colors.DARK_GREY,
                        'C' => fg = colors.CONCRETE,
                        'c' => fg = colors.LIGHT_CONCRETE,
                        'p' => fg = colors.PINK,
                        'b' => fg = colors.LIGHT_STEEL_BLUE,
                        'r' => fg = colors.PALE_VIOLET_RED,
                        'a' => fg = colors.AQUAMARINE,
                        'o' => fg = colors.GOLD,
                        else => err.bug("[Console] Found unknown escape sequence '${u}' (line: '{s}')", .{ next_codepoint, line }),
                    }
                    continue;
                },
                else => {
                    self.setCell(x, y, .{ .ch = codepoint, .fg = fg, .bg = bg orelse def_bg });
                    x += 1;
                },
            }

            if (!opts.fold and x == self.width) {
                x -= 1;
            }
        }
    }

    if (y == starty) { // Handle case of message w/o newline
        self.last_text_endy = y;
    } else {
        self.last_text_endy = y - 1;
    }

    return y - starty;
}

pub fn drawBarAt(self: *Self, x: usize, endx: usize, y: usize, current: usize, max: usize, description: []const u8, bg: u32, fg: u32, opts: struct {
    detail: bool = true,
    detail_type: enum { Specific, Percent } = .Specific,
}) usize {
    assert(current <= max);
    if (y >= self.height) return 0;

    const depleted_bg = colors.percentageOf(bg, 40);
    const percent = if (max == 0) 100 else (current * 100) / max;
    const bar = ((endx - x - 1) * percent) / 100;
    const bar_end = x + bar;

    self.clearLineTo(x, endx - 1, y, .{ .ch = ' ', .fg = fg, .bg = depleted_bg });
    if (percent != 0)
        self.clearLineTo(x, bar_end, y, .{ .ch = ' ', .fg = fg, .bg = bg });

    _ = self.drawTextAt(x + 1, y, description, .{ .fg = fg, .bg = null });

    if (opts.detail) switch (opts.detail_type) {
        .Percent => {
            const info_width = @intCast(usize, std.fmt.count("{}%", .{percent}));
            _ = self.drawTextAtf(endx - info_width - 1, y, "{}%", .{percent}, .{ .fg = fg, .bg = null });
        },
        .Specific => {
            const info_width = @intCast(usize, std.fmt.count("{} / {}", .{ current, max }));
            _ = self.drawTextAtf(endx - info_width - 1, y, "{} / {}", .{ current, max }, .{ .fg = fg, .bg = null });
        },
    };

    self.last_text_startx = x;
    self.last_text_endx = endx - 1;
    return 1;
}
