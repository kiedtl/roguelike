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
const display = @import("display.zig");
const err = @import("err.zig");
const explosions = @import("explosions.zig");
const fire = @import("fire.zig");
const fov = @import("fov.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const materials = @import("materials.zig");
const player = @import("player.zig");
const rng = @import("rng.zig");
const sound = @import("sound.zig");
const spells = @import("spells.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const termbox = @import("termbox.zig");
const utils = @import("utils.zig");

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const Rune = items.Rune;
const Evocable = items.Evocable;
const Projectile = items.Projectile;
const Consumable = items.Consumable;
const PatternChecker = items.PatternChecker;
const Cloak = items.Cloak;

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
            math.max(a.y, b.y) - math.min(a.y, b.y),
        );
    }

    pub inline fn distance(a: Self, b: Self) usize {
        const diff = a.difference(b);

        // Euclidean: d = sqrt(dx^2 + dy^2)
        //
        // return math.sqrt((diff.x * diff.x) + (diff.y * diff.y));

        // Manhattan: d = dx + dy
        // return diff.x + diff.y;

        // Chebyshev: d = max(dx, dy)
        return math.max(diff.x, diff.y);
    }

    pub inline fn distanceManhattan(a: Self, b: Self) usize {
        const diff = a.difference(b);
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
        return Coord.new2(a.z, a.x + b.x, a.y + b.y);
    }

    pub inline fn asRect(self: *const Self) Rect {
        return Rect{ .start = self.*, .width = 1, .height = 1 };
    }

    pub fn move(self: *const Self, direction: Direction, limit: Self) ?Coord {
        var dx: isize = 0;
        var dy: isize = 0;

        switch (direction) {
            .North => {
                dx = 0;
                dy = -1;
            },
            .South => {
                dx = 0;
                dy = 1;
            },
            .East => {
                dx = 1;
                dy = 0;
            },
            .West => {
                dx = -1;
                dy = 0;
            },
            .NorthEast => {
                dx = 1;
                dy = -1;
            },
            .NorthWest => {
                dx = -1;
                dy = -1;
            },
            .SouthEast => {
                dx = 1;
                dy = 1;
            },
            .SouthWest => {
                dx = -1;
                dy = 1;
            },
        }

        const newx = @intCast(isize, self.x) + dx;
        const newy = @intCast(isize, self.y) + dy;

        if ((newx >= 0 and @intCast(usize, newx) < limit.x) and
            (newy >= 0 and @intCast(usize, newy) < limit.y))
        {
            return Coord.new2(self.z, @intCast(usize, newx), @intCast(usize, newy));
        } else {
            return null;
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
    Status, // A status effect was added or removed.
    Combat, // X hit you! You hit X!
    CombatUnimportant, // X missed you! You miss X! You slew X!
    Unimportant, // A bit dark, okay if player misses it.
    Info,
    Move,
    Trap,
    Damage,
    Important,
    SpellCast,
    Inventory, // Grabbing, dropping, or equipping item

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
            .Inventory => 0x7a9cc7,
        };
    }
};

pub const Resistance = enum {
    rFire,
    rElec,
    Armor,
    rFume,
    rPois,

    pub fn string(self: Resistance) []const u8 {
        return switch (self) {
            .rFire => "rFire",
            .rElec => "rElec",
            .Armor => "Armor",
            .rFume => "rFume",
            .rPois => "rPois",
        };
    }
};

pub const Damage = struct {
    lethal: bool = true, // If false, extra damage will be shaved
    amount: f64,
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
        Poison,

        pub fn resist(self: DamageKind) Resistance {
            return switch (self) {
                .Physical => .Armor,
                .Fire => .rFire,
                .Electric => .rElec,
                .Poison => .rPois,
            };
        }

        pub fn string(self: DamageKind) []const u8 {
            return switch (self) {
                .Physical => "dmg",
                .Fire => "fire",
                .Electric => "elec",
                .Poison => "poison",
            };
        }
    };

    pub const DamageSource = enum {
        Other,
        MeleeAttack,
        RangedAttack,
        Stab,
        Explosion,
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
        delay: usize,
    },
    Teleport: Coord,
    Grab,
    Drop,
    Use,
    Throw,
    Fire,
    Cast,
    None,

    pub inline fn cost(self: Activity) usize {
        return switch (self) {
            .Interact, .Cast, .Throw, .Fire, .Rest, .Move, .Teleport, .Grab, .Drop, .Use => 100,
            .Attack => |a| a.delay,
            .None => err.wat(),
        };
    }
};

