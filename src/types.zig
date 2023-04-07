const std = @import("std");
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const fmt = std.fmt;
const assert = std.debug.assert;
const enums = std.enums;
const testing = std.testing;

const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const LinkedList = @import("list.zig").LinkedList;
const RingBuffer = @import("ringbuffer.zig").RingBuffer;
const StackBuffer = @import("buffer.zig").StackBuffer;
const StringBuf64 = @import("buffer.zig").StringBuf64;

const ai = @import("ai.zig");
const astar = @import("astar.zig");
const combat = @import("combat.zig");
const colors = @import("colors.zig");
const dijkstra = @import("dijkstra.zig");
const ui = @import("ui.zig");
const err = @import("err.zig");
const explosions = @import("explosions.zig");
const fire = @import("fire.zig");
const fov = @import("fov.zig");
const font = @import("font.zig");
const mobs = @import("mobs.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const materials = @import("materials.zig");
const player = @import("player.zig");
const rng = @import("rng.zig");
const sound = @import("sound.zig");
const spells = @import("spells.zig");
const scores = @import("scores.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const display = @import("display.zig");
const utils = @import("utils.zig");

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const Evocable = items.Evocable;
const Projectile = items.Projectile;
const Consumable = items.Consumable;
const PatternChecker = items.PatternChecker;
const Cloak = items.Cloak;
const Aux = items.Aux;

const Sound = @import("sound.zig").Sound;
const SoundIntensity = @import("sound.zig").SoundIntensity;
const SoundType = @import("sound.zig").SoundType;

const SpellOptions = spells.SpellOptions;
const Spell = spells.Spell;
const Poster = literature.Poster;

pub const DIAGONAL_DIRECTIONS = [_]Direction{ .NorthWest, .SouthWest, .NorthEast, .SouthEast };
pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const CoordArrayList = std.ArrayList(Coord);
pub const StockpileArrayList = std.ArrayList(Stockpile);
pub const MessageArrayList = std.ArrayList(Message);
pub const StatusArray = enums.EnumArray(Status, StatusDataInfo);
pub const SpatterArray = enums.EnumArray(Spatter, usize);
pub const MobList = LinkedList(Mob);
pub const MobArrayList = std.ArrayList(*Mob);
pub const RingList = LinkedList(Ring);
pub const ArmorList = LinkedList(Armor);
pub const WeaponList = LinkedList(Weapon);
pub const PropList = LinkedList(Prop);
pub const PropArrayList = std.ArrayList(Prop);
pub const MachineList = LinkedList(Machine);
pub const ContainerList = LinkedList(Container);

pub const MOB_CORRUPTION_CHANCE = 33;
pub const TORMENT_UNDEAD_DAMAGE = 2;
pub const DETECT_HEAT_RADIUS = math.min(ui.MAP_HEIGHT_R, ui.MAP_WIDTH_R);
pub const DETECT_ELEC_RADIUS = math.min(ui.MAP_HEIGHT_R, ui.MAP_WIDTH_R);
pub const DETECT_UNDEAD_RADIUS = math.min(ui.MAP_HEIGHT_R, ui.MAP_WIDTH_R);

pub fn MinMax(comptime T: type) type {
    return struct {
        min: T,
        max: T,

        pub fn contains(s: @This(), v: T) bool {
            return v <= s.max and v >= s.min;
        }
    };
}
pub fn minmax(comptime T: type, min: T, max: T) MinMax(T) {
    return MinMax(T){ .min = min, .max = max };
}

pub const Direction = enum { // {{{
    North,
    South,
    East,
    West,
    NorthEast,
    NorthWest,
    SouthEast,
    SouthWest,

    const Self = @This();

    pub fn from(base: Coord, neighbor: Coord) ?Self {
        const dx = @intCast(isize, neighbor.x) - @intCast(isize, base.x);
        const dy = @intCast(isize, neighbor.y) - @intCast(isize, base.y);

        if (dx == 0 and dy == -1) {
            return .North;
        } else if (dx == 0 and dy == 1) {
            return .South;
        } else if (dx == 1 and dy == 0) {
            return .East;
        } else if (dx == -1 and dy == 0) {
            return .West;
        } else if (dx == 1 and dy == -1) {
            return .NorthEast;
        } else if (dx == -1 and dy == -1) {
            return .NorthWest;
        } else if (dx == 1 and dy == 1) {
            return .SouthEast;
        } else if (dx == -1 and dy == 1) {
            return .SouthWest;
        } else {
            return null;
        }
    }

    pub fn adjacentDirectionsTo(base: Self) [2]Direction {
        return switch (base) {
            .North => .{ .NorthWest, .NorthEast },
            .East => .{ .NorthEast, .SouthEast },
            .South => .{ .SouthWest, .SouthEast },
            .West => .{ .NorthWest, .SouthWest },
            .NorthWest => .{ .West, .North },
            .NorthEast => .{ .East, .North },
            .SouthWest => .{ .South, .West },
            .SouthEast => .{ .South, .East },
        };
    }

    pub fn is_adjacent(base: Self, other: Self) bool {
        const adjacent = adjacentDirectionsTo(base);
        return other == adjacent[0] or other == adjacent[1];
    }

    pub fn is_diagonal(self: Self) bool {
        return switch (self) {
            .North, .South, .East, .West => false,
            else => true,
        };
    }

    pub fn opposite(self: *const Self) Self {
        return switch (self.*) {
            .North => .South,
            .South => .North,
            .East => .West,
            .West => .East,
            .NorthEast => .SouthWest,
            .NorthWest => .SouthEast,
            .SouthEast => .NorthWest,
            .SouthWest => .NorthEast,
        };
    }

    pub fn turnleft(self: *const Self) Self {
        return switch (self.*) {
            .North => .West,
            .South => .East,
            .East => .North,
            .West => .South,
            else => err.wat(),
        };
    }

    pub fn turnright(self: *const Self) Self {
        return self.turnleft().opposite();
    }

    pub fn turnLeftDiagonally(self: *const Self) Self {
        return switch (self.*) {
            .North => .NorthWest,
            .South => .SouthEast,
            .East => .NorthEast,
            .West => .SouthWest,
            .NorthEast => .North,
            .NorthWest => .West,
            .SouthEast => .East,
            .SouthWest => .South,
        };
    }

    pub fn turnRightDiagonally(self: *const Self) Self {
        return switch (self.*) {
            .North => .NorthEast,
            .South => .SouthWest,
            .East => .SouthEast,
            .West => .NorthWest,
            .NorthEast => .East,
            .NorthWest => .North,
            .SouthEast => .South,
            .SouthWest => .West,
        };
    }

    pub fn name(self: Self) []const u8 {
        return switch (self) {
            .North => "north",
            .South => "south",
            .East => "east",
            .West => "west",
            .NorthEast => "north-east",
            .NorthWest => "north-west",
            .SouthEast => "south-east",
            .SouthWest => "south-west",
        };
    }

    pub fn fromStr(str: []const u8) !Self {
        return for (&DIRECTIONS) |d| {
            if (mem.eql(u8, str, d.name()))
                break d;
        } else error.NoSuchDirection;
    }

    pub fn format(self: Self, comptime f: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        if (comptime !mem.eql(u8, f, "")) {
            @compileError("Unknown format string: '" ++ f ++ "'");
        }

        try writer.writeAll(self.name());
    }
}; // }}}

pub const Coord = struct { // {{{
    x: usize,
    y: usize,
    z: usize,

    const Self = @This();

    pub const __JANET_PROTOTYPE = "Coord";

    pub inline fn new2(level: usize, x: usize, y: usize) Coord {
        return .{ .z = level, .x = x, .y = y };
    }

    pub inline fn new(x: usize, y: usize) Coord {
        return .{ .z = 0, .x = x, .y = y };
    }

    pub inline fn difference(a: Self, b: Self) Self {
        return Coord.new2(
            a.z,
            math.max(a.x, b.x) - math.min(a.x, b.x),
            math.max(a.y, b.y) -
                math.min(a.y, b.y),
        );
    }

    pub inline fn distance(a: Self, b: Self) usize {
        const diff =
            a.difference(b);

        // Euclidean: d = sqrt(dx^2 + dy^2)
        //
        // return math.sqrt((diff.x * diff.x) + (diff.y * diff.y));

        // Manhattan: d = dx + dy return diff.x + diff.y;

        // Chebyshev: d = max(dx, dy)
        return math.max(diff.x, diff.y);
    }

    pub inline fn distanceManhattan(a: Self, b: Self) usize {
        const diff =
            a.difference(b);
        return diff.x + diff.y;
    }

    // Sometimes we want to pass Coord.eq around, but we can't since an inline
    // function has a different type than a non-inline function.
    //
    pub fn eqNotInline(a: Self, b: Self) bool {
        return a.eq(b);
    }

    pub inline fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }

    pub inline fn add(a: Self, b: Self) Self {
        return Coord.new2(a.z, a.x +
            b.x, a.y + b.y);
    }

    pub inline fn asRect(self: *const Self) Rect {
        return Rect{ .start = self.*, .width = 1, .height = 1 };
    }

    // FIXME: this only checks if the relevant Coordinate component is within
    // bounds. So, if trying to move a coord south that has the x-axis out of
    // bounds, it won't return null.
    pub fn move(self: *const Self, direction: Direction, limit: Self) ?Coord {
        switch (direction) {
            .North => {
                if (self.y == 0) return null;
                return Coord.new2(self.z, self.x, self.y - 1);
            },
            .South => {
                if (self.y >= limit.y -| 1) return null;
                return Coord.new2(self.z, self.x, self.y + 1);
            },
            .East => {
                if (self.x >= limit.x -| 1) return null;
                return Coord.new2(self.z, self.x + 1, self.y);
            },
            .West => {
                if (self.x == 0) return null;
                return Coord.new2(self.z, self.x - 1, self.y);
            },
            .NorthEast => {
                if (self.x >= limit.x -| 1 or self.y == 0) return null;
                return Coord.new2(self.z, self.x + 1, self.y - 1);
            },
            .NorthWest => {
                if (self.x == 0 or self.y == 0) return null;
                return Coord.new2(self.z, self.x - 1, self.y - 1);
            },
            .SouthEast => {
                if (self.x >= limit.x -| 1 or self.y >= limit.y -| 1) return null;
                return Coord.new2(self.z, self.x + 1, self.y + 1);
            },
            .SouthWest => {
                if (self.y >= limit.y -| 1 or self.x == 0) return null;
                return Coord.new2(self.z, self.x - 1, self.y + 1);
            },
        }
    }

    pub fn closestDirectionTo(self: Coord, to: Coord, limit: Coord) Direction {
        var closest_distance: usize = @as(usize, 0) -% 1;
        var closest_direction: Direction = .North;

        for (&DIRECTIONS) |direction| if (self.move(direction, limit)) |neighbor| {
            const dist = neighbor.distanceManhattan(to);

            if (dist < closest_distance) {
                closest_distance = dist;
                closest_direction = direction;
            }
        };

        return closest_direction;
    }

    fn insert_if_valid(z: usize, x: isize, y: isize, buf: *StackBuffer(Coord, 2048), limit: Coord) void {
        if (x < 0 or y < 0)
            return;
        if (x > @intCast(isize, limit.x) or y > @intCast(isize, limit.y))
            return;

        buf.append(Coord.new2(z, @intCast(usize, x), @intCast(usize, y))) catch err.wat();
    }

    pub fn drawLine(from: Coord, to: Coord, limit: Coord, extra: usize) StackBuffer(Coord, 2048) {
        assert(from.z == to.z);

        var buf = StackBuffer(Coord, 2048).init(null);

        const xstart = @intCast(isize, from.x);
        const xend = @intCast(isize, to.x);
        const ystart = @intCast(isize, from.y);
        const yend = @intCast(isize, to.y);
        const stepx: isize = if (xstart < xend) 1 else -1;
        const stepy: isize = if (ystart < yend) 1 else -1;
        const dx = @intToFloat(f64, math.absInt(xend - xstart) catch err.wat());
        const dy = @intToFloat(f64, math.absInt(yend - ystart) catch err.wat());

        var errmarg: f64 = 0.0;
        var x = @intCast(isize, from.x);
        var y = @intCast(isize, from.y);

        var extra_ctr: usize = extra;

        if (dx > dy) {
            errmarg = dx / 2.0;
            var reached_goal = false;
            while (true) {
                if (x == xend) {
                    reached_goal = true;
                }
                if (reached_goal) {
                    if (extra_ctr == 0) {
                        break;
                    }
                    extra_ctr -= 1;
                }
                insert_if_valid(from.z, x, y, &buf, limit);
                errmarg -= dy;
                if (errmarg < 0) {
                    y += stepy;
                    errmarg += dx;
                }
                x += stepx;
            }
            insert_if_valid(from.z, x, y, &buf, limit);
        } else {
            errmarg = dy / 2.0;
            var reached_goal = false;
            while (true) {
                if (y == yend) {
                    reached_goal = true;
                }
                if (reached_goal) {
                    if (extra_ctr == 0) {
                        break;
                    }
                    extra_ctr -= 1;
                }
                insert_if_valid(from.z, x, y, &buf, limit);
                errmarg -= dx;
                if (errmarg < 0) {
                    x += stepx;
                    errmarg += dy;
                }
                y += stepy;
            }
            insert_if_valid(from.z, x, y, &buf, limit);
        }

        return buf;
    }

    pub fn draw_circle(center: Coord, radius: usize, limit: Coord, alloc: mem.Allocator) CoordArrayList {
        //const circum = @floatToInt(usize, math.ceil(math.tau * @intToFloat(f64, radius)));

        var buf = CoordArrayList.init(alloc);

        const x: isize = @intCast(isize, center.x);
        const y: isize = @intCast(isize, center.y);

        var f: isize = 1 - @intCast(isize, radius);
        var ddf_x: isize = 0;
        var ddf_y: isize = -2 * @intCast(isize, radius);
        var dx: isize = 0;
        var dy: isize = @intCast(isize, radius);

        insert_if_valid(x, y + @intCast(isize, radius), &buf, limit);
        insert_if_valid(x, y - @intCast(isize, radius), &buf, limit);
        insert_if_valid(x + @intCast(isize, radius), y, &buf, limit);
        insert_if_valid(x - @intCast(isize, radius), y, &buf, limit);

        while (dx < dy) {
            if (f >= 0) {
                dy -= 1;
                ddf_y += 2;
                f += ddf_y;
            }

            dx += 1;
            ddf_x += 2;
            f += ddf_x + 1;

            insert_if_valid(x + dx, y + dy, &buf, limit);
            insert_if_valid(x - dx, y + dy, &buf, limit);
            insert_if_valid(x + dx, y - dy, &buf, limit);
            insert_if_valid(x - dx, y - dy, &buf, limit);
            insert_if_valid(x + dy, y + dx, &buf, limit);
            insert_if_valid(x - dy, y + dx, &buf, limit);
            insert_if_valid(x + dy, y - dx, &buf, limit);
            insert_if_valid(x - dy, y - dx, &buf, limit);
        }

        return buf;
    }

    pub fn iterNeighbors(ctx: *GeneratorCtx(Coord), self: Coord) void {
        for (&DIRECTIONS) |d| if (self.move(d, state.mapgeometry)) |neighbor| {
            ctx.yield(neighbor);
        };

        ctx.finish();
    }

    pub fn iterCardinalNeighbors(ctx: *GeneratorCtx(Coord), self: Coord) void {
        for (&CARDINAL_DIRECTIONS) |d| if (self.move(d, state.mapgeometry)) |neighbor| {
            ctx.yield(neighbor);
        };

        ctx.finish();
    }
}; // }}}

test "coord.drawLine straight lines" {
    const t_height = 5;
    const t_width = 10;
    const limit = Coord.new(t_width, t_height);

    const cases = [_][t_height]*const [t_width]u8{
        .{
            ".....S....",
            ".....p....",
            ".....p....",
            ".....p....",
            ".....E....",
        },
        .{
            "..........",
            "..........",
            "SppppppppE",
            "..........",
            "..........",
        },
        .{
            "..........",
            "..........",
            "SpE.......",
            "..........",
            "..........",
        },
        .{
            "..........",
            ".S........",
            ".p........",
            ".E........",
            "..........",
        },
        .{
            "..........",
            ".S........",
            "..p.......",
            "...E......",
            "..........",
        },
    };

    for (cases) |case, bi| {
        _ = bi;
        // std.log.warn("testing case {}", .{bi});

        const case_start = b: for (case) |row, y| {
            for (row) |cell, x|
                if (cell == 'S')
                    break :b Coord.new(x, y);
        } else unreachable;

        const case_end = b: for (case) |row, y| {
            for (row) |cell, x|
                if (cell == 'E')
                    break :b Coord.new(x, y);
        } else unreachable;

        var case_path_length: usize = 0;
        for (case) |row| for (row) |cell| {
            if (cell != '.') case_path_length += 1;
        };

        const line = case_start.drawLine(case_end, limit, 0);

        try testing.expectEqual(case_path_length, line.len);

        // std.log.info("Got:", .{});
        // {
        //     var y: usize = 0;
        //     while (y < t_height) : (y += 1) {
        //         var x: usize = 0;
        //         while (x < t_width) : (x += 1) {
        //             var path_contains = for (line.constSlice()) |path_coord| {
        //                 if (path_coord.x == x and path_coord.y == y)
        //                     break true;
        //             } else false;
        //             const ch: u21 = if (path_contains) '#' else '.';
        //             std.debug.print("{u}", .{ch});
        //         }
        //         std.debug.print("\n", .{});
        //     }
        // }

        for (line.constSlice()) |path_coord, i| {
            try testing.expect(path_coord.x < t_width);
            try testing.expect(path_coord.y < t_height);

            if (i == 0) {
                try testing.expect(path_coord.eq(case_start));
            } else if (i == line.len - 1) {
                try testing.expect(path_coord.eq(case_end));
            } else {
                try testing.expect(case[path_coord.y][path_coord.x] == 'p');
            }
        }
    }
}

test "coord.distance" {
    try std.testing.expectEqual(Coord.new(0, 0).distance(Coord.new(0, 1)), 1);
    try std.testing.expectEqual(Coord.new(0, 0).distance(Coord.new(1, 1)), 1);
    try std.testing.expectEqual(Coord.new(0, 0).distance(Coord.new(0, 2)), 2);
}

test "coord.move" {
    const limit = Coord.new(9, 9);
    const c = Coord.new(0, 0);
    try std.testing.expectEqual(c.move(.East, limit), Coord.new(1, 0));
}

pub const Rect = struct {
    start: Coord,
    width: usize,
    height: usize,

    pub const ArrayList = std.ArrayList(Rect);

    pub fn new(start: Coord, w: usize, h: usize) Rect {
        return Rect{ .start = start, .width = w, .height = h };
    }

    pub fn add(a: *const Rect, b: *const Rect) Rect {
        assert(b.start.z == 0);

        return .{
            .start = Coord.new2(a.start.z, a.start.x + b.start.x, a.start.y + b.start.y),
            .width = a.width,
            .height = b.width,
        };
    }

    pub fn overflowsLimit(self: *const Rect, limit: *const Rect) bool {
        return self.end().x >= limit.end().x or
            self.end().y >= limit.end().y or
            self.start.x < limit.start.x or
            self.start.y < limit.start.y;
    }

    pub fn end(self: *const Rect) Coord {
        return Coord.new2(self.start.z, self.start.x + self.width, self.start.y + self.height);
    }

    pub fn intersects(a: *const Rect, b: *const Rect, padding: usize) bool {
        const a_end = a.end();
        const b_end = b.end();

        const ca = (a.start.x -| padding) < b_end.x;
        const cb = (a_end.x + padding) > b.start.x;
        const cc = (a.start.y -| padding) < b_end.y;
        const cd = (a_end.y + padding) > b.start.y;

        return ca and cb and cc and cd;
    }

    pub fn randomCoord(self: *const Rect) Coord {
        const x = rng.range(usize, self.start.x, self.end().x - 1);
        const y = rng.range(usize, self.start.y, self.end().y - 1);
        return Coord.new2(self.start.z, x, y);
    }

    pub fn rectIter(ctx: *GeneratorCtx(Coord), rect: Rect) void {
        var y: usize = rect.start.y;
        while (y < rect.end().y) : (y += 1) {
            var x: usize = rect.start.x;
            while (x < rect.end().x) : (x += 1) {
                ctx.yield(Coord.new2(rect.start.z, x, y));
            }
        }

        ctx.finish();
    }
};

// Tests that rectIter visits each coordinate exactly once.
test "Rect.rectIter" {
    const height = 100;
    const width = 70;

    var matrix = [_][width]usize{[_]usize{0} ** width} ** height;
    const matrix_rect = Rect{ .start = Coord.new(0, 0), .width = width, .height = height };

    var gen = Generator(Rect.rectIter).init(matrix_rect);
    while (gen.next()) |coord| {
        matrix[coord.y][coord.x] += 1;
    }

    for (matrix) |row| {
        try testing.expect(mem.allEqual(usize, row[0..], 1));
    }
}

pub const Stockpile = struct {
    room: Rect,
    type: ItemType,
    boulder_material_type: ?Material.MaterialType = null,

    pub fn findEmptySlot(self: *const Stockpile) ?Coord {
        var y: usize = self.room.start.y;
        while (y < self.room.end().y) : (y += 1) {
            var x: usize = self.room.start.x;
            while (x < self.room.end().x) : (x += 1) {
                const coord = Coord.new2(self.room.start.z, x, y);

                if (state.dungeon.at(coord).type != .Floor) {
                    continue;
                }

                if (state.dungeon.hasContainer(coord)) |container|
                    if (!container.items.isFull()) {
                        return coord;
                    };
                if (!state.dungeon.itemsAt(coord).isFull()) {
                    return coord;
                }
            }
        }
        return null;
    }

    pub fn findItem(self: *const Stockpile) ?Coord {
        var y: usize = self.room.start.y;
        while (y < self.room.end().y) : (y += 1) {
            var x: usize = self.room.start.x;
            while (x < self.room.end().x) : (x += 1) {
                const coord = Coord.new2(self.room.start.z, x, y);
                if (state.dungeon.hasContainer(coord)) |container|
                    if (container.items.len > 0) {
                        return coord;
                    };
                if (state.dungeon.itemsAt(coord).len > 0) {
                    return coord;
                }
            }
        }
        return null;
    }

    // TODO: rewrite this monstrosity
    pub fn isStockpileOfSameType(a: *const Stockpile, b: *const Stockpile) bool {
        if (a.type != b.type) {
            return false;
        }

        if (a.boulder_material_type) |mat| {
            if (b.boulder_material_type == null) return false;
            if (b.boulder_material_type != mat) return false;
        }

        if (b.boulder_material_type) |mat| {
            if (a.boulder_material_type == null) return false;
            if (a.boulder_material_type != mat) return false;
        }

        return true;
    }

    pub fn isItemOfSameType(self: *const Stockpile, item: *const Item) bool {
        if (self.type != std.meta.activeTag(item.*)) {
            return false;
        }

        switch (item.*) {
            .Boulder => |b| if (b.type != self.boulder_material_type.?) return false,
            else => {},
        }

        return true;
    }

    pub fn inferType(self: *Stockpile) bool {
        if (self.findItem()) |item_location| {
            const item = if (state.dungeon.hasContainer(item_location)) |container|
                container.items.data[0]
            else
                state.dungeon.itemsAt(item_location).data[0];

            self.type = std.meta.activeTag(item);
            switch (self.type) {
                .Boulder => self.boulder_material_type = item.Boulder.type,
                else => {},
            }

            return true;
        } else {
            return false;
        }
    }
};

test "stockpile type equality" {
    try std.testing.expect((Stockpile{ .room = undefined, .type = .Weapon }).isItemOfSameType(&Item{ .Weapon = undefined }));
    try std.testing.expect((Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .Metal }).isItemOfSameType(&Item{ .Boulder = &materials.Iron }));
    try std.testing.expect((Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .I_Stone }).isItemOfSameType(&Item{ .Boulder = &materials.Basalt }));
    try std.testing.expect(!(Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .I_Stone }).isItemOfSameType(&Item{ .Boulder = &materials.Iron }));
    try std.testing.expect(!(Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .Metal }).isItemOfSameType(&Item{ .Boulder = &materials.Hematite }));
}

