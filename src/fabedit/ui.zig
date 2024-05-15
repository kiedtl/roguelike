const std = @import("std");
const meta = std.meta;
const math = std.math;
const mem = std.mem;

const colors = @import("../colors.zig");
const display = @import("../display.zig");
const err = @import("../err.zig");
const fabedit = @import("../fabedit.zig");
const mapgen = @import("../mapgen.zig");
const materials = @import("../materials.zig");
const state = @import("../state.zig");
const surfaces = @import("../surfaces.zig");
const types = @import("../types.zig");
const utils = @import("../utils.zig");

const Rect = types.Rect;
const Coord = types.Coord;
const Console = @import("../ui/Console.zig");

pub const FRAMERATE = 1000 / 45;

pub var map_win: struct {
    main: Console = undefined,
    lyr1: Console = undefined,

    pub fn init(self: *@This()) void {
        self.main = Console.init(state.gpa.allocator(), 40 * 2, 40);
        self.lyr1 = Console.init(state.gpa.allocator(), 40 * 2, 40);
        self.lyr1.default_transparent = true;
        self.lyr1.clear();
        self.lyr1.addMouseTrigger(self.main.dimensionsRect(), .Click, .Coord);
        self.lyr1.addMouseTrigger(self.main.dimensionsRect(), .Hover, .Coord);
        self.main.addSubconsole(&self.lyr1, 0, 0);
    }

    pub fn handleMouseEvent(self: *@This(), ev: display.Event, st: *fabedit.EdState) bool {
        return switch (ev) {
            .Click, .Hover => |c| switch (self.lyr1.handleMouseEvent(c, _evToMEvType(ev))) {
                .Coord => |coord| b: {
                    if (ev == .Click) {
                        switch (st.cursor) {
                            .Prop => fabedit.applyCursorProp(),
                            .Basic => fabedit.applyCursorBasic(),
                            .PrisonArea => fabedit.applyCursorPrisonArea(),
                        }
                        break :b true;
                    } else {
                        st.x = math.min(st.fab.width, coord.x / 2);
                        st.y = math.min(st.fab.height, coord.y);
                        break :b true;
                    }
                },
                .Signal => err.wat(),
                .Unhandled, .Void => true,
                .Outside => false,
            },
            .Wheel => false,
            else => unreachable,
        };
    }
} = .{};

pub const HUD_WIDTH = 30;
pub const HudMouseSignalTag = enum(u64) {
    SwitchPane = 1 << 16,
    Prop = 1 << 17,
    Basic = 1 << 18,
    Area = 1 << 19,
    AreaIncH = 1 << 20,
    AreaDecH = 1 << 21,
    AreaIncW = 1 << 22,
    AreaDecW = 1 << 23,
    AreaAddDel = 1 << 24, // 0 == add, 1 == del
};
pub var hud_win: struct {
    main: Console = undefined,

    pub fn init(self: *@This()) void {
        self.main = Console.init(state.gpa.allocator(), HUD_WIDTH, 40);
    }

    pub fn handleMouseEvent(self: *@This(), ev: display.Event, st: *fabedit.EdState) bool {
        return switch (ev) {
            .Click, .Hover => |c| switch (self.main.handleMouseEvent(c, _evToMEvType(ev))) {
                .Coord => err.wat(),
                .Signal => |s| b: {
                    if (s & @enumToInt(HudMouseSignalTag.SwitchPane) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.SwitchPane);
                        st.hud_pane = @intToEnum(fabedit.EdState.HudPane, i);
                        st.fab_redraw = true;
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.Prop) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.Prop);
                        st.cursor = .{ .Prop = i };
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.Basic) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.Basic);
                        st.cursor = .{ .Basic = @intToEnum(fabedit.EdState.BasicCursor, i) };
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.Area) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.Area);
                        st.cursor = .{ .PrisonArea = i };
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.AreaIncH) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.AreaIncH);
                        st.fab.prisons.slice()[i].height += 1;
                        st.fab_info[st.fab_index].unsaved = true;
                        st.fab_redraw = true;
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.AreaDecH) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.AreaDecH);
                        st.fab.prisons.slice()[i].height -|= 1;
                        st.fab_info[st.fab_index].unsaved = true;
                        st.fab_redraw = true;
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.AreaIncW) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.AreaIncW);
                        st.fab.prisons.slice()[i].width += 1;
                        st.fab_info[st.fab_index].unsaved = true;
                        st.fab_redraw = true;
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.AreaDecW) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.AreaDecW);
                        st.fab.prisons.slice()[i].width -|= 1;
                        st.fab_info[st.fab_index].unsaved = true;
                        st.fab_redraw = true;
                        break :b true;
                    } else if (s & @enumToInt(HudMouseSignalTag.AreaAddDel) > 0) {
                        switch (s & ~@enumToInt(HudMouseSignalTag.AreaAddDel)) {
                            0 => st.fab.prisons.append(Rect.new(Coord.new(0, 0), 1, 1)) catch {
                                std.log.err("Too many prison areas", .{});
                            },
                            1 => if (st.cursor == .PrisonArea) {
                                _ = st.fab.prisons.orderedRemove(st.cursor.PrisonArea) catch err.wat();
                                st.cursor.PrisonArea -|= 1;
                                if (st.fab.prisons.len == 0) {
                                    st.cursor = .{ .Basic = .Wall };
                                }
                            },
                            else => unreachable,
                        }
                        st.fab_info[st.fab_index].unsaved = true;
                        st.fab_redraw = true;
                        break :b true;
                    } else unreachable;
                },
                .Unhandled, .Void => true,
                .Outside => false,
            },
            .Wheel => false,
            else => unreachable,
        };
    }
} = .{};

