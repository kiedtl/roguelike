const std = @import("std");
const math = std.math;
const io = std.io;
const sort = std.sort;
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;
const enums = std.enums;

const RexMap = @import("rexpaint").RexMap;

const janet = @import("janet.zig");
const display = @import("display.zig");
const dijkstra = @import("dijkstra.zig");
const colors = @import("colors.zig");
const player = @import("player.zig");
const spells = @import("spells.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const gas = @import("gas.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const termbox = @import("termbox.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");
const rng = @import("rng.zig");
const scores = @import("scores.zig");

// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const StackBuffer = @import("buffer.zig").StackBuffer;
const BStr = utils.BStr;

const Mob = types.Mob;
const StatusDataInfo = types.StatusDataInfo;
const SurfaceItem = types.SurfaceItem;
const Stat = types.Stat;
const Resistance = types.Resistance;
const Coord = types.Coord;
const CoordIsize = types.CoordIsize;
const Rect = types.Rect;
const Direction = types.Direction;
const Tile = types.Tile;
const Status = types.Status;
const Item = types.Item;
const CoordArrayList = types.CoordArrayList;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// -----------------------------------------------------------------------------
pub const labels = @import("ui/labels.zig");
pub const drawLabels = @import("ui/labels.zig").drawLabels;
pub const Console = @import("ui/Console.zig");

pub const FRAMERATE = 1000 / 60;

pub const LEFT_INFO_WIDTH: usize = 35;
//pub const RIGHT_INFO_WIDTH: usize = 24;
pub const LOG_HEIGHT = 7;
pub const ZAP_HEIGHT = 15 + 4;
pub const PLAYER_INFO_MODAL_HEIGHT = 24;
pub const MAP_HEIGHT_R = 15;
pub const MAP_WIDTH_R = 22;

pub const MIN_HEIGHT = (MAP_HEIGHT_R * 2) + LOG_HEIGHT + 2;
pub const MIN_WIDTH = (MAP_WIDTH_R * 4) + LEFT_INFO_WIDTH + 2 + 1;

pub var uirng: std.Random.DefaultPrng = undefined;

pub var log_win: struct {
    main: Console,
    last_message: ?usize = null,

    pub fn init(self: *@This()) void {
        const d = dimensions(.Log);
        self.main = Console.init(state.alloc, d.width(), 0);
        self.last_message = null;
    }

    pub fn stepAnimations(self: *@This()) void {
        const start = self.main.subconsoles.items.len -| LOG_HEIGHT;
        for (self.main.subconsoles.items[start..]) |*subconsole| {
            subconsole.console.stepRevealAnimation();
        }
    }

    pub fn deinit(self: *@This()) void {
        self.main.deinit();
    }

    pub fn render(self: *@This()) void {
        const log_window = dimensions(.Log);
        self.main.renderAreaAt(log_window.startx, log_window.starty, 0, self.main.height -| (log_window.endy - log_window.starty), self.main.width, self.main.height);
    }

    pub fn handleMouseEvent(self: *@This(), ev: display.Event) bool {
        return switch (ev) {
            .Click, .Hover => |c| switch (self.main.handleMouseEvent(c, _evToMEvType(ev))) {
                .Coord, .Signal => err.wat(),
                .Unhandled, .Void => true,
                .Outside => false,
            },
            .Wheel => false,
            else => err.wat(),
        };
    }
} = undefined;

pub var hud_win: struct {
    main: Console,

    pub fn init(self: *@This()) void {
        const d = dimensions(.PlayerInfo);
        self.main = Console.init(state.alloc, d.width(), d.height());
        self.main.addRevealAnimation(.{});
    }

    pub fn handleMouseEvent(self: *@This(), ev: display.Event) bool {
        return switch (ev) {
            .Click, .Hover => |c| switch (self.main.handleMouseEvent(c, _evToMEvType(ev))) {
                .Coord, .Signal => err.wat(),
                .Unhandled, .Void => true,
                .Outside => false,
            },
            .Wheel => false,
            else => err.wat(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.main.deinit();
    }
} = undefined;

pub var map_win: struct {
    map: Console = undefined,
    text_line: Console = undefined,
    text_line_anim_layer: Console = undefined,
    text_line_anim: ?AnimationRevealUnreveal = null,

    // For Examine mode, directional choose, labels, etc.
    annotations: Console = undefined,

    // For border around map, labels, etc.
    grid_annotations: Console = undefined,

    // For particle animations and such.
    animations: Console = undefined,
    cell_animation_grid: []?CellAnimation = undefined, // This is a grid, btw

    pub fn init(self: *@This()) void {
        const d = dimensions(.Main);
        self.map = Console.init(state.alloc, d.width(), d.height());

        self.text_line = Console.init(state.alloc, d.width(), 2);
        self.text_line.default_transparent = true;
        self.text_line.clear();
        self.text_line_anim_layer = Console.init(state.alloc, d.width(), 2);
        self.text_line_anim_layer.default_transparent = true;
        self.text_line_anim_layer.clear();
        self.text_line.addSubconsole(&self.text_line_anim_layer, 0, 0);

        self.annotations = Console.init(state.alloc, d.width(), d.height());
        self.annotations.default_transparent = true;
        self.annotations.clear();

        self.grid_annotations = Console.init(state.alloc, d.width(), d.height());
        self.grid_annotations.default_transparent = true;
        self.grid_annotations.clear();

        self.animations = Console.init(state.alloc, d.width(), d.height());
        self.animations.default_transparent = true;
        self.animations.clear();

        self.cell_animation_grid = state.alloc.alloc(?CellAnimation, d.width() * d.height()) catch err.oom();
        @memset(self.cell_animation_grid, null);

        self.map.addSubconsole(&self.text_line, 0, 0);
        self.map.addSubconsole(&self.grid_annotations, 0, 0);
        self.map.addSubconsole(&self.annotations, 0, 0);
        self.map.addSubconsole(&self.animations, 0, 0);
    }

    pub fn gridAnimAt(self: *@This(), x: usize, y: usize) *?CellAnimation {
        return &self.cell_animation_grid[y * self.grid_annotations.width + x];
    }

    pub fn gridAnimAt2(self: *@This(), x: usize, y: usize) ?*CellAnimation {
        return if (self.cell_animation_grid[y * self.grid_annotations.width + x]) |*anim|
            anim
        else
            null;
    }

    pub fn stepGridAnimations(self: *@This()) void {
        var y: usize = 0;
        while (y < self.grid_annotations.height) : (y += 1) {
            var x: usize = 0;
            while (x < self.grid_annotations.width) : (x += 1) {
                if (map_win.gridAnimAt2(x, y)) |anim| {
                    anim.step();
                    map_win.grid_annotations.setCell(x, y, anim.get());
                }
            }
        }
    }

    // Clear grid_annotations before this.
    pub fn stepBorderAnimations(self: *@This(), refpoint: Coord) void {
        const S = struct {
            var ctr: usize = 0;
        };
        const f = (1 + math.sin(@as(f64, @floatFromInt(S.ctr)) * math.pi / 180.0)) / 4;
        const c = colors.mix(colors.BG, colors.CONCRETE, math.clamp(f, 0.1, 0.7));
        const a = Rect.new(Coord.new(0, 0), WIDTH + 2, HEIGHT + 2);
        const b = Rect.new(Coord.new(1, 1), WIDTH + 0, HEIGHT + 0);
        var y: usize = 0;
        while (y < a.end().y) : (y += 1) {
            var x: usize = 0;
            while (x < a.end().x) : (x += 1) {
                const co = Coord.new(x, y).asRect();
                if (co.intersects(&a, 0) and !co.intersects(&b, 0)) {
                    const zy = @as(isize, @intCast(y)) - (@as(isize, @intCast(refpoint.y)) - MAP_HEIGHT_R) - 1;
                    const zx = @as(isize, @intCast(x)) - (@as(isize, @intCast(refpoint.x)) - MAP_WIDTH_R) - 1;
                    if (zy > 0 and zx > 0 and zx < self.map.width and zy < self.map.height - 1) {
                        self.grid_annotations.setCell(@intCast(zx * 2), @intCast(zy), .{ .bg = c, .fl = .{ .wide = true } });
                    }
                }
            }
        }
        S.ctr = (S.ctr + 1) % 360;
    }

    fn _addTextLineReveal(self: *@This(), duration: usize) void {
        //if (self.text_line_anim) |ptr|
        //state.alloc.destroy(ptr);
        //self.text_line_anim = state.alloc.create(Generator(animationRevealUnreveal)) catch err.oom();
        // self.text_line_anim.?.* = Generator(animationRevealUnreveal).init(.{
        //     .main_layer = &self.text_line,
        //     .anim_layer = &self.text_line_anim_layer,
        //     .opts = .{ .rv_unrv_delay = duration },
        // });
        self.text_line_anim = animationRevealUnreveal(.{
            .main_layer = &self.text_line,
            .anim_layer = &self.text_line_anim_layer,
            .opts = .{ .rv_unrv_delay = duration },
        });
    }

    pub fn drawTextLinef(self: *@This(), comptime fmt: []const u8, args: anytype, opts: DrawStrOpts) void {
        const str = std.fmt.allocPrint(state.alloc, fmt, args) catch err.oom();
        defer state.alloc.free(str);

        var y: usize = 0;
        var fibuf = StackBuffer(u8, 4096).init(null);
        var fold_iter = utils.FoldedTextIterator.init(str, self.text_line.width * 75 / 100);
        while (fold_iter.next(&fibuf)) |line| {
            const x = self.text_line.width / 2 - line.len / 2;
            y += self.text_line.drawTextAt(x, y, line, opts);
        }

        self._addTextLineReveal(80 * @max(1, str.len / 20));
    }

    pub fn stepTextLineAnimations(self: *@This()) void {
        if (self.text_line_anim) |*anim|
            if (anim.next() == null) {
                self.text_line.clear();
                self.text_line_anim_layer.clear();
                //state.alloc.destroy(self.text_line_anim.?);
                self.text_line_anim = null;
            };
    }

    pub fn handleMouseEvent(self: *@This(), ev: display.Event) bool {
        return switch (ev) {
            .Click, .Hover => |c| switch (self.map.handleMouseEvent(c, _evToMEvType(ev))) {
                .Coord, .Signal => err.wat(),
                .Unhandled, .Void => true,
                .Outside => false,
            },
            .Wheel => false,
            else => err.wat(),
        };
    }

    pub fn deinit(self: *@This()) void {
        self.map.deinit();
        state.alloc.free(self.cell_animation_grid);
        // if (self.text_line_anim) |ptr|
        //     state.alloc.destroy(ptr);
    }
} = .{};

fn ModalWindow(comptime left_width: usize, comptime dim: DisplayWindow) type {
    return struct {
        container: Console,
        left: Console,
        right: Console,

        const LEFT_WIDTH = left_width;

        pub fn init(self: *@This()) void {
            const d = dimensions(dim);

            self.container = Console.init(state.alloc, d.width(), d.height());
            self.left = Console.init(state.alloc, LEFT_WIDTH, d.height() - 2);
            self.right = Console.init(state.alloc, d.width() - LEFT_WIDTH - 3, d.height() - 2);

            self.container.addSubconsole(&self.left, 1, 1);
            self.container.addSubconsole(&self.right, LEFT_WIDTH + 2, 1);
        }

        pub fn deinit(self: *@This()) void {
            self.container.deinit();
        }
    };
}

// 28: 15 (length of longest ring name, electification) + 6 (MP cost) + 7 (padding)
pub var zap_win: ModalWindow(28, .Zap) = undefined;
pub var pinfo_win: ModalWindow(15, .PlayerInfoModal) = undefined;
pub var wiz_win: ModalWindow(0, .Zap) = undefined;

pub fn init(scale: f32) !void {
    try display.init(MIN_WIDTH, MIN_HEIGHT, scale);

    uirng = @TypeOf(uirng).init(@intCast(std.time.milliTimestamp()));

    zap_win.init();
    pinfo_win.init();
    wiz_win.init();
    map_win.init();
    hud_win.init();
    log_win.init();
    clearScreen();

    labels.labels = @TypeOf(labels.labels).init(state.alloc);
}

// Check that the window is the minimum size.
//
// Return true if the user resized the window, false if the user press Ctrl+C.
pub fn checkWindowSize() bool {
    if (state.state == .Viewer or display.driver == .SDL2) {
        return true;
    }

    while (true) {
        const cur_w = display.width();
        const cur_h = display.height();

        if (cur_w >= MIN_WIDTH and cur_h >= MIN_HEIGHT) {
            // All's well
            clearScreen();
            return true;
        }

        _ = _drawStr(1, 1, cur_w, "Your terminal is too small.", .{});
        _ = _drawStrf(1, 3, cur_w, "Minimum: {}x{}.", .{ MIN_WIDTH, MIN_HEIGHT }, .{});
        _ = _drawStrf(1, 4, cur_w, "Current size: {}x{}.", .{ cur_w, cur_h }, .{});

        display.present();

        var evgen = display.getEvents(null);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return false;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc => return false,
                else => {},
            },
            .Char => |c| switch (c) {
                'q' => return false,
                else => {},
            },
            else => {},
        };
    }
}

pub fn deinit() !void {
    try display.deinit();
    zap_win.deinit();
    pinfo_win.deinit();
    map_win.deinit();
    hud_win.deinit();
    log_win.deinit();
    wiz_win.deinit();
    for (labels.labels.items) |label|
        label.deinit();
    labels.labels.deinit();
}

pub const DisplayWindow = enum { Whole, PlayerInfo, Main, Log, Zap, PlayerInfoModal };
pub const Dimension = struct {
    startx: usize,
    endx: usize,
    starty: usize,
    endy: usize,

    pub fn width(self: @This()) usize {
        return self.endx - self.startx;
    }

    pub fn height(self: @This()) usize {
        return self.endy - self.starty;
    }

    pub fn asRect(self: @This()) Rect {
        return Rect.new(Coord.new(self.startx, self.starty), self.width(), self.height());
    }
};

pub fn dimensions(w: DisplayWindow) Dimension {
    const height = display.height();
    //const width = display.width();

    const playerinfo_width = LEFT_INFO_WIDTH;
    //const playerinfo_width = width - WIDTH - 2;
    //const enemyinfo_width = RIGHT_INFO_WIDTH;

    const main_start = 1;
    const main_width = MAP_WIDTH_R * 4;
    const main_height = MAP_HEIGHT_R * 2;
    const playerinfo_start = main_start + main_width + 1;
    const log_start = main_start;
    const zap_start = height / 2 - (ZAP_HEIGHT / 2);
    const pinfo_modal_start = height / 2 - (PLAYER_INFO_MODAL_HEIGHT / 2);

    return switch (w) {
        .Whole => .{
            .startx = 1,
            .endx = playerinfo_start + playerinfo_width,
            .starty = 1,
            .endy = height - 1,
        },
        .PlayerInfo => .{
            .startx = playerinfo_start,
            .endx = playerinfo_start + playerinfo_width,
            .starty = 1,
            .endy = height - 1,
            //.width = playerinfo_width,
            //.height = height - 1,
        },
        .Main => .{
            .startx = main_start,
            .endx = main_start + main_width,
            .starty = 1,
            .endy = main_height + 2,
            //.width = main_width,
            //.height = main_height,
        },
        .Log => .{
            .startx = log_start,
            .endx = log_start + main_width,
            .starty = 2 + main_height,
            .endy = height - 1,
            //.width = main_width,
            //.height = @max(LOG_HEIGHT, height - (2 + main_height) - 1),
        },
        .Zap => .{
            .startx = 0,
            .endx = playerinfo_start + playerinfo_width + 1,
            .starty = zap_start,
            .endy = zap_start + ZAP_HEIGHT,
        },
        .PlayerInfoModal => .{
            .startx = 0,
            .endx = playerinfo_start + playerinfo_width + 1,
            .starty = pinfo_modal_start,
            .endy = pinfo_modal_start + PLAYER_INFO_MODAL_HEIGHT,
        },
    };
}

// Formatting descriptions for stuff. {{{

// XXX: Uses a static internal buffer. Buffer must be consumed before next call,
// not thread safe, etc.
//
// FIXME: convert this to a formatting struct
fn _formatBool(val: bool) []const u8 {
    // 4 control chars, max 3 for actual "yes" or "no"
    var buf: [3 + 4]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();

    const color: u21 = if (val) 'b' else 'r';
    const string = if (val) @as([]const u8, "yes") else "no";
    w.print("${u}{s}$.", .{ color, string }) catch err.wat();

    return fbs.getWritten();
}

// XXX: Uses a static internal buffer. Buffer must be consumed before next call,
// not thread safe, etc.
//
// FIXME: convert this to a formatting struct
//
fn _formatEffectNumber(val: spells.Effect.EffectNumber, spellcfg: spells.SpellOptions) []const u8 {
    var buf: [24]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    var w = fbs.writer();

    switch (val) {
        .Power => w.print("$b{}$.", .{spellcfg.power}) catch err.wat(),
        .PowerRangeHalf => w.print("$b{}$.-$b{}$.", .{ spellcfg.power / 2, spellcfg.power }) catch err.wat(),
        .Fixed => |n| w.print("$b{}$.", .{n}) catch err.wat(),
    }

    return fbs.getWritten();
}

// XXX: Uses a static internal buffer. Buffer must be consumed before next call,
// not thread safe, etc.
//
// FIXME: convert this to a formatting struct
//
fn _formatStatusInfo(statusinfo: *const StatusDataInfo) []const u8 {
    const S = struct {
        var buf: [65535]u8 = undefined;
    };

    var fbs = std.io.fixedBufferStream(&S.buf);
    var w = fbs.writer();

    const sname = statusinfo.status.string(state.player);
    switch (statusinfo.duration) {
        .Prm => w.print("$bPrm$. {s}", .{sname}) catch err.wat(),
        .Equ => w.print("$bEqu$. {s}", .{sname}) catch err.wat(),
        .Tmp => w.print("$bTmp$. {s} $g({})$.", .{ sname, statusinfo.duration.Tmp }) catch err.wat(),
        .Ctx => w.print("$bCtx$. {s}", .{sname}) catch err.wat(),
    }

    return fbs.getWritten();
}

fn _writerTwice(
    self: *Console,
    starty: usize,
    linewidth: usize,
    string: []const u8,
    comptime fmt2: []const u8,
    args2: anytype,
) usize {
    _ = self.drawTextAtf(0, starty, "$c{s}$.", .{string}, .{});

    const col = linewidth - utils.countFmt(fmt2, args2);
    _ = self.drawTextAtf(col, starty, fmt2, args2, .{});
    return 1;
}

fn _writerWrite(writer: io.FixedBufferStream([]u8).Writer, comptime fmt: []const u8, args: anytype) void {
    writer.print(fmt, args) catch err.wat();
}

fn _writerHeader(self: *Console, y: usize, linewidth: usize, comptime fmt: []const u8, args: anytype) usize {
    _ = self.drawTextAtf(0, y, "$c" ++ fmt ++ "$.", args, .{});

    const fmt_width = utils.countFmt(fmt, args);
    var i: usize = linewidth - fmt_width - 1;
    while (i > 0) : (i -= 1)
        _ = self.drawTextAt(fmt_width + i, y, "$G─", .{});

    return 1;
}

fn _writerHLine(self: *Console, y: usize, linewidth: usize) usize {
    var i: usize = 0;
    while (i < linewidth) : (i += 1)
        _ = self.drawTextAt(i, y, "─", .{});
    return 1;
}

fn _writerMonsHostility(self: *Console, y: usize, mob: *Mob) usize {
    if (mob.isHostileTo(state.player)) {
        if (mob.ai.is_combative) {
            return self.drawTextAt(0, y, "$rhostile$.", .{});
        } else {
            return self.drawTextAt(0, y, "$gnon-combatant$.", .{});
        }
    } else {
        return self.drawTextAt(0, y, "$bneutral$.", .{});
    }
}

fn _writerMobStats(self: *Console, starty: usize, mob: *Mob) usize {
    var y = starty;

    for (types.STAT_LIST) |stat| {
        const stat_val_raw = mob.stat(stat);
        const stat_val = utils.SignedFormatter{ .v = stat_val_raw };

        if (!stat.showMobStat(mob, stat_val_raw))
            continue;

        const stat_val_real: isize = switch (stat) {
            .Melee => @intCast(combat.chanceOfMeleeLanding(mob, null)),
            .Evade => @intCast(combat.chanceOfAttackEvaded(mob, null)),
            .Missile => @intCast(combat.chanceOfMissileLanding(mob)),
            else => stat_val_raw,
        };

        // Special cases
        switch (stat) {
            .Melee, .Evade, .Missile => {
                if (@as(usize, @intCast(math.clamp(stat_val_raw, 0, 100))) != stat_val_real) {
                    const c = if (@as(usize, @intCast(stat_val_real)) < stat_val_raw) @as(u21, 'r') else 'b';
                    y += self.drawTextAtf(0, y, "$c{s: <9}$. {: >5}{s: >1}  $g(${u}{}{s}$g)$.", .{ stat.string(), stat_val, stat.formatAfter(), c, stat_val_real, stat.formatAfter() }, .{});
                    continue;
                }
            },
            .Willpower => if (stat_val_raw == mobs.WILL_IMMUNE) {
                y += self.drawTextAtf(0, y, "$c{s: <9}$. {u: >5}{s: >1}", .{ stat.string(), '∞', stat.formatAfter() }, .{});
                continue;
            },
            else => {},
        }

        // Regular case
        y += self.drawTextAtf(0, y, "$c{s: <9}$. {: >5}{s: >1}", .{ stat.string(), stat_val, stat.formatAfter() }, .{});
    }
    y += self.drawTextAt(0, y, "\n", .{});

    inline for (@typeInfo(Resistance).@"enum".fields) |resistancev| {
        const resist: Resistance = @enumFromInt(resistancev.value);
        const resist_val = utils.SignedFormatter{ .v = mob.resistance(resist) };
        const resist_str = resist.string();
        if (resist_val.v != 0)
            y += self.drawTextAtf(0, y, "$c{s: <9}$. {: >5}%\n", .{ resist_str, resist_val }, .{});
    }
    y += self.drawTextAt(0, y, "\n", .{});
    return y - starty;
}

fn _writerSobStats(
    self: *Console,
    starty: usize,
    linewidth: usize,
    p_stats: ?enums.EnumFieldStruct(Stat, isize, 0),
    p_resists: ?enums.EnumFieldStruct(Resistance, isize, 0),
) usize {
    var y = starty;

    if (p_stats) |stats| {
        inline for (@typeInfo(Stat).@"enum".fields) |statv| {
            const stat: Stat = @enumFromInt(statv.value);

            const x_stat_val = utils.getFieldByEnum(Stat, stats, stat);
            // var base_stat_val = @intCast(isize, switch (stat) {
            //     .Missile => combat.chanceOfMissileLanding(state.player),
            //     .Melee => combat.chanceOfMeleeLanding(state.player, null),
            //     .Evade => combat.chanceOfAttackEvaded(state.player, null),
            //     else => state.player.stat(stat),
            // });
            // if (state.dungeon.terrainAt(state.player.coord) == terrain) {
            //     base_stat_val -= terrain_stat_val;
            // }
            // const new_stat_val = base_stat_val + terrain_stat_val;

            if (x_stat_val != 0) {
                // // TODO: use $r for negative '->' values, I tried to do this with
                // // Zig v9.1 but ran into a compiler bug where the `color` variable
                // // was replaced with random garbage.
                // y += self.drawTextAtf(x, y, "{s: <8} $a{: >5}$. $b{: >5}$. $a{: >5}$.\n", .{
                //     stat.string(), base_stat_val, terrain_stat_val, new_stat_val,
                // }, .{});
                const fmt_val = utils.SignedFormatter{ .v = x_stat_val };
                // y += self.drawTextAtf(x, y, "{s: <8} $a{: >5}$.\n", .{ stat.string(), fmt_val }, .{});
                y += _writerTwice(self, y, linewidth, stat.string(), "{}", .{fmt_val});
            }
        }
    }
    if (p_resists) |resists| {
        inline for (@typeInfo(Resistance).@"enum".fields) |resistancev| {
            const resist: Resistance = @enumFromInt(resistancev.value);

            const x_resist_val = utils.getFieldByEnum(Resistance, resists, resist);
            // var base_resist_val = @intCast(isize, state.player.resistance(resist));
            // if (state.dungeon.terrainAt(state.player.coord) == terrain) {
            //     base_resist_val -= terrain_resist_val;
            // }
            // const new_resist_val = base_resist_val + terrain_resist_val;

            if (x_resist_val != 0) {
                // // TODO: use $r for negative '->' values, I tried to do this with
                // // Zig v9.1 but ran into a compiler bug where the `color` variable
                // // was replaced with random garbage.
                // _writerWrite(w, "{s: <8} $a{: >5}$. $b{: >5}$. $a{: >5}$.\n", .{
                //     resist.string(), base_resist_val, terrain_resist_val, new_resist_val,
                // });
                const fmt_val = utils.SignedFormatter{ .v = x_resist_val };
                // _writerWrite(w, "{s: <8} $a{: >5}$.\n", .{ resist.string(), fmt_val });
                y += _writerTwice(self, y, linewidth, resist.string(), "{}", .{fmt_val});
            }
        }
    }

    y += self.drawTextAt(0, y, "\n", .{});

    return y - starty;
}

fn _getTerrDescription(self: *Console, starty: usize, terrain: *const surfaces.Terrain, linewidth: usize) usize {
    var y = starty;

    y += self.drawTextAtf(0, y, "$c{s}$.", .{terrain.name}, .{});
    y += self.drawTextAt(0, y, "terrain", .{});
    y += self.drawTextAt(0, y, "\n", .{});

    y += _writerHeader(self, y, linewidth, "stats", .{});
    y += _writerSobStats(self, y, linewidth, terrain.stats, terrain.resists);
    y += self.drawTextAt(0, y, "\n", .{});

    if (terrain.effects.len > 0) {
        y += _writerHeader(self, y, linewidth, "effects", .{});
        for (terrain.effects) |effect| {
            y += self.drawTextAtf(0, y, "{s}", .{_formatStatusInfo(&effect)}, .{});
        }
        y += 1;
    }

    y += _writerHeader(self, y, linewidth, "info", .{});

    if (terrain.fire_retardant) {
        y += self.drawTextAt(0, y, "$c·$. It will put out fires.\n", .{});
    } else if (terrain.flammability > 0) {
        y += self.drawTextAt(0, y, "$c·$. It is flammable.\n", .{});
    }

    if (terrain.trample_cloud) |gas_opts| {
        y += self.drawTextAtf(0, y, "$c·$. Trample: $b{s}$. (1$g/$.{} chance)\n", .{
            gas.Gases[gas_opts.id].name, gas_opts.chance,
        }, .{});
    }

    if (terrain.trample_into) |terr| {
        y += self.drawTextAtf(0, y, "$c·$. Trample: $b{s}$.\n", .{terr.name}, .{});
    }

    if (terrain.gas) |gas_opts| {
        y += self.drawTextAtf(0, y, "$c·$. Creates $b{s}$. (1$g/$.{} chance)\n", .{
            gas.Gases[gas_opts.id].name, gas_opts.chance,
        }, .{});
    }

    return y - starty;
}

fn _getSurfDescription(self: *Console, starty: usize, surface: SurfaceItem, linewidth: usize) usize {
    var y = starty;

    switch (surface) {
        .Machine => |m| {
            y += self.drawTextAtf(0, y, "$c{s}$.", .{m.name}, .{});
            y += self.drawTextAt(0, y, "feature", .{});
            y += self.drawTextAt(0, y, "\n", .{});

            if (m.player_interact) |interaction| {
                const remaining = interaction.max_use - interaction.used;
                const plural: []const u8 = if (remaining == 1) "" else "s";
                y += self.drawTextAtf(0, y, "$cInteraction:$. {s}.\n\n", .{interaction.name}, .{});
                y += self.drawTextAtf(0, y, "You used this machine $b{}$. times.", .{interaction.used}, .{});
                y += self.drawTextAtf(0, y, "It can be used $b{}$. more time{s}.", .{ remaining, plural }, .{});
                y += self.drawTextAt(0, y, "\n", .{});
            }

            y += self.drawTextAt(0, y, "\n", .{});
        },
        .Prop => |p| y += self.drawTextAtf(0, y, "$c{s}$.\nobject\n\n$gNothing to see here.$.", .{p.name}, .{}),
        .Container => |c| {
            y += self.drawTextAtf(0, y, "$cA {s}$.\ncontainer\n\n", .{c.name}, .{});
            if (c.items.len == 0) {
                y += self.drawTextAt(0, y, "It appears to be empty...", .{});
            } else if (!c.isLootable()) {
                y += self.drawTextAt(0, y, "You don't expect to find anything useful inside.", .{});
            } else {
                y += self.drawTextAt(0, y, "Who knows what lies within?\n", .{});
                y += self.drawTextAt(0, y, "$gBump into it to search for loot.", .{});
            }
        },
        .Poster => |p| {
            y += self.drawTextAt(0, y, "$cPoster$.\n", .{});
            y += self.drawTextAt(0, y, "Some writing on a board:", .{});
            y += _writerHLine(self, y, linewidth);
            y += self.drawTextAtf(0, y, "$g{s}$.", .{p.text}, .{});
            y += _writerHLine(self, y, linewidth);
        },
        .Stair => |s| {
            if (s.stairtype == .Down) {
                y += self.drawTextAt(0, y, "$cDownward Stairs$.\n", .{});
            } else if (s.stairtype == .Access) {
                y += self.drawTextAt(0, y, "$cUpward Stairs$.\n\nStairs to outside.", .{});

                y += self.drawTextAt(0, y, "\nIt seems your journey is over.", .{});
            } else {
                y += self.drawTextAtf(0, y, "$cUpward Stairs$.\n\nStairs to {s}.", .{state.levelinfo[s.stairtype.Up].name}, .{});

                if (state.levelinfo[s.stairtype.Up].optional) {
                    y += self.drawTextAt(0, y, "\nThese stairs are $coptional$. and lead to more difficult floors.", .{});
                }
            }

            if (s.locked) {
                assert(s.stairtype != .Down);
                y += self.drawTextAt(0, y, "\n$bA key is needed to unlock these stairs.$.", .{});
            }
        },
        .Corpse => |c| {
            // Since the mob object was deinit'd, we can't rely on
            // mob.displayName() working
            const name = c.ai.profession_name orelse c.species.name;
            y += self.drawTextAtf(0, y, "$c{s} remains$.", .{name}, .{});
            y += self.drawTextAt(0, y, "corpse\n", .{});
        },
    }

    return y - starty;
}

const MobInfoLine = struct {
    char: u21,
    color: u21,
    string: std.ArrayList(u8),

    pub const ArrayList = std.ArrayList(@This());

    pub fn new(ch: u21, alloc: mem.Allocator) @This() {
        return .{ .char = ch, .color = '.', .string = std.ArrayList(u8).init(alloc) };
    }

    pub fn newColored(ch: u21, color: u21, alloc: mem.Allocator) @This() {
        return .{ .char = ch, .color = color, .string = std.ArrayList(u8).init(alloc) };
    }

    pub fn deinitList(list: ArrayList) void {
        for (list.items) |item| item.string.deinit();
        list.deinit();
    }
};

fn _getMonsInfoSet(mob: *Mob, alloc: mem.Allocator) MobInfoLine.ArrayList {
    var list = MobInfoLine.ArrayList.init(alloc);

    {
        var i = MobInfoLine.new('*', alloc);
        i.color = if (mob.HP <= (mob.max_HP / 5)) @as(u21, 'r') else '.';
        i.string.writer().print("{}/{} HP, {} MP", .{ mob.HP, mob.max_HP, mob.MP }) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.prisoner_status) |ps| {
        var i = MobInfoLine.new('p', alloc);
        const str = if (ps.held_by) |_| "chained" else "prisoner";
        i.string.writer().print("{s}", .{str}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.resistance(.rFume) == 100) {
        var i = MobInfoLine.new('u', alloc);
        i.string.writer().print("unbreathing $g(100% rFume)$.", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.immobile) {
        var i = MobInfoLine.new('i', alloc);
        i.string.writer().print("immobile", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.isMobMartial()) {
        var i = MobInfoLine.newColored('M', 'r', alloc);
        i.string.writer().print("uses martial attacks <$b+{}$.>", .{mob.stat(.Martial)}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.isUnderStatus(.CopperWeapon) != null and mob.hasWeaponOfEgo(.Copper)) {
        var i = MobInfoLine.newColored('C', 'r', alloc);
        i.string.writer().print("has copper weapon", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    const mobspeed = mob.stat(.Speed);
    const youspeed = state.player.stat(.Speed);
    if (mobspeed != youspeed) {
        var i = MobInfoLine.new(if (mobspeed < youspeed) @as(u21, 'f') else 's', alloc);
        i.color = if (mobspeed < youspeed) @as(u21, 'p') else 'b';
        const str = if (mobspeed < youspeed) "faster than you" else "slower than you";
        i.string.writer().print("{s}", .{str}) catch err.wat();
        list.append(i) catch err.wat();
    }

    if (mob.ai.phase == .Investigate) {
        assert(mob.sustiles.items.len > 0);

        var i = MobInfoLine.new('?', alloc);
        var you_str: []const u8 = "";
        {
            const cur_sustile = mob.sustiles.items[mob.sustiles.items.len - 1].coord;
            if (state.dungeon.soundAt(cur_sustile).mob_source) |soundsource| {
                if (soundsource == state.player) {
                    you_str = "your noise";
                }
            }
        }
        i.string.writer().print("investigating {s}", .{you_str}) catch err.wat();

        list.append(i) catch err.wat();
    } else if (mob.ai.phase == .Flee) {
        var i = MobInfoLine.new('!', alloc);
        i.string.writer().print("fleeing", .{}) catch err.wat();
        list.append(i) catch err.wat();
    }

    {
        var i = MobInfoLine.new('@', alloc);

        if (mob.isHostileTo(state.player) and mob.ai.is_combative) {
            const Awareness = union(enum) { Seeing, Remember: usize, None };
            const awareness: Awareness = for (mob.enemyList().items) |enemyrec| {
                if (enemyrec.mob == state.player) {
                    // Zig, why the fuck do I need to cast the below as
                    // Awareness? Wouldn't I like to chop your type checker
                    // into tiny shreds with a +9 halberd of flaming.
                    //
                    // 2023-08-28: no idea why I was this angry, I do this all
                    // the time now without having an aneurysm. caffeine famine
                    // maybe?

                    break if (enemyrec.last_seen != null and enemyrec.last_seen.?.eq(state.player.coord) and mob.canSeeMob(state.player))
                        @as(Awareness, .Seeing)
                    else
                        Awareness{ .Remember = enemyrec.counter };
                }
            } else .None;

            switch (awareness) {
                .Seeing => {
                    i.color = 'r';
                    i.string.writer().print("sees you", .{}) catch err.wat();
                },
                .Remember => |turns_left| {
                    i.color = 'p';
                    if (mob.life_type == .Undead and state.player.hasStatus(.Corruption)) {
                        i.string.writer().print("remembers you ($ocorruption$.)", .{}) catch err.wat();
                    } else {
                        i.string.writer().print("remembers you (~$b{}$. turns left)", .{turns_left}) catch err.wat();
                    }
                },
                .None => {
                    i.color = 'b';
                    i.string.writer().print("unaware of you", .{}) catch err.wat();
                },
            }
        } else {
            i.string.writer().print("doesn't care", .{}) catch err.wat();
        }

        list.append(i) catch err.wat();
    }

    if (mob.isUnderStatus(.Sleeping) != null) {
        var i = MobInfoLine.new('Z', alloc);
        i.string.writer().print("{s}", .{Status.string(.Sleeping, mob)}) catch err.wat();
        list.append(i) catch err.wat();
    }

    return list;
}

fn _getMonsStatsDescription(self: *Console, starty: usize, mob: *Mob, _: usize) usize {
    var y = starty;

    y += self.drawTextAtf(0, y, "$c{s}$.", .{mob.displayName()}, .{});
    y += _writerMonsHostility(self, y, mob);
    y += self.drawTextAt(0, y, "\n", .{});

    y += _writerMobStats(self, y, mob);

    return y - starty;
}

fn _getMonsSpellsDescription(self: *Console, starty: usize, mob: *Mob, _: usize) usize {
    var y = starty;

    y += self.drawTextAtf(0, y, "$c{s}$.", .{mob.displayName()}, .{});
    y += _writerMonsHostility(self, y, mob);
    y += self.drawTextAt(0, y, "\n", .{});

    if (mob.spells.len > 0) {
        y += self.drawTextAt(0, y, "$g(Click spell for info.)$.", .{});
    }

    const has_willchecked_spell = for (mob.spells) |spellcfg| {
        if (spellcfg.spell.checks_will) break true;
    } else false;
    if (has_willchecked_spell) {
        const chance = spells.checkAvgWillChances(mob, state.player);
        const colorset = [_]u21{ 'g', 'b', 'b', 'p', 'p', 'r', 'r', 'r', 'r', 'r' };
        y += self.drawTextAtf(0, y, "$cChance to overpower your will$.: ${u}{}%$.", .{
            colorset[chance / 10], chance,
        }, .{});
        y += self.drawTextAt(0, y, "\n", .{});
    }

    for (mob.spells) |spellcfg| {
        y += self.drawTextAtf(0, y, "$c{s}$. $g($b{}$. $gmp)$. $g[{s}]$.", .{
            spellcfg.spell.name, spellcfg.MP_cost, spellcfg.spell.noise.string(),
        }, .{});
        self.addTooltipForText("{s}", .{spellcfg.spell.name}, "{s}", .{spellcfg.spell.id});

        if (spellcfg.spell.cast_type == .Smite) {
            const target = @as([]const u8, switch (spellcfg.spell.smite_target_type) {
                .Self => "$bself$.",
                .SpecificAlly => |id| b: {
                    const t = mobs.findMobById(id).?;
                    break :b t.mob.ai.profession_name orelse t.mob.species.name;
                },
                .UndeadAlly => "undead ally",
                .ConstructAlly => "construct ally",
                .Mob => "you",
                .Corpse => "corpse",
            });
            y += self.drawTextAtf(0, y, "· $ctarget$.: {s}", .{target}, .{});
        } else if (spellcfg.spell.cast_type == .Bolt) {
            const dodgeable: []const u8 = if (spellcfg.spell.bolt_dodgeable) "$bdodgeable$." else "$rundodgeable$.";
            const missable: []const u8 = if (spellcfg.spell.bolt_missable) "$bmissable$." else "$runmissable$.";
            y += self.drawTextAtf(0, y, "· {s}$g,$. {s}", .{ dodgeable, missable }, .{});
            self.addTooltipForText("Dodgeability and Missability", .{}, "ex_sp_dodgeable_missable", .{});
        }

        if (!(spellcfg.spell.cast_type == .Smite and
            spellcfg.spell.smite_target_type == .Self))
        {
            const targeting = @as([]const u8, switch (spellcfg.spell.cast_type) {
                .Ray => @panic("TODO"),
                .Smite => "smite-targeted",
                .Bolt => "bolt",
            });
            if (spellcfg.spell.bolt_aoe > 1) {
                y += self.drawTextAtf(0, y, "· $ctype$.: {s} $g($.aoe: $b{}$g)$.", .{ targeting, spellcfg.spell.bolt_aoe }, .{});
            } else {
                y += self.drawTextAtf(0, y, "· $ctype$.: {s}", .{targeting}, .{});
            }
        }

        if (spellcfg.spell.cast_type != .Smite or spellcfg.spell.smite_target_type == .Mob) {
            if (spellcfg.spell.checks_will) {
                y += self.drawTextAt(0, y, "· $bwill-checked$.", .{});
                self.addTooltipForText("Will-checking", .{}, "ex_sp_will", .{});

                // Disabled to save space. I'd prefer being explicit though
                //y += self.drawTextAt(0, y, "· $cwill-checked$.: $byes$.", .{});
                // } else {
                //     y += self.drawTextAt(0, y, "· $cwill-checked$.: $rno$.", .{});
            }
        }

        for (spellcfg.spell.effects) |effect| switch (effect) {
            .Status => |s| {
                y += self.drawTextAtf(0, y, "· $gTmp$. {s} ({})", .{
                    s.string(state.player), spellcfg.duration,
                }, .{});
                self.addTooltipForText("{s}", .{s.string(state.player)}, "nonplayer_{s}", .{@tagName(s)});
            },
            .Heal => {
                y += self.drawTextAtf(0, y, "· $gIns$. Heal <{}>", .{spellcfg.power}, .{});
                self.addTooltipForText("Heal", .{}, "ex_sp_effect_heal", .{});
            },
            .Damage => |d| {
                const dmg_str = BStr(32).init(_formatEffectNumber(d.amount, spellcfg));
                y += self.drawTextAtf(0, y, "· $gIns$. {s} <{s}>", .{ d.kind.string(), dmg_str.constSlice() }, .{});
            },
            .FireBlast => |b| {
                const rad_str = BStr(32).init(_formatEffectNumber(b.radius, spellcfg));
                const dmg_str = BStr(32).init(_formatEffectNumber(b.damage, spellcfg));
                y += self.drawTextAtf(0, y, "· $gIns$. fireblast <rad {s}> <dmg {s}>", .{ rad_str.constSlice(), dmg_str.constSlice() }, .{});
                self.addTooltipForText("Fireblast", .{}, "ex_sp_effect_fireblast", .{});
            },
            .Custom => y += self.drawTextAt(0, y, "· $g(See description)$.", .{}),
        };

        y += self.drawTextAt(0, y, "\n", .{});
    }

    const weapons = mob.listOfWeapons();
    for (weapons.constSlice()) |weapon| {
        y += self.drawTextAtf(0, y, "$c{s}$. $g(melee)$.", .{weapon.name}, .{});
        y += self.drawTextAtf(0, y, "· $cdamage$.: {} $g<{s}>$.", .{
            weapon.damage, weapon.damage_kind.stringLong(),
        }, .{});
        if (weapon.ego != .None) {
            const name = weapon.ego.name().?;
            y += self.drawTextAtf(0, y, "· $cego$.: {s}", .{name}, .{});
            self.addTooltipForText("{s} ego", .{name}, "{s}", .{weapon.ego.id().?});
        }
        if (weapon.martial != false)
            y += self.drawTextAt(0, y, "· $cmartial$.: yes", .{});
        if (weapon.delay != 100)
            y += self.drawTextAtf(0, y, "· $cdelay$.: {}%", .{weapon.delay}, .{});
        if (weapon.knockback != 0)
            y += self.drawTextAtf(0, y, "· $cknockback$.: {}", .{weapon.knockback}, .{});
        assert(weapon.reach == 1);
        y += self.drawTextAt(0, y, "\n", .{});
    }

    return y - starty;
}

fn _getMonsDescription(self: *Console, starty: usize, mob: *Mob, linewidth: usize, alloc: mem.Allocator) usize {
    var y = starty;

    if (mob == state.player) {
        y += self.drawTextAt(0, y, "$cYou.$.", .{});
        y += self.drawTextAt(0, y, "\n", .{});
        y += self.drawTextAt(0, y, "Press $b@$. to see your stats, abilities, and more.", .{});

        return y - starty;
    }

    y += self.drawTextAtf(0, y, "$c{s}$.", .{mob.displayName()}, .{});
    y += _writerMonsHostility(self, y, mob);
    y += self.drawTextAt(0, y, "\n", .{});

    if (mob.name_given != null or mob.name_family != null) {
        const g = mob.name_given orelse "";
        const f = mob.name_family orelse "";
        const s = if (mob.name_given != null and mob.name_family != null) " " else "";
        y += self.drawTextAtf(0, y, "$a\"{s}{s}{s}\"", .{ f, s, g }, .{});
        y += self.drawTextAt(0, y, "\n", .{});
    }

    const infoset = _getMonsInfoSet(mob, alloc);
    defer MobInfoLine.deinitList(infoset);
    for (infoset.items) |info| {
        y += self.drawTextAtf(0, y, "${u}{u}$. {s}", .{ info.color, info.char, info.string.items }, .{});
    }

    y += self.drawTextAt(0, y, "\n", .{});

    const you_melee = combat.chanceOfMeleeLanding(state.player, mob);
    const you_evade = combat.chanceOfAttackEvaded(state.player, null);
    const mob_melee = combat.chanceOfMeleeLanding(mob, state.player);
    const mob_evade = combat.chanceOfAttackEvaded(mob, null);

    const c_melee_you = mob_melee * (100 - you_evade) / 100;
    const c_evade_you = 100 - (you_melee * (100 - mob_evade) / 100);

    const m_colorsets = [_]u21{ 'g', 'g', 'g', 'g', 'b', 'b', 'b', 'b', 'r', 'r', 'r' };
    const e_colorsets = [_]u21{ 'g', 'b', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r', 'r' };
    const c_melee_you_color = m_colorsets[c_melee_you / 10];
    const c_evade_you_color = e_colorsets[c_evade_you / 10];

    y += self.drawTextAtf(0, y, "${u}{}%$. to hit you, ${u}{}%$. to evade.", .{
        c_melee_you_color, c_melee_you, c_evade_you_color, c_evade_you,
    }, .{});
    y += self.drawTextAtf(0, y, "Hits for ~$r{}$. damage.", .{mob.totalMeleeOutput(state.player)}, .{});

    var statuses = mob.statuses.iterator();
    while (statuses.next()) |entry| {
        if (mob.isUnderStatus(entry.key) == null)
            continue;
        y += self.drawTextAtf(0, y, "{s}", .{_formatStatusInfo(entry.value)}, .{});
    }
    y += self.drawTextAtf(0, y, "\n", .{}, .{});

    y += _writerHeader(self, y, linewidth, "info", .{});
    if (mob.life_type == .Construct) {
        y += self.drawTextAt(0, y, "· is non-living ($bconstruct$.)", .{});
        self.addTooltipForText("Construct", .{}, "ex_mob_nonliving_construct", .{});
    } else if (mob.life_type == .Undead) {
        y += self.drawTextAt(0, y, "· is non-living ($bundead$.)", .{});
        self.addTooltipForText("Undead", .{}, "ex_mob_nonliving_undead", .{});
    } else if (mob.life_type == .Spectral) {
        y += self.drawTextAt(0, y, "· is non-living ($bspectral$.)", .{});
        self.addTooltipForText("Spectral", .{}, "ex_mob_nonliving_spectral", .{});
    }
    if (mob.max_drainable_MP > 0) {
        y += self.drawTextAtf(0, y, "· is a $oWielder$. ($o{}$. drainable MP)", .{mob.max_drainable_MP}, .{});
        self.addTooltipForText("Wielder", .{}, "ex_mob_wielder", .{});
    }
    if (!combat.canMobBeSurprised(mob)) {
        y += self.drawTextAt(0, y, "· can't be $bsurprised$.", .{});
        self.addTooltipForText("Unsurprisable", .{}, "ex_mob_unsurprised", .{});
    }
    if (mob.ai.is_fearless)
        y += self.drawTextAt(0, y, "· is $pfearless$.", .{});
    if (mob.max_drainable_MP > 0 and mob.is_drained)
        y += self.drawTextAt(0, y, "· is $odrained$.", .{});
    if (mob.ai.flag(.Coward)) {
        y += self.drawTextAt(0, y, "· is cowardly", .{});
        self.addTooltipForText("Coward", .{}, "ex_mob_coward", .{});
    }
    if (mob.ai.is_curious and !mob.deaf)
        y += self.drawTextAt(0, y, "· investigates noises", .{})
    else if (mob.deaf)
        y += self.drawTextAt(0, y, "· is deaf", .{})
    else
        y += self.drawTextAt(0, y, "· won't check noises outside FOV", .{});
    if (mob.ai.flag(.SocialFighter) or mob.ai.flag(.SocialFighter2))
        y += self.drawTextAt(0, y, "· won't attack alone", .{});
    if (mob.ai.flag(.MovesDiagonally))
        y += self.drawTextAt(0, y, "· (usually) moves diagonally", .{});
    if (mob.ai.flag(.DetectWithHeat))
        y += self.drawTextAt(0, y, "· detected w/ $bDetect Heat$.", .{});
    if (mob.ai.flag(.DetectWithElec))
        y += self.drawTextAt(0, y, "· detected w/ $bDetect Electricity$.", .{});
    y += self.drawTextAt(0, y, "\n", .{});

    if (mob.ai.flee_effect) |effect| {
        y += _writerHeader(self, y, linewidth, "flee behaviour", .{});
        y += self.drawTextAtf(0, y, "· {s}", .{_formatStatusInfo(&effect)}, .{});
        y += self.drawTextAt(0, y, "\n", .{});
    }

    return y - starty;
}

fn _getItemDescription(self: *Console, starty: usize, item: Item, linewidth: usize) usize {
    var y = starty;

    const shortname = (item.shortName() catch err.wat()).constSlice();

    y += self.drawTextAtf(0, y, "$c{s}$.", .{shortname}, .{});

    const itemtype: []const u8 = switch (item) {
        .Ring => "ring",
        .Key => "key",
        .Consumable => |c| if (c.is_potion) "potion" else "consumable",
        .Vial => "misc",
        .Projectile => "projectile",
        .Armor => "armor",
        .Cloak => "cloak",
        .Head => "headgear",
        .Shoe => "shoe",
        .Aux => "auxiliary item",
        .Weapon => |wp| if (wp.martial) "martial weapon" else "weapon",
        .Boulder => "misc",
        .Prop => "misc",
        .Evocable => "evocable",
    };
    y += self.drawTextAtf(0, y, "{s}", .{itemtype}, .{});

    y += self.drawTextAt(0, y, "\n", .{});

    switch (item) {
        .Key => |k| switch (k.lock) {
            .Up => |u| y += self.drawTextAtf(0, y, "A key for the stairs to {s}", .{
                state.levelinfo[u].name,
            }, .{}),
            .Access => y += self.drawTextAt(0, y, "A key for the main entrace", .{}),
            .Down => y += self.drawTextAt(0, y, "On the key is a masterpiece engraving of a cockroach enjoying a hearty meal", .{}),
        },
        .Ring => {},
        .Consumable => |p| {
            y += _writerHeader(self, y, linewidth, "effects", .{});
            for (p.effects) |effect| switch (effect) {
                .Kit => |m| y += self.drawTextAtf(0, y, "· $gMachine$. {s}", .{m.name}, .{}),
                .Damage => |d| y += self.drawTextAtf(0, y, "· $gIns$. {s} <$b{}$.>", .{ d.kind.string(), d.amount }, .{}),
                .Heal => |h| y += self.drawTextAtf(0, y, "· $gIns$. heal <$b{}$.>", .{h}, .{}),
                .Resist => |r| y += self.drawTextAtf(0, y, "· $gPrm$. {s: <9} $b{:>4}$.", .{ r.r.string(), r.change }, .{}),
                .Stat => |s| y += self.drawTextAtf(0, y, "· $gPrm$. {s: <9} $b{:>4}$.", .{ s.s.string(), s.change }, .{}),
                .Gas => |g| y += self.drawTextAtf(0, y, "· $gGas$. {s}", .{gas.Gases[g].name}, .{}),
                .Status => |s| y += self.drawTextAtf(0, y, "· $gTmp$. {s}", .{s.string(state.player)}, .{}),
                .MaxMP => |chg| y += self.drawTextAtf(0, y, "· $gPrm$. {s: <9} $b{:>4}$.", .{ "max MP", chg }, .{}),
                .Custom => y += self.drawTextAt(0, y, "· $G(See description)$.", .{}),
            };
            y += self.drawTextAt(0, y, "\n", .{});
        },
        .Projectile => |p| {
            const dmg = p.damage orelse @as(usize, 0);
            y += self.drawTextAtf(0, y, "$cdamage$.: {}", .{dmg}, .{});
            switch (p.effect) {
                .Status => |sinfo| {
                    y += _writerHeader(self, y, linewidth, "effects", .{});
                    y += self.drawTextAtf(0, y, "{s}", .{_formatStatusInfo(&sinfo)}, .{});
                },
            }
        },
        .Cloak => |c| {
            y += _writerHeader(self, y, linewidth, "stats", .{});
            y += _writerSobStats(self, y, linewidth, c.stats, c.resists);
        },
        .Head => |c| {
            y += _writerHeader(self, y, linewidth, "stats", .{});
            y += _writerSobStats(self, y, linewidth, c.stats, c.resists);
        },
        .Shoe => |c| {
            y += _writerHeader(self, y, linewidth, "stats", .{});
            y += _writerSobStats(self, y, linewidth, c.stats, c.resists);
        },
        .Aux => |aux| {
            y += _writerHeader(self, y, linewidth, "stats", .{});
            y += _writerSobStats(self, y, linewidth, aux.stats, aux.resists);

            if (aux.night) {
                y += _writerHeader(self, y, linewidth, "night stats (if in dark)", .{});
                y += _writerSobStats(self, y, linewidth, aux.night_stats, aux.night_resists);
            }

            if (aux.equip_effects.len > 0) {
                y += _writerHeader(self, y, linewidth, "on equip", .{});
                for (aux.equip_effects) |effect|
                    y += self.drawTextAtf(0, y, "· {s}", .{_formatStatusInfo(&effect)}, .{});
                y += self.drawTextAt(0, y, "\n", .{});
            }

            if (aux.night) {
                y += _writerHeader(self, y, linewidth, "traits", .{});
                y += self.drawTextAt(0, y, "It is a $cnight$. item and provides greater benefits if you stand on an unlit tile.", .{});
            }
        },
        .Armor => |a| {
            y += _writerHeader(self, y, linewidth, "stats", .{});
            y += _writerSobStats(self, y, linewidth, a.stats, a.resists);

            if (a.night) {
                y += _writerHeader(self, y, linewidth, "night stats (if in dark)", .{});
                y += _writerSobStats(self, y, linewidth, a.night_stats, a.night_resists);

                y += _writerHeader(self, y, linewidth, "traits", .{});
                y += self.drawTextAt(0, y, "It is a $cnight$. item and provides greater benefits if you stand on an unlit tile.", .{});
            }
        },
        .Weapon => |p| {
            // if (p.reach != 1) _writerWrite(w, "$creach:$. {}\n", .{p.reach});
            assert(p.reach == 1);

            y += _writerHeader(self, y, linewidth, "overview", .{});
            y += _writerTwice(self, y, linewidth, "damage", "($g{s}$.) {}", .{ p.damage_kind.stringLong(), p.damage });
            if (p.knockback != 0)
                y += _writerTwice(self, y, linewidth, "knockback", "{}", .{p.knockback});
            if (p.delay != 100) {
                const col: u21 = if (p.delay > 100) 'r' else 'b';
                y += _writerTwice(self, y, linewidth, "delay", "${u}{}%$.\n", .{ col, p.delay });
            }
            for (p.effects) |effect|
                y += _writerTwice(self, y, linewidth, "effect", "{s}", .{_formatStatusInfo(&effect)});
            y += self.drawTextAt(0, y, "\n", .{});

            y += _writerHeader(self, y, linewidth, "stats", .{});
            y += _writerSobStats(self, y, linewidth, p.stats, null);

            if (p.equip_effects.len > 0) {
                y += _writerHeader(self, y, linewidth, "on equip", .{});
                for (p.equip_effects) |effect|
                    y += self.drawTextAtf(0, y, "· {s}", .{_formatStatusInfo(&effect)}, .{});
                y += self.drawTextAt(0, y, "\n", .{});
            }

            y += _writerHeader(self, y, linewidth, "traits", .{});

            const p_ego_desc = if (p.ego.id()) |i| state.descriptions.get(i) else null;

            if (p.martial) {
                const stat = state.player.stat(.Martial);
                const statfmt = utils.SignedFormatter{ .v = stat };
                const color = if (stat < 0) @as(u21, 'r') else 'c';
                y += self.drawTextAtf(0, y, "$cmartial$.: You can attack up to ${u}{}$. extra time(s) (your Martial stat) if your attacks all land.\n", .{ color, statfmt }, .{});
            }

            // Newline between martial description and ego description, if
            // applicable
            if (p.martial and p_ego_desc != null) {
                y += 1;
            }

            if (p_ego_desc) |description| {
                y += self.drawTextAtf(0, y, "$c{s}$.: {s}\n", .{ p.ego.name().?, description }, .{});
            }

            y += self.drawTextAt(0, y, "\n", .{});
        },
        .Evocable => |e| {
            y += self.drawTextAtf(0, y, "$b{}$./$b{}$. charges.", .{ e.charges, e.max_charges }, .{});
            y += self.drawTextAtf(0, y, "$crechargable:$. {s}", .{_formatBool(e.rechargable)}, .{});
            y += self.drawTextAt(0, y, "\n", .{});

            if (e.delete_when_inert) {
                y += self.drawTextAt(0, y, "$bThis item is destroyed on use.$.", .{});
                y += self.drawTextAt(0, y, "\n", .{});
            }
        },
        .Boulder, .Prop, .Vial => y += self.drawTextAt(0, y, "$G(This item is useless to you.)$.", .{}),
    }

    y += self.drawTextAt(0, y, "\n", .{});

    return y - starty;
}

// }}}

fn _clearLineWith(from: usize, to: usize, y: usize, ch: u32, fg: u32, bg: u32) void {
    var x = from;
    while (x <= to) : (x += 1)
        display.setCell(x, y, .{ .ch = ch, .fg = fg, .bg = bg });
}

pub fn clearScreen() void {
    const height = display.height();
    const width = display.width();

    var y: usize = 0;
    while (y < height) : (y += 1)
        _clearLineWith(0, width, y, ' ', 0, colors.BG);
}

fn _clear_line(from: usize, to: usize, y: usize) void {
    _clearLineWith(from, to, y, ' ', 0, colors.BG);
}

pub fn _drawBorder(color: u32, d: Dimension) void {
    var y = d.starty;
    while (y <= d.endy) : (y += 1) {
        var x = d.startx;
        while (x <= d.endx) : (x += 1) {
            if (y != d.starty and y != d.endy and x != d.startx and x != d.endx) {
                continue;
            }

            const char: u21 = if (y == d.starty or y == d.endy) '─' else '│';
            display.setCell(x, y, .{ .ch = char, .fg = color, .bg = colors.BG });
        }
    }

    // Fix corners
    display.setCell(d.startx, d.starty, .{ .ch = '╭', .fg = color, .bg = colors.BG });
    display.setCell(d.endx, d.starty, .{ .ch = '╮', .fg = color, .bg = colors.BG });
    display.setCell(d.startx, d.endy, .{ .ch = '╰', .fg = color, .bg = colors.BG });
    display.setCell(d.endx, d.endy, .{ .ch = '╯', .fg = color, .bg = colors.BG });

    display.present();
}

pub const DrawStrOpts = struct {
    bg: ?u32 = colors.BG,
    fg: u32 = colors.OFF_WHITE,
    endy: ?usize = null,
    fold: bool = true,
    // When folding text, skip the first X lines. Used to implement scrolling.
    skip_lines: usize = 0,
    // When done, record last position of x in variable
    xptr: ?*usize = null,
};

fn _drawStrf(_x: usize, _y: usize, endx: usize, comptime format: []const u8, args: anytype, opts: DrawStrOpts) usize {
    const str = std.fmt.allocPrint(state.alloc, format, args) catch err.oom();
    defer state.alloc.free(str);
    return _drawStr(_x, _y, endx, str, opts);
}

// Escape characters:
//     $g       fg = GREY
//     $G       fg = DARK_GREY
//     $C       fg = CONCRETE
//     $c       fg = LIGHT_CONCRETE
//     $a       fg = AQUAMARINE
//     $p       fg = PINK
//     $b       fg = LIGHT_STEEL_BLUE
//     $r       fg = PALE_VIOLET_RED
//     $o       fg = GOLD
//     $.       reset fg and bg to defaults
//     $~       inverg fg/bg
fn _drawStr(_x: usize, _y: usize, endx: usize, str: []const u8, opts: DrawStrOpts) usize {
    assert(opts.xptr == null); // unsupported, use Console you degenerate

    // const width = display.width();
    const height = display.height();

    var x = _x;
    var y = _y;
    var skipped: usize = 0;

    var fg = opts.fg;
    var bg: ?u32 = opts.bg;

    const linewidth = if (opts.fold) @as(usize, @intCast(endx - x + 1)) else str.len;

    var fibuf = StackBuffer(u8, 4096).init(null);
    var fold_iter = utils.FoldedTextIterator.init(str, linewidth);
    while (fold_iter.next(&fibuf)) |line| : ({
        y += 1;
        x = _x;
    }) {
        if (skipped < opts.skip_lines) {
            skipped += 1;
            y -= 1; // Stay on the same line
            continue;
        }

        if (y >= height or (opts.endy != null and y >= opts.endy.?)) {
            break;
        }

        var utf8 = (std.unicode.Utf8View.init(line) catch err.bug("bad utf8", .{})).iterator();
        while (utf8.nextCodepointSlice()) |encoded_codepoint| {
            const codepoint = std.unicode.utf8Decode(encoded_codepoint) catch err.bug("bad utf8", .{});
            const def_bg = display.getCell(x, y).bg;

            switch (codepoint) {
                '\n' => {
                    y += 1;
                    x = _x;
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
                        else => err.bug("Found unknown escape sequence '${u}' (line: '{s}')", .{ next_codepoint, line }),
                    }
                    continue;
                },
                else => {
                    display.setCell(x, y, .{ .ch = codepoint, .fg = fg, .bg = bg orelse def_bg });
                    x += 1;
                },
            }

            if (!opts.fold and x == endx) {
                x -= 1;
            }
        }
    }

    return y;
}

fn drawHUD(moblist: []const *Mob) void {
    // const last_action_cost = if (state.player.activities.current()) |lastaction| b: {
    //     const spd = @floatFromInt(f64, state.player.speed());
    //     break :b (spd * @floatFromInt(f64, lastaction.cost())) / 100.0 / 10.0;
    // } else 0.0;

    var arena = std.heap.ArenaAllocator.init(state.alloc);
    defer arena.deinit();

    const endx = hud_win.main.width - 1;

    hud_win.main.clearMouseTriggers();
    hud_win.main.clear();
    var y: usize = 0;

    const lvlstr = state.levelinfo[state.player.coord.z].name;
    const lvlid = state.levelinfo[state.player.coord.z].id;
    _ = hud_win.main.drawTextAtf(0, y, "$cturns:$. {}", .{state.player_turns}, .{});
    y += hud_win.main.drawTextAtf(endx - (lvlstr.len - 1), y, "$c{s}$.", .{lvlstr}, .{});
    hud_win.main.addTooltipForText("{s}", .{lvlstr}, "level_{s}", .{lvlid});
    y += 1;

    // zig fmt: off
    const stats = [_]struct { id: []const u8, b: []const u8, a: []const u8, v: isize, va: ?usize = null, p: bool = true }{
        .{ .id = "Melee",       .b = "to-hit: ", .a = "%", .v = state.player.stat(.Melee), .va = combat.chanceOfMeleeLanding(state.player, null) },
        .{ .id = "rFire",       .b = "rFire:  ", .a = "%", .v = state.player.resistance(.rFire) },
        .{ .id = "Evade",       .b = "evasion:", .a = "%", .v = state.player.stat(.Evade), .va = combat.chanceOfAttackEvaded(state.player, null) },
        .{ .id = "rElec",       .b = "rElec:  ", .a = "%", .v = state.player.resistance(.rElec) },
        .{ .id = "Martial",     .b = "martial:", .a = " ", .v = state.player.stat(.Martial),     .p = player.isPlayerMartial() },
        .{ .id = "Conjuration", .b = "conj:   ", .a = " ", .v = state.player.stat(.Conjuration), .p = state.player.stat(.Conjuration) > 0 },
        .{ .id = "Spikes",      .b = "spikes: ", .a = " ", .v = state.player.stat(.Spikes),      .p = state.player.stat(.Spikes) > 0 },
    }; 
    // zig fmt: on

    var i: usize = 0;
    for (stats) |stat| {
        if (!stat.p) continue;
        const v = utils.SignedFormatter{ .v = stat.v };
        const x = switch (i % 2) {
            0 => 0,
            1 => std.fmt.count("{s} {: >3}{s}", .{ stat.b, v, stat.a }) + 9,
            //2 => (@divTrunc(endx - startx, 3) * 2) + 1,
            else => unreachable,
        };
        const c: u21 = if (stat.v < 0) 'p' else '.';
        if (stat.va == null or @as(usize, @intCast(math.clamp(stat.v, 0, 100))) == stat.va.?) {
            _ = hud_win.main.drawTextAtf(x, y, "$c{s}$. ${u}{: >3}{s}$.", .{ stat.b, c, v, stat.a }, .{});
        } else {
            const ca: u21 = if (stat.va.? < stat.v) 'p' else 'b';
            _ = hud_win.main.drawTextAtf(x, y, "$c{s}$. ${u}{: >3}{s} $g(${u}{}{s}$g)$.", .{ stat.b, c, v, stat.a, ca, stat.va.?, stat.a }, .{});
        }
        hud_win.main.addTooltipForText("{s} stat", .{stat.id}, "stat_{s}", .{stat.id});
        if (i % 2 == 1)
            y += 1;
        i += 1;
    }
    if (i % 2 == 1)
        y += 1;
    y += 1;

    const repfmt = utils.ReputationFormatter{};
    if (repfmt.dewIt()) {
        y += hud_win.main.drawTextAtf(0, y, "{}", .{repfmt}, .{});
        hud_win.main.addTooltipForText("Reputation", .{}, "concept_Reputation", .{});
        y += 1;
    }

    const bar_endx = endx - 8;
    // const bar_endx2 = endx - 18;

    // Use red if below 40% health
    const color: [2]u32 = if (state.player.HP < (state.player.max_HP / 5) * 2)
        [_]u32{ colors.percentageOf(colors.PALE_VIOLET_RED, 25), colors.LIGHT_PALE_VIOLET_RED }
    else
        [_]u32{ colors.percentageOf(colors.DOBALENE_BLUE, 25), colors.DOBALENE_BLUE };
    _ = hud_win.main.drawBarAt(0, bar_endx, y, state.player.HP, state.player.max_HP, "health", color[0], color[1], .{});
    hud_win.main.addTooltipForText("Health", .{}, "stat_Health_player", .{});
    const hit = combat.chanceOfMeleeLanding(state.player, null);
    _ = hud_win.main.drawTextAtf(bar_endx + 1, y, "$bhit {: >3}%$.", .{hit}, .{});
    hud_win.main.addTooltipForText("Melee stat", .{}, "stat_Melee", .{});
    y += 1;

    _ = hud_win.main.drawBarAt(0, bar_endx, y, state.player.MP, state.player.max_MP, "mana", colors.percentageOf(colors.GOLD, 55), colors.LIGHT_GOLD, .{});
    hud_win.main.addTooltipForText("Magic", .{}, "stat_Magic", .{});
    const pot = utils.SignedFormatter{ .v = state.player.stat(.Potential) };
    _ = hud_win.main.drawTextAtf(bar_endx + 1, y, "$opot {: >3}%$.", .{pot}, .{});
    hud_win.main.addTooltipForText("Potential stat", .{}, "stat_Potential", .{});
    y += 1;

    // const ev = utils.SignedFormatter{ .v = state.player.stat(.Evade) };
    const arm = utils.SignedFormatter{ .v = state.player.resistance(.Armor) };
    const willpower: usize = @intCast(state.player.stat(.Willpower));
    const is_corrupted = state.player.hasStatus(.Corruption);
    const corruption_str = if (is_corrupted) "corrupted" else "corruption";
    const corruption_val = if (is_corrupted) willpower else state.player.corruption_ctr;
    _ = hud_win.main.drawBarAt(0, bar_endx, y, corruption_val, willpower, corruption_str, 0x999999, 0xeeeeee, .{ .detail = !is_corrupted });
    hud_win.main.addTooltipForText("Corruption", .{}, "concept_Corruption", .{});
    // _ = _hud_win.main.drawTextAtf(bar_endx2 + 1, y, bar_endx, "$pev  {: >3}%$.", .{ev}, .{});
    _ = hud_win.main.drawTextAtf(bar_endx + 1, y, "$.arm {: >3}%$.", .{arm}, .{});
    hud_win.main.addTooltipForText("Armor stat", .{}, "stat_Armor", .{});
    y += 2;

    {
        var status_drawn = false;
        var statuses = state.player.statuses.iterator();
        while (statuses.next()) |entry| {
            if (state.player.isUnderStatus(entry.key) == null)
                continue;

            const statusinfo = state.player.isUnderStatus(entry.key).?;
            const sname = statusinfo.status.string(state.player);

            if (statusinfo.duration == .Tmp) {
                y += hud_win.main.drawBarAt(0, endx, y, statusinfo.duration.Tmp, Status.MAX_DURATION, sname, 0x30055c, 0xd069fc, .{});
            } else {
                y += hud_win.main.drawBarAt(0, endx, y, Status.MAX_DURATION, Status.MAX_DURATION, sname, 0x054c20, 0x69fcd0, .{ .detail = false });
            }
            hud_win.main.addTooltipForText("{s}", .{sname}, "player_{s}", .{@tagName(entry.key)});

            //y += hud_win.main.drawTextAtf(startx, y, endx, "{s} ({} turns)", .{ sname, duration }, .{ .fg = 0x8019ac, .bg = null });

            status_drawn = true;
        }
        if (status_drawn) y += 1;
    }

    const light = state.player.isLit();
    const spotted = player.isPlayerSpotted();

    if (light or spotted) {
        const lit_str = if (light) "$C$~ Lit $." else "";
        const spotted_str = if (spotted) "$bSpotted$." else "";

        _ = hud_win.main.drawTextAtf(0, y, "{s}", .{lit_str}, .{});
        hud_win.main.addTooltipForText("Lit", .{}, "concept_Lit", .{});
        const spotted_x = if (light) hud_win.main.last_text_endx + 2 else 0;
        _ = hud_win.main.drawTextAtf(spotted_x, y, "{s}", .{spotted_str}, .{});
        hud_win.main.addTooltipForText("Spotted", .{}, "concept_Spotted", .{});

        y += 2;
    }

    // ------------------------------------------------------------------------

    {
        const FeatureInfo = struct {
            name: BStr(32),
            tile: display.Cell,
            coord: Coord,
            ex_focus: ExamineTileFocus,
            priority: usize,
            player: bool,
        };

        var features = std.ArrayList(FeatureInfo).init(arena.allocator());
        defer features.deinit();

        var dijk = dijkstra.Dijkstra.init(
            state.player.coord,
            state.mapgeometry,
            @intCast(state.player.stat(.Vision)),
            dijkstra.dummyIsValid,
            .{},
            arena.allocator(),
        );
        defer dijk.deinit();

        while (dijk.next()) |coord| if (state.player.cansee(coord)) {
            var name = BStr(32).init(null);
            var priority: usize = 0;
            var focus: ExamineTileFocus = .Item;

            if (state.dungeon.itemsAt(coord).len > 0) {
                const item = state.dungeon.itemsAt(coord).last().?;
                if (item != .Vial and item != .Prop and item != .Boulder) {
                    name.appendSlice((item.shortName() catch err.wat()).constSlice()) catch err.wat();
                }
                priority = 3;
                focus = .Item;
            } else if (state.dungeon.at(coord).surface) |surf| {
                priority = 2;
                focus = .Surface;
                name.appendSlice(switch (surf) {
                    .Machine => |m| if (m.player_interact != null or m.show_on_hud) m.name else "",
                    .Prop => "",
                    .Corpse => "corpse",
                    .Container => |c| c.name,
                    .Poster => "poster",
                    .Stair => |s| switch (s.stairtype) {
                        .Up => "upward stairs",
                        .Access => "main stairway",
                        .Down => "",
                    },
                }) catch err.wat();
            } else if (!mem.eql(u8, state.dungeon.terrainAt(coord).id, "t_default")) {
                priority = 1;
                focus = .Surface;
                name.appendSlice(state.dungeon.terrainAt(coord).name) catch err.wat();
            } else if (state.dungeon.at(coord).type != .Wall) {
                const material = state.dungeon.at(coord).material;
                focus = .Surface;
                switch (state.dungeon.at(coord).type) {
                    .Wall => name.fmt("{s} wall", .{material.name}),
                    .Floor => name.fmt("{s} floor", .{material.name}),
                    .Lava => name.appendSlice("lava") catch err.wat(),
                    .Water => name.appendSlice("water") catch err.wat(),
                }
            }

            if (name.len > 0) {
                const existing = utils.findFirstNeedlePtr(features.items, name, struct {
                    pub fn func(f: *const FeatureInfo, n: BStr(32)) bool {
                        return mem.eql(u8, n.constSlice(), f.name.constSlice());
                    }
                }.func);
                if (existing == null) {
                    var tile = Tile.displayAs(coord, true, true);
                    tile.fl.wide = true;

                    features.append(FeatureInfo{
                        .name = name,
                        .tile = tile,
                        .coord = coord,
                        .ex_focus = focus,
                        .player = state.player.coord.eq(coord),
                        .priority = priority,
                    }) catch err.wat();
                } else {
                    if (state.player.coord.eq(coord))
                        existing.?.player = true;
                }
            }
        };

        std.sort.insertion(FeatureInfo, features.items, {}, struct {
            pub fn f(_: void, a: FeatureInfo, b: FeatureInfo) bool {
                return a.priority < b.priority;
            }
        }.f);

        for (features.items) |feature| {
            hud_win.main.setCell(0, y, feature.tile);
            hud_win.main.setCell(0 + 1, y, .{ .fl = .{ .skip = true } });

            _ = hud_win.main.drawTextAtf(0 + 3, y, "$c{s}$.", .{feature.name.constSlice()}, .{});
            if (feature.player) {
                _ = hud_win.main.drawTextAtf(endx, y, "@", .{}, .{});
            }

            const trigrect = Rect.new(Coord.new(0, y), endx, 0);
            hud_win.main.addMouseTrigger(trigrect, .Hover, .{ .RecordElem = &hud_win.main });
            hud_win.main.addMouseTrigger(trigrect, .Click, .{
                .ExamineScreen = .{ .starting_focus = feature.ex_focus, .start_coord = feature.coord },
            });

            y += 1;
        }
    }
    y += 1;

    // ------------------------------------------------------------------------

    for (moblist) |mob| {
        if (mob.is_dead) continue;

        var t = Tile.displayAs(mob.coord, true, false);
        t.fl.wide = true;
        hud_win.main.setCell(0, y, t);
        hud_win.main.setCell(0 + 1, y, .{ .fl = .{ .skip = true } });

        const name = mob.displayName();
        _ = hud_win.main.drawTextAtf(0 + 3, y, "$c{s}$.", .{name}, .{ .bg = null });

        const infoset = _getMonsInfoSet(mob, arena.allocator());
        defer MobInfoLine.deinitList(infoset);
        //var info_x: isize = startx + 2 + @intCast(isize, name.len) + 2;
        var info_x: usize = endx - (infoset.items.len - 1);
        for (infoset.items) |info| {
            _ = hud_win.main.drawTextAtf(info_x, y, "${u}{u}$.", .{ info.color, info.char }, .{ .bg = null });
            info_x += 1;
        }

        const trigrect = Rect.new(Coord.new(0, y), endx, 0);
        hud_win.main.addMouseTrigger(trigrect, .Hover, .{ .RecordElem = &hud_win.main });
        hud_win.main.addMouseTrigger(trigrect, .Click, .{
            .ExamineScreen = .{ .starting_focus = .Mob, .start_coord = mob.coord },
        });

        y += 1;

        {
            var status_drawn = false;
            var statuses = mob.statuses.iterator();
            while (statuses.next()) |entry| {
                if (mob.isUnderStatus(entry.key) == null or entry.value.duration != .Tmp)
                    continue;

                const statusinfo = mob.isUnderStatus(entry.key).?;
                const duration = statusinfo.duration.Tmp;
                const sname = statusinfo.status.string(state.player);

                y += hud_win.main.drawBarAt(0, endx, y, duration, Status.MAX_DURATION, sname, 0x30055c, 0xd069fc, .{});
                hud_win.main.addTooltipForText("{s}", .{sname}, "nonplayer_{s}", .{@tagName(entry.key)});
                status_drawn = true;
            }
            if (status_drawn) y += 1;
        }

        //const activity = if (mob.prisoner_status != null) if (mob.prisoner_status.?.held_by != null) "(chained)" else "(prisoner)" else mob.activity_description();
        //y += hud_win.main.drawTextAtf(endx - @divTrunc(endx - startx, 2) - @intCast(isize, activity.len / 2), y, endx, "{s}", .{activity}, .{ .fg = 0x9a9a9a });

        //y += 2;
    }

    hud_win.main.highlightMouseArea(colors.BG_L);
}

fn drawLog() void {
    if (state.messages.items.len == 0)
        return;

    const linewidth = log_win.main.width - 1;
    const messages_len = state.messages.items.len - 1;

    var y: usize = log_win.main.height;
    for (state.messages.items, 0..) |message, i| {
        if (log_win.last_message) |last_message|
            if (i <= last_message)
                continue;
        const col = if (message.turn >= state.player_turns or i == messages_len)
            message.type.color()
        else
            colors.darken(message.type.color(), 2);

        const line = if (i > 0 and i < messages_len and (message.turn != state.messages.items[i - 1].turn and message.turn != state.messages.items[i + 1].turn))
            @as(u21, ' ')
        else if (i == 0 or message.turn > state.messages.items[i - 1].turn)
            @as(u21, '╭')
        else if (i == messages_len or message.turn < state.messages.items[i + 1].turn)
            @as(u21, '╰')
        else
            @as(u21, '│');

        const noisetext: []const u8 = if (message.noise) "$c─$a♫$. " else "$c─$.  ";

        var str: BStr(256) = undefined;
        str.clear();

        if (message.dups == 0) {
            str.fmt("$G{u}$.{s}{s}", .{ line, noisetext, message.msg.constSlice() });
        } else {
            str.fmt("$G{u}$.{s}{s} (×{})", .{ line, noisetext, message.msg.constSlice(), message.dups + 1 });
        }

        var fibuf = StackBuffer(u8, 4096).init(null);
        var fold_iter = utils.FoldedTextIterator.init(str.constSlice(), linewidth + 1);
        while (fold_iter.next(&fibuf)) |text_line| : (y += 1) {
            var console = Console.initHeap(state.alloc, linewidth, 1);
            _ = console.drawTextAt(0, 0, text_line, .{ .fg = col });
            console.addRevealAnimation(.{ .factor = 6 });
            log_win.main.addSubconsole(console, 0, y);
        }
    }

    log_win.last_message = messages_len;
    log_win.main.changeHeight(y);
    log_win.main.clearMouseTriggers();
    log_win.main.addMouseTrigger(log_win.main.dimensionsRect(), .Click, .OpenLogWindow);
}

fn _mobs_can_see(moblist: []const *Mob, coord: Coord) bool {
    for (moblist) |mob| {
        if (mob.is_dead or mob.no_show_fov or
            !mob.ai.is_combative or !mob.isHostileTo(state.player))
            continue;
        if (mob.cansee(coord)) return true;
    }
    return false;
}

pub fn screenCoordToNormal(coord: Coord, absrefpoint: Coord) ?Coord {
    const refpoint = coordToScreenFromRefpoint(absrefpoint, absrefpoint).?;
    const x = @as(isize, @intCast(absrefpoint.x)) +
        @divFloor(@as(isize, @intCast(coord.x)) - @as(isize, @intCast(refpoint.x)), 2);
    const y = @as(isize, @intCast(absrefpoint.y)) +
        (@as(isize, @intCast(coord.y)) - @as(isize, @intCast(refpoint.y)) - 1);
    if (x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT)
        return null;
    return Coord.new2(absrefpoint.z, @intCast(x), @intCast(y));
}

pub fn coordToScreenFromRefpoint(coord: Coord, refpoint: Coord) ?Coord {
    if (coord.x < refpoint.x -| MAP_WIDTH_R or coord.x > refpoint.x + MAP_WIDTH_R or
        coord.y < refpoint.y -| MAP_HEIGHT_R or coord.y > refpoint.y + MAP_HEIGHT_R)
    {
        return null;
    }
    const r = Coord.new2(
        0,
        @as(usize, @intCast(@as(isize, @intCast(coord.x)) - (@as(isize, @intCast(refpoint.x)) -| MAP_WIDTH_R))) * 2,
        @intCast(@as(isize, @intCast(coord.y)) - (@as(isize, @intCast(refpoint.y)) -| MAP_HEIGHT_R)),
    );
    if (r.x >= map_win.map.width or r.y >= map_win.map.height) {
        return null;
    }
    return r;
}

pub fn coordToScreen(coord: Coord) ?Coord {
    return coordToScreenFromRefpoint(coord, state.player.coord);
}

fn modifyTile(moblist: []const *Mob, coord: Coord, p_tile: display.Cell) display.Cell {
    var tile = p_tile;

    // Draw noise and indicate if that tile is visible by another mob
    switch (state.dungeon.at(coord).type) {
        .Floor => {
            // const has_stuff = state.dungeon.at(coord).surface != null or
            //     state.dungeon.at(coord).mob != null or
            //     state.dungeon.itemsAt(coord).len > 0;

            const light = state.dungeon.lightAt(state.player.coord).*;
            if (state.player.coord.eq(coord)) {
                tile.fg = if (light) colors.LIGHT_CONCRETE else colors.LIGHT_STEEL_BLUE;
            }

            if (_mobs_can_see(moblist, coord)) {
                // // Treat this cell specially if it's the player and the player is
                // // being watched.
                // if (state.player.coord.eq(coord) and _mobs_can_see(moblist, coord)) {
                //     return .{ .bg = colors.LIGHT_CONCRETE, .fg = colors.BG, .ch = '@' };
                // }

                // if (has_stuff) {
                //     if (state.is_walkable(coord, .{ .right_now = true })) {
                //         // Swap.
                //         tile.fg ^= tile.bg;
                //         tile.bg ^= tile.fg;
                //         tile.fg ^= tile.bg;
                //     }
                // } else {
                //tile.ch = '⬞';
                //tile.ch = '÷';
                //tile.fg = 0xffffff;
                // tile.fg = 0xff6666;
                if (state.is_walkable(coord, .{ .mob = state.player })) {
                    tile.bg = colors.percentageOf(colors.DOBALENE_BLUE, 15);
                }
                // }
            }
        },
        else => {},
    }

    return tile;
}

// FIXME: Refactor this into 2-3 functions, one which just provides an iterator
// over the area to be drawn over, one which gets the tile to be drawn, and one
// which modifies the console.
//
// This function draws onto map_win.map usually, but is also used for other
// things. So we have to check if console==map_win.map before doing mouse
// triggers and other map_win.map-only things, which is kinda yucky and
// fragile.
//
pub fn drawMap(console: *Console, moblist: []const *Mob, refpoint: Coord) void {
    const refpointy: isize = @intCast(refpoint.y);
    const refpointx: isize = @intCast(refpoint.x);
    const level = state.player.coord.z;

    var cursory: usize = 0;
    var cursorx: usize = 0;

    const map_starty = refpointy - @as(isize, @intCast(MAP_HEIGHT_R));
    const map_endy = refpointy + @as(isize, @intCast(MAP_HEIGHT_R));
    const map_startx = refpointx - @as(isize, @intCast(MAP_WIDTH_R));
    const map_endx = refpointx + @as(isize, @intCast(MAP_WIDTH_R));

    if (console == &map_win.map) // yuck
        console.clearMouseTriggers();

    console.clearTo(.{ .fl = .{ .wide = true } });

    var y = map_starty;
    while (y < map_endy and cursory < console.height) : ({
        y += 1;
        cursory += 1;
        cursorx = 0;
    }) {
        var x = map_startx;
        while (x < map_endx and cursorx < console.width) : ({
            x += 1;
            cursorx += 2;
        }) {
            // if out of bounds on the map, draw a black tile
            if (y < 0 or x < 0 or y >= HEIGHT or x >= WIDTH) {
                if (console == &map_win.map) // yuck
                    map_win.gridAnimAt(cursorx, cursory).* = null;

                console.setCell(cursorx, cursory, .{ .bg = colors.BG, .fl = .{ .wide = true } });
                console.setCell(cursorx + 1, cursory, .{ .fl = .{ .skip = true } });
                continue;
            }

            const u_x: usize = @intCast(x);
            const u_y: usize = @intCast(y);
            const coord = Coord.new2(level, u_x, u_y);
            const cursor_coord = Coord.new(cursorx, cursory);

            var tile: display.Cell = undefined;

            const cansee = state.player.cansee(coord);

            // if player can't see area, draw a blank/blue tile, depending on
            // what they saw last there
            if (!cansee) {
                tile = .{ .fg = 0, .bg = colors.BG, .ch = ' ' };

                if (state.memory.contains(coord)) {
                    tile = (state.memory.get(coord) orelse unreachable).tile;

                    const old_sbg = tile.sbg;

                    tile.bg = colors.filterBluescale(tile.bg);
                    tile.fg = colors.filterBluescale(tile.fg);
                    tile.sbg = colors.filterBluescale(tile.sbg);
                    tile.sfg = colors.filterBluescale(tile.sfg);

                    if (tile.bg < colors.BG) tile.bg = colors.BG;

                    // Don't lighten the sbg if it was originally 0 (because
                    // then we have to fallback to the bg)
                    if (tile.sbg < colors.BG and old_sbg != 0) tile.sbg = colors.BG;
                }

                // Can we hear anything
                if (state.player.canHear(coord)) |noise| if (noise.state == .New) {
                    tile.fg = 0x00d610;
                    tile.ch = if (noise.intensity.radiusHeard() > 6) '♫' else '♩';
                    tile.sch = null;
                };

                if (console == &map_win.map) // yuck
                    map_win.gridAnimAt(cursorx, cursory).* = null;
            } else {
                tile = modifyTile(moblist, coord, Tile.displayAs(coord, false, false));
            }

            tile.fl.wide = true;
            console.setCell(cursorx, cursory, tile);
            console.setCell(cursorx + 1, cursory, .{ .fl = .{ .skip = true } });

            if (cansee and
                console == &map_win.map) // yuck
            {
                console.addMouseTrigger(cursor_coord.asRect(), .Hover, .{ .RecordElem = &map_win.annotations });
                console.addMouseTrigger(cursor_coord.asRect(), .Click, .{ .ExamineScreen = .{ .start_coord = coord } });

                map_win.gridAnimAt(cursorx, cursory).* = Tile.animateAs(coord);
                if (map_win.gridAnimAt2(cursorx, cursory)) |anim|
                    map_win.grid_annotations.setCell(cursorx, cursory, anim.get());
            }
        }
    }

    // console.highlightMouseArea(colors.BG_L);
}

pub fn drawAnimationNoPresentTimeout(timeout: ?usize) void {
    assert(timeout == null or timeout.? >= FRAMERATE);
    var timer = std.time.Timer.start() catch err.wat();
    while (true) {
        drawLabels();
        hud_win.main.stepRevealAnimation();
        log_win.stepAnimations();
        map_win.grid_annotations.clear();
        map_win.stepBorderAnimations(state.player.coord);
        map_win.stepTextLineAnimations();
        map_win.stepGridAnimations();

        if (timeout == null) return;

        const max_timeout_ns = FRAMERATE * 1_000_000; // 20 ms
        const remaining = ((timeout orelse std.math.maxInt(u64)) *| 1_000_000) -| timer.read();
        std.Thread.sleep(@min(max_timeout_ns, remaining));

        if (timer.read() / 1_000_000 > timeout.?) return;
    }
}

pub fn drawAnimationsNoPresent() void {
    drawAnimationNoPresentTimeout(null);
}

pub fn drawAnimations() void {
    drawAnimationsNoPresent();
    render();
    display.present();
}

pub fn render() void {
    map_win.map.renderFullyW(.Main);
    hud_win.main.renderFullyW(.PlayerInfo);
    log_win.render();
}

pub fn drawNoPresent() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    const moblist = state.createMobList(false, true, state.player.coord.z, alloc);

    drawHUD(moblist.items);
    drawMap(&map_win.map, moblist.items, state.player.coord);
    drawLog();
    drawAnimations();
    render();
}

pub fn draw() void {
    drawNoPresent();
    display.present();
}

pub fn handleMouseEvent(ev: display.Event) bool {
    return map_win.handleMouseEvent(ev) or
        hud_win.handleMouseEvent(ev) or
        log_win.handleMouseEvent(ev);
}

pub const ChooseCellOpts = struct {
    max_distance: ?usize = null,
    targeter: Targeter = .Single,
    require_seen: bool = true,
    require_lof: bool = false,
    require_enemy_on_tile: bool = false,
    require_walkable: ?state.IsWalkableOptions = null,

    pub const Targeter = union(enum) {
        Single,
        Trajectory: struct { require_lof: bool = true },
        Exclusion: struct {},
        AoE1: struct { dist: usize, opts: state.IsWalkableOptions },
        Gas: struct { gas: usize },
        Duo: [2]*const Targeter,

        pub const Result = struct {
            coord: Coord,
            ch: ?u32 = null,
            color: usize,
            pub const AList = std.ArrayList(@This());
        };

        pub const Func = *const fn (Targeter, bool, Coord, *Result.AList) Error!void;
        pub const Error = error{ BrokenLOF, OutOfRange, OutOfLOS, RequireEnemyOnTile, Unwalkable };

        pub fn func(self: Targeter) Func {
            return switch (self) {
                .Single => struct {
                    pub fn f(_: Targeter, _: bool, coord: Coord, buf: *Result.AList) Error!void {
                        buf.append(.{ .coord = coord, .color = 100 }) catch err.wat();
                    }
                }.f,
                .Trajectory => struct {
                    pub fn f(t: Targeter, require_seen: bool, coord: Coord, buf: *Result.AList) Error!void {
                        const trajectory = state.player.coord.drawLine(coord, state.mapgeometry, 0);

                        const trajectory_is_unseen = if (require_seen) for (trajectory.constSlice()) |c| {
                            if (!state.player.cansee(c)) break true;
                        } else false else false;
                        const lof_is_ok = !t.Trajectory.require_lof or
                            utils.hasClearLOF(state.player.coord, coord);

                        buf.append(.{ .coord = state.player.coord, .color = 100 }) catch err.wat();
                        buf.append(.{ .coord = coord, .color = 100 }) catch err.wat();

                        for (trajectory.constSlice()) |traj_c| {
                            if (state.player.coord.eq(traj_c)) continue;
                            if (coord.eq(traj_c)) break;

                            buf.append(.{ .coord = traj_c, .color = 100 }) catch err.wat();
                        }

                        if (!lof_is_ok or trajectory_is_unseen) {
                            return error.BrokenLOF;
                        }
                    }
                }.f,
                .Exclusion => struct {
                    // XXX: Lots of duplicated code btween here and Exclusion Ring code
                    pub fn f(t: Targeter, require_seen: bool, coord: Coord, buf: *Result.AList) Error!void {
                        _ = t;

                        if (require_seen and !state.player.cansee(coord))
                            return error.OutOfLOS;

                        buf.append(.{ .coord = coord, .color = 100 }) catch unreachable;

                        const direct = coord.closestCardinalDirectionTo(state.player.coord, state.mapgeometry);
                        const dir1 = direct.turnleft();
                        const dir2 = direct.turnright();
                        var c = coord.move(dir1, state.mapgeometry);
                        while (c != null and state.is_walkable(c.?, .{})) {
                            buf.append(.{ .coord = c.?, .color = 50 }) catch unreachable;
                            c = c.?.move(dir1, state.mapgeometry);
                        }
                        c = coord.move(dir2, state.mapgeometry);
                        while (c != null and state.is_walkable(c.?, .{})) {
                            buf.append(.{ .coord = c.?, .color = 50 }) catch unreachable;
                            c = c.?.move(dir2, state.mapgeometry);
                        }

                        if (require_seen) {
                            var i: usize = 0;
                            while (i < buf.items.len) {
                                if (!state.player.cansee(buf.items[i].coord)) {
                                    _ = buf.swapRemove(i);
                                } else {
                                    i += 1;
                                }
                            }
                        }
                    }
                }.f,
                .Gas => struct {
                    pub fn f(targeter: Targeter, _: bool, coord: Coord, buf: *Result.AList) Error!void {
                        buf.append(.{ .coord = coord, .color = 100 }) catch err.wat();

                        var matrix = std.mem.zeroes([HEIGHT][WIDTH]usize);
                        _ = gas.mockGasSpread(targeter.Gas.gas, 100, coord, &matrix);
                        for (matrix, 0..) |row, y| for (row, 0..) |cell, x| if (cell > 0) {
                            const c = Coord.new2(coord.z, x, y);
                            buf.append(.{ .coord = c, .color = cell }) catch err.wat();
                        };
                    }
                }.f,
                .AoE1 => struct {
                    pub fn f(targeter: Targeter, _: bool, coord: Coord, buf: *Result.AList) Error!void {
                        // First do the squares that the player can see
                        {
                            var dijk = dijkstra.Dijkstra.init(coord, state.mapgeometry, targeter.AoE1.dist, state.is_walkable, targeter.AoE1.opts, state.alloc);
                            defer dijk.deinit();

                            while (dijk.next()) |child| if (state.player.cansee(child)) {
                                const percent = 100 - (child.distance(coord) * 100 / (targeter.AoE1.dist * 3 / 2));
                                // const percent = if (child.eq(coord)) @as(usize, 100) else 30;
                                buf.append(.{ .coord = child, .color = percent }) catch err.wat();
                            };
                        }

                        // ...And now the squares the player can't see
                        {
                            var dijk = dijkstra.Dijkstra.init(coord, state.mapgeometry, targeter.AoE1.dist, struct {
                                pub fn f(c: Coord, opts: state.IsWalkableOptions) bool {
                                    if (state.player.cansee(c)) return state.is_walkable(c, opts);
                                    return true;
                                }
                            }.f, targeter.AoE1.opts, state.alloc);
                            defer dijk.deinit();

                            while (dijk.next()) |child| if (!state.player.cansee(child)) {
                                buf.append(.{ .coord = child, .color = 30, .ch = '?' }) catch err.wat();
                            };
                        }
                    }
                }.f,
                .Duo => struct {
                    pub fn f(targeter: Targeter, require_seen: bool, coord: Coord, buf: *Result.AList) Error!void {
                        var terror: ?Error = null;
                        (targeter.Duo[0].*.func())(targeter.Duo[0].*, require_seen, coord, buf) catch |e| {
                            terror = e;
                        };
                        (targeter.Duo[1].*.func())(targeter.Duo[1].*, require_seen, coord, buf) catch |e| {
                            terror = e;
                        };
                        return if (terror) |e| e else {};
                    }
                }.f,
            };
        }
    };
};

pub fn chooseCell(opts: ChooseCellOpts) ?Coord {
    const COLOR_Y = colors.percentageOf(colors.LIGHT_STEEL_BLUE, 40);
    const COLOR_N = colors.percentageOf(colors.PALE_VIOLET_RED, 40);

    var terror: ?ChooseCellOpts.Targeter.Error = null;
    var coord: Coord = state.player.coord;
    var coords = ChooseCellOpts.Targeter.Result.AList.init(state.alloc);
    defer coords.deinit();

    map_win.annotations.clear();

    defer map_win.annotations.clear();
    defer map_win.map.renderFullyW(.Main);

    const moblist = state.createMobList(false, true, state.player.coord.z, state.alloc);
    defer moblist.deinit();

    while (true) {
        terror = null;
        const refpoint = if (opts.require_seen) state.player.coord else coord;

        drawMap(&map_win.map, moblist.items, refpoint);
        map_win.annotations.clear();
        map_win.map.renderFullyW(.Main);

        if (opts.require_seen and !state.player.cansee(coord) and
            !state.memory.contains(coord))
        {
            terror = error.OutOfLOS;
        } else if (opts.max_distance != null and
            coord.distance(state.player.coord) > opts.max_distance.?)
        {
            terror = error.OutOfRange;
        } else if (opts.require_enemy_on_tile and
            (utils.getHostileAt(state.player, coord) catch null) == null)
        {
            terror = error.RequireEnemyOnTile;
        } else if (opts.require_walkable != null and
            !state.is_walkable(coord, opts.require_walkable.?))
        {
            terror = error.Unwalkable;
        }

        coords.clearAndFree();
        (opts.targeter.func())(opts.targeter, opts.require_seen, coord, &coords) catch |e| {
            terror = e;
        };

        const color = if (terror != null) COLOR_N else COLOR_Y;

        for (coords.items) |item| {
            const ditemc = coordToScreenFromRefpoint(item.coord, refpoint) orelse continue;
            const old = map_win.map.getCell(ditemc.x, ditemc.y);
            const item_color = colors.percentageOf(color, item.color);
            const ch = item.ch orelse old.ch;
            map_win.annotations.setCell(ditemc.x, ditemc.y, .{ .ch = ch, .fg = old.fg, .bg = item_color, .fl = .{ .wide = true } });
        }

        map_win.map.renderFullyW(.Main);
        display.present();

        var evgen = display.getEvents(null);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return null;
            },
            .Key => |k| switch (k) {
                .Esc, .CtrlC, .CtrlG => return null,
                .Enter => {
                    if (terror) |_terror| {
                        switch (_terror) {
                            error.BrokenLOF => drawAlert("There's something in the way.", .{}),
                            error.OutOfRange => drawAlert("Out of range!", .{}),
                            error.OutOfLOS => drawAlert("You haven't seen that place!", .{}),
                            error.RequireEnemyOnTile => drawAlert("You must select a nearby enemy.", .{}),
                            error.Unwalkable => drawAlert("Tile must be empty.", .{}),
                        }
                    } else {
                        return coord;
                    }
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'a', 'h' => coord = coord.move(.West, state.mapgeometry) orelse coord,
                'x', 'j' => coord = coord.move(.South, state.mapgeometry) orelse coord,
                'w', 'k' => coord = coord.move(.North, state.mapgeometry) orelse coord,
                'd', 'l' => coord = coord.move(.East, state.mapgeometry) orelse coord,
                'q', 'y' => coord = coord.move(.NorthWest, state.mapgeometry) orelse coord,
                'e', 'u' => coord = coord.move(.NorthEast, state.mapgeometry) orelse coord,
                'z', 'b' => coord = coord.move(.SouthWest, state.mapgeometry) orelse coord,
                'c', 'n' => coord = coord.move(.SouthEast, state.mapgeometry) orelse coord,
                else => {},
            },
            else => {},
        };
    }
}

pub fn chooseDirection() ?Direction {
    var direction: Direction = .North;

    defer map_win.annotations.clear();
    defer map_win.map.renderFullyW(.Main);

    while (true) {
        map_win.annotations.clear();
        map_win.map.renderFullyW(.Main);

        const maybe_coord = state.player.coord.move(direction, state.mapgeometry);

        if (maybe_coord != null and coordToScreen(maybe_coord.?) != null) {
            const dcoord = coordToScreen(maybe_coord.?).?;
            const char: u21 = switch (direction) {
                .North => '↑',
                .South => '↓',
                .East => '→',
                .West => '←',
                .NorthEast => '↗',
                .NorthWest => '↖',
                .SouthEast => '↘',
                .SouthWest => '↙',
            };
            map_win.annotations.setCell(dcoord.x, dcoord.y, .{ .ch = char, .fg = colors.LIGHT_CONCRETE, .bg = colors.BG, .fl = .{ .wide = true } });
        }

        map_win.map.renderFullyW(.Main);
        display.present();

        drawModalText(colors.CONCRETE, "direction: {}", .{direction});

        var evgen = display.getEvents(null);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return null;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc => return null,
                .Enter => {
                    if (maybe_coord == null) {
                        //drawAlert("Invalid coord!", .{});
                        drawModalText(0xffaaaa, "Invalid direction!", .{});
                    } else {
                        return direction;
                    }
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'a', 'h' => direction = .West,
                'x', 'j' => direction = .South,
                'w', 'k' => direction = .North,
                'd', 'l' => direction = .East,
                'q', 'y' => direction = .NorthWest,
                'e', 'u' => direction = .NorthEast,
                'z', 'b' => direction = .SouthWest,
                'c', 'n' => direction = .SouthEast,
                else => {},
            },
            else => {},
        };
    }
}

pub const LoadingScreen = struct {
    main_con: Console,
    logo_con: *Console,
    text_con: *Console,

    pub const TEXT_CON_HEIGHT = 2;
    pub const TEXT_CON_WIDTH = 28;

    pub fn deinit(self: *@This()) void {
        self.main_con.deinit();
    }
};

pub fn initLoadingScreen() LoadingScreen {
    const win = dimensions(.Whole);
    var win_c: LoadingScreen = undefined;

    const map = RexMap.initFromFile(state.alloc, "data/logo.xp") catch err.wat();
    defer map.deinit();

    win_c.main_con = Console.init(state.alloc, win.width(), win.height());
    win_c.logo_con = Console.initHeap(state.alloc, map.width, map.height + 1); // +1 padding
    win_c.text_con = Console.initHeap(state.alloc, LoadingScreen.TEXT_CON_WIDTH, LoadingScreen.TEXT_CON_HEIGHT);

    const starty = (win.height() / 2) - ((map.height + LoadingScreen.TEXT_CON_HEIGHT + 2) / 2) - 4;

    win_c.logo_con.drawXP(&map, 0, 0, null, false);
    win_c.main_con.addSubconsole(win_c.logo_con, win_c.main_con.centerX(map.width), starty);

    win_c.main_con.addSubconsole(win_c.text_con, win_c.main_con.centerX(LoadingScreen.TEXT_CON_WIDTH), starty + win_c.logo_con.height);

    return win_c;
}

pub fn drawLoadingScreen(loading_win: *LoadingScreen, text_context: []const u8, text: []const u8, percent_done: usize) !void {
    const win = dimensions(.Whole);

    loading_win.text_con.clear();

    var y: usize = 0;
    y += loading_win.text_con.drawTextAt(0, y, text, .{});
    y += loading_win.text_con.drawBarAt(
        0,
        LoadingScreen.TEXT_CON_WIDTH,
        y,
        percent_done,
        100,
        text_context,
        colors.percentageOf(colors.DOBALENE_BLUE, 25),
        colors.DOBALENE_BLUE,
        .{ .detail_type = .Percent },
    );

    loading_win.main_con.renderFully(@as(usize, @intCast(win.startx)), @as(usize, @intCast(win.starty)));

    display.present();
    clearScreen();

    var evgen = display.getEvents(20);
    while (evgen.next()) |ev| switch (ev) {
        .Quit => {
            state.state = .Quit;
            return error.Canceled;
        },
        .Key => |k| switch (k) {
            .CtrlC, .Esc, .Enter => return error.Canceled,
            else => {},
        },
        else => {},
    };
}

pub fn drawLoadingScreenFinish(loading_win: *LoadingScreen) bool {
    const win = dimensions(.Whole);

    loading_win.text_con.clear();

    const text = switch (rng.range(usize, 0, 99)) {
        0...97 => "-- Press any key to begin --",
        98...99 => "-- Press any key to inevitably die --",
        else => err.wat(),
    };

    _ = loading_win.text_con.drawTextAtf(0, 0, "$b{s}$.", .{text}, .{});

    loading_win.main_con.renderFully(@intCast(win.startx), @intCast(win.starty));

    display.present();
    clearScreen();

    if (state.state != .Viewer)
        _ = waitForInput(' ') orelse return false;
    return true;
}

pub fn drawGameOverScreen(scoreinfo: scores.Info) void {
    draw();

    // Delete labels and don't show mob vision areas for the gameover screen
    // Need to draw anyway to ensure drawCapturedDisplay() works right
    map_win.annotations.clear();
    drawMap(&map_win.map, &[_]*Mob{}, state.player.coord);
    map_win.map.renderFullyW(.Main);
    display.present();

    const win_d = dimensions(.Whole);
    var container_c = Console.init(state.alloc, win_d.width(), win_d.height());
    defer container_c.deinit();

    var layer1_c = Console.init(state.alloc, win_d.width(), win_d.height());
    layer1_c.drawCapturedDisplay(1, 1);
    container_c.addSubconsole(&layer1_c, 0, 0);

    const player_dc = coordToScreen(state.player.coord).?;
    for (&DIRECTIONS) |d| if (state.player.coord.move(d, state.mapgeometry)) |nei| {
        if (coordToScreen(nei)) |c| {
            container_c.setCell(c.x, c.y, layer1_c.getCell(c.x, c.y));
            container_c.setCell(c.x + 1, c.y, .{ .fl = .{ .skip = true } });
        }
    };
    container_c.setCell(player_dc.x, player_dc.y, layer1_c.getCell(player_dc.x, player_dc.y));
    container_c.setCell(player_dc.x + 1, player_dc.y, .{ .fl = .{ .skip = true } });

    // TODO: have different border styles for different levels that the player can die on
    // - Border styles would be defined in levelinfo.tsv as strings
    //   - One field that describes the characters
    //   - One field that states whether it'd be inverted or not
    //   - So, this current border would be:
    //     - \t "    ▐▐▐▌▌▌▂▂▂▂▂▂▆▆▆▆▆▆" \t "................######"
    //     - (First four describe the borders)
    // - Higher levels should have more "fancy" border styles
    // - Shrine borders should be somewhat ornate
    // - Laboratory should be dashed lines (see Cogmind achievement art)
    // - Caves should be, uh, more "rough"
    // - Maybe different/special border if player dies from angry night creature syndrome
    // - Different colors for different floors. Concrete for prison, blue for Lab, etc
    // - etc etc etc
    //
    {
        const c = colors.percentageOf(colors.CONCRETE, 20);
        container_c.setCell(player_dc.x - 3, player_dc.y - 1, .{ .ch = '▐', .fg = c });
        container_c.setCell(player_dc.x - 3, player_dc.y + 0, .{ .ch = '▐', .fg = c });
        container_c.setCell(player_dc.x - 3, player_dc.y + 1, .{ .ch = '▐', .fg = c });

        container_c.setCell(player_dc.x + 4, player_dc.y - 1, .{ .ch = '▌', .fg = c });
        container_c.setCell(player_dc.x + 4, player_dc.y + 0, .{ .ch = '▌', .fg = c });
        container_c.setCell(player_dc.x + 4, player_dc.y + 1, .{ .ch = '▌', .fg = c });

        container_c.setCell(player_dc.x - 2, player_dc.y - 2, .{ .ch = '▂', .fg = c });
        container_c.setCell(player_dc.x - 1, player_dc.y - 2, .{ .ch = '▂', .fg = c });
        container_c.setCell(player_dc.x + 0, player_dc.y - 2, .{ .ch = '▂', .fg = c });
        container_c.setCell(player_dc.x + 1, player_dc.y - 2, .{ .ch = '▂', .fg = c });
        container_c.setCell(player_dc.x + 2, player_dc.y - 2, .{ .ch = '▂', .fg = c });
        container_c.setCell(player_dc.x + 3, player_dc.y - 2, .{ .ch = '▂', .fg = c });

        container_c.setCell(player_dc.x - 2, player_dc.y + 2, .{ .ch = '▆', .bg = c, .fg = colors.BG });
        container_c.setCell(player_dc.x - 1, player_dc.y + 2, .{ .ch = '▆', .bg = c, .fg = colors.BG });
        container_c.setCell(player_dc.x + 0, player_dc.y + 2, .{ .ch = '▆', .bg = c, .fg = colors.BG });
        container_c.setCell(player_dc.x + 1, player_dc.y + 2, .{ .ch = '▆', .bg = c, .fg = colors.BG });
        container_c.setCell(player_dc.x + 2, player_dc.y + 2, .{ .ch = '▆', .bg = c, .fg = colors.BG });
        container_c.setCell(player_dc.x + 3, player_dc.y + 2, .{ .ch = '▆', .bg = c, .fg = colors.BG });
    }

    {
        var tmpbuf = StackBuffer(u8, 128).init(null);
        const x = player_dc.x - (24 + 4); // padding + space between @ and text

        tmpbuf.fmt("{s} the Oathbreaker", .{scoreinfo.username.constSlice()});
        _ = container_c.drawTextAtf(x, player_dc.y - 1, "$c{s: >24}", .{tmpbuf.constSlice()}, .{});
        tmpbuf.clear();

        tmpbuf.fmt("at {s}", .{state.levelinfo[scoreinfo.level].name});
        _ = container_c.drawTextAtf(x, player_dc.y + 0, "{s: >24}$.", .{tmpbuf.constSlice()}, .{});
        tmpbuf.clear();

        const s = if (scoreinfo.turns > 1) @as([]const u8, "s") else "";
        tmpbuf.fmt("after {} turn{s}", .{ scoreinfo.turns, s });
        _ = container_c.drawTextAtf(x, player_dc.y + 1, "$b{s: >24}$.", .{tmpbuf.constSlice()}, .{});
        tmpbuf.clear();
    }

    {
        const x = player_dc.x + 6;
        var oy: usize = player_dc.y - 1;
        oy += container_c.drawTextAtf(x, oy, "$c{s}", .{scoreinfo.result}, .{});
        if (state.state == .Lose) {
            if (scoreinfo.slain_by_name.len > 0)
                oy += container_c.drawTextAtf(x, oy, "{s} by a {s}", .{ scoreinfo.slain_str, scoreinfo.slain_by_name.constSlice() }, .{});
            if (scoreinfo.slain_by_captain_name.len > 0)
                oy += container_c.drawTextAtf(x, oy, "$bled by a {s}$.", .{scoreinfo.slain_by_captain_name.constSlice()}, .{});
        }
    }

    {
        const startx = player_dc.x - 24;
        const endx = player_dc.x + 24;
        var oy: usize = player_dc.y + 4;

        // zig fmt: off
        const stats = [_]struct { b: []const u8, v: scores.Stat }{
            .{ .b = "      Foes slain:",      .v = .KillRecord },
            .{ .b = "    Foes stabbed:",      .v = .StabRecord },
            .{ .b = "Inflicted damage:", .v = .DamageInflicted },
            .{ .b = "  Endured damage:",   .v = .DamageEndured },
        };
        // zig fmt: on

        for (stats, 0..) |stat, i| {
            if (i % 2 == 0)
                _ = container_c.drawTextAt(startx, oy, "$c│$.", .{});
            const v = scores.get(stat.v).BatchUsize.total;
            const x = switch (i % 2) {
                0 => startx + 2,
                1 => endx - std.fmt.count("{s} {: >4}", .{ stat.b, v }),
                else => unreachable,
            };
            _ = container_c.drawTextAtf(x, oy, "{s} $o{: >4}$.", .{ stat.b, v }, .{});
            if (i % 2 == 1 or i == stats.len - 1)
                oy += 1;
        }
    }

    // _ = container_c.drawTextAt(player_dc.x - 32, player_dc.y - 4, "$gPress <Enter> to continue.$.", .{});

    var layer1_anim = animationDeath(&layer1_c);

    while (true) {
        _ = layer1_anim.next();
        container_c.renderFully(@intCast(win_d.startx), @intCast(win_d.starty));
        display.present();

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => return,
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .Enter => return,
                else => {},
            },
            .Char => |c| switch (c) {
                ' ' => return,
                else => {},
            },
            else => {},
        };
    }
}

pub fn drawTextScreen(comptime fmt: []const u8, args: anytype) void {
    const mainw = dimensions(.Main);

    const text = std.fmt.allocPrint(state.alloc, fmt, args) catch err.wat();
    defer state.alloc.free(text);

    var con = Console.init(state.alloc, mainw.width(), mainw.height());
    defer con.deinit();

    var y: usize = 0;
    y += con.drawTextAt(0, y, text, .{});

    con.renderFully(@intCast(mainw.startx), @intCast(mainw.starty));

    display.present();
    clearScreen();

    while (true) {
        var evgen = display.getEvents(null);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .Enter => return,
                else => {},
            },
            .Char => |c| switch (c) {
                ' ' => return,
                else => {},
            },
            else => {},
        };
    }
}