pub const Path = struct { from: Coord, to: Coord, confused_state: bool };

pub const Material = struct {
    // Name of the material. e.g. "rhyolite"
    id: ?[]const u8 = null,
    name: []const u8,

    type: MaterialType = .I_Stone,

    // Tile used to represent walls.
    color_fg: u32,
    color_bg: ?u32,
    sprite: ?font.Sprite = .S_G_Wall_Rough,
    color_sfg: ?u32 = null,
    color_sbg: ?u32 = null,
    color_floor: u32,
    tileset: usize,
    floor_tile: u21 = '·',

    smelt_result: ?*const Material = null,

    // How much light this thing emits
    luminescence: usize,

    opacity: f64,

    pub const MaterialType = enum {
        Metal,
        I_Stone,
        S_Stone,
        M_Stone,
        Gem,
    };

    pub fn chunkTile(self: *const Material) u21 {
        return switch (self.type) {
            .Metal => '⁍',
            .I_Stone, .S_Stone, .M_Stone => '•',
            .Gem => '¤',
        };
    }

    pub fn chunkName(self: *const Material) []const u8 {
        return switch (self.type) {
            .Metal => "ingot",
            .I_Stone, .S_Stone, .M_Stone => "boulder",
            .Gem => "gem",
        };
    }
};

pub const MessageType = union(enum) {
    Prompt, // Prompt for a choice/input, or respond to result from previous prompt
    Status, // A status effect (or other misc effects, like disruption) was added or removed.
    Combat, // X hit you! You hit X!
    CombatUnimportant, // X missed you! You miss X! You slew X!
    Unimportant, // A bit dark, okay if player misses it.
    Info,
    Move, // TODO: merge with Info (only used for stairs rn)
    Trap, // TODO: merge with ... what? (only used for trap messages in surfaces.zig)
    Damage,
    Important,
    SpellCast,
    Inventory, // Grabbing, dropping, or equipping item
    Dialog,

    pub fn color(self: MessageType) u32 {
        return switch (self) {
            .Prompt => 0x34cdff, // cyan blue
            .Info => 0xdadeda, // creamy white
            .Move => 0xdadeda, // creamy white
            .Trap => 0xed254d, // pinkish red
            .Damage => 0xed254d, // pinkish red
            .Important => 0xed254d, // pinkish red
            .SpellCast => 0xdadeda, // creamy white
            .Status => colors.AQUAMARINE, // aquamarine
            .Combat => 0xdadeda, // creamy white
            .CombatUnimportant => 0x7a9cc7, // steel blue
            .Unimportant => 0x8019ac,
            .Inventory => 0x7a9cc7, // steel blue
            .Dialog => 0x9abce7, // lighter steel blue
        };
    }
};

pub const Resistance = enum {
    rFire,
    rElec,
    Armor,
    rFume,

    pub fn string(self: Resistance) []const u8 {
        return switch (self) {
            .rFire => "rFire",
            .rElec => "rElec",
            .Armor => "Armor",
            .rFume => "rFume",
        };
    }
};

pub const Damage = struct {
    lethal: bool = true, // If false, extra damage will be shaved
    amount: usize,
    by_mob: ?*Mob = null,
    source: DamageSource = .Other,
    blood: bool = true,

    kind: DamageKind = .Physical,

    // by_mob isn't null, but the damage done wasn't done in melee, ranged,
    // or spell attack. E.g., it could have been a fire or explosion caused by
    // by_mob.
    indirect: bool = false,

    // Whether to propagate electric damage to the surroundings if the mob
    // is conductive. Usually this will be true, but it will be false when
    // takeDamage is called recursively to prevent an infinite recursion.
    //
    propagate_elec_damage: bool = true,

    pub const DamageKind = enum {
        Physical,
        Fire,
        Electric,
        Irresistible,

        pub fn resist(self: DamageKind) ?Resistance {
            return switch (self) {
                .Physical => .Armor,
                .Fire => .rFire,
                .Electric => .rElec,
                .Irresistible => null,
            };
        }

        pub fn string(self: DamageKind) []const u8 {
            return switch (self) {
                .Physical => "dmg",
                .Fire => "fire",
                .Electric => "elec",
                .Irresistible => "irresist",
            };
        }

        pub fn stringLong(self: DamageKind) []const u8 {
            return switch (self) {
                .Physical => "physical",
                .Fire => "fire",
                .Electric => "electric",
                .Irresistible => "irresistible",
            };
        }
    };

    pub const DamageSource = enum {
        Other,
        MeleeAttack,
        RangedAttack,
        Stab,
        Explosion,
        Passive,
    };
};
pub const Activity = union(enum) {
    Interact,
    Rest,
    Move: Direction,
    Attack: struct {
        who: *Mob,
        direction: Direction,
        coord: Coord,
    },
    Teleport: Coord,
    Grab,
    Drop,
    Use,
    Throw,
    Fire,
    Cast,
    None,
};

pub const EnemyRecord = struct {
    mob: *Mob,
    last_seen: ?Coord,
    counter: usize,

    pub const AList = std.ArrayList(EnemyRecord);

    pub fn lastSeenOrCoord(self: *const EnemyRecord) Coord {
        return self.last_seen orelse self.mob.coord;
    }
};

pub const SuspiciousTileRecord = struct {
    coord: Coord,
    time_stared_at: usize = 0,
    age: usize = 0,
    unforgettable: bool = false,
};

pub const Message = struct {
    msg: [128:0]u8,
    type: MessageType,
    turn: usize,
    dups: usize = 0,
    noise: bool = false,
};

pub const Faction = enum(usize) {
    Necromancer = 0,
    Player = 1,
    CaveGoblins = 2,
    Revgenunkim = 3,
    Night = 4,

    pub const TOTAL = std.meta.fields(@This()).len;
};

pub const Status = enum {
    // Status list {{{

    // Ring status effects
    RingTeleportation, // No power field
    RingDamnation, // Power field == initial damage
    RingElectrocution, // Power field == damage
    RingExcision, // No power field
    RingConjuration, // No power field

    // Item-specific effects.
    DetectHeat, // Doesn't have a power field.
    DetectElec, // Doesn't have a power field.
    EtherealShield, // Doesn't have a power field.
    FumesVest, // Doesn't have a power field.

    // Causes monster to be considered hostile to all other monsters.
    //
    // Doesn't have a power field.
    Insane,

    // Causes a monster to forget any noise or enemies they ran across, and
    // return to a working state. When the status is depleted, all dementia
    // will be instantly cured.
    //
    // Doesn't have a power field.
    Amnesia,

    // Causes adjacent undead, enemy or not, to take TORMENT_UNDEAD_DAMAGE damage.
    //
    // Doesn't have a power field.
    TormentUndead,

    // Gives sharp reduction to enemy's morale.
    //
    // Doesn't have a power field
    Intimidating,

    // Variety of effects.
    //
    // Doesn't have a power field (yet?)
    Corruption,

    // Fire resistance.
    //
    // Doesn't have a power field to keep things simple.
    Fireproof,

    // Fire vulnerability.
    //
    // Doesn't have a power field to keep things simple.
    Flammable,

    // Prevents mob from seeing more than 1 tile in any direction.
    //
    // Doesn't have a power field.
    Blind,

    // Gives a free attack after evading an attack.
    //
    // Doesn't have a power field.
    Riposte,

    // Evade, Melee, and Missile nerfs.
    //
    // Doesn't have a power field.
    Debil,

    // Makes monster "share" electric damage to nearby mobs and through
    // conductive terrain.
    //
    // Doesn't have a power field.
    Conductive,

    // Monster always makes noise, unless it has .Sleeping status.
    //
    // Doesn't have a power field.
    Noisy,

    // Prevents a mob from doing their work AI and checking FOV for enemies.
    // If it hears a noise, it will awake.
    //
    // Doesn't have a power field.
    Sleeping,

    // Prevents a mob from taking their turn.
    //
    // Doesn't have a power field.
    Paralysis,

    // Prevents a mob from moving and dodging. When mob tries to move, the duration
    // decreases by a bit depending on how strong mob is.
    //
    // Doesn't have a power field.
    Held,

    // Allows mob to "see" presence of walls around sounds.
    //
    // Power field determines radius of effect.
    Echolocation,

    // Make mob emit light.
    //
    // Power field determines amount of light emitted.
    Corona,

    // Makes mob move and in random directions.
    //
    // Doesn't have a power field.
    Daze,

    // Prevents mobs from using diagonal moves.
    //
    // Doesn't have a power field.
    Disorient,

    // Makes mob fast or slow.
    //
    // Doesn't have a power field.
    Fast,
    Slow,

    // Makes the mob regenerate 1 HP per turn.
    //
    // Doesn't have a power field.
    Recuperate,

    // Slows down mob and gives sprays vomit everywhere.
    //
    // Doesn't have a power field.
    Nausea,

    // Removes 1-2 HP per turn and sets mob's coord on fire.
    //
    // Doesn't have a power field.
    Fire,

    // Raises strength and dexterity.
    //
    // Doesn't have a power field.
    Invigorate,

    // Forces mob to move in random directions instead of resting, scream,
    // and lose HP every turn.
    //
    // Power field determines maximum amount of HP that can be lost per turn.
    Pain,

    // Forces the mob to always flee.
    //
    // Doesn't have a power field.
    Fear,

    // Prevents mob from seeing in brightly-lit areas.
    //
    // Doesn't have a power field.
    DayBlindness,

    // Prevents mob from seeing in dimly-lit areas.
    //
    // Doesn't have a power field.
    NightBlindness,

    // Gives mob several combat/speed bonuses (and nerfs).
    //
    // Doesn't have a power field.
    Enraged,

    // Several effects:
    // - prevents a mob from getting bonuses when cornered
    //
    // Doesn't have a power field.
    Exhausted,

    // Makes the mob explode upon dying or the status running out.
    //
    // Power field is explosion strength.
    Explosive,

    // Makes the mob explode in a blast of electricty upon dying or the status
    // running out.
    //
    // Power field is maximum damage dealt.
    ExplosiveElec,

    // Makes the mob automatically suicide when the status runs out.
    //
    // Doesn't have a power field.
    Lifespan,

    // }}}

    pub const TOTAL = @typeInfo(@This()).Enum.fields.len;
    pub const MAX_DURATION: usize = 20;

    pub fn string(self: Status, mob: *const Mob) []const u8 { // {{{
        return switch (self) {
            .RingTeleportation => "ring: teleportation",
            .RingDamnation => "ring: damnation",
            .RingElectrocution => "ring: electrocution",
            .RingExcision => "ring: excision",
            .RingConjuration => "ring: conjuration",

            .DetectHeat => "detect heat",
            .DetectElec => "detect electricity",
            .EtherealShield => "ethereal shield",
            .FumesVest => "fuming vest",

            .Amnesia => "amnesia",
            .Insane => "insane",
            .TormentUndead => "torment undead",
            .Intimidating => "intimidating",
            .Corruption => "corrupted",
            .Fireproof => "fireproof",
            .Flammable => "flammable",
            .Blind => "blind",
            .Riposte => "riposte",
            .Debil => "debilitated",
            .Conductive => "conductive",
            .Noisy => "noisy",
            .Sleeping => switch (mob.life_type) {
                .Living => "sleeping",
                .Spectral, .Construct, .Undead => "dormant",
            },
            .Paralysis => "paralyzed",
            .Held => "held",
            .Echolocation => "echolocating",
            .Corona => "glowing",
            .Daze => "dazed",
            .Disorient => "disoriented",
            .Fast => "hasted",
            .Slow => "slowed",
            .Recuperate => "recuperating",
            .Nausea => "nauseated",
            .Fire => "burning",
            .Invigorate => "invigorated",
            .Pain => "pain",
            .Fear => "fear",
            .DayBlindness => "day-blinded",
            .NightBlindness => "night-blinded",
            .Enraged => "enraged",
            .Exhausted => "exhausted",
            .Explosive => "explosive",
            .ExplosiveElec => "charged",
            .Lifespan => "lifespan",
        };
    } // }}}

    pub fn miniString(self: Status) ?[]const u8 { // {{{
        return switch (self) {
            .RingTeleportation, .RingDamnation, .RingElectrocution, .RingExcision, .RingConjuration => null,

            .DetectHeat, .DetectElec, .Riposte, .EtherealShield, .FumesVest, .Echolocation, .DayBlindness, .NightBlindness, .Explosive, .ExplosiveElec, .Lifespan => null,

            .Amnesia => "amnesia",
            .Insane => "insane",
            .Intimidating => "intim",
            .TormentUndead => "trmnt undead",
            .Corruption => "corrupt",
            .Fireproof => "fireproof",
            .Flammable => "flammable",
            .Blind => "blind",
            .Debil => "debil",
            .Conductive => "conductve",
            .Noisy => "noisy",
            .Sleeping => "sleep",
            .Paralysis => "para",
            .Held => "held",
            .Corona => "glow",
            .Daze => "dazed",
            .Disorient => "disorient",
            .Fast => "hasted",
            .Slow => "slowed",
            .Recuperate => "recup",
            .Nausea => "nausea",
            .Fire => "burn",
            .Invigorate => "invig",
            .Pain => "pain",
            .Fear => "fear",
            .Enraged => "rage",
            .Exhausted => "exhausted",
        };
    } // }}}

    pub fn isMobImmune(self: Status, mob: *Mob) bool {
        if (mob == state.player) {
            switch (self) {
                .Amnesia, .Explosive, .ExplosiveElec, .Fear, .Insane, .Lifespan => return true,
                else => {},
            }
        }

        return switch (self) {
            // .Disorient => mob.life_type == .Construct,
            .Fire => mob.isFullyResistant(.rFire),
            .Exhausted,
            .Pain,
            .Fear,
            .Nausea,
            .Recuperate,
            .Daze,
            .Paralysis,
            .Debil,
            .Corruption,
            .Blind,
            => mob.life_type != .Living,
            else => false,
        };
    }

    pub fn jsonStringify(val: Status, opts: std.json.StringifyOptions, stream: anytype) !void {
        try std.json.stringify(val.string(state.player), opts, stream);
    }

    // Tick functions {{{

    pub fn tickDetectHeat(mob: *Mob) void {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(mob.coord.z, x, y);
                if (coord.distance(mob.coord) > DETECT_HEAT_RADIUS) {
                    continue;
                }

                if (state.dungeon.at(coord).mob) |othermob| {
                    if (othermob.ai.flag(.DetectWithHeat)) {
                        mob.fov[y][x] = 100;
                    }

                    if (othermob.hasStatus(.Fire)) {
                        mob.fov[y][x] = 100;
                    }
                }

                if (state.dungeon.machineAt(coord)) |machine| {
                    if (machine.detect_with_heat) {
                        for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |n| {
                            mob.fov[n.y][n.x] = 100;
                        };
                        mob.fov[y][x] = 100;
                    }
                }

                if (state.dungeon.fireAt(coord).* > 0 or
                    state.dungeon.at(coord).type == .Lava)
                {
                    for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |n| {
                        mob.fov[n.y][n.x] = 100;
                    };
                    mob.fov[y][x] = 100;
                }
            }
        }
    }

    pub fn tickDetectElec(mob: *Mob) void {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(mob.coord.z, x, y);
                if (coord.distance(mob.coord) > DETECT_ELEC_RADIUS) {
                    continue;
                }

                if (state.dungeon.at(coord).mob) |othermob| {
                    if (othermob.ai.flag(.DetectWithElec)) {
                        mob.fov[y][x] = 100;
                    }

                    if (othermob.hasStatus(.ExplosiveElec)) {
                        mob.fov[y][x] = 100;
                    }
                }

                if (state.dungeon.machineAt(coord)) |machine| {
                    if (machine.detect_with_elec) {
                        for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |n| {
                            mob.fov[n.y][n.x] = 100;
                        };
                        mob.fov[y][x] = 100;
                    }
                }
            }
        }
    }

    pub fn tickTormentUndead(mob: *Mob) void {
        for (&DIRECTIONS) |d| if (utils.getMobInDirection(mob, d)) |othermob| {
            if (othermob.life_type != .Undead)
                continue;

            // It's adjacent, should be seen...
            assert(mob.cansee(othermob.coord));

            if (othermob.isHostileTo(mob)) {
                ai.updateEnemyKnowledge(othermob, mob, null);
            }

            // FIXME: reduce duplicated will-checking code between this and spells.cast()
            if (!spells.willSucceedAgainstMob(mob, othermob)) {
                if (state.player.cansee(othermob.coord) or state.player.cansee(mob.coord)) {
                    const chance = 100 - spells.appxChanceOfWillOverpowered(mob, othermob);
                    state.message(.SpellCast, "{c} resisted $oTorment Undead$. $g($c{}%$g chance)$.", .{ othermob, chance });
                }
                continue;
            }

            othermob.takeDamage(.{
                .amount = TORMENT_UNDEAD_DAMAGE,
                .by_mob = mob,
                .kind = .Irresistible,
                .blood = false,
                .source = .Passive,
            }, .{
                .strs = &[_]DamageStr{
                    items._dmgstr(99, "torment", "torments", ""),
                    // When it is completely destroyed, it has been dispelled
                    items._dmgstr(100, "dispel", "dispels", ""),
                },
            });
        } else |_| {};
    }

    pub fn tickNoisy(mob: *Mob) void {
        if (mob.isUnderStatus(.Sleeping) == null)
            mob.makeNoise(.Movement, .Medium);
    }

    pub fn tickRecuperate(mob: *Mob) void {
        mob.HP = math.clamp(mob.HP + 1, 0, mob.max_HP);
    }

    pub fn tickNausea(mob: *Mob) void {
        if (state.ticks % 3 == 0) {
            state.messageAboutMob(mob, null, .Unimportant, "retch profusely.", .{}, "retches profusely.", .{});
            state.dungeon.spatter(mob.coord, .Vomit);
        }
    }

    pub fn tickFire(mob: *Mob) void {
        if (state.dungeon.terrainAt(mob.coord).fire_retardant) {
            mob.cancelStatus(.Fire);
            return;
        }

        if (!mob.isFullyResistant(.rFire)) { // Don't spam "you are scorched" messages
            if (rng.percent(@as(usize, 50))) {
                mob.takeDamage(.{ .amount = 1, .kind = .Fire, .blood = false }, .{
                    .noun = "The fire",
                    .strs = &[_]DamageStr{
                        items._dmgstr(0, "BUG", "BUG", ""),
                        items._dmgstr(20, "BUG", "scorches", ""),
                        items._dmgstr(80, "BUG", "burns", ""),
                        items._dmgstr(100, "BUG", "burns", " horribly"),
                    },
                });
            }
        }

        if (state.dungeon.fireAt(mob.coord).* == 0) {
            // Don't create too much fire from permanently-burning monsters, or
            // they'll burn the entire dungeon down when exploring/investigating
            if (mob.isUnderStatus(.Fire).?.duration == .Prm)
                fire.setTileOnFire(mob.coord, 3)
            else
                fire.setTileOnFire(mob.coord, null);
        }
    }

    pub fn tickPain(mob: *Mob) void {
        const st = mob.isUnderStatus(.Pain).?;

        const damage = rng.rangeClumping(usize, 0, st.power, 2);
        if (damage > 0) {
            mob.takeDamage(.{ .amount = damage, .blood = false }, .{
                .noun = "The pain",
                .strs = &[_]DamageStr{items._dmgstr(0, "weaken", "weakens", "")},
            });
        }
    }

    pub fn tickEcholocation(mob: *Mob) void {
        if (!mob.coord.eq(state.player.coord)) return;

        // TODO: do some tests and figure out what's the practical limit to memory
        // usage, and reduce the buffer's size to that.
        var membuf: [65535]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

        const st = state.player.isUnderStatus(.Echolocation).?;

        const radius = @intCast(usize, state.player.stat(.Vision));
        const z = state.player.coord.z;
        const ystart = state.player.coord.y -| radius;
        const yend = math.min(state.player.coord.y + radius, HEIGHT);
        const xstart = state.player.coord.x -| radius;
        const xend = math.min(state.player.coord.x + radius, WIDTH);

        var tile: state.MemoryTile = .{
            .tile = .{
                .fg = 0xffffff,
                .bg = colors.BG,
                .ch = '#',
            },
            .type = .Echolocated,
        };

        var y: usize = ystart;
        while (y < yend) : (y += 1) {
            var x: usize = xstart;
            while (x < xend) : (x += 1) {
                const coord = Coord.new2(z, x, y);
                if (state.player.canHear(coord) == null)
                    continue;

                var dijk = dijkstra.Dijkstra.init(
                    coord,
                    state.mapgeometry,
                    st.power,
                    dijkstra.dummyIsValid,
                    .{},
                    fba.allocator(),
                );
                defer dijk.deinit();
                while (dijk.next()) |item| {
                    if (state.dungeon.neighboringWalls(item, true) == 9) {
                        dijk.skip();
                        continue;
                    }

                    tile.tile.ch = if (state.dungeon.at(item).type == .Wall) '#' else '·';
                    _ = state.memory.getOrPutValue(item, tile) catch err.wat();
                }
            }
        }
    }

    // Helper for tickFOV when Corruption status is active
    // Implements detect undead.
    //
    pub fn _revealUndead(mob: *Mob) void {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(mob.coord.z, x, y);
                if (coord.distance(mob.coord) > DETECT_UNDEAD_RADIUS) {
                    continue;
                }

                if (state.dungeon.at(coord).mob) |othermob| {
                    if (othermob.life_type == .Undead) {
                        for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |n| {
                            mob.fov[n.y][n.x] = 100;
                        };
                        mob.fov[y][x] = 100;
                    }
                }
            }
        }
    }

    // }}}
};