pub var bar_win: struct {
    main: Console = undefined,

    pub fn init(self: *@This()) void {
        self.main = Console.init(state.gpa.allocator(), 40 * 2, 1);
    }

    pub fn handleMouseEvent(self: *@This(), ev: display.Event, _: *fabedit.EdState) bool {
        return switch (ev) {
            .Click, .Hover => |c| switch (self.main.handleMouseEvent(c, _evToMEvType(ev))) {
                .Coord => err.wat(),
                .Signal => |s| switch (s) {
                    1 => b: {
                        fabedit.prevFab();
                        break :b true;
                    },
                    2 => b: {
                        fabedit.nextFab();
                        break :b true;
                    },
                    else => unreachable,
                },
                .Unhandled, .Void => true,
                .Outside => false,
            },
            .Wheel => false,
            else => unreachable,
        };
    }
} = .{};

pub var container: struct {
    main: Console = undefined,

    pub fn init(self: *@This()) void {
        self.main = Console.init(state.gpa.allocator(), (40 * 2) + HUD_WIDTH + 1, 40 + 1);
        self.main.addSubconsole(&map_win.main, 0, 0);
        self.main.addSubconsole(&hud_win.main, 40 * 2 + 1, 0);
        self.main.addSubconsole(&bar_win.main, 0, 40);
    }

    pub fn deinit(self: *@This()) void {
        self.main.deinit();
    }
} = .{};

pub fn init() !void {
    try display.init((40 * 2) + HUD_WIDTH + 1, 40 + 1, 1.0);
    map_win.init();
    hud_win.init();
    bar_win.init();
    container.init();
}