pub fn drawMessagesScreen() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const mainw = dimensions(.Main);
    const logw = dimensions(.Log);

    assert(logw.starty > mainw.starty);
    assert(logw.endx == mainw.endx);

    var starty = logw.starty;
    const endy = logw.endy;

    var scroll: usize = 0;

    log_win.main.clearMouseTriggers();

    main: while (true) {
        if (starty > mainw.starty) {
            starty = @max(mainw.starty, starty -| 3);
        }

        // Clear window.
        {
            var y = starty;
            while (y <= endy) : (y += 1)
                _clear_line(mainw.startx, mainw.endx, y);
        }

        const window_height: usize = @intCast(endy - starty - 1);

        scroll = @min(scroll, log_win.main.height -| window_height);

        const first_line = log_win.main.height -| window_height -| scroll;
        const last_line = @min(first_line + window_height, log_win.main.height);
        log_win.main.addMouseTrigger(log_win.main.dimensionsRect(), .Wheel, .{ .Signal = 1 });
        log_win.main.renderAreaAt(@intCast(mainw.startx), @intCast(starty), 0, first_line, log_win.main.width, last_line);

        display.present();

        var evgen = display.getEvents(50);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                break :main;
            },
            .Click => |c| switch (log_win.main.handleMouseEvent(c, .Click)) {
                .Coord, .Signal, .Void => err.wat(),
                .Outside => break :main,
                .Unhandled => {},
            },
            .Wheel => |w| switch (log_win.main.handleMouseEvent(w.c, .Wheel)) {
                .Signal => |s| if (s == 1) {
                    const new: isize = @as(isize, @intCast(scroll)) + w.y;
                    scroll = @intCast(@max(0, new));
                },
                else => {},
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .Enter => break :main,
                else => {},
            },
            .Char => |c| switch (c) {
                'x', 'j' => scroll -|= 1,
                'w', 'k' => scroll += 1,
                'M' => break,
                else => {},
            },
            else => {},
        };
    }

    // FIXME: remove this when visual artifacts between windows are fixed
    clearScreen();
}

