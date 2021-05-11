const std = @import("std");
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

const rng = @import("rng.zig");
const state = @import("state.zig");
const ai = @import("ai.zig");

pub const Direction = enum {
    North,
    South,
    East,
    West,
    NorthEast,
    NorthWest,
    SouthEast,
    SouthWest,

    const Self = @This();

    pub fn from_coords(base: Coord, neighbor: Coord) !Self {
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
            return error.NotNeighbor;
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
            else => unreachable,
        };
    }

    pub fn turnright(self: *const Self) Self {
        return self.turnleft().opposite();
    }
};

pub const DirectionArrayList = std.ArrayList(Direction);

test "from_coords" {
    std.testing.expectEqual(Direction.from_coords(Coord.new(0, 0), Coord.new(1, 0)), .East);
}

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const Coord = struct {
    x: usize,
    y: usize,

    const Self = @This();

    pub fn new(x: usize, y: usize) Coord {
        return .{ .x = x, .y = y };
    }

    pub fn distance(a: Self, b: Self) usize {
        // d = sqrt(dx^2 + dy^2)
        const x = math.max(a.x, b.x) - math.min(a.x, b.x);
        const y = math.max(a.y, b.y) - math.min(a.y, b.y);
        return math.sqrt((x * x) + (y * y));
    }

    pub fn hash(a: Self) u64 {}

    pub fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }

    pub fn move(self: *Self, direction: Direction, limit: Self) bool {
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

        if (newx >= 0 and @intCast(usize, newx) < (limit.x - 1)) {
            if (newy >= 0 and @intCast(usize, newy) < (limit.y - 1)) {
                self.x = @intCast(usize, newx);
                self.y = @intCast(usize, newy);
                return true;
            }
        }

        return false;
    }

    fn insert_if_valid(x: isize, y: isize, buf: *CoordArrayList, limit: Coord) void {
        if (x < 0 or y < 0)
            return;
        if (x > @intCast(isize, limit.x) or y > @intCast(isize, limit.y))
            return;

        buf.append(Coord.new(@intCast(usize, x), @intCast(usize, y))) catch unreachable;
    }

    pub fn draw_line(from: Coord, to: Coord, limit: Coord, alloc: *mem.Allocator) CoordArrayList {
        var buf = CoordArrayList.init(alloc);

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
                insert_if_valid(x, y, &buf, limit);
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
                insert_if_valid(x, y, &buf, limit);
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
};

test "coord.move" {
    const limit = Coord.new(9, 9);

    var c = Coord.new(0, 0);
    std.testing.expect(c.move(.East, limit));
    std.testing.expectEqual(c, Coord.new(1, 0));
}

pub const CoordCharMap = std.AutoHashMap(Coord, u21);
pub const CoordArrayList = std.ArrayList(Coord);

pub const Allegiance = enum {
    Sauron,
    Illuvatar,
    Self,
    NoneEvil,
    NoneGood,
};

pub const OccupationPhase = enum {
    Work,
    SawHostile,

    // XXX: Should be renamed to "Investigating". But perhaps there's a another
    // usecase for this phase?
    GoTo,

    // Eat,
    // Drink,
    // Flee,
    // Idle,
    // GetItem,
    // SearchItem,
};

pub const Occupation = struct {
    // Name of work, intended to be used as a description of what the mob is
    // doing. Examples: Guard("patrolling"), Smith("forging"), Demon("sulking")
    work_description: []const u8,

    // The area where the mob should be doing work.
    work_area: CoordArrayList,

    // work_fn is called on each tick when the mob is doing work.
    //
    // We only need to pass the Mob pointer because dungeon is a global variable,
    // amirite?
    work_fn: fn (*Mob, *mem.Allocator) void,

    // Is the "work" combative? if so, in "SawHostile" phase the mob should try
    // to attack the hostile mob; otherwise, it should merely raise the alarm.
    is_combative: bool,

    // The "target" in any phase.
    target: ?Coord,

    phase: OccupationPhase,
};