pub fn displayAs(st: *fabedit.EdState, ftile: mapgen.Prefab.FabTile) display.Cell {
    const prefix = st.fab_name[0..3];
    const wall_material = if (mem.eql(u8, prefix, "CAV"))
        &materials.Basalt
    else if (mem.eql(u8, prefix, "LAB") or mem.eql(u8, prefix, "WRK"))
        &materials.Dobalene
    else if (mem.eql(u8, prefix, "CRY") or mem.eql(u8, prefix, "SIN"))
        &materials.Marble
    else
        &materials.Concrete;
    const win_material = if (mem.eql(u8, prefix, "LAB") or mem.eql(u8, prefix, "WRK"))
        &materials.LabGlass
    else
        &materials.Glass;
    const door_machine = if (mem.eql(u8, prefix, "LAB") or mem.eql(u8, prefix, "WRK"))
        &surfaces.LabDoor
    else
        &surfaces.NormalDoor;
    return switch (ftile) {
        .Wall => .{
            .ch = '#',
            .sch = wall_material.sprite,
            .fg = wall_material.color_fg,
            .bg = wall_material.color_bg orelse colors.BG,
        },
        .Window => .{
            .ch = '#',
            .sch = win_material.sprite,
            .fg = win_material.color_fg,
            .bg = win_material.color_bg orelse colors.BG,
        },
        .Any => .{ .ch = '?', .fg = 0xaaaaaa, .bg = colors.BG },
        .Connection => .{ .ch = '*', .fg = 0xaaaaaa, .bg = colors.BG },
        .Floor => .{ .ch = '·', .fg = 0x777777, .bg = colors.BG },
        .Door => .{
            .ch = '·',
            .sch = door_machine.unpowered_sprite,
            .fg = door_machine.unpowered_fg orelse 0xcccccc,
            .bg = door_machine.unpowered_bg orelse colors.BG,
        },
        .LockedDoor => .{
            .ch = '±',
            .sch = surfaces.LockedDoor.unpowered_sprite,
            .fg = surfaces.LockedDoor.unpowered_fg orelse 0xcccccc,
            .bg = surfaces.LockedDoor.unpowered_bg orelse colors.BG,
        },
        else => unreachable,
    };
}

pub fn drawBar(st: *fabedit.EdState) void {
    bar_win.main.clear();
    bar_win.main.clearMouseTriggers();

    var x: usize = 1;

    // *name
    if (st.fab_info[st.fab_index].unsaved) {
        bar_win.main.setCell(x, 0, .{ .ch = '*', .fg = 0xff1111, .bg = colors.BG });
        x += 1;
    }
    _ = bar_win.main.drawTextAt(x, 0, st.fab_name, .{ .xptr = &x });
    x += 1;

    // « {}/{} »
    const can_go_back = st.fab_index > 0;
    const can_go_forw = st.fab_index < st.fab_variants.len - 1;

    const c1: u32 = if (can_go_back) 0xffd700 else 0xaaaaaa;
    bar_win.main.setCell(x, 0, .{ .ch = '«', .fg = c1, .bg = colors.BG });
    bar_win.main.addMouseTrigger(Rect.new(Coord.new(x, 0), 0, 0), .Click, .{
        .Signal = 1,
    });
    x += 2;

    _ = bar_win.main.drawTextAtf(x, 0, "{}$g/$.{}", .{ st.fab_index + 1, st.fab_variants.len }, .{ .xptr = &x });
    x += 1;

    const c2: u32 = if (can_go_forw) 0xffd700 else 0xaaaaaa;
    bar_win.main.setCell(x, 0, .{ .ch = '»', .fg = c2, .bg = colors.BG });
    bar_win.main.addMouseTrigger(Rect.new(Coord.new(x, 0), 0, 0), .Click, .{
        .Signal = 2,
    });
    x += 2;

    if (st.fab.tunneler_prefab) {
        _ = bar_win.main.drawTextAt(x, 0, "$g·$. $cTun $g($.", .{ .xptr = &x });
        for (st.fab.tunneler_orientation.constSlice()) |orien| {
            bar_win.main.setCell(x, 0, .{ .ch = orien.name()[0], .fg = colors.OFF_WHITE, .bg = colors.BG });
            x += 1;
        }
        if (st.fab.tunneler_inset)
            _ = bar_win.main.drawTextAt(x, 0, "$g; $pinset", .{ .xptr = &x });
        _ = bar_win.main.drawTextAt(x, 0, "$g)", .{ .xptr = &x });
    }
}