pub fn drawPlayerInfoScreen() void {
    pinfo_win.left.addRevealAnimation(.{ .factor = 3, .idelay = 4 });

    const Tab = enum(usize) {
        Stats = 0,
        Statuses = 1,
        Aptitudes = 2,
        Augments = 3,

        pub fn draw(self: @This()) void {
            var iy: usize = 0;
            switch (self) {
                .Stats => {
                    inline for (@typeInfo(Stat).@"enum".fields) |statv| {
                        const stat: Stat = @enumFromInt(statv.value);
                        const stat_val_raw = state.player.stat(stat);
                        const stat_val = utils.SignedFormatter{ .v = stat_val_raw };
                        const stat_val_real: isize = switch (stat) {
                            .Melee => @intCast(combat.chanceOfMeleeLanding(state.player, null)),
                            .Evade => @intCast(combat.chanceOfAttackEvaded(state.player, null)),
                            else => stat_val_raw,
                        };
                        if (stat.showMobStat(state.player, stat_val_raw)) {
                            if (stat.showMobStatFancy(stat_val_raw, stat_val_real)) {
                                const c = if (@as(isize, @intCast(stat_val_real)) < stat_val_raw) @as(u21, 'r') else 'b';
                                iy += pinfo_win.right.drawTextAtf(0, iy, "$c{s: <11}$.  {: >5}{s: >1}    $g(${u}{}{s}$g)$.\n", .{ stat.string(), stat_val, stat.formatAfter(), c, stat_val_real, stat.formatAfter() }, .{});
                            } else {
                                iy += pinfo_win.right.drawTextAtf(0, iy, "$c{s: <11}$.  {: >5}{s: >1}\n", .{ stat.string(), stat_val, stat.formatAfter() }, .{});
                            }
                        }
                    }
                    iy += pinfo_win.right.drawTextAt(0, iy, "\n", .{});
                    inline for (@typeInfo(Resistance).@"enum".fields) |resistancev| {
                        const resist: Resistance = @enumFromInt(resistancev.value);
                        const resist_val = utils.SignedFormatter{ .v = state.player.resistance(resist) };
                        const resist_str = resist.string();
                        iy += pinfo_win.right.drawTextAtf(0, iy, "$c{s: <11}$.  {: >5}%\n", .{ resist_str, resist_val }, .{});
                    }
                    iy += pinfo_win.right.drawTextAt(0, iy, "\n", .{});

                    const repfmt = utils.ReputationFormatter{};
                    if (repfmt.dewIt()) {
                        iy += pinfo_win.right.drawTextAtf(0, iy, "{}", .{repfmt}, .{});
                        iy += 1;
                    }
                },
                .Statuses => {
                    var statuses = state.player.statuses.iterator();
                    while (statuses.next()) |entry| {
                        if (state.player.isUnderStatus(entry.key) == null)
                            continue;
                        iy += pinfo_win.right.drawTextAt(0, iy, _formatStatusInfo(entry.value), .{});
                    }
                    if (iy == 0) {
                        iy += pinfo_win.right.drawTextAt(0, iy, "You have no status effects (yet).\n", .{});
                    }
                },
                .Aptitudes => {
                    const any = for (state.player_upgrades) |upgr| {
                        if (upgr.recieved) break true;
                    } else false;
                    if (any) {
                        iy += pinfo_win.right.drawTextAt(0, iy, "$cAptitudes:$.\n", .{});
                        for (state.player_upgrades) |upgr| if (upgr.recieved) {
                            const name = upgr.upgrade.name();
                            const desc = upgr.upgrade.description();
                            iy += pinfo_win.right.drawTextAtf(0, iy, "- [{s}] {s}\n", .{ name, desc }, .{});
                        };
                    } else {
                        iy += pinfo_win.right.drawTextAt(0, iy, "You have no aptitudes (yet).\n\n", .{});
                        iy += pinfo_win.right.drawTextAt(0, iy, "(As you ascend, you'll gain up to three random aptitudes.)\n", .{});
                    }
                },
                .Augments => {
                    const conjuration: usize = @intCast(state.player.stat(.Conjuration));
                    if (conjuration > 0) {
                        iy = pinfo_win.right.drawTextAtf(0, iy, "$cConjuration:$. $b{}$.", .{conjuration}, .{});

                        var augment_cnt: usize = 0;
                        var augment_buf = StackBuffer(player.ConjAugment, 64).init(null);
                        for (state.player_conj_augments) |aug| if (aug.received) {
                            augment_cnt += 1;
                            augment_buf.append(aug.a) catch err.wat();
                        };

                        std.sort.insertion(player.ConjAugment, augment_buf.slice(), {}, struct {
                            pub fn f(_: void, a: player.ConjAugment, b: player.ConjAugment) bool {
                                return @intFromEnum(a) < @intFromEnum(b);
                            }
                        }.f);

                        var augment_str = StackBuffer(u8, 64).init(null);
                        for (augment_buf.constSlice()) |aug|
                            augment_str.appendSlice(aug.char()) catch err.wat();

                        if (augment_cnt == 0) {
                            iy = pinfo_win.right.drawTextAtf(0, iy, "$cNo augments$.", .{}, .{});
                        } else {
                            iy = pinfo_win.right.drawTextAtf(0, iy, "$cAugments($b{}$c)$.: {s}", .{ augment_cnt, augment_str.constSlice() }, .{});
                        }

                        iy += 1;
                    }
                },
            }
        }
    };

    var tab: usize = @intFromEnum(@as(Tab, .Stats));
    var tab_hover: ?usize = null;
    var tab_changed = true;

    main: while (true) {
        pinfo_win.container.clearLineTo(0, pinfo_win.container.width - 1, 0, .{ .ch = '▀', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
        pinfo_win.container.clearLineTo(0, pinfo_win.container.width - 1, pinfo_win.container.height - 1, .{ .ch = '▄', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });

        pinfo_win.left.clearMouseTriggers();
        var my: usize = 0;
        my += pinfo_win.left.drawTextAt(0, my, "$cPlayer Info$.", .{});
        inline for (@typeInfo(Tab).@"enum".fields) |tabv| {
            const sel = if (tabv.value == tab) "$c>" else "$g ";
            const bg = if (tab_hover != null and tab_hover.? == tabv.value) colors.BG_L else colors.BG;
            pinfo_win.left.clearLine(0, pinfo_win.left.width, my);
            my += pinfo_win.left.drawTextAtf(0, my, "{s} {s}$.", .{ sel, tabv.name }, .{ .bg = bg });
            pinfo_win.left.addClickableLine(.Hover, .{ .RecordElem = &pinfo_win.left });
            pinfo_win.left.addClickableLine(.Click, .{ .Signal = tabv.value });
        }
        pinfo_win.left.highlightMouseArea(colors.BG_L);
        pinfo_win.left.stepRevealAnimation();

        if (tab_changed) {
            pinfo_win.right.clear();
            @as(Tab, @enumFromInt(tab)).draw();
            pinfo_win.right.addRevealAnimation(.{ .factor = 2, .idelay = 1 });
            tab_changed = false;
        }

        pinfo_win.right.stepRevealAnimation();
        pinfo_win.container.renderFullyW(.PlayerInfoModal);
        display.present();

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                break :main;
            },
            .Hover => |c| switch (pinfo_win.container.handleMouseEvent(c, .Hover)) {
                .Coord, .Signal => err.wat(),
                .Void, .Outside, .Unhandled => {},
            },
            .Click => |c| switch (pinfo_win.container.handleMouseEvent(c, .Click)) {
                .Signal => |sig| {
                    tab = sig;
                    tab_hover = null;
                    tab_changed = true;
                },
                .Coord, .Void => err.wat(),
                .Outside => break :main,
                .Unhandled => {},
            },
            .Key => |k| switch (k) {
                .CtrlC, .CtrlG, .Esc => break :main,
                .ArrowDown => if (tab < meta.fields(Tab).len - 1) {
                    tab += 1;
                    tab_changed = true;
                },
                .ArrowUp => {
                    tab -|= 1;
                    tab_changed = true;
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'x', 'j', 'h' => if (tab < meta.fields(Tab).len - 1) {
                    tab += 1;
                    tab_changed = true;
                },
                'w', 'k', 'l' => {
                    tab -|= 1;
                    tab_changed = true;
                },
                else => {},
            },
            else => {},
        };
    }

    // FIXME: remove once all of ui.* is converted to subconsole system and
    // artifacts are auto-cleared
    clearScreen();
}

pub fn drawWizScreen() void {
    // wiz_win.right.addRevealAnimation(.{ .rvtype = .All });

    main: while (true) {
        wiz_win.container.clearLineTo(0, wiz_win.container.width - 1, 0, .{ .ch = '▀', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
        wiz_win.container.clearLineTo(0, wiz_win.container.width - 1, wiz_win.container.height - 1, .{ .ch = '▄', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });

        var y: usize = 0;
        var x: usize = 0;
        var s: u21 = 'a';
        const W = 13;

        inline for (meta.fields(player.WizardFun)) |field| {
            wiz_win.right.clearLine(x, x + W, y);
            _ = wiz_win.right.drawTextAtf(x, y, "$b{u}$g - $.{s}", .{ s, field.name }, .{});
            s += 1;
            y += 1;
            if (y == zap_win.right.height - 1) {
                y = 0;
                x += W + 2;
            }
        }

        wiz_win.container.renderFullyW(.Zap);
        display.present();

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                break :main;
            },
            .Key => |k| switch (k) {
                .CtrlC, .CtrlG, .Esc => break :main,
                .F1 => break :main,
                else => {},
            },
            .Char => |c| switch (c) {
                'a'...'z' => {
                    const sel = c - 'a';
                    inline for (meta.fields(player.WizardFun), 0..) |field, i| {
                        if (sel == i) {
                            player.executeWizardFun(@as(player.WizardFun, @enumFromInt(field.value)));
                            break;
                        }
                    }
                },
                else => {},
            },
            else => {},
        };
    }

    // FIXME: remove once all of ui.* is converted to subconsole system and
    // artifacts are auto-cleared
    clearScreen();
}

pub fn drawZapScreen() void {
    var selected: usize = 0;
    var r_error: ?player.RingError = null;

    zap_win.left.addRevealAnimation(.{ .rvtype = .All });
    zap_win.right.addRevealAnimation(.{ .rvtype = .All });

    main: while (true) {
        zap_win.container.clearLineTo(0, zap_win.container.width - 1, 0, .{ .ch = '▀', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });
        zap_win.container.clearLineTo(0, zap_win.container.width - 1, zap_win.container.height - 1, .{ .ch = '▄', .fg = colors.LIGHT_STEEL_BLUE, .bg = colors.BG });

        zap_win.left.clearMouseTriggers();
        zap_win.right.clearMouseTriggers();

        var ring_count: usize = 0;
        var y: usize = 0;
        var ring_i: usize = 0;
        while (ring_i < Mob.Inventory.RING_SLOTS.len) : (ring_i += 1) {
            zap_win.left.clearLine(0, zap_win.left.width, y);
            if (player.getRingByIndex(ring_i)) |ring| {
                ring_count = ring_i;
                r_error = player.checkRing(selected);
                const arrow = if (selected == ring_i) "$c>" else "$.·";
                const mp_cost_color: u8 = if (state.player.MP < ring.required_MP) 'r' else 'b';
                y += zap_win.left.drawTextAtf(0, y, "{s} {s}$. $g(${u}{}$g MP)$.", .{ arrow, ring.name, mp_cost_color, ring.required_MP }, .{});
                zap_win.left.addClickableLine(.Hover, .{ .RecordElem = &zap_win.left });
                zap_win.left.addClickableText(.Click, .{ .Signal = ring_i });

                if (selected == ring_i) {
                    var ry: usize = 0;
                    const itemdesc = state.descriptions.get((Item{ .Ring = ring }).id().?).?;
                    zap_win.right.clear();
                    if (r_error) |r_err| {
                        ry += zap_win.right.drawTextAtf(0, ry, "$cCannot use$.: $b{s}$.\n\n", .{r_err.text1()}, .{});
                    } else {
                        ry += zap_win.right.drawTextAt(0, ry, "Press $b<Enter>$. to use.\n\n", .{});
                    }
                    ry += zap_win.right.drawTextAt(0, ry, itemdesc, .{});
                }
            } else {
                y += zap_win.left.drawTextAt(0, y, "$g· <none>$.", .{});
                zap_win.left.addClickableLine(.Hover, .{ .RecordElem = &zap_win.left });
                r_error = null;
            }
        }

        const has_no_rings = player.getRingByIndex(selected) == null;

        if (has_no_rings) {
            var ry: usize = 0;
            ry += zap_win.right.drawTextAt(0, ry, "You have no rings.", .{});
            ry += zap_win.right.drawTextAt(0, ry, "\n", .{});
            ry += zap_win.right.drawTextAt(0, ry, "$gHint: rings are usually found in golden enclosures on most (but not all) levels.$.", .{});
        }

        zap_win.left.stepRevealAnimation();
        zap_win.left.highlightMouseArea(colors.BG_L);
        zap_win.right.stepRevealAnimation();
        zap_win.container.renderFullyW(.Zap);

        display.present();

        const oldselected = selected;

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                break :main;
            },
            .Hover => |c| switch (zap_win.container.handleMouseEvent(c, .Hover)) {
                .Coord, .Signal => err.wat(),
                .Void, .Outside, .Unhandled => {},
            },
            .Click => |c| switch (zap_win.container.handleMouseEvent(c, .Click)) {
                .Signal => |sig| selected = sig,
                .Coord, .Void => err.wat(),
                .Outside => break :main,
                .Unhandled => {},
            },
            .Key => |k| switch (k) {
                .CtrlC, .CtrlG, .Esc => break :main,
                .ArrowUp => selected -|= 1,
                .ArrowDown => selected = @min(ring_count, selected + 1),
                .Enter => if (!has_no_rings and r_error == null) {
                    clearScreen();
                    player.beginUsingRing(selected);
                    break :main;
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'w', 'k' => selected -|= 1,
                'x', 'j' => selected = @min(ring_count, selected + 1),
                else => {},
            },
            else => {},
        };

        while (selected > 0 and player.getRingByIndex(selected) == null)
            selected -= 1;

        if (selected != oldselected)
            zap_win.right.addRevealAnimation(.{ .rvtype = .All });
    }

    // FIXME: remove once all of ui.* is converted to subconsole system and
    // artifacts are auto-cleared
    clearScreen();
}

