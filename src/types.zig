const std = @import("std");
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const assert = std.debug.assert;
const enums = @import("std/enums.zig");

const LinkedList = @import("list.zig").LinkedList;
const RingBuffer = @import("ringbuffer.zig").RingBuffer;
const StackBuffer = @import("buffer.zig").StackBuffer;

const ai = @import("ai.zig");
const fov = @import("fov.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
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

const Evocable = @import("items.zig").Evocable;

const Sound = @import("sound.zig").Sound;
const SoundIntensity = @import("sound.zig").SoundIntensity;
const SoundType = @import("sound.zig").SoundType;

const SpellInfo = spells.SpellInfo;
const Spell = spells.Spell;
const Poster = literature.Poster;

pub const HEIGHT = 40;
pub const WIDTH = 100;
pub const LEVELS = 7;
pub const PLAYER_STARTING_LEVEL = 5; // TODO: define in data file

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const CoordArrayList = std.ArrayList(Coord);
pub const StockpileArrayList = std.ArrayList(Stockpile);
pub const MessageArrayList = std.ArrayList(Message);
pub const StatusArray = enums.EnumArray(Status, StatusData);
pub const SpatterArray = enums.EnumArray(Spatter, usize);
pub const MobList = LinkedList(Mob);
pub const MobArrayList = std.ArrayList(*Mob);
pub const RingList = LinkedList(Ring);
pub const PotionList = LinkedList(Potion);
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
            else => err.wat(),
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

        buf.append(Coord.new2(z, @intCast(usize, x), @intCast(usize, y))) catch err.wat();
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
        const dx = @intToFloat(f64, math.absInt(xend - xstart) catch err.wat());
        const dy = @intToFloat(f64, math.absInt(yend - ystart) catch err.wat());

        var errmarg: f64 = 0.0;
        var x = @intCast(isize, from.x);
        var y = @intCast(isize, from.y);

        if (dx > dy) {
            errmarg = dx / 2.0;
            while (x != xend) {
                insert_if_valid(from.z, x, y, &buf, limit);
                errmarg -= dy;
                if (errmarg < 0) {
                    y += stepy;
                    errmarg += dx;
                }
                x += stepx;
            }
        } else {
            errmarg = dy / 2.0;
            while (y != yend) {
                insert_if_valid(from.z, x, y, &buf, limit);
                errmarg -= dx;
                if (errmarg < 0) {
                    x += stepx;
                    errmarg += dy;
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

        const ca = utils.saturating_sub(a.start.x, padding) < b_end.x;
        const cb = (a_end.x + padding) > b.start.x;
        const cc = utils.saturating_sub(a.start.y, padding) < b_end.y;
        const cd = (a_end.y + padding) > b.start.y;

        return ca and cb and cc and cd;
    }

    pub fn randomCoord(self: *const Rect) Coord {
        const x = rng.range(usize, self.start.x, self.end().x - 1);
        const y = rng.range(usize, self.start.y, self.end().y - 1);
        return Coord.new2(self.start.z, x, y);
    }
};

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
    std.testing.expect((Stockpile{ .room = undefined, .type = .Weapon }).isOfSameType(&Item{ .Weapon = undefined }));
    std.testing.expect((Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .Metal }).isOfSameType(&Item{ .Boulder = &materials.Iron }));
    std.testing.expect((Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .I_Stone }).isOfSameType(&Item{ .Boulder = &materials.Basalt }));
    std.testing.expect(!(Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .I_Stone }).isOfSameType(&Item{ .Boulder = &materials.Iron }));
    std.testing.expect(!(Stockpile{ .room = undefined, .type = .Boulder, .boulder_material_type = .Metal }).isOfSameType(&Item{ .Boulder = &materials.Hematite }));
}

pub const Path = struct { from: Coord, to: Coord };

pub const Material = struct {
    // Name of the material. e.g. "rhyolite"
    name: []const u8,

    // Description. e.g. "A sooty, flexible material used to make fire-proof
    // cloaks."
    description: []const u8,

    type: MaterialType = .I_Stone,

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

    smelt_result: ?*const Material = null,

    // Specific heat in kJ/(kg K)
    specific_heat: f64,

    // How much light this thing emits
    luminescence: usize,

    opacity: f64,

    pub const AIR_SPECIFIC_HEAT = 200.5;
    pub const AIR_DENSITY = 0.012;

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
    MetaError, // Player tried to do something invalid.
    Status, // A status effect was added or removed.
    Info,
    Move,
    Trap,
    Damage,
    SpellCast,

    pub fn color(self: MessageType) u32 {
        return switch (self) {
            .Prompt => 0x34cdff, // cyan blue
            .MetaError => 0xffffff, // white
            .Info => 0xfafefa, // creamy white
            .Move => 0xfafefe, // creamy white
            .Trap => 0xed254d, // pinkish red
            .Damage => 0xed254d, // pinkish red
            .SpellCast => 0xff7750, // golden yellow
            .Status => 0x7fffd4, // aquamarine
        };
    }
};

