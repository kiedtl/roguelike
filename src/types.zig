const std = @import("std");
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const assert = std.debug.assert;
const enums = @import("std/enums.zig");

const LinkedList = @import("list.zig").LinkedList;
const RingBuffer = @import("ringbuffer.zig").RingBuffer;
const StackBuffer = @import("buffer.zig").StackBuffer;

const fov = @import("fov.zig");
const heat = @import("heat.zig");
const combat = @import("combat.zig");
const spells = @import("spells.zig");
const rng = @import("rng.zig");
const dijkstra = @import("dijkstra.zig");
const display = @import("display.zig");
const mapgen = @import("mapgen.zig");
const termbox = @import("termbox.zig");
const astar = @import("astar.zig");
const materials = @import("materials.zig");
const items = @import("items.zig");
const gas = @import("gas.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
const literature = @import("literature.zig");
const ai = @import("ai.zig");

const SpellInfo = spells.SpellInfo;
const Spell = spells.Spell;
const Poster = literature.Poster;

pub const HEIGHT = 40;
pub const WIDTH = 100;
pub const LEVELS = 7;
pub const PLAYER_STARTING_LEVEL = 5; // TODO: define in data file

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const DirectionArrayList = std.ArrayList(Direction);
pub const CoordCellMap = std.AutoHashMap(Coord, termbox.tb_cell);
pub const CoordArrayList = std.ArrayList(Coord);
pub const AnnotatedCoordArrayList = std.ArrayList(AnnotatedCoord);
pub const RoomArrayList = std.ArrayList(Room);
pub const StockpileArrayList = std.ArrayList(Stockpile);
pub const MessageArrayList = std.ArrayList(Message);
pub const StatusArray = enums.EnumArray(Status, StatusData);
pub const SpatterArray = enums.EnumArray(Spatter, usize);
pub const MobList = LinkedList(Mob);
pub const SobList = LinkedList(Sob);
pub const MobArrayList = std.ArrayList(*Mob); // STYLE: rename to MobPtrArrayList
pub const RingList = LinkedList(Ring);
pub const PotionList = LinkedList(Potion);
pub const ArmorList = LinkedList(Armor);
pub const WeaponList = LinkedList(Weapon);
pub const ProjectileList = LinkedList(Projectile);
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

    // FIXME: deprecated!
    pub fn from_coords(a: Coord, b: Coord) !Self {
        return if (Direction.from(a, b)) |d| d else error.NotNeighbor;
    }

    pub fn is_adjacent(base: Self, other: Self) bool {
        const adjacent: [2]Direction = switch (base) {
            .North => .{ .NorthWest, .NorthEast },
            .East => .{ .NorthEast, .SouthEast },
            .South => .{ .SouthWest, .SouthEast },
            .West => .{ .NorthWest, .SouthWest },
            .NorthWest => .{ .West, .North },
            .NorthEast => .{ .East, .North },
            .SouthWest => .{ .South, .West },
            .SouthEast => .{ .South, .East },
        };

        for (adjacent) |adj| {
            if (other == adj)
                return true;
        }
        return false;
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
            else => unreachable,
        };
    }

    pub fn turnright(self: *const Self) Self {
        return self.turnleft().opposite();
    }
}; // }}}