// Examine mode {{{
pub const ExamineTileFocus = enum(usize) { Mob = 0, Surface = 1, Item = 2 };

pub fn drawExamineScreen(starting_focus: ?ExamineTileFocus, start_coord: ?Coord) bool {
    var arena = std.heap.ArenaAllocator.init(state.alloc);
    defer arena.deinit();

    var container = Console.init(state.alloc, MIN_WIDTH, MIN_HEIGHT);
    var log_d = dimensions(.Log);
    var lgg_win = Console.init(state.alloc, log_d.width(), log_d.height());
    var inf_d = dimensions(.PlayerInfo);
    var inf_win = Console.init(state.alloc, inf_d.width(), inf_d.height());
    var map_d = dimensions(.Main);
    var mpp_win = Console.init(state.alloc, map_d.width(), map_d.height());
    var mp3_win = Console.init(state.alloc, map_d.width(), map_d.height());
    mp3_win.default_transparent = true;

    container.addSubconsole(&lgg_win, log_d.startx, log_d.starty);
    container.addSubconsole(&inf_win, inf_d.startx, inf_d.starty);
    container.addSubconsole(&mpp_win, map_d.startx, map_d.starty);
    mpp_win.addSubconsole(&mp3_win, 0, 0);
    mpp_win.addMouseTrigger(mpp_win.dimensionsRect(), .Click, .Coord);
    mpp_win.addMouseTrigger(mpp_win.dimensionsRect(), .Hover, .Coord);
    lgg_win.addMouseTrigger(lgg_win.dimensionsRect(), .Wheel, .{ .Signal = 1 });

    defer container.deinit();

    const MobTileFocus = enum {
        Main,
        Stats,
        Spells,

        pub fn cycle(self: *@This()) void {
            self.* = switch (self.*) {
                .Main => .Stats,
                .Stats => .Spells,
                .Spells => .Main,
            };
        }
    };

    var coord: Coord = start_coord orelse state.player.coord;
    var highlight: ?Coord = null;
    var tile_focus = starting_focus orelse .Mob;
    var mob_tile_focus: MobTileFocus = .Main;
    var tile_focus_set_manually = false;
    var desc_scroll: usize = 0;

    var kbd_s = false;

    const moblist = state.createMobList(false, true, state.player.coord.z, state.alloc);
    defer moblist.deinit();

    var prev_coord = coord;

    while (true) {
        const has_item = state.dungeon.itemsAt(coord).len > 0;
        const has_mons = state.dungeon.at(coord).mob != null;
        const has_surf = state.dungeon.at(coord).surface != null or !mem.eql(u8, state.dungeon.terrainAt(coord).id, "t_default");

        if (!tile_focus_set_manually) {
            const has_something = switch (tile_focus) {
                .Mob => has_mons,
                .Surface => has_surf,
                .Item => has_item,
            };

            if (!has_something) {
                if (has_item) tile_focus = .Item;
                if (has_surf) tile_focus = .Surface;
                if (has_mons) tile_focus = .Mob;
            }
        }

        // Draw side info pane.
        inf_win.clear();
        inf_win.clearMouseTriggers();
        if (state.player.cansee(coord) and has_mons or has_surf or has_item) {
            var y: usize = 0;

            var tabx: usize = 0;
            inline for (meta.fields(ExamineTileFocus), 0..) |field, i| {
                if (i != 0) {
                    _ = inf_win.drawTextAt(tabx, y, " · ", .{});
                    tabx += 3;
                }
                var c: u21 = 'g';
                if (mem.eql(u8, @tagName(tile_focus), field.name))
                    c = 'c';
                _ = inf_win.drawTextAtf(tabx, y, "${u}{s}$.", .{ c, field.name }, .{});
                inf_win.addClickableTextBoth(.{ .Signal = i });
                tabx += field.name.len;
            }
            y += 1;

            //y += inf_win.drawTextAt(0, y, "Press $b<$./$b>$. to switch tabs.\n\n", .{});
            y += inf_win.drawTextAt(0, y, "Switch tabs with $b<$./$b>$..\n\n", .{});

            const linewidth: usize = @intCast(inf_d.endx - inf_d.startx);

            if (tile_focus == .Mob and has_mons) {
                const mob = state.dungeon.at(coord).mob.?;

                // Sanitize mob_tile_focus
                if (mob == state.player) {
                    mob_tile_focus = .Main;
                }

                switch (mob_tile_focus) {
                    .Main => y += _getMonsDescription(&inf_win, y, mob, inf_win.width, arena.allocator()),
                    .Spells => y += _getMonsSpellsDescription(&inf_win, y, mob, inf_win.width),
                    .Stats => y += _getMonsStatsDescription(&inf_win, y, mob, inf_win.width),
                }
            } else if (tile_focus == .Surface and has_surf) {
                if (state.dungeon.at(coord).surface) |surf| {
                    y += _getSurfDescription(&inf_win, y, surf, linewidth);
                } else {
                    y += _getTerrDescription(&inf_win, y, state.dungeon.terrainAt(coord), linewidth);
                }
            } else if (tile_focus == .Item and has_item) {
                y += _getItemDescription(&inf_win, y, state.dungeon.itemsAt(coord).last().?, linewidth);
            }

            // Add keybinding descriptions
            if (tile_focus == .Mob and has_mons and
                state.dungeon.at(coord).mob.? != state.player)
            {
                kbd_s = true;
                const s: []const u8 = switch (mob_tile_focus) {
                    .Main => "stats",
                    .Stats => "abilities",
                    .Spells => "mob",
                };
                y += inf_win.drawTextAtf(0, y, "Press $bs$. to see {s}", .{s}, .{});
                inf_win.addClickableTextBoth(.{ .Signal = 0xFF });
            }

            inf_win.highlightMouseArea(colors.BG_L);
        }

        // Draw description pane.
        if (state.player.cansee(coord)) {
            var descbuf: [4096]u8 = undefined;
            var descbuf_stream = io.fixedBufferStream(&descbuf);
            const writer = descbuf_stream.writer();

            if (tile_focus == .Mob and state.dungeon.at(coord).mob != null) {
                const mob = state.dungeon.at(coord).mob.?;
                if (state.descriptions.get(mob.id)) |mobdesc| {
                    _writerWrite(writer, "{s}", .{mobdesc});
                    _writerWrite(writer, "\n\n", .{});
                }
            }

            if (tile_focus == .Surface) {
                if (state.dungeon.at(coord).surface != null) {
                    const id = state.dungeon.at(coord).surface.?.id();
                    if (state.descriptions.get(id)) |surfdesc| {
                        _writerWrite(writer, "{s}", .{surfdesc});
                        _writerWrite(writer, "\n\n", .{});
                    }
                } else {
                    const id = state.dungeon.terrainAt(coord).id;
                    if (state.descriptions.get(id)) |terraindesc| {
                        _writerWrite(writer, "{s}", .{terraindesc});
                        _writerWrite(writer, "\n\n", .{});
                    }
                }
            }

            if (tile_focus == .Item and state.dungeon.itemsAt(coord).len > 0) {
                if (state.dungeon.itemsAt(coord).data[0].id()) |id|
                    if (state.descriptions.get(id)) |itemdesc| {
                        _writerWrite(writer, "{s}", .{itemdesc});
                        _writerWrite(writer, "\n\n", .{});
                    };
            }

            lgg_win.clear();

            const lasty = lgg_win.drawTextAt(0, 0, descbuf_stream.getWritten(), .{ .skip_lines = desc_scroll });

            if (desc_scroll > 0) {
                _ = lgg_win.drawTextAt(lgg_win.width - 14, 0, " $p-- PgUp --$.", .{});
            }
            if (lasty >= lgg_win.height) {
                _ = lgg_win.drawTextAt(lgg_win.width - 14, lgg_win.height - 1, " $p-- PgDn --$.", .{});
            }
        }

        mpp_win.clear();
        mp3_win.clear();
        drawMap(&mpp_win, moblist.items, coord);

        const dcoord = coordToScreenFromRefpoint(coord, coord).?;
        mp3_win.drawOutlineAround(dcoord, .{ .fg = colors.CONCRETE, .fl = .{ .wide = true } });

        if (highlight) |_highlight| {
            if (coordToScreenFromRefpoint(_highlight, coord)) |hdcoord| {
                mp3_win.drawOutlineAround(hdcoord, .{ .fg = 0xaaaaaa, .fl = .{ .wide = true } });
            }
        }

        // Sometimes if highlight outline and main outline overlap then
        // center coord will be opaqued.
        //
        // Force it to be transparent to prevent this
        mp3_win.setCell(dcoord.x, dcoord.y, .{ .trans = true });
        if (highlight) |_highlight| {
            if (coordToScreenFromRefpoint(_highlight, coord)) |hdcoord| {
                mp3_win.setCell(hdcoord.x, hdcoord.y, .{ .trans = true });
            }
        }

        container.renderFully(0, 0);
        display.present();

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return false;
            },
            .Hover => |c| switch (container.handleMouseEvent(c, .Hover)) {
                .Coord => |screenc| {
                    if (screenCoordToNormal(screenc, coord)) |mapc|
                        highlight = mapc;
                },
                .Signal => err.wat(),
                .Void => {},
                .Outside, .Unhandled => highlight = null,
            },
            .Click => |c| switch (container.handleMouseEvent(c, .Click)) {
                .Coord => |screenc| {
                    if (screenCoordToNormal(screenc, coord)) |mapc|
                        coord = mapc;
                },
                .Signal => |s| switch (s) {
                    0xFF => mob_tile_focus.cycle(),
                    else => {
                        tile_focus_set_manually = true;
                        tile_focus = @enumFromInt(s);
                        if (tile_focus == .Mob) mob_tile_focus = .Main;
                        desc_scroll = 0;
                    },
                },
                .Void, .Outside, .Unhandled => {},
            },
            .Wheel => |w| switch (container.handleMouseEvent(w.c, .Wheel)) {
                .Signal => |s| if (s == 1) {
                    const new = @as(isize, @intCast(desc_scroll)) + w.y * -1;
                    desc_scroll = @as(usize, @intCast(@max(0, new)));
                },
                else => {},
            },
            .Key => |k| switch (k) {
                .CtrlC, .CtrlG, .Esc => return false,
                .PgUp => desc_scroll -|= 1,
                .PgDn => desc_scroll += 1,
                else => {},
            },
            .Char => |c| switch (c) {
                '@' => if (coord.eq(state.player.coord)) drawPlayerInfoScreen(),
                'a', 'h' => coord = coord.move(.West, state.mapgeometry) orelse coord,
                'x', 'j' => coord = coord.move(.South, state.mapgeometry) orelse coord,
                'w', 'k' => coord = coord.move(.North, state.mapgeometry) orelse coord,
                'd', 'l' => coord = coord.move(.East, state.mapgeometry) orelse coord,
                'q', 'y' => coord = coord.move(.NorthWest, state.mapgeometry) orelse coord,
                'e', 'u' => coord = coord.move(.NorthEast, state.mapgeometry) orelse coord,
                'z', 'b' => coord = coord.move(.SouthWest, state.mapgeometry) orelse coord,
                'c', 'n' => coord = coord.move(.SouthEast, state.mapgeometry) orelse coord,
                's' => if (kbd_s) mob_tile_focus.cycle(),
                '>' => {
                    tile_focus_set_manually = true;
                    tile_focus = switch (tile_focus) {
                        .Mob => .Surface,
                        .Surface => .Item,
                        .Item => .Mob,
                    };
                    if (tile_focus == .Mob) mob_tile_focus = .Main;
                    desc_scroll = 0;
                },
                '<' => {
                    tile_focus_set_manually = true;
                    tile_focus = switch (tile_focus) {
                        .Mob => .Item,
                        .Surface => .Mob,
                        .Item => .Surface,
                    };
                    if (tile_focus == .Mob) mob_tile_focus = .Main;
                    desc_scroll = 0;
                },
                else => {},
            },
            else => {},
        };

        // If new coord selected, reset some stuff
        if (!prev_coord.eq(coord)) {
            prev_coord = coord;
            desc_scroll = 0; // Reset scrolling
        }
    }

    return false;
}
// }}}