pub const Mob = struct {
    species: []const u8,
    tile: u21,
    occupation: Occupation,
    allegiance: Allegiance,
    memory: CoordCharMap,
    fov: CoordArrayList,
    sound_fov: CoordArrayList,
    facing: Direction,
    facing_wide: bool,
    vision: usize,
    coord: Coord,

    is_dead: bool,

    // The amount of sound the mob is making. Decays by 0.5 every tick.
    //
    // XXX: Would it be best to make this per-tile instead of per-mob? That way,
    // the source of old sounds would be known when the soundmaker moves.
    noise: usize,

    // If the practical pain goes over PAIN_UNCONSCIOUS_THRESHHOLD, the mob
    // should go unconscious. If it goes over PAIN_DEATH_THRESHHOLD, it will
    // succumb and die.
    //
    // practical_pain = pain / willpower
    pain: f64,

    // Immutable instrinsic attributes.
    //
    // willpower: Controls the ability to resist pain and spells
    // dexterity: Controls the likelihood of a mob dodging an attack.
    //            Examples:   Troll: 1
    //                     Hill Orc: 21
    //                          Elf: 35
    //                    Large Imp: 49
    //                    Small Imp: 63
    // hearing:   The minimum intensity of a noise source before it can be
    //            heard by a mob. The lower the value, the better.
    //
    willpower: usize, // Range: 0 < willpower < 10
    dexterity: usize, // Range: 0 < dexterity < 100
    hearing: usize,
    max_HP: usize,

    // Mutable instrinsic attributes.
    //
    // The use and effects of most of these are obvious.
    HP: usize,

    pub const PAIN_DECAY = 0.08;
    pub const PAIN_UNCONSCIOUS_THRESHHOLD = 1.0;
    pub const PAIN_DEATH_THRESHHOLD = 1.8;

    // Halves sound. Should be called by state.tick().
    pub fn tick_noise(self: *Mob) void {
        assert(!self.is_dead);
        self.noise /= 2;
    }

    // Reduce pain. Should be called by state.tick().
    //
    // TODO: pain effects (unconsciousness, etc)
    pub fn tick_pain(self: *Mob) void {
        assert(!self.is_dead);

        // The <mob> writhes in pain!
        if (self.current_pain() > 0.2) {
            self.noise += 5; // The <mob> writhes in pain!
        } else if (self.current_pain() > 0.4) {
            self.noise += 8; // The <mob> gasps in pain!
        } else if (self.current_pain() > 0.6) {
            self.noise += 24; // The <mob> yells!
        } else if (self.current_pain() > 0.8) {
            self.noise += 32; // The <mob> screams in agony!!
        }

        self.pain -= PAIN_DECAY * @intToFloat(f64, self.willpower);
    }

    pub fn fight(attacker: *Mob, recipient: *Mob) void {
        assert(!attacker.is_dead);
        assert(!recipient.is_dead);
        assert(recipient.dexterity < 100);

        // TODO: attacker's skill should play a significant part
        const rand = rng.int(u7) % 100;

        if (rand < recipient.dexterity) {
            // missed
            return;
        }

        // WHAM
        recipient.pain += 0.21;

        // saturate on subtraction
        recipient.HP = if ((recipient.HP -% 10) > recipient.HP) 0 else recipient.HP - 5;

        attacker.noise += 15;
        recipient.noise += 15;
    }

    pub fn kill(self: *Mob) void {
        self.fov.deinit();
        self.sound_fov.deinit();
        self.occupation.work_area.deinit();
        self.memory.clearAndFree();
        self.pain = 0.0;
        self.is_dead = true;
    }

    pub fn should_be_dead(self: *const Mob) bool {
        if (self.current_pain() > PAIN_DEATH_THRESHHOLD)
            return true;

        if (self.HP == 0)
            return true;

        return false;
    }

    pub fn current_pain(self: *const Mob) f64 {
        return self.pain / @intToFloat(f64, self.willpower);
    }

    pub fn isHostileTo(self: *const Mob, othermob: *const Mob) bool {
        // TODO: deal with all the nuances (eg .NoneGood should not be hostile
        // to .Illuvatar, but .NoneEvil should be hostile to .Sauron)
        return self.allegiance != othermob.allegiance;
    }

    pub fn canHear(self: *const Mob, coord: Coord) bool {
        if (state.dungeon[coord.y][coord.x].mob == null)
            return false;

        // TODO: check the *apparent* sound (that is, the sound's intensity
        // on the hearer's coordinate)
        if (self.hearing > state.dungeon[coord.y][coord.x].mob.?.noise)
            return false;

        for (self.sound_fov.items) |fovcoord| {
            if (coord.eq(fovcoord))
                return true;
        }

        return false;
    }

    pub fn cansee(self: *const Mob, coord: Coord) bool {
        assert(!self.is_dead);

        // Can't see stuff beyond your range of vision
        if (self.coord.distance(coord) > self.vision)
            return false;

        // Can always see yourself
        if (self.coord.eq(coord))
            return true;

        for (self.fov.items) |fovcoord| {
            if (coord.eq(fovcoord))
                return true;
        }

        return false;
    }

    // What's the monster doing right now?
    pub fn activity_description(self: *const Mob) []const u8 {
        var res = switch (self.occupation.phase) {
            .Work => self.occupation.work_description,
            .SawHostile => if (self.occupation.is_combative) "hunting" else "alarmed",
            .GoTo => "investigating",
        };

        if (self.is_dead) {
            res = "dead";
        }

        return res;
    }
};

pub const MobArrayList = std.ArrayList(*Mob);

pub const TileType = enum {
    Wall = 0,
    Floor = 1,
};

pub const Tile = struct {
    type: TileType,
    mob: ?Mob,
    marked: bool,
};

// ---------- Mob templates ----------

pub const GuardTemplate = Mob{
    .species = "Hill Orc",
    .tile = 'א',
    .occupation = Occupation{
        .work_description = "patrolling",
        .work_area = undefined,
        .work_fn = ai.guardWork,
        .is_combative = true,
        .target = null,
        .phase = .Work,
    },
    .allegiance = .Sauron,
    .fov = undefined,
    .sound_fov = undefined,
    .memory = undefined,
    .facing = .North,
    .facing_wide = false,
    .vision = 5,
    .coord = undefined,

    .is_dead = false,

    .noise = 0,
    .pain = 0.0,

    .willpower = 2,
    .dexterity = 21,
    .hearing = 10,
    .max_HP = 16,

    .HP = 16,
};

pub const ElfTemplate = Mob{
    .species = "Elf",
    .tile = '@',
    .occupation = Occupation{
        .work_description = "meditating",
        .work_area = undefined,
        .work_fn = ai.dummyWork,
        .is_combative = false,
        .target = null,
        .phase = .Work,
    },
    .allegiance = .Illuvatar,
    .fov = undefined,
    .sound_fov = undefined,
    .memory = undefined,
    .facing = .North,
    .facing_wide = false,
    .vision = 20,
    .coord = undefined,

    .is_dead = false,

    .noise = 0,
    .pain = 0.0,

    .willpower = 4,
    .dexterity = 35,
    .hearing = 5,
    .max_HP = 49,

    .HP = 49,
};