test "from_coords" {
    std.testing.expectEqual(Direction.from_coords(Coord.new(0, 0), Coord.new(1, 0)), .East);
}

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

    pub inline fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }

    pub inline fn add(a: Self, b: Self) Self {
        return Coord.new2(a.z, a.x + b.x, a.y + b.y);
    }

    pub inline fn asRoom(self: *const Self) Room {
        return Room{ .start = self.*, .width = 1, .height = 1 };
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
        var closest_distance: usize = 10000000000;
        var closest_direction: Direction = .North;

        for (&DIRECTIONS) |direction| if (self.move(direction, limit)) |neighbor| {
            const diff = neighbor.difference(to);
            const dist = diff.x + diff.y;

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

        buf.append(Coord.new2(z, @intCast(usize, x), @intCast(usize, y))) catch unreachable;
    }

    pub fn drawLine(from: Coord, to: Coord, limit: Coord) StackBuffer(Coord, 2048) {
        assert(from.z == to.z);

        var buf = StackBuffer(Coord, 2048).init(null);

        const xstart = @intCast(isize, from.x);
        const xend = @intCast(isize, to.x);
        const ystart = @intCast(isize, from.y);
        const yend = @intCast(isize, to.y);
        const stepx: isize = if (xstart < xend) 1 else -1;
        const stepy: isize = if (ystart < yend) 1 else -1;
        const dx = @intToFloat(f64, math.absInt(xend - xstart) catch unreachable);
        const dy = @intToFloat(f64, math.absInt(yend - ystart) catch unreachable);

        var err: f64 = 0.0;
        var x = @intCast(isize, from.x);
        var y = @intCast(isize, from.y);

        if (dx > dy) {
            err = dx / 2.0;
            while (x != xend) {
                insert_if_valid(from.z, x, y, &buf, limit);
                err -= dy;
                if (err < 0) {
                    y += stepy;
                    err += dx;
                }
                x += stepx;
            }
        } else {
            err = dy / 2.0;
            while (y != yend) {
                insert_if_valid(from.z, x, y, &buf, limit);
                err -= dx;
                if (err < 0) {
                    x += stepx;
                    err += dy;
                }
                y += stepy;
            }
        }

        return buf;
    }

    pub fn draw_circle(center: Coord, radius: usize, limit: Coord, alloc: *mem.Allocator) CoordArrayList {
        const circum = @floatToInt(usize, math.ceil(math.tau * @intToFloat(f64, radius)));

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
}; // }}}

test "coord.distance" {
    std.testing.expectEqual(Coord.new(0, 0).distance(Coord.new(0, 1)), 1);
    std.testing.expectEqual(Coord.new(0, 0).distance(Coord.new(1, 1)), 1);
    std.testing.expectEqual(Coord.new(0, 0).distance(Coord.new(0, 2)), 2);
}

test "coord.move" {
    const limit = Coord.new(9, 9);
    const c = Coord.new(0, 0);
    std.testing.expectEqual(c.move(.East, limit), Coord.new(1, 0));
}

pub const AnnotatedCoord = struct { coord: Coord, value: usize };

pub const Room = struct {
    type: RoomType = .Room,

    prefab: ?*mapgen.Prefab = null,
    has_subroom: bool = false,

    start: Coord,
    width: usize,
    height: usize,

    pub const RoomType = enum { Corridor, Room };

    pub fn add(a: *const Room, b: *const Room) Room {
        assert(b.start.z == 0);

        return .{
            .start = Coord.new2(a.start.z, a.start.x + b.start.x, a.start.y + b.start.y),
            .width = a.width,
            .height = b.width,
        };
    }

    pub fn overflowsLimit(self: *const Room, limit: *const Room) bool {
        return self.end().x >= limit.end().x or
            self.end().y >= limit.end().y or
            self.start.x < limit.start.x or
            self.start.y < limit.start.y;
    }

    pub fn end(self: *const Room) Coord {
        return Coord.new2(self.start.z, self.start.x + self.width, self.start.y + self.height);
    }

    pub fn intersects(a: *const Room, b: *const Room, padding: usize) bool {
        const a_end = a.end();
        const b_end = b.end();

        const ca = utils.saturating_sub(a.start.x, padding) < b_end.x;
        const cb = (a_end.x + padding) > b.start.x;
        const cc = utils.saturating_sub(a.start.y, padding) < b_end.y;
        const cd = (a_end.y + padding) > b.start.y;

        return ca and cb and cc and cd;
    }

    pub fn randomCoord(self: *const Room) Coord {
        const x = rng.range(usize, self.start.x, self.end().x - 1);
        const y = rng.range(usize, self.start.y, self.end().y - 1);
        return Coord.new2(self.start.z, x, y);
    }
};

pub const Stockpile = struct {
    room: Room,
    type: ItemType,

    pub fn findEmptySlot(self: *const Stockpile) ?Coord {
        var y: usize = self.room.start.y;
        while (y < self.room.end().y) : (y += 1) {
            var x: usize = self.room.start.x;
            while (x < self.room.end().x) : (x += 1) {
                const coord = Coord.new2(self.room.start.z, x, y);
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

    pub fn inferType(self: *Stockpile) bool {
        var y: usize = self.room.start.y;
        while (y < self.room.end().y) : (y += 1) {
            var x: usize = self.room.start.x;
            while (x < self.room.end().x) : (x += 1) {
                const coord = Coord.new2(self.room.start.z, x, y);

                if (state.dungeon.hasContainer(coord)) |container| {
                    if (container.items.len > 0) {
                        self.type = std.meta.activeTag(container.items.data[0]);
                        return true;
                    }
                } else {
                    const titems = state.dungeon.itemsAt(coord);

                    if (titems.len > 0) {
                        self.type = std.meta.activeTag(titems.data[0]);
                        return true;
                    }
                }
            }
        }

        return false;
    }
};

pub const Path = struct { from: Coord, to: Coord };

pub const Material = struct {
    // Name of the material. e.g. "rhyolite"
    name: []const u8,

    // Description. e.g. "A sooty, flexible material used to make fire-proof
    // cloaks."
    description: []const u8,

    // Material density in g/cm³
    density: f64,

    // Tile used to represent walls. The foreground color is used to represent
    // items made with that material.
    color_fg: u32,
    color_bg: ?u32,
    color_floor: u32,
    tileset: usize,

    // Melting point in Celsius, and combust temperature, also in Celsius.
    melting_point: usize,
    combust_point: ?usize,

    // Specific heat in kJ/(kg K)
    specific_heat: f64,

    // How much light this thing emits
    luminescence: usize,

    opacity: f64,

    pub const AIR_SPECIFIC_HEAT = 200.5;
    pub const AIR_DENSITY = 0.012;
};

pub const MessageType = union(enum) {
    MetaError,
    Info,
    Aquire,
    Move,
    Trap,
    Damage,
    SpellCast,

    pub fn color(self: MessageType) u32 {
        return switch (self) {
            .MetaError => 0xffffff,
            .Info => 0xfafefa,
            .Aquire => 0xffd700,
            .Move => 0xfafefe,
            .Trap => 0xed254d,
            .Damage => 0xed254d,
            .SpellCast => 0xff7750,
        };
    }
};

pub const Damage = struct { amount: f64 };
pub const Activity = union(enum) {
    Interact,
    Rest,
    Move: Direction,
    Attack: Coord,
    Teleport: Coord,
    Grab,
    Drop,
    Use,
    Throw,
    Fire,
    Cast,
    SwapWeapons,
    Rifle,

    pub inline fn cost(self: Activity) usize {
        return switch (self) {
            .Interact => 90,
            .Rest,
            .Move,
            .Teleport,
            .Grab,
            .Drop,
            => 100,
            .Cast, .Throw, .Fire, .Attack => 110,
            .SwapWeapons, .Use => 120,
            .Rifle => 150,
        };
    }
};

pub const EnemyRecord = struct {
    mob: *Mob,
    last_seen: Coord,
    counter: usize,
};

pub const Message = struct {
    msg: [128]u8,
    type: MessageType,
    turn: usize,
};

pub const Allegiance = enum { Neutral, Sauron, Illuvatar, NoneEvil, NoneGood };

pub const Status = enum {
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

    // Makes mob move in random directions.
    //
    // Doesn't have a power field.
    Confusion,

    // Makes mob fast or slow.
    //
    // Doesn't have a power field.
    Fast,
    Slow,

    // Increases a mob's regeneration rate (see Mob.tick_hp).
    //
    // Doesn't have a power field.
    Recuperate,

    // Prevents regen and gives damage.
    //
    // Doesn't have a power field (but probably should).
    Poison,

    // Raises strength and dexterity and increases regeneration.
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

    // Allows mob to see directly behind them as well as in front of them.
    //
    // Doesn't have a power field.
    Backvision,

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

    pub const MAX_DURATION: usize = 20;

    pub fn string(self: Status) []const u8 {
        return switch (self) {
            .Paralysis => "paralyzed",
            .Held => "held",
            .Echolocation => "echolocation",
            .Corona => "glowing",
            .Confusion => "confused",
            .Fast => "hasted",
            .Slow => "slowed",
            .Recuperate => "recuperating",
            .Poison => "poisoned",
            .Invigorate => "invigorated",
            .Pain => "pain",
            .Fear => "fearful",
            .Backvision => "back vision",
            .NightVision => "night vision",
            .DayBlindness => "day blindness",
            .NightBlindness => "night blindness",
        };
    }

    pub fn tickPoison(mob: *Mob) void {
        mob.takeDamage(.{
            .amount = @intToFloat(f64, rng.rangeClumping(usize, 0, 2, 2)),
        });
    }

    pub fn tickPain(mob: *Mob) void {
        const st = mob.isUnderStatus(.Pain).?;

        mob.makeNoise(Mob.NOISE_SCREAM);
        mob.takeDamage(.{
            .amount = @intToFloat(f64, rng.rangeClumping(usize, 1, st.power, 2)),
        });
    }

    pub fn tickEcholocation(mob: *Mob) void {
        if (!mob.coord.eq(state.player.coord)) return;

        // TODO: do some tests and figure out what's the practical limit to memory
        // usage, and reduce the buffer's size to that.
        var membuf: [65535]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

        const st = state.player.isUnderStatus(.Echolocation).?;

        const radius = state.player.vision;
        const z = state.player.coord.z;
        const ystart = utils.saturating_sub(state.player.coord.y, radius);
        const yend = math.min(state.player.coord.y + radius, HEIGHT);
        const xstart = utils.saturating_sub(state.player.coord.x, radius);
        const xend = math.min(state.player.coord.x + radius, WIDTH);

        var tile: termbox.tb_cell = .{ .fg = 0xffffff, .ch = '#' };
        var y: usize = ystart;
        while (y < yend) : (y += 1) {
            var x: usize = xstart;
            while (x < xend) : (x += 1) {
                const coord = Coord.new2(z, x, y);
                const noise = state.player.canHear(coord) orelse continue;
                var dijk = dijkstra.Dijkstra.init(
                    coord,
                    state.mapgeometry,
                    st.power,
                    dijkstra.dummyIsValid,
                    .{},
                    &fba.allocator,
                );
                defer dijk.deinit();
                while (dijk.next()) |item| {
                    if (state.dungeon.neighboringWalls(item, true) == 9) {
                        dijk.skip();
                        continue;
                    }

                    tile.ch = if (state.dungeon.at(item).type == .Wall) '#' else '·';
                    _ = state.memory.getOrPutValue(item, tile) catch unreachable;
                }
            }
        }
    }
};

pub const StatusData = struct {
    // Which turn the status was slapped onto the mob
    started: usize = 0,

    // What's the "power" of a status (percentage). For some statuses, doesn't
    // mean anything at all.
    power: usize = 0, // What's the "power" of the status

    // How long the status should last, from the time it started.
    // turns_left := (started + duration) - current_turn
    duration: usize = 0, // How long

    // If the status is permanent.
    // If set, the duration doesn't matter.
    permanent: bool = false,
};

pub const StatusDataInfo = struct {
    status: Status,
    power: usize = 0,
    duration: usize = Status.MAX_DURATION,
    permanent: bool = false,
};

pub const AIPhase = enum { Work, Hunt, Investigate, Flee };

pub const AI = struct {
    // Name of mob doing the profession.
    profession_name: ?[]const u8,

    // Description of what the mob is doing. Examples: Guard("patrolling"),
    // Smith("forging"), Demon("sulking")
    profession_description: []const u8,

    // The area where the mob should be doing work.
    work_area: CoordArrayList = undefined,

    // Work callbacks:
    //     - work_fn:  on each tick when the mob is doing work.
    //     - fight_fn: on each tick when the mob is pursuing a hostile mob.
    //
    work_fn: fn (*Mob, *mem.Allocator) void,
    fight_fn: ?fn (*Mob, *mem.Allocator) void,

    // Should the mob attack hostiles?
    is_combative: bool,

    // Should the mob investigate noises?
    is_curious: bool,

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
};

pub const Mob = struct { // {{{
    species: []const u8,
    tile: u21,
    allegiance: Allegiance,

    squad_members: MobArrayList = undefined,
    prisoner_status: ?Prisoner = null,

    fov: [HEIGHT][WIDTH]usize = [1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT,
    path_cache: std.AutoHashMap(Path, Coord) = undefined,
    enemies: std.ArrayList(EnemyRecord) = undefined,

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
    is_dead: bool = false,

    // Immutable instrinsic attributes.
    //
    // willpower:          Controls the ability to resist and cast spells.
    // base_dexterity:     Controls the likelihood of a mob dodging an attack.
    // base_strength:      TODO: define!
    // hearing:            The minimum intensity of a noise source before it can be
    //                     heard by a mob. The lower the value, the better.
    // vision:             Maximum radius of the mob's field of vision.
    // base_night_vision:  If the light in a tile is below this amount, the mob cannot
    //                     see that tile, even if it's in the FOV. The lower, the
    //                     better.
    // deg360_vision:      Mob's FOV ignores the facing mechanic and can see in all
    //                     directions (e.g., player, statues)
    // no_show_fov:        If false, display code will not show mob's FOV.
    // memory:             The maximum length of time for which a mob can remember
    //                     an enemy.
    //
    willpower: usize, // Range: 0 < willpower < 10
    base_strength: usize,
    base_dexterity: usize, // Range: 0 < dexterity < 100
    vision: usize,
    base_night_vision: usize, // Range: 0 < night_vision < 100
    deg360_vision: bool = false,
    no_show_fov: bool = false,
    hearing: usize,
    memory_duration: usize,
    base_speed: usize,
    max_HP: f64,
    regen: f64 = 0.14,
    blood: ?Spatter,
    immobile: bool = false,
    spells: StackBuffer(SpellInfo, 2) = StackBuffer(SpellInfo, 2).init(null),

    pub const Inventory = struct {
        pack: PackBuffer = PackBuffer.init(&[_]Item{}),

        r_rings: [2]?*Ring = [2]?*Ring{ null, null },
        l_rings: [2]?*Ring = [2]?*Ring{ null, null },

        armor: ?*Armor = null,
        wielded: ?*Weapon = null,
        backup: ?*Weapon = null,

        pub const PACK_SIZE: usize = 7;
        pub const PackBuffer = StackBuffer(Item, PACK_SIZE);
    };

    // Size of `activities` Ringbuffer
    pub const MAX_ACTIVITY_BUFFER_SZ = 4;

    // Maximum field of hearing.
    pub const MAX_FOH = 20;

    pub const NOISE_MOVE = 50;
    pub const NOISE_SPEAK = 100;
    pub const NOISE_YELL = 150;
    pub const NOISE_SCREAM = 200;

    pub fn tickFOV(self: *Mob) void {
        for (self.fov) |*row| for (row) |*cell| {
            cell.* = 0;
        };

        const c_vision_range = self.vision_range();
        const energy = math.clamp(self.vision * state.FLOOR_OPACITY, 0, 100);
        const direction = if (self.deg360_vision) null else self.facing;

        fov.rayCast(self.coord, self.vision, energy, state.tileOpacity, &self.fov, direction);
        if (self.isUnderStatus(.Backvision) != null and direction != null)
            fov.rayCast(self.coord, self.vision, energy, state.tileOpacity, &self.fov, direction.?.opposite());

        for (self.fov) |row, y| for (row) |_, x| {
            if (self.fov[y][x] > 0) {
                const fc = Coord.new2(self.coord.z, x, y);
                const light = state.dungeon.lightIntensityAt(fc).*;

                // If a tile is too dim to be seen by a mob and it's not adjacent to that mob,
                // mark it as unlit.
                if (fc.distance(self.coord) > 1 and !c_vision_range.contains(light)) {
                    self.fov[y][x] = 0;
                    continue;
                }

                if (self.coord.eq(state.player.coord))
                    state.memory.put(fc, Tile.displayAs(fc, true)) catch unreachable;
            }
        };
    }

    // Regenerate health as necessary.
    //
    // TODO: regenerate health more if mob rested in last turn.
    pub fn tick_hp(self: *Mob) void {
        assert(!self.is_dead);

        if (self.isUnderStatus(.Poison)) |_| return;

        var regen = self.regen;
        if (self.isUnderStatus(.Invigorate)) |_| regen = regen * 150 / 100;
        if (self.isUnderStatus(.Recuperate)) |_| regen = regen * 450 / 100;

        self.HP = math.clamp(self.HP + regen, 0, self.max_HP);
    }

    // Check surrounding temperature/gas/water and drown, burn, freeze, or
    // corrode mob.
    pub fn tick_env(self: *Mob) void {
        const gases = state.dungeon.atGas(self.coord);
        for (gases) |quantity, gasi| {
            if (quantity > 0.0) {
                gas.Gases[gasi].trigger(self, quantity);
            }
        }
    }

    // Update the status powers for the rings
    pub fn tickRings(self: *Mob) void {
        for (&[_]?*Ring{
            self.inventory.l_rings[0],
            self.inventory.l_rings[1],
            self.inventory.r_rings[0],
            self.inventory.r_rings[1],
        }) |maybe_ring| {
            if (maybe_ring) |ring|
                self.addStatus(ring.status, ring.currentPower(), Status.MAX_DURATION, false);
        }
    }

    // Do stuff for various statuses that need babysitting each turn.
    pub fn tickStatuses(self: *Mob) void {
        inline for (@typeInfo(Status).Enum.fields) |status| {
            const status_e = @field(Status, status.name);
            if (self.isUnderStatus(status_e)) |_| {
                switch (status_e) {
                    .Echolocation => Status.tickEcholocation(self),
                    .Poison => Status.tickPoison(self),
                    .Pain => Status.tickPain(self),
                    else => {},
                }
            }
        }
    }

    pub fn swapWeapons(self: *Mob) bool {
        const tmp = self.inventory.wielded;
        self.inventory.wielded = self.inventory.backup;
        self.inventory.backup = tmp;
        return false; // zero-cost action
    }

    pub fn removeItem(self: *Mob, index: usize) !Item {
        if (index >= self.inventory.pack.len)
            return error.IndexOutOfRange;

        return self.inventory.pack.orderedRemove(index) catch unreachable;
    }

    pub fn quaffPotion(self: *Mob, potion: *Potion) void {
        // TODO: make the duration of potion status effect random (clumping, ofc)
        switch (potion.type) {
            .Status => |s| self.addStatus(s, 0, Status.MAX_DURATION, false),
            .Gas => |s| state.dungeon.atGas(self.coord)[s] = 1.0,
            .Custom => |c| c(self),
        }
    }

    pub fn launchProjectile(self: *Mob, launcher: *const Weapon.Launcher, at: Coord) bool {
        const trajectory = self.coord.drawLine(at, state.mapgeometry);
        var landed: ?Coord = null;
        var energy: usize = self.strength() * 2;

        for (trajectory.constSlice()) |coord| {
            if (energy == 0 or
                (!coord.eq(self.coord) and
                !state.is_walkable(coord, .{ .right_now = true })))
            {
                landed = coord;
                break;
            }
            energy -= 1;
        }
        if (landed == null) landed = at;

        if (state.dungeon.at(landed.?).mob) |bastard| {
            const hit =
                (rng.range(usize, 1, 100) <= combat.chanceOfAttackLanding(self, bastard)) and
                (rng.range(usize, 1, 100) >= combat.chanceOfAttackDodged(bastard, self));

            if (hit) {
                const projectile = launcher.projectile;
                const defender_armor = bastard.inventory.armor orelse &items.NoneArmor;
                const max_damage = projectile.damages.resultOf(&defender_armor.resists).sum();

                var damage = rng.rangeClumping(usize, max_damage / 2, max_damage, 2);
                bastard.takeDamage(.{ .amount = @intToFloat(f64, damage) });
            }
        }

        if (launcher.projectile.effect) |effect_func| (effect_func)(landed.?);

        self.declareAction(.Fire);
        self.makeNoise(launcher.noise);

        return true;
    }

    pub fn dropItem(self: *Mob, item: Item, at: Coord) bool {
        if (state.dungeon.at(at).surface) |surface| {
            switch (surface) {
                .Container => |container| {
                    if (container.items.len >= container.capacity) {
                        return false;
                    } else {
                        container.items.append(item) catch unreachable;
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
            state.dungeon.itemsAt(at).append(item) catch unreachable;
            self.declareAction(.Drop);
            return true;
        }
    }

    pub fn throwItem(self: *Mob, item: *Item, at: Coord) bool {
        switch (item.*) {
            .Potion => {},
            .Weapon => @panic("W/A TODO"),
            else => return false,
        }

        const trajectory = self.coord.drawLine(at, state.mapgeometry);
        var landed: ?Coord = null;
        var energy: usize = self.strength();

        for (trajectory.constSlice()) |coord| {
            if (energy == 0 or
                (!coord.eq(self.coord) and
                !state.is_walkable(coord, .{ .right_now = true })))
            {
                landed = coord;
                break;
            }
            energy -= 1;
        }
        if (landed == null) landed = at;

        switch (item.*) {
            .Weapon => |_| @panic("W/A TODO"),
            .Potion => |potion| {
                if (!potion.ingested) {
                    if (state.dungeon.at(landed.?).mob) |bastard| {
                        bastard.quaffPotion(potion);
                    } else switch (potion.type) {
                        .Status => {},
                        .Gas => |s| state.dungeon.atGas(landed.?)[s] = 1.0,
                        .Custom => |f| f(null),
                    }
                }

                // TODO: have cases where thrower misses and potion lands (unused?)
                // in adjacent square
            },
            else => unreachable,
        }

        return true;
    }

    pub fn declareAction(self: *Mob, action: Activity) void {
        assert(!self.is_dead);
        self.activities.append(action);
        self.energy -= @divTrunc(self.speed() * @intCast(isize, action.cost()), 100);
    }

    pub fn makeNoise(self: *Mob, amount: usize) void {
        assert(!self.is_dead);
        state.dungeon.soundAt(self.coord).* += amount;
    }

    // Check if a mob, when trying to move into a space that already has a mob,
    // can swap with that other mob. Return true if:
    //     - The mob's strength is greater than the other mob's strength.
    //     - The mob's speed is greater than the other mob's speed.
    //     - The other mob didn't try to move in the past turn.
    //     - The other mob was trying to move in the opposite direction, i.e.,
    //       both mobs were trying to shuffle past each other.
    //     - The mob wasn't working (e.g., may have been attacking), but the other
    //       one wasn't.
    //
    // Return false if:
    //     - The other mob was trying to move in the same direction. No need to barge
    //       past, he'll move soon enough.
    //     - The other mob is the player. No mob should be able to swap with the player.
    //     - The mob is the player and the other mob is a noncombative enemy (e.g.,
    //       slaves). The player has no business attacking non-combative enemies.
    //     - The other mob is immobile (e.g., a statue).
    //
    pub fn canSwapWith(self: *const Mob, other: *Mob, direction: ?Direction) bool {
        var can = false;

        if (other.isUnderStatus(.Paralysis)) |se| {
            can = true;
        }
        if (self.strength() > other.strength()) {
            can = true;
        }
        if (self.speed() > other.speed()) {
            can = true;
        }
        if (self.ai.phase != .Work and other.ai.phase == .Work) {
            can = true;
        }
        if (direction != null and other.last_attempted_move == null) {
            can = true;
        }
        if (direction != null and other.last_attempted_move != null) {
            if (direction.? == other.last_attempted_move.?.opposite()) {
                can = true;
            }
        }

        if (direction != null and other.last_attempted_move != null) {
            if (direction.? == other.last_attempted_move.?) {
                can = false;
            }
        }
        if (self.allegiance != other.allegiance) {
            can = false;
        }
        if (other.coord.eq(state.player.coord)) {
            can = false;
        }
        if (self.coord.eq(state.player.coord) and
            other.isHostileTo(state.player) and
            !other.ai.is_combative)
        {
            can = true;
        }

        if (other.immobile) {
            can = false;
        }

        return can;
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

        if (self.isUnderStatus(.Confusion)) |_|
            direction = rng.chooseUnweighted(Direction, &DIRECTIONS);

        // Face in that direction and update last_attempted_move, no matter
        // whether we end up moving or no
        self.facing = direction;
        self.last_attempted_move = direction;

        if (coord.move(direction, state.mapgeometry)) |dest| {
            return self.teleportTo(dest, direction);
        } else {
            return false;
        }
    }

    pub fn teleportTo(self: *Mob, dest: Coord, direction: ?Direction) bool {
        const coord = self.coord;

        if (!state.is_walkable(dest, .{ .right_now = true })) {
            if (state.dungeon.at(dest).surface) |surface| {
                switch (surface) {
                    .Machine => |m| if (!m.isWalkable()) {
                        m.addPower(self);
                        self.declareAction(.Interact);
                        return true;
                    },
                    .Poster => |p| {
                        state.message(.Info, "You read the poster: '{}'", .{p.text});
                    },
                    else => {},
                }
            }

            return false;
        }

        if (!self.isCreeping()) self.makeNoise(NOISE_MOVE);

        if (direction) |d| {
            self.declareAction(Activity{ .Move = d });
        } else {
            self.declareAction(Activity{ .Teleport = dest });
        }

        if (self.isUnderStatus(.Held)) |se| {
            const held_remove_max = self.strength() / 2;
            const held_remove = rng.rangeClumping(usize, 2, held_remove_max, 2);
            const new_duration = utils.saturating_sub(se.duration, held_remove);
            self.addStatus(.Held, 0, new_duration, false);
            return true;
        }

        if (state.dungeon.at(dest).mob) |other| {
            if (!self.canSwapWith(other, direction)) return false;
            state.dungeon.at(dest).mob = self;
            state.dungeon.at(coord).mob = other;
            self.coord = dest;
            other.coord = coord;
        } else {
            state.dungeon.at(dest).mob = self;
            state.dungeon.at(coord).mob = null;
            self.coord = dest;
        }

        if (state.dungeon.at(dest).surface) |surface| {
            switch (surface) {
                .Machine => |m| if (m.isWalkable()) m.addPower(self),
                else => {},
            }
        }

        return true;
    }

    pub fn gaze(self: *Mob, direction: Direction) bool {
        self.facing = direction;
        return true;
    }

    pub fn rest(self: *Mob) bool {
        if (self.isUnderStatus(.Pain) != null and !self.immobile) {
            if (!self.moveInDirection(rng.chooseUnweighted(Direction, &DIRECTIONS)))
                self.declareAction(.Rest);
        } else {
            self.declareAction(.Rest);
        }
        return true;
    }

    pub fn fight(attacker: *Mob, recipient: *Mob) void {
        assert(!attacker.is_dead);
        assert(!recipient.is_dead);

        assert(attacker.strength() > 0);
        assert(recipient.strength() > 0);

        attacker.declareAction(.{ .Attack = recipient.coord });

        // const chance_of_land = combat.chanceOfAttackLanding(attacker, recipient);
        // const chance_of_dodge = combat.chanceOfAttackDodged(recipient, attacker);
        // if (attacker.coord.eq(state.player.coord)) {
        //     state.message(.Info, "you attack: chance of land: {}, chance of dodge: {}", .{ chance_of_land, chance_of_dodge });
        // } else if (recipient.coord.eq(state.player.coord)) {
        //     state.message(.Info, "you defend: chance of land: {}, chance of dodge: {}", .{ chance_of_land, chance_of_dodge });
        // }

        const hit =
            (rng.range(usize, 1, 100) <= combat.chanceOfAttackLanding(attacker, recipient)) and
            (rng.range(usize, 1, 100) >= combat.chanceOfAttackDodged(recipient, attacker));

        if (!hit) return;

        const is_stab = !recipient.isAwareOfAttack(attacker.coord);
        const attacker_weapon = attacker.inventory.wielded orelse &items.UnarmedWeapon;
        const attacker_extra_str = attacker.strength() * 100 / attacker_weapon.required_strength;
        const attacker_extra_str_adj = math.clamp(attacker_extra_str, 0, 150);
        const recipient_armor = recipient.inventory.armor orelse &items.NoneArmor;
        const max_damage = attacker_weapon.damages.resultOf(&recipient_armor.resists).sum();

        assert(attacker_weapon.required_strength > 0);

        var damage: usize = 0;
        damage += rng.rangeClumping(usize, max_damage / 2, max_damage, 2);
        damage = utils.percentOf(usize, damage, attacker_extra_str_adj);

        if (is_stab) {
            const bonus = DamageType.stabBonus(attacker_weapon.main_damage);
            damage = utils.percentOf(usize, damage, bonus);
        }

        recipient.takeDamage(.{ .amount = @intToFloat(f64, damage) });

        const noise = DamageType.causeNoise(attacker_weapon.main_damage, is_stab);
        attacker.makeNoise(noise + rng.range(usize, 1, 3));
        recipient.makeNoise(noise + rng.range(usize, 1, 3));

        const hitstr = DamageType.damageString(
            attacker_weapon.main_damage,
            recipient.lastDamagePercentage(),
        );

        if (recipient.coord.eq(state.player.coord)) {
            state.message(.Info, "The {} {} you for {} damage!", .{ attacker.species, hitstr, damage });
        } else if (attacker.coord.eq(state.player.coord)) {
            state.message(.Info, "You {} the {} for {} damage!", .{ hitstr, recipient.species, damage });
            if (recipient.should_be_dead()) {
                state.message(.Damage, "You slew the {}.", .{recipient.species});
            }
        }
    }

    pub fn takeDamage(self: *Mob, d: Damage) void {
        self.HP = math.clamp(self.HP - d.amount, 0, self.max_HP);
        self.last_damage = d;
        if (self.blood) |s| state.dungeon.spatter(self.coord, s);
    }

    // Called when player hits the [r]ifle key -- I see no reason for it to
    // be called anytime else.
    //
    pub fn vomitInventory(self: *Mob, alloc: *mem.Allocator) void {
        const special_invent = [_]?Item{
            if (self.inventory.l_rings[0]) |r| Item{ .Ring = r } else null,
            if (self.inventory.l_rings[1]) |r| Item{ .Ring = r } else null,
            if (self.inventory.r_rings[0]) |r| Item{ .Ring = r } else null,
            if (self.inventory.r_rings[1]) |r| Item{ .Ring = r } else null,
            if (self.inventory.armor) |a| Item{ .Armor = a } else null,
            if (self.inventory.wielded) |w| Item{ .Weapon = w } else null,
        };

        comptime const inventory_size = special_invent.len + Inventory.PACK_SIZE;
        var coords = StackBuffer(Coord, inventory_size).init(null);

        var dijk = dijkstra.Dijkstra.init(
            self.coord,
            state.mapgeometry,
            5,
            state.is_walkable,
            .{ .right_now = true },
            alloc,
        );
        defer dijk.deinit();

        while (dijk.next()) |coord| {
            // Papering over a bug here, next() should never return starting coord
            if (coord.eq(self.coord)) continue;

            if (!state.is_walkable(coord, .{}) or state.dungeon.itemsAt(coord).isFull())
                continue;

            coords.append(coord) catch |e| switch (e) {
                error.NoSpaceLeft => break,
                else => unreachable,
            };
        }

        var ctr: usize = 0;

        for (&special_invent) |maybe_item| {
            if (maybe_item) |item| {
                if (ctr >= coords.len) break;
                state.dungeon.itemsAt(coords.data[ctr]).append(item) catch unreachable;
                ctr += 1;
            }
        }
        for (self.inventory.pack.constSlice()) |item| {
            if (ctr >= coords.len) break;
            state.dungeon.itemsAt(coords.data[ctr]).append(item) catch unreachable;
            ctr += 1;
        }

        self.inventory.pack.clear();
        self.inventory.armor = null;
        self.inventory.wielded = null;
        self.inventory.l_rings = [_]?*Ring{ null, null };
        self.inventory.r_rings = [_]?*Ring{ null, null };
    }

    pub fn init(self: *Mob, alloc: *mem.Allocator) void {
        self.HP = self.max_HP;
        self.squad_members = MobArrayList.init(alloc);
        self.enemies = std.ArrayList(EnemyRecord).init(alloc);
        self.activities.init();
        self.path_cache = std.AutoHashMap(Path, Coord).init(alloc);
        self.ai.work_area = CoordArrayList.init(alloc);
    }

    pub fn kill(self: *Mob) void {
        self.squad_members.deinit();
        self.enemies.deinit();
        self.path_cache.clearAndFree();
        self.ai.work_area.deinit();

        self.is_dead = true;

        if (state.dungeon.itemsAt(self.coord).isFull())
            _ = state.dungeon.itemsAt(self.coord).orderedRemove(0) catch unreachable;

        state.dungeon.itemsAt(self.coord).append(Item{ .Corpse = self }) catch unreachable;

        state.dungeon.at(self.coord).mob = null;
    }

    pub fn should_be_dead(self: *const Mob) bool {
        if (self.HP == 0)
            return true;

        return false;
    }

    pub fn nextDirectionTo(self: *Mob, to: Coord) ?Direction {
        // FIXME: make this an assertion; no mob should ever be trying to path to
        // themself.
        if (self.coord.eq(to)) return null;

        if (Direction.from_coords(self.coord, to)) |direction| {
            return direction;
        } else |_err| {}

        const pathobj = Path{ .from = self.coord, .to = to };

        if (!self.path_cache.contains(pathobj)) {
            // TODO: do some tests and figure out what's the practical limit to memory
            // usage, and reduce the buffer's size to that.
            var membuf: [65535]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

            const pth = astar.path(
                self.coord,
                to,
                state.mapgeometry,
                state.is_walkable,
                .{ .mob = self },
                &fba.allocator,
            ) orelse return null;

            assert(pth.items[0].eq(self.coord));
            var last: Coord = self.coord;
            for (pth.items[1..]) |coord| {
                self.path_cache.put(Path{ .from = last, .to = to }, coord) catch unreachable;
                last = coord;
            }
            assert(last.eq(to));

            pth.deinit();
        }

        // Return the next direction, ensuring that the next tile is walkable.
        // If it is not, set the path to null, ensuring that the path will be
        // recalculated next time.
        if (self.path_cache.get(pathobj)) |next| {
            const direction = Direction.from_coords(self.coord, next) catch unreachable;
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

    pub fn addStatus(self: *Mob, status: Status, power: usize, duration: ?usize, permanent: bool) void {
        const p_se = self.statuses.getPtr(status);
        p_se.started = state.ticks;
        p_se.power = power;
        p_se.duration = duration orelse Status.MAX_DURATION;
        p_se.permanent = permanent;
    }

    pub fn isUnderStatus(self: *const Mob, status: Status) ?*const StatusData {
        const se = self.statuses.getPtrConst(status);
        return if (se.permanent or (se.started + se.duration) < state.ticks) null else se;
    }

    pub fn lastDamagePercentage(self: *const Mob) usize {
        if (self.last_damage) |dam| {
            const am = math.clamp(dam.amount, 0, self.max_HP);
            return @floatToInt(usize, (am * 100) / self.max_HP);
        } else {
            return 0;
        }
    }

    // Check if a mob is capable of dodging an attack. Return false if:
    //  - Mob was in .Work AI phase, and not in Investigate/Attack phase
    //  - Mob was incapitated by a status effect (e.g. Paralysis)
    //
    // Player is always aware of attacks. Stabs are there in the first place
    // to "reward" the player for catching a hostile off guard, but allowing
    // enemies to stab a paralyzed player is too harsh of a punishment.
    //
    pub fn isAwareOfAttack(self: *const Mob, attacker: Coord) bool {
        if (self.coord.eq(state.player.coord))
            return true;

        switch (self.ai.phase) {
            .Flee, .Hunt, .Investigate => {},
            else => return false,
        }

        if (self.isUnderStatus(.Paralysis)) |_| return false;

        if (self.cansee(attacker)) return true;

        return false;
    }

    pub fn canHear(self: *const Mob, coord: Coord) ?usize {
        const sound = state.dungeon.soundAt(coord).*;

        if (self.coord.z != coord.z)
            return null; // Can't hear across levels
        if (self.coord.distance(coord) > MAX_FOH)
            return null; // Too far away
        if (sound < self.hearing)
            return null; // Too quiet to hear

        const line = self.coord.drawLine(coord, state.mapgeometry);
        var apparent_volume = sound - self.hearing;

        // FIXME: this lazy sound propagation formula isn't accurate. But this is
        // a game, so I can get away with it, right?
        for (line.constSlice()) |c| {
            const resistance: usize = if (state.dungeon.at(c).type == .Wall)
                @floatToInt(usize, 2 * state.dungeon.at(c).material.density)
            else
                0;
            apparent_volume = utils.saturating_sub(apparent_volume, resistance);
        }

        return if (apparent_volume >= self.hearing) apparent_volume else null;
    }

    pub fn isHostileTo(self: *const Mob, othermob: *const Mob) bool {
        var hostile = false;

        // TODO: deal with all the nuances (eg .NoneGood should not be hostile
        // to .Illuvatar, but .NoneEvil should be hostile to .Sauron)
        if (self.allegiance != othermob.allegiance) hostile = true;

        // If the other mob is a prisoner of my faction or we're both prisoners
        // of the same faction, don't be hostile
        if (othermob.prisoner_status) |prisoner_status| {
            if (prisoner_status.of == self.allegiance and
                state.dungeon.at(othermob.coord).prison)
            {
                hostile = false;
            }

            if (self.prisoner_status) |my_prisoner_status| {
                if (my_prisoner_status.of == prisoner_status.of and
                    state.dungeon.at(self.coord).prison)
                {
                    hostile = false;
                }
            }
        }

        return hostile;
    }

    pub fn cansee(self: *const Mob, coord: Coord) bool {
        if (self.coord.distance(coord) > self.vision)
            return false;

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

    pub fn speed(self: *const Mob) isize {
        var bonus: usize = 100;
        if (self.ai.phase == .Flee) bonus -= 10;
        if (self.isUnderStatus(.Fast)) |_| bonus = bonus * 50 / 100;
        if (self.isUnderStatus(.Slow)) |_| bonus = bonus * 160 / 100;

        return @intCast(isize, self.base_speed * bonus / 100);
    }

    pub fn vision_range(self: *const Mob) MinMax(usize) {
        var min: usize = self.base_night_vision;
        if (self.isUnderStatus(.NightBlindness) != null)
            min = math.clamp(min + 30, 0, 50);
        if (self.isUnderStatus(.NightVision) != null and min > 0)
            min = 0;

        var max: usize = 100;
        if (self.isUnderStatus(.DayBlindness) != null)
            max = 60;

        return .{ .min = min, .max = max };
    }

    pub inline fn strength(self: *const Mob) usize {
        var str = self.base_strength;
        if (self.isUnderStatus(.Invigorate)) |_| str = str * 180 / 100;
        return str;
    }

    pub inline fn dexterity(self: *const Mob) usize {
        var dex = self.base_dexterity;
        if (self.isUnderStatus(.Invigorate)) |_| dex = dex * 150 / 100;
        return dex;
    }

    pub fn isCreeping(self: *const Mob) bool {
        return self.turnsSinceRest() < self.activities.len;
    }

    pub fn turnsSinceRest(self: *const Mob) usize {
        var since: usize = 0;

        var iter = self.activities.iterator();
        while (iter.next()) |ac| {
            if (ac == .Rest) return since else since += 1;
        }

        return since;
    }
}; // }}}

pub const Sob = struct {
    id: []const u8 = "",
    species: []const u8,
    tile: u21,
    coord: Coord = undefined,
    allegiance: Allegiance = .Neutral,
    damage: usize = 0, // 1..100
    age: usize = 0,
    is_dead: usize = false,
    walkable: bool,
    ai_func: fn (*Sob) void,
};

pub const Machine = struct {
    id: []const u8 = "",
    name: []const u8,

    powered_tile: u21,
    unpowered_tile: u21,

    powered_fg: ?u32 = null,
    unpowered_fg: ?u32 = null,
    powered_bg: ?u32 = null,
    unpowered_bg: ?u32 = null,

    power_drain: usize = 100, // Power drained per turn
    power_add: usize = 100, // Power added on interact
    auto_power: bool = false,

    restricted_to: ?Allegiance = null,
    powered_walkable: bool = true,
    unpowered_walkable: bool = true,

    powered_opacity: f64 = 0.0,
    unpowered_opacity: f64 = 0.0,

    powered_luminescence: usize = 0,
    unpowered_luminescence: usize = 0,
    dims: bool = false,

    // A* penalty if the machine is walkable
    pathfinding_penalty: usize = 0,

    coord: Coord = Coord.new(0, 0),
    on_power: fn (*Machine) void, // Called on each turn when the machine is powered
    power: usize = 0, // percentage (0..100)
    last_interaction: ?*Mob = null,
    disabled: bool = false,

    // TODO: Remove
    props: [40]?*Prop = [_]?*Prop{null} ** 40,

    // Areas the machine might manipulate/change while powered
    //
    // E.g., a blast furnace will heat up the first area, and search
    // for fuel in the second area.
    areas: StackBuffer(Coord, 8) = StackBuffer(Coord, 8).init(null),

    pub fn addPower(self: *Machine, by: ?*Mob) void {
        if (by) |_by|
            if (self.restricted_to) |restriction|
                if (restriction != _by.allegiance) return;

        self.power = math.min(self.power + self.power_add, 100);
        self.last_interaction = by;
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
};

pub const Prop = struct {
    id: []const u8,
    name: []const u8,
    tile: u21,
    fg: ?u32 = null,
    bg: ?u32 = null,
    walkable: bool = true,
    opacity: f64 = 0.0,
    coord: Coord = Coord.new(0, 0),

    pub fn deinit(self: *const Prop, alloc: *mem.Allocator) void {
        alloc.free(self.id);
        alloc.free(self.name);
    }
};

pub const Container = struct {
    name: []const u8,
    tile: u21,
    capacity: usize,
    items: ItemBuffer = ItemBuffer.init(null),
    type: ContainerType,
    coord: Coord = undefined,
    item_repeat: usize = 10, // Chance of the first item appearing again

    pub const ItemBuffer = StackBuffer(Item, 21);
    pub const ContainerType = enum {
        Eatables, // All food
        Wearables, // Weapons, armor, clothing, thread, cloth
        Valuables, // potions
        VOres, // self-explanatory
        Casual, // dice, deck of cards
        Utility, // Depends on the level (for PRI: rope, chains, etc)
    };
};

pub const SurfaceItemTag = enum { Machine, Prop, Sob, Container, Poster };
pub const SurfaceItem = union(SurfaceItemTag) {
    Machine: *Machine,
    Prop: *Prop,
    Sob: *Sob,
    Container: *Container,
    Poster: *const Poster,
};

// Each weapon and armor has a specific amount of maximum damage it can create
// or prevent. That damage comes in several different types:
//      - Crushing: clubs, maces, morningstars, battleaxes.
//      - Slashing: swords, battleaxes.
//      - Pulping: morningstars.
//      - Puncture: spears, daggers, swords.
//      - Lacerate: warwhips, morningstars.
//
// Just as each weapon may cause one or more of each type of damage, each armor
// may prevent one or more of each damage as well.

pub const DamageType = enum {
    Crushing,
    Pulping,
    Slashing,
    Piercing,
    Lacerating,

    const CRUSHING_STRS = [_][]const u8{ "slap", "smack", "bump", "thwack", "whack", "club", "cudgel", "bash", "pummel", "drub", "batter", "thrash" };
    const PULPING_STRS = CRUSHING_STRS;
    const SLASHING_STRS = [_][]const u8{ "nip", "cut", "slice", "slash", "shred" };
    const PIERCING_STRS = [_][]const u8{ "poke", "prick", "pierce", "puncture", "stab", "skewer" };
    const LACERATING_STRS = [_][]const u8{ "whip", "lash", "tear", "lacerate", "shred" };

    pub fn damageString(d: DamageType, damage_percentage: usize) []const u8 {
        const strs = switch (d) {
            .Crushing => &CRUSHING_STRS,
            .Pulping => &PULPING_STRS,
            .Slashing => &SLASHING_STRS,
            .Piercing => &PIERCING_STRS,
            .Lacerating => &LACERATING_STRS,
        };

        return strs[(damage_percentage * (strs.len - 1)) / 100];
    }

    pub fn causeNoise(d: DamageType, stab: bool) usize {
        return switch (d) {
            .Crushing => if (stab) @as(usize, 10) else @as(usize, 18),
            .Pulping => if (stab) @as(usize, 11) else @as(usize, 18),
            .Slashing => if (stab) @as(usize, 5) else @as(usize, 14),
            .Piercing => if (stab) @as(usize, 3) else @as(usize, 10),
            .Lacerating => if (stab) @as(usize, 15) else @as(usize, 19),
        };
    }

    // Return a percentile bonus with which to multiply the base damage
    // amount when an attack is a stabbing attack.
    pub fn stabBonus(d: DamageType) usize {
        return switch (d) {
            .Crushing => 420,
            .Pulping => 350,
            .Slashing => 540,
            .Piercing => 700,
            .Lacerating => 210,
        };
    }
};

//pub const Damages = enums.EnumFieldStruct(DamageType, 0);
pub const Damages = struct {
    Crushing: usize = 0,
    Pulping: usize = 0,
    Slashing: usize = 0,
    Piercing: usize = 0,
    Lacerating: usize = 0,

    pub const Self = @This();

    pub fn sum(self: *Self) usize {
        return self.Crushing +
            self.Pulping +
            self.Slashing +
            self.Piercing +
            self.Lacerating;
    }

    pub fn resultOf(attack: *const Self, defense: *const Self) Self {
        return .{
            .Crushing = @intCast(usize, math.max(
                0,
                (@intCast(isize, defense.Crushing) - @intCast(isize, attack.Crushing)) * -1,
            )),
            .Pulping = @intCast(usize, math.max(
                0,
                (@intCast(isize, defense.Pulping) - @intCast(isize, attack.Pulping)) * -1,
            )),
            .Slashing = @intCast(usize, math.max(
                0,
                (@intCast(isize, defense.Slashing) - @intCast(isize, attack.Slashing)) * -1,
            )),
            .Piercing = @intCast(usize, math.max(
                0,
                (@intCast(isize, defense.Piercing) - @intCast(isize, attack.Piercing)) * -1,
            )),
            .Lacerating = @intCast(usize, math.max(
                0,
                (@intCast(isize, defense.Lacerating) - @intCast(isize, attack.Lacerating)) * -1,
            )),
        };
    }

    pub fn damageOf(self: *Self, d: DamageType) *usize {
        const fields = @typeInfo(Self).fields;
        var found_at: 0 = 0;
        inline for (fields) |field, i| {
            if (mem.eql(u8, @tagName(d), field.name))
                found_at = i;
        }
        return @field(self, fields[found_at].name);
    }
};

pub const Armor = struct {
    id: []const u8,
    name: []const u8,
    resists: Damages,
};

pub const Projectile = struct {
    main_damage: DamageType,
    damages: Damages,
    effect: ?fn (Coord) void = null,
};

pub const Weapon = struct {
    id: []const u8,
    name: []const u8,
    required_strength: usize,
    required_dexterity: usize,
    damages: Damages,
    main_damage: DamageType,
    secondary_damage: ?DamageType,
    launcher: ?Launcher = null,

    pub const Launcher = struct {
        noise: usize,
        projectile: Projectile,
    };
};

pub const Potion = struct {
    id: []const u8,

    // Potion of <name>
    name: []const u8,

    type: union(enum) {
        Status: Status,
        Gas: usize,
        Custom: fn (?*Mob) void,
    },

    // Whether the potion needs to be quaffed to work. If false,
    // thrown potions will not have any effect, even if they land
    // on a mob.
    ingested: bool = false,

    color: u32,
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
    // Ring of <name>
    name: []const u8,

    status: Status,

    // So, statuses have a concept of "power". And rings work by conferring a status
    // when worn, and removing it when taken off.
    //
    // However, ring's don't give the full power all at once -- rather, the power starts
    // at a certain amount ($status_start_power), increases by 1 every $status_power_increase
    // turns, until it reaches $status_max_power.
    //
    status_start_power: usize,
    status_max_power: usize,
    status_power_increase: usize,

    worn_since: ?usize = null,

    pub fn currentPower(self: *Ring) usize {
        if (self.worn_since) |worn_since| {
            assert(worn_since <= state.ticks);

            const turns_passed = state.ticks - worn_since;
            const base_pow = turns_passed / self.status_power_increase;
            const max = self.status_max_power;
            return math.min(self.status_start_power + base_pow, max);
        } else {
            return 0;
        }
    }
};

pub const ItemType = enum {
    Corpse, Ring, Potion, Vial, Armor, Weapon, Boulder, Prop
};

pub const Item = union(ItemType) {
    Corpse: *Mob,
    Ring: *Ring,
    Potion: *Potion,
    Vial: Vial,
    Armor: *Armor,
    Weapon: *Weapon,
    Boulder: *const Material,
    Prop: *const Prop,

    pub fn shortName(self: *const Item) !StackBuffer(u8, 128) {
        var buf = StackBuffer(u8, 128).init(&([_]u8{0} ** 128));
        var fbs = std.io.fixedBufferStream(buf.slice());
        switch (self.*) {
            .Corpse => |c| try fmt.format(fbs.writer(), "{} corpse", .{c.species}),
            .Ring => |r| try fmt.format(fbs.writer(), "ring of {}", .{r.name}),
            .Potion => |p| try fmt.format(fbs.writer(), "potion of {}", .{p.name}),
            .Vial => |v| try fmt.format(fbs.writer(), "vial of {}", .{v.name()}),
            .Armor => |a| try fmt.format(fbs.writer(), "{} armor", .{a.name}),
            .Weapon => |w| try fmt.format(fbs.writer(), "{}", .{w.name}),
            .Boulder => |b| try fmt.format(fbs.writer(), "boulder of {}", .{b.name}),
            .Prop => |b| try fmt.format(fbs.writer(), "{}", .{b.name}),
        }
        buf.resizeTo(@intCast(usize, fbs.getPos() catch unreachable));
        return buf;
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
    spatter: SpatterArray = SpatterArray.initFill(0),

    pub fn displayAs(coord: Coord, ignore_lights: bool) termbox.tb_cell {
        var self = state.dungeon.at(coord);
        var cell = termbox.tb_cell{};

        const color: u32 = utils.percentageOfColor(self.material.color_floor, 40);

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
            .Wall => {
                cell = .{
                    .ch = materials.tileFor(coord, self.material.tileset),
                    .fg = self.material.color_fg,
                    .bg = self.material.color_bg orelse color,
                };
            },
            .Floor => {
                if (self.mob) |mob| {
                    cell.bg = color;

                    const hp_loss_percent = 100 - (mob.HP * 100 / mob.max_HP);
                    if (hp_loss_percent > 0) {
                        const red = @floatToInt(u32, (255 * hp_loss_percent) / 100) + 0x66;
                        cell.bg = math.clamp(red, 0x66, 0xff) << 16;
                    }

                    cell.ch = mob.tile;
                } else if (state.dungeon.itemsAt(coord).last()) |item| {
                    cell.fg = 0xffffff;
                    cell.bg = color;

                    switch (item) {
                        .Corpse => |_| {
                            cell.ch = '%';
                            cell.fg = 0xffe0ef;
                        },
                        .Potion => |potion| {
                            cell.ch = '¡';
                            cell.fg = potion.color;
                        },
                        .Vial => |v| {
                            cell.ch = '♪';
                            cell.fg = v.color();
                        },
                        .Weapon => |_| {
                            cell.ch = '≥'; // TODO: use U+1F5E1?
                        },
                        .Armor => |_| {
                            cell.ch = '&'; // TODO: use U+1F6E1?
                        },
                        .Boulder => |b| {
                            cell.ch = '©';
                            cell.fg = b.color_floor;
                        },
                        .Prop => |p| {
                            cell.ch = p.tile;
                            cell.fg = p.fg orelse 0xffffff;
                        },
                        else => cell.ch = '?',
                    }
                } else if (state.dungeon.at(coord).surface) |surfaceitem| {
                    cell.fg = 0xffffff;
                    cell.bg = color;

                    const ch = switch (surfaceitem) {
                        .Container => |c| cont: {
                            if (c.capacity >= 14) {
                                cell.fg = 0x000000;
                                cell.bg = 0x808000;
                            }
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
                            break :mach m.tile();
                        },
                        .Prop => |p| prop: {
                            if (p.bg) |prop_bg| cell.bg = prop_bg;
                            if (p.fg) |prop_fg| cell.fg = prop_fg;
                            break :prop p.tile;
                        },
                        .Sob => |s| s.tile,
                        .Poster => '∺',
                    };

                    cell.ch = ch;
                } else {
                    cell.ch = ' ';
                    cell.bg = color;
                }
            },
        }

        if (!ignore_lights) {
            const light = math.clamp(state.dungeon.lightIntensityAt(coord).*, 0, 100);
            cell.bg = math.max(utils.percentageOfColor(cell.bg, light), utils.darkenColor(cell.bg, 3));
            cell.fg = math.max(utils.percentageOfColor(cell.fg, light), utils.darkenColor(cell.fg, 3));
        }

        const temperature = state.dungeon.heat[coord.z][coord.y][coord.x];
        const light_emitted = heat.lightEmittedByHeat(temperature);
        cell.bg = utils.mixColors(cell.bg, 0xffe122, @intToFloat(f64, light_emitted) / 1000);

        var spattering = self.spatter.iterator();
        while (spattering.next()) |entry| {
            const spatter = entry.key;
            const num = entry.value.*;
            const sp_color = spatter.color();
            const q = @intToFloat(f64, num / 10);
            const aq = 1 - math.clamp(q, 0.19, 0.40);
            if (num > 0) cell.bg = utils.mixColors(sp_color, cell.bg, aq);
        }

        const gases = state.dungeon.atGas(coord);
        for (gases) |q, g| {
            const gcolor = gas.Gases[g].color;
            const aq = 1 - math.clamp(q, 0.19, 1);
            if (q > 0) cell.bg = utils.mixColors(gcolor, cell.bg, aq);
        }

        return cell;
    }
};

pub const Dungeon = struct {
    map: [LEVELS][HEIGHT][WIDTH]Tile = [1][HEIGHT][WIDTH]Tile{[1][WIDTH]Tile{[1]Tile{.{}} ** WIDTH} ** HEIGHT} ** LEVELS,
    items: [LEVELS][HEIGHT][WIDTH]ItemBuffer = [1][HEIGHT][WIDTH]ItemBuffer{[1][WIDTH]ItemBuffer{[1]ItemBuffer{ItemBuffer.init(null)} ** WIDTH} ** HEIGHT} ** LEVELS,
    gas: [LEVELS][HEIGHT][WIDTH][gas.GAS_NUM]f64 = [1][HEIGHT][WIDTH][gas.GAS_NUM]f64{[1][WIDTH][gas.GAS_NUM]f64{[1][gas.GAS_NUM]f64{[1]f64{0} ** gas.GAS_NUM} ** WIDTH} ** HEIGHT} ** LEVELS,
    sound: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    light_intensity: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    light_color: [LEVELS][HEIGHT][WIDTH]u32 = [1][HEIGHT][WIDTH]u32{[1][WIDTH]u32{[1]u32{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    heat: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{heat.DEFAULT_HEAT} ** WIDTH} ** HEIGHT} ** LEVELS,
    rooms: [LEVELS]RoomArrayList = undefined,

    pub const ItemBuffer = StackBuffer(Item, 7);

    pub fn emittedLightIntensity(self: *Dungeon, coord: Coord) usize {
        const tile: *Tile = state.dungeon.at(coord);

        var l: usize = 0;

        l += heat.lightEmittedByHeat(self.heat[coord.z][coord.y][coord.x]);

        if (tile.mob) |mob| {
            if (mob.isUnderStatus(.Corona)) |se| l += se.power;
        }

        if (tile.surface) |surface| {
            switch (surface) {
                .Machine => |m| l += m.luminescence(),
                else => {},
            }
        }

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
        const directions = if (diags) &DIRECTIONS else &CARDINAL_DIRECTIONS;

        var walls: usize = if (self.at(c).type == .Wall) 1 else 0;
        for (directions) |d| {
            if (c.move(d, state.mapgeometry)) |neighbor| {
                if (self.at(neighbor).type == .Wall)
                    walls += 1;
            } else {
                walls += 1;
                continue;
            }
        }
        return walls;
    }

    pub fn spatter(self: *Dungeon, c: Coord, what: Spatter) void {
        for (&DIRECTIONS) |d| {
            if (!rng.onein(4)) continue;

            if (c.move(d, state.mapgeometry)) |neighbor| {
                const prev = self.at(neighbor).spatter.get(what);
                const new = math.min(prev + rng.range(usize, 0, 5), 10);
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

    // STYLE: rename to gasAt
    pub inline fn atGas(self: *Dungeon, c: Coord) []f64 {
        return &self.gas[c.z][c.y][c.x];
    }

    pub inline fn soundAt(self: *Dungeon, c: Coord) *usize {
        return &self.sound[c.z][c.y][c.x];
    }

    pub inline fn lightIntensityAt(self: *Dungeon, c: Coord) *usize {
        return &self.light_intensity[c.z][c.y][c.x];
    }

    pub inline fn itemsAt(self: *Dungeon, c: Coord) *ItemBuffer {
        return &self.items[c.z][c.y][c.x];
    }
};

pub const Spatter = enum {
    Blood,
    Dust,

    pub inline fn color(self: Spatter) u32 {
        return switch (self) {
            .Blood => 0x9a1313,
            .Dust => 0x92744c,
        };
    }
};

pub const Gas = struct {
    color: u32,
    dissipation_rate: f64,
    opacity: f64,
    trigger: fn (*Mob, f64) void,
    id: usize,
    residue: ?Spatter = null,
};