pub const StatusDataInfo = struct {
    // This field doesn't matter when it's in mob.statuses
    status: Status = undefined,

    // What's the "power" of a status. For most statuses, doesn't mean anything
    // at all.
    power: usize = 0,

    // How long the status should last.
    //
    // If Tmp, decremented each turn.
    duration: Duration = .{ .Tmp = 0 },

    // Whether to give the .Exhaust status after the effect is over.
    exhausting: bool = false,

    pub const Duration = union(enum) {
        Prm,
        Equ,
        Tmp: usize,
        Ctx: ?*const surfaces.Terrain,

        pub fn jsonStringify(val: Duration, opts: std.json.StringifyOptions, stream: anytype) !void {
            try stream.writeByte('{');

            try stream.writeAll("\"duration_type\":");
            try stream.writeByte('"');
            try stream.writeAll(@tagName(val));
            try stream.writeByte('"');
            try stream.writeByte(',');

            // val.Ctx should never be null, in theory, but it is an optional
            // for some reason... Just putting a check here to be safe...
            //
            if (val == .Tmp or (val == .Ctx and val.Ctx != null)) {
                try stream.writeAll("\"duration_arg\":");
                if (val == .Tmp) {
                    try std.json.stringify(val.Tmp, opts, stream);
                } else {
                    try std.json.stringify(val.Ctx.?.id, opts, stream);
                }
            }

            try stream.writeByte('}');
        }
    };
};

pub const AIPhase = enum { Work, Hunt, Investigate, Flee };

pub const AI = struct {
    // Name of mob doing the profession.
    profession_name: ?[]const u8 = null,

    // Description of what the mob is doing. Examples: Guard("patrolling"),
    // Smith("forging"), Demon("sulking")
    profession_description: []const u8,

    // The area where the mob should be doing work.
    work_area: CoordArrayList = undefined,

    // Work callbacks:
    //     - work_fn:  on each tick when the mob is doing work.
    //     - fight_fn: on each tick when the mob is pursuing a hostile mob.
    //
    work_fn: fn (*Mob, mem.Allocator) void,
    fight_fn: ?fn (*Mob, mem.Allocator) void,

    // Should the mob attack hostiles?
    is_combative: bool = true,

    // Should the mob investigate noises?
    is_curious: bool = true,

    // Should the mob ever flee at low health?
    is_fearless: bool = false,

    // What should a mage-fighter do when it didn't/couldn't cast a spell?
    //
    // Obviously, only makes sense on mages.
    spellcaster_backup_action: union(enum) { KeepDistance, Melee, Flee } = .Melee,

    flee_effect: ?StatusDataInfo = null,

    // The "target" in any phase (except .Hunt, the target for that is in
    // the enemy records).
    target: ?Coord = null,

    // For a laborer (cleaner/hauler), the associated task ID.
    // The task ID is simply the index for state.tasks.
    task_id: ?usize = null,

    phase: AIPhase = .Work,

    // The particular phase of a mob's work phase. For instance a working Cleaner
    // might be scanning, idling, or cleaning.
    work_phase: AIWorkPhase = undefined,

    flags: []const Flag = &[_]Flag{},

    pub const Flag = enum {
        AwakesNearAllies, // If the monster is dormant, it awakes near allies.
        SocialFighter, // Won't fight unless there are aware allies around.
        SocialFighter2, // Like above, but doesn't need allies to be aware.
        CalledWithUndead, // Can be called by CAST_CALL_UNDEAD, even if not undead.
        FearsDarkness, // Tries very hard to stay in light areas (pathfinding).
        FearsLight, // Opposite of FearsDarkness (pathfinding).
        MovesDiagonally, // Usually tries to move diagonally.
        DetectWithHeat, // Detected with .DetectHeat status
        DetectWithElec, // Detected with .DetectElec status
        AvoidsEnemies, // A* penalty for enemy monsters. For prisoners/stalkers.
        IgnoredByEnemies, // Hacky fix for prisoners continually hacking at statues.
        IgnoresEnemiesUnknownToLeader, // Won't attack enemies that the leader can't see
        ForceNormalWork, // Continue normal work even when in squad with leader.
        WallLover, // Considers areas without adjacent walls to be unwalkable.
    };

    pub fn flag(self: *const AI, f: Flag) bool {
        return mem.containsAtLeast(Flag, self.flags, 1, &[_]Flag{f});
    }
};

pub const AIWorkPhase = enum {
    NC_Guard,
    NC_PatrolTo,
    NC_MoveTo,
    CleanerScan,
    CleanerClean,
    HaulerScan,
    HaulerTake,
    HaulerDrop,
};

pub const AIJob = struct {
    job: Type,
    ctx: Ctx,

    pub const Ctx = std.StringHashMap(Value);
    pub const JStatus = enum { Defer, Ongoing, Complete };

    pub const Value = union(enum) {
        bool: bool,
    };

    pub const Type = enum {
        SPC_NCAlignment,

        pub fn func(self: @This()) fn (*Mob, *AIJob) JStatus {
            return switch (self) {
                .SPC_NCAlignment => ai._Job_SPC_NCAlignment,
            };
        }
    };

    pub fn deinit(self: *@This()) void {
        self.ctx.deinit();
    }

    pub fn getCtx(self: *@This(), comptime T: type, key: []const u8, default: T) T {
        const default_v = @unionInit(Value, @typeName(T), default);
        const entry = self.ctx.getOrPutValue(key, default_v) catch err.wat();
        return @field(entry.value_ptr, @typeName(T));
    }

    pub fn setCtx(self: *@This(), comptime T: type, key: []const u8, val: T) void {
        const val_v = @unionInit(Value, @typeName(T), val);
        self.ctx.put(key, val_v) catch err.wat();
    }
};

pub const Prisoner = struct {
    of: Faction,
    held_by: ?union(enum) { Mob: *const Mob, Prop: *const Prop } = null,

    pub fn heldAt(self: *const Prisoner) Coord {
        assert(self.held_by != null);

        return switch (self.held_by.?) {
            .Mob => |m| m.coord,
            .Prop => |p| p.coord,
        };
    }
};

pub const Species = struct {
    name: []const u8,
    default_attack: *const Weapon = &items.FistWeapon,
    aux_attacks: []const *const Weapon = &[_]*const Weapon{},
};

pub const Squad = struct {
    // linked list stuff
    __next: ?*Squad = null,
    __prev: ?*Squad = null,

    members: StackBuffer(*Mob, 64) = StackBuffer(*Mob, 64).init(null),
    leader: ?*Mob = null, // FIXME: Should never be null in practice!
    enemies: EnemyRecord.AList = undefined,

    pub const List = LinkedList(Squad);

    pub fn allocNew() *Squad {
        const squad = Squad{
            //.members = MobArrayList.init(state.GPA.allocator()),
            .enemies = EnemyRecord.AList.init(state.GPA.allocator()),
        };
        state.squads.append(squad) catch err.wat();
        return state.squads.last().?;
    }

    // Remove dead members. Should be called before adding to player's squad, in
    // case it's full of long-dead allies.
    //
    pub fn trimMembers(self: *Squad) void {
        var newmembers = @TypeOf(self.members).init(null);
        for (self.members.constSlice()) |member| {
            // TODO: hostility checks?
            if (!member.is_dead)
                newmembers.append(member) catch err.wat();
        }
        self.members = newmembers;
    }

    pub fn deinit(self: *Squad) void {
        self.enemies.deinit();
    }
};

pub const Stat = enum {
    Melee,
    Missile,
    Martial,
    Evade,
    Speed,
    Sneak,
    Vision,
    Willpower,
    Spikes,
    Conjuration,

    pub fn string(self: Stat) []const u8 {
        return switch (self) {
            .Melee => "melee%",
            .Missile => "missile%",
            .Martial => "martial",
            .Evade => "evade%",
            .Speed => "speed",
            .Sneak => "sneak",
            .Vision => "vision",
            .Willpower => "will",
            .Spikes => "spikes",
            .Conjuration => "conjuration",
        };
    }

    pub fn showMobStat(self: Stat, value: isize) bool {
        return switch (self) {
            .Melee, .Evade, .Vision, .Willpower => true,
            .Sneak => false,
            .Missile => value != 40,
            .Speed => value != 100,
            .Martial, .Spikes, .Conjuration => value > 0,
        };
    }
};