pub const EnemyRecord = struct {
    mob: *Mob,
    last_seen: Coord,
    counter: usize,

    pub const AList = std.ArrayList(EnemyRecord);
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

// Note, this is outdated. Cave goblins are just as nice as plains humans,
// and southern humans are supposed to be the protoganists (sort of) in this
// universe.
//
// TODO: rewrite allegiances (and rename to 'Factions' maybe?)
//
pub const Allegiance = enum {
    Necromancer,
    OtherGood, // Humans in the plains
    OtherEvil, // Cave goblins, southern humans
};

pub const Status = enum {
    // Status list {{{

    // Gives sharp reduction to enemy's morale.
    //
    // Doesn't have a power field
    Intimidating,

    // Hampers movement.
    //
    // Doesn't have a power field.
    Drunk,

    // Enables copper weapons.
    //
    // Doesn't have a power field.
    CopperWeapon,

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

    // .Melee bonus if surrounded by empty space.
    //
    // Doesn't have a power field.
    OpenMelee,

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
    Confusion,

    // Makes mob fast or slow.
    //
    // Doesn't have a power field.
    Fast,
    Slow,

    // Makes the mob regenerate 1 HP per turn.
    //
    // Doesn't have a power field.
    Recuperate,

    // Gives damage and slows mob.
    //
    // Doesn't have a power field (but probably should).
    Poison,

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

    // Allows mob to see completely in dark areas.
    //
    // Doesn't have a power field.
    NightVision,

    // Prevents mob from seeing in brightly-lit areas.
    //
    // Doesn't have a power field.
    DayBlindness,

    // Prevents mob from seeing in dimly-lit areas.
    //
    // Doesn't have a power field.
    NightBlindness,

    // Allows a mob to shove past all other mobs.
    //
    // Doesn't have a power field.
    Shove,

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

    pub const MAX_DURATION: usize = 20;

    pub fn string(self: Status, mob: *const Mob) []const u8 { // {{{
        return switch (self) {
            .Intimidating => "intimidating",
            .Drunk => "drunk",
            .CopperWeapon => "copper",
            .Corruption => "corrupted",
            .Fireproof => "fireproof",
            .Flammable => "flammable",
            .Blind => "blind",
            .Riposte => "riposte",
            .Debil => "debilitated",
            .OpenMelee => "open melee",
            .Conductive => "conductive",
            .Noisy => "noisy",
            .Sleeping => switch (mob.life_type) {
                .Living => "sleeping",
                .Construct, .Undead => "dormant",
            },
            .Paralysis => "paralyzed",
            .Held => "held",
            .Echolocation => "echolocating",
            .Corona => "glowing",
            .Daze => "dazed",
            .Confusion => "confused",
            .Fast => "hasted",
            .Slow => "slowed",
            .Recuperate => "recuperating",
            .Poison => "poisoned",
            .Nausea => "nauseated",
            .Fire => "burning",
            .Invigorate => "invigorated",
            .Pain => "tormented",
            .Fear => "terrified",
            .NightVision => "night-sighted",
            .DayBlindness => "day-blinded",
            .NightBlindness => "night-blinded",
            .Shove => "shoving",
            .Enraged => "enraged",
            .Exhausted => "exhausted",
            .Explosive => "explosive",
            .ExplosiveElec => "charged",
            .Lifespan => "lifespan",
        };
    } // }}}

    pub fn messageWhenAdded(self: Status) ?[3][]const u8 { // {{{
        return switch (self) {
            .Intimidating => .{ "assume", "assumes", " a fearsome visage" },
            .Drunk => .{ "feel", "looks", " a bit drunk" },
            .CopperWeapon => null,
            .Corruption => .{ "are", "is", " corrupted" },
            .Fireproof => .{ "are", "is", " resistant to fire" },
            .Flammable => .{ "are", "is", " vulnerable to fire" },
            .Blind => .{ "are", "is", " blinded" },
            .Riposte => null,
            .Debil => .{ "are", "is", " debilitated" },
            .OpenMelee, .Conductive, .Noisy => null,
            .Sleeping => .{ "go", "goes", " to sleep" }, // FIXME: bad wording for unliving
            .Paralysis => .{ "are", "is", " paralyzed" },
            .Held => .{ "are", "is", " entangled" },
            .Corona => .{ "begin", "starts", " glowing" },
            .Daze => .{ "are", "is", " dazed" },
            .Confusion => .{ "are", "looks", " confused" },
            .Fast => .{ "feel yourself", "starts", " moving faster" },
            .Slow => .{ "feel yourself", "starts", " moving slowly" },
            .Poison => .{ "feel very", "looks very", " sick" },
            .Nausea => .{ "feel", "looks", " nauseated" },
            .Fire => .{ "catch", "catches", " fire" },
            .Invigorate => .{ "feel", "looks", " invigorated" },
            .Pain => .{ "are", "is", " wracked with pain" },
            .Fear => .{ "are crazed", "is crazed", " with fear" },
            .Shove => .{ "begin", "starts", " violently shoving past foes" },
            .Enraged => .{ "fly", "flies", " into a rage" },
            .Exhausted => .{ "feel", "looks", " exhausted" },
            .Lifespan => null,
            .Explosive => null,
            .ExplosiveElec => null,
            .Echolocation => null,
            .Recuperate => null,
            .NightVision,
            .NightBlindness,
            .DayBlindness,
            => null,
        };
    } // }}}

    pub fn messageWhenRemoved(self: Status) ?[3][]const u8 { // {{{
        return switch (self) {
            .Intimidating => .{ "no longer seem", "no longer seems", " so scary" },
            .Drunk => .{ "feel", "looks", " more sober" },
            .CopperWeapon => null,
            .Corruption => .{ "are no longer", "is no longer", " corrupted" },
            .Fireproof => .{ "are no longer", "is no longer", " resistant to fire" },
            .Flammable => .{ "are no longer", "is no longer", " vulnerable to fire" },
            .Blind => .{ "are no longer", "is no longer", " blinded" },
            .Riposte => null,
            .Debil => .{ "are no longer", "is no longer", " debilitated" },
            .OpenMelee, .Conductive, .Noisy => null,
            .Sleeping => .{ "wake", "wakes", " up" },
            .Paralysis => .{ "can move again", "starts moving again", "" },
            .Held => .{ "break", "breaks", " free" },
            .Corona => .{ "stop", "stops", " glowing" },
            .Daze => .{ "break out of your daze", "breaks out of their daze", "" },
            .Confusion => .{ "are no longer", "no longer looks", " confused" },
            .Fast => .{ "are no longer", "is no longer", " moving faster" },
            .Slow => .{ "are no longer", "is no longer", " moving slowly" },
            .Poison => .{ "feel", "looks", " healthier" },
            .Nausea => .{ "are no longer", "is no longer", " nauseated" },
            .Fire => .{ "are no longer", "is no longer", " on fire" },
            .Invigorate => .{ "no longer feel", "no longer looks", " invigorated" },
            .Pain => .{ "are no longer", "is no longer", " wracked with pain" },
            .Fear => .{ "are no longer", "is no longer", " crazed with fear" },
            .Shove => .{ "stop", "stops", " shoving past foes" },
            .Enraged => .{ "stop", "stops", " raging" },
            .Exhausted => .{ "are no longer", "is no longer", " exhausted" },
            .Explosive => null,
            .ExplosiveElec => null,
            .Lifespan => null,
            .Echolocation => null,
            .Recuperate => null,
            .NightVision,
            .NightBlindness,
            .DayBlindness,
            => null,
        };
    } // }}}

    // Tick functions {{{

    pub fn tickCorruption(mob: *Mob) void {
        // Implement detect undead.
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(mob.coord.z, x, y);
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

    pub fn tickNoisy(mob: *Mob) void {
        if (mob.isUnderStatus(.Sleeping) == null)
            mob.makeNoise(.Movement, .Medium);
    }

    pub fn tickRecuperate(mob: *Mob) void {
        mob.HP = math.clamp(mob.HP + 1, 0, mob.max_HP);
    }

    pub fn tickPoison(mob: *Mob) void {
        const damage = rng.range(usize, 0, 1);
        if (damage > 0) { // Don't spam "You are weakened (0 damage, 0 resist)"
            mob.takeDamage(.{
                .amount = @intToFloat(f64, damage),
                .blood = false,
                .kind = .Poison,
            }, .{ .basic = true });
        }
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
                mob.takeDamage(.{
                    .amount = @intToFloat(f64, 1),
                    .kind = .Fire,
                    .blood = false,
                }, .{
                    .noun = "The fire",
                    .strs = &[_]DamageStr{
                        items._dmgstr(000, "BUG", "BUG", ""),
                        items._dmgstr(020, "BUG", "scorches", ""),
                        items._dmgstr(080, "BUG", "burns", ""),
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

        if (st.power > 0) {
            mob.takeDamage(.{
                .amount = @intToFloat(f64, rng.rangeClumping(usize, 0, st.power, 2)),
                .blood = false,
            }, .{
                .noun = "The pain",
                .strs = &[_]DamageStr{items._dmgstr(0, "weaken", "weakens", "")},
            });
        }

        if (rng.percent(@as(usize, 50))) {
            var directions = DIRECTIONS;
            rng.shuffle(Direction, &directions);
            for (&directions) |direction|
                if (mob.coord.move(direction, state.mapgeometry)) |dest_coord| {
                    if (mob.teleportTo(dest_coord, direction, true)) {
                        if (state.player.cansee(mob.coord)) {
                            const verb: []const u8 = if (state.player == mob) "writhe" else "writhes";
                            state.message(.Unimportant, "{c} {s} in agony.", .{ mob, verb });
                        }

                        if (rng.percent(@as(usize, 50))) {
                            mob.makeNoise(.Scream, .Louder);
                        }
                        break;
                    }
                };
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

        var tile: state.MemoryTile = .{ .fg = 0xffffff, .bg = colors.BG, .ch = '#', .type = .Echolocated };

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

                    tile.ch = if (state.dungeon.at(item).type == .Wall) '#' else '·';
                    _ = state.memory.getOrPutValue(item, tile) catch err.wat();
                }
            }
        }
    }

    // }}}
};

pub const StatusDataInfo = struct {
    // This field doesn't matter when it's in mob.statuses
    status: Status = undefined,

    // What's the "power" of a status (percentage). For some statuses, doesn't
    // mean anything at all.
    power: usize = 0, // What's the "power" of the status

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
    spellcaster_backup_action: union(enum) { KeepDistance, Melee } = .Melee,

    flee_effect: ?StatusDataInfo = .{
        .status = .Fast,
        .duration = .{ .Tmp = 0 },
        .exhausting = true,
    },

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
        CalledWithUndead, // Can be called by CAST_CALL_UNDEAD, even if not undead.
        FearsDarkness, // Tries very hard to stay in light areas (pathfinding).
        MovesDiagonally, // Usually tries to move diagonally.
    };

    pub fn flag(self: *const AI, f: Flag) bool {
        return mem.containsAtLeast(Flag, self.flags, 1, &[_]Flag{f});
    }
};

pub const AIWorkPhase = enum {
    CleanerScan,
    CleanerClean,
    HaulerScan,
    HaulerTake,
    HaulerDrop,
};

pub const Prisoner = struct {
    of: Allegiance,
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

    members: StackBuffer(*Mob, 16) = StackBuffer(*Mob, 16).init(null),
    leader: ?*Mob = null, // FIXME: Should never be null in practice!
    enemies: EnemyRecord.AList = undefined,

    pub const List = LinkedList(Squad);

    pub fn allocNew() *Squad {
        const squad = Squad{
            .enemies = EnemyRecord.AList.init(state.GPA.allocator()),
        };
        state.squads.append(squad) catch err.wat();
        return state.squads.last().?;
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
        };
    }
};

pub const Mob = struct { // {{{
    // linked list stuff
    __next: ?*Mob = null,
    __prev: ?*Mob = null,

    id: []const u8,
    species: *const Species,
    undead_prefix: []const u8 = "former ",
    tile: u21,
    allegiance: Allegiance = .Necromancer,

    squad: ?*Squad = null,
    prisoner_status: ?Prisoner = null,

    fov: [HEIGHT][WIDTH]usize = [1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT,
    path_cache: std.AutoHashMap(Path, Coord) = undefined,
    enemies: EnemyRecord.AList = undefined,
    allies: MobArrayList = undefined,
    sustiles: std.ArrayList(SuspiciousTileRecord) = undefined,

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

    HP: f64 = undefined,
    energy: isize = 0,
    statuses: StatusArray = StatusArray.initFill(.{}),
    ai: AI,
    activities: RingBuffer(Activity, MAX_ACTIVITY_BUFFER_SZ) = .{},
    last_attempted_move: ?Direction = null,
    last_damage: ?Damage = null,

    inventory: Inventory = .{},

    life_type: enum { Living, Construct, Undead } = .Living,
    is_dead: bool = false,
    killed_by: ?*Mob = null,

    // Immutable instrinsic attributes.
    //
    // base_night_vision:  Whether the mob can see in darkness.
    // deg360_vision:      Mob's FOV ignores the facing mechanic and can see in all
    //                     directions (e.g., player, statues)
    // no_show_fov:        If false, display code will not show mob's FOV.
    // memory:             The maximum length of time for which a mob can remember
    //                     an enemy.
    // deaf:               Whether it can hear sounds.
    //
    base_night_vision: bool = false,
    deg360_vision: bool = false,
    no_show_fov: bool = false,
    memory_duration: usize = 4,
    deaf: bool = false,
    max_HP: f64,
    blood: ?Spatter = .Blood,
    blood_spray: ?usize = null, // Gas ID
    corpse: enum { Normal, Wall, None } = .Normal,
    immobile: bool = false,
    innate_resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},

    // Don't use EnumFieldStruct here because we want to provide per-field
    // defaults.
    //stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    stats: struct {
        Melee: isize = 60,
        Missile: isize = 40,
        Martial: isize = 0,
        Evade: isize = 0,
        Speed: isize = 100,
        Sneak: isize = 1,
        Vision: isize = 6,
        Willpower: isize = 3,
    } = .{},

    // Listed in order of preference.
    spells: []const SpellOptions = &[_]SpellOptions{},

    max_MP: usize = 0,
    MP: usize = 0,

    pub const Inventory = struct {
        pack: PackBuffer = PackBuffer.init(&[_]Item{}),
        equ_slots: [EQU_SLOT_SIZE]?Item = [_]?Item{null} ** EQU_SLOT_SIZE,

        pub const RING_SLOTS = [_]EquSlot{ .Ring1, .Ring2, .Ring3, .Ring4 };

        pub const EquSlot = enum(usize) {
            Weapon = 0,
            Backup = 1,
            Ring1 = 2,
            Ring2 = 3,
            Ring3 = 4,
            Ring4 = 5,
            Armor = 6,
            Cloak = 7,

            pub fn slotFor(item: Item) EquSlot {
                return switch (item) {
                    .Weapon => .Weapon,
                    .Ring => err.bug("Tried to get equipment slot for ring", .{}),
                    .Armor => .Armor,
                    .Cloak => .Cloak,
                    else => err.wat(),
                };
            }

            pub fn name(self: EquSlot) []const u8 {
                return switch (self) {
                    .Weapon => "weapon",
                    .Backup => "backup",
                    .Ring1, .Ring2, .Ring3, .Ring4 => "ring",
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

        if (self.life_type == .Undead) {
            var fbs = std.io.fixedBufferStream(&Static.buf);
            std.fmt.format(fbs.writer(), "{s}{s}", .{
                self.undead_prefix, base_name,
            }) catch err.wat();
            return fbs.getWritten();
        } else {
            return base_name;
        }
    }

    pub fn format(self: *const Mob, comptime f: []const u8, opts: fmt.FormatOptions, writer: anytype) !void {
        _ = opts;

        comptime var caps = false;

        if (comptime mem.eql(u8, f, "")) {
            //
        } else if (comptime mem.eql(u8, f, "c")) {
            caps = true;
        } else {
            @compileError("Unknown format string: '" ++ f ++ "'");
        }

        if (self == state.player) {
            const n = if (caps) "You" else "you";
            try fmt.format(writer, "{s}", .{n});
        } else if (!state.player.cansee(self.coord)) {
            const n = if (caps) "Something" else "something";
            try fmt.format(writer, "{s}", .{n});
        } else {
            const the = if (caps) "The" else "the";
            try fmt.format(writer, "{s} {s}", .{ the, self.displayName() });
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

        fov.rayCast(self.coord, vision, energy, Dungeon.tileOpacity, &self.fov, direction, self == state.player);

        for (self.fov) |row, y| for (row) |_, x| {
            if (self.fov[y][x] > 0) {
                const fc = Coord.new2(self.coord.z, x, y);
                const light = state.dungeon.lightAt(fc).*;

                // If a tile is too dim to be seen by a mob and the tile isn't
                // adjacent to that mob, mark it as unlit.
                if (fc.distance(self.coord) > 1 and
                    (!light_needs[@boolToInt(light)] or is_blinded))
                {
                    self.fov[y][x] = 0;
                    continue;
                }
            }
        };
    }

    // Misc stuff.
    pub fn tick_env(self: *Mob) void {
        self.push_flag = false;
        self.MP = math.clamp(self.MP + 1, 0, self.max_MP);

        const gases = state.dungeon.atGas(self.coord);
        for (gases) |quantity, gasi| {
            if ((rng.range(usize, 0, 100) < self.resistance(.rFume) or gas.Gases[gasi].not_breathed) and quantity > 0.0) {
                gas.Gases[gasi].trigger(self, quantity);
            }
        }

        // Corruption effects
        if (self.life_type == .Living and self.isUnderStatus(.Corruption) == null) {
            for (&DIRECTIONS) |d| if (self.coord.move(d, state.mapgeometry)) |neighbor| {
                if (state.dungeon.at(neighbor).mob) |mob|
                    if (mob.life_type == .Undead and mob.isHostileTo(self) and
                        rng.percent(@as(usize, 10)))
                    {
                        if (state.player.cansee(self.coord)) {
                            state.message(.Combat, "{c} corrupts {}!", .{ mob, self });
                        }
                        self.addStatus(.Corruption, 0, .{ .Tmp = 7 });
                        ai.updateEnemyKnowledge(mob, self, null);
                        break;
                    };
            };
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
            // (See surfaces.Terrain.)
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
                    state.chardata.time_with_statuses.getPtr(status_e).* += 1;
                }

                switch (status_e) {
                    .Corruption => Status.tickCorruption(self),
                    .Noisy => Status.tickNoisy(self),
                    .Echolocation => Status.tickEcholocation(self),
                    .Recuperate => Status.tickRecuperate(self),
                    .Poison => Status.tickPoison(self),
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
                else => {},
            }
        }
        self.inventory.equipment(slot).* = item;
    }

    pub fn dequipItem(self: *Mob, slot: Inventory.EquSlot, drop_coord: ?Coord) void {
        const item = self.inventory.equipment(slot).*.?;
        if (slot != .Backup) {
            switch (item) {
                .Weapon => |w| for (w.equip_effects) |effect| {
                    if (self.isUnderStatus(effect.status)) |effect_info| {
                        if (effect_info.duration == .Equ) {
                            self.cancelStatus(effect.status);
                        }
                    }
                },
                else => {},
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

            _ = self.rest();
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
                .lethal = false,
                .amount = @intToFloat(f64, d.amount),
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
            .Custom => |c| if (direct) c(self, self.coord),
        };
    }

    pub fn evokeOrRest(self: *Mob, evocable: *Evocable) void {
        evocable.evoke(self) catch {
            _ = self.rest();
            return;
        };

        self.declareAction(.Use);
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
        display.Animation.apply(.{ .TraverseLine = .{
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
                        mob.takeDamage(.{ .amount = @intToFloat(f64, damage), .source = .RangedAttack, .by_mob = self }, .{ .noun = msg_noun.constSlice() });
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
        self.energy -= @divTrunc(self.stat(.Speed) * @intCast(isize, action.cost()), 100);
    }

    pub fn makeNoise(self: *Mob, s_type: SoundType, intensity: SoundIntensity) void {
        assert(!self.is_dead);

        state.dungeon.soundAt(self.coord).* = .{
            .mob_source = self,
            .intensity = intensity,
            .type = s_type,
            .state = .New,
            .when = state.ticks,
        };

        sound.announceSound(self.coord);
    }

    // Check if a mob, when trying to move into a space that already has a mob,
    // can swap with that other mob.
    //
    pub fn canSwapWith(self: *const Mob, other: *Mob, _: ?Direction) bool {
        return other != state.player and
            (!other.isHostileTo(self) or self.hasStatus(.Shove)) and
            !other.immobile and
            (other.prisoner_status == null or other.prisoner_status.?.held_by == null) and
            (other.hasStatus(.Paralysis) or
            !other.push_flag);
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
            if (!self.moveInDirection(d)) _ = self.rest();
        } else _ = self.rest();

        assert(prev_energy > self.energy);
    }

    // Try to move a mob.
    pub fn moveInDirection(self: *Mob, p_direction: Direction) bool {
        const coord = self.coord;
        var direction = p_direction;

        // This should have been handled elsewhere (in the pathfinding code
        // for monsters, or in main:moveOrFight() for the player).
        //
        if (direction.is_diagonal() and self.isUnderStatus(.Confusion) != null)
            err.bug("Confused mob is trying to move diagonally!", .{});

        if (self.isUnderStatus(.Drunk)) |_| {
            if (rng.percent(@as(usize, 60))) {
                var adjacents = Direction.adjacentDirectionsTo(direction);
                rng.shuffle(Direction, &adjacents);

                if (coord.move(adjacents[0], state.mapgeometry)) |candidate|
                    if (state.is_walkable(candidate, .{ .mob = self })) {
                        direction = adjacents[0];
                    };
                if (coord.move(adjacents[1], state.mapgeometry)) |candidate|
                    if (state.is_walkable(candidate, .{ .mob = self })) {
                        direction = adjacents[1];
                    };
            }
        }

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
            succeeded = self.teleportTo(dest, direction, false);
        } else {
            succeeded = false;
        }

        if (!succeeded and self.isUnderStatus(.Daze) != null) {
            if (self == state.player) {
                state.message(.Info, "You stumble around in a daze.", .{});
            } else if (state.player.cansee(self.coord)) {
                state.message(.Info, "The {s} stumbles around in a daze.", .{self.displayName()});
            }

            _ = self.rest();
            return true;
        } else return succeeded;
    }

    pub fn teleportTo(self: *Mob, dest: Coord, direction: ?Direction, instant: bool) bool {
        assert(!self.immobile);

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
                    .Stair => |s| if (self == state.player) {
                        if (s) |floor| {
                            return player.triggerStair(dest, floor);
                        } else {
                            display.drawAlertThenLog("It's suicide to go back!", .{});
                        }
                    },
                    else => {},
                }
            }

            return false;
        }

        if (!instant) {
            if (direction) |d| {
                self.declareAction(Activity{ .Move = d });
            } else {
                self.declareAction(Activity{ .Teleport = dest });
            }
        }

        if (state.dungeon.at(dest).mob) |other| {
            if (!self.canSwapWith(other, direction)) return false;
            self.coord = dest;
            state.dungeon.at(dest).mob = self;
            other.coord = coord;
            state.dungeon.at(coord).mob = other;

            other.push_flag = true;
            self.push_flag = true;
        } else {
            self.coord = dest;
            state.dungeon.at(dest).mob = self;
            state.dungeon.at(coord).mob = null;
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

    pub fn rest(self: *Mob) bool {
        self.declareAction(.Rest);
        return true;
    }

    pub fn listOfWeapons(self: *Mob) StackBuffer(*const Weapon, 7) {
        var buf = StackBuffer(*const Weapon, 7).init(null);

        buf.append(if (self.inventory.equipment(.Weapon).*) |w| w.Weapon else self.species.default_attack) catch err.wat();

        for (self.species.aux_attacks) |w|
            buf.append(w) catch err.wat();

        return buf;
    }

    pub fn canMelee(attacker: *Mob, defender: *Mob) bool {
        const weapons = attacker.listOfWeapons();
        const distance = attacker.coord.distance(defender.coord);

        return for (weapons.constSlice()) |weapon| {
            if (weapon.reach >= distance and
                utils.hasClearLOF(attacker.coord, defender.coord))
            {
                break true;
            }
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
        const wielded_wp = if (attacker.inventory.equipment(.Weapon).*) |w| w.Weapon else null;

        var longest_delay: usize = 0;
        for (weapons.constSlice()) |weapon| {
            // recipient could be out of reach, either because the attacker has
            // multiple attacks and only one of them reaches, or because the
            // previous attack knocked the defender backwards
            if (weapon.reach < attacker.coord.distance(recipient.coord))
                continue;

            if (weapon.delay > longest_delay) longest_delay = weapon.delay;
            _fightWithWeapon(
                attacker,
                recipient,
                weapon,
                if (wielded_wp != null and wielded_wp.? == weapon) wielded_wp else null,
                opts,
                if (weapon.martial) martial else 0,
            );
        }

        // If longest_delay is still 0, we didn't attack at all!
        assert(longest_delay > 0);

        if (!opts.free_attack) {
            const d = attacker.coord.closestDirectionTo(recipient.coord, state.mapgeometry);
            attacker.declareAction(.{ .Attack = .{ .who = recipient, .coord = recipient.coord, .direction = d, .delay = longest_delay } });
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
        mut_attacker_weapon: ?*Weapon, // XXX: hack, because not all weapons are mutable
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

        const hit = opts.auto_hit or (!missed and !evaded);

        if (!hit) {
            if (state.player.cansee(attacker.coord) or state.player.cansee(recipient.coord)) {
                if (missed) {
                    const verb = if (attacker == state.player) "miss" else "misses";
                    state.message(.CombatUnimportant, "{c} {s} {}.", .{
                        attacker, verb, recipient,
                    });
                    display.Animation.blink(&.{recipient.coord}, '/', colors.LIGHT_STEEL_BLUE, .{}).apply();
                } else if (evaded) {
                    const verb = if (recipient == state.player) "evade" else "evades";
                    state.message(.CombatUnimportant, "{c} {s} {}.", .{
                        recipient, verb, attacker,
                    });
                    display.Animation.blink(&.{recipient.coord}, ')', colors.LIGHT_STEEL_BLUE, .{}).apply();
                }
            }

            if (recipient.isUnderStatus(.Riposte)) |_| {
                if (recipient.canMelee(attacker)) {
                    display.Animation.blink(&.{recipient.coord}, 'R', colors.LIGHT_STEEL_BLUE, .{}).apply();
                    recipient.fight(attacker, .{ .free_attack = true, .is_riposte = true });
                }
            }
            return;
        }

        const is_stab = !opts.disallow_stab and combat.isAttackStab(attacker, recipient) and !opts.is_bonus;
        const weapon_damage = combat.damageOfWeapon(attacker, attacker_weapon, recipient);
        const damage = combat.damageOfMeleeAttack(attacker, weapon_damage.total, is_stab) * opts.damage_bonus / 100;

        recipient.takeDamage(.{
            .amount = @intToFloat(f64, damage),
            .kind = attacker_weapon.damage_kind,
            .source = if (is_stab) .Stab else .MeleeAttack,
            .by_mob = attacker,
        }, .{
            .strs = attacker_weapon.strs,
            .is_bonus = opts.is_bonus,
            .is_riposte = opts.is_riposte,
            .is_bone = weapon_damage.bone_bonus,
            .is_nbone = weapon_damage.bone_nbonus,
            .is_copper = weapon_damage.copper_bonus,
        });

        // XXX: should this be .Loud instead of .Medium?
        if (!is_stab) {
            attacker.makeNoise(.Combat, opts.loudness);
        }

        for (attacker_weapon.effects) |effect| {
            recipient.applyStatus(effect, .{});
        }

        // Apply weapon dipping effects.
        if (attacker_weapon.dip_effect) |potion| {
            assert(attacker_weapon.dip_counter > 0);
            assert(mut_attacker_weapon != null);

            if (rng.percent(combat.CHANCE_FOR_DIP_EFFECT)) {
                recipient.applyStatus(potion.dip_effect.?, .{});
                mut_attacker_weapon.?.dip_counter -= 1;

                if (attacker_weapon.dip_counter == 0) {
                    mut_attacker_weapon.?.dip_effect = null;
                }
            }
        }

        if (attacker_weapon.knockback > 0) {
            const d = attacker.coord.closestDirectionTo(recipient.coord, state.mapgeometry);
            combat.throwMob(attacker, recipient, d, attacker_weapon.knockback);
        }

        // Daze stabbed mobs.
        if (is_stab and !recipient.should_be_dead()) {
            recipient.addStatus(.Daze, 0, .{ .Tmp = rng.range(usize, 3, 5) });
        }

        // Bonus attacks?
        if (!is_stab and remaining_bonus_attacks > 0 and !recipient.should_be_dead()) {
            var newopts = opts;
            newopts.auto_hit = false;
            newopts.damage_bonus = 100;
            newopts.is_bonus = true;

            display.Animation.blink(&.{attacker.coord}, 'M', colors.LIGHT_STEEL_BLUE, .{}).apply();

            _fightWithWeapon(
                attacker,
                recipient,
                attacker_weapon,
                mut_attacker_weapon,
                newopts,
                remaining_bonus_attacks - 1,
            );
        }
    }

    pub fn takeHealing(self: *Mob, h: usize) void {
        self.HP = math.clamp(self.HP + @intToFloat(f64, h), 0, self.max_HP);

        const verb: []const u8 = if (self == state.player) "are" else "is";
        const fully_adj: []const u8 = if (self.HP == self.max_HP) "fully " else "";
        const punc: []const u8 = if (self.HP == self.max_HP) "!" else ".";
        state.message(.Info, "{c} {s} {s}healed{s} $g($c{}$g HP)", .{ self, verb, fully_adj, punc, h });
    }

    pub fn takeDamage(self: *Mob, d: Damage, msg: struct {
        basic: bool = false,
        noun: ?[]const u8 = null,
        strs: []const DamageStr = &[_]DamageStr{
            items._dmgstr(000, "hit", "hits", ""),
        },
        is_bonus: bool = false,
        is_riposte: bool = false,
        is_bone: bool = false,
        is_nbone: bool = false,
        is_copper: bool = false,
    }) void {
        const was_already_dead = self.should_be_dead();
        const old_HP = self.HP;

        const resist = self.resistance(d.kind.resist());
        const unshaved_amount = combat.shaveDamage(d.amount, resist);
        const amount = if (!d.lethal and unshaved_amount > self.HP - 1)
            self.HP - 1
        else
            unshaved_amount;
        const dmg_percent = @floatToInt(usize, amount * 100 / math.max(1, self.HP));

        self.HP = math.clamp(self.HP - amount, 0, self.max_HP);

        // Inform defender of attacker
        //
        // We already do this in fight() for missed attacks, but this takes
        // care of ranged combat, spell damage, etc.
        if (d.by_mob) |attacker| {
            ai.updateEnemyKnowledge(self, attacker, null);
        }

        // Make animations
        const clamped_dmg = math.clamp(@floatToInt(u21, amount), 0, 9);
        const damage_char = if (self.should_be_dead()) '∞' else '0' + clamped_dmg;
        display.Animation.blink(&.{self.coord}, damage_char, colors.PALE_VIOLET_RED, .{}).apply();

        // Print message
        if (state.player.cansee(self.coord) or (d.by_mob != null and state.player.cansee(d.by_mob.?.coord))) {
            var punctuation: []const u8 = ".";
            if (dmg_percent >= 20) punctuation = "!";
            if (dmg_percent >= 40) punctuation = "!!";
            if (dmg_percent >= 60) punctuation = "!!!";
            if (dmg_percent >= 80) punctuation = "!!!!";

            var hitstrs = msg.strs[msg.strs.len - 1];
            // FIXME: insert some randomization here. Currently every single stab
            // the player makes results in "You puncture the XXX like a sieve!!!!"
            // which gets boring after a bit.
            {
                for (msg.strs) |strset| {
                    if (strset.dmg_percent > dmg_percent) {
                        hitstrs = strset;
                        break;
                    }
                }
            }

            const resisted = @floatToInt(isize, d.amount - amount);
            const resist_str = if (d.kind == .Physical) "armor" else "resist";

            if (msg.basic) {
                const basic_helper_verb: []const u8 = if (self == state.player) "are" else "is";
                const basic_verb = switch (d.kind) {
                    .Physical => "damaged",
                    .Fire => "burnt with fire",
                    .Electric => "electrocuted",
                    .Poison => "weakened",
                };

                state.message(
                    .Combat,
                    "{c} {s} {s}{s} $g($r{}$. $g{s}$g, $c{}$. $g{s}$.)",
                    .{
                        self,        basic_helper_verb,          basic_verb,
                        punctuation, @floatToInt(usize, amount), d.kind.string(),
                        resisted,    resist_str,
                    },
                );
            } else {
                const martial_str = if (msg.is_bonus) " $b*Martial*$. " else "";
                const riposte_str = if (msg.is_riposte) " $b*Riposte*$. " else "";
                const bone_str = if (msg.is_bone) " $b*Bone*$. " else "";
                const nbone_str = if (msg.is_nbone) " $b*-Bone*$. " else "";
                const copper_str = if (msg.is_copper) " $b*Copper*$. " else "";

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
                    "{s} {s} {}{s}{s} $g($r{}$. $g{s}$g, $c{}$. $g{s}$.) {s}{s}{s}{s}{s}",
                    .{
                        noun.constSlice(),   verb,        self,
                        hitstrs.verb_degree, punctuation, @floatToInt(usize, amount),
                        d.kind.string(),     resisted,    resist_str,
                        martial_str,         riposte_str, bone_str,
                        nbone_str,           copper_str,
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
                        if (m.isUnderStatus(.Conductive) != null)
                            return true;
                    return false;
                }
            };

            var membuf: [4096]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

            var dijk = dijkstra.Dijkstra.init(self.coord, state.mapgeometry, 9, S.isConductive, .{}, fba.allocator());
            defer dijk.deinit();

            while (dijk.next()) |child| {
                const mob = state.dungeon.at(child).mob.?;
                if (mob == self) continue;

                const damage_percent = 10 - child.distance(self.coord);
                const damage = d.amount * @intToFloat(f64, damage_percent) / 100.0;

                mob.takeDamage(.{
                    .amount = damage,
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
                state.chardata.foes_killed_total += 1;
                if (d.source == .Stab) state.chardata.foes_stabbed += 1;

                const prevtotal = (state.chardata.foes_killed.getOrPutValue(self.displayName(), 0) catch err.wat()).value_ptr.*;
                state.chardata.foes_killed.put(self.displayName(), prevtotal + 1) catch err.wat();
            }
        }

        // Should we give the mob its flee-effect?
        //
        // FIXME: this probably shouldn't be handled here.
        if (self.HP > 0 and
            self.isUnderStatus(.Exhausted) == null and
            self.lastDamagePercentage() >= 50 or
            (self.HP <= (self.max_HP / 10) and old_HP > (self.max_HP / 10)))
        {
            if (self.ai.flee_effect) |s| {
                if (self.isUnderStatus(s.status) == null) {
                    self.applyStatus(s, .{});
                }
            }
        }
    }

    pub fn init(self: *Mob, alloc: mem.Allocator) void {
        self.HP = self.max_HP;
        self.MP = self.max_MP;
        self.enemies = EnemyRecord.AList.init(alloc);
        self.allies = MobArrayList.init(alloc);
        self.sustiles = std.ArrayList(SuspiciousTileRecord).init(alloc);
        self.activities.init();
        self.path_cache = std.AutoHashMap(Path, Coord).init(alloc);
        self.ai.work_area = CoordArrayList.init(alloc);
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
        self.allegiance = .Necromancer;

        self.stats.Speed += 10;
        self.stats.Evade -= 10;
        self.stats.Willpower -= 2;
        self.stats.Vision = 4;

        self.memory_duration = 4;
        self.deaf = true;

        self.innate_resists.rFire = math.clamp(self.innate_resists.rFire - 25, -100, 100);
        self.innate_resists.rElec = math.clamp(self.innate_resists.rElec - 25, -100, 100);
        self.innate_resists.rFume = 100;

        return true;
    }

    pub fn kill(self: *Mob) void {
        if (self != state.player) {
            if (self.killed_by) |by_mob| {
                if (by_mob == state.player) {
                    state.message(.Damage, "You slew the {s}.", .{self.displayName()});
                } else if (state.player.cansee(by_mob.coord)) {
                    state.message(.Damage, "The {s} killed the {s}.", .{ by_mob.displayName(), self.displayName() });
                }
            } else {
                if (state.player.cansee(self.coord)) {
                    state.message(.Damage, "The {s} dies.", .{self.displayName()});
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

        self.enemies.deinit();
        self.allies.deinit();
        self.sustiles.deinit();
        self.path_cache.clearAndFree();
        self.ai.work_area.deinit();

        self.is_dead = true;
        state.dungeon.at(self.coord).mob = null;

        if (self.corpse != .None) {
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
                    .Normal => state.dungeon.at(c).surface = .{ .Corpse = self },
                    .Wall => state.dungeon.at(c).type = .Wall,
                }
            }
        }
    }

    pub fn should_be_dead(self: *const Mob) bool {
        return self.HP == 0;
    }

    pub fn nextDirectionTo(self: *Mob, to: Coord) ?Direction {
        // FIXME: make this an assertion; no mob should ever be trying to path to
        // themself.
        if (self.coord.eq(to)) return null;

        const is_confused = self.isUnderStatus(.Confusion) != null;

        // Cannot move if you're a prisoner (unless you're moving one space away)
        if (self.prisoner_status) |p|
            if (p.held_by != null and p.heldAt().distance(to) > 1)
                return null;

        if (!is_confused) {
            if (Direction.from(self.coord, to)) |direction| {
                return direction;
            }
        }

        const pathobj = Path{ .from = self.coord, .to = to, .confused_state = is_confused };

        if (!self.path_cache.contains(pathobj)) {
            const directions = b: {
                if (is_confused) {
                    break :b &CARDINAL_DIRECTIONS;
                } else {
                    if (self.ai.flag(.MovesDiagonally)) {
                        break :b &DIAGONAL_DIRECTIONS;
                    } else {
                        break :b &DIRECTIONS;
                    }
                }
            };

            const pth = astar.path(self.coord, to, state.mapgeometry, state.is_walkable, .{ .mob = self }, directions, state.GPA.allocator()) orelse return null;
            defer pth.deinit();

            assert(pth.items[0].eq(self.coord));

            var last: Coord = self.coord;
            for (pth.items[1..]) |coord| {
                self.path_cache.put(
                    Path{ .from = last, .to = to, .confused_state = is_confused },
                    coord,
                ) catch err.wat();
                last = coord;
            }
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
        self.applyStatus(.{ .status = s, .duration = .{ .Tmp = 0 } }, .{
            .add_duration = false,
            .replace_duration = true,
        });
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

        var msg_parts: ?[3][]const u8 = null;

        if (had_status_before and !has_status_now) {
            msg_parts = s.status.messageWhenRemoved();

            if (was_exhausting or s.exhausting)
                self.addStatus(.Exhausted, 0, .{ .Tmp = Status.MAX_DURATION });

            if (p_se.status == .Lifespan) {
                self.HP = 0;
            }
        } else if (!had_status_before and has_status_now) {
            msg_parts = s.status.messageWhenAdded();
        }

        if (meta.activeTag(p_se.duration) == .Tmp and msg_parts != null) {
            if (self == state.player) {
                state.message(.Status, "You {s}{s}.", .{ msg_parts.?[0], msg_parts.?[2] });
            } else if (state.player.cansee(self.coord)) {
                state.message(.Status, "The {s} {s}{s}.", .{
                    self.displayName(), msg_parts.?[1], msg_parts.?[2],
                });
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
        if (self.last_damage) |dam| {
            return @floatToInt(usize, (dam.amount * 100) / self.max_HP);
        } else {
            return 0;
        }
    }

    pub fn canHear(self: *const Mob, coord: Coord) ?*Sound {
        if (self.deaf) return null;

        const noise = state.dungeon.soundAt(coord);

        if (self.coord.z != coord.z)
            return null; // Can't hear across levels

        if (noise.state == .Dead or noise.intensity == .Silent)
            return null; // Sound was made a while back, or is silent

        const line = self.coord.drawLine(coord, state.mapgeometry, 0);
        var walls_in_way: usize = 0;
        for (line.constSlice()) |c| {
            if (state.dungeon.at(c).type == .Wall) {
                walls_in_way += 1;
            }
        }

        // If there are a lot of walls in the way, quiet the noise
        var radius = noise.intensity.radiusHeard();
        if (self != state.player) radius -|= walls_in_way;
        if (self == state.player) radius = radius * 150 / 100;

        if (self.coord.distance(coord) > radius)
            return null; // Too far away

        return noise;
    }

    pub fn isHostileTo(self: *const Mob, othermob: *const Mob) bool {
        var hostile = false;

        if (self.allegiance != othermob.allegiance) hostile = true;

        // If the other mob is a prisoner of my faction (and is actually in
        // prison) or we're both prisoners of the same faction, don't be hostile.
        if (othermob.prisoner_status) |ps| {
            if (ps.of == self.allegiance and
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

        return hostile;
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
            if (self.isUnderStatus(.NightVision) != null) return true;
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
                if (self.isUnderStatus(.Enraged)) |_| val = @divTrunc(val * 80, 100);
                if (self.isUnderStatus(.Slow)) |_| val = @divTrunc(val * 150, 100);
                if (self.isUnderStatus(.Poison)) |_| val = @divTrunc(val * 150, 100);
            },
            .Willpower => {
                if (self.isUnderStatus(.Corruption)) |_| val -|= 2;
            },
            else => {},
        }

        // Check weapons.
        if (self.inventory.equipmentConst(.Weapon).*) |weapon| {
            val += utils.getFieldByEnum(Stat, weapon.Weapon.stats, _stat);
        }

        // Check armor and cloaks.
        if (self.inventory.equipmentConst(.Cloak).*) |clk|
            val += utils.getFieldByEnum(Stat, clk.Cloak.stats, _stat);
        if (self.inventory.equipmentConst(.Armor).*) |clk|
            val += utils.getFieldByEnum(Stat, clk.Armor.stats, _stat);

        // Check rings.
        for (Inventory.RING_SLOTS) |ring_slot|
            if (self.inventory.equipmentConst(ring_slot).*) |ring| {
                val += utils.getFieldByEnum(Stat, ring.Ring.stats, _stat);
            };

        // Clamp value.
        val = switch (_stat) {
            .Sneak => math.clamp(val, 0, 10),
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
        if (self.inventory.equipmentConst(.Armor).*) |arm|
            r += utils.getFieldByEnum(Resistance, arm.Armor.resists, resist);

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

        const rings = [_]Inventory.EquSlot{ .Ring1, .Ring2, .Ring3, .Ring4 };
        for (rings) |r| if (self.inventory.equipment(r).*) |ring_item|
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
    pub fn enemyList(self: *Mob) *EnemyRecord.AList {
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

    powered_fg: ?u32 = null,
    unpowered_fg: ?u32 = null,
    powered_bg: ?u32 = null,
    unpowered_bg: ?u32 = null,
    bg: ?u32 = null,

    power_drain: usize = 100, // Power drained per turn

    restricted_to: ?Allegiance = null,
    powered_walkable: bool = true,
    unpowered_walkable: bool = true,

    powered_opacity: f64 = 0.0,
    unpowered_opacity: f64 = 0.0,

    powered_luminescence: usize = 0,
    unpowered_luminescence: usize = 0,
    dims: bool = false,

    porous: bool = false,
    flammability: usize = 0,

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
        success_msg: []const u8,
        no_effect_msg: ?[]const u8,
        needs_power: bool = true,
        used: usize = 0,
        max_use: usize, // 0 for infinite uses
        func: fn (*Machine, *Mob) bool,
    };

    pub fn canBeInteracted(self: *Machine, mob: *Mob, interaction: *const MachInteract) bool {
        _ = mob;
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

    pub fn addPower(self: *Machine, by: *Mob) bool {
        if (self.restricted_to) |restriction|
            if (restriction != by.allegiance) return false;

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
                        if (mob.allegiance == .Necromancer) return;

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
        Weapons, // Weapons
        VOres, // Useless. Vial ores
        Utility, // Useless. Depends on the level (for PRI: rope, chains, etc).
    };

    pub fn isLootable(self: *const Container) bool {
        return self.type == .Weapons and self.items.len > 0;
    }
};

pub const SurfaceItemTag = enum { Corpse, Machine, Prop, Container, Poster, Stair };
pub const SurfaceItem = union(SurfaceItemTag) {
    Corpse: *Mob,
    Machine: *Machine,
    Prop: *Prop,
    Container: *Container,
    Poster: *const Poster,
    Stair: ?Coord, // null = downstairs

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
};

pub const Weapon = struct {
    // linked list stuff
    __next: ?*Weapon = null,
    __prev: ?*Weapon = null,

    id: []const u8 = "",
    name: []const u8 = "",

    reach: usize = 1,
    delay: usize = 100, // Percentage (100 = normal speed, 200 = twice as slow)
    damage: usize,
    damage_kind: Damage.DamageKind = .Physical,
    knockback: usize = 0,
    martial: bool = false,
    ego: Ego = .None,

    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    effects: []const StatusDataInfo = &[_]StatusDataInfo{},
    equip_effects: []const StatusDataInfo = &[_]StatusDataInfo{},

    is_dippable: bool = false,
    dip_effect: ?*const Consumable = null,
    dip_counter: usize = 0,

    strs: []const DamageStr,

    pub const Ego = enum { None, Bone, Copper };

    pub fn createBoneWeapon(comptime weapon: *const Weapon, opts: struct {}) Weapon {
        _ = opts;
        var new = weapon.*;
        new.id = "bone_" ++ weapon.id;
        new.name = "bone " ++ weapon.name;
        new.ego = .Bone;
        new.stats.Willpower -= 2;
        return new;
    }

    pub fn createCopperWeapon(comptime weapon: *const Weapon, opts: struct {}) Weapon {
        _ = opts;
        var new = weapon.*;
        new.id = "copper_" ++ weapon.id;
        new.name = "copper " ++ weapon.name;
        new.ego = .Copper;
        new.damage_kind = .Electric;
        new.damage -= 1;
        return new;
    }
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
    pattern_checker: PatternChecker,
    effect: fn (*Mob, PatternChecker.State) void,

    activated: bool = false,
};

pub const ItemType = enum { Rune, Ring, Consumable, Vial, Projectile, Armor, Cloak, Weapon, Boulder, Prop, Evocable };

pub const Item = union(ItemType) {
    Rune: Rune,
    Ring: *Ring,
    Consumable: *const Consumable,
    Vial: Vial,
    Projectile: *const Projectile,
    Armor: *Armor,
    Cloak: *const Cloak,
    Weapon: *Weapon,
    Boulder: *const Material,
    Prop: *const Prop,
    Evocable: *Evocable,

    // Should we announce the item to the player when we find it?
    pub fn announce(self: Item) bool {
        return switch (self) {
            .Vial, .Boulder, .Prop => false,
            .Rune, .Projectile, .Cloak, .Ring, .Consumable, .Armor, .Weapon, .Evocable => true,
        };
    }

    pub fn tile(self: Item) termbox.tb_cell {
        var cell = termbox.tb_cell{ .fg = 0xffffff, .bg = colors.BG, .ch = ' ' };

        switch (self) {
            .Rune => |_| {
                cell.ch = 'ß';
                cell.fg = colors.AQUAMARINE;
            },
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
            .Rune => |r| try fmt.format(fbs.writer(), "ß{s}", .{r.name()}),
            .Ring => |r| try fmt.format(fbs.writer(), "*{s}", .{r.name}),
            .Consumable => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Vial => |v| try fmt.format(fbs.writer(), "♪{s}", .{v.name()}),
            .Projectile => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Armor => |a| try fmt.format(fbs.writer(), "]{s}", .{a.name}),
            .Cloak => |c| try fmt.format(fbs.writer(), "clk of {s}", .{c.name}),
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
            .Rune => |r| try fmt.format(fbs.writer(), "{s} Rune", .{r.name()}),
            .Ring => |r| try fmt.format(fbs.writer(), "ring of {s}", .{r.name}),
            .Consumable => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Vial => |v| try fmt.format(fbs.writer(), "vial of {s}", .{v.name()}),
            .Projectile => |p| try fmt.format(fbs.writer(), "{s}", .{p.name}),
            .Armor => |a| try fmt.format(fbs.writer(), "{s} armor", .{a.name}),
            .Cloak => |c| try fmt.format(fbs.writer(), "cloak of {s}", .{c.name}),
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
            .Weapon => |w| w.id,
            .Prop => |p| p.id,
            .Evocable => |v| v.id,
            .Ring => |r| r.name,
            .Rune => "AMBIG_rune",
            .Vial, .Boulder => null,
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

    pub fn displayAs(coord: Coord, ignore_lights: bool, ignore_mobs: bool) termbox.tb_cell {
        var self = state.dungeon.at(coord);
        var cell = termbox.tb_cell{};

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
            },
            .Floor => {
                cell.ch = self.terrain.tile;
                cell.fg = self.terrain.color;
                cell.bg = colors.BG;
            },
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
                cell.fg = 0xb0c4de;

            const hp_loss_percent = 100 - (mob.HP * 100 / mob.max_HP);
            if (hp_loss_percent > 0) {
                //const red = @floatToInt(u32, (255 * (hp_loss_percent / 2)) / 100) + 0x22;
                //cell.bg = math.clamp(red, 0x66, 0xff) << 16;
            }

            if (mob.prisoner_status) |ps| {
                if (state.dungeon.at(coord).prison or ps.held_by != null) {
                    cell.fg = 0xffcfff;
                }
            }

            cell.ch = mob.tile;
        } else if (state.dungeon.fireAt(coord).* > 0) {
            const famount = state.dungeon.fireAt(coord).*;
            cell.ch = fire.fireGlyph(famount);
            cell.fg = fire.fireColor(famount);
        } else if (state.dungeon.itemsAt(coord).last()) |item| {
            assert(self.type != .Wall);
            cell = item.tile();
        } else if (state.dungeon.at(coord).surface) |surfaceitem| {
            if (self.type == .Wall) {
                cell.fg = 0;
                cell.bg = 0xff0000;
                cell.ch = 'X';
                return cell;
            }
            //assert(self.type != .Wall);

            cell.fg = 0xffffff;

            const ch: u21 = switch (surfaceitem) {
                .Corpse => |_| c: {
                    cell.fg = 0xffe0ef;
                    break :c '%';
                },
                .Container => |c| cont: {
                    // if (c.capacity >= 14) {
                    //     cell.fg = 0x000000;
                    //     cell.bg = 0x808000;
                    // }
                    cell.fg = if (c.isLootable()) colors.GOLD else colors.GREY;
                    break :cont c.tile;
                },
                .Machine => |m| mach: {
                    if (m.isPowered()) {
                        if (m.powered_bg) |mach_bg| cell.bg = mach_bg;
                        if (m.powered_fg) |mach_fg| cell.fg = mach_fg;
                    } else {
                        if (m.unpowered_bg) |mach_bg| cell.bg = mach_bg;
                        if (m.unpowered_fg) |mach_fg| cell.fg = mach_fg;
                    }
                    if (m.bg) |bg| cell.bg = bg;

                    break :mach m.tile();
                },
                .Prop => |p| prop: {
                    if (p.bg) |prop_bg| cell.bg = prop_bg;
                    if (p.fg) |prop_fg| cell.fg = prop_fg;
                    break :prop p.tile;
                },
                .Poster => |_| poster: {
                    cell.fg = self.material.color_bg orelse self.material.color_fg;
                    break :poster '?';
                },
                .Stair => |s| stair: {
                    var ch: u21 = '.';
                    if (s == null) {
                        ch = '>';
                        cell.fg = 0xeeeeee;
                        cell.bg = 0x0000ff;
                    } else {
                        ch = if (state.levelinfo[s.?.z].optional) '≤' else '<';
                        cell.bg = 0x997700;
                        cell.fg = 0xffd700;
                    }
                    break :stair ch;
                },
            };

            cell.ch = ch;
        }

        if (!ignore_lights and self.type == .Floor) {
            if (!state.dungeon.lightAt(coord).*) {
                cell.fg = colors.percentageOf(cell.fg, 60);
            }
        }

        var spattering = self.spatter.iterator();
        while (spattering.next()) |entry| {
            const spatter = entry.key;
            const num = entry.value.*;
            const sp_color = spatter.color();
            const q = @intToFloat(f64, num / 10);
            const aq = 1 - math.clamp(q, 0.19, 0.40);
            if (num > 0) cell.bg = colors.mix(sp_color, cell.bg, aq);
        }

        const gases = state.dungeon.atGas(coord);
        for (gases) |q, g| {
            const gcolor = gas.Gases[g].color;
            const aq = 1 - math.clamp(q, 0.19, 1);
            if (q > 0) cell.bg = colors.mix(gcolor, cell.bg, aq);
        }

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

    pub const ItemBuffer = StackBuffer(Item, 4);
    pub const StairBuffer = StackBuffer(Coord, MAX_STAIRS);

    pub const MAX_STAIRS: usize = 2;

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
