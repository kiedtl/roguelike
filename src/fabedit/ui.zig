const colors = @import("../colors.zig");
const display = @import("../display.zig");
const fabedit = @import("../fabedit.zig");
const mapgen = @import("../mapgen.zig");
const state = @import("../state.zig");
const surfaces = @import("../surfaces.zig");
const utils = @import("../utils.zig");

const Console = @import("../ui/Console.zig");

pub const FRAMERATE = 1000 / 25;

pub var map_win: struct {
    main: Console = undefined,

    pub fn init(self: *@This()) void {
        self.main = Console.init(state.gpa.allocator(), 40 * 2, 40);
    }

    pub fn handleMouseEvent(_: *@This(), ev: display.Event) bool {
        return switch (ev) {
            .Click, .Hover => false,
            .Wheel => false,
            else => unreachable,
        };
    }
} = .{};

pub var container: struct {
    main: Console = undefined,

    pub fn init(self: *@This()) void {
        self.main = Console.init(state.gpa.allocator(), (40 * 2) + 20, 40);
        self.main.addSubconsole(&map_win.main, 0, 0);
    }

    pub fn deinit(self: *@This()) void {
        self.main.deinit();
    }
} = .{};

pub fn init() !void {
    try display.init((40 * 2) + 20, 40, 1.0);
    map_win.init();
    container.init();
}

pub fn draw(st: *fabedit.EdState) void {
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

            if (st.x == x and st.y == y)
                cell.bg = colors.mix(cell.bg, 0xffffff, 0.2);

            cell.fl.wide = true;
            map_win.main.setCell(dx, y, cell);
            map_win.main.setCell(dx + 1, y, .{ .fl = .{ .skip = true } });
        }
    }

    container.main.renderFully(0, 0);
    display.present();
}

pub fn deinit() !void {
    try display.deinit();
    container.deinit();
}

pub fn handleMouseEvent(ev: display.Event) bool {
    _ = ev;
    return false;
}
