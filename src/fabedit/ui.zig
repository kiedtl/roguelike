const std = @import("std");
const meta = std.meta;
const math = std.math;
const mem = std.mem;

const colors = @import("../colors.zig");
const display = @import("../display.zig");
const err = @import("../err.zig");
const fabedit = @import("../fabedit.zig");
const mapgen = @import("../mapgen.zig");
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
                    st.x = coord.x / 2;
                    st.y = coord.y;
                    break :b true;
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
    Prop = 1 << 16,
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
                    if (s & @enumToInt(HudMouseSignalTag.Prop) > 0) {
                        const i = s & ~@enumToInt(HudMouseSignalTag.Prop);
                        st.cursor.Prop = i;
                        break :b true;
                    }
                    break :b false;
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
        self.main = Console.init(state.gpa.allocator(), (40 * 2) + HUD_WIDTH + 1, 40);
        self.main.addSubconsole(&map_win.main, 0, 0);
        self.main.addSubconsole(&hud_win.main, 40 * 2 + 1, 0);
    }

    pub fn deinit(self: *@This()) void {
        self.main.deinit();
    }
} = .{};

pub fn init() !void {
    try display.init((40 * 2) + HUD_WIDTH + 1, 40, 1.0);
    map_win.init();
    hud_win.init();
    container.init();
}

pub fn drawHUD(st: *fabedit.EdState) void {
    hud_win.main.clear();
    hud_win.main.clearMouseTriggers();

    var y: usize = 0;

    var tabx: usize = 0;
    inline for (meta.fields(fabedit.EdState.HudPane)) |field, i| {
        if (i != 0) {
            _ = hud_win.drawTextAt(tabx, y, " · ", .{});
            tabx += 3;
        }
        var c: u21 = 'g';
        if (mem.eql(u8, @tagName(st.hud_pane), field.name))
            c = 'c';
        _ = hud_win.main.drawTextAtf(tabx, y, "${u}{s}$.", .{ c, field.name }, .{});
        //hud_win.addClickableTextBoth(.{ .Signal = i });
        tabx += field.name.len;
    }
    y += 2;

    switch (st.hud_pane) {
        .Props => {
            const PANEL_WIDTH = HUD_WIDTH / 2;

            const cursor_x = st.cursor.Prop % PANEL_WIDTH;
            var display_row = (st.cursor.Prop - cursor_x) / PANEL_WIDTH;
            if (display_row >= 4)
                display_row -= 4;

            const selected = &surfaces.props.items[st.cursor.Prop];
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
                if (i == st.cursor.Prop)
                    cell.bg = colors.mix(cell.bg, 0xffffff, 0.2);
                cell.fl.wide = true;
                hud_win.main.setCell(dx, y, cell);
                hud_win.main.setCell(dx + 1, y, .{ .fl = .{ .skip = true } });
                const signal = @enumToInt(HudMouseSignalTag.Prop) | i;
                hud_win.main.addClickableTextBoth(.{ .Signal = signal });
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
        },
    }
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

            cell.fg = switch (st.fab.content[y][x]) {
                .Any, .Connection => 0xaaaaaa,
                .Window, .Wall => colors.LIGHT_CONCRETE,
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
                    .Machine => |mid| surfaces.MACHINES[utils.findById(&surfaces.MACHINES, mid.id).?].powered_fg orelse 0xffffff,
                    else => colors.LIGHT_CONCRETE,
                },
                .LevelFeature => colors.LIGHT_STEEL_BLUE,
                .LockedDoor,
                .HeavyLockedDoor,
                .Door,
                .Bars,
                .Brazier,
                .ShallowWater,
                .Loot1,
                .RareLoot,
                .Corpse,
                .Ring,
                => 0xffffff,
                .Floor => 0x777777,
                .Water => 0x0000ff,
                .Lava => 0xff0000,
            };

            cell.ch = switch (st.fab.content[y][x]) {
                .Any => '?',
                .Connection => '*',
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
                .LockedDoor => '±',
                .HeavyLockedDoor => '±', // TODO: fg
                .Door => '+',
                .Brazier => '¤',
                .ShallowWater => '~',
                .Bars => '×',
                .Loot1 => 'L',
                .RareLoot => 'R',
                .Corpse => '%', // TODO: fg
                .Ring => '=',
                .Lava, .Water => '≈',
                .Floor => '.',
                else => '@',
            };

            cell.fl.wide = true;
            map_win.main.setCell(dx, y, cell);
            map_win.main.setCell(dx + 1, y, .{ .fl = .{ .skip = true } });
        }
    }
}

pub fn draw(st: *fabedit.EdState) void {
    drawHUD(st);

    if (st.fab_modified) {
        drawMap(st);
        st.fab_modified = false;
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
        hud_win.handleMouseEvent(ev, st);
}

fn _evToMEvType(ev: display.Event) Console.MouseTrigger.Kind {
    return switch (ev) {
        .Click => .Click,
        .Hover => .Hover,
        .Wheel => .Wheel,
        else => err.wat(),
    };
}