pub const Mob = struct { // {{{
    // linked list stuff
    __next: ?*Mob = null,
    __prev: ?*Mob = null,

    id: []const u8,
    species: *const Species,
    prefix: []const u8 = "",
    tile: u21,
    faction: Faction = .Necromancer,

    squad: ?*Squad = null,
    prisoner_status: ?Prisoner = null,
    linked_fovs: StackBuffer(*Mob, 16) = StackBuffer(*Mob, 16).init(null),

    fov: [HEIGHT][WIDTH]usize = [1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT,
    path_cache: std.AutoHashMap(Path, Coord) = undefined,
    enemies: EnemyRecord.AList = undefined,
    allies: MobArrayList = undefined,
    sustiles: std.ArrayList(SuspiciousTileRecord) = undefined,
    jobs: StackBuffer(AIJob, 16) = StackBuffer(AIJob, 16).init(null),

    // "Push" flag, set when mob pushes past or is pushed past.
    // Reset on each turn.
    //
    // Taken from Unangband:
    //
    // > To avoid this situation, I added the MFLAG_PUSH flag, to which was set
    // > on both monsters, when one pushes past the other. And when a monster has
    // > MFLAG_PUSH set, it becomes unpushable, until the start of its next move,
    // > at which point it is cleared. The flag is set on both monsters to
    // > prevent either getting 'free moves' by being pushed around by multiple
    // > monsters: originally I did this to prevent a monster that must swim
    // > being pushed beyond the edge of water (which requires two consecutive
    // > pushes), but it equally applied to stop a powerful monster getting
    // > multiple moves against the player.
    // -- http://roguelikedeveloper.blogspot.com/2007/10/unangband-monster-ai-part-three.html
    //
    push_flag: bool = false,

    facing: Direction = .North,
    coord: Coord = Coord.new(0, 0),

    HP: usize = 0xAA,
    energy: isize = 0,
    statuses: StatusArray = StatusArray.initFill(.{}),
    ai: AI,
    activities: RingBuffer(Activity, MAX_ACTIVITY_BUFFER_SZ) = .{},
    last_attempted_move: ?Direction = null,
    last_damage: ?Damage = null,
    corruption_ctr: usize = 0,

    inventory: Inventory = .{},

    life_type: enum { Living, Spectral, Construct, Undead } = .Living,
    multitile: ?usize = null,
    is_dead: bool = true,
    is_death_reported: bool = false,
    is_death_verified: bool = false,
    killed_by: ?*Mob = null,

    // Immutable instrinsic attributes.
    //
    // base_night_vision:  Whether the mob can see in darkness.
    // deg360_vision:      Mob's FOV ignores the facing mechanic and can see in all
    //                     directions (e.g., player, statues)
    // no_show_fov:        If false, ui code will not show mob's FOV.
    // memory:             The maximum length of time for which a mob can remember
    //                     an enemy.
    // deaf:               Whether it can hear sounds.
    //
    base_night_vision: bool = false,
    deg360_vision: bool = false,
    no_show_fov: bool = false,
    memory_duration: usize = 4,
    deaf: bool = false,
    max_HP: usize,
    immobile: bool = false,
    innate_resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
    blood: ?Spatter = .Blood,
    blood_spray: ?usize = null, // Gas ID
    corpse: enum { Normal, Wall, Dust, None } = .Normal,
    slain_trigger: union(enum) { None, Disintegrate: []const *const mobs.MobTemplate } = .None,

    //stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    stats: MobStat = .{},

    // Listed in order of preference.
    spells: []const SpellOptions = &[_]SpellOptions{},

    max_MP: usize = 0,
    MP: usize = 0,

    // Don't use EnumFieldStruct here because we want to provide per-field
    // defaults.
    pub const MobStat = struct {
        Melee: isize = 60,
        Missile: isize = 40,
        Martial: isize = 0,
        Evade: isize = 0,
        Speed: isize = 100,
        Sneak: isize = 1,
        Vision: isize = 7,
        Willpower: isize = 3,
        Spikes: isize = 0,
        Conjuration: isize = 0,
    };

    pub const Inventory = struct {
        pack: PackBuffer = PackBuffer.init(&[_]Item{}),
        equ_slots: [EQU_SLOT_SIZE]?Item = [_]?Item{null} ** EQU_SLOT_SIZE,

        pub const RING_SLOTS = [_]EquSlot{ .Ring1, .Ring2, .Ring3, .Ring4, .Ring5 };

        pub const EquSlot = enum(usize) {
            Weapon = 0,
            Backup = 1,
            Aux = 2,
            Ring1 = 3,
            Ring2 = 4,
            Ring3 = 5,
            Ring4 = 6,
            Ring5 = 7,
            Armor = 8,
            Cloak = 9,

            pub fn slotFor(item: Item) EquSlot {
                return switch (item) {
                    .Weapon => .Weapon,
                    .Ring => err.bug("Tried to get equipment slot for ring", .{}),
                    .Armor => .Armor,
                    .Cloak => .Cloak,
                    .Aux => .Aux,
                    else => err.wat(),
                };
            }

            pub fn name(self: EquSlot) []const u8 {
                return switch (self) {
                    .Weapon => "weapon",
                    .Backup => "backup",
                    .Aux => "aux",
                    .Ring1, .Ring2, .Ring3, .Ring4, .Ring5 => "ring",
                    .Armor => "armor",
                    .Cloak => "cloak",
                };
            }
        };

        pub const EQU_SLOT_SIZE = utils.directEnumArrayLen(EquSlot);
        pub const PACK_SIZE: usize = 10;
        pub const PackBuffer = StackBuffer(Item, PACK_SIZE);

        pub fn equipment(self: *Inventory, eq: EquSlot) *?Item {
            return &self.equ_slots[@enumToInt(eq)];
        }

        pub fn equipmentConst(self: *const Inventory, eq: EquSlot) *const ?Item {
            return &self.equ_slots[@enumToInt(eq)];
        }
    };

    // Size of `activities` Ringbuffer
    pub const MAX_ACTIVITY_BUFFER_SZ = 10;

    pub fn displayName(self: *const Mob) []const u8 {
        const Static = struct {
            var buf: [32]u8 = undefined;
        };

        const base_name = self.ai.profession_name orelse self.species.name;

        var fbs = std.io.fixedBufferStream(&Static.buf);
        std.fmt.format(fbs.writer(), "{s}{s}", .{ self.prefix, base_name }) catch err.wat();
        return fbs.getWritten();
    }

    pub fn format(self: *const Mob, comptime f: []const u8, opts: fmt.FormatOptions, writer: anytype) !void {
        _ = opts;

        comptime var caps = false;
        comptime var force = false;

        inline for (f) |char| switch (char) {
            'c' => caps = true,
            'f' => force = true,
            else => @compileError("Unknown format string: '" ++ f ++ "'"),
        };

        if (self == state.player) {
            const n = if (caps) "You" else "you";
            try fmt.format(writer, "{s}", .{n});
        } else if (!state.player.cansee(self.coord) and !force) {
            const n = if (caps) "Something" else "something";
            try fmt.format(writer, "{s}", .{n});
        } else {
            const the = if (caps) "The" else "the";
            try fmt.format(writer, "{s} {s}", .{ the, self.displayName() });
        }
    }

    pub fn areaRect(self: *const Mob) Rect {
        const l = self.multitile orelse 1;
        return Rect{ .start = self.coord, .width = l, .height = l };
    }

    pub fn tickDisruption(self: *Mob) void {
        if (self.faction == .Necromancer and self.life_type == .Undead and
            self.ai.phase == .Hunt)
        {
            combat.disruptIndividualUndead(self);
        }
    }

    pub fn tickFOV(self: *Mob) void {
        for (self.fov) |*row| for (row) |*cell| {
            cell.* = 0;
        };

        if (self.isUnderStatus(.Sleeping)) |_| return;

        const is_blinded = self.isUnderStatus(.Blind) != null;
        const light_needs = [_]bool{ self.canSeeInLight(false), self.canSeeInLight(true) };

        const vision = @intCast(usize, self.stat(.Vision));
        const energy = math.clamp(vision * Dungeon.FLOOR_OPACITY, 0, 100);
        const direction = if (self.deg360_vision) null else self.facing;

        // Handle multitile creatures
        var eyes = Rect{ .start = self.coord, .width = 1, .height = 1 };
        if (direction != null and self.multitile != null) {
            const area = self.areaRect();
            eyes = switch (direction.?) {
                .North => Rect.new(area.start, self.multitile.?, 1),
                .South => Rect.new(Coord.new2(self.coord.z, area.start.x, area.end().y), self.multitile.?, 1),
                .East => Rect.new(Coord.new2(self.coord.z, area.end().x, area.start.y), 1, self.multitile.?),
                .West => Rect.new(area.start, 1, self.multitile.?),
                .NorthWest => Rect.new(area.start, 1, 1),
                .NorthEast => Rect.new(Coord.new2(self.coord.z, area.end().x - 1, area.start.y), 1, 1),
                .SouthWest => Rect.new(Coord.new2(self.coord.z, area.start.x, area.end().y), 1, 1),
                .SouthEast => Rect.new(Coord.new2(self.coord.z, area.end().x - 1, area.end().y), 1, 1),
            };
        }

        var gen = Generator(Rect.rectIter).init(eyes);
        while (gen.next()) |eye_coord|
            fov.rayCast(eye_coord, vision, energy, Dungeon.tileOpacity, &self.fov, direction, self == state.player);

        for (self.fov) |row, y| for (row) |_, x| {
            if (self.fov[y][x] > 0) {
                const fc = Coord.new2(self.coord.z, x, y);
                const light = state.dungeon.lightAt(fc).*;

                // If a tile is too dim to be seen by a mob and the tile isn't
                // adjacent to that mob, mark it as unlit.
                if (fc.distance(self.coordMT(fc)) > 1 and
                    (!light_needs[@boolToInt(light)] or is_blinded))
                {
                    self.fov[y][x] = 0;
                    continue;
                }
            }
        };
        self.fov[self.coord.y][self.coord.x] = 100;

        // Clear out linked-fovs list of dead/non-z-level mobs
        if (self.linked_fovs.len > 0) {
            var new_linked_fovs = @TypeOf(self.linked_fovs).init(null);
            for (self.linked_fovs.constSlice()) |linked_fov_mob|
                if (!linked_fov_mob.is_dead and linked_fov_mob.coord.z == self.coord.z)
                    new_linked_fovs.append(linked_fov_mob) catch unreachable;
            self.linked_fovs = new_linked_fovs;
        }

        for (self.linked_fovs.constSlice()) |linked_fov_mob| {
            for (linked_fov_mob.fov) |row, y| for (row) |_, x| {
                if (linked_fov_mob.fov[y][x] > 0) {
                    self.fov[y][x] = 100;
                }
            };
        }

        if (self.hasStatus(.Corruption)) {
            Status._revealUndead(self);
        }
    }

    // Misc stuff.
    pub fn tick_env(self: *Mob) void {
        self.push_flag = false;
        self.MP = math.clamp(self.MP + 1, 0, self.max_MP);

        // Gases
        const gases = state.dungeon.atGas(self.coord);
        for (gases) |quantity, gasi| {
            if ((rng.range(usize, 0, 100) < self.resistance(.rFume) or gas.Gases[gasi].not_breathed) and quantity > 0.0) {
                gas.Gases[gasi].trigger(self, quantity);
            }
        }

        // Corruption effects
        if (self.life_type == .Living and !self.hasStatus(.Corruption)) {
            const adjacent_undead: ?*Mob = for (&DIRECTIONS) |d| {
                if (utils.getHostileInDirection(self, d)) |hostile| {
                    if (hostile.life_type == .Undead)
                        break hostile;
                } else |_| {}
            } else null;

            if (adjacent_undead) |hostile| {
                self.corruption_ctr += 1;
                if (self.corruption_ctr >= self.stat(.Willpower)) {
                    if (self == state.player) {
                        scores.recordTaggedUsize(.TimesCorrupted, .{ .M = hostile }, 1);
                    }
                    if (state.player.cansee(self.coord)) {
                        state.message(.Combat, "{c} corrupts {}!", .{ hostile, self });
                    }
                    self.addStatus(.Corruption, 0, .{ .Tmp = 7 });
                    ai.updateEnemyKnowledge(hostile, self, null);
                    self.corruption_ctr = 0;
                }
            } else {
                self.corruption_ctr = 0;
            }
        }

        // Player conjuration augments
        if (self == state.player and player.hasSabresInSight()) {
            var spawn_ctr = 0 +
                (if (player.hasAugment(.WallDisintegrate1)) @as(usize, 1) else 0) +
                (if (player.hasAugment(.WallDisintegrate2)) @as(usize, 2) else 0);
            for (&DIRECTIONS) |d| {
                if (spawn_ctr == 0)
                    break;
                if (state.player.coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.dungeon.at(neighbor).type == .Wall) {
                        state.dungeon.at(neighbor).type = .Floor;
                        spells.spawnSabreSingle(state.player, neighbor);
                        state.message(.Info, "A nearby wall disintegrates into a spectral sabre.", .{});
                        spawn_ctr -= 1;
                    }
                }
            }
        }
    }

    // Decrement status durations, and do stuff for various statuses that need
    // babysitting each turn.
    pub fn tickStatuses(self: *Mob) void {
        const terrain = state.dungeon.terrainAt(self.coord);
        for (terrain.effects) |effect| {
            var adj_effect = effect;

            // Set the dummy .Ctx durations' values.
            //
            if (meta.activeTag(effect.duration) == .Ctx) {
                adj_effect.duration = .{ .Ctx = terrain };
            }

            self.applyStatus(adj_effect, .{});
        }

        inline for (@typeInfo(Status).Enum.fields) |status| {
            const status_e = @field(Status, status.name);

            // Decrement
            if (self.isUnderStatus(status_e)) |status_data| {
                const status_type = meta.activeTag(status_data.duration);
                if (status_type == .Tmp) {
                    var n_status_data = status_data.*;
                    n_status_data.duration = .{ .Tmp = n_status_data.duration.Tmp -| 1 };
                    self.applyStatus(n_status_data, .{
                        .add_duration = false,
                        .replace_duration = true,
                    });
                } else if (status_type == .Ctx) {
                    if (status_data.duration.Ctx != terrain) {
                        self.cancelStatus(status_e);
                    }
                }
            }

            if (self.isUnderStatus(status_e)) |_| {
                if (self == state.player) {
                    scores.recordTaggedUsize(.StatusRecord, .{ .s = status_e.string(self) }, 1);
                }

                switch (status_e) {
                    .DetectHeat => Status.tickDetectHeat(self),
                    .DetectElec => Status.tickDetectElec(self),
                    .TormentUndead => Status.tickTormentUndead(self),
                    .Noisy => Status.tickNoisy(self),
                    .Echolocation => Status.tickEcholocation(self),
                    .Recuperate => Status.tickRecuperate(self),
                    .Nausea => Status.tickNausea(self),
                    .Fire => Status.tickFire(self),
                    .Pain => Status.tickPain(self),
                    else => {},
                }
            }
        }
    }

    pub fn swapWeapons(self: *Mob) void {
        const weapon = self.inventory.equipment(.Weapon).*;
        const backup = self.inventory.equipment(.Backup).*;

        if (weapon) |_| self.dequipItem(.Weapon, null);
        if (backup) |_| self.dequipItem(.Backup, null);

        if (weapon) |i| self.equipItem(.Backup, i);
        if (backup) |i| self.equipItem(.Weapon, i);
    }

    pub fn equipItem(self: *Mob, slot: Inventory.EquSlot, item: Item) void {
        if (slot != .Backup) {
            switch (item) {
                .Weapon => |w| for (w.equip_effects) |effect| self.applyStatus(effect, .{}),
                .Armor => |a| for (a.equip_effects) |effect| self.applyStatus(effect, .{}),
                .Aux => |a| for (a.equip_effects) |effect| self.applyStatus(effect, .{}),
                else => {},
            }
        }
        self.inventory.equipment(slot).* = item;
    }

    pub fn dequipItem(self: *Mob, slot: Inventory.EquSlot, drop_coord: ?Coord) void {
        const item = self.inventory.equipment(slot).*.?;
        if (slot != .Backup and
            (item == .Weapon or item == .Aux))
        {
            const equip_effects = switch (item) {
                .Weapon => |w| w.equip_effects,
                .Armor => |a| a.equip_effects,
                .Aux => |a| a.equip_effects,
                else => unreachable,
            };

            for (equip_effects) |effect| {
                if (self.isUnderStatus(effect.status)) |effect_info| {
                    if (effect_info.duration == .Equ) {
                        self.cancelStatus(effect.status);
                    }
                }
            }
        }
        if (drop_coord) |c|
            state.dungeon.itemsAt(c).append(item) catch err.wat();
        self.inventory.equipment(slot).* = null;
    }

    pub fn removeItem(self: *Mob, index: usize) !Item {
        if (index >= self.inventory.pack.len)
            return error.IndexOutOfRange;

        return self.inventory.pack.orderedRemove(index) catch err.wat();
    }

    // This is what happens when you flail to dodge a net.
    //
    // If held, flail around trying to get free.
    //
    pub fn flailAround(self: *Mob) void {
        if (self.isUnderStatus(.Held)) |se| {
            const new_duration = se.duration.Tmp -| 1;

            self.applyStatus(.{
                .status = .Held,
                .power = 0,
                .duration = .{ .Tmp = new_duration },
            }, .{ .replace_duration = true, .add_duration = false });

            if (self.isUnderStatus(.Held)) |_| {
                state.messageAboutMob(self, self.coord, .Info, "flail around helplessly.", .{}, "flails around helplessly.", .{});
            }

            self.rest();
        } else err.bug("Tried to make a non-.Held mob flail around!", .{});
    }

    // Use a consumable.
    //
    // direct: was the consumable used directly (i.e., was it thrown at the
    //   mob or did the mob use it?). Used to determine whether to print a
    //   message.
    pub fn useConsumable(self: *Mob, item: *const Consumable, direct: bool) !void {
        if (item.is_potion and direct and self.isUnderStatus(.Nausea) != null) {
            err.bug("Nauseated mob is quaffing potions!", .{});
        }

        if (direct) {
            const verbs = if (state.player == self) item.verbs_player else item.verbs_other;
            const verb = rng.chooseUnweighted([]const u8, verbs);
            state.message(.Info, "{c} {s} a {s}!", .{ self, verb, item.name });
        }

        for (item.effects) |effect| switch (effect) {
            .Status => |s| if (direct) self.addStatus(s, 0, .{ .Tmp = Status.MAX_DURATION }),
            .Gas => |s| state.dungeon.atGas(self.coord)[s] = 1.0,
            .Damage => |d| self.takeDamage(.{
                .lethal = d.lethal,
                .amount = d.amount,
                .kind = d.kind,
                .by_mob = self,
            }, .{ .basic = true }),
            .Heal => |h| self.takeHealing(h),
            .Resist => |r| utils.getFieldByEnumPtr(Resistance, *isize, &self.innate_resists, r.r).* += r.change,
            .Stat => |s| utils.getFieldByEnumPtr(Stat, *isize, &self.stats, s.s).* += s.change,
            .Kit => |template| {
                // TODO: generalize this code for all mobs & remove assert
                assert(self == state.player);

                if (state.dungeon.at(self.coord).surface) |_| {
                    return error.BadPosition;
                }

                var mach = template.*;
                mach.coord = self.coord;
                state.machines.append(mach) catch err.wat();
                state.dungeon.at(self.coord).surface = SurfaceItem{ .Machine = state.machines.last().? };
            },
            .Custom => |c| c(self, self.coord),
        };
    }

    pub fn dropItem(self: *Mob, item: Item, at: Coord) bool {
        // Some faulty AI might be doing this. Or maybe a stockpile is
        // configured incorrectly and a hauler is trying to drop items in the
        // wrong place.
        if (state.dungeon.at(at).type == .Wall) return false;

        if (state.dungeon.at(at).surface) |surface| {
            switch (surface) {
                .Container => |container| {
                    if (container.items.len >= container.capacity) {
                        return false;
                    } else {
                        container.items.append(item) catch err.wat();
                        self.declareAction(.Drop);
                        return true;
                    }
                },
                else => {},
            }
        }

        if (state.dungeon.itemsAt(at).isFull()) {
            return false;
        } else {
            state.dungeon.itemsAt(at).append(item) catch err.wat();
            self.declareAction(.Drop);
            return true;
        }
    }

    pub fn throwItem(self: *Mob, item: *const Item, at: Coord, alloc: mem.Allocator) void {
        const item_name = (item.*.shortName() catch err.wat()).constSlice();

        self.declareAction(.Throw);
        state.messageAboutMob(self, self.coord, .Info, "throw a {s}!", .{item_name}, "throws a {s}!", .{item_name});

        if (self == state.player) {
            scores.recordTaggedUsize(.ItemsThrown, .{ .I = item.* }, 1);
        }

        const dodgeable = switch (item.*) {
            .Projectile => true,
            .Consumable => |c| if (c.throwable) false else err.wat(),
            else => err.wat(),
        };

        const trajectory = self.coord.drawLine(at, state.mapgeometry, 3);
        const landed: ?Coord = for (trajectory.constSlice()) |coord| {
            if (self.coord.eq(coord)) continue;

            if (!state.is_walkable(coord, .{
                .right_now = true,
                .only_if_breaks_lof = true,
            })) {
                if (state.dungeon.at(coord).mob) |mob| {
                    const land_chance = combat.chanceOfMissileLanding(mob);
                    const evade_chance = combat.chanceOfAttackEvaded(mob, null);
                    if (dodgeable and (!rng.percent(land_chance) or rng.percent(evade_chance))) {
                        state.messageAboutMob(mob, self.coord, .CombatUnimportant, "dodge the {s}.", .{item_name}, "dodges the {s}.", .{item_name});
                        continue; // Evaded, onward!
                    } else {
                        //state.messageAboutMob(mob, self.coord, .Combat, "are hit by the {s}.", .{item_name}, "is hit by the {s}.", .{item_name});
                    }
                }

                break coord;
            }
        } else null;

        const tile = item.*.tile();
        ui.Animation.apply(.{ .TraverseLine = .{
            .start = self.coord,
            .end = landed orelse at,
            .char = tile.ch,
            .fg = tile.fg,
        } });

        switch (item.*) {
            .Projectile => |proj| {
                if (landed != null and state.dungeon.at(landed.?).mob != null) {
                    const mob = state.dungeon.at(landed.?).mob.?;
                    if (proj.damage) |max_damage| {
                        const damage = rng.range(usize, max_damage / 2, max_damage);
                        const msg_noun = StringBuf64.initFmt("The {s}", .{proj.name});
                        mob.takeDamage(.{ .amount = damage, .source = .RangedAttack, .by_mob = self }, .{ .noun = msg_noun.constSlice() });
                    }
                    switch (proj.effect) {
                        .Status => |s| mob.applyStatus(s, .{}),
                    }
                } else {
                    const spot = state.nextAvailableSpaceForItem(at, alloc);
                    if (spot) |_spot|
                        state.dungeon.itemsAt(_spot).append(item.*) catch err.wat();
                }
            },
            .Consumable => |c| {
                const coord = landed orelse at;
                if (state.dungeon.at(coord).mob) |mob| {
                    mob.useConsumable(c, false) catch |e|
                        err.bug("Couldn't use thrown consumable: {}", .{e});
                } else for (c.effects) |effect| switch (effect) {
                    .Gas => |s| state.dungeon.atGas(coord)[s] = 1.0,
                    .Custom => |f| f(null, coord),
                    else => {},
                };
            },
            else => err.wat(),
        }
    }

    pub fn declareAction(self: *Mob, action: Activity) void {
        assert(!self.is_dead);
        self.activities.append(action);
        self.energy -= @divTrunc(self.stat(.Speed) * 100, 100);
    }

    pub fn makeNoise(self: *Mob, s_type: SoundType, intensity: SoundIntensity) void {
        assert(!self.is_dead);

        var gen = Generator(Rect.rectIter).init(self.areaRect());
        while (gen.next()) |mobcoord|
            state.dungeon.soundAt(mobcoord).* = .{
                .mob_source = self,
                .intensity = intensity,
                .type = s_type,
                .state = .New,
                .when = state.ticks,
            };

        sound.announceSound(self.coordMT(state.player.coord));
    }

    pub fn addUnderling(self: *Mob, underling: *Mob) void {
        if (self.squad == null) {
            self.squad = Squad.allocNew();
            self.squad.?.leader = self;
            //
            // Copy over existing enemies.
            //
            // (Not doing this caused a bug where spectral totems conjure spectral
            // sabres, lose their enemy list (since a squad was added and enemylist now
            // points to the squad enemylist instead of the totem's enemylist),
            // and then fail an assertion right after <mob_fight_fn>() stating that
            // there should be at least one enemy in enemylist.
            //
            // Not sure why I wrote three paragraphs for a one-line fix.
            //
            self.squad.?.enemies.appendSlice(self.enemies.items[0..]) catch err.wat();
        }

        self.squad.?.trimMembers();
        self.squad.?.members.append(underling) catch err.wat();
        underling.squad = self.squad.?;
        underling.faction = self.faction;
    }

    // Check if a mob, when trying to move into a space that already has a mob,
    // can swap with that other mob.
    //
    pub fn canSwapWith(self: *const Mob, other: *Mob, opts: struct { ignore_hostility: bool = false }) bool {
        if (self.multitile != null or other.multitile != null) {
            return false;
        }

        return other != state.player and
            (opts.ignore_hostility or !other.isHostileTo(self)) and
            !other.immobile and
            (other.prisoner_status == null or other.prisoner_status.?.held_by == null) and
            (other.hasStatus(.Paralysis) or !other.push_flag);
    }

    // Try to move to a destination, one step at a time.
    //
    // Unlike the other move functions (teleportTo, moveInDirection) this
    // function is guaranteed to return with a lower time energy amount than
    // when it started with.
    //
    pub fn tryMoveTo(self: *Mob, dest: Coord) void {
        const prev_energy = self.energy;

        if (self.nextDirectionTo(dest)) |d| {
            if (!self.moveInDirection(d)) self.rest();
        } else ai.tryRest(self);

        assert(prev_energy > self.energy);
    }

    // Try to move a mob.
    pub fn moveInDirection(self: *Mob, p_direction: Direction) bool {
        const coord = self.coord;
        var direction = p_direction;

        // This should have been handled elsewhere (in the pathfinding code
        // for monsters, or in main:moveOrFight() for the player).
        //
        if (direction.is_diagonal() and self.isUnderStatus(.Disorient) != null)
            err.bug("Disoriented mob is trying to move diagonally!", .{});

        if (self.isUnderStatus(.Daze)) |_|
            direction = rng.chooseUnweighted(Direction, &DIRECTIONS);

        // Face in that direction and update last_attempted_move, no matter
        // whether we end up moving or no
        self.facing = direction;
        self.last_attempted_move = direction;

        if (self.isUnderStatus(.Held)) |_| {
            self.flailAround();
            return true;
        }

        var succeeded = false;
        if (coord.move(direction, state.mapgeometry)) |dest| {
            succeeded = self.teleportTo(dest, direction, false, false);
        } else {
            succeeded = false;
        }

        if (!succeeded and self.isUnderStatus(.Daze) != null) {
            if (self == state.player) {
                state.message(.Info, "You stumble around in a daze.", .{});
            } else if (state.player.cansee(self.coord)) {
                state.message(.Info, "The {s} stumbles around in a daze.", .{self.displayName()});
            }

            self.rest();
            return true;
        } else return succeeded;
    }

    pub fn teleportTo(self: *Mob, dest: Coord, direction: ?Direction, instant: bool, swap_ignore_hostility: bool) bool {
        if (self.multitile != null) {
            return self._teleportToMultitile(dest, direction, instant);
        }

        const coord = self.coord;

        if (self.prisoner_status) |prisoner|
            if (prisoner.held_by != null)
                return false;

        if (!state.is_walkable(dest, .{ .right_now = true, .ignore_mobs = true })) {
            if (state.dungeon.at(dest).surface) |surface| {
                switch (surface) {
                    .Machine => |m| if (!m.isWalkable()) {
                        if (self == state.player and
                            m.player_interact != null)
                        {
                            return player.activateSurfaceItem(dest);
                        } else if (m.addPower(self)) {
                            if (!instant)
                                self.declareAction(.Interact);
                            return true;
                        } else {
                            return false;
                        }
                    },
                    .Poster => |_| if (self == state.player) {
                        return player.triggerPoster(dest);
                    },
                    .Stair => |s| if (self == state.player) {
                        if (s) |floor| {
                            return player.triggerStair(dest, floor);
                        } else {
                            ui.drawAlertThenLog("It's suicide to go back!", .{});
                        }
                    },
                    else => {},
                }
            }

            return false;
        }

        if (state.dungeon.at(dest).mob) |other| {
            if (!self.canSwapWith(other, .{ .ignore_hostility = swap_ignore_hostility }))
                return false;

            self.coord = dest;
            state.dungeon.at(dest).mob = self;
            other.coord = coord;
            state.dungeon.at(coord).mob = other;

            other.push_flag = true;
            self.push_flag = true;

            if (other.isHostileTo(self)) {
                ai.updateEnemyKnowledge(other, self, null);
            }
        } else {
            self.coord = dest;
            state.dungeon.at(dest).mob = self;
            state.dungeon.at(coord).mob = null;
        }

        if (!instant) {
            if (direction) |d| {
                self.declareAction(Activity{ .Move = d });
            } else {
                self.declareAction(Activity{ .Teleport = dest });
            }
        }

        if (self.hasStatus(.FumesVest) and direction != null) {
            state.dungeon.atGas(coord)[gas.Darkness.id] += 0.02;
        }

        if (state.dungeon.at(dest).surface) |surface| {
            switch (surface) {
                .Machine => |m| if (m.isWalkable()) {
                    _ = m.addPower(self);
                },
                else => {},
            }
        }

        return true;
    }

    pub fn _teleportToMultitile(self: *Mob, dest: Coord, direction: ?Direction, instant: bool) bool {
        assert(!self.immobile);

        if (self.prisoner_status) |prisoner|
            if (prisoner.held_by != null)
                return false;

        if (!state.is_walkable(dest, .{ .right_now = true, .mob = self })) {
            return false;
        }

        {
            var gen = Generator(Rect.rectIter).init(self.areaRect());
            while (gen.next()) |mobcoord|
                state.dungeon.at(mobcoord).mob = null;
        }

        self.coord = dest;

        {
            var gen = Generator(Rect.rectIter).init(self.areaRect());
            while (gen.next()) |mobcoord| {
                assert(state.dungeon.at(mobcoord).mob == null);
                assert(state.dungeon.at(mobcoord).surface == null);
                state.dungeon.at(mobcoord).mob = self;
            }
        }

        if (!instant) {
            if (direction) |d| {
                self.declareAction(Activity{ .Move = d });
            } else {
                self.declareAction(Activity{ .Teleport = dest });
            }
        }

        return true;
    }

    pub fn rest(self: *Mob) void {
        // Commenting this out because this fn might need to be used in places
        // where AI'd mobs cannot writhe around, e.g. when caught in a net
        //
        //assert(!self.hasStatus(.Pain));

        self.declareAction(.Rest);
    }

    // XXX: increase max stackbuffer size if adding bigger mobs
    pub fn coordListMT(self: *Mob) StackBuffer(Coord, 16) {
        var list = StackBuffer(Coord, 16).init(null);
        var gen = Generator(Rect.rectIter).init(self.areaRect());
        while (gen.next()) |mobcoord|
            list.append(mobcoord) catch err.wat();
        return list;
    }

    // closestMultitileCoord
    pub fn coordMT(self: *Mob, to: Coord) Coord {
        var closest = self.coord;
        {
            var gen = Generator(Rect.rectIter).init(self.areaRect());
            while (gen.next()) |mobcoord|
                if (mobcoord.distance(to) < closest.distanceManhattan(to)) {
                    closest = mobcoord;
                };
        }
        return closest;
    }

    pub fn distance(a: *Mob, b: *Mob) usize {
        const ac = a.coordMT(b.coord);
        const bc = b.coordMT(ac);
        return ac.distance(bc);
    }

    pub fn listOfWeapons(self: *Mob) StackBuffer(*const Weapon, 7) {
        var buf = StackBuffer(*const Weapon, 7).init(null);

        buf.append(if (self.inventory.equipment(.Weapon).*) |w| w.Weapon else self.species.default_attack) catch err.wat();

        for (self.species.aux_attacks) |w|
            buf.append(w) catch err.wat();

        return buf;
    }

    pub fn canMelee(attacker: *Mob, defender: *Mob) bool {
        if (attacker.coordMT(defender.coord).closestDirectionTo(defender.coord, state.mapgeometry).is_diagonal() and
            attacker.hasStatus(.Disorient))
        {
            return false;
        }

        const weapons = attacker.listOfWeapons();
        const dist = attacker.distance(defender);

        return for (weapons.constSlice()) |weapon| {
            if (weapon.reach >= dist and utils.hasClearLOF(attacker.coordMT(defender.coord), defender.coordMT(attacker.coord)))
                break true;
        } else false;
    }

    pub fn totalMeleeOutput(self: *Mob, defender: *Mob) usize {
        const weapons = self.listOfWeapons();
        var total: usize = 0;
        for (weapons.constSlice()) |weapon| {
            const weapon_damage = combat.damageOfWeapon(self, weapon, defender);
            total += combat.damageOfMeleeAttack(self, weapon_damage.total, false);
        }
        return total;
    }

    pub fn hasWeaponOfEgo(self: *Mob, ego: Weapon.Ego) bool {
        const weapons = self.listOfWeapons();
        return for (weapons.constSlice()) |weapon| {
            if (weapon.ego == ego) {
                break true;
            }
        } else false;
    }

    pub const FightOptions = struct {
        free_attack: bool = false,
        auto_hit: bool = false,
        disallow_stab: bool = false,
        damage_bonus: usize = 100, // percentage
        loudness: SoundIntensity = .Medium,

        is_bonus: bool = false,
        is_riposte: bool = false,
    };

    pub fn fight(attacker: *Mob, recipient: *Mob, opts: FightOptions) void {
        assert(!recipient.is_dead);

        const martial = @intCast(usize, math.max(0, attacker.stat(.Martial)));
        const weapons = attacker.listOfWeapons();

        for (weapons.constSlice()) |weapon| {
            // recipient could be out of reach, either because the attacker has
            // multiple attacks and only one of them reaches, or because the
            // previous attack knocked the defender backwards
            if (weapon.reach < attacker.distance(recipient))
                continue;

            _fightWithWeapon(attacker, recipient, weapon, opts, if (weapon.martial) martial else 0);
        }

        if (!opts.free_attack) {
            const d = attacker.coordMT(recipient.coord).closestDirectionTo(recipient.coord, state.mapgeometry);
            attacker.declareAction(.{ .Attack = .{ .who = recipient, .coord = recipient.coord, .direction = d } });
        }

        // If the defender didn't know about the attacker's existence now's a
        // good time to find out
        //
        // (Do this after actually attacking to avoid blinking the '!'
        // animation, then immediately the '∞' animation for stabs.)
        ai.updateEnemyKnowledge(recipient, attacker, null);
    }

    fn _fightWithWeapon(
        attacker: *Mob,
        recipient: *Mob,
        attacker_weapon: *const Weapon,
        opts: FightOptions,
        remaining_bonus_attacks: usize,
    ) void {
        assert(!attacker.is_dead);
        assert(!recipient.is_dead);

        // const chance_of_land = combat.chanceOfMeleeLanding(attacker, recipient);
        // const chance_of_dodge = combat.chanceOfAttackEvaded(recipient, attacker);
        // if (attacker.coord.eq(state.player.coord)) {
        //     state.message(.Info, "you attack: chance of land: {}, chance of dodge: {}", .{ chance_of_land, chance_of_dodge });
        // } else if (recipient.coord.eq(state.player.coord)) {
        //     state.message(.Info, "you defend: chance of land: {}, chance of dodge: {}", .{ chance_of_land, chance_of_dodge });
        // }

        const missed = !rng.percent(combat.chanceOfMeleeLanding(attacker, recipient));
        const evaded = rng.percent(combat.chanceOfAttackEvaded(recipient, attacker));
        const acoord = attacker.coordMT(recipient.coord);
        const rcoord = recipient.coordMT(acoord);

        const hit = opts.auto_hit or (!missed and !evaded);

        if (!hit) {
            if (state.player.canSeeMob(attacker) or state.player.canSeeMob(recipient)) {
                if (missed) {
                    const verb = if (attacker == state.player) "miss" else "misses";
                    state.message(.CombatUnimportant, "{c} {s} {}.", .{
                        attacker, verb, recipient,
                    });
                    ui.Animation.blinkMob(&.{recipient}, '/', colors.LIGHT_STEEL_BLUE, .{});
                } else if (evaded) {
                    const verb = if (recipient == state.player) "evade" else "evades";
                    state.message(.CombatUnimportant, "{c} {s} {}.", .{
                        recipient, verb, attacker,
                    });
                    ui.Animation.blinkMob(&.{recipient}, ')', colors.LIGHT_STEEL_BLUE, .{});
                }
            }

            if (recipient.isUnderStatus(.Riposte)) |_| {
                if (recipient.canMelee(attacker)) {
                    ui.Animation.blinkMob(&.{recipient}, 'R', colors.LIGHT_STEEL_BLUE, .{});
                    recipient.fight(attacker, .{ .free_attack = true, .is_riposte = true });
                }
            }

            if (recipient.isUnderStatus(.EtherealShield)) |_| {
                if (!recipient.isLit() and !attacker.isLit() and
                    spells.willSucceedAgainstMob(recipient, attacker))
                {
                    const d = acoord.closestDirectionTo(rcoord, state.mapgeometry).opposite();
                    const w = @intCast(usize, recipient.stat(.Willpower));
                    combat.throwMob(recipient, attacker, d, w);
                }
            }

            return;
        }

        const is_stab = !opts.disallow_stab and combat.isAttackStab(attacker, recipient) and !opts.is_bonus;
        const weapon_damage = combat.damageOfWeapon(attacker, attacker_weapon, recipient);
        const damage = combat.damageOfMeleeAttack(attacker, weapon_damage.total, is_stab) * opts.damage_bonus / 100;

        recipient.takeDamage(.{
            .amount = damage,
            .kind = attacker_weapon.damage_kind,
            .source = if (is_stab) .Stab else .MeleeAttack,
            .by_mob = attacker,
        }, .{
            .strs = attacker_weapon.strs,
            .is_bonus = opts.is_bonus,
            .is_riposte = opts.is_riposte,
        });

        // XXX: should this be .Loud instead of .Medium?
        attacker.makeNoise(.Combat, if (is_stab) .Quiet else opts.loudness);

        // Weapon effects.
        for (attacker_weapon.effects) |effect| {
            recipient.applyStatus(effect, .{});
        }

        // Weapon ego effects.
        switch (attacker_weapon.ego) {
            .Swap => {
                if ((attacker != state.player or player.getActiveRing() == null) and
                    attacker.canSwapWith(recipient, .{ .ignore_hostility = true }))
                {
                    _ = attacker.teleportTo(recipient.coord, null, true, true);
                }
            },
            .NC_Insane => {
                if (!recipient.isLit() and !attacker.isLit() and
                    spells.willSucceedAgainstMob(attacker, recipient))
                {
                    recipient.addStatus(.Insane, 0, .{ .Tmp = 20 });
                }
            },
            .NC_MassPara => {
                if (!attacker.isLit()) {
                    var iter = state.mobs.iterator();
                    while (iter.next()) |mob| {
                        if (mob.coord.z == attacker.coord.z and attacker.canSeeMob(mob) and
                            mob.distance(attacker) > 1 and mob.isHostileTo(attacker) and
                            spells.willSucceedAgainstMob(attacker, mob) and !mob.isLit())
                        {
                            const dist = mob.distance(attacker);
                            const dur = rng.range(usize, dist / 2, dist);
                            mob.addStatus(.Paralysis, 0, .{ .Tmp = dur });
                        }
                    }
                }
            },
            .NC_Duplicate => {
                if (!recipient.should_be_dead() and
                    recipient.faction != .Night and recipient.life_type != .Spectral and
                    !recipient.isLit() and !attacker.isLit() and
                    spells.willSucceedAgainstMob(attacker, recipient))
                {
                    const new = recipient.duplicateIntoSpectral();
                    if (new) |new_mob| {
                        new_mob.addStatus(.Lifespan, 0, .{ .Tmp = @intCast(usize, attacker.stat(.Willpower)) * 2 });
                    }
                }
            },
            else => {},
        }

        // Daze stabbed mobs.
        if (is_stab) {
            recipient.addStatus(.Daze, 0, .{ .Tmp = rng.range(usize, 3, 5) });
        }

        // Knockback
        if (attacker_weapon.knockback > 0) {
            const d = acoord.closestDirectionTo(rcoord, state.mapgeometry);
            combat.throwMob(attacker, recipient, d, attacker_weapon.knockback);
        }

        // Retaliation/spikes damage?
        if (recipient.stat(.Spikes) > 0 and
            attacker.coord.distance(recipient.coord) == 1)
        {
            ui.Animation.blinkMob(&.{recipient}, 'S', colors.LIGHT_STEEL_BLUE, .{});

            attacker.takeDamage(.{
                .amount = @intCast(usize, recipient.stat(.Spikes)),
                .source = .Passive,
                .by_mob = recipient,
            }, .{
                .strs = &[_]DamageStr{items._dmgstr(0, "spike", "spikes", "")},
                .is_spikes = true,
            });
        }

        // Bonus attacks?
        if (!is_stab and remaining_bonus_attacks > 0 and !recipient.should_be_dead()) {
            var newopts = opts;
            newopts.auto_hit = false;
            newopts.damage_bonus = 100;
            newopts.is_bonus = true;

            ui.Animation.blinkMob(&.{attacker}, 'M', colors.LIGHT_STEEL_BLUE, .{});

            _fightWithWeapon(attacker, recipient, attacker_weapon, newopts, remaining_bonus_attacks - 1);
        }
    }

    pub fn takeHealing(self: *Mob, h: usize) void {
        self.HP = math.clamp(self.HP + h, 0, self.max_HP);

        const verb: []const u8 = if (self == state.player) "are" else "is";
        const fully_adj: []const u8 = if (self.HP == self.max_HP) "fully " else "";
        const punc: []const u8 = if (self.HP == self.max_HP) "!" else ".";
        state.message(.Info, "{c} {s} {s}healed{s} $g($c{}$g HP)", .{ self, verb, fully_adj, punc, h });
    }

    pub fn takeDamage(self: *Mob, d: Damage, msg: struct {
        basic: bool = false,
        noun: ?[]const u8 = null,
        strs: []const DamageStr = &[_]DamageStr{
            items._dmgstr(0, "hit", "hits", ""),
        },
        is_bonus: bool = false,
        is_riposte: bool = false,
        is_spikes: bool = false,
    }) void {
        const was_already_dead = self.should_be_dead();
        const old_HP = self.HP;

        const resist = if (d.kind.resist()) |r| self.resistance(r) else 0;
        const unshaved_amount = combat.shaveDamage(d.amount, resist); // TODO: change this variable name to "lethal_amount"
        const amount = if (!d.lethal and unshaved_amount >= self.HP) self.HP - 1 else unshaved_amount;
        const dmg_percent = amount * 100 / math.max(1, self.HP);

        self.HP -|= amount;

        // Inform defender of attacker
        //
        // We already do this in fight() for missed attacks, but this takes
        // care of ranged combat, spell damage, etc.
        if (d.by_mob) |attacker| {
            if (attacker.isHostileTo(self) and self.hasStatus(.Amnesia)) {
                self.cancelStatus(.Amnesia);
            }
            ai.updateEnemyKnowledge(self, attacker, null);
        }

        // Record stats
        if (d.by_mob != null and d.by_mob == state.player) {
            scores.recordTaggedUsize(.DamageInflicted, .{ .M = self }, 1);
        } else if (self == state.player) {
            if (d.by_mob) |attacker| {
                scores.recordTaggedUsize(.DamageEndured, .{ .M = attacker }, 1);
            } else {
                scores.recordTaggedUsize(.DamageEndured, .{ .s = "???" }, 1);
            }
        }

        // Make animations
        const clamped_dmg = math.clamp(@intCast(u21, amount), 0, 9);
        const damage_char = if (self.should_be_dead()) '∞' else '0' + clamped_dmg;
        ui.Animation.blinkMob(&.{self}, damage_char, colors.PALE_VIOLET_RED, .{});

        // Print message
        if (state.player.cansee(self.coord) or (d.by_mob != null and state.player.cansee(d.by_mob.?.coord))) {
            var punctuation: []const u8 = ".";
            if (dmg_percent >= 20) punctuation = "!";
            if (dmg_percent >= 40) punctuation = "!!";
            if (dmg_percent >= 60) punctuation = "!!!";
            if (dmg_percent >= 80) punctuation = "!!!!";

            var hitstrs = msg.strs[msg.strs.len - 1];
            {
                for (msg.strs) |strset| {
                    if (strset.dmg_percent > dmg_percent) {
                        hitstrs = strset;
                        break;
                    }
                }
            }

            const resisted = @intCast(isize, d.amount) - @intCast(isize, amount);
            const resist_str = if (d.kind == .Physical) "armor" else "resist";

            if (msg.basic) {
                const basic_helper_verb: []const u8 = if (self == state.player) "are" else "is";
                const basic_verb = switch (d.kind) {
                    .Irresistible, .Physical => "damaged",
                    .Fire => "burnt with fire",
                    .Electric => "electrocuted",
                };

                state.message(
                    .Combat,
                    "{c} {s} {s}{s} $g($r{}$. $g{s}$g, $c{}$. $g{s}$.)",
                    .{
                        self,        basic_helper_verb, basic_verb,
                        punctuation, amount,            d.kind.string(),
                        resisted,    resist_str,
                    },
                );
            } else {
                const martial_str = if (msg.is_bonus) " $b*Martial*$. " else "";
                const riposte_str = if (msg.is_riposte) " $b*Riposte*$. " else "";
                const spikes_str = if (msg.is_spikes) " $b*Spikes*$. " else "";

                var noun = StackBuffer(u8, 64).init(null);
                if (msg.noun) |m_noun| {
                    noun.fmt("{s}", .{m_noun});
                } else {
                    noun.fmt("{c}", .{d.by_mob.?});
                }

                const verb = if (d.by_mob != null and d.by_mob.? == state.player)
                    hitstrs.verb_self
                else
                    hitstrs.verb_other;

                state.message(
                    .Combat,
                    "{s} {s} {}{s}{s} $g($r{}$. $g{s}$g, $c{}$. $g{s}$.) {s}{s}{s}",
                    .{
                        noun.constSlice(),   verb,        self,
                        hitstrs.verb_degree, punctuation, amount,
                        d.kind.string(),     resisted,    resist_str,
                        martial_str,         riposte_str, spikes_str,
                    },
                );
            }
        }

        if (d.blood) {
            if (d.amount > 0) {
                if (self.blood) |s|
                    state.dungeon.spatter(self.coord, s);
                if (self.blood_spray) |g|
                    state.dungeon.atGas(self.coord)[g] += 0.2;
            }
        }

        self.last_damage = d;

        // Propagate electric damage
        if (d.kind == .Electric and d.propagate_elec_damage) {
            const S = struct {
                pub fn isConductive(c: Coord, _: state.IsWalkableOptions) bool {
                    if (state.dungeon.at(c).mob) |m|
                        if (m.hasStatus(.Conductive) and !m.isFullyResistant(.rElec))
                            return true;
                    return false;
                }
            };

            var membuf: [4096]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

            var dijk = dijkstra.Dijkstra.init(self.coord, state.mapgeometry, 9, S.isConductive, .{}, fba.allocator());
            defer dijk.deinit();

            var list = StackBuffer(*Mob, 64).init(null);

            while (dijk.next()) |child| {
                const mob = state.dungeon.at(child).mob.?;
                if (mob != self and list.len < list.capacity)
                    list.append(mob) catch unreachable;
            }

            ui.Animation.blinkMob(list.constSlice(), '*', ui.Animation.ELEC_LINE_FG, .{});

            for (list.constSlice()) |mob| {
                mob.takeDamage(.{
                    .amount = d.amount,
                    .by_mob = d.by_mob,
                    .source = d.source,
                    .kind = .Electric,
                    .indirect = d.indirect,
                    .propagate_elec_damage = false,
                }, msg);
            }
        }

        // Player kill-count bookkeeping.
        if (!was_already_dead and self.HP == 0 and d.by_mob != null) {
            self.killed_by = d.by_mob.?;
            if (d.by_mob == state.player) {
                scores.recordTaggedUsize(.KillRecord, .{ .M = self }, 1);
                if (d.source == .Stab)
                    scores.recordTaggedUsize(.StabRecord, .{ .M = self }, 1);
            }
        }

        // Should we give the mob its flee-effect?
        //
        // FIXME: this probably shouldn't be handled here.
        if (self.HP > 0 and
            self.isUnderStatus(.Exhausted) == null and
            (self.lastDamagePercentage() >= 50 or
            (self.HP <= (self.max_HP / 10) and old_HP > (self.max_HP / 10))))
        {
            if (self.ai.flee_effect) |s| {
                if (self.isUnderStatus(s.status) == null) {
                    self.applyStatus(s, .{});
                }
            }
        }
    }

    pub fn init(self: *Mob, alloc: mem.Allocator) void {
        self.is_dead = false;
        self.HP = self.max_HP;
        self.MP = self.max_MP;
        self.enemies = EnemyRecord.AList.init(alloc);
        self.allies = MobArrayList.init(alloc);
        self.sustiles = std.ArrayList(SuspiciousTileRecord).init(alloc);
        self.jobs = @TypeOf(self.jobs).init(null);
        self.activities.init();
        self.path_cache = std.AutoHashMap(Path, Coord).init(alloc);
        self.ai.work_area = CoordArrayList.init(alloc);

        self.squad = null;
        self.linked_fovs.clear();
        self.push_flag = false;
        self.energy = 0;
        self.statuses = StatusArray.initFill(.{});
        self.activities = .{};
        self.last_attempted_move = null;
        self.last_damage = null;
        self.corruption_ctr = 0;
        self.inventory = .{};
    }

    // Returns null if there wasn't any nearby walkable spot to put the new
    // spectral creature
    pub fn duplicateIntoSpectral(self: *Mob) ?*Mob {
        var dijk = dijkstra.Dijkstra.init(self.coord, state.mapgeometry, 5, state.is_walkable, .{}, state.GPA.allocator());
        defer dijk.deinit();

        const newcoord = while (dijk.next()) |child| {
            if (state.dungeon.at(child).mob == null) break child;
        } else return null;

        var new = self.*;
        new.init(state.GPA.allocator());
        new.coord = newcoord;
        new.prefix = "spectral ";

        // Can't have "spectral [this is a bug]" enemies being created when a
        // night reaper attacks the player.
        if (self == state.player)
            new.ai.profession_name = "clone";

        new.faction = .Night;
        new.prisoner_status = null;
        new.life_type = .Spectral;
        new.blood = null;
        new.corpse = .None;

        new.ai.work_fn = ai.dummyWork;
        new.ai.is_curious = false;
        new.ai.flee_effect = null;
        new.ai.is_combative = true;

        new.innate_resists.rFire = math.clamp(self.innate_resists.rFire - 25, -100, 100);
        new.innate_resists.rElec = math.clamp(self.innate_resists.rElec + 25, -100, 100);
        new.innate_resists.rFume = 100;

        state.mobs.append(new) catch err.wat();
        const new_ptr = state.mobs.last().?;
        state.dungeon.at(newcoord).mob = new_ptr;
        return new_ptr;
    }

    // Returns false if there wasn't any nearby walkable spot to put the new
    // zombie
    pub fn raiseAsUndead(self: *Mob, corpse_coord: Coord) bool {
        var newcoord: ?Coord = corpse_coord;
        if (state.dungeon.at(corpse_coord).mob != null) {
            var membuf: [4096]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

            var dijk = dijkstra.Dijkstra.init(self.coord, state.mapgeometry, 10, state.is_walkable, .{ .right_now = true }, fba.allocator());
            defer dijk.deinit();

            newcoord = while (dijk.next()) |child| {
                if (state.dungeon.at(child).mob == null) break child;
            } else null;
        }

        if (newcoord) |coord| {
            state.dungeon.at(corpse_coord).surface = null;
            state.dungeon.at(coord).mob = self;
            self.coord = coord;
        } else {
            return false;
        }

        self.is_dead = false;
        self.init(state.GPA.allocator());

        self.tile = 'z';
        self.prefix = "former ";
        self.life_type = .Undead;

        self.energy = 0;

        self.ai = .{
            .profession_name = self.ai.profession_name,
            .profession_description = "watching",
            .work_area = self.ai.work_area,
            .work_fn = ai.dummyWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = false,
            .flee_effect = null,
        };

        // Erase/reset all statuses
        var statuses = self.statuses.iterator();
        while (statuses.next()) |entry|
            self.cancelStatus(entry.key);

        self.blood = null;
        self.corpse = .None;

        // FIXME: don't assume this (the player might be raising a corpse too!)
        self.faction = .Necromancer;

        self.stats.Evade -= 10;
        self.stats.Melee -= 10;
        self.stats.Willpower -= 2;
        self.stats.Vision = 5;

        self.memory_duration = 7;
        self.deaf = true;

        self.innate_resists.rFire = math.clamp(self.innate_resists.rFire + 25, -100, 100);
        self.innate_resists.rElec = math.clamp(self.innate_resists.rElec + 25, -100, 100);
        self.innate_resists.rFume = 100;

        return true;
    }

    pub fn kill(self: *Mob) void {
        if (self != state.player) {
            if (self.killed_by) |by_mob| {
                if (by_mob == state.player) {
                    state.message(.Damage, "You slew {c}.", .{self});
                } else if (state.player.cansee(by_mob.coord)) {
                    state.message(.Damage, "{c} killed the {c}.", .{ by_mob, self });
                }
            } else {
                if (state.player.cansee(self.coord)) {
                    state.message(.Damage, "{c} dies.", .{self});
                }
            }
        }

        self.deinit();

        if (self.isUnderStatus(.Explosive)) |s| {
            explosions.kaboom(self.coord, .{ .strength = s.power });
        }

        if (self.isUnderStatus(.ExplosiveElec)) |s| {
            explosions.elecBurst(self.coord, s.power, self);
        }

        if (state.player.canSeeMob(self) and player.hasSabresInSight() and
            self.isHostileTo(state.player) and self.life_type == .Undead and
            player.hasAugment(.UndeadBloodthirst))
        {
            spells.spawnSabreVolley(state.player, self.coord);
        }

        // Apply death effect
        switch (self.slain_trigger) {
            .None => {},
            .Disintegrate => |list| {
                const coords = self.coordListMT();
                assert(list.len <= coords.len);

                // FIXME: this loop exits as soon as there are no more coords to place
                // mobs on. In future it should continue looking at adjacent coords via
                // Dijkstra search.
                //
                var list_i: usize = 0;
                for (coords.constSlice()) |coord| {
                    if (list_i >= list.len) break;
                    if (!state.is_walkable(coord, .{})) continue;
                    _ = mobs.placeMob(state.GPA.allocator(), list[list_i], coord, .{});
                    list_i += 1;
                }

                // FIXME: make template specify message, currently this only works
                // for hulkers
                state.message(.Combat, "{c} contorts and breaks up.", .{self});
            },
        }
    }

    pub fn deinitNoCorpse(self: *Mob) void {
        assert(!self.is_dead);

        self.enemies.deinit();
        self.allies.deinit();
        self.sustiles.deinit();
        self.path_cache.clearAndFree();
        self.ai.work_area.deinit();

        for (self.jobs.slice()) |*job|
            job.deinit();

        self.is_dead = true;

        var gen = Generator(Rect.rectIter).init(self.areaRect());
        while (gen.next()) |mobcoord|
            state.dungeon.at(mobcoord).mob = null;
    }

    // Separate from kill() because some code (e.g., mapgen) cannot rely on the player
    // having been initialized (to print the messages).
    pub fn deinit(self: *Mob) void {
        const S = struct {
            pub fn _isNotWall(c: Coord, _: state.IsWalkableOptions) bool {
                return state.dungeon.at(c).type != .Wall and
                    state.dungeon.at(c).surface == null;
            }
        };

        self.deinitNoCorpse();

        if (self.corpse != .None) {
            assert(self.multitile == null);

            // Generate a corpse if possible.
            var membuf: [4096]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

            var dijk = dijkstra.Dijkstra.init(self.coord, state.mapgeometry, 2, S._isNotWall, .{}, fba.allocator());
            defer dijk.deinit();

            const corpsetile: ?Coord = while (dijk.next()) |child| {
                if (state.dungeon.at(child).surface == null) break child;
            } else null;

            if (corpsetile) |c| {
                switch (self.corpse) {
                    .None => err.wat(),
                    .Normal => {
                        state.dungeon.at(c).surface = .{ .Corpse = self };
                        self.coord = c;
                    },
                    .Wall => state.dungeon.at(c).type = .Wall,
                    .Dust => if (utils.findById(surfaces.props.items, "undead_ash")) |prop| {
                        _ = mapgen.placeProp(c, &surfaces.props.items[prop]);
                    } else unreachable,
                }
            }
        }
    }

    pub fn should_be_dead(self: *const Mob) bool {
        return self.HP == 0;
    }

    pub fn nextDirectionTo(self: *Mob, to: Coord) ?Direction {
        if (self.immobile) return null;

        // FIXME: make this an assertion; no mob should ever be trying to path to
        // themself.
        if (self.coord.eq(to)) return null;

        const is_disoriented = self.isUnderStatus(.Disorient) != null;

        // Cannot move if you're a prisoner (unless you're moving one space away)
        if (self.prisoner_status) |p|
            if (p.held_by != null and p.heldAt().distance(to) > 1)
                return null;

        if (!is_disoriented) {
            if (Direction.from(self.coord, to)) |direction| {
                return direction;
            }
        }

        const pathobj = Path{ .from = self.coord, .to = to, .confused_state = is_disoriented };

        if (!self.path_cache.contains(pathobj)) {
            const directions = b: {
                if (is_disoriented) {
                    break :b &CARDINAL_DIRECTIONS;
                } else {
                    if (self.ai.flag(.MovesDiagonally)) {
                        break :b &DIAGONAL_DIRECTIONS;
                    } else {
                        break :b &DIRECTIONS;
                    }
                }
            };

            const pth = astar.path(self.coord, to, state.mapgeometry, state.is_walkable, .{ .mob = self }, astar.basePenaltyFunc, directions, state.GPA.allocator()) orelse return null;
            defer pth.deinit();

            assert(pth.items[0].eq(self.coord));

            var last: Coord = self.coord;
            for (pth.items[1..]) |coord| {
                self.path_cache.put(
                    Path{ .from = last, .to = to, .confused_state = is_disoriented },
                    coord,
                ) catch err.wat();
                last = coord;
            }
            if (self.multitile == null)
                assert(last.eq(to));
        }

        // Return the next direction, ensuring that the next tile is walkable.
        // If it is not, set the path to null, ensuring that the path will be
        // recalculated next time.
        if (self.path_cache.get(pathobj)) |next| {
            const direction = Direction.from(self.coord, next).?;
            if (!next.eq(to) and !state.is_walkable(next, .{ .mob = self })) {
                _ = self.path_cache.remove(pathobj);
                return null;
            } else {
                return direction;
            }
        } else {
            return null;
        }
    }

    pub fn addStatus(self: *Mob, status: Status, power: usize, duration: StatusDataInfo.Duration) void {
        self.applyStatus(.{ .status = status, .duration = duration, .power = power }, .{});
    }

    pub fn cancelStatus(self: *Mob, s: Status) void {
        if (self.isUnderStatus(s)) |_| {
            const status_state = self.statuses.getPtr(s);
            status_state.duration = .{ .Tmp = 0 };
        }
    }

    pub fn applyStatus(
        self: *Mob,
        s: StatusDataInfo,
        opts: struct {
            add_power: bool = false,
            // Add .Tmp durations together, instead of replacing it.
            add_duration: bool = true,
            // Force the duration to be set to the new one.
            replace_duration: bool = false,
        },
    ) void {
        if (self.should_be_dead()) {
            return;
        }

        if (s.status.isMobImmune(self)) {
            self.cancelStatus(s.status);
            return;
        }

        const had_status_before = self.isUnderStatus(s.status) != null;

        const p_se = self.statuses.getPtr(s.status);
        const was_exhausting = p_se.exhausting;
        p_se.status = s.status;

        p_se.power = if (opts.add_power) p_se.power + s.power else s.power;

        // Only change the duration if the new one is a "higher" duration, or
        // we didn't have the status previously.
        //
        // i.e., if the old status was .Prm we won't change it if the newer status
        // is .Tmp. Or if the old status was .Tmp, we won't change it if the
        // newer one is .Ctx.
        //
        const new_dur_type = meta.activeTag(s.duration);
        const replace_anyway = opts.replace_duration or !had_status_before;
        switch (p_se.duration) {
            .Prm => if (replace_anyway or new_dur_type == .Prm) {
                p_se.duration = s.duration;
            },
            .Equ => if (replace_anyway or new_dur_type == .Prm or new_dur_type == .Equ) {
                p_se.duration = s.duration;
            },
            .Tmp => |dur| {
                if (replace_anyway or new_dur_type == .Prm or new_dur_type == .Tmp) {
                    if (opts.add_duration and new_dur_type == .Tmp) {
                        var newdur = dur + s.duration.Tmp;
                        newdur = math.clamp(newdur, 0, Status.MAX_DURATION);

                        p_se.duration = .{ .Tmp = newdur };
                    } else if (replace_anyway or
                        (new_dur_type == .Tmp and s.duration.Tmp >= p_se.duration.Tmp))
                    {
                        p_se.duration = s.duration;
                    }
                }
            },
            .Ctx => p_se.duration = s.duration,
        }

        p_se.exhausting = s.exhausting;

        const has_status_now = self.isUnderStatus(s.status) != null;

        var got: ?bool = null;
        var ministring = s.status.miniString();
        var string = s.status.string(self);

        if (had_status_before and !has_status_now) {
            got = false;

            if (was_exhausting or s.exhausting)
                self.addStatus(.Exhausted, 0, .{ .Tmp = Status.MAX_DURATION });

            switch (p_se.status) {
                .Lifespan => self.HP = 0,
                .RingExcision => {
                    assert(self == state.player);
                    state.player.squad.?.trimMembers();
                    for (state.player.squad.?.members.constSlice()) |member|
                        if (mem.eql(u8, member.id, "spec_sword"))
                            member.deinit();
                },
                else => {},
            }
        } else if (!had_status_before and has_status_now) {
            got = true;

            if (s.status == .Paralysis and self == state.player) {
                ui.drawContinuePrompt("You are paralysed!", .{});
            }
        }

        if (p_se.duration == .Tmp and got != null and
            (self == state.player or state.player.cansee(self.coord)))
        {
            const verb = if (got.?) @as([]const u8, "gained") else "lost";
            state.message(.Info, "{c} {s} $a{s}$..", .{ self, verb, string });
            if (ministring) |str| {
                const pref = if (got.?) "+" else "-";
                ui.labels.addForf(self, "{s}{s}", .{ pref, str }, .{ .color = colors.AQUAMARINE });
            }
        }
    }

    pub fn hasStatus(self: *const Mob, status: Status) bool {
        return self.isUnderStatus(status) != null;
    }

    pub fn isUnderStatus(self: *const Mob, status: Status) ?*const StatusDataInfo {
        const se = self.statuses.getPtrConst(status);
        const has_status = switch (se.duration) {
            .Prm, .Equ => true,
            .Tmp => |turns| turns > 0,
            .Ctx => se.duration.Ctx == state.dungeon.terrainAt(self.coord),
        };
        return if (has_status) se else null;
    }

    pub fn lastDamagePercentage(self: *const Mob) usize {
        return if (self.last_damage) |dam| (dam.amount * 100) / self.max_HP else 0;
    }

    pub fn canHear(self: *const Mob, coord: Coord) ?*Sound {
        if (self.deaf) return null;

        const noise = state.dungeon.soundAt(coord);

        if (self.coord.z != coord.z)
            return null; // Can't hear across levels

        if (noise.state == .Dead or noise.intensity == .Silent)
            return null; // Sound was made a while back, or is silent

        var radius = noise.intensity.radiusHeard();

        // Make the player hear farther than monsters
        if (self == state.player) radius = radius * 150 / 100;

        if (self.coord.distance(coord) > radius)
            return null; // Too far away

        return noise;
    }

    // ~~FIXME: need a isAlliedWith() function, since even if alliegiances match
    // mobs may be enemies (if one of them is insane)~~
    //
    // Hope I remember this when implementing insanity effects :P
    //
    // EDIT: I did!
    //
    pub fn isHostileTo(self: *const Mob, othermob: *const Mob) bool {
        if (self.hasStatus(.Insane) or othermob.hasStatus(.Insane)) return true;
        if (self.faction == othermob.faction) return false;

        var hostile = true;
        assert(self.faction != othermob.faction);

        // If the other mob is a prisoner of my faction (and is actually in
        // prison) or we're both prisoners of the same faction, don't be hostile.
        if (othermob.prisoner_status) |ps| {
            if (ps.of == self.faction and
                (state.dungeon.at(othermob.coord).prison or ps.held_by != null))
            {
                hostile = false;
            }

            if (self.prisoner_status) |my_ps| {
                if (my_ps.of == ps.of) {
                    hostile = false;
                }
            }
        }

        if (self.faction == .Night and
            state.night_rep[@enumToInt(othermob.faction)] > -5 and
            (state.night_rep[@enumToInt(othermob.faction)] > 0 or
            state.dungeon.terrainAt(othermob.coord) != &surfaces.SladeTerrain))
        {
            hostile = false;
        }

        return hostile;
    }

    pub fn isLit(self: *const Mob) bool {
        return state.dungeon.lightAt(self.coord).*;
    }

    pub fn canSeeMob(self: *const Mob, mob: *const Mob) bool {
        var gen = Generator(Rect.rectIter).init(mob.areaRect());
        return while (gen.next()) |mobcoord| {
            if (self.cansee(mobcoord)) break true;
        } else false;
    }

    pub fn cansee(self: *const Mob, coord: Coord) bool {
        if (self == state.player and player.wiz_lidless_eye)
            return true;

        // This was added previously as an "optimization", but it messes with
        // Detect Undead when the detected undead are outside normal field of
        // vision.
        //
        // Anyway, it wouldn't have saved much processing time considering how
        // fast the actual vision-check is...
        //
        //if (self.coord.distance(coord) > self.stat(.Vision))
        //    return false;

        // Can always see yourself
        if (self.coord.eq(coord))
            return true;

        if (self.fov[coord.y][coord.x] > 0)
            return true;

        return false;
    }

    // What's the monster doing right now?
    pub fn activity_description(self: *const Mob) []const u8 {
        var res = switch (self.ai.phase) {
            .Work => self.ai.profession_description,
            .Hunt => if (self.ai.is_combative) "hunting" else "alarmed",
            .Investigate => "investigating",
            .Flee => "fleeing",
        };

        if (self.is_dead) {
            res = "dead";
        }

        return res;
    }

    pub fn hasMoreEnergyThan(a: *const Mob, b: *const Mob) bool {
        return a.energy < b.energy;
    }

    pub fn canSeeInLight(self: *const Mob, light: bool) bool {
        if (!light) {
            if (self.isUnderStatus(.NightBlindness) != null) return false;
            if (self.base_night_vision) return true;
            return false;
        } else {
            if (self.isUnderStatus(.DayBlindness) != null) return false;
            return true;
        }
    }

    pub fn stat(self: *const Mob, _stat: Stat) isize {
        var val: isize = 0;

        // Add the mob's innate stat.
        const innate = utils.getFieldByEnum(Stat, self.stats, _stat);
        val += innate;

        // Check terrain.
        const terrain = state.dungeon.terrainAt(self.coord);
        val += utils.getFieldByEnum(Stat, terrain.stats, _stat);

        // Check statuses.
        switch (_stat) {
            .Speed => {
                if (self.isUnderStatus(.Fast)) |_| val = @divTrunc(val * 50, 100);
                if (self.isUnderStatus(.Slow)) |_| val = @divTrunc(val * 150, 100);
            },
            else => {},
        }

        // Check equipment.
        if (self.inventory.equipmentConst(.Weapon).*) |weapon|
            val += utils.getFieldByEnum(Stat, weapon.Weapon.stats, _stat);
        if (self.inventory.equipmentConst(.Cloak).*) |clk|
            val += utils.getFieldByEnum(Stat, clk.Cloak.stats, _stat);
        if (self.inventory.equipmentConst(.Armor).*) |arm| {
            if (arm.Armor.night and !self.isLit()) {
                val += utils.getFieldByEnum(Stat, arm.Armor.night_stats, _stat);
            } else {
                val += utils.getFieldByEnum(Stat, arm.Armor.stats, _stat);
            }
        }
        if (self.inventory.equipmentConst(.Aux).*) |aux| {
            if (aux.Aux.night and !self.isLit()) {
                val += utils.getFieldByEnum(Stat, aux.Aux.night_stats, _stat);
            } else {
                val += utils.getFieldByEnum(Stat, aux.Aux.stats, _stat);
            }
        }

        // Check rings.
        for (Inventory.RING_SLOTS) |ring_slot|
            if (self.inventory.equipmentConst(ring_slot).*) |ring| {
                val += utils.getFieldByEnum(Stat, ring.Ring.stats, _stat);
            };

        // Clamp value.
        val = switch (_stat) {
            .Sneak => math.clamp(val, 0, 10),
            // Should never be below 0
            .Vision, .Spikes => math.max(0, val),
            else => val,
        };

        return val;
    }

    pub fn isVulnerable(self: *const Mob, resist: Resistance) bool {
        return self.resistance(resist) < 0;
    }

    pub fn isFullyResistant(self: *const Mob, resist: Resistance) bool {
        return self.resistance(resist) >= 100;
    }

    // Returns different things depending on what resist is.
    //
    // For all resists except rFume, returns damage mitigated.
    // For rFume, returns chance for gas to trigger.
    pub fn resistance(self: *const Mob, resist: Resistance) isize {
        var r: isize = 0;

        // Add the mob's innate resistance.
        const innate = utils.getFieldByEnum(Resistance, self.innate_resists, resist);
        // Special case for immunity
        if (resist != .rFume and innate == 1000) {
            return 100;
        }
        assert(innate <= 100 and innate >= -100);
        r += innate;

        // Check terrain.
        const terrain = state.dungeon.terrainAt(self.coord);
        r += utils.getFieldByEnum(Resistance, terrain.resists, resist);

        // Check armor and cloaks
        if (self.inventory.equipmentConst(.Cloak).*) |clk|
            r += utils.getFieldByEnum(Resistance, clk.Cloak.resists, resist);
        if (self.inventory.equipmentConst(.Armor).*) |arm| {
            if (arm.Armor.night and !self.isLit()) {
                r += utils.getFieldByEnum(Resistance, arm.Armor.night_resists, resist);
            } else {
                r += utils.getFieldByEnum(Resistance, arm.Armor.resists, resist);
            }
        }
        if (self.inventory.equipmentConst(.Aux).*) |aux| {
            if (aux.Aux.night and !self.isLit()) {
                r += utils.getFieldByEnum(Resistance, aux.Aux.night_resists, resist);
            } else {
                r += utils.getFieldByEnum(Resistance, aux.Aux.resists, resist);
            }
        }

        // Check statuses
        switch (resist) {
            .Armor => if (self.isUnderStatus(.Recuperate) != null) {
                r -= 50;
            },
            .rFire => {
                if (self.isUnderStatus(.Flammable) != null) {
                    r -= 25;
                }

                if (self.isUnderStatus(.Fireproof) != null) {
                    r += 25;
                }
            },
            else => {},
        }

        r = math.clamp(r, -100, 100);

        // For rFume, make the value a percentage
        return if (resist == .rFume) 100 - r else r;
    }

    // This is very very very ugly.
    //
    pub fn checkForPatternUsage(self: *Mob) void {
        var activities: [MAX_ACTIVITY_BUFFER_SZ]Activity = undefined;
        var activity_iter = self.activities.iterator();
        while (activity_iter.next()) |activity|
            activities[activity_iter.counter - 1] = activity;

        // Walking pattern
        if (!self.isCreeping()) self.makeNoise(.Movement, .Medium);

        self.forEachRing(struct {
            pub fn f(mself: *Mob, ring: *Ring) void {
                if (ring.activated) {
                    switch (ring.pattern_checker.advance(mself)) {
                        .Completed => |stt| {
                            ring.activated = false;
                            ring.effect(mself, stt);
                            assert(mself == state.player);
                            scores.recordTaggedUsize(.PatternsUsed, .{ .s = ring.name }, 1);
                        },
                        .Failed => {
                            ring.activated = false;
                            if (state.player.cansee(mself.coord)) {
                                state.message(.Info, "{c} failed to use $o{s}$.", .{ mself, ring.name });
                            }
                        },
                        .Continued => {},
                    }
                }
            }
        }.f);
    }

    pub fn forEachRing(self: *Mob, func: fn (*Mob, *Ring) void) void {
        if (self == state.player) {
            for (state.default_patterns) |*ring|
                (func)(self, ring);
        }

        for (&Inventory.RING_SLOTS) |r| if (self.inventory.equipment(r).*) |ring_item|
            (func)(self, ring_item.Ring);
    }

    pub fn isCreeping(self: *const Mob) bool {
        return self.turnsSpentMoving() <= @intCast(usize, self.stat(.Sneak));
    }

    // Find out how many turns spent in moving
    pub fn turnsSpentMoving(self: *const Mob) usize {
        var turns: usize = 0;
        var iter = self.activities.iterator();
        while (iter.next()) |ac| {
            if (ac != .Move) return turns else turns += 1;
        }
        return turns;
    }

    // XXX: returning &self.enemies might be a really terrible idea, since if
    // we somehow invalidate the current `self` pointer while we're appending
    // to self.enemies (say, we change self.mobs to an ArrayList and append to
    // it or something, triggering a realloc) then havoc can happen
    //
    pub fn enemyList(self: *Mob) *EnemyRecord.AList {
        assert(@TypeOf(state.mobs) == LinkedList(Mob));

        if (self.squad) |squad| {
            return &squad.enemies;
        } else {
            return &self.enemies;
        }
    }

    pub fn enemyListConst(self: *const Mob) *const EnemyRecord.AList {
        assert(@TypeOf(state.mobs) == LinkedList(Mob));

        if (self.squad) |squad| {
            return &squad.enemies;
        } else {
            return &self.enemies;
        }
    }

    pub fn isAloneOrLeader(self: *const Mob) bool {
        if (self.squad == null) return true;
        if (self.squad.?.leader == self) return true;
        return false;
    }
}; // }}}