pub const Damage = struct {
    amount: f64,
    by_mob: ?*Mob = null,
    source: DamageSource = .Other,
    blood: bool = true,

    // by_mob isn't null, but the damage done wasn't done in melee, ranged,
    // or spell attack. E.g., it could have been a fire or explosion caused by
    // by_mob.
    indirect: bool = false,

    pub const DamageSource = enum {
        Other, MeleeAttack, RangedAttack, Stab, Explosion
    };
};
pub const Activity = union(enum) {
    Interact,
    Rest,
    Move: Direction,
    Attack: struct { coord: Coord, weapon_delay: usize },
    Teleport: Coord,
    Grab,
    Drop,
    Use,
    Throw,
    Fire,
    Cast,

    pub inline fn cost(self: Activity) usize {
        return switch (self) {
            .Interact => 90,
            .Rest, .Move, .Teleport, .Grab, .Drop, .Use => 100,
            .Cast, .Throw, .Fire => 120,
            .Attack => |a| 120 * a.weapon_delay / 100,
        };
    }
};

pub const EnemyRecord = struct {
    mob: *Mob,
    last_seen: Coord,
    counter: usize,
};

pub const Message = struct {
    msg: [128:0]u8,
    type: MessageType,
    turn: usize,
    dups: usize = 0,
};

