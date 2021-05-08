const std = @import("std");
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

const rng = @import("rng.zig");

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

        const newx = @intCast(usize, @intCast(isize, self.x) + dx);
        const newy = @intCast(usize, @intCast(isize, self.y) + dy);

        if (0 < newx and newx < (limit.x - 1)) {
            if (0 < newy and newy < (limit.y - 1)) {
                self.x = newx;
                self.y = newy;
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

pub const CoordCharMap = std.AutoHashMap(Coord, u21);
pub const CoordArrayList = std.ArrayList(Coord);

pub const Slave = struct {
    prison_start: Coord,
    prison_end: Coord,
};

pub const Guard = struct {
    patrol_start: Coord,
    patrol_end: Coord,
};

pub const OccupationTag = enum {
    Guard,
    // Cook,
    // Miner,
    // Architect,
    Slave,
    // None,
};

pub const Allegiance = enum {
    Sauron,
    Illuvatar,
    Self,
    NoneEvil,
    NoneGood,
};

pub const Occupation = union(OccupationTag) {
    Guard: Guard,
    Slave: Slave,
};

pub const Mob = struct {
    tile: u21,
    occupation: Occupation,
    allegiance: Allegiance,
    memory: CoordCharMap,
    fov: CoordArrayList,
    facing: Direction,
    facing_wide: bool,
    vision: usize,
    coord: Coord,

    is_dead: bool,

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
    //
    willpower: usize, // Range: 0 < willpower < 10
    dexterity: usize, // Range: 0 < dexterity < 100
    max_HP: usize,

    // Mutable instrinsic attributes.
    //
    // The use and effects of most of these are obvious.
    HP: usize,

    pub const PAIN_DECAY = 0.0;
    pub const PAIN_UNCONSCIOUS_THRESHHOLD = 1.0;
    pub const PAIN_DEATH_THRESHHOLD = 1.8;

    // Reduce pain. Should be called by state.tick().
    pub fn tick_pain(self: *Mob) void {
        assert(!self.is_dead);

        // TODO: pain effects (unconsciousness, screaming, etc)
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
        recipient.pain += 0.14;

        // saturate on subtraction
        recipient.HP = if ((recipient.HP -% 10) > recipient.HP) 0 else recipient.HP - 5;
    }

    pub fn kill(self: *Mob) void {
        self.fov.deinit();
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
};

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
    .tile = 'א',
    .occupation = Occupation{
        .Guard = Guard{
            .patrol_start = Coord.new(0, 0),
            .patrol_end = Coord.new(0, 0),
        },
    },
    .allegiance = .Sauron,
    .fov = undefined,
    .memory = undefined,
    .facing = .North,
    .facing_wide = false,
    .vision = 4,
    .coord = undefined,

    .is_dead = false,

    .pain = 0.0,

    .willpower = 2,
    .dexterity = 21,
    .max_HP = 16,

    .HP = 16,
};

pub const ElfTemplate = Mob{
    .tile = '@',
    .occupation = Occupation{
        .Slave = Slave{
            .prison_start = Coord.new(0, 0),
            .prison_end = Coord.new(0, 0),
        },
    },
    .allegiance = .Illuvatar,
    .fov = undefined,
    .memory = undefined,
    .facing = .North,
    .facing_wide = false,
    .vision = 20,
    .coord = undefined,

    .is_dead = false,

    .pain = 0.0,

    .willpower = 4,
    .dexterity = 35,
    .max_HP = 49,

    .HP = 49,
};