pub fn drawHUD(st: *fabedit.EdState) void {
    hud_win.main.clear();
    hud_win.main.clearMouseTriggers();

    var y: usize = 0;

    var tabx: usize = 0;
    inline for (meta.fields(fabedit.EdState.HudPane)) |field, i| {
        if (i != 0) {
            _ = hud_win.main.drawTextAt(tabx, y, " · ", .{});
            tabx += 3;
        }
        var c: u21 = 'g';
        if (mem.eql(u8, @tagName(st.hud_pane), field.name))
            c = 'c';
        _ = hud_win.main.drawTextAtf(tabx, y, "${u}{s}$.", .{ c, field.name }, .{});
        const signal = @enumToInt(HudMouseSignalTag.SwitchPane) | i;
        hud_win.main.addClickableTextBoth(.{ .Signal = signal });
        tabx += field.name.len;
    }
    y += 2;

    const PANEL_WIDTH = HUD_WIDTH / 2;

    switch (st.hud_pane) {
        .Basic => {
            var dx: usize = 0;
            inline for (meta.fields(fabedit.EdState.BasicCursor)) |field| {
                const v = @intToEnum(fabedit.EdState.BasicCursor, field.value);
                var cell: display.Cell = switch (v) {
                    .Wall => displayAs(st, .Wall),
                    .Window => displayAs(st, .Window),
                    .Door => displayAs(st, .Door),
                    .LockedDoor => displayAs(st, .LockedDoor),
                    .Connection => displayAs(st, .Connection),
                    .Any => displayAs(st, .Any),
                };
                if (st.cursor == .Basic and v == st.cursor.Basic)
                    cell.bg = colors.mix(cell.bg, 0xffffff, 0.2);
                cell.fl.wide = true;
                hud_win.main.setCell(dx, y, cell);
                hud_win.main.setCell(dx + 1, y, .{ .fl = .{ .skip = true } });
                const signal = @enumToInt(HudMouseSignalTag.Basic) | field.value;
                hud_win.main.addClickableTextBoth(.{ .Signal = signal });
                hud_win.main.addMouseTrigger(Rect.new(Coord.new(dx, y), 0, 0), .Click, .{
                    .Signal = signal,
                });
                dx += 2;
            }
        },
        .Props => {
            const selected_i = if (st.cursor == .Prop) st.cursor.Prop else 0;
            const cursor_x = selected_i % PANEL_WIDTH;
            var display_row = (selected_i - cursor_x) / PANEL_WIDTH;
            if (display_row >= 4)
                display_row -= 4;

            const selected = &surfaces.props.items[selected_i];
            y += hud_win.main.drawTextAtf(0, y, "$cSelected:$. {s}", .{selected.id}, .{});

            var dx: usize = 0;
            for (surfaces.props.items) |prop, i| {
                var cell = display.Cell{};
                cell.fg = prop.fg orelse colors.BG;
                cell.bg = prop.bg orelse colors.BG;
                cell.ch = prop.tile;
                cell.sch = prop.sprite;
                if (prop.tile == ' ')
                    cell = .{ .ch = '·', .fg = 0xaaaaaa, .bg = colors.BG };
                if (st.cursor == .Prop and i == st.cursor.Prop)
                    cell.bg = colors.mix(cell.bg, 0xffffff, 0.2);
                cell.fl.wide = true;
                hud_win.main.setCell(dx, y, cell);
                hud_win.main.setCell(dx + 1, y, .{ .fl = .{ .skip = true } });
                const signal = @enumToInt(HudMouseSignalTag.Prop) | i;
                hud_win.main.addMouseTrigger(Rect.new(Coord.new(dx, y), 0, 0), .Click, .{
                    .Signal = signal,
                });
                dx += 2;
                if (dx >= HUD_WIDTH - 2) {
                    dx = 0;
                    if (i / PANEL_WIDTH > display_row -| 4)
                        y += 1;
                }
            }

            const box_chars = [_]u21{ '┌', '╥', '┐', '╔', '╤', '╗', '╓', '┬', '╖', '\n', '╞', '╬', '╡', '╟', '┼', '╢', '╠', '╪', '╣', '\n', '└', '╨', '┘', '╚', '╧', '╝', '╙', '┴', '╜', '\n', '┌', '─', '┬', '┐', '╔', '═', '╦', '╗', '╒', '╕', '\n', '├', '─', '┼', '┤', '╠', '═', '╬', '╣', '╘', '╛', '\n', '│', ' ', '│', '│', '║', ' ', '║', '║', '╭', '╮', '\n', '└', '─', '┴', '┘', '╚', '═', '╩', '╝', '╰', '╯' };
            const box_char_names = [_]struct { ch: u21, name: []const u8 }{
                .{ .ch = '┌', .name = "s1e1" },
                .{ .ch = '└', .name = "n1e1" },
                .{ .ch = '┘', .name = "n1w1" },
                .{ .ch = '┐', .name = "s1w1" },
                .{ .ch = '┬', .name = "s1e1w1" },
                .{ .ch = '┼', .name = "n1s1e1w1" },
                .{ .ch = '┴', .name = "n1e1w1" },
                .{ .ch = '─', .name = "e1w1" },
                .{ .ch = '├', .name = "n1s1e1" },
                .{ .ch = '┤', .name = "n1s1w1" },
                .{ .ch = '│', .name = "n1s1" },
                .{ .ch = '╞', .name = "n1s1e2" },
                .{ .ch = '╡', .name = "n1s1w2" },
                .{ .ch = '╟', .name = "n2s2e1" },
                .{ .ch = '╢', .name = "n2s2w1" },
                .{ .ch = '╨', .name = "n2e1w1" },
                .{ .ch = '╥', .name = "s2e1w1" },
                .{ .ch = '╪', .name = "n1s1e2w2" },
                .{ .ch = '╧', .name = "n1e2w2" },
                .{ .ch = '╙', .name = "n2e1" },
                .{ .ch = '╜', .name = "n2w1" },
                .{ .ch = '╒', .name = "s1e2" },
                .{ .ch = '╕', .name = "s1w2" },
                .{ .ch = '╘', .name = "n1e2" },
                .{ .ch = '╛', .name = "n1w2" },
                .{ .ch = '╤', .name = "s1e2w2" },
                .{ .ch = '╔', .name = "s2e2" },
                .{ .ch = '╝', .name = "n2w2" },
                .{ .ch = '╗', .name = "s2w2" },
                .{ .ch = '╓', .name = "s2e1" },
                .{ .ch = '╖', .name = "s2w1" },
                .{ .ch = '╬', .name = "n2s2e2w2" },
                .{ .ch = '╠', .name = "n2s2e2" },
                .{ .ch = '╣', .name = "n1s1w2" },
                .{ .ch = '╚', .name = "n2e2" },
                .{ .ch = '═', .name = "e2w2" },
                .{ .ch = '╦', .name = "s2e2w2" },
                .{ .ch = '╩', .name = "n2e2w2" },
                .{ .ch = '║', .name = "n2s2" },
                .{ .ch = '╭', .name = "s1e1c" },
                .{ .ch = '╮', .name = "s1w1c" },
                .{ .ch = '╰', .name = "n1e1c" },
                .{ .ch = '╯', .name = "n1w1c" },
            };

            var sel_prefix: ?[]const u8 = null;
            var sel_char: ?usize = null; // index into box_char_names

            if (st.cursor == .Prop) {
                const sel = &surfaces.props.items[st.cursor.Prop];
                if (mem.lastIndexOfScalar(u8, sel.id, '_')) |last| {
                    if (last + 1 < sel.id.len) {
                        const sel_charname = sel.id[last + 1 ..];
                        sel_char = for (box_char_names) |charname, i| {
                            if (mem.eql(u8, charname.name, sel_charname))
                                break i;
                        } else null;
                        sel_prefix = sel.id[0..last];
                    }
                }
            }

            y += 3;
            dx = 0;
            for (box_chars) |box_char| {
                if (box_char == '\n') {
                    y += 1;
                    dx = 0;
                    continue;
                } else if (box_char == ' ') {
                    dx += 2;
                    continue;
                }

                const info = for (box_char_names) |charname| {
                    if (charname.ch == box_char) break charname;
                } else unreachable;

                var cell = display.Cell{ .ch = box_char, .fg = 0x555555 };
                var prop: ?usize = null;
                if (sel_char) |sel_char_| {
                    if (mem.eql(u8, info.name, box_char_names[sel_char_].name)) {
                        cell.bg = colors.mix(cell.bg, 0xffffff, 0.2);
                    }
                    var buf: [32]u8 = undefined;
                    const prop_id = utils.print(&buf, "{s}_{s}", .{ sel_prefix.?, info.name });
                    prop = utils.findById(surfaces.props.items, prop_id);
                    if (prop != null)
                        cell.fg = surfaces.props.items[st.cursor.Prop].fg orelse 0xffffff;
                }
                cell.fl.wide = true;
                hud_win.main.setCell(dx, y, cell);
                hud_win.main.setCell(dx + 1, y, .{ .fl = .{ .skip = true } });

                if (prop) |prop_index| {
                    const signal = @enumToInt(HudMouseSignalTag.Prop) | prop_index;
                    hud_win.main.addMouseTrigger(Rect.new(Coord.new(dx, y), 0, 0), .Click, .{
                        .Signal = signal,
                    });
                }

                dx += 2;
            }
        },
        .Areas => {
            for (st.fab.prisons.constSlice()) |prect, i| {
                const sel = st.cursor == .PrisonArea and st.cursor.PrisonArea == i;
                const c1: u21 = if (sel) 'c' else '.';
                const c2: u21 = if (sel) '.' else 'g';
                const c3: u21 = if (sel) 'g' else 'G';
                _ = hud_win.main.drawTextAtf(0, y, "$g{: >2}: ${u}prison ${u}(${u}{}${u},${u}{} {}${u}×${u}{}${u})", .{
                    i, c1, c3, c2, prect.start.x, c3, c2, prect.start.y, prect.width, c3, c2, prect.height, c3,
                }, .{});
                if (!sel) {
                    const signal = @enumToInt(HudMouseSignalTag.Area) | i;
                    hud_win.main.addClickableTextBoth(.{ .Signal = signal });
                }

                var x = hud_win.main.width - 1 - 7;
                const buttons = [_]HudMouseSignalTag{
                    .AreaDecH,
                    .AreaIncH,
                    .AreaDecW,
                    .AreaIncW,
                };
                for (&buttons) |button, bi| {
                    if (bi == 1 or bi == 3) {
                        hud_win.main.setCell(x, y, .{ .ch = '/', .fg = colors.GREY });
                        x += 1;
                    } else if (bi == 2) {
                        x += 1;
                    }
                    const ch: u21 = if (bi % 2 == 1) '+' else '-';
                    hud_win.main.setCell(x, y, .{ .ch = ch, .fg = colors.LIGHT_CONCRETE });
                    const signal = @enumToInt(button) | i;
                    hud_win.main.addMouseTrigger(Rect.new(Coord.new(x, y), 0, 0), .Click, .{
                        .Signal = signal,
                    });
                    hud_win.main.addMouseTrigger(Rect.new(Coord.new(x, y), 0, 0), .Hover, .{
                        .RecordElem = &hud_win.main,
                    });
                    x += 1;
                }

                y += 1;
            }

            y += 1;

            var x: usize = 0;
            _ = hud_win.main.drawTextAt(x, y, " Add new ", .{ .xptr = &x });
            const s1 = @enumToInt(HudMouseSignalTag.AreaAddDel) | 0;
            hud_win.main.addClickableTextBoth(.{ .Signal = s1 });
            _ = hud_win.main.drawTextAt(x, y, " $g·$. ", .{ .xptr = &x });
            _ = hud_win.main.drawTextAt(x, y, " Delete selected ", .{});
            const s2 = @enumToInt(HudMouseSignalTag.AreaAddDel) | 1;
            hud_win.main.addClickableTextBoth(.{ .Signal = s2 });
        },
    }

    hud_win.main.highlightMouseArea(colors.BG_L);
}

