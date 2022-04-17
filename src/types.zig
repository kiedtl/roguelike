const std = @import("std");
const math = std.math;
const mem = std.mem;
const meta = std.meta;
const fmt = std.fmt;
const assert = std.debug.assert;
const enums = std.enums;

const LinkedList = @import("list.zig").LinkedList;
const RingBuffer = @import("ringbuffer.zig").RingBuffer;
const StackBuffer = @import("buffer.zig").StackBuffer;

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
const spells = @import("spells.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const termbox = @import("termbox.zig");
const utils = @import("utils.zig");

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const Evocable = @import("items.zig").Evocable;
const Projectile = @import("items.zig").Projectile;
const Cloak = @import("items.zig").Cloak;

const Sound = @import("sound.zig").Sound;
const SoundIntensity = @import("sound.zig").SoundIntensity;
const SoundType = @import("sound.zig").SoundType;

const SpellOptions = spells.SpellOptions;
const Spell = spells.Spell;
const Poster = literature.Poster;

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
            insert_if_valid(from.z, x, y, &buf, limit);
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
    CombatUnimportant, // X missed you! You miss X!
    Unimportant, // A bit dark, okay if player misses it.
    Info,
    Move,
    Trap,
    Damage,
    SpellCast,

    pub fn color(self: MessageType) u32 {
        return switch (self) {
            .Prompt => 0x34cdff, // cyan blue
            .Info => 0xdadeda, // creamy white
            .Move => 0xdadeda, // creamy white
            .Trap => 0xed254d, // pinkish red
            .Damage => 0xed254d, // pinkish red
            .SpellCast => 0xff7750, // golden yellow
            .Status => colors.AQUAMARINE, // aquamarine
            .Combat => 0xdadeda, // creamy white
            .CombatUnimportant => 0x7a9cc7, // steel blue
            .Unimportant => 0x8019ac,
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
    };

    pub const DamageSource = enum { Other, MeleeAttack, RangedAttack, Stab, Explosion };
};
pub const Activity = union(enum) {
    Interact,
    Rest,
    Move: Direction,
    Attack: struct {
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
            .Interact => 90,
            .Rest, .Move, .Teleport, .Grab, .Drop, .Use => 100,
            .Cast, .Throw, .Fire => 120,
            .Attack => |a| 120 * a.delay / 100,
            .None => err.wat(),
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
    // Gives a free attack after evading an attack.
    //
    // Doesn't have a power field.
    Riposte,

    // Evade, Melee, and Missile nerfs.
    //
    // Doesn't have a power field.
    Stun,

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

    pub const MAX_DURATION: usize = 20;

    pub fn string(self: Status, mob: *const Mob) []const u8 {
        return switch (self) {
            .Riposte => "riposte",
            .Stun => "stunned",
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
            .Fear => "fearful",
            .Backvision => "reverse-sighted",
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
    }

    pub fn messageWhenAdded(self: Status) ?[3][]const u8 {
        return switch (self) {
            .Riposte => null,
            .Stun => .{ "are", "is", " stunned" },
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
            .Fear => .{ "feel", "looks", " troubled" },
            .Shove => .{ "begin", "starts", " violently shoving past foes" },
            .Enraged => .{ "fly", "flies", " into a rage" },
            .Exhausted => .{ "feel", "looks", " exhausted" },
            .Lifespan => null,
            .Explosive => null,
            .ExplosiveElec => null,
            .Echolocation => null,
            .Recuperate => null,
            .NightVision,
            .Backvision,
            .NightBlindness,
            .DayBlindness,
            => null,
        };
    }

    pub fn messageWhenRemoved(self: Status) ?[3][]const u8 {
        return switch (self) {
            .Riposte => null,
            .Stun => .{ "are no longer", "is no longer", " stunned" },
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
            .Fear => .{ "no longer feel", "no longer looks", " troubled" },
            .Shove => .{ "stop", "stops", " shoving past foes" },
            .Enraged => .{ "stop", "stops", " raging" },
            .Exhausted => .{ "are no longer", "is no longer", " exhausted" },
            .Explosive => null,
            .ExplosiveElec => null,
            .Lifespan => null,
            .Echolocation => null,
            .Recuperate => null,
            .NightVision,
            .Backvision,
            .NightBlindness,
            .DayBlindness,
            => null,
        };
    }

    pub fn tickNoisy(mob: *Mob) void {
        if (mob.isUnderStatus(.Sleeping) == null)
            mob.makeNoise(.Movement, .Medium);
    }

    pub fn tickRecuperate(mob: *Mob) void {
        mob.HP = math.clamp(mob.HP + 1, 0, mob.max_HP);
    }

    pub fn tickPoison(mob: *Mob) void {
        mob.takeDamage(.{
            .amount = @intToFloat(f64, rng.range(usize, 0, 1)),
            .blood = false,
            .kind = .Poison,
        });
    }

    pub fn tickNausea(mob: *Mob) void {
        if (state.ticks % 3 == 0) {
            state.messageAboutMob(mob, null, .Status, "retch profusely.", .{}, "retches profusely", .{});
            state.dungeon.spatter(mob.coord, .Vomit);
        }
    }

    pub fn tickFire(mob: *Mob) void {
        if (state.dungeon.terrainAt(mob.coord).fire_retardant) {
            mob.cancelStatus(.Fire);
            return;
        }

        mob.takeDamage(.{
            .amount = @intToFloat(f64, rng.range(usize, 1, 2)),
            .kind = .Fire,
            .blood = false,
        });
        if (state.dungeon.fireAt(mob.coord).* == 0)
            fire.setTileOnFire(mob.coord);
    }

    pub fn tickPain(mob: *Mob) void {
        const st = mob.isUnderStatus(.Pain).?;

        mob.makeNoise(.Scream, .Louder);
        mob.takeDamage(.{
            .amount = @intToFloat(f64, rng.rangeClumping(usize, 0, st.power, 2)),
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
    work_fn: fn (*Mob, mem.Allocator) void,
    fight_fn: ?fn (*Mob, mem.Allocator) void,

    // Should the mob attack hostiles?
    is_combative: bool,

    // Should the mob investigate noises?
    is_curious: bool,

    // Should the mob ever flee at low health?
    is_fearless: bool = false,

    // What should a mage-fighter do when it didn't/couldn't cast a spell?
    //
    // Obviously, only makes sense on mages.
    spellcaster_backup_action: enum { KeepDistance, Melee } = .Melee,

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
};

pub const AIWorkPhase = enum {
    CleanerScan,
    CleanerClean,
    HaulerScan,
    HaulerTake,
    HaulerDrop,
    EngineerScan,
    EngineerRepair,
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
    allegiance: Allegiance,

    squad_members: MobArrayList = undefined,
    prisoner_status: ?Prisoner = null,

    fov: [HEIGHT][WIDTH]usize = [1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT,
    path_cache: std.AutoHashMap(Path, Coord) = undefined,
    enemies: std.ArrayList(EnemyRecord) = undefined,
    allies: MobArrayList = undefined,

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
    memory_duration: usize,
    deaf: bool = false,
    max_HP: f64,
    blood: ?Spatter,
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
        Evade: isize = 10,
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

        rings: [4]?*Ring = [4]?*Ring{ null, null, null, null },

        pub const EquSlot = enum(usize) {
            Weapon = 0,
            Backup = 1,
            Armor = 2,
            Cloak = 3,

            pub fn slotFor(item: Item) EquSlot {
                return switch (item) {
                    .Weapon => .Weapon,
                    .Armor => .Armor,
                    .Cloak => .Cloak,
                    else => err.wat(),
                };
            }

            pub fn name(self: EquSlot) []const u8 {
                return switch (self) {
                    .Weapon => "weapon",
                    .Backup => "backup",
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

    pub fn tickFOV(self: *Mob) void {
        for (self.fov) |*row| for (row) |*cell| {
            cell.* = 0;
        };

        if (self.isUnderStatus(.Sleeping)) |_| return;

        const light_needs = [_]bool{ self.canSeeInLight(false), self.canSeeInLight(true) };

        const vision = @intCast(usize, self.stat(.Vision));
        const energy = math.clamp(vision * Dungeon.FLOOR_OPACITY, 0, 100);
        const direction = if (self.deg360_vision) null else self.facing;

        fov.rayCast(self.coord, vision, energy, Dungeon.tileOpacity, &self.fov, direction, self == state.player);
        if (self.isUnderStatus(.Backvision) != null and direction != null)
            fov.rayCast(self.coord, vision, energy, Dungeon.tileOpacity, &self.fov, direction.?.opposite(), self == state.player);

        for (self.fov) |row, y| for (row) |_, x| {
            if (self.fov[y][x] > 0) {
                const fc = Coord.new2(self.coord.z, x, y);
                const light = state.dungeon.lightAt(fc).*;

                // If a tile is too dim to be seen by a mob and the tile isn't
                // adjacent to that mob, mark it as unlit.
                if (fc.distance(self.coord) > 1 and !light_needs[@boolToInt(light)]) {
                    self.fov[y][x] = 0;
                    continue;
                }
            }
        };
    }

    // Misc stuff.
    pub fn tick_env(self: *Mob) void {
        self.MP = math.clamp(self.MP + 1, 0, self.max_MP);

        const gases = state.dungeon.atGas(self.coord);
        for (gases) |quantity, gasi| {
            if ((rng.range(usize, 0, 100) < self.resistance(.rFume) or gas.Gases[gasi].not_breathed) and quantity > 0.0) {
                gas.Gases[gasi].trigger(self, quantity);
            }
        }
    }

    // Update the status powers for the rings
    pub fn tickRings(self: *Mob) void {
        for (self.inventory.rings) |m_ring| if (m_ring) |ring| {
            self.applyStatus(.{
                .status = ring.status,
                .power = ring.currentPower(),
                .duration = .{ .Tmp = Status.MAX_DURATION },
            }, .{ .add_duration = false });
        };
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

    pub fn swapWeapons(self: *Mob) bool {
        const tmp = self.inventory.equipment(.Weapon).*;
        self.inventory.equipment(.Weapon).* = self.inventory.equipment(.Backup).*;
        self.inventory.equipment(.Backup).* = tmp;
        return false; // zero-cost action
    }

    pub fn equipItem(self: *Mob, slot: Inventory.EquSlot, item: Item) void {
        switch (item) {
            .Weapon => |w| for (w.equip_effects) |effect| self.applyStatus(effect, .{}),
            else => {},
        }
        self.inventory.equipment(slot).* = item;
        self.declareAction(.Use);
    }

    pub fn dequipItem(self: *Mob, slot: Inventory.EquSlot, drop_coord: Coord) void {
        const item = self.inventory.equipment(slot).*.?;
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
        state.dungeon.itemsAt(drop_coord).append(item) catch err.wat();
        self.inventory.equipment(slot).* = null;
        self.declareAction(.Drop);
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

    // Quaff a potion, applying its effects to a Mob.
    //
    // direct: was the potion quaffed directly (i.e., was it thrown at the
    //   mob or did the mob quaff it?). Used to determine whether to print a
    //   message.
    pub fn quaffPotion(self: *Mob, potion: *const Potion, direct: bool) void {
        if (direct and self.isUnderStatus(.Nausea) != null) {
            err.bug("Nauseated mob is quaffing potions!", .{});
        }

        if (direct) {
            state.messageAboutMob(self, self.coord, .Info, "slurp a potion of {s}", .{potion.name}, "quaffs a potion of {s}!", .{potion.name});
        }

        // TODO: make the duration of potion status effect random (clumping, ofc)
        switch (potion.type) {
            .Status => |s| self.addStatus(s, 0, .{ .Tmp = Status.MAX_DURATION }),
            .Gas => |s| state.dungeon.atGas(self.coord)[s] = 1.0,
            .Custom => |c| c(self, self.coord),
        }
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
            .Potion => false,
            else => err.wat(),
        };

        const trajectory = self.coord.drawLine(at, state.mapgeometry);
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
                        state.messageAboutMob(mob, self.coord, .Combat, "are hit by the {s}.", .{item_name}, "is hit by the {s}.", .{item_name});
                    }
                }

                break coord;
            }
        } else null;

        switch (item.*) {
            .Projectile => |proj| {
                if (landed != null and state.dungeon.at(landed.?).mob != null) {
                    const mob = state.dungeon.at(landed.?).mob.?;
                    if (proj.damage) |max_damage| {
                        const damage = rng.range(usize, max_damage / 2, max_damage);
                        mob.takeDamage(.{ .amount = @intToFloat(f64, damage), .source = .RangedAttack, .by_mob = self });
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
            .Potion => |potion| {
                const crd = landed orelse at;
                if (!potion.ingested) {
                    if (state.dungeon.at(crd).mob) |mob| {
                        mob.quaffPotion(potion, false);
                    } else switch (potion.type) {
                        .Status => {},
                        .Gas => |s| state.dungeon.atGas(crd)[s] = 1.0,
                        .Custom => |f| f(null, crd),
                    }
                }

                // TODO: have cases where thrower misses and potion lands (unused?)
                // in adjacent square
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
    //     - The mob has the .Shove status.
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

        if (other.isUnderStatus(.Paralysis)) |_| {
            can = true;
        }
        if (self.stat(.Speed) > other.stat(.Speed)) {
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
        if (self.isUnderStatus(.Shove) != null) {
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
                        if (m.addPower(self)) {
                            if (!instant)
                                self.declareAction(.Interact);
                            return true;
                        } else {
                            return false;
                        }
                    },
                    .Stair => |s| if (self == state.player) {
                        if (s) |floor| {
                            player.triggerStair(dest, floor);
                            return true;
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
        for (self.species.aux_attacks) |w| buf.append(w) catch err.wat();

        return buf;
    }

    pub fn canMelee(attacker: *Mob, defender: *Mob) bool {
        const weapons = attacker.listOfWeapons();
        const distance = attacker.coord.distance(defender.coord);

        return for (weapons.constSlice()) |weapon| {
            if (weapon.reach >= distance) break true;
        } else false;
    }

    pub fn totalMeleeOutput(self: *Mob) usize {
        const weapons = self.listOfWeapons();
        var total: usize = 0;
        for (weapons.constSlice()) |weapon|
            total += combat.damageOfMeleeAttack(self, weapon.damage, false);
        return total;
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
        // If the defender didn't know about the attacker's existence now's a
        // good time to find out
        ai.updateEnemyRecord(recipient, .{
            .mob = attacker,
            .counter = recipient.memory_duration,
            .last_seen = attacker.coord,
        });

        const martial = @intCast(usize, attacker.stat(.Martial));
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
                martial,
            );
        }

        // If longest_delay is still 0, we didn't attack at all!
        assert(longest_delay > 0);

        if (!opts.free_attack) {
            attacker.declareAction(.{
                .Attack = .{
                    .coord = recipient.coord,
                    .direction = attacker.coord.closestDirectionTo(recipient.coord, state.mapgeometry),
                    .delay = longest_delay,
                },
            });
        }
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

        const hit = opts.auto_hit or
            ((rng.percent(combat.chanceOfMeleeLanding(attacker, recipient))) and
            (!rng.percent(combat.chanceOfAttackEvaded(recipient, attacker))));

        if (!hit) {
            if (attacker == state.player) {
                state.message(.CombatUnimportant, "You miss the {s}.", .{recipient.displayName()});
            } else if (recipient == state.player) {
                state.message(.CombatUnimportant, "The {s} misses you.", .{attacker.displayName()});
            } else {
                const cansee_a = state.player.cansee(attacker.coord);
                const cansee_r = state.player.cansee(recipient.coord);

                if (cansee_a or cansee_r) {
                    state.message(.Info, "{s}{s} misses {s}{s}.", .{
                        if (cansee_a) @as([]const u8, "The ") else "",
                        if (cansee_a) attacker.displayName() else "Something",
                        if (cansee_r) @as([]const u8, "the ") else "",
                        if (cansee_r) recipient.displayName() else "something",
                    });
                }
            }

            if (recipient.isUnderStatus(.Riposte)) |_| {
                if (recipient.canMelee(attacker)) {
                    recipient.fight(attacker, .{ .free_attack = true, .is_riposte = true });
                }
            }
            return;
        }

        const is_stab = !opts.disallow_stab and !recipient.isAwareOfAttack(attacker.coord) and !opts.is_bonus;
        const damage = combat.damageOfMeleeAttack(attacker, attacker_weapon.damage, is_stab) * opts.damage_bonus / 100;

        recipient.takeDamage(.{
            .amount = @intToFloat(f64, damage),
            .source = if (is_stab) .Stab else .MeleeAttack,
            .by_mob = attacker,
        });

        // XXX: should this be .Loud instead of .Medium?
        if (!is_stab) {
            attacker.makeNoise(.Combat, opts.loudness);
        }

        var dmg_percent = recipient.lastDamagePercentage();
        var hitstrs = attacker_weapon.strs[attacker_weapon.strs.len - 1];
        // FIXME: insert some randomization here. Currently every single stab
        // the player makes results in "You puncture the XXX like a sieve!!!!"
        // which gets boring after a bit.
        {
            for (attacker_weapon.strs) |strset| {
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

        const martial_str = if (opts.is_bonus) " $b*Martial*$." else "";
        const riposte_str = if (opts.is_riposte) " $b*Riposte*$." else "";

        if (recipient.coord.eq(state.player.coord)) {
            state.message(.Combat, "The {s} {s} you{s}{s} ($p{}% dmg$.){s}{s}", .{
                attacker.displayName(),
                hitstrs.verb_other,
                hitstrs.verb_degree,
                punctuation,
                dmg_percent,
                martial_str,
                riposte_str,
            });
        } else if (attacker.coord.eq(state.player.coord)) {
            state.message(.Combat, "You {s} the {s}{s}{s} ($p{}% dmg$.){s}{s}", .{
                hitstrs.verb_self,
                recipient.displayName(),
                hitstrs.verb_degree,
                punctuation,
                dmg_percent,
                martial_str,
                riposte_str,
            });
        } else {
            const cansee_a = state.player.cansee(attacker.coord);
            const cansee_r = state.player.cansee(recipient.coord);

            if (cansee_a or cansee_r) {
                state.message(.Combat, "{s}{s} {s} {s}{s}{s}{s} ($p{}% dmg$.){s}{s}", .{
                    if (cansee_a) @as([]const u8, "The ") else "",
                    if (cansee_a) attacker.displayName() else "Something",
                    hitstrs.verb_other,
                    if (cansee_r) @as([]const u8, "the ") else "",
                    if (cansee_r) recipient.displayName() else "something",
                    hitstrs.verb_degree,
                    punctuation,
                    dmg_percent,
                    martial_str,
                    riposte_str,
                });
            }
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

        if (attacker_weapon.knockback > 0 and rng.onein(2)) {
            const d = attacker.coord.closestDirectionTo(recipient.coord, state.mapgeometry);
            combat.throwMob(attacker, recipient, d, attacker_weapon.knockback);
        }

        // Daze stabbed mobs.
        if (is_stab and !recipient.should_be_dead()) {
            recipient.addStatus(.Daze, 0, .{ .Tmp = rng.range(usize, 3, 5) });
        }

        // Bonus attacks?
        if (remaining_bonus_attacks > 0 and !recipient.should_be_dead()) {
            var newopts = opts;
            newopts.auto_hit = false;
            newopts.is_bonus = true;

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

    pub fn takeDamage(self: *Mob, d: Damage) void {
        const was_already_dead = self.should_be_dead();
        const old_HP = self.HP;

        const resist = @intToFloat(f64, self.resistance(d.kind.resist()));
        const amount = d.amount * resist / 100.0;

        self.HP = math.clamp(self.HP - amount, 0, self.max_HP);
        if (d.blood) if (self.blood) |s| state.dungeon.spatter(self.coord, s);
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
                const damage_percent = 10 - child.distance(self.coord);
                const damage = d.amount * @intToFloat(f64, damage_percent) / 100.0;

                mob.takeDamage(.{
                    .amount = damage,
                    .by_mob = d.by_mob,
                    .source = d.source,
                    .kind = .Electric,
                    .indirect = d.indirect,
                    .propagate_elec_damage = false,
                });
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
        self.squad_members = MobArrayList.init(alloc);
        self.enemies = std.ArrayList(EnemyRecord).init(alloc);
        self.allies = MobArrayList.init(alloc);
        self.activities.init();
        self.path_cache = std.AutoHashMap(Path, Coord).init(alloc);
        self.ai.work_area = CoordArrayList.init(alloc);
    }

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
        self.init(state.GPA.allocator()); // FIXME: antipattern?

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

        self.squad_members.deinit();
        self.enemies.deinit();
        self.allies.deinit();
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
            if (Direction.from(self.coord, to)) |direction| {
                return direction;
            }
        }

        const pathobj = Path{ .from = self.coord, .to = to, .confused_state = is_confused };

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
                fba.allocator(),
            ) orelse return null;

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

            pth.deinit();
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
                self.takeDamage(.{ .amount = self.HP * 1000 });
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
                }

                break :b true;
            },
            .Work => false,
        };
    }

    pub fn canHear(self: *const Mob, coord: Coord) ?*Sound {
        if (self.deaf) return null;

        const sound = state.dungeon.soundAt(coord);

        if (self.coord.z != coord.z)
            return null; // Can't hear across levels

        if (sound.state == .Dead or sound.intensity == .Silent)
            return null; // Sound was made a while back, or is silent

        const line = self.coord.drawLine(coord, state.mapgeometry);
        var walls_in_way: usize = 0;
        for (line.constSlice()) |c| {
            if (state.dungeon.at(c).type == .Wall) {
                walls_in_way += 1;
            }
        }

        // If there are a lot of walls in the way, quiet the noise
        var radius = sound.intensity.radiusHeard();
        if (self != state.player) radius -|= (walls_in_way * 2);
        if (self == state.player) radius = radius * 150 / 100;

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
        if (self.coord.distance(coord) > self.stat(.Vision))
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

        return val;
    }

    // Returns different things depending on what resist is.
    //
    // For all resists except rFume, returns damage mitigated.
    // For rFume, returns chance for gas to trigger.
    pub fn resistance(self: *const Mob, resist: Resistance) usize {
        var r: isize = 0;

        // Add the mob's innate resistance.
        const innate = utils.getFieldByEnum(Resistance, self.innate_resists, resist);
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
                r -= 25;
            },
            else => {},
        }

        r = math.clamp(r, -100, 100);

        // Value is between -100 and 100. Change it to be between 100 and 200.
        return @intCast(usize, 100 - r);
    }

    pub fn isFlanked(self: *const Mob) bool {
        var counter: usize = 0;
        return for (&DIRECTIONS) |d| {
            if (self.coord.move(d, state.mapgeometry)) |neighbor| {
                if (state.dungeon.at(neighbor).mob) |mob| {
                    if (mob.isHostileTo(self) and mob.ai.phase == .Hunt) {
                        counter += 1;
                        if (counter > 1) return true;
                    }
                }
            }
        } else false;
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

        // Charging pattern
        if (activities[3] == .Rest and
            activities[2] == .Move and
            activities[1] == .Move and
            activities[0] == .Move and
            activities[2].Move == activities[1].Move and
            activities[2].Move == activities[0].Move)
        {
            if (self.coord.move(activities[2].Move, state.mapgeometry)) |adj_mob_coord| {
                if (state.dungeon.at(adj_mob_coord).mob) |othermob| {
                    if (othermob.isHostileTo(self) and othermob.ai.is_combative and othermob.isAwareOfAttack(self.coord)) {
                        if (othermob == state.player) {
                            state.messageAboutMob(self, self.coord, .Combat, "[BUG]", .{}, "charges you!", .{});
                        } else {
                            state.messageAboutMob(self, self.coord, .Combat, "charge the {s}!", .{othermob.displayName()}, "charges the {s}!", .{othermob.displayName()});
                        }

                        self.fight(othermob, .{ .free_attack = true, .auto_hit = true, .damage_bonus = 130, .loudness = .Loud });
                        combat.throwMob(self, othermob, activities[2].Move, 3);
                        return;
                    }
                }
            }
        }

        // Lunge pattern
        if (activities[1] == .Rest and activities[0] == .Move) {
            if (self.coord.move(activities[0].Move, state.mapgeometry)) |adj_mob_coord| {
                if (state.dungeon.at(adj_mob_coord).mob) |othermob| {
                    if (othermob.isHostileTo(self) and othermob.ai.is_combative and
                        othermob.isAwareOfAttack(state.player.coord))
                    {
                        if (othermob == state.player) {
                            state.messageAboutMob(self, self.coord, .Combat, "[BUG]", .{}, "lunges at you!", .{});
                        } else {
                            state.messageAboutMob(self, self.coord, .Combat, "lunge at the {s}!", .{othermob.displayName()}, "lunges at the {s}!", .{othermob.displayName()});
                        }

                        self.fight(othermob, .{ .free_attack = true, .auto_hit = true, .disallow_stab = true, .damage_bonus = 200, .loudness = .Loud });
                        return;
                    }
                }
            }
        }

        // Counterattack pattern
        if (activities[4] == .Move and
            activities[3] == .Attack and
            activities[2] == .Move and
            activities[1] == .Attack and
            activities[0] == .Move and
            activities[4].Move == activities[2].Move and
            activities[4].Move == activities[0].Move and
            activities[3].Attack.direction == activities[1].Attack.direction and
            activities[3].Attack.direction == activities[4].Move.opposite())
        {
            self.addStatus(.Fast, 0, .{ .Tmp = 10 });
            return;
        }
    }

    pub fn isCreeping(self: *const Mob) bool {
        return self.turnsSpentMoving() < @intCast(usize, self.stat(.Sneak));
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

    flammability: usize = 0,

    // A* penalty if the machine is walkable
    pathfinding_penalty: usize = 0,

    coord: Coord = Coord.new(0, 0),
    on_power: fn (*Machine) void, // Called on each turn when the machine is powered
    power: usize = 0, // percentage (0..100)
    last_interaction: ?*Mob = null,

    disabled: bool = false,
    malfunctioning: bool = false, // Should only be true if tile.broken is true
    malfunction_effect: ?MalfunctionEffect = null,

    can_be_jammed: bool = false,
    jammed: bool = false,

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

    // chance: each turn, effect has ten in $chance to trigger.
    pub const MalfunctionEffect = union(enum) {
        Electrocute: struct { chance: usize, radius: usize, damage: usize },
        Explode: struct { chance: usize, power: usize },
    };

    pub const MachInteract = struct {
        name: []const u8,
        success_msg: []const u8,
        no_effect_msg: []const u8,
        needs_power: bool = true,
        used: usize = 0,
        max_use: usize, // 0 for infinite uses
        func: fn (*Machine, *Mob) bool,
    };

    pub fn evoke(self: *Machine, mob: *Mob, interaction: *MachInteract) !void {
        if (interaction.needs_power and !self.isPowered())
            return error.NotPowered;

        if (interaction.max_use > 0 and interaction.used >= interaction.max_use)
            return error.UsedMax;

        if ((interaction.func)(self, mob)) {
            interaction.used += 1;
        } else return error.NoEffect;
    }

    pub fn addPower(self: *Machine, by: *Mob) bool {
        if (self.restricted_to) |restriction|
            if (restriction != by.allegiance) return false;

        if (self.jammed) {
            if (!self._tryUnjam(by)) {
                return true;
            }
        }

        self.power = math.min(self.power + 100, 100);
        self.last_interaction = by;

        return true;
    }

    fn _tryUnjam(self: *Machine, by: ?*Mob) bool {
        assert(self.jammed and self.can_be_jammed);

        if (rng.percent(@as(usize, 10))) {
            // unjammed!
            self.jammed = false;

            if (rng.percent(@as(usize, 10))) {
                // broken!
                state.dungeon.at(self.coord).broken = true;
                if (by) |mob| mob.makeNoise(.Crash, .Medium);

                if (by) |mob| {
                    state.messageAboutMob(mob, self.coord, .Info, "break down the jammed {s}!", .{self.name}, "breaks down the jammed {s}!", .{self.name});
                } else {
                    state.message(.Info, "The {s} breaks down!", .{self.name});
                }
            } else {
                if (by) |mob| mob.makeNoise(.Crash, .Quiet);

                if (by) |mob| {
                    state.messageAboutMob(mob, self.coord, .Info, "push on {s} and unjam it!", .{self.name}, "pushes on the {s}, and unjams it!", .{self.name});
                } else {
                    state.message(.Info, "The {s} unjams itself!", .{self.name});
                }
            }

            return true;
        } else {
            if (by) |mob| {
                state.messageAboutMob(mob, self.coord, .Info, "push on the jammed {s}, but nothing happens.", .{self.name}, "pushes on the jammed {s}, but nothing happens.", .{self.name});
            } else {
                state.message(.Info, "The jammed {s} groans!", .{self.name});
            }

            return false;
        }
    }

    pub fn isPowered(self: *const Machine) bool {
        return !state.dungeon.at(self.coord).broken and self.power > 0;
    }

    pub fn tile(self: *const Machine) u21 {
        return if (self.isPowered()) self.powered_tile else self.unpowered_tile;
    }

    pub fn isWalkable(self: *const Machine) bool {
        if (self.jammed) return false;
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
        Eatables, // All food
        Wearables, // Weapons, armor, clothing, thread, cloth
        VOres, // self-explanatory
        Casual, // dice, deck of cards
        Utility, // Depends on the level (for PRI: rope, chains, etc)
    };
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
    knockback: usize = 0,

    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    effects: []const StatusDataInfo = &[_]StatusDataInfo{},
    equip_effects: []const StatusDataInfo = &[_]StatusDataInfo{},

    is_dippable: bool = false,
    dip_effect: ?*const Potion = null,
    dip_counter: usize = 0,

    strs: []const DamageStr,
};

pub const Potion = struct {
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

    // If null, the player will be prevented from dipping stuff
    // in it.
    dip_effect: ?StatusDataInfo = null,

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

pub const ItemType = enum { Ring, Potion, Vial, Projectile, Armor, Cloak, Weapon, Boulder, Prop, Evocable };

pub const Item = union(ItemType) {
    Ring: *Ring,
    Potion: *const Potion,
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
            .Cloak, .Projectile, .Ring, .Potion, .Armor, .Weapon, .Evocable => true,
        };
    }

    // FIXME: can't we just return the constSlice() of the stack buffer?
    pub fn shortName(self: *const Item) !StackBuffer(u8, 64) {
        var buf = StackBuffer(u8, 64).init(&([_]u8{0} ** 64));
        var fbs = std.io.fixedBufferStream(buf.slice());
        switch (self.*) {
            .Ring => |r| try fmt.format(fbs.writer(), "*{s}", .{r.name}),
            .Potion => |p| try fmt.format(fbs.writer(), "¡{s}", .{p.name}),
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
            .Ring => |r| try fmt.format(fbs.writer(), "ring of {s}", .{r.name}),
            .Potion => |p| try fmt.format(fbs.writer(), "potion of {s}", .{p.name}),
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
            .Potion => |p| p.id,
            .Projectile => |p| p.id,
            .Armor => |a| a.id,
            .Cloak => |c| c.id,
            .Weapon => |w| w.id,
            .Prop => |p| p.id,
            .Evocable => |v| v.id,
            .Vial, .Boulder, .Ring => null,
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

    // Is the surface item (or wall) on the tile broken?
    broken: bool = false,

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
                .bg = self.material.color_bg orelse colors.BG,
            },
            .Floor => {
                cell.ch = self.terrain.tile;
                cell.fg = self.terrain.color;
                cell.bg = colors.BG;
            },
        }

        if (self.broken) {
            cell.bg = colors.BG;

            const chars = [_]u32{ '`', ',', '^', '\'', '*', '"' };
            if (self.rand % 100 < 15) {
                cell.ch = chars[self.rand % chars.len];
            }
        }

        if (self.mob) |mob| {
            if (!self.broken) assert(self.type != .Wall);

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
                const red = @floatToInt(u32, (255 * (hp_loss_percent / 2)) / 100) + 0x22;
                cell.bg = math.clamp(red, 0x66, 0xff) << 16;
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
            if (!self.broken) assert(self.type != .Wall);

            cell.fg = 0xffffff;

            switch (item) {
                .Potion => |potion| {
                    cell.ch = '¡';
                    cell.fg = potion.color;
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
                    cell.ch = p.tile;
                    cell.fg = p.fg orelse 0xffffff;
                },
                .Evocable => |v| {
                    cell.ch = '}';
                    cell.fg = v.tile_fg;
                },
            }
        } else if (state.dungeon.at(coord).surface) |surfaceitem| {
            if (!self.broken) assert(self.type != .Wall);

            cell.fg = 0xffffff;

            const ch: u21 = switch (surfaceitem) {
                .Corpse => |_| c: {
                    cell.fg = 0xffe0ef;
                    break :c '%';
                },
                .Container => |c| cont: {
                    if (!self.broken) {
                        // if (c.capacity >= 14) {
                        //     cell.fg = 0x000000;
                        //     cell.bg = 0x808000;
                        // }
                        cell.fg = 0xffeeaa;
                    }
                    break :cont if (self.broken) 'x' else c.tile;
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

                    break :mach if (self.broken) 'x' else m.tile();
                },
                .Prop => |p| prop: {
                    if (!self.broken) {
                        if (p.bg) |prop_bg| cell.bg = prop_bg;
                        if (p.fg) |prop_fg| cell.fg = prop_fg;
                    }
                    break :prop if (self.broken) '·' else p.tile;
                },
                .Poster => |_| poster: {
                    if (!self.broken) {
                        cell.fg = self.material.color_bg orelse self.material.color_fg;
                    }
                    break :poster if (self.broken) @as(u21, '·') else '?';
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

    pub const ItemBuffer = StackBuffer(Item, 7);
    pub const StairBuffer = StackBuffer(Coord, MAX_STAIRS);

    pub const MAX_STAIRS: usize = 2;

    pub const MOB_OPACITY: usize = 10;
    pub const FLOOR_OPACITY: usize = 10;

    // Return the terrain if no surface item, else the default terrain.
    //
    pub fn terrainAt(self: *Dungeon, coord: Coord) *const surfaces.Terrain {
        const tile = self.at(coord);
        return if (tile.surface == null) tile.terrain else &surfaces.DefaultTerrain;
    }

    pub fn isTileOpaque(coord: Coord) bool {
        const tile = state.dungeon.at(coord);

        if (tile.type == .Wall and !tile.broken)
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

        if (tile.type == .Wall and !tile.broken)
            return @floatToInt(usize, tile.material.opacity * 100);

        o += tile.terrain.opacity;

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
            if (mob.isUnderStatus(.Corona)) |se| l += se.power;
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