pub const Allegiance = enum {
    Necromancer,
    OtherGood, // Humans in the plains
    OtherEvil, // Cave goblins, southern humans
};

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
            .Echolocation => "echolocating",
            .Corona => "glowing",
            .Daze => "dazed",
            .Confusion => "confused",
            .Fast => "hasted",
            .Slow => "slowed",
            .Recuperate => "recuperating",
            .Poison => "poisoned",
            .Invigorate => "invigorated",
            .Pain => "tormented",
            .Fear => "fearful",
            .Backvision => "reverse-sighted",
            .NightVision => "night-sighted",
            .DayBlindness => "day-blinded",
            .NightBlindness => "night-blinded",
        };
    }

    pub fn messageWhenAdded(self: Status) ?[3][]const u8 {
        return switch (self) {
            .Paralysis => .{ "are", "is", " paralyzed" },
            .Held => .{ "are", "is", " entangled" },
            .Corona => .{ "begin", "starts", " glowing" },
            .Daze => .{ "are lost in", "stumbles around in", " a daze" },
            .Confusion => .{ "are", "looks", " confused" },
            .Fast => .{ "feel yourself", "starts", " moving faster" },
            .Slow => .{ "feel yourself", "starts", " moving slowly" },
            .Poison => .{ "feel very", "looks very", " sick" },
            .Invigorate => .{ "feel", "looks", " invigorated" },
            .Pain => .{ "are", "is", " wracked with pain" },
            .Fear => .{ "feel", "looks", " troubled" },
            .Echolocation => null,
            .Recuperate => null,
            .NightVision,
            .Backvision,
            .NightBlindness,
            .DayBlindness,
            => err.wat(),
        };
    }

    pub fn messageWhenRemoved(self: Status) ?[3][]const u8 {
        return switch (self) {
            .Paralysis => .{ "can move again", "starts moving again", "" },
            .Held => .{ "break", "breaks", " free" },
            .Corona => .{ "stop", "stops", " glowing" },
            .Daze => .{ "break out of your daze", "breaks out of their daze", "" },
            .Confusion => .{ "are no longer", "no longer looks", " confused" },
            .Fast => .{ "are no longer", "is no longer", " moving faster" },
            .Slow => .{ "are no longer", "is no longer", " moving slowly" },
            .Poison => .{ "feel", "looks", " healtheir" },
            .Invigorate => .{ "no longer feel", "no longer looks", " invigorated" },
            .Pain => .{ "are no longer", "is no longer", " wracked with pain" },
            .Fear => .{ "no longer feel", "no longer looks", " troubled" },
            .Echolocation => null,
            .Recuperate => null,
            .NightVision,
            .Backvision,
            .NightBlindness,
            .DayBlindness,
            => err.wat(),
        };
    }

    pub fn tickPoison(mob: *Mob) void {
        mob.takeDamage(.{
            .amount = @intToFloat(f64, rng.rangeClumping(usize, 0, 2, 2)),
            .blood = false,
        });
    }

    pub fn tickPain(mob: *Mob) void {
        const st = mob.isUnderStatus(.Pain).?;

        mob.makeNoise(.Scream, .Louder);
        mob.takeDamage(.{
            .amount = @intToFloat(f64, rng.rangeClumping(usize, 1, st.power, 2)),
            .blood = false,
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

        var tile: state.MemoryTile = .{ .fg = 0xffffff, .ch = '#', .type = .Echolocated };

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
                    &fba.allocator,
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
};

pub const StatusData = struct {
    // What's the "power" of a status (percentage). For some statuses, doesn't
    // mean anything at all.
    power: usize = 0, // What's the "power" of the status

    // How long the status should last. Decremented each turn.
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
    held_by: ?union(enum) { Mob: *const Mob, Prop: *const Prop } = null,

    pub fn heldAt(self: *const Prisoner) Coord {
        assert(self.held_by != null);

        return switch (self.held_by.?) {
            .Mob => |m| m.coord,
            .Prop => |p| p.coord,
        };
    }
};

pub const Mob = struct { // {{{
    // linked list stuff
    __next: ?*Mob = null,
    __prev: ?*Mob = null,

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
    killed_by: ?*Mob = null,

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
    // unbreathing:        Controls whether a mob is susceptible to a gas' effect.
    //
    willpower: usize, // Range: 0 < willpower < 10
    base_strength: usize,
    base_dexterity: usize, // Range: 0 < dexterity < 100
    vision: usize = 7,
    base_night_vision: usize = 20, // Range: 0 < night_vision < 100
    deg360_vision: bool = false,
    no_show_fov: bool = false,
    hearing: usize,
    memory_duration: usize,
    base_speed: usize,
    max_HP: f64,
    regen: f64 = 0.14,
    blood: ?Spatter,
    immobile: bool = false,
    unbreathing: bool = false,
    spells: StackBuffer(SpellInfo, 2) = StackBuffer(SpellInfo, 2).init(null),

    pub const Inventory = struct {
        pack: PackBuffer = PackBuffer.init(&[_]Item{}),

        rings: [4]?*Ring = [4]?*Ring{ null, null, null, null },

        armor: ?*Armor = null,
        wielded: ?*Weapon = null,
        backup: ?*Weapon = null,

        pub const PACK_SIZE: usize = 10;
        pub const PackBuffer = StackBuffer(Item, PACK_SIZE);
    };

    // Size of `activities` Ringbuffer
    pub const MAX_ACTIVITY_BUFFER_SZ = 4;

    pub fn displayName(self: *Mob) []const u8 {
        return self.ai.profession_name orelse self.species;
    }

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
            if ((!self.unbreathing or gas.Gases[gasi].not_breathed) and quantity > 0.0) {
                gas.Gases[gasi].trigger(self, quantity);
            }
        }
    }

    // Update the status powers for the rings
    pub fn tickRings(self: *Mob) void {
        for (self.inventory.rings) |maybe_ring| {
            if (maybe_ring) |ring|
                self.addStatus(ring.status, ring.currentPower(), Status.MAX_DURATION, false);
        }
    }

    // Decrement status durations, and do stuff for various statuses that need
    // babysitting each turn.
    pub fn tickStatuses(self: *Mob) void {
        inline for (@typeInfo(Status).Enum.fields) |status| {
            const status_e = @field(Status, status.name);

            if (self.isUnderStatus(status_e)) |status_data| {
                if (self == state.player) {
                    state.chardata.time_with_statuses.getPtr(status_e).* += 1;
                }

                // Decrement
                self.addStatus(status_e, status_data.power, utils.saturating_sub(status_data.duration, 1), status_data.permanent);

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

        return self.inventory.pack.orderedRemove(index) catch err.wat();
    }

    // Quaff a potion, applying its effects to a Mob.
    //
    // direct: was the potion quaffed directly (i.e., was it thrown at the
    //   mob or did the mob quaff it?). Used to determine whether to print a
    //   message.
    pub fn quaffPotion(self: *Mob, potion: *Potion, direct: bool) void {
        if (direct) {
            if (self == state.player) {
                state.message(.Info, "You slurp the potion of {}.", .{potion.name});
            } else if (state.player.cansee(self.coord)) {
                state.message(.Info, "The {} quaffs a potion of {}!", .{
                    self.displayName(), potion.name,
                });
            }
        }

        // TODO: make the duration of potion status effect random (clumping, ofc)
        switch (potion.type) {
            .Status => |s| self.addStatus(s, 0, Status.MAX_DURATION, false),
            .Gas => |s| state.dungeon.atGas(self.coord)[s] = 1.0,
            .Custom => |c| c(self, self.coord),
        }
    }

    pub fn evokeOrRest(self: *Mob, evocable: *Evocable) void {
        evocable.evoke(self) catch |_| {
            _ = self.rest();
            return;
        };

        self.declareAction(.Use);
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
                bastard.takeDamage(.{
                    .amount = @intToFloat(f64, damage),
                    .source = .RangedAttack,
                });
            }
        }

        if (launcher.projectile.effect) |effect_func| (effect_func)(landed.?);

        self.declareAction(.Fire);
        self.makeNoise(.Combat, .Medium);

        return true;
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

    pub fn throwItem(self: *Mob, item: *Item, at: Coord) bool {
        switch (item.*) {
            .Potion => {},
            .Weapon => err.todo(),
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
            .Weapon => |_| err.todo(),
            .Potion => |potion| {
                if (!potion.ingested) {
                    if (state.dungeon.at(landed.?).mob) |bastard| {
                        bastard.quaffPotion(potion, false);
                    } else switch (potion.type) {
                        .Status => {},
                        .Gas => |s| state.dungeon.atGas(landed.?)[s] = 1.0,
                        .Custom => |f| f(null, landed.?),
                    }
                }

                // TODO: have cases where thrower misses and potion lands (unused?)
                // in adjacent square
            },
            else => err.wat(),
        }

        return true;
    }

    pub fn declareAction(self: *Mob, action: Activity) void {
        assert(!self.is_dead);
        self.activities.append(action);
        self.energy -= @divTrunc(self.speed() * @intCast(isize, action.cost()), 100);
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
    }

    // Check if a mob, when trying to move into a space that already has a mob,
    // can swap with that other mob. Return true if:
    //     - The mob's strength is greater than the other mob's strength.
    //     - The mob's speed is greater than the other mob's speed.
    //     - The other mob didn't try to move in the past turn.
    //     - The other mob was trying to move in the opposite direction, i.e.,
    //       both mobs were trying to shuffle past each other.
    //     - The mob wasn't working (e.g., may have been attacking), but the other
    //       one was.
    //     - The mob is the player and the other mob is a noncombative enemy (e.g.,
    //       slaves). The player has no business attacking non-combative enemies.
    //
    // Return false if:
    //     - The other mob was trying to move in the same direction. No need to barge
    //       past, it'll move soon enough.
    //     - The other mob is the player. No mob should be able to swap with the player.
    //     - The other mob is immobile (e.g., a statue).
    //     - The other mob is a prisoner that's tied up somewhere.
    //
    // TODO: cleanup this, express login in a cleaner way.
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
        if (other.prisoner_status) |ps|
            if (ps.held_by != null) {
                can = false;
            };

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

        // This should have been handled elsewhere (in the pathfinding code
        // for monsters, or in main:moveOrFight() for the player).
        //
        if (direction.is_diagonal() and self.isUnderStatus(.Confusion) != null)
            err.bug("Confused mob is trying to move diagonally!", .{});

        if (self.isUnderStatus(.Daze)) |_|
            direction = rng.chooseUnweighted(Direction, &DIRECTIONS);

        // Face in that direction and update last_attempted_move, no matter
        // whether we end up moving or no
        self.facing = direction;
        self.last_attempted_move = direction;

        var succeeded = false;
        if (coord.move(direction, state.mapgeometry)) |dest| {
            succeeded = self.teleportTo(dest, direction);
        } else {
            succeeded = false;
        }

        if (!succeeded and self.isUnderStatus(.Daze) != null) {
            if (self == state.player) {
                state.message(.Info, "You stumble around in a daze.", .{});
            } else if (state.player.cansee(self.coord)) {
                state.message(.Info, "The {} stumbles around in a daze.", .{self.displayName()});
            }

            _ = self.rest();
            return true;
        } else return succeeded;
    }

    pub fn teleportTo(self: *Mob, dest: Coord, direction: ?Direction) bool {
        const coord = self.coord;

        if (self.prisoner_status) |prisoner|
            if (prisoner.held_by != null)
                return false;

        if (!state.is_walkable(dest, .{ .right_now = true, .ignore_mobs = true })) {
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

        if (!self.isCreeping()) self.makeNoise(.Movement, .Medium);

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

        const attacker_weapon = attacker.inventory.wielded orelse &items.UnarmedWeapon;

        attacker.declareAction(.{
            .Attack = .{ .coord = recipient.coord, .weapon_delay = attacker_weapon.delay },
        });

        // If the defender didn't know about the attacker's existence now's a
        // good time to find out
        ai.updateEnemyRecord(recipient, .{
            .mob = attacker,
            .counter = recipient.memory_duration,
            .last_seen = attacker.coord,
        });

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

        if (!hit) {
            if (attacker == state.player) {
                state.message(.Info, "You miss the {}.", .{recipient.displayName()});
            } else if (recipient == state.player) {
                state.message(.Info, "The {} misses you.", .{attacker.displayName()});
            } else {
                const cansee_a = state.player.cansee(attacker.coord);
                const cansee_r = state.player.cansee(recipient.coord);

                if (cansee_a or cansee_r) {
                    state.message(.Info, "{}{} misses {}{}.", .{
                        if (cansee_a) @as([]const u8, "The ") else "",
                        if (cansee_a) attacker.displayName() else "Something",
                        if (cansee_r) @as([]const u8, "the ") else "",
                        if (cansee_r) recipient.displayName() else "something",
                    });
                }
            }

            return;
        }

        const is_stab = !recipient.isAwareOfAttack(attacker.coord);
        const damage = combat.damageOutput(attacker, recipient, is_stab);

        recipient.takeDamage(.{
            .amount = @intToFloat(f64, damage),
            .source = if (is_stab) .Stab else .MeleeAttack,
            .by_mob = attacker,
        });

        // Daze stabbed mobs.
        if (is_stab) {
            recipient.addStatus(.Daze, 0, rng.range(usize, 3, 5), false);
        }

        // XXX: should this be .Loud instead of .Medium?
        if (!is_stab) {
            attacker.makeNoise(.Combat, .Medium);
            recipient.makeNoise(.Combat, .Medium);
        }

        var dmg_percent = recipient.lastDamagePercentage();
        var hitstrs = attacker_weapon.strs[attacker_weapon.strs.len - 1];
        // FIXME: insert some randomization here. Currently every single stab
        // the player makes results in "You puncture the XXX like a sieve!!!!"
        // which gets boring after a bit.
        {
            for (attacker_weapon.strs) |strset, i| {
                if (strset.dmg_percent > dmg_percent) {
                    hitstrs = strset;
                    break;
                }
            }
        }

        var punctuation: []const u8 = ".";
        if (dmg_percent >= 20) punctuation = "!";
        if (dmg_percent >= 40) punctuation = "!!";
        if (dmg_percent >= 60) punctuation = "!!!";
        if (dmg_percent >= 80) punctuation = "!!!!";

        if (recipient.coord.eq(state.player.coord)) {
            state.message(.Info, "The {} {} you{}{} ({}% dmg)", .{
                attacker.displayName(),
                hitstrs.verb_other,
                hitstrs.verb_degree,
                punctuation,
                dmg_percent,
            });
        } else if (attacker.coord.eq(state.player.coord)) {
            state.message(.Info, "You {} the {}{}{} ({}% dmg)", .{
                hitstrs.verb_self,
                recipient.displayName(),
                hitstrs.verb_degree,
                punctuation,
                dmg_percent,
            });
        } else {
            const cansee_a = state.player.cansee(attacker.coord);
            const cansee_r = state.player.cansee(recipient.coord);

            // XXX: this and the above "something misses something" message
            // thing will print stuff like "The Something misses the goblin!" I
            // suspect this is a miscompilation, because test code runs fine
            // otherwise. Must check after upgrading to Zig v9.
            //
            // FIXME TODO
            if (cansee_a or cansee_r) {
                state.message(.Info, "{}{} {} {}{}{}{} ({}% dmg)", .{
                    if (cansee_a) @as([]const u8, "The ") else "",
                    if (cansee_a) attacker.displayName() else "Something",
                    hitstrs.verb_other,
                    if (cansee_r) @as([]const u8, "the ") else "",
                    if (cansee_r) recipient.displayName() else "something",
                    hitstrs.verb_degree,
                    punctuation,
                    dmg_percent,
                });
            }
        }
    }

    pub fn takeDamage(self: *Mob, d: Damage) void {
        const was_already_dead = self.should_be_dead();

        self.HP = math.clamp(self.HP - d.amount, 0, self.max_HP);
        if (d.blood) if (self.blood) |s| state.dungeon.spatter(self.coord, s);
        self.last_damage = d;

        if (!was_already_dead and self.HP == 0 and d.by_mob != null) {
            self.killed_by = d.by_mob.?;
            if (d.by_mob == state.player) {
                state.chardata.foes_killed_total += 1;
                if (d.source == .Stab) state.chardata.foes_stabbed += 1;

                const prevtotal = (state.chardata.foes_killed.getOrPutValue(self.displayName(), 0) catch err.wat()).value;
                state.chardata.foes_killed.put(self.displayName(), prevtotal + 1) catch err.wat();
            }
        }
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
        if (self != state.player) {
            if (self.killed_by) |by_mob| {
                if (by_mob == state.player) {
                    state.message(.Damage, "You slew the {}.", .{self.displayName()});
                } else if (state.player.cansee(by_mob.coord)) {
                    state.message(.Damage, "The {} killed the {}.", .{ by_mob.displayName(), self.displayName() });
                }
            } else {
                if (state.player.cansee(self.coord)) {
                    state.message(.Damage, "The {} dies.", .{self.displayName()});
                }
            }
        }

        self.deinit();
    }

    // Separate from kill() because some code (e.g., mapgen) cannot rely on the player
    // having been initialized.
    pub fn deinit(self: *Mob) void {
        self.squad_members.deinit();
        self.enemies.deinit();
        self.path_cache.clearAndFree();
        self.ai.work_area.deinit();

        self.is_dead = true;

        if (state.dungeon.itemsAt(self.coord).isFull())
            _ = state.dungeon.itemsAt(self.coord).orderedRemove(0) catch err.wat();

        state.dungeon.itemsAt(self.coord).append(Item{ .Corpse = self }) catch err.wat();

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

        const is_confused = self.isUnderStatus(.Confusion) != null;

        // Cannot move if you're a prisoner (unless you're moving one space away)
        if (self.prisoner_status) |p|
            if (p.held_by != null and p.heldAt().distance(to) > 1)
                return null;

        if (!is_confused) {
            if (Direction.from_coords(self.coord, to)) |direction| {
                return direction;
            } else |_err| {}
        }

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
                if (is_confused) &CARDINAL_DIRECTIONS else &DIRECTIONS,
                &fba.allocator,
            ) orelse return null;

            assert(pth.items[0].eq(self.coord));
            var last: Coord = self.coord;
            for (pth.items[1..]) |coord| {
                self.path_cache.put(Path{ .from = last, .to = to }, coord) catch err.wat();
                last = coord;
            }
            assert(last.eq(to));

            pth.deinit();
        }

        // Return the next direction, ensuring that the next tile is walkable.
        // If it is not, set the path to null, ensuring that the path will be
        // recalculated next time.
        if (self.path_cache.get(pathobj)) |next| {
            const direction = Direction.from_coords(self.coord, next) catch err.wat();
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
        const had_status_before = self.isUnderStatus(status) != null;

        const p_se = self.statuses.getPtr(status);
        p_se.power = power;
        p_se.duration = duration orelse Status.MAX_DURATION;
        p_se.permanent = permanent;

        const has_status_now = self.isUnderStatus(status) != null;

        var msg_parts: ?[3][]const u8 = null;

        if (had_status_before and !has_status_now) {
            msg_parts = status.messageWhenRemoved();
        } else if (!had_status_before and has_status_now) {
            msg_parts = status.messageWhenAdded();
        }

        if (msg_parts) |_| {
            if (self == state.player) {
                state.message(.Status, "You {}{}.", .{ msg_parts.?[0], msg_parts.?[2] });
            } else if (state.player.cansee(self.coord)) {
                state.message(.Status, "The {} {}{}.", .{
                    self.displayName(), msg_parts.?[1], msg_parts.?[2],
                });
            }
        }
    }

    pub fn isUnderStatus(self: *const Mob, status: Status) ?*const StatusData {
        const se = self.statuses.getPtrConst(status);
        return if (se.permanent or se.duration == 0) null else se;
    }

    pub fn lastDamagePercentage(self: *const Mob) usize {
        if (self.last_damage) |dam| {
            return @floatToInt(usize, (dam.amount * 100) / self.max_HP);
        } else {
            return 0;
        }
    }

    // Check if a mob is capable of dodging an attack. Return false if:
    //  - Mob was in .Work AI phase
    //  - Is in Investigate/Hunt phase and:
    //    - is incapitated by a status effect (e.g. Paralysis)
    //
    // Player is always aware of attacks. Stabs are there in the first place
    // to "reward" the player for catching a hostile off guard, but allowing
    // enemies to stab a paralyzed player is too harsh of a punishment.
    //
    pub fn isAwareOfAttack(self: *const Mob, attacker: Coord) bool {
        if (self.coord.eq(state.player.coord))
            return true;

        return switch (self.ai.phase) {
            .Flee, .Hunt, .Investigate => b: {
                if (self.isUnderStatus(.Paralysis)) |_| break :b false;
                if (self.isUnderStatus(.Daze)) |_| break :b false;

                if (self.ai.phase == .Flee and !self.cansee(attacker)) {
                    break :b false;
                } else {
                    break :b true;
                }
            },
            .Work => false,
        };
    }

    pub fn canHear(self: *const Mob, coord: Coord) ?*Sound {
        const sound = state.dungeon.soundAt(coord);

        if (self.coord.z != coord.z)
            return null; // Can't hear across levels

        if (sound.state == .Dead or sound.intensity == .Silent)
            return null; // Sound was made a while back, or is silent

        // If there are a lot of walls in the way, quiet the noise
        const line = self.coord.drawLine(coord, state.mapgeometry);
        var walls_in_way: usize = 0;
        for (line.constSlice()) |c| {
            if (state.dungeon.at(c).type == .Wall) {
                walls_in_way += 1;
            }
        }

        const radius = utils.saturating_sub(sound.intensity.radiusHeard(), walls_in_way);
        if (self != state.player) // Player can always hear sounds
            if (self.coord.distance(coord) > radius)
                return null; // Too far away

        return sound;
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
        var speed_perc: isize = 100;
        if (self.ai.phase == .Flee) speed_perc -= 10;
        if (self.isUnderStatus(.Fast)) |_| speed_perc = @divTrunc(speed_perc * 50, 100);
        if (self.isUnderStatus(.Slow)) |_| speed_perc = @divTrunc(speed_perc * 160, 100);

        if (self.inventory.armor) |a|
            if (a.speed_penalty) |pen| {
                speed_perc += @intCast(isize, pen);
            };

        return @divTrunc(@intCast(isize, self.base_speed) * math.max(0, speed_perc), 100);
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
        if (self.inventory.armor) |a|
            if (a.dex_penalty) |pen| {
                dex = dex * pen / 100;
            };
        return dex;
    }

    pub fn isCreeping(self: *const Mob) bool {
        return self.turnsSpentMoving() < self.activities.len;
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

    interact1: ?MachInteract = null,

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

    pub const MachInteract = struct {
        name: []const u8,
        used: usize = 0,
        max_use: usize, // 0 for infinite uses
        func: fn (*Machine, *Mob) bool,
    };

    pub fn evoke(self: *Machine, mob: *Mob, interaction: *MachInteract) !void {
        if (!self.isPowered())
            return error.NotPowered;

        if (interaction.max_use > 0 and interaction.used >= interaction.max_use)
            return error.UsedMax;

        if ((interaction.func)(self, mob)) {
            interaction.used += 1;
        } else return error.NoEffect;
    }

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
    // linked list stuff
    __next: ?*Prop = null,
    __prev: ?*Prop = null,

    id: []const u8,
    name: []const u8,
    tile: u21,
    fg: ?u32 = null,
    bg: ?u32 = null,
    walkable: bool = true,
    opacity: f64 = 0.0,
    holder: bool = false, // Can a prisoner be held to it?
    coord: Coord = Coord.new(0, 0),

    pub fn deinit(self: *const Prop, alloc: *mem.Allocator) void {
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
        Eatables, // All food
        Wearables, // Weapons, armor, clothing, thread, cloth
        VOres, // self-explanatory
        Casual, // dice, deck of cards
        Utility, // Depends on the level (for PRI: rope, chains, etc)
    };
};

pub const SurfaceItemTag = enum { Machine, Prop, Container, Poster };
pub const SurfaceItem = union(SurfaceItemTag) {
    Machine: *Machine,
    Prop: *Prop,
    Container: *Container,
    Poster: *const Poster,
};

// Each weapon and armor has a specific amount of maximum damage it can create
// or prevent. That damage comes in several different types:
//      - Crushing: clubs, maces, morningstars, battleaxes, warhammers.
//      - Slashing: swords, battleaxes.
//      - Pulping: morningstars.
//      - Puncture: spears, daggers, swords, warhammers.
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

pub const DamageStr = struct {
    dmg_percent: usize,
    verb_self: []const u8,
    verb_other: []const u8,
    verb_degree: []const u8,
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
    // linked list stuff
    __next: ?*Armor = null,
    __prev: ?*Armor = null,

    id: []const u8,
    name: []const u8,
    resists: Damages,
    speed_penalty: ?usize = null,
    dex_penalty: ?usize = null,
};

pub const Projectile = struct {
    main_damage: DamageType,
    damages: Damages,
    effect: ?fn (Coord) void = null,
};

pub const Weapon = struct {
    // linked list stuff
    __next: ?*Weapon = null,
    __prev: ?*Weapon = null,

    id: []const u8,
    name: []const u8,
    required_strength: usize,
    required_dexterity: usize,
    delay: usize = 100, // Percentage (100 = normal speed, 200 = twice as slow)
    damages: Damages,
    main_damage: DamageType,
    secondary_damage: ?DamageType,
    launcher: ?Launcher = null,
    strs: []const DamageStr,

    pub const Launcher = struct {
        projectile: Projectile,
    };
};

pub const Potion = struct {
    // linked list stuff
    __next: ?*Potion = null,
    __prev: ?*Potion = null,

    id: []const u8,

    // Potion of <name>
    name: []const u8,

    type: union(enum) {
        Status: Status,
        Gas: usize,
        Custom: fn (?*Mob, Coord) void,
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
    // linked list stuff
    __next: ?*Ring = null,
    __prev: ?*Ring = null,

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
    Corpse, Ring, Potion, Vial, Armor, Weapon, Boulder, Prop, Evocable
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
    Evocable: *Evocable,

    // Should we announce the item to the player when we find it?
    pub fn announce(self: Item) bool {
        return switch (self) {
            .Corpse, .Vial, .Boulder, .Prop => false,
            .Ring, .Potion, .Armor, .Weapon, .Evocable => true,
        };
    }

    // FIXME: can't we just return the constSlice() of the stack buffer?
    pub fn shortName(self: *const Item) !StackBuffer(u8, 64) {
        var buf = StackBuffer(u8, 64).init(&([_]u8{0} ** 64));
        var fbs = std.io.fixedBufferStream(buf.slice());
        switch (self.*) {
            .Corpse => |c| try fmt.format(fbs.writer(), "%{}", .{c.species}),
            .Ring => |r| try fmt.format(fbs.writer(), "*{}", .{r.name}),
            .Potion => |p| try fmt.format(fbs.writer(), "¡{}", .{p.name}),
            .Vial => |v| try fmt.format(fbs.writer(), "♪{}", .{v.name()}),
            .Armor => |a| try fmt.format(fbs.writer(), "]{}", .{a.name}),
            .Weapon => |w| try fmt.format(fbs.writer(), "){}", .{w.name}),
            .Boulder => |b| try fmt.format(fbs.writer(), "•{} of {}", .{ b.chunkName(), b.name }),
            .Prop => |b| try fmt.format(fbs.writer(), "{}", .{b.name}),
            .Evocable => |v| try fmt.format(fbs.writer(), "}}{}", .{v.name}),
        }
        buf.resizeTo(@intCast(usize, fbs.getPos() catch err.wat()));
        return buf;
    }

    // FIXME: can't we just return the constSlice() of the stack buffer?
    pub fn longName(self: *const Item) !StackBuffer(u8, 128) {
        var buf = StackBuffer(u8, 128).init(&([_]u8{0} ** 128));
        var fbs = std.io.fixedBufferStream(buf.slice());
        switch (self.*) {
            .Corpse => |c| try fmt.format(fbs.writer(), "{} corpse", .{c.species}),
            .Ring => |r| try fmt.format(fbs.writer(), "ring of {}", .{r.name}),
            .Potion => |p| try fmt.format(fbs.writer(), "potion of {}", .{p.name}),
            .Vial => |v| try fmt.format(fbs.writer(), "vial of {}", .{v.name()}),
            .Armor => |a| try fmt.format(fbs.writer(), "{} armor", .{a.name}),
            .Weapon => |w| try fmt.format(fbs.writer(), "{}", .{w.name}),
            .Boulder => |b| try fmt.format(fbs.writer(), "{} of {}", .{ b.chunkName(), b.name }),
            .Prop => |b| try fmt.format(fbs.writer(), "{}", .{b.name}),
            .Evocable => |v| try fmt.format(fbs.writer(), "{}", .{v.name}),
        }
        buf.resizeTo(@intCast(usize, fbs.getPos() catch err.wat()));
        return buf;
    }
};

pub const TileType = enum {
    Wall,
    Floor,
    Water,
    Lava,
    BrokenWall,
    BrokenFloor,
};

pub const Tile = struct {
    marked: bool = false,
    prison: bool = false,
    type: TileType = .Wall,
    material: *const Material = &materials.Basalt,
    mob: ?*Mob = null,
    surface: ?SurfaceItem = null,
    spatter: SpatterArray = SpatterArray.initFill(0),

    // A random value that's set at the beginning of the game.
    // To be used when a random value that's specific to a coordinate, but that
    // won't change over time, is needed.
    rand: usize = 0,

    pub fn displayAs(coord: Coord, ignore_lights: bool) termbox.tb_cell {
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
                .bg = self.material.color_bg orelse 0x000000,
            },
            .Floor => {
                cell.ch = '·';
                cell.fg = 0xcacbca;
            },
            .BrokenFloor, .BrokenWall => {
                cell.fg = 0xcacbca;

                const chars = [_]u32{ '`', ',', '^', '\'', '*', '"' };
                if (self.rand % 100 < 15) {
                    cell.ch = chars[self.rand % chars.len];
                } else {
                    cell.ch = '·';
                }
            },
        }

        if (self.mob) |mob| {
            assert(self.type != .Wall);

            cell.fg = switch (mob.ai.phase) {
                .Work, .Flee => 0xffffff,
                .Investigate => 0xffd700,
                .Hunt => 0xffbbbb,
            };
            if (mob == state.player or
                mob.isUnderStatus(.Paralysis) != null or
                mob.isUnderStatus(.Daze) != null)
                cell.fg = 0xffffff;

            const hp_loss_percent = 100 - (mob.HP * 100 / mob.max_HP);
            if (hp_loss_percent > 0) {
                const red = @floatToInt(u32, (255 * hp_loss_percent) / 100) + 0x66;
                cell.bg = math.clamp(red, 0x66, 0xff) << 16;
            }

            if (mob.prisoner_status) |ps| {
                if (state.dungeon.at(coord).prison or ps.held_by != null) {
                    cell.fg = 0xffcfff;
                }
            }

            cell.ch = mob.tile;
        } else if (state.dungeon.itemsAt(coord).last()) |item| {
            assert(self.type != .Wall);

            cell.fg = 0xffffff;

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
                .Ring => |_| {
                    cell.ch = '*';
                },
                .Weapon => |_| {
                    cell.ch = ')';
                },
                .Armor => |_| {
                    cell.ch = '[';
                },
                .Boulder => |b| {
                    cell.ch = b.chunkTile();
                    cell.fg = b.color_floor;
                },
                .Prop => |p| {
                    cell.ch = p.tile;
                    cell.fg = p.fg orelse 0xffffff;
                },
                .Evocable => |v| {
                    cell.ch = '}';
                    cell.fg = v.tile_fg;
                },
            }
        } else if (state.dungeon.at(coord).surface) |surfaceitem| {
            assert(self.type != .Wall);

            cell.fg = 0xffffff;

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
                .Poster => |p| poster: {
                    cell.fg = self.material.color_bg orelse self.material.color_fg;
                    break :poster '?';
                },
            };

            cell.ch = ch;
        }

        if (!ignore_lights and self.type != .Wall) {
            const light = state.dungeon.lightIntensityAt(coord).*;
            if (light < 20) {
                cell.fg = utils.percentageOfColor(cell.fg, 40);
            }
        }

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
    sound: [LEVELS][HEIGHT][WIDTH]Sound = [1][HEIGHT][WIDTH]Sound{[1][WIDTH]Sound{[1]Sound{.{}} ** WIDTH} ** HEIGHT} ** LEVELS,
    light_intensity: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT} ** LEVELS,

    pub const ItemBuffer = StackBuffer(Item, 7);

    pub fn emittedLightIntensity(self: *Dungeon, coord: Coord) usize {
        const tile: *Tile = state.dungeon.at(coord);

        var l: usize = 0;

        if (tile.type == .Lava)
            l += 80;

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

    pub inline fn soundAt(self: *Dungeon, c: Coord) *Sound {
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
    not_breathed: bool = false, // if true, will affect nonbreathing mobs
    id: usize,
    residue: ?Spatter = null,
};