pub fn drawMap(st: *fabedit.EdState) void {
    var y: usize = 0;
    while (y < map_win.main.height) : (y += 1) {
        var x: usize = 0;
        var dx: usize = 0;
        while (x < map_win.main.width) : ({
            x += 1;
            dx += 2;
        }) {
            if (y >= st.fab.height or x >= st.fab.width) {
                map_win.main.setCell(dx, y, .{ .bg = 0, .fl = .{ .wide = true } });
                map_win.main.setCell(dx + 1, y, .{ .bg = 0, .fl = .{ .skip = true } });
                continue;
            }

            var cell = display.Cell{};

            switch (st.fab.content[y][x]) {
                .Floor, .Wall, .Window, .Any, .Connection, .LockedDoor, .Door => cell = displayAs(st, st.fab.content[y][x]),
                else => {},
            }

            cell.fg = switch (st.fab.content[y][x]) {
                .Feature => |f| switch (st.fab.features[f].?) {
                    .Stair => |s| if (s.locked)
                        0xff4400
                    else
                        @as(u32, switch (s.stairtype) {
                            .Up, .Access => @as(u32, 0xffd700),
                            .Down => 0xeeeeee,
                        }),
                    .CCont, .Poster => 0xffd700,
                    .Prop => |pid| surfaces.props.items[utils.findById(surfaces.props.items, pid).?].fg orelse 0xffffff,
                    .Machine => |mid| surfaces.MACHINES[utils.findById(&surfaces.MACHINES, mid.id).?].unpowered_fg orelse 0xffffff,
                    else => colors.LIGHT_CONCRETE,
                },
                .LevelFeature => colors.LIGHT_STEEL_BLUE,
                .HeavyLockedDoor,
                .Bars,
                .Brazier,
                .ShallowWater,
                .Loot1,
                .RareLoot,
                .Corpse,
                .Ring,
                => 0xffffff,
                .Water => 0x0000ff,
                .Lava => 0xff0000,
                else => cell.fg,
            };

            cell.bg = switch (st.fab.content[y][x]) {
                .Feature => |f| switch (st.fab.features[f].?) {
                    .Machine => |mid| surfaces.MACHINES[utils.findById(&surfaces.MACHINES, mid.id).?].unpowered_bg orelse colors.BG,
                    else => cell.bg,
                },
                else => cell.bg,
            };

            cell.ch = switch (st.fab.content[y][x]) {
                .LevelFeature => |l| '0' + @intCast(u21, l),
                .Feature => |f| switch (st.fab.features[f].?) {
                    .Stair => |s| @as(u21, switch (s.stairtype) {
                        .Up => '<',
                        .Access => '«',
                        .Down => '>',
                    }),
                    .Key => '$',
                    .Item => '@',
                    .Mob => |mt| mt.mob.tile, // TODO: bg
                    .CMob => |mob_info| mob_info.t.mob.tile,
                    .CCont => |container_info| container_info.t.tile,
                    .Cpitem => '%',
                    .Poster => 'P',
                    .Prop => |pid| surfaces.props.items[utils.findById(surfaces.props.items, pid).?].tile,
                    .Machine => |mid| surfaces.MACHINES[utils.findById(&surfaces.MACHINES, mid.id).?].powered_tile,
                },
                .HeavyLockedDoor => '±', // TODO: fg
                .Brazier => '¤',
                .ShallowWater => '~',
                .Bars => '×',
                .Loot1 => 'L',
                .RareLoot => 'R',
                .Corpse => '%', // TODO: fg
                .Ring => '=',
                .Lava, .Water => '≈',
                else => cell.ch,
            };

            cell.fl.wide = true;
            map_win.main.setCell(dx, y, cell);
            map_win.main.setCell(dx + 1, y, .{ .fl = .{ .skip = true } });
        }
    }

    if (st.hud_pane == .Areas) {
        for (st.fab.prisons.constSlice()) |rect| {
            y = rect.start.y;
            while (y < rect.end().y) : (y += 1) {
                var x: usize = rect.start.x;
                while (x < rect.end().x) : (x += 1) {
                    var cell = map_win.main.getCell(x * 2, y);
                    cell.bg = colors.mix(cell.bg, 0xff0000, 0.2);
                    map_win.main.setCell(x * 2, y, cell);
                }
            }
        }
    }
}

pub fn draw(st: *fabedit.EdState) void {
    drawBar(st);
    drawHUD(st);

    if (st.fab_redraw) {
        drawMap(st);
        st.fab_redraw = false;
    }

    map_win.lyr1.clear();
    var mark = map_win.main.getCell(st.x * 2, st.y);
    mark.bg = colors.mix(mark.bg, 0xffffff, 0.2);
    map_win.lyr1.setCell(st.x * 2, st.y, mark);

    container.main.renderFully(0, 0);
    display.present();
}

pub fn deinit() !void {
    try display.deinit();
    container.deinit();
}

pub fn handleMouseEvent(ev: display.Event, st: *fabedit.EdState) bool {
    return map_win.handleMouseEvent(ev, st) or
        hud_win.handleMouseEvent(ev, st) or
        bar_win.handleMouseEvent(ev, st);
}

fn _evToMEvType(ev: display.Event) Console.MouseTrigger.Kind {
    return switch (ev) {
        .Click => .Click,
        .Hover => .Hover,
        .Wheel => .Wheel,
        else => err.wat(),
    };
}