pub const Machine = struct {
    // linked list stuff
    __next: ?*Machine = null,
    __prev: ?*Machine = null,

    id: []const u8 = "",
    name: []const u8,

    // Should we announce its existence to the player when found?
    announce: bool = false,

    powered_tile: u21,
    unpowered_tile: u21,
    powered_sprite: ?font.Sprite = null,
    unpowered_sprite: ?font.Sprite = null,

    powered_fg: ?u32 = null,
    unpowered_fg: ?u32 = null,
    powered_bg: ?u32 = null,
    unpowered_bg: ?u32 = null,
    bg: ?u32 = null,

    powered_sfg: ?u32 = null,
    unpowered_sfg: ?u32 = null,
    powered_sbg: ?u32 = null,
    unpowered_sbg: ?u32 = null,
    sbg: ?u32 = null,

    power_drain: usize = 100, // Power drained per turn

    restricted_to: ?Faction = null,
    powered_walkable: bool = true,
    unpowered_walkable: bool = true,

    powered_opacity: f64 = 0.0,
    unpowered_opacity: f64 = 0.0,

    powered_luminescence: usize = 0,
    unpowered_luminescence: usize = 0,
    dims: bool = false,

    porous: bool = false,
    flammability: usize = 0,
    detect_with_heat: bool = false,
    detect_with_elec: bool = false,

    // A* penalty if the machine is walkable
    pathfinding_penalty: usize = 0,

    coord: Coord = Coord.new(0, 0),
    on_power: fn (*Machine) void, // Called on each turn when the machine is powered
    power: usize = 0, // percentage (0..100)
    last_interaction: ?*Mob = null,

    disabled: bool = false,

    player_interact: ?MachInteract = null,

    // If the player tries to trigger the machine, should we prompt for a
    // confirmation?
    evoke_confirm: ?[]const u8 = null,

    // TODO: Remove
    props: [40]?*Prop = [_]?*Prop{null} ** 40,

    // Areas the machine might manipulate/change while powered
    //
    // E.g., a blast furnace will heat up the first area, and search
    // for fuel in the second area.
    areas: StackBuffer(Coord, 16) = StackBuffer(Coord, 16).init(null),

    // chance: each turn, effect has ten in $chance to trigger.
    pub const MalfunctionEffect = union(enum) {
        Electrocute: struct { chance: usize, radius: usize, damage: usize },
        Explode: struct { chance: usize, power: usize },
    };

    pub const MachInteract = struct {
        name: []const u8,
        success_msg: ?[]const u8,
        no_effect_msg: ?[]const u8,
        expended_msg: ?[]const u8 = null,
        needs_power: bool = true,
        used: usize = 0,
        max_use: usize, // 0 for infinite uses
        func: fn (*Machine, *Mob) bool,
    };

    pub fn canBeInteracted(self: *Machine, _: *Mob, interaction: *const MachInteract) bool {
        if (interaction.needs_power and !self.isPowered())
            return false;
        return interaction.max_use == 0 or interaction.used < interaction.max_use;
    }

    pub fn evoke(self: *Machine, mob: *Mob, interaction: *MachInteract) !void {
        if (!canBeInteracted(self, mob, interaction))
            return error.UsedMax;

        if ((interaction.func)(self, mob)) {
            interaction.used += 1;
        } else return error.NoEffect;
    }

    pub fn canBePoweredBy(self: *Machine, by: *const Mob) bool {
        if (self.restricted_to) |restriction|
            if ((restriction == .Night and state.night_rep[@enumToInt(by.faction)] > 0) or
                restriction == by.faction)
            {
                return true;
            } else return false;
        return true;
    }

    pub fn addPower(self: *Machine, by: *Mob) bool {
        if (!self.canBePoweredBy(by))
            return false;

        self.power = math.min(self.power + 100, 100);
        self.last_interaction = by;

        return true;
    }

    pub fn isPowered(self: *const Machine) bool {
        return self.power > 0;
    }

    pub fn tile(self: *const Machine) u21 {
        return if (self.isPowered()) self.powered_tile else self.unpowered_tile;
    }

    pub fn sprite(self: *const Machine) ?font.Sprite {
        return if (self.isPowered()) self.powered_sprite else self.unpowered_sprite;
    }

    pub fn isWalkable(self: *const Machine) bool {
        return if (self.isPowered()) self.powered_walkable else self.unpowered_walkable;
    }

    pub fn opacity(self: *const Machine) f64 {
        return if (self.isPowered()) self.powered_opacity else self.unpowered_opacity;
    }

    pub fn luminescence(self: *const Machine) usize {
        return if (self.isPowered())
            if (self.dims)
                self.powered_luminescence * self.power / 100
            else
                self.powered_luminescence
        else
            self.unpowered_luminescence;
    }

    // Utility funcs to aid machine definition creation

    pub fn createGasTrap(comptime gstr: []const u8, g: *const gas.Gas) Machine {
        return Machine{
            .name = gstr ++ " trap",
            .powered_tile = '^',
            .unpowered_tile = '^',
            .evoke_confirm = "Really trigger the " ++ gstr ++ " trap?",
            .on_power = struct {
                fn f(machine: *Machine) void {
                    if (machine.last_interaction) |mob| {
                        if (mob.faction == .Necromancer) return;

                        for (machine.props) |maybe_prop| if (maybe_prop) |vent| {
                            state.dungeon.atGas(vent.coord)[g.id] = 1.0;
                        };

                        state.message(.Trap, "{c} triggers a " ++ gstr ++ " trap!", .{mob});
                        state.message(.Trap, "Noxious fumes seep through nearby vents!", .{});

                        machine.disabled = true;
                        state.dungeon.at(machine.coord).surface = null;
                    }
                }
            }.f,
        };
    }
};