pub fn drawEscapeMenu() void {
    // FIXME: fix underlying issue then remove this clear();
    //
    // (Too lazy to explain issue, just remove call and see what happens when
    // pressing <F4> then Escape)
    clearScreen();

    const main_c_dim = dimensions(.Main);
    var main_c = Console.init(state.alloc, main_c_dim.width(), main_c_dim.height());
    main_c.addRevealAnimation(.{ .rvtype = .All });
    defer main_c.deinit();

    const menu_c_dim = dimensions(.PlayerInfo);
    var menu_c = Console.init(state.alloc, menu_c_dim.width(), menu_c_dim.height());
    menu_c.addRevealAnimation(.{});
    defer menu_c.deinit();

    const movement = RexMap.initFromFile(state.alloc, "data/keybinds_movement.xp") catch err.wat();
    defer movement.deinit();

    const pad = 11; // Padding between two columns

    var y: usize = 0;
    y += main_c.drawTextAt(0, y, "$c──── Movement ────$.", .{});
    y += 1;
    main_c.drawXP(&movement, 5, y, Rect{ .start = Coord.new(0, 0), .width = 9, .height = 9 }, true);
    main_c.drawXP(&movement, 5 + 18 + pad, y, Rect{ .start = Coord.new(9, 0), .width = 9, .height = 9 }, true);
    y += 11 + 1;
    y += main_c.drawTextAt(5, y, "$g(qweasdzxc movement keys, or hjklyubn for neckbeards.)$.", .{});
    y += 2;
    y += main_c.drawTextAt(0, y, "$c──── Misc ────$.", .{});
    y += 1;
    // Two columns
    y += main_c.drawTextAt(5, y, "$CMessages$.            $bM$.", .{});
    y += main_c.drawTextAt(5, y, "$CInventory$.           $bi$.", .{});
    y += main_c.drawTextAt(5, y, "$CExamine$.             $bv$.", .{});
    y += main_c.drawTextAt(5, y, "$CAbilities$.       $bSPACE$.", .{});
    y -= 4; // Next column
    y += main_c.drawTextAt(5 + 18 + pad, y, "$CSwap weapons$.        $b'$.", .{});
    y += main_c.drawTextAt(5 + 18 + pad, y, "$CPickup item$.         $b,$.", .{});
    y += main_c.drawTextAt(5 + 18 + pad, y, "$CActivate feature$.    $bA$.", .{});

    y += 8;
    y += main_c.drawTextAtf(0, y, "$gOathbreaker v{s} (dist {s})$.", .{
        @import("build_options").release,
        @import("build_options").dist,
    }, .{});
    y += main_c.drawTextAt(0, y, "$gCreated by kiedtl on a Raspberry Pi Zero.$.", .{});
    // TODO: credit tilde.team here

    const Tab = enum(usize) { Continue = 0, @"Player Info" = 1, Quit = 2 };
    var tab: usize = @intFromEnum(@as(Tab, .Continue));

    while (true) {
        menu_c.clearMouseTriggers();
        var my: usize = 0;
        my += menu_c.drawTextAt(0, my, "$cMain Menu$.", .{});
        inline for (@typeInfo(Tab).@"enum".fields) |tabv| {
            const sel = if (tabv.value == tab) "$c>" else "$g ";
            my += menu_c.drawTextAtf(0, my, "{s} {s}$.", .{ sel, tabv.name }, .{});
            menu_c.addClickableText(.Hover, .{ .Signal = tabv.value });
            menu_c.addClickableText(.Click, .{ .Signal = tabv.value });
        }
        menu_c.renderFullyW(.PlayerInfo);
        menu_c.stepRevealAnimation();

        main_c.stepRevealAnimation();
        main_c.renderFullyW(.Main);
        display.present();

        var menu_tab_chosen = false;

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => return,
            .Hover => |c| switch (menu_c.handleMouseEvent(c, .Hover)) {
                .Signal => |sig| tab = sig,
                .Coord, .Void => err.wat(),
                .Outside, .Unhandled => {},
            },
            .Click => |c| switch (menu_c.handleMouseEvent(c, .Click)) {
                .Signal => |sig| {
                    assert(tab == sig);
                    menu_tab_chosen = true;
                },
                .Coord, .Void => err.wat(),
                .Outside, .Unhandled => {},
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .CtrlG => return,
                .Enter => menu_tab_chosen = true,
                .ArrowDown => if (tab < meta.fields(Tab).len - 1) {
                    tab += 1;
                },
                .ArrowUp => if (tab > 0) {
                    tab -= 1;
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'q' => return,
                'x', 'j', 'h' => if (tab < meta.fields(Tab).len - 1) {
                    tab += 1;
                },
                'w', 'k', 'l' => tab -|= 1,
                else => {},
            },
            else => {},
        };

        if (menu_tab_chosen) switch (@as(Tab, @enumFromInt(tab))) {
            .Continue => return,
            .@"Player Info" => drawPlayerInfoScreen(),
            .Quit => {
                if (drawYesNoPrompt("Really abandon this run?", .{})) {
                    state.state = .Quit;
                    return;
                }
            },
        };
    }
}

