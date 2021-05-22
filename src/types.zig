const std = @import("std");
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

const LinkedList = @import("list.zig").LinkedList;
const rng = @import("rng.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
const ai = @import("ai.zig");

pub const HEIGHT = 40;
pub const WIDTH = 100;
pub const LEVELS = 08;

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const DirectionArrayList = std.ArrayList(Direction);
pub const CoordCharMap = std.AutoHashMap(Coord, u21);
pub const CoordArrayList = std.ArrayList(Coord);
pub const MessageArrayList = std.ArrayList(Message);
pub const MobList = LinkedList(Mob);
pub const MachineList = LinkedList(Machine);
pub const PropList = LinkedList(Prop);
pub const MobArrayList = std.ArrayList(*Mob); // STYLE: rename to MobPtrArrayList

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
}; // }}}

test "from_coords" {
    std.testing.expectEqual(Direction.from_coords(Coord.new(0, 0), Coord.new(1, 0)), .East);
}

pub const Coord = struct { // {{{
    x: usize,
    y: usize,
    z: usize,

    const Self = @This();

    pub fn new2(level: usize, x: usize, y: usize) Coord {
        return .{ .z = level, .x = x, .y = y };
    }

    pub fn new(x: usize, y: usize) Coord {
        return .{ .z = 0, .x = x, .y = y };
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
}; // }}}

test "coord.move" {
    const limit = Coord.new(9, 9);

    var c = Coord.new(0, 0);
    std.testing.expect(c.move(.East, limit));
    std.testing.expectEqual(c, Coord.new(1, 0));
}

pub const MessageType = enum {
    Info,
    Aquire,
    Move,
    Trap,

    pub fn color(self: MessageType) u32 {
        return switch (self) {
            .Info => 0xfafefa,
            .Aquire => 0xffd700,
            .Move => 0xfafefe,
            .Trap => 0xed254d,
        };
    }
};

pub const Message = struct {
    msg: [128]u8,
    type: MessageType,
};

pub const Allegiance = enum { Sauron, Illuvatar, NoneEvil, NoneGood };

// TODO: add phases: Eat, Drink, Flee, Idle, GetItem
// XXX: "GoTo" should be renamed to "Investigating". But perhaps there's a another
// usecase for this phase?
pub const OccupationPhase = enum { Work, SawHostile, GoTo };

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

pub const Mob = struct { // {{{
    species: []const u8,
    tile: u21,
    occupation: Occupation,
    allegiance: Allegiance,
    memory: CoordCharMap = undefined,
    fov: CoordArrayList = undefined,
    facing: Direction,
    facing_wide: bool,
    vision: usize,
    coord: Coord = Coord.new(0, 0),

    is_dead: bool = false,

    // The amount of sound the mob is making. Decays by 0.5 every tick.
    //
    // XXX: Would it be best to make this per-tile instead of per-mob? That way,
    // the source of old sounds would be known when the soundmaker moves.
    noise: usize = 0,

    // If the practical pain goes over PAIN_UNCONSCIOUS_THRESHHOLD, the mob
    // should go unconscious. If it goes over PAIN_DEATH_THRESHHOLD, it will
    // succumb and die.
    //
    // practical_pain = pain / willpower
    pain: f64 = 0.0,

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
    max_HP: f64, // Should always be a whole number

    // Mutable instrinsic attributes.
    //
    // The use and effects of most of these are obvious.
    HP: f64, // f64 so that we can regenerate <1 HP per turn
    strength: usize,

    // Maximum field of hearing.
    pub const MAX_FOH = 35;

    pub const NOISE_WRITHE = 5;
    pub const NOISE_GASP = 8;
    pub const NOISE_YELL = 24;
    pub const NOISE_SCREAM = 32;

    pub const PAIN_DECAY = 0.08;
    pub const PAIN_UNCONSCIOUS_THRESHHOLD = 1.0;
    pub const PAIN_DEATH_THRESHHOLD = 1.8;

    // Regenerate health as necessary.
    //
    // TODO: regenerate health more if mob rested in last turn.
    pub fn tick_hp(self: *Mob) void {
        assert(!self.is_dead);
        self.HP = math.clamp(self.HP + 0.14, 0, self.max_HP);
    }

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
            self.noise += NOISE_WRITHE; // The <mob> writhes in pain!
        } else if (self.current_pain() > 0.4) {
            self.noise += NOISE_GASP; // The <mob> gasps in pain!
        } else if (self.current_pain() > 0.6) {
            self.noise += NOISE_YELL; // The <mob> yells!
        } else if (self.current_pain() > 0.8) {
            self.noise += NOISE_SCREAM; // The <mob> screams in agony!!
        }

        self.pain = math.max(self.pain - PAIN_DECAY * @intToFloat(f64, self.willpower), 0);
    }

    // Try to move a mob.
    pub fn moveInDirection(self: *Mob, direction: Direction) bool {
        const coord = self.coord;

        // Face in that direction no matter whether we end up moving or no
        self.facing = direction;

        var dest = coord;
        if (!dest.move(direction, Coord.new(state.WIDTH, state.HEIGHT))) {
            return false;
        }

        return self.teleportTo(dest);
    }

    pub fn teleportTo(self: *Mob, dest: Coord) bool {
        const coord = self.coord;

        if (state.dungeon.at(dest).type == .Wall) {
            return false;
        }

        if (state.dungeon.at(dest).mob) |othermob| {
            if (self.isHostileTo(othermob) and !othermob.is_dead) {
                self.fight(othermob);
                return true;
            } else if (!othermob.is_dead) {
                return false;
            }
        }

        const othermob = state.dungeon.at(dest).mob;
        state.dungeon.at(dest).mob = self;
        state.dungeon.at(coord).mob = othermob;
        self.noise += rng.int(u4) % 10;
        self.coord = dest;

        if (state.dungeon.at(dest).surface) |surface| {
            switch (surface) {
                .Machine => |m| m.on_trigger(self, m),
                else => {},
            }
        }

        return true;
    }

    pub fn gaze(self: *Mob, direction: Direction) bool {
        if (self.facing == direction) {
            self.facing_wide = !self.facing_wide;
        } else {
            self.facing = direction;
        }

        return true;
    }

    pub fn fight(attacker: *Mob, recipient: *Mob) void {
        assert(!attacker.is_dead);
        assert(!recipient.is_dead);
        assert(attacker.dexterity < 100);

        const is_stab = !recipient.isAwareOfAttack(attacker.coord);

        // TODO: attacker's skill should play a significant part
        const rand = rng.int(u7) % 100;

        if (!is_stab and rand < recipient.dexterity) {
            return; // dodged attack!
        }

        // WHAM
        recipient.pain += 0.21;

        const noise: usize = if (is_stab) 3 else 15;
        attacker.noise += noise;
        recipient.noise += noise;

        var damage = (attacker.strength / 4) + rng.range(usize, 0, 3);
        if (is_stab) damage *= 6;

        // saturate on subtraction
        const HP = @floatToInt(usize, math.floor(recipient.HP));
        recipient.HP = @intToFloat(f64, if ((HP -% damage) > HP) 0 else HP - damage);

        const hitstr = if (is_stab) "stab" else "hit";
        if (recipient.coord.eq(state.player.coord)) {
            state.message(.Info, "The {} {} you for {} damage!", .{ attacker.species, hitstr, damage });
        } else if (attacker.coord.eq(state.player.coord)) {
            state.message(.Info, "You {} the {} for {} damage!", .{ hitstr, recipient.species, damage });
        }
    }

    pub fn kill(self: *Mob) void {
        self.fov.deinit();
        self.occupation.work_area.deinit();
        self.memory.clearAndFree();
        self.noise = 0;
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

    pub fn isAwareOfAttack(self: *const Mob, attacker: Coord) bool {
        // Was the mob in attack/investigate phase?
        switch (self.occupation.phase) {
            .SawHostile, .GoTo => {},
            else => return false,
        }

        // Could the mob see the attacker?
        for (self.fov.items) |fovitem| {
            if (fovitem.eq(attacker))
                return true;
        }

        return false;
    }

    pub fn canHear(self: *const Mob, coord: Coord) ?usize {
        if (state.dungeon.at(coord).mob == null)
            return null; // No mob there, nothing to hear
        if (self.coord.z != coord.z)
            return null; // Can't hear across levels

        const other = state.dungeon.at(coord).mob.?;

        if (self.coord.distance(other.coord) > MAX_FOH)
            return null; // Too far away
        if (other.noise <= self.hearing)
            return null; // Too quiet to hear

        var membuf: [65535]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

        const line = self.coord.draw_line(other.coord, state.mapgeometry, &fba.allocator);
        var sound_resistance: f64 = 0.0;

        for (line.items) |line_coord| {
            sound_resistance += state.tile_sound_opacity(line_coord);
            if (sound_resistance > 1.0) break;
        }

        const heard = other.noise - self.hearing;
        const apparent_volume = utils.saturating_sub(heard, @floatToInt(usize, sound_resistance));
        return if (apparent_volume == 0) null else apparent_volume;
    }

    pub fn current_pain(self: *const Mob) f64 {
        return self.pain / @intToFloat(f64, self.willpower);
    }

    pub fn isHostileTo(self: *const Mob, othermob: *const Mob) bool {
        // TODO: deal with all the nuances (eg .NoneGood should not be hostile
        // to .Illuvatar, but .NoneEvil should be hostile to .Sauron)
        return self.allegiance != othermob.allegiance;
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
}; // }}}

pub const Machine = struct {
    name: []const u8,
    tile: u21,
    // Does the presence of this machine render a tile unwalkable?
    walkable: bool,
    opacity: f64,
    coord: Coord = Coord.new(0, 0),
    on_trigger: fn (*Mob, *Machine) void,
    // Should the machine, if walkable, be avoided when doing pathfinding?
    // Traps and staircases should be avoided, for instance.
    should_be_avoided: bool,
    // FIXME: there has got to be a better way to do this
    props: [40]?Prop = [_]?Prop{null} ** 40,
    // TODO: is_disabled, strength_needed
};

pub const Prop = struct { name: []const u8, tile: u21 };

pub const SurfaceItemTag = enum { Machine, Prop };
pub const SurfaceItem = union(SurfaceItemTag) { Machine: *Machine, Prop: *Prop };

pub const TileType = enum {
    Wall = 0,
    Floor = 1,
};

pub const Tile = struct {
    type: TileType = .Wall,
    mob: ?*Mob = null,
    marked: bool = false,
    surface: ?SurfaceItem = null,
};

pub const Dungeon = struct {
    map: [LEVELS][HEIGHT][WIDTH]Tile = [1][HEIGHT][WIDTH]Tile{[1][WIDTH]Tile{[1]Tile{.{}} ** WIDTH} ** HEIGHT} ** LEVELS,

    pub fn at(self: *Dungeon, c: Coord) *Tile {
        return &self.map[c.z][c.y][c.x];
    }
};

// ---------- Mob templates ----------

pub const GuardTemplate = Mob{
    .species = "orc",
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
    .facing = .North,
    .facing_wide = false,
    .vision = 12,

    .willpower = 2,
    .dexterity = 10,
    .hearing = 13,
    .max_HP = 17,

    .HP = 21,
    .strength = 10,
};

pub const ElfTemplate = Mob{
    .species = "elf",
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
    .facing = .North,
    .facing_wide = false,
    .vision = 20,

    .willpower = 4,
    .dexterity = 28,
    .hearing = 5,
    .max_HP = 49,

    .HP = 40,
    .strength = 14,
};