pub const Prop = struct {
    // linked list stuff
    __next: ?*Prop = null,
    __prev: ?*Prop = null,

    id: []const u8,
    name: []const u8,
    tile: u21,
    sprite: ?font.Sprite,
    fg: ?u32,
    bg: ?u32,
    walkable: bool,
    opacity: f64,
    holder: bool, // Can a prisoner be held to it?
    flammability: usize,
    coord: Coord = Coord.new(0, 0),

    pub fn deinit(self: *const Prop, alloc: mem.Allocator) void {
        alloc.free(self.id);
        alloc.free(self.name);
    }
};

pub const Container = struct {
    // linked list stuff
    __next: ?*Container = null,
    __prev: ?*Container = null,

    name: []const u8,
    tile: u21,
    capacity: usize,
    items: ItemBuffer = ItemBuffer.init(null),
    type: ContainerType,
    coord: Coord = undefined,
    item_repeat: usize = 10, // Chance of the first item appearing again

    pub const ItemBuffer = StackBuffer(Item, 21);
    pub const ContainerType = enum {
        Smackables, // Weapons
        Drinkables, // Potions, alcohol, etc
        Wearables, // Cloaks, armors, etc
        Evocables, // Consumables, evocables, aux items
        VOres, // Useless. Vial ores
        Utility, // Useless. Depends on the level (for PRI: rope, chains, etc).

        pub fn itemType(self: ContainerType) ?[]const items.ItemTemplate.Type {
            return switch (self) {
                .Smackables => &[_]items.ItemTemplate.Type{.W},
                .Drinkables => &[_]items.ItemTemplate.Type{.P},
                .Wearables => &[_]items.ItemTemplate.Type{ .A, .C },
                .Evocables => &[_]items.ItemTemplate.Type{ .c, .E, .X },
                else => null,
            };
        }
    };

    pub fn isFull(self: *const Container) bool {
        assert(self.capacity <= self.items.capacity);
        return self.items.len == self.capacity;
    }

    pub fn isLootable(self: *const Container) bool {
        return self.items.len > 0 and
            (self.type == .Smackables or
            self.type == .Drinkables or
            self.type == .Wearables or
            self.type == .Evocables);
    }
};