// Wait for input. Return null if Ctrl+c or escape was pressed, default_input
// if <enter> is pressed ,otherwise the key pressed. Will continue waiting if a
// mouse event or resize event was recieved.
pub fn waitForInput(default_input: ?u8) ?u32 {
    while (true) {
        var evgen = display.getEvents(null);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return null;
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc => return null,
                .Enter => if (default_input) |def| return def else continue,
                else => {},
            },
            .Char => |c| return c,
            else => {},
        };
    }
}

pub fn drawInventoryScreen() bool {
    var container = Console.init(state.alloc, MIN_WIDTH, MIN_HEIGHT);
    var log_d = dimensions(.Log);
    var lgg_win = Console.init(state.alloc, log_d.width(), log_d.height());
    var inf_d = dimensions(.PlayerInfo);
    var inf_win = Console.init(state.alloc, inf_d.width(), inf_d.height());
    var map_d = dimensions(.Main);
    var inv_win = Console.init(state.alloc, map_d.width(), map_d.height());

    container.addSubconsole(&lgg_win, log_d.startx, log_d.starty);
    container.addSubconsole(&inf_win, inf_d.startx, inf_d.starty);
    container.addSubconsole(&inv_win, map_d.startx, map_d.starty);
    lgg_win.addMouseTrigger(lgg_win.dimensionsRect(), .Wheel, .{ .Signal = 1 });

    defer container.deinit();

    const ItemListType = enum { Pack, Equip };

    var desc_scroll: usize = 0;
    var chosen: usize = 0;
    var chosen_itemlist: ItemListType = if (state.player.inventory.pack.len == 0) .Equip else .Pack;
    var y: usize = 0;

    while (true) {
        clearScreen();

        const itemlist_len = if (chosen_itemlist == .Pack) state.player.inventory.pack.len else state.player.inventory.equ_slots.len;
        const chosen_item: ?Item = if (chosen_itemlist == .Pack) state.player.inventory.pack.data[chosen] else state.player.inventory.equ_slots[chosen];

        // Draw list of items
        {
            inv_win.clear();
            var mouse_ctr: usize = 0;

            y = 0;
            y += inv_win.drawTextAt(0, y, "$cInventory:$.", .{});
            for (state.player.inventory.pack.constSlice(), 0..) |item, i| {
                const name = (item.longName() catch err.wat()).constSlice();
                const color = if (i == chosen and chosen_itemlist == .Pack) colors.LIGHT_CONCRETE else colors.GREY;
                const arrow = if (i == chosen and chosen_itemlist == .Pack) ">" else " ";
                y += inv_win.drawTextAtf(0, y, "{s} {s}", .{ arrow, name }, .{ .fg = color });
                inv_win.addClickableTextBoth(.{ .Signal = mouse_ctr });
                mouse_ctr += 1;
            }

            y = 0;
            const startx = inv_win.width - @divTrunc(inv_win.width, 2);
            y += inv_win.drawTextAt(startx, y, "$cEquipment:$.", .{});
            inline for (@typeInfo(Mob.Inventory.EquSlot).@"enum".fields, 0..) |slots_f, i| {
                const slot: Mob.Inventory.EquSlot = @enumFromInt(slots_f.value);
                const arrow = if (i == chosen and chosen_itemlist == .Equip) ">" else "·";
                const color = if (i == chosen and chosen_itemlist == .Equip) colors.LIGHT_CONCRETE else colors.GREY;

                if (state.player.inventory.equipment(slot).*) |item| {
                    const name = (item.longName() catch unreachable).constSlice();
                    y += inv_win.drawTextAtf(startx, y, "{s} {s: >6}: {s}", .{ arrow, slot.name(), name }, .{ .fg = color });
                } else {
                    y += inv_win.drawTextAtf(startx, y, "{s} {s: >6}:", .{ arrow, slot.name() }, .{ .fg = color });
                }
                inv_win.addClickableTextBoth(.{ .Signal = mouse_ctr });
                mouse_ctr += 1;
            }
        }

        var usable = false;
        var throwable = false;
        var upgradable: ?Mob.Inventory.EquSlot = null;

        if (chosen_item != null and itemlist_len > 0) switch (chosen_item.?) {
            .Aux => upgradable = player.isAuxUpgradable(chosen),
            .Consumable => |p| {
                usable = true;
                throwable = p.throwable;
            },
            .Evocable => usable = true,
            .Projectile => throwable = true,
            else => {},
        };

        // Draw item info
        inf_win.clear();
        if (chosen_item != null and itemlist_len > 0) {
            var ii_y = _getItemDescription(&inf_win, 0, chosen_item.?, inf_win.width);

            if (usable) {
                ii_y += inf_win.drawTextAt(0, ii_y, "$b<Enter>$. to use.\n", .{});
                inf_win.addClickableTextBoth(.{ .Signal = 0xF1 });
            }
            if (throwable) {
                ii_y += inf_win.drawTextAt(0, ii_y, "$bt$. to throw.\n", .{});
                inf_win.addClickableTextBoth(.{ .Signal = 0xF2 });
            }
            if (upgradable) |ring_slot| {
                assert(!usable);
                const ind = player.getRingIndexBySlot(ring_slot);
                const ring = player.getRingByIndex(ind).?;
                ii_y += inf_win.drawTextAtf(0, ii_y, "$b<Enter>$. to upgrade with the $oring of {s}$..\n", .{ring.name}, .{});
                inf_win.addClickableTextBoth(.{ .Signal = 0xF3 });
            }
        }

        // Draw item description
        lgg_win.clear();
        if (chosen_item != null) {
            if (itemlist_len > 0) {
                const id = chosen_item.?.id();
                const default_desc = "(Missing description)";
                const desc: []const u8 = if (id) |i_id| state.descriptions.get(i_id) orelse default_desc else default_desc;

                const ending_y = lgg_win.drawTextAt(0, 0, desc, .{ .skip_lines = desc_scroll });

                if (desc_scroll > 0) {
                    _ = lgg_win.drawTextAt(lgg_win.width - 14, 0, " $p-- PgUp --$.", .{});
                }
                if (ending_y >= lgg_win.height) {
                    _ = lgg_win.drawTextAt(lgg_win.width - 14, lgg_win.height - 1, " $p-- PgDn --$.", .{});
                }
            } else {
                _ = lgg_win.drawTextAt(0, 0, "Your inventory is empty.", .{});
            }
        }

        inv_win.highlightMouseArea(colors.BG_L);
        inf_win.highlightMouseArea(colors.BG_L);
        container.renderFully(0, 0);
        display.present();

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return false;
            },
            .Hover => |c| switch (container.handleMouseEvent(c, .Hover)) {
                .Coord, .Signal => err.wat(),
                .Outside, .Unhandled, .Void => {},
            },
            .Click => |c| switch (container.handleMouseEvent(c, .Click)) {
                .Signal => |s| {
                    if (s == 0xF1) {
                        // FIXME: duplicated code here and in Enter handling
                        if (chosen_itemlist == .Pack) {
                            if (itemlist_len > 0)
                                return player.useItem(chosen);
                        } else if (chosen_item) |item| switch (item) {
                            .Weapon => drawTextModal("Bump into enemies to attack.", .{}),
                            .Ring => {
                                const slot: Mob.Inventory.EquSlot = @enumFromInt(chosen);
                                player.beginUsingRing(player.getRingIndexBySlot(slot));
                                return false;
                            },
                            .Aux => if (upgradable) |u| player.upgradeAux(chosen, u),
                            .Cloak => drawTextModal("You're already wearing it, stupid.", .{}),
                            else => {},
                        };
                    } else if (s == 0xF2) {
                        if (throwable and player.throwItem(chosen))
                            return true;
                    } else if (s == 0xF3) {
                        if (upgradable) |u| {
                            player.upgradeAux(chosen, u);
                            return false;
                        }
                    } else if (s >= state.player.inventory.pack.len) {
                        chosen_itemlist = .Equip;
                        chosen = s - state.player.inventory.pack.len;
                    } else {
                        chosen_itemlist = .Pack;
                        chosen = s;
                    }
                },
                .Coord, .Void => err.wat(),
                .Outside, .Unhandled => {},
            },
            .Wheel => |w| switch (container.handleMouseEvent(w.c, .Wheel)) {
                .Signal => |s| if (s == 1) {
                    const new = @as(isize, @intCast(desc_scroll)) + w.y * -1;
                    desc_scroll = @as(usize, @intCast(@max(0, new)));
                },
                else => {},
            },
            .Key => |k| switch (k) {
                .ArrowRight => {
                    chosen_itemlist = .Equip;
                    chosen = 0;
                },
                .ArrowLeft => {
                    chosen_itemlist = .Pack;
                    chosen = 0;
                },
                .ArrowDown => if (chosen < itemlist_len - 1) {
                    chosen += 1;
                },
                .ArrowUp => chosen -|= 1,
                .PgUp => desc_scroll -|= 1,
                .PgDn => desc_scroll += 1,
                .CtrlC, .Esc => return false,
                .Enter => if (chosen_itemlist == .Pack) {
                    if (itemlist_len > 0)
                        return player.useItem(chosen);
                } else if (chosen_item) |item| {
                    switch (item) {
                        .Weapon => drawTextModal("Bump into enemies to attack.", .{}),
                        .Ring => {
                            const slot: Mob.Inventory.EquSlot = @enumFromInt(chosen);
                            player.beginUsingRing(player.getRingIndexBySlot(slot));
                            return false;
                        },
                        .Aux => if (upgradable) |u| player.upgradeAux(chosen, u),
                        .Cloak => drawTextModal("You're already wearing it, stupid.", .{}),
                        else => {},
                    }
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'd' => if (chosen_itemlist == .Pack) {
                    if (itemlist_len > 0)
                        switch (player.dropItem(chosen, true)) {
                            .Success => return true,
                            .Failure => |e| drawTextModal("{s}", .{e}),
                        };
                } else if (chosen_item != null) {
                    switch (player.dropItem(chosen, false)) {
                        .Success => return true,
                        .Failure => |e| drawTextModal("{s}", .{e}),
                    }
                },
                't' => if (chosen_itemlist == .Pack) {
                    if (itemlist_len > 0)
                        if (player.throwItem(chosen)) return true;
                } else {
                    drawTextModal("You can't throw that!", .{});
                },
                'l' => {
                    chosen_itemlist = .Equip;
                    chosen = 0;
                },
                'h' => {
                    chosen_itemlist = .Pack;
                    chosen = 0;
                },
                'j' => if (itemlist_len > 0 and chosen < itemlist_len - 1) {
                    chosen += 1;
                },
                'k' => if (itemlist_len > 0 and chosen > 0) {
                    chosen -= 1;
                },
                else => {},
            },
            else => {},
        };
    }
}

pub fn drawModalText(color: u32, comptime fmt: []const u8, args: anytype) void {
    const wind = dimensions(.Main);

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch err.bug("format error!", .{});
    const str = fbs.getWritten();

    assert(str.len < WIDTH - 4);

    const y = if (state.player.coord.y > (HEIGHT / 2) * 2) wind.starty + 2 else wind.endy - 2;
    const x = 1;

    display.setCell(x, y, .{ .ch = '█', .fg = color, .bg = colors.BG });
    _ = _drawStrf(x + 1, y, wind.endx, " {s} ", .{str}, .{ .bg = colors.percentageOf(color, 30) });
    display.setCell(x + str.len + 3, y, .{ .ch = '█', .fg = color, .bg = colors.BG });

    display.present();
}

pub fn drawAlert(comptime fmt: []const u8, args: anytype) void {
    map_win.drawTextLinef(fmt, args, .{ .fg = colors.PALE_VIOLET_RED });
}

pub fn drawAlertThenLog(comptime fmt: []const u8, args: anytype) void {
    drawAlert(fmt, args);
}

fn _setupTextModal(comptime fmt: []const u8, args: anytype) Console {
    const str = std.fmt.allocPrint(state.alloc, fmt, args) catch err.oom();
    defer state.alloc.free(str);

    const width = if (str.len < 200) @as(usize, 30) else 50;

    var text_height: usize = 0;
    var fibuf = StackBuffer(u8, 4096).init(null);
    var fold_iter = utils.FoldedTextIterator.init(str, width);
    while (fold_iter.next(&fibuf)) |_| text_height += 1;

    var container_c = Console.init(state.alloc, width + 4, text_height + 4);
    var text_c = Console.initHeap(state.alloc, width, text_height);

    container_c.addSubconsole(text_c, 2, 2);

    container_c.clearTo(.{ .bg = colors.ABG });
    container_c.setBorder();
    text_c.clearTo(.{ .bg = colors.ABG });
    _ = text_c.drawTextAt(0, 0, str, .{ .bg = colors.ABG });

    return container_c;
}

pub fn drawTextModalNoInput(comptime fmt: []const u8, args: anytype) void {
    var container_c = _setupTextModal(fmt, args);
    defer container_c.deinit();
    defer clearScreen();

    container_c.renderFully(
        display.width() / 2 - container_c.width / 2,
        display.height() / 2 - container_c.height / 2,
    );
    display.present();
}

pub fn drawTextModal(comptime fmt: []const u8, args: anytype) void {
    var container_c = _setupTextModal(fmt, args);
    const text_c = container_c.subconsoles.items[0].console;

    text_c.addRevealAnimation(.{ .rvtype = .All });
    defer container_c.deinit();
    defer clearScreen();

    while (true) {
        text_c.stepRevealAnimation();
        container_c.renderFully(
            display.width() / 2 - container_c.width / 2,
            display.height() / 2 - container_c.height / 2,
        );
        display.present();

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                return;
            },
            .Click => |c| if (container_c.handleMouseEvent(c, .Click) == .Outside) return,
            .Char, .Key => return,
            else => {},
        };
    }
}

pub fn drawChoicePrompt(comptime fmt: []const u8, args: anytype, options: []const []const u8) ?usize {
    const W_WIDTH = 30;
    const HINT = "$GUse movement keys to select a choice.$.";

    assert(options.len > 0);

    const str = std.fmt.allocPrint(state.alloc, fmt, args) catch err.oom();
    defer state.alloc.free(str);

    var text_height: usize = 0;
    var fibuf = StackBuffer(u8, 4096).init(null);
    var fold_iter = utils.FoldedTextIterator.init(str, W_WIDTH);
    while (fold_iter.next(&fibuf)) |_| text_height += 1;

    var container_c = Console.init(state.alloc, W_WIDTH + 4, text_height + 4 + options.len + 2);
    var text_c = Console.init(state.alloc, W_WIDTH, text_height);
    var options_c = Console.init(state.alloc, W_WIDTH, options.len);
    var hint_c = Console.init(state.alloc, W_WIDTH, 2);
    var hint_used = false;

    container_c.addSubconsole(&text_c, 2, 2);
    container_c.addSubconsole(&options_c, 2, 2 + text_height + 1);

    container_c.clearTo(.{ .bg = colors.ABG });
    container_c.setBorder();
    text_c.clearTo(.{ .bg = colors.ABG });
    text_c.addRevealAnimation(.{ .rvtype = .All });
    _ = text_c.drawTextAt(0, 0, str, .{ .bg = colors.ABG });

    defer if (!hint_used) hint_c.deinit();
    defer container_c.deinit();

    defer clearScreen();

    var chosen: usize = 0;
    var cancelled = false;

    main: while (true) {
        var y: usize = 0;
        options_c.clearTo(.{ .bg = colors.ABG });
        options_c.clearMouseTriggers();
        for (options, 0..) |option, i| {
            const ind = if (chosen == i) ">" else "-";
            const color = if (chosen == i) colors.LIGHT_CONCRETE else colors.GREY;
            y += options_c.drawTextAtf(0, y, "{s} {s}", .{ ind, option }, .{ .fg = color, .bg = colors.ABG });
            options_c.addClickableText(.Hover, .{ .Signal = i });
            options_c.addClickableText(.Click, .{ .Signal = i });
        }

        text_c.stepRevealAnimation();
        container_c.renderFully(
            display.width() / 2 - container_c.width / 2,
            display.height() / 2 - container_c.height / 2,
        );
        display.present();

        var evgen = display.getEvents(FRAMERATE);
        while (evgen.next()) |ev| switch (ev) {
            .Quit => {
                state.state = .Quit;
                cancelled = true;
                break :main;
            },
            .Hover => |c| switch (container_c.handleMouseEvent(c, .Hover)) {
                .Signal => |sig| chosen = sig,
                .Coord, .Void => err.wat(),
                .Outside, .Unhandled => {},
            },
            .Click => |c| switch (container_c.handleMouseEvent(c, .Click)) {
                .Signal => |sig| {
                    chosen = sig;
                    break :main;
                },
                .Coord, .Void => err.wat(),
                .Unhandled => {},
                .Outside => break :main,
            },
            .Key => |k| switch (k) {
                .CtrlC, .Esc, .CtrlG => {
                    cancelled = true;
                    break :main;
                },
                .Enter => break :main,
                .ArrowDown => if (chosen < options.len - 1) {
                    chosen += 1;
                },
                .ArrowUp => if (chosen > 0) {
                    chosen -= 1;
                },
                else => {},
            },
            .Char => |c| switch (c) {
                'q' => {
                    cancelled = true;
                    break :main;
                },
                'x', 'j', 'h' => if (chosen < options.len - 1) {
                    chosen += 1;
                },
                'w', 'k', 'l' => if (chosen > 0) {
                    chosen -= 1;
                },
                '0'...'9' => {
                    const num: usize = c - '0';
                    if (num < options.len) {
                        chosen = num;
                    }
                },
                else => {
                    if (!hint_used) {
                        hint_used = true;
                        container_c.changeHeight(container_c.height + 2 + 1);
                        container_c.clearTo(.{ .bg = colors.ABG });
                        container_c.setBorder();
                        container_c.addSubconsole(&hint_c, 2, 2 + text_height + 1 + options.len + 1);
                        hint_c.clearTo(.{ .bg = colors.ABG });
                        _ = hint_c.drawTextAt(0, 0, HINT, .{ .bg = colors.ABG });
                    }
                },
            },
            else => {},
        };
    }

    return if (cancelled) null else chosen;
}

pub fn drawYesNoPrompt(comptime fmt: []const u8, args: anytype) bool {
    Animation.apply(.{ .PopChar = .{ .coord = state.player.coord, .char = '?', .delay = 120 } });

    const r = (drawChoicePrompt(fmt, args, &[_][]const u8{ "No", "Yes" }) orelse 0) == 1;
    if (!r) state.message(.Unimportant, "Cancelled.", .{});
    return r;
}

pub fn drawContinuePrompt(comptime fmt: []const u8, args: anytype) void {
    state.message(.Info, fmt, args);
    _ = drawChoicePrompt(fmt, args, &[_][]const u8{"Press $b<Enter>$. to continue."});
}

pub fn drawItemChoicePrompt(comptime fmt: []const u8, args: anytype, items: []const Item) ?usize {
    assert(items.len > 0); // This should have been handled previously.

    // A bit messy.
    var namebuf = std.ArrayList([]const u8).init(state.alloc);
    defer {
        for (namebuf.items) |str| state.alloc.free(str);
        namebuf.deinit();
    }

    for (items) |item| {
        const itemname = item.longName() catch err.wat();
        const string = state.alloc.alloc(u8, itemname.len) catch err.wat();
        std.mem.copy(u8, string, itemname.constSlice());
        namebuf.append(string) catch err.wat();
    }

    return drawChoicePrompt(fmt, args, namebuf.items);
}

fn _evToMEvType(ev: display.Event) Console.MouseTrigger.Kind {
    return switch (ev) {
        .Click => .Click,
        .Hover => .Hover,
        .Wheel => .Wheel,
        else => err.wat(),
    };
}

// Animations {{{

pub const CellAnimation = struct {
    kind: Kind,

    // Options
    //
    // Not constant, can also be used as state by poorly-written animations :P
    interval: usize,

    // State, used internally
    lifetime: usize = 0,
    ctr: usize = 0, // Only incremented if lifetime % interval == 0

    pub const Kind = union(enum) {
        RotateCells: struct {
            cells: StackBuffer(display.Cell, 4),

            pub fn get(self: *@This(), anim: *CellAnimation) display.Cell {
                var c = self.cells.slice()[anim.ctr % self.cells.len];
                c.fl.wide = true;
                return c;
            }
        },
    };

    pub fn get(self: *CellAnimation) display.Cell {
        return switch (self.kind) {
            .RotateCells => |*r| r.get(self),
        };
    }

    pub fn step(self: *CellAnimation) void {
        self.lifetime += 1;
        if (self.lifetime % self.interval == 0)
            self.ctr += 1;
    }
};

pub const Animation = union(enum) {
    PopChar: struct {
        coord: Coord,
        char: u32,
        fg: u32 = colors.LIGHT_CONCRETE,
        delay: usize = 80,
    },
    BlinkChar: struct {
        coords: []const Coord,
        char: u32,
        fg: ?u32 = null,
        delay: usize = 170,
        repeat: usize = 1,
    },
    EncircleChar: struct {
        coord: Coord,
        char: u32,
        fg: u32,
    },
    TraverseLine: struct {
        start: Coord,
        end: Coord,
        extra: usize = 0,
        char: u32,
        fg: ?u32 = null,
        path_char: ?u32 = null,
    },
    // Used for elec bolt.
    //
    // TODO: merge with TraverseLine?
    AnimatedLine: struct {
        approach: ?usize = null,
        start: Coord,
        end: Coord,
        chars: []const u8,
        fg: u32,
        bg: ?u32,
        bg_mix: ?f64,
    },
    Particle: struct {
        name: []const u8,
        coord: Coord,
        target: union(enum) {
            C: Coord,
            L: []const Coord,
            I: isize,
            Z: usize,
        },
    },

    pub const ELEC_LINE_CHARS = "AEFHIKLMNTYZ13457*-=+~?!@#%&";
    pub const ELEC_LINE_FG = 0x9fefff;
    pub const ELEC_LINE_BG = 0x8fdfff;
    pub const ELEC_LINE_MIX = 0.02;

    pub fn blinkMob(list: []const *Mob, char: u32, fg: ?u32, opts: struct {
        repeat: usize = 1,
        delay: usize = 170,
    }) void {
        var coords = StackBuffer(Coord, 128).init(null);
        for (list) |mob| {
            var gen = mob.areaRect().iter();
            while (gen.next()) |mobcoord|
                coords.append(mobcoord) catch err.wat();
        }
        (Animation{ .BlinkChar = .{
            .coords = coords.constSlice(),
            .char = char,
            .fg = fg,
            .repeat = opts.repeat,
            .delay = opts.delay,
        } }).apply();
    }

    pub fn blink(coords: []const Coord, char: u32, fg: ?u32, opts: struct {
        repeat: usize = 1,
        delay: usize = 170,
    }) Animation {
        return Animation{ .BlinkChar = .{
            .coords = coords,
            .char = char,
            .fg = fg,
            .repeat = opts.repeat,
            .delay = opts.delay,
        } };
    }

    pub fn apply(self: Animation) void {
        if (state.state == .Viewer)
            return;

        drawNoPresent();
        map_win.animations.clear();

        state.player.tickFOV();

        switch (self) {
            .PopChar => |anim| {
                const dcoord = coordToScreen(anim.coord) orelse return;
                const old = map_win.map.getCell(dcoord.x, dcoord.y);

                map_win.animations.setCell(dcoord.x, dcoord.y, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG, .fl = .{ .wide = true } });
                map_win.map.renderFullyW(.Main);
                display.present();

                std.Thread.sleep(anim.delay * 1_000_000);

                map_win.animations.setCell(dcoord.x, dcoord.y, old);
                map_win.animations.setCell(dcoord.x - 2, dcoord.y - 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG, .fl = .{ .wide = true } });
                map_win.animations.setCell(dcoord.x + 2, dcoord.y - 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG, .fl = .{ .wide = true } });
                map_win.animations.setCell(dcoord.x - 2, dcoord.y + 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG, .fl = .{ .wide = true } });
                map_win.animations.setCell(dcoord.x + 2, dcoord.y + 1, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG, .fl = .{ .wide = true } });

                map_win.map.renderFullyW(.Main);
                display.present();

                std.Thread.sleep(anim.delay * 1_000_000);
            },
            .BlinkChar => |anim| {
                assert(anim.coords.len < 256); // XXX: increase if necessary
                var old_cells = StackBuffer(display.Cell, 256).init(null);
                var coords = StackBuffer(Coord, 256).init(null);
                for (anim.coords) |coord| {
                    if (!state.player.cansee(coord)) {
                        continue;
                    }
                    if (coordToScreen(coord)) |dcoord| {
                        coords.append(coord) catch err.wat();
                        old_cells.append(map_win.map.getCell(dcoord.x, dcoord.y)) catch err.wat();
                    }
                }

                if (coords.len == 0) {
                    // Player can't see any coord, bail out
                    return;
                }

                var ctr: usize = anim.repeat;
                while (ctr > 0) : (ctr -= 1) {
                    for (coords.constSlice(), 0..) |coord, i| {
                        const dcoord = coordToScreen(coord).?;
                        const old = old_cells.constSlice()[i];
                        map_win.animations.setCell(dcoord.x, dcoord.y, .{ .ch = anim.char, .fg = anim.fg orelse old.fg, .bg = colors.BG, .fl = .{ .wide = true } });
                    }

                    map_win.map.renderFullyW(.Main);
                    display.present();
                    // std.Thread.sleep(anim.delay * 1_000_000);
                    drawAnimationNoPresentTimeout(anim.delay);

                    for (coords.constSlice(), 0..) |coord, i| if (state.player.cansee(coord)) {
                        const dcoord = coordToScreen(coord).?;
                        const old = old_cells.constSlice()[i];
                        map_win.animations.setCell(dcoord.x, dcoord.y, old);
                    };

                    if (ctr > 1) {
                        display.present();
                        std.Thread.sleep(anim.delay * 1_000_000);
                    }
                }
            },
            .EncircleChar => |anim| {
                const directions = [_]Direction{ .NorthWest, .North, .NorthEast, .East, .SouthEast, .South, .SouthWest, .West, .NorthWest, .North, .NorthEast };
                for (&directions) |d| if (anim.coord.move(d, state.mapgeometry)) |neighbor| {
                    if (coordToScreen(neighbor)) |dneighbor| {
                        const old = map_win.map.getCell(dneighbor.x, dneighbor.y);

                        map_win.animations.setCell(dneighbor.x, dneighbor.y, .{ .ch = anim.char, .fg = anim.fg, .bg = colors.BG, .fl = .{ .wide = true } });
                        map_win.map.renderFullyW(.Main);
                        display.present();

                        std.Thread.sleep(90_000_000);

                        map_win.animations.setCell(dneighbor.x, dneighbor.y, old);
                        map_win.map.renderFullyW(.Main);
                        display.present();
                    }
                };
            },
            .TraverseLine => |anim| {
                const line = anim.start.drawLine(anim.end, state.mapgeometry, anim.extra);
                for (line.constSlice()) |coord| {
                    if (!state.player.cansee(coord)) {
                        continue;
                    }

                    const dcoord = coordToScreen(coord) orelse continue;
                    const old = map_win.map.getCell(dcoord.x, dcoord.y);

                    map_win.animations.setCell(dcoord.x, dcoord.y, .{ .ch = anim.char, .fg = anim.fg orelse old.fg, .bg = colors.BG, .fl = .{ .wide = true } });
                    map_win.map.renderFullyW(.Main);
                    display.present();

                    std.Thread.sleep(80_000_000);

                    if (anim.path_char) |path_char| {
                        map_win.animations.setCell(dcoord.x, dcoord.y, .{ .ch = path_char, .fg = colors.CONCRETE, .bg = old.bg, .fl = .{ .wide = true } });
                    } else {
                        map_win.animations.setCell(dcoord.x, dcoord.y, old);
                    }

                    map_win.map.renderFullyW(.Main);
                    display.present();
                }
            },
            .AnimatedLine => |anim| {
                const line = anim.start.drawLine(anim.end, state.mapgeometry, 0);

                var animated_len: usize = if (anim.approach != null) 1 else line.len;
                var animated: []const Coord = line.data[0..animated_len];

                const iters: usize = 15;
                var counter: usize = iters;
                while (counter > 0) : (counter -= 1) {
                    for (animated) |coord| {
                        if (!state.player.cansee(coord)) {
                            continue;
                        }

                        const dcoord = coordToScreen(coord) orelse continue;
                        const old = map_win.map.getCell(dcoord.x, dcoord.y);

                        const special = coord.eq(anim.start) or coord.eq(anim.end);

                        const char = if (special) old.ch else rng.chooseUnweighted(u8, anim.chars);
                        const fg = if (special) old.fg else colors.percentageOf(anim.fg, counter * 100 / (iters / 2));

                        const bg = if (anim.bg) |color|
                            colors.mix(
                                old.bg,
                                colors.percentageOf(color, counter * 100 / iters),
                                anim.bg_mix.?,
                            )
                        else
                            colors.BG;

                        map_win.animations.setCell(dcoord.x, dcoord.y, .{ .ch = char, .fg = fg, .bg = bg, .fl = .{ .wide = true } });
                    }

                    map_win.map.renderFullyW(.Main);
                    display.present();
                    std.Thread.sleep(40_000_000);

                    if (anim.approach != null and animated_len < line.len) {
                        animated_len = @min(line.len, animated_len + anim.approach.?);
                        animated = line.data[0..animated_len];
                    }
                }
            },
            .Particle => |anim| {
                var ctx: janet.c.Janet = undefined;
                if (anim.target == .L) {
                    ctx = janet.callFunction("animation-init", .{
                        anim.coord,                          anim.target.L,
                        state.player.coord.x -| MAP_WIDTH_R, state.player.coord.y -| MAP_HEIGHT_R,
                        MAP_WIDTH_R * 2,                     MAP_HEIGHT_R * 2,
                        anim.name,
                    }) catch err.wat();
                } else {
                    const target = switch (anim.target) {
                        .C => |c| c,
                        .I => |n| Coord.new(anim.coord.x, anim.coord.y + @as(usize, @intCast(n))),
                        .Z => |n| Coord.new(anim.coord.x, anim.coord.y + n),
                        .L => unreachable,
                    };
                    ctx = janet.callFunction("animation-init", .{
                        anim.coord,                          target,
                        state.player.coord.x -| MAP_WIDTH_R, state.player.coord.y -| MAP_HEIGHT_R,
                        MAP_WIDTH_R * 2,                     MAP_HEIGHT_R * 2,
                        anim.name,
                    }) catch |e| {
                        err.ensure(false, "Could not load particle effect {s}: {}", .{
                            anim.name, e,
                        }) catch {};
                        return;
                    };
                }

                // FIXME: use framerate (will require adjustment of all particle
                // effects)
                const WAIT_PERIOD = 50_000_000;

                var last_tick_time = std.time.nanoTimestamp();
                var j_particles = janet.callFunction("animation-tick", .{ ctx, 0 }) catch err.wat();
                var were_any_visible = true;
                var tick: usize = 1;
                while (tick < 200) : (tick += 1) {
                    if (were_any_visible) {
                        const time_since_last_sleep = @as(u64, @intCast(std.time.nanoTimestamp() - last_tick_time));
                        std.Thread.sleep(WAIT_PERIOD -| time_since_last_sleep);
                    }

                    last_tick_time = std.time.nanoTimestamp();
                    were_any_visible = false;

                    drawAnimations();
                    map_win.map.renderFullyW(.Main);
                    display.present();

                    map_win.animations.clear();

                    const particles = janet.c.janet_unwrap_array(j_particles).*;
                    if (particles.count == 0) {
                        break;
                    }
                    var i: usize = 0;
                    while (i < @as(usize, @intCast(particles.count))) : (i += 1) {
                        const particle = janet.c.janet_unwrap_array(particles.data[i]).*;
                        const p_tile_str = janet.c.janet_unwrap_string(particle.data[0]);
                        const p_tile = std.unicode.utf8Decode(p_tile_str[0..mem.len(p_tile_str)]) catch 'X';
                        const p_fg: u32 = @intCast(janet.c.janet_unwrap_integer(particle.data[1]));
                        const p_bg: u32 = @intCast(janet.c.janet_unwrap_integer(particle.data[2]));
                        const p_bg_mix = janet.c.janet_unwrap_number(particle.data[3]);
                        const p_x: usize = @intCast(janet.c.janet_unwrap_integer(particle.data[4]));
                        const p_y: usize = @intCast(janet.c.janet_unwrap_integer(particle.data[5]));
                        const p_need_los = janet.c.janet_unwrap_number(particle.data[6]);
                        const p_need_nonwall = janet.c.janet_unwrap_boolean(particle.data[7]);
                        const p_coord = Coord.new2(state.player.coord.z, p_x, p_y);
                        const p_dcoord = coordToScreen(Coord.new(p_x, p_y)) orelse continue;
                        const p_out_of_map = p_coord.x >= WIDTH or p_coord.y >= HEIGHT;

                        const cansee = !p_out_of_map and state.player.cansee(p_coord);

                        // XXX: this could be a switch statement, but it causes Zig 0.9.1 to segfault
                        if ((!cansee and p_need_los == 1) or (cansee and p_need_los == -1))
                            continue;

                        if (p_need_nonwall == 1 and (p_out_of_map or state.dungeon.at(p_coord).type == .Wall))
                            continue;

                        const mapcell = map_win.map.getCell(p_dcoord.x, p_dcoord.y);
                        map_win.animations.setCell(p_dcoord.x, p_dcoord.y, .{ .ch = p_tile, .fg = p_fg, .bg = colors.mix(mapcell.bg, p_bg, p_bg_mix), .fl = .{ .wide = true } });
                        were_any_visible = true;
                    }
                    j_particles = janet.callFunction("animation-tick", .{ ctx, tick }) catch err.wat();
                }
            },
        }

        map_win.animations.clear();
        draw();
    }
};