pub const SurfaceItemTag = enum { Corpse, Machine, Prop, Container, Poster, Stair };
pub const SurfaceItem = union(SurfaceItemTag) {
    Corpse: *Mob,
    Machine: *Machine,
    Prop: *Prop,
    Container: *Container,
    Poster: *const Poster,
    Stair: ?usize, // null = downstairs

    pub fn id(self: SurfaceItem) []const u8 {
        return switch (self) {
            .Corpse => |c| c.id,
            .Machine => |m| m.id,
            .Prop => |p| p.id,
            .Container => "AMBIG_container",
            .Poster => "AMBIG_poster",
            .Stair => "AMBIG_stair",
        };
    }
};

pub const DamageStr = struct {
    dmg_percent: usize,
    verb_self: []const u8,
    verb_other: []const u8,
    verb_degree: []const u8,
};

pub const Armor = struct {
    // linked list stuff
    __next: ?*Armor = null,
    __prev: ?*Armor = null,

    id: []const u8,
    name: []const u8,
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    night: bool = false,
    night_stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    night_resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},

    equip_effects: []const StatusDataInfo = &[_]StatusDataInfo{},
};

pub const Weapon = struct {
    // linked list stuff
    __next: ?*Weapon = null,
    __prev: ?*Weapon = null,

    id: []const u8 = "",
    name: []const u8 = "",

    reach: usize = 1,
    damage: usize,
    damage_kind: Damage.DamageKind = .Physical,
    knockback: usize = 0,
    martial: bool = false,
    ego: Ego = .None,

    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    effects: []const StatusDataInfo = &[_]StatusDataInfo{},
    equip_effects: []const StatusDataInfo = &[_]StatusDataInfo{},

    strs: []const DamageStr,

    pub const Ego = enum {
        None,
        NC_Insane,
        NC_MassPara,
        NC_Duplicate,
        Swap,

        pub fn name(self: Ego) ?[]const u8 {
            return switch (self) {
                .None => null,
                .NC_Insane => "insanity",
                .NC_MassPara => "mass paralysis",
                .NC_Duplicate => "duplicity",
                .Swap => "swapping",
            };
        }

        pub fn description(self: Ego) ?[]const u8 {
            return switch (self) {
                .None => null,
                .NC_Insane => "When both you and your foe are in an unlit area, you have a will-checked chance to send your foe insane with your attacks.",
                .NC_MassPara => "When you are attacking from an unlit area, you have a will-checked chance to paralyse nearby foes if they are also standing in the dark. The duration of the paralysis will always be less than the time needed to reach them.",
                .NC_Duplicate => "When both you and your foe are in an unlit area, you have a will-checked chance to create a spectral copy of your foe. The spectral copy will be aligned with the Night Creatures, and will last for $bwillpower * 2$. turns.",
                .Swap => "When you land a successful hit, you have a chance to swap places with your foe.",
            };
        }
    };
};

pub const Vial = enum {
    Tanus,
    Slade,
    Pholenine,
    Chloroforon,
    Hyine,
    Quagenine,
    Flouine,
    Cataline,
    Phytin,

    pub const VIALS = [_]Vial{
        .Tanus, .Slade, .Pholenine, .Chloroforon, .Hyine, .Quagenine, .Flouine, .Cataline, .Phytin,
    };

    // Commonicity (adj) -- the opposite of rarity, because why not. Higher numbers are more common.
    //
    // Is in same order as with VIAL_ORES and VIALS.
    pub const VIAL_COMMONICITY = [_]usize{ 5, 1, 2, 3, 7, 7, 2, 1, 5 };

    pub const OreAndVial = struct { m: ?*const Material, v: Vial };

    pub const VIAL_ORES = [_]OreAndVial{
        .{ .m = &materials.Talonium, .v = .Tanus },
        .{ .m = &materials.Sulon, .v = .Slade },
        .{ .m = &materials.Phosire, .v = .Pholenine },
        .{ .m = null, .v = .Chloroforon },
        .{ .m = &materials.Hyalt, .v = .Hyine },
        .{ .m = &materials.Quaese, .v = .Quagenine },
        .{ .m = null, .v = .Flouine },
        .{ .m = &materials.Catasine, .v = .Cataline },
        .{ .m = &materials.Phybro, .v = .Phytin },
    };

    pub inline fn color(self: Vial) u32 {
        return switch (self) {
            .Tanus => materials.Talonium.color_floor,
            .Slade => materials.Sulon.color_floor,
            .Pholenine => materials.Phosire.color_floor,
            .Chloroforon => 0xffe001,
            .Hyine => materials.Hyalt.color_floor,
            .Quagenine => materials.Quaese.color_floor,
            .Flouine => 0x33ccff,
            .Cataline => materials.Catasine.color_floor,
            .Phytin => materials.Phybro.color_floor,
        };
    }

    pub inline fn name(self: Vial) []const u8 {
        return switch (self) {
            .Tanus => "tanus",
            .Slade => "slade",
            .Pholenine => "pholenine",
            .Chloroforon => "chloroforon",
            .Hyine => "hyine",
            .Quagenine => "quagenine",
            .Flouine => "flouine",
            .Cataline => "cataline",
            .Phytin => "phytin",
        };
    }
};

pub const Ring = struct {
    // linked list stuff
    __next: ?*Ring = null,
    __prev: ?*Ring = null,

    // Ring of <name>
    name: []const u8,

    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    hated_by_nc: bool = false,
    pattern_checker: PatternChecker,
    effect: fn (*Mob, PatternChecker.State) void,

    activated: bool = false,
};

pub const ItemType = enum { Ring, Consumable, Vial, Projectile, Armor, Cloak, Aux, Weapon, Boulder, Prop, Evocable };

pub const Item = union(ItemType) {
    Ring: *Ring,
    Consumable: *const Consumable,
    Vial: Vial,
    Projectile: *const Projectile,
    Armor: *const Armor,
    Cloak: *const Cloak,
    Aux: *const Aux,
    Weapon: *const Weapon,
    Boulder: *const Material,
    Prop: *const Prop,
    Evocable: *Evocable,

    pub fn isUseful(self: Item) bool {
        return switch (self) {
            .Vial, .Boulder, .Prop => false,
            .Projectile, .Cloak, .Aux, .Ring, .Consumable, .Armor, .Weapon, .Evocable => true,
        };
    }

    // Should we announce the item to the player when we find it?
    pub fn announce(self: Item) bool {
        return self.isUseful();
    }

    pub fn tile(self: Item) display.Cell {
        var cell = display.Cell{ .fg = 0xffffff, .bg = colors.BG, .ch = ' ' };

        switch (self) {
            .Consumable => |cons| {
                cell.ch = if (cons.is_potion) '¡' else '&';
                cell.fg = cons.color;
            },
            .Vial => |v| {
                cell.ch = '♪';
                cell.fg = v.color();
            },
            .Projectile => |p| {
                cell.ch = '(';
                cell.fg = p.color;
            },
            .Ring => |_| {
                cell.ch = '*';
                cell.fg = colors.GOLD;
            },
            .Weapon => |_| {
                cell.ch = ')';
            },
            .Aux => |_| {
                cell.ch = ']';
            },
            .Cloak, .Armor => {
                cell.ch = '[';
            },
            .Boulder => |b| {
                cell.ch = b.chunkTile();
                cell.fg = b.color_floor;
            },
            .Prop => |p| {
                cell.ch = '%';
                cell.fg = p.fg orelse 0xcacbca;
            },
            .Evocable => |v| {
                cell.ch = '}';
                cell.fg = v.tile_fg;
            },
        }
        return cell;
    }

    // FIXME: can't we just return the constSlice() of the stack buffer?
    pub fn shortName(self: *const Item) !StackBuffer(u8, 64) {
        var buf = StackBuffer(u8, 64).init(&([_]u8{0} ** 64));
        var fbs = std.io.fixedBufferStream(buf.slice());
        switch (self.*) {
            .Ring => |r| try fmt.format(fbs.writer(), "*{s}", .{r.name}),
            .Consumable => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Vial => |v| try fmt.format(fbs.writer(), "♪{s}", .{v.name()}),
            .Projectile => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Armor => |a| try fmt.format(fbs.writer(), "]{s}", .{a.name}),
            .Cloak => |c| try fmt.format(fbs.writer(), "clk of {s}", .{c.name}),
            .Aux => |c| try fmt.format(fbs.writer(), "[{s}", .{c.name}),
            .Weapon => |w| try fmt.format(fbs.writer(), "){s}", .{w.name}),
            .Boulder => |b| try fmt.format(fbs.writer(), "•{s} of {s}", .{ b.chunkName(), b.name }),
            .Prop => |b| try fmt.format(fbs.writer(), "{s}", .{b.name}),
            .Evocable => |v| try fmt.format(fbs.writer(), "}}{s}", .{v.name}),
        }
        buf.resizeTo(@intCast(usize, fbs.getPos() catch err.wat()));
        return buf;
    }

    // FIXME: can't we just return the constSlice() of the stack buffer?
    pub fn longName(self: *const Item) !StackBuffer(u8, 128) {
        var buf = StackBuffer(u8, 128).init(&([_]u8{0} ** 128));
        var fbs = std.io.fixedBufferStream(buf.slice());
        switch (self.*) {
            .Ring => |r| try fmt.format(fbs.writer(), "ring of {s}", .{r.name}),
            .Consumable => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Vial => |v| try fmt.format(fbs.writer(), "vial of {s}", .{v.name()}),
            .Projectile => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Armor => |a| try fmt.format(fbs.writer(), "{s}", .{a.name}),
            .Cloak => |c| try fmt.format(fbs.writer(), "cloak of {s}", .{c.name}),
            .Aux => |c| try fmt.format(fbs.writer(), "{s}", .{c.name}),
            .Weapon => |w| try fmt.format(fbs.writer(), "{s}", .{w.name}),
            .Boulder => |b| try fmt.format(fbs.writer(), "{s} of {s}", .{ b.chunkName(), b.name }),
            .Prop => |b| try fmt.format(fbs.writer(), "{s}", .{b.name}),
            .Evocable => |v| try fmt.format(fbs.writer(), "{s}", .{v.name}),
        }
        buf.resizeTo(@intCast(usize, fbs.getPos() catch err.wat()));
        return buf;
    }

    pub fn id(self: Item) ?[]const u8 {
        return switch (self) {
            .Consumable => |p| p.id,
            .Projectile => |p| p.id,
            .Armor => |a| a.id,
            .Cloak => |c| c.id,
            .Aux => |a| a.id,
            .Weapon => |w| w.id,
            .Prop => |p| p.id,
            .Evocable => |v| v.id,
            .Ring => |r| r.name,
            .Vial => "AMBIG_vial",
            .Boulder => "AMBIG_boulder",
        };
    }
};

pub const TileType = enum {
    Wall,
    Floor,
    Water,
    Lava,
};

pub const Tile = struct {
    marked: bool = false,
    prison: bool = false,
    type: TileType = .Wall,
    material: *const Material = &materials.Basalt,
    mob: ?*Mob = null,
    surface: ?SurfaceItem = null,
    terrain: *const surfaces.Terrain = &surfaces.DefaultTerrain,
    spatter: SpatterArray = SpatterArray.initFill(0),

    // A random value that's set at the beginning of the game.
    // To be used when a random value that's specific to a coordinate, but that
    // won't change over time, is needed.
    rand: usize = 0,

    pub fn displayAs(coord: Coord, ignore_lights: bool, ignore_mobs: bool) display.Cell {
        var self = state.dungeon.at(coord);
        var cell = display.Cell{};

        switch (self.type) {
            .Water => cell = .{
                .ch = '≈',
                .fg = 0x86c2f5, // cornflowerblue
                .bg = 0x34558e, // steelblue
            },
            .Lava => cell = .{
                .ch = '≈',
                .fg = 0xff5347, // tomato
                .bg = 0xcb0f1f, // red
            },
            .Wall => cell = .{
                .ch = materials.tileFor(coord, self.material.tileset),
                .fg = self.material.color_fg,
                .bg = self.material.color_bg orelse colors.BG,
                .sch = self.material.sprite,
                .sfg = self.material.color_sfg orelse self.material.color_fg,
                .sbg = self.material.color_sbg orelse self.material.color_bg orelse colors.BG,
            },
            .Floor => {
                cell.ch = self.terrain.tile;
                cell.sch = self.terrain.sprite;
                cell.fg = self.terrain.color;
                cell.bg = colors.BG;
            },
        }

        const gases = state.dungeon.atGas(coord);
        for (gases) |q, g| {
            const gcolor = gas.Gases[g].color;
            // const aq = 1 - math.clamp(q, 0.19, 1);
            if (q > 0) {
                cell.fg = gcolor; //colors.mix(gcolor, cell.bg, aq);
                cell.ch = '§';
                cell.sch = null;
            }
        }

        if (self.mob != null and !ignore_mobs) {
            assert(self.type != .Wall);

            const mob = self.mob.?;

            cell.fg = switch (mob.ai.phase) {
                .Work, .Flee => 0xffffff,
                .Investigate => 0xffd700,
                .Hunt => 0xff9999,
            };
            if (mob == state.player or
                mob.isUnderStatus(.Paralysis) != null or
                mob.isUnderStatus(.Daze) != null)
                cell.fg = 0xffffff;
            if (mob.isUnderStatus(.Sleeping) != null)
                cell.fg = 0xffcfff;

            const hp_loss_percent = 100 - (mob.HP * 100 / mob.max_HP);
            if (hp_loss_percent > 0) {
                //const red = @floatToInt(u32, (255 * (hp_loss_percent / 2)) / 100) + 0x22;
                //cell.bg = math.clamp(red, 0x66, 0xff) << 16;
            }

            if (!mob.ai.is_combative) {
                cell.fg = colors.AQUAMARINE;
            }

            if (mob.prisoner_status) |ps| {
                if (state.dungeon.at(coord).prison or ps.held_by != null) {
                    cell.fg = 0xb0c4de;
                }
            }

            cell.ch = mob.tile;
            cell.sch = null;
        } else if (state.dungeon.fireAt(coord).* > 0) {
            const famount = state.dungeon.fireAt(coord).*;
            cell.ch = fire.fireGlyph(famount);
            cell.sch = null;
            cell.fg = fire.fireColor(famount);
        } else if (state.dungeon.itemsAt(coord).last()) |item| {
            err.ensure(self.type != .Wall, "Item {s} located in wall @({},{})", .{ item.id().?, coord.x, coord.y }) catch {
                return .{ .fg = 0xffffff, .bg = 0xff0000, .sfg = 0, .sbg = 0, .ch = 'X', .sch = null };
            };

            cell = item.tile();
        } else if (state.dungeon.at(coord).surface) |surfaceitem| {
            err.ensure(self.type != .Wall, "Surface {s} located in wall @({},{})", .{ surfaceitem.id(), coord.x, coord.y }) catch {
                return .{ .fg = 0xffffff, .bg = 0xff0000, .sfg = 0, .sbg = 0, .ch = 'X', .sch = null };
            };

            cell.fg = 0xffffff;

            switch (surfaceitem) {
                .Corpse => |_| {
                    cell.fg = 0xffe0ef;
                    cell.ch = '%';
                    cell.sch = null;
                },
                .Container => |c| {
                    // if (c.capacity >= 14) {
                    //     cell.fg = 0x000000;
                    //     cell.bg = 0x808000;
                    // }
                    cell.fg = if (c.isLootable()) colors.GOLD else colors.GREY;
                    cell.ch = c.tile;
                    cell.sch = null;
                },
                .Machine => |m| {
                    if (m.isPowered()) {
                        if (m.powered_bg) |mach_bg| cell.bg = mach_bg;
                        if (m.powered_fg) |mach_fg| cell.fg = mach_fg;
                        if (m.powered_sbg) |mach_bg| cell.sbg = mach_bg;
                        if (m.powered_sfg) |mach_fg| cell.sfg = mach_fg;
                    } else {
                        if (m.unpowered_bg) |mach_bg| cell.bg = mach_bg;
                        if (m.unpowered_fg) |mach_fg| cell.fg = mach_fg;
                        if (m.unpowered_sbg) |mach_bg| cell.sbg = mach_bg;
                        if (m.unpowered_sfg) |mach_fg| cell.sfg = mach_fg;
                    }
                    if (m.bg) |bg| cell.bg = bg;
                    if (m.sbg) |bg| cell.bg = bg;

                    cell.ch = m.tile();
                    cell.sch = m.sprite();
                },
                .Prop => |p| {
                    if (p.bg) |prop_bg| cell.bg = prop_bg;
                    if (p.fg) |prop_fg| cell.fg = prop_fg;
                    cell.ch = p.tile;
                    cell.sch = p.sprite;
                },
                .Poster => |_| {
                    //cell.fg = self.material.color_bg orelse self.material.color_fg;
                    //break :poster '?';
                    cell.bg = colors.GOLD;
                    cell.fg = 0;
                    cell.ch = '≡';

                    cell.sch = .S_G_Poster;
                    cell.sfg = colors.GOLD;
                    cell.sbg = colors.BG;
                },
                .Stair => |s| {
                    if (s == null) {
                        cell.ch = '>';
                        cell.sch = .S_G_StairsDown;
                        cell.fg = 0xeeeeee;
                        cell.bg = 0x0000ff;
                    } else {
                        cell.ch = if (state.levelinfo[s.?].optional) '≤' else '<';
                        cell.bg = 0x997700;
                        cell.fg = 0xffd700;

                        cell.sch = if (state.levelinfo[s.?].optional) .S_G_M_DoorShut else .S_G_StairsUp;
                        cell.sbg = colors.BG;
                        cell.sfg = 0xffd700;
                    }
                },
            }
        }

        if (!ignore_lights and self.type == .Floor) {
            if (!state.dungeon.lightAt(coord).*) {
                cell.fg = colors.percentageOf(cell.fg, 60);
            }
        }

        // var spattering = self.spatter.iterator();
        // while (spattering.next()) |entry| {
        //     const spatter = entry.key;
        //     const num = entry.value.*;
        //     const sp_color = spatter.color();
        //     const q = @intToFloat(f64, num / 10);
        //     const aq = 1 - math.clamp(q, 0.19, 0.40);
        //     if (num > 0) cell.bg = colors.mix(sp_color, cell.bg, aq);
        // }

        return cell;
    }
};

pub const Dungeon = struct {
    map: [LEVELS][HEIGHT][WIDTH]Tile = [1][HEIGHT][WIDTH]Tile{[1][WIDTH]Tile{[1]Tile{.{}} ** WIDTH} ** HEIGHT} ** LEVELS,
    items: [LEVELS][HEIGHT][WIDTH]ItemBuffer = [1][HEIGHT][WIDTH]ItemBuffer{[1][WIDTH]ItemBuffer{[1]ItemBuffer{ItemBuffer.init(null)} ** WIDTH} ** HEIGHT} ** LEVELS,
    gas: [LEVELS][HEIGHT][WIDTH][gas.GAS_NUM]f64 = [1][HEIGHT][WIDTH][gas.GAS_NUM]f64{[1][WIDTH][gas.GAS_NUM]f64{[1][gas.GAS_NUM]f64{[1]f64{0} ** gas.GAS_NUM} ** WIDTH} ** HEIGHT} ** LEVELS,
    sound: [LEVELS][HEIGHT][WIDTH]Sound = [1][HEIGHT][WIDTH]Sound{[1][WIDTH]Sound{[1]Sound{.{}} ** WIDTH} ** HEIGHT} ** LEVELS,
    light: [LEVELS][HEIGHT][WIDTH]bool = [1][HEIGHT][WIDTH]bool{[1][WIDTH]bool{[1]bool{false} ** WIDTH} ** HEIGHT} ** LEVELS,
    fire: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    stairs: [LEVELS]StairBuffer = [_]StairBuffer{StairBuffer.init(null)} ** LEVELS,
    entries: [LEVELS]Coord = [_]Coord{Coord.new2(0, 0, 0)} ** LEVELS,

    pub const ItemBuffer = StackBuffer(Item, 4);
    pub const StairBuffer = StackBuffer(Coord, MAX_STAIRS);

    pub const MAX_STAIRS: usize = 10; // Used to be 2, but need to make room for tunneling alg's stairs

    pub const MOB_OPACITY: usize = 0;
    pub const FLOOR_OPACITY: usize = 10;

    // Return the terrain if no surface item, else the default terrain.
    //
    pub fn terrainAt(self: *Dungeon, coord: Coord) *const surfaces.Terrain {
        const tile = self.at(coord);
        if (tile.type != .Floor) return &surfaces.DefaultTerrain;
        return if (tile.surface == null) tile.terrain else &surfaces.DefaultTerrain;
    }

    pub fn isTileOpaque(coord: Coord) bool {
        const tile = state.dungeon.at(coord);

        if (tile.type == .Wall)
            return true;

        if (tile.surface) |surface| {
            switch (surface) {
                .Machine => |m| if (m.opacity() >= 1.0) return true,
                .Prop => |p| if (p.opacity >= 1.0) return true,
                else => {},
            }
        }

        const gases = state.dungeon.atGas(coord);
        for (gases) |q, g| {
            if (q > 0 and gas.Gases[g].opacity >= 1.0) return true;
        }

        return false;
    }

    pub fn tileOpacity(coord: Coord) usize {
        const tile = state.dungeon.at(coord);
        var o: usize = FLOOR_OPACITY;

        if (tile.type == .Wall)
            return @floatToInt(usize, tile.material.opacity * 100);

        o += state.dungeon.terrainAt(coord).opacity;

        if (tile.mob) |_|
            o += MOB_OPACITY;

        if (tile.surface) |surface| {
            switch (surface) {
                .Machine => |m| o += @floatToInt(usize, m.opacity() * 100),
                .Prop => |p| o += @floatToInt(usize, p.opacity * 100),
                else => {},
            }
        }

        const gases = state.dungeon.atGas(coord);
        for (gases) |q, g| {
            if (q > 0) o += @floatToInt(usize, gas.Gases[g].opacity * 100);
        }

        o += fire.fireOpacity(state.dungeon.fireAt(coord).*);

        return o;
    }

    pub fn emittedLight(self: *Dungeon, coord: Coord) usize {
        const tile: *Tile = state.dungeon.at(coord);

        var l: usize = tile.terrain.luminescence;

        if (tile.type == .Lava)
            l += 60;

        if (tile.mob) |mob| {
            if (mob.isUnderStatus(.Corona)) |se| {
                l += if (se.power > 0) se.power else 50;
            }
        }

        if (tile.surface) |surface| {
            switch (surface) {
                .Machine => |m| l += m.luminescence(),
                .Stair => l += 30,
                else => {},
            }
        }

        l += fire.fireLight(self.fireAt(coord).*);

        return l;
    }

    pub fn hasMachine(self: *Dungeon, c: Coord) bool {
        if (self.at(c).surface) |surface| {
            switch (surface) {
                .Machine => |_| return true,
                else => {},
            }
        }

        return false;
    }

    pub fn hasContainer(self: *Dungeon, c: Coord) ?*Container {
        const tile = self.at(c);
        if (tile.surface) |surface|
            if (std.meta.activeTag(surface) == .Container)
                return surface.Container;
        return null;
    }

    pub fn neighboringMachines(self: *Dungeon, c: Coord) usize {
        var machs: usize = if (self.hasMachine(c)) 1 else 0;
        for (&DIRECTIONS) |d| {
            if (c.move(d, state.mapgeometry)) |neighbor| {
                if (self.hasMachine(neighbor)) machs += 1;
            }
        }
        return machs;
    }

    pub fn neighboringWalls(self: *Dungeon, c: Coord, diags: bool) usize {
        return self.neighboringOfType(c, diags, .Wall);
    }

    pub fn neighboringOfType(self: *Dungeon, c: Coord, diags: bool, ttype: TileType) usize {
        const directions = if (diags) &DIRECTIONS else &CARDINAL_DIRECTIONS;

        var ctr: usize = if (self.at(c).type == ttype) 1 else 0;
        for (directions) |d| {
            if (c.move(d, state.mapgeometry)) |neighbor| {
                if (self.at(neighbor).type == ttype)
                    ctr += 1;
            } else {
                if (ttype == .Wall)
                    ctr += 1;
                continue;
            }
        }
        return ctr;
    }

    // Get an item from the ground or a container (if it exists), otherwise
    // return null;
    pub fn getItem(self: *Dungeon, c: Coord) !Item {
        if (self.hasContainer(c)) |container| {
            return try container.items.orderedRemove(0);
        } else {
            return try self.itemsAt(c).pop();
        }
    }

    pub fn spatter(self: *Dungeon, c: Coord, what: Spatter) void {
        for (&DIRECTIONS) |d| {
            if (!rng.onein(4)) continue;

            if (c.move(d, state.mapgeometry)) |neighbor| {
                const prev = self.at(neighbor).spatter.get(what);
                const new = math.min(prev + rng.range(usize, 0, 4), 10);
                self.at(neighbor).spatter.set(what, new);
            }
        }

        if (rng.boolean()) {
            const prev = self.at(c).spatter.get(what);
            const new = math.min(prev + rng.range(usize, 0, 5), 10);
            self.at(c).spatter.set(what, new);
        }
    }

    pub inline fn at(self: *Dungeon, c: Coord) *Tile {
        return &self.map[c.z][c.y][c.x];
    }

    pub fn corpseAt(self: *Dungeon, c: Coord) ?*Mob {
        if (self.at(c).surface) |s|
            if (s == .Corpse)
                return s.Corpse;
        return null;
    }

    pub fn machineAt(self: *Dungeon, c: Coord) ?*Machine {
        if (self.at(c).surface) |s|
            if (s == .Machine)
                return s.Machine;
        return null;
    }

    // STYLE: rename to gasAt
    pub inline fn atGas(self: *Dungeon, c: Coord) []f64 {
        return &self.gas[c.z][c.y][c.x];
    }

    pub inline fn soundAt(self: *Dungeon, c: Coord) *Sound {
        return &self.sound[c.z][c.y][c.x];
    }

    pub inline fn fireAt(self: *Dungeon, c: Coord) *usize {
        return &self.fire[c.z][c.y][c.x];
    }

    pub inline fn lightAt(self: *Dungeon, c: Coord) *bool {
        return &self.light[c.z][c.y][c.x];
    }

    pub inline fn itemsAt(self: *Dungeon, c: Coord) *ItemBuffer {
        return &self.items[c.z][c.y][c.x];
    }
};

pub const Spatter = enum {
    Ash,
    Blood,
    Dust,
    Vomit,
    Water,

    pub inline fn color(self: Spatter) u32 {
        return switch (self) {
            .Ash => 0x121212,
            .Blood => 0x9a1313,
            .Dust => 0x92744c,
            .Vomit => 0x329b32,
            .Water => 0x12356e,
        };
    }
};