pub const AnimationRevealUnreveal = struct {
    args: RevealAnimationArgs,
    stage: union(enum) {
        a: AnimationReveal,
        b: usize,
        c: AnimationReveal,
    },

    pub fn next(self: *@This()) ?void {
        switch (self.stage) {
            .a => |*iter| {
                if (iter.next() == null)
                    self.stage = .{ .b = self.args.opts.rv_unrv_delay };
            },
            .b => |*ctr| {
                ctr.* -= 1;
                if (ctr.* == 0) {
                    var cargs = self.args;
                    cargs.opts.reverse = true;
                    self.stage = .{ .c = animationReveal(cargs) };
                }
            },
            .c => |*iter| {
                if (iter.next() == null)
                    return null;
            },
        }

        return {};
    }
};

pub fn animationRevealUnreveal(args: RevealAnimationArgs) AnimationRevealUnreveal {
    return .{
        .args = args,
        .stage = .{ .a = animationReveal(args) },
    };
}

// pub fn animationRevealUnreveal(ctx: *GeneratorCtx(void), args: RevealAnimationArgs) void {
//     var a = animationReveal(args);
//     while (a.next()) |_| ctx.yield(.{});

//     var b = args.opts.rv_unrv_delay;
//     while (b > 0) : (b -= 1) ctx.yield(.{});

//     var cargs = args;
//     cargs.opts.reverse = true;
//     var c = animationReveal(cargs);
//     while (c.next()) |_| ctx.yield(.{});

//     ctx.finish();
// }

pub const RevealAnimationOpts = struct {
    factor: usize = 3,
    ydelay: usize = 3,
    idelay: usize = 2,
    rvtype: enum { TopDown, All } = .TopDown,
    reverse: bool = false,
    rv_unrv_delay: usize = 100,
};

pub const RevealAnimationArgs = struct {
    main_layer: *Console,
    anim_layer: *Console,
    opts: RevealAnimationOpts = .{},
};

pub const AnimationReveal = struct {
    args: RevealAnimationArgs,
    revealctrs: [128]usize = [_]usize{0} ** 128,
    i: usize = 0,
    did_anything: bool = false,

    pub fn _resetAnimLayer(self: *@This()) void {
        const args = &self.args;

        var y: usize = 0;
        while (y < args.main_layer.height) : (y += 1) {
            var x: usize = 0;
            while (x < args.main_layer.width) : (x += 1) {
                if (!args.main_layer.getCell(x, y).fl.skip and
                    args.main_layer.getCell(x, y).ch != ' ' and
                    args.anim_layer.getCell(x, y).trans and
                    self.revealctrs[y] != 0)
                {
                    args.anim_layer.setCell(x, y, args.main_layer.getCell(x, y));
                    if (args.opts.reverse) {
                        args.anim_layer.grid[args.main_layer.width * y + x].trans = false;
                    } else {
                        args.anim_layer.grid[args.main_layer.width * y + x].ch = ' ';
                        args.anim_layer.grid[args.main_layer.width * y + x].sch = null;
                    }
                }
            }
        }
    }

    pub fn next(self: *@This()) ?void {
        const args = self.args;

        self._resetAnimLayer();
        self.did_anything = false;

        var y: usize = 0;
        while (y < args.anim_layer.height) : (y += 1) {
            if (self.revealctrs[y] == 0)
                continue;
            self.did_anything = true;
            if (args.opts.rvtype != .All and 1 + (self.i / args.opts.idelay) < y + args.opts.ydelay)
                continue;
            var x: usize = 0;
            while (x < args.anim_layer.width) : (x += 1) {
                if (args.opts.reverse) {
                    if (self.revealctrs[y] == 2 * args.opts.factor) {
                        args.anim_layer.grid[args.main_layer.width * y + x].ch = '⠿';
                    } else if (self.revealctrs[y] == 1 * args.opts.factor) {
                        args.anim_layer.grid[args.main_layer.width * y + x].ch = '·';
                    } else if (self.revealctrs[y] == 1) {
                        args.anim_layer.grid[args.main_layer.width * y + x].ch = ' ';
                        args.anim_layer.grid[args.main_layer.width * y + x].sch = null;
                    }
                } else {
                    if (self.revealctrs[y] == 2 * args.opts.factor) {
                        args.anim_layer.grid[args.main_layer.width * y + x].ch = '·';
                    } else if (self.revealctrs[y] == 1 * args.opts.factor) {
                        args.anim_layer.grid[args.main_layer.width * y + x].ch = '⠿';
                    } else if (self.revealctrs[y] == 1) {
                        args.anim_layer.setCell(x, y, .{ .trans = true });
                    }
                }
            }
            self.revealctrs[y] -= 1;
        }

        if (!self.did_anything)
            return null;

        self.i += 1;
        return {};
    }
};

pub fn animationReveal(args: RevealAnimationArgs) AnimationReveal {
    var self = AnimationReveal{ .args = args };
    for (&self.revealctrs) |*c| c.* = 2 * args.opts.factor;
    return self;
}

// pub fn animationReveal(ctx: *GeneratorCtx(void), args: RevealAnimationArgs) void {
//     const S_resetAnimLayer = struct {
//         pub fn f(_args: RevealAnimationArgs, revealctrs: []const usize) void {
//             var y: usize = 0;
//             while (y < _args.main_layer.height) : (y += 1) {
//                 var x: usize = 0;
//                 while (x < _args.main_layer.width) : (x += 1) {
//                     if (!_args.main_layer.getCell(x, y).fl.skip and
//                         _args.main_layer.getCell(x, y).ch != ' ' and
//                         _args.anim_layer.getCell(x, y).trans and
//                         revealctrs[y] != 0)
//                     {
//                         _args.anim_layer.setCell(x, y, _args.main_layer.getCell(x, y));
//                         if (_args.opts.reverse) {
//                             _args.anim_layer.grid[_args.main_layer.width * y + x].trans = false;
//                         } else {
//                             _args.anim_layer.grid[_args.main_layer.width * y + x].ch = ' ';
//                             _args.anim_layer.grid[_args.main_layer.width * y + x].sch = null;
//                         }
//                     }
//                 }
//             }
//         }
//     }.f;

//     var revealctrs = [_]usize{0} ** 128;
//     for (&revealctrs) |*c| c.* = 2 * args.opts.factor;

//     S_resetAnimLayer(args, &revealctrs);

//     var i: usize = 0;
//     var did_anything = false;
//     while (true) : (i += 1) {
//         S_resetAnimLayer(args, &revealctrs);
//         did_anything = false;
//         var y: usize = 0;
//         while (y < args.anim_layer.height) : (y += 1) {
//             if (revealctrs[y] == 0)
//                 continue;
//             did_anything = true;
//             if (args.opts.rvtype != .All and 1 + (i / args.opts.idelay) < y + args.opts.ydelay)
//                 continue;
//             var x: usize = 0;
//             while (x < args.anim_layer.width) : (x += 1) {
//                 if (args.opts.reverse) {
//                     if (revealctrs[y] == 2 * args.opts.factor) {
//                         args.anim_layer.grid[args.main_layer.width * y + x].ch = '⠿';
//                     } else if (revealctrs[y] == 1 * args.opts.factor) {
//                         args.anim_layer.grid[args.main_layer.width * y + x].ch = '·';
//                     } else if (revealctrs[y] == 1) {
//                         args.anim_layer.grid[args.main_layer.width * y + x].ch = ' ';
//                         args.anim_layer.grid[args.main_layer.width * y + x].sch = null;
//                     }
//                 } else {
//                     if (revealctrs[y] == 2 * args.opts.factor) {
//                         args.anim_layer.grid[args.main_layer.width * y + x].ch = '·';
//                     } else if (revealctrs[y] == 1 * args.opts.factor) {
//                         args.anim_layer.grid[args.main_layer.width * y + x].ch = '⠿';
//                     } else if (revealctrs[y] == 1) {
//                         args.anim_layer.setCell(x, y, .{ .trans = true });
//                     }
//                 }
//             }
//             revealctrs[y] -= 1;
//         }
//         if (!did_anything)
//             break;
//         ctx.yield({});
//     }

//     ctx.finish();
// }

pub const AnimationDeath = struct {
    console: *Console,
    pdc: Coord,
    pdci: CoordIsize,
    rays: StackBuffer(Ray, 360),

    i: usize,
    z: isize,
    m: usize,

    const Ray = struct {
        c: display.Cell,
        x: f64,
        y: f64,
        speed: f64 = 1.0,
        orig: CoordIsize,
        dead: bool = false,

        pub fn init(x: f64, y: f64) @This() {
            const xr: isize = @intFromFloat(math.round(x));
            const yr: isize = @intFromFloat(math.round(y));
            return .{ .c = .{ .trans = true }, .x = x, .y = y, .orig = CoordIsize.new(xr, yr) };
        }

        pub fn move(ray: *@This(), angle: usize, f: f64) void {
            ray.x -= math.sin(@as(f64, @floatFromInt(angle)) * math.pi / 180.0) * f;
            ray.y -= math.cos(@as(f64, @floatFromInt(angle)) * math.pi / 180.0) * f;
        }

        pub fn isValid(ray: *@This(), w: usize, h: usize) bool {
            if (!ray.dead and ray.x > 0 and ray.y > 0) {
                const x: usize = @intFromFloat(math.round(ray.x));
                const y: usize = @intFromFloat(math.round(ray.y));
                if (x < w and y < h) return true;
            }
            return false;
        }
    };

    pub fn next(self: *@This()) ?void {
        if (self.i == self.m) {
            self.console.clearTo(.{ .trans = true });
            return null;
        }

        const pdc = self.pdc;
        const pdci = self.pdci;

        var farthest_ray: usize = 0;
        for (self.rays.slice(), 0..) |*ray, angle| {
            if (ray.isValid(self.console.width, self.console.height)) {
                const x: usize = @intFromFloat(math.round(ray.x));
                const y: usize = @intFromFloat(math.round(ray.y));

                if (farthest_ray < Coord.new(x, y).distance(pdc)) {
                    farthest_ray = Coord.new(x, y).distance(pdc);
                }

                self.console.setCell(x, y, .{ .trans = true });
            }

            // Some stupid casting going on because rangeClumping can't handle f64's
            const f = ray.speed / (@as(f64, @floatFromInt(rng.range(usize, 14, 28))) / 10.0);
            ray.move(angle, f);

            {
                const x: isize = @intFromFloat(math.round(ray.x));
                const y: isize = @intFromFloat(math.round(ray.y));

                const orig_dist = ray.orig.distanceEuclidean(pdci);
                const curr_dist = CoordIsize.new(x, y).distanceEuclidean(pdci);
                const journey_done = (orig_dist - curr_dist) / orig_dist;
                ray.speed = 2 * (1.3 + (journey_done * journey_done * journey_done));
                ray.speed = @min(2.3, ray.speed);
            }

            if (ray.isValid(self.console.width, self.console.height)) {
                const x: usize = @intFromFloat(math.round(ray.x));
                const y: usize = @intFromFloat(math.round(ray.y));

                const cell = self.console.getCell(x, y);

                if (Coord.new(x, y).distance(pdc) < 2) {
                    ray.dead = true;
                    self.console.setCell(x, y, .{ .trans = true, .fl = .{ .wide = cell.fl.wide } });
                    if (cell.fl.wide) self.console.setCell(x, y, .{ .fl = .{ .skip = true } });
                } else if (!cell.fl.skip) {
                    ray.c.trans = false;
                    if ((ray.c.bg == colors.BG or rng.percent(33)) and cell.bg != colors.BG) {
                        const frac = @as(f64, @floatFromInt(rng.range(usize, 0, 0) / 100));
                        const bg = colors.percentageOf2(cell.bg, 140);
                        if (colors.brightness(bg) > colors.brightness(ray.c.bg)) {
                            ray.c.bg = bg;
                        } else if (colors.brightness(0xcccccc) < colors.brightness(ray.c.bg)) {
                            ray.c.bg = colors.mix(ray.c.bg, cell.bg, frac);
                        } else {
                            ray.c.bg = colors.mix(ray.c.bg, bg, frac);
                        }
                    }
                    if ((ray.c.ch == ' ' or rng.percent(33)) and cell.ch != ' ') {
                        ray.c.ch = cell.ch;
                    }
                    if ((ray.c.fg == 0x0 or rng.percent(33)) and cell.fg != 0x0) {
                        ray.c.fg = colors.mix(ray.c.fg, cell.fg, 0.5);
                    }
                    if (cell.fl.wide and !(cell.bg == colors.BG and cell.fg == 0x0)) {
                        ray.c.fl.wide = true;
                        self.console.setCell(x + 1, y, .{ .fl = .{ .skip = true } });
                    }

                    self.console.setCell(x, y, ray.c);

                    for (self.rays.slice()) |*otherray|
                        if (otherray.isValid(self.console.width, self.console.height) and
                            @as(usize, @intFromFloat(math.round(otherray.x))) == x and
                            @as(usize, @intFromFloat(math.round(otherray.y))) == y and
                            !otherray.c.trans and
                            colors.brightness(otherray.c.bg) < colors.brightness(ray.c.bg))
                        {
                            otherray.c = ray.c;
                        };
                }
            }
        }

        while (farthest_ray > 0 and self.z > 0 and self.z > farthest_ray + 1) : (self.z -= 1) {
            var box_x: usize = 0;
            while (box_x < self.console.width) : (box_x += 1) {
                self.console.setCell(box_x, pdc.y + @as(usize, @intCast(self.z)), .{ .trans = true });
                if (@as(usize, @intCast(self.z)) <= pdc.y)
                    self.console.setCell(box_x, pdc.y - @as(usize, @intCast(self.z)), .{ .trans = true });
            }
            var box_b: usize = 0;
            while (box_b < self.console.height) : (box_b += 1) {
                self.console.setCell(pdc.x + @as(usize, @intCast(self.z)), box_b, .{ .trans = true });
                if (@as(usize, @intCast(self.z)) <= pdc.x)
                    self.console.setCell(pdc.x - @as(usize, @intCast(self.z)), box_b, .{ .trans = true });
            }
        }

        self.i += 1;
        return {};
    }
};

pub fn animationDeath(self: *Console) AnimationDeath {
    const pdc = coordToScreen(state.player.coord).?;
    const pdci = CoordIsize.fromCoord(pdc);

    var rays = StackBuffer(AnimationDeath.Ray, 360).init(null);
    {
        const d = pdc.distanceEuclidean(Coord.new(self.width, self.height));
        var i: f64 = 0;
        while (i < 360) : (i += 1)
            rays.append(AnimationDeath.Ray.init(
                @as(f64, @floatFromInt(pdc.x)) + math.sin(i * math.pi / 180.0) * d,
                @as(f64, @floatFromInt(pdc.y)) + math.cos(i * math.pi / 180.0) * d,
            )) catch err.wat();
        for (rays.slice(), 0..) |*ray, angle|
            ray.move(angle, 0.5);
    }

    return .{
        .console = self,
        .pdc = pdc,
        .pdci = pdci,
        .rays = rays,
        .i = 0,
        .z = @intCast(pdc.distance(Coord.new(self.width, self.height / 2))),
        .m = @max(self.width - pdc.x, self.height - pdc.y) * 15 / 10,
    };
}

// pub fn animationDeath(ctx: *GeneratorCtx(void), self: *Console) void {
//     const pdc = coordToScreen(state.player.coord).?;
//     const pdci = CoordIsize.fromCoord(pdc);

//     var rays = StackBuffer(Ray, 360).init(null);
//     {
//         const d = pdc.distanceEuclidean(Coord.new(self.width, self.height));
//         var i: f64 = 0;
//         while (i < 360) : (i += 1)
//             rays.append(Ray.init(
//                 @as(f64, @floatFromInt(pdc.x)) + math.sin(i * math.pi / 180.0) * d,
//                 @as(f64, @floatFromInt(pdc.y)) + math.cos(i * math.pi / 180.0) * d,
//             )) catch err.wat();
//         for (rays.slice(), 0..) |*ray, angle|
//             ray.move(angle, 0.5);
//     }

//     var i: usize = 0;
//     var z: isize = @intCast(pdc.distance(Coord.new(self.width, self.height / 2)));
//     const m = @max(self.width - pdc.x, self.height - pdc.y) * 15 / 10;
//     while (i < m) : (i += 1) {
//         var farthest_ray: usize = 0;
//         for (rays.slice(), 0..) |*ray, angle| {
//             if (ray.isValid(self.width, self.height)) {
//                 const x: usize = @intFromFloat(math.round(ray.x));
//                 const y: usize = @intFromFloat(math.round(ray.y));

//                 if (farthest_ray < Coord.new(x, y).distance(pdc)) {
//                     farthest_ray = Coord.new(x, y).distance(pdc);
//                 }

//                 self.setCell(x, y, .{ .trans = true });
//             }

//             // Some stupid casting going on because rangeClumping can't handle f64's
//             const f = ray.speed / (@as(f64, @floatFromInt(rng.range(usize, 14, 28))) / 10.0);
//             ray.move(angle, f);

//             {
//                 const x: isize = @intFromFloat(math.round(ray.x));
//                 const y: isize = @intFromFloat(math.round(ray.y));

//                 const orig_dist = ray.orig.distanceEuclidean(pdci);
//                 const curr_dist = CoordIsize.new(x, y).distanceEuclidean(pdci);
//                 const journey_done = (orig_dist - curr_dist) / orig_dist;
//                 ray.speed = 2 * (1.3 + (journey_done * journey_done * journey_done));
//                 ray.speed = @min(2.3, ray.speed);
//             }

//             if (ray.isValid(self.width, self.height)) {
//                 const x: usize = @intFromFloat(math.round(ray.x));
//                 const y: usize = @intFromFloat(math.round(ray.y));

//                 const cell = self.getCell(x, y);

//                 if (Coord.new(x, y).distance(pdc) < 2) {
//                     ray.dead = true;
//                     self.setCell(x, y, .{ .trans = true, .fl = .{ .wide = cell.fl.wide } });
//                     if (cell.fl.wide) self.setCell(x, y, .{ .fl = .{ .skip = true } });
//                 } else if (!cell.fl.skip) {
//                     ray.c.trans = false;
//                     if ((ray.c.bg == colors.BG or rng.percent(33)) and cell.bg != colors.BG) {
//                         const frac = @as(f64, @floatFromInt(rng.range(usize, 0, 0) / 100));
//                         const bg = colors.percentageOf2(cell.bg, 140);
//                         if (colors.brightness(bg) > colors.brightness(ray.c.bg)) {
//                             ray.c.bg = bg;
//                         } else if (colors.brightness(0xcccccc) < colors.brightness(ray.c.bg)) {
//                             ray.c.bg = colors.mix(ray.c.bg, cell.bg, frac);
//                         } else {
//                             ray.c.bg = colors.mix(ray.c.bg, bg, frac);
//                         }
//                     }
//                     if ((ray.c.ch == ' ' or rng.percent(33)) and cell.ch != ' ') {
//                         ray.c.ch = cell.ch;
//                     }
//                     if ((ray.c.fg == 0x0 or rng.percent(33)) and cell.fg != 0x0) {
//                         ray.c.fg = colors.mix(ray.c.fg, cell.fg, 0.5);
//                     }
//                     if (cell.fl.wide and !(cell.bg == colors.BG and cell.fg == 0x0)) {
//                         ray.c.fl.wide = true;
//                         self.setCell(x + 1, y, .{ .fl = .{ .skip = true } });
//                     }

//                     self.setCell(x, y, ray.c);

//                     for (rays.slice()) |*otherray|
//                         if (otherray.isValid(self.width, self.height) and
//                             @as(usize, @intFromFloat(math.round(otherray.x))) == x and
//                             @as(usize, @intFromFloat(math.round(otherray.y))) == y and
//                             !otherray.c.trans and
//                             colors.brightness(otherray.c.bg) < colors.brightness(ray.c.bg))
//                         {
//                             otherray.c = ray.c;
//                         };
//                 }
//             }
//         }

//         while (farthest_ray > 0 and z > 0 and z > farthest_ray + 1) : (z -= 1) {
//             var box_x: usize = 0;
//             while (box_x < self.width) : (box_x += 1) {
//                 self.setCell(box_x, pdc.y + @as(usize, @intCast(z)), .{ .trans = true });
//                 if (@as(usize, @intCast(z)) <= pdc.y)
//                     self.setCell(box_x, pdc.y - @as(usize, @intCast(z)), .{ .trans = true });
//             }
//             var box_b: usize = 0;
//             while (box_b < self.height) : (box_b += 1) {
//                 self.setCell(pdc.x + @as(usize, @intCast(z)), box_b, .{ .trans = true });
//                 if (@as(usize, @intCast(z)) <= pdc.x)
//                     self.setCell(pdc.x - @as(usize, @intCast(z)), box_b, .{ .trans = true });
//             }
//         }

//         ctx.yield({});
//     }

//     self.clearTo(.{ .trans = true });
//     ctx.finish();
// }

// }}}
