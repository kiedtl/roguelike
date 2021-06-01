const std = @import("std");
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

const LinkedList = @import("list.zig").LinkedList;
const RingBuffer = @import("ringbuffer.zig").RingBuffer;

const rng = @import("rng.zig");
const termbox = @import("termbox.zig");
const astar = @import("astar.zig");
const materials = @import("materials.zig");
const gas = @import("gas.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
const ai = @import("ai.zig");

pub const HEIGHT = 40;
pub const WIDTH = 100;
pub const LEVELS = 07;
pub const PLAYER_STARTING_LEVEL = 5; // second to last, TODO: define in data file

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const DirectionArrayList = std.ArrayList(Direction);
pub const CoordCellMap = std.AutoHashMap(Coord, termbox.tb_cell);
pub const CoordArrayList = std.ArrayList(Coord);
pub const RoomArrayList = std.ArrayList(Room);
pub const MessageArrayList = std.ArrayList(Message);
pub const MobList = LinkedList(Mob);
pub const MobArrayList = std.ArrayList(*Mob); // STYLE: rename to MobPtrArrayList
pub const MachineList = LinkedList(Machine);
pub const PropList = LinkedList(Prop);

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

pub const Room = struct {
    start: Coord,
    width: usize,
    height: usize,

    pub fn overflowsLimit(self: *const Room, limit: *const Room) bool {
        const a = self.end().x >= limit.end().x or self.end().y >= limit.end().x;
        const b = self.start.x < limit.start.x or self.start.y < limit.start.y;
        return a or b;
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

    pub fn attach(self: *const Room, d: Direction, width: usize, height: usize, distance: usize) Room {
        return switch (d) {
            .North => Room{
                .start = Coord.new2(self.start.z, self.start.x + (self.width / 2), utils.saturating_sub(self.start.y, height + distance)),
                .height = height,
                .width = width,
            },
            .East => Room{
                .start = Coord.new2(self.start.z, self.end().x + distance, self.start.y + (self.height / 2)),
                .height = height,
                .width = width,
            },
            .South => Room{
                .start = Coord.new2(self.start.z, self.start.x + (self.width / 2), self.end().y + distance),
                .height = height,
                .width = width,
            },
            .West => Room{
                .start = Coord.new2(self.start.z, utils.saturating_sub(self.start.x, width + distance), self.start.y + (self.height / 2)),
                .width = width,
                .height = height,
            },
            else => @panic("unimplemented"),
        };
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
    color_bg: u32,
    glyph: u21,

    // Melting point in Celsius, and combust temperature, also in Celsius.
    melting_point: usize,
    combust_point: ?usize,

    // Specific heat in kJ/(kg K)
    specific_heat: f64,

    // How much light this thing emits
    luminescence: usize,

    opacity: f64,
};

pub const MessageType = enum {
    Info,
    Aquire,
    Move,
    Trap,
    Damage,

    pub fn color(self: MessageType) u32 {
        return switch (self) {
            .Info => 0xfafefa,
            .Aquire => 0xffd700,
            .Move => 0xfafefe,
            .Trap => 0xed254d,
            .Damage => 0xed254d,
        };
    }
};

pub const Damage = struct { amount: f64 };
pub const Activity = union(enum) {
    Rest, Move: Direction, Attack: Direction, Teleport: Coord
};

pub const EnemyRecord = struct { mob: *Mob, counter: usize };

pub const Message = struct {
    msg: [128]u8,
    type: MessageType,
    turn: usize,
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

    prefers_distance: usize = 0,
    squad_members: MobArrayList = undefined,

    // TODO: instead of storing the tile's representation in memory, store the
    // actual tile -- if a wall is destroyed outside of the player's FOV, the display
    // code has no way of knowing what the player remembers the destroyed tile as...
    memory: CoordCellMap = undefined,
    fov: CoordArrayList = undefined,
    path_cache: std.AutoHashMap(Path, Coord) = undefined,
    enemies: std.ArrayList(EnemyRecord) = undefined,

    facing: Direction = .North,
    facing_wide: bool = false, // TODO: remove?
    coord: Coord = Coord.new(0, 0),

    HP: f64, // f64 so that we can regenerate <1 HP per turn
    activities: RingBuffer(Activity, 4) = .{},
    last_damage: ?Damage = null,
    is_dead: bool = false,

    // Immutable instrinsic attributes.
    //
    // willpower: Controls the ability to resist spells
    // dexterity: Controls the likelihood of a mob dodging an attack.
    // hearing:   The minimum intensity of a noise source before it can be
    //            heard by a mob. The lower the value, the better.
    // vision:    Maximum radius of the mob's field of vision.
    // strength:  TODO: define!
    // memory:    The maximum length of time for which a mob can remember
    //            an enemy.
    //
    willpower: usize, // Range: 0 < willpower < 10
    dexterity: usize, // Range: 0 < dexterity < 100
    vision: usize,
    hearing: usize,
    strength: usize,
    memory_duration: usize,
    max_HP: f64, // Should always be a whole number

    // Maximum field of hearing.
    pub const MAX_FOH = 35;

    pub const NOISE_MOVE = 20;
    pub const NOISE_YELL = 40;
    pub const NOISE_SCREAM = 60;

    pub const PAIN_DECAY = 0.08;
    pub const PAIN_UNCONSCIOUS_THRESHHOLD = 1.0;
    pub const PAIN_DEATH_THRESHHOLD = 1.8;

    // Regenerate health as necessary.
    //
    // TODO: regenerate health more if mob rested in last turn.
    pub fn tick_hp(self: *Mob) void {
        assert(!self.is_dead);
        self.HP = math.clamp(self.HP + 0.14, 0, self.max_HP);
        self.last_damage = null;
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

    pub fn makeNoise(self: *Mob, amount: usize) void {
        assert(!self.is_dead);
        state.dungeon.soundAt(self.coord).* += amount;
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
        if (!self.isCreeping()) self.makeNoise(NOISE_MOVE);
        self.coord = dest;

        if (state.dungeon.at(dest).surface) |surface| {
            switch (surface) {
                .Machine => |m| m.on_trigger(self, m),
                else => {},
            }
        }

        if (coord.distance(dest) == 1) {
            // [unreachable] Since the distance == 1 the coords have to be together
            const d = Direction.from_coords(coord, dest) catch unreachable;

            self.activities.append(Activity{ .Move = d });
        } else {
            self.activities.append(Activity{ .Teleport = dest });
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

    pub fn rest(self: *Mob) bool {
        self.activities.append(.Rest);
        return true;
    }

    pub fn fight(attacker: *Mob, recipient: *Mob) void {
        assert(!attacker.is_dead);
        assert(!recipient.is_dead);
        assert(attacker.dexterity < 100);

        if (Direction.from(attacker.coord, recipient.coord)) |d| {
            attacker.activities.append(.{ .Attack = d });
        }

        const is_stab = !recipient.isAwareOfAttack(attacker.coord);

        // TODO: attacker's skill should play a significant part
        const rand = rng.int(u7) % 100;

        if (!is_stab and rand < recipient.dexterity) {
            return; // dodged attack!
        }

        const noise: usize = if (is_stab) 3 else 15;
        attacker.makeNoise(noise);
        recipient.makeNoise(noise);

        var damage = (attacker.strength / 4) + rng.range(usize, 0, 3);
        if (is_stab) damage *= 6;

        recipient.takeDamage(.{ .amount = @intToFloat(f64, damage) });

        const hitstr = if (is_stab) "stab" else "hit";
        if (recipient.coord.eq(state.player.coord)) {
            state.message(.Info, "The {} {} you for {} damage!", .{ attacker.species, hitstr, damage });
            if (recipient.should_be_dead()) {
                state.message(.Damage, "The {} killed you.", .{attacker.species});
            }
        } else if (attacker.coord.eq(state.player.coord)) {
            state.message(.Info, "You {} the {} for {} damage!", .{ hitstr, recipient.species, damage });
        }
    }

    pub fn takeDamage(self: *Mob, d: Damage) void {
        self.HP = math.clamp(self.HP - d.amount, 0, self.max_HP);

        // Commented out because last_damage is set to null too soon for the
        // display to display it
        //
        //self.last_damage = d;
    }

    pub fn init(self: *Mob, alloc: *mem.Allocator) void {
        self.squad_members = MobArrayList.init(alloc);
        self.enemies = std.ArrayList(EnemyRecord).init(alloc);
        self.activities.init();
        self.path_cache = std.AutoHashMap(Path, Coord).init(alloc);
        self.occupation.work_area = CoordArrayList.init(alloc);
        self.fov = CoordArrayList.init(alloc);
        self.memory = CoordCellMap.init(alloc);
    }

    pub fn kill(self: *Mob) void {
        self.fov.deinit();
        self.occupation.work_area.deinit();
        self.memory.clearAndFree();
        self.path_cache.clearAndFree();
        self.is_dead = true;

        state.dungeon.at(self.coord).item = Item{ .Corpse = self };
        state.dungeon.at(self.coord).mob = null;
    }

    pub fn should_be_dead(self: *const Mob) bool {
        if (self.HP == 0)
            return true;

        return false;
    }

    // TODO: get rid of is_walkable parameter.
    pub fn nextDirectionTo(self: *Mob, to: Coord, is_walkable: fn (Coord) bool) ?Direction {
        const pathobj = Path{ .from = self.coord, .to = to };

        if (!self.path_cache.contains(pathobj)) {
            // TODO: do some tests and figure out what's the practical limit to memory
            // usage, and reduce the buffer's size to that.
            var membuf: [65535 * 10]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

            const pth = astar.path(self.coord, to, state.mapgeometry, is_walkable, &fba.allocator) orelse return null;

            var last: Coord = self.coord;
            for (pth.items[1..]) |coord| {
                self.path_cache.put(Path{ .from = last, .to = to }, coord) catch unreachable;
                last = coord;
            }

            pth.deinit();
        }

        // Return the next direction, ensuring that the next tile is walkable.
        // If it is not, set the path to null, ensuring that the path will be
        // recalculated next time.
        const next = self.path_cache.get(pathobj).?;
        const direction = Direction.from_coords(self.coord, next) catch unreachable;
        if (!next.eq(to) and !is_walkable(next)) {
            _ = self.path_cache.remove(pathobj);
            return null;
        } else {
            return direction;
        }
    }

    pub fn lastDamagePercentage(self: *const Mob) usize {
        if (self.last_damage) |dam| {
            const am = math.clamp(dam.amount, 0, self.max_HP);
            return @floatToInt(usize, (am * 100) / self.max_HP);
        } else {
            return 0;
        }
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
        const sound = state.dungeon.soundAt(coord).*;

        if (self.coord.z != coord.z)
            return null; // Can't hear across levels
        if (self.coord.distance(coord) > MAX_FOH)
            return null; // Too far away
        if (sound <= self.hearing)
            return null; // Too quiet to hear

        // TODO: do some tests and find the maximum used memory in practice,
        // decrease the buffer's size to that
        var membuf: [65535]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

        const line = self.coord.draw_line(coord, state.mapgeometry, &fba.allocator);
        var sound_resistance: f64 = 0.0;

        // FIXME: this lazy sound propagation formula isn't accurate. But this is
        // a game, so I can get away with it, right?
        for (line.items) |line_coord| {
            const resistance = if (state.dungeon.at(line_coord).type == .Wall)
                0.4 * state.dungeon.at(line_coord).material.density
            else
                0.08;
            sound_resistance += resistance;
            if (sound_resistance > 1.0) break;
        }

        const heard = sound - self.hearing;
        const apparent_volume = utils.saturating_sub(heard, @floatToInt(usize, sound_resistance));
        return if (apparent_volume == 0) null else apparent_volume;
    }

    pub fn isHostileTo(self: *const Mob, othermob: *const Mob) bool {
        // TODO: deal with all the nuances (eg .NoneGood should not be hostile
        // to .Illuvatar, but .NoneEvil should be hostile to .Sauron)
        return self.allegiance != othermob.allegiance;
    }

    pub fn cansee(self: *const Mob, coord: Coord) bool {
        // There is nothing hid from the spirits of the dead
        if (self.is_dead) return true;

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
    props: [40]?*Prop = [_]?*Prop{null} ** 40,
    // TODO: is_disabled, strength_needed
};

pub const Prop = struct { name: []const u8, tile: u21, coord: Coord = Coord.new(0, 0) };

pub const SurfaceItemTag = enum { Machine, Prop };
pub const SurfaceItem = union(SurfaceItemTag) { Machine: *Machine, Prop: *Prop };

// TODO: make corpse a surfaceitem? (if a mob dies over a surface item just dumb it
// on a nearby tile)
pub const ItemTag = enum { Corpse };
pub const Item = union(ItemTag) { Corpse: *Mob };

pub const TileType = enum {
    Wall = 0,
    Floor = 1,
};

pub const Tile = struct {
    material: *const Material = &materials.Basalt,
    type: TileType = .Wall,
    mob: ?*Mob = null,
    marked: bool = false,
    surface: ?SurfaceItem = null,
    item: ?Item = null,

    pub fn displayAs(coord: Coord) termbox.tb_cell {
        var self = state.dungeon.at(coord);
        var cell = termbox.tb_cell{};

        switch (self.type) {
            .Wall => cell = .{
                .ch = self.material.glyph,
                .fg = self.material.color_fg,
                .bg = self.material.color_bg,
            },
            .Floor => {
                var color: u32 = utils.darkenColor(self.material.color_bg, 4);

                if (self.mob) |mob| {
                    const hp_loss_percent = 100 - (mob.HP * 100 / mob.max_HP);
                    if (hp_loss_percent > 0) {
                        const red = @floatToInt(u32, (255 * hp_loss_percent) / 100);
                        color = math.clamp(red, 0x00, 0xee) << 16;
                    }

                    if (mob.is_dead) {
                        color = 0xdc143c;
                    }

                    cell.ch = mob.tile;
                    cell.bg = color;
                } else if (state.dungeon.at(coord).item) |item| {
                    switch (item) {
                        .Corpse => |corpse| {
                            cell.ch = corpse.tile;
                            cell.bg = 0xee0000;
                        },
                    }
                } else if (state.dungeon.at(coord).surface) |surfaceitem| {
                    const ch = switch (surfaceitem) {
                        .Machine => |m| m.tile,
                        .Prop => |p| p.tile,
                    };

                    cell.ch = ch;
                    cell.bg = color;
                } else {
                    cell.ch = ' ';
                    cell.bg = color;
                }
            },
        }

        const gases = state.dungeon.atGas(coord);
        for (gases) |q, g| {
            const gcolor = gas.Gases[g].color;
            const aq = 1 - math.clamp(q, 0.21, 1);
            if (q > 0) cell.bg = utils.mixColors(gcolor, cell.bg, aq);
        }

        return cell;
    }
};

pub const Dungeon = struct {
    map: [LEVELS][HEIGHT][WIDTH]Tile = [1][HEIGHT][WIDTH]Tile{[1][WIDTH]Tile{[1]Tile{.{}} ** WIDTH} ** HEIGHT} ** LEVELS,
    gas: [LEVELS][HEIGHT][WIDTH][gas.GAS_NUM]f64 = [1][HEIGHT][WIDTH][gas.GAS_NUM]f64{[1][WIDTH][gas.GAS_NUM]f64{[1][gas.GAS_NUM]f64{[1]f64{0} ** gas.GAS_NUM} ** WIDTH} ** HEIGHT} ** LEVELS,
    sound: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    rooms: [LEVELS]RoomArrayList = undefined,

    pub fn at(self: *Dungeon, c: Coord) *Tile {
        return &self.map[c.z][c.y][c.x];
    }

    // STYLE: rename to gasAt
    pub fn atGas(self: *Dungeon, c: Coord) []f64 {
        return &self.gas[c.z][c.y][c.x];
    }

    pub fn soundAt(self: *Dungeon, c: Coord) *usize {
        return &self.sound[c.z][c.y][c.x];
    }
};

pub const Gas = struct {
    color: u32,
    dissipation_rate: f64,
    opacity: f64,
    trigger: fn (*Mob, f64) void,
    id: usize,
};

// ---------- Mob templates ----------
// STYLE: move to mobs.zig

pub const WatcherTemplate = Mob{
    .species = "watcher",
    .tile = 'ש',
    .prefers_distance = 5,
    .occupation = Occupation{
        .work_description = "watching",
        .work_area = undefined,
        .work_fn = ai.watcherWork,
        .is_combative = true,
        .target = null,
        .phase = .Work,
    },
    .allegiance = .Sauron,
    .vision = 13,

    .willpower = 3,
    .dexterity = 17,
    .hearing = 5,
    .max_HP = 8,
    .memory_duration = 10,

    .HP = 8,
    .strength = 5, // weakling!
};

pub const GuardTemplate = Mob{
    .species = "orc guard",
    .tile = 'ג',
    .occupation = Occupation{
        .work_description = "patrolling",
        .work_area = undefined,
        .work_fn = ai.guardWork,
        .is_combative = true,
        .target = null,
        .phase = .Work,
    },
    .allegiance = .Sauron,
    .vision = 9,

    .willpower = 2,
    .dexterity = 9,
    .hearing = 7,
    .max_HP = 17,
    .memory_duration = 3,

    .HP = 17,
    .strength = 14,
};

// TODO: make this a hooman
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
    .vision = 20,

    .willpower = 4,
    .dexterity = 28,
    .hearing = 5,
    .max_HP = 49,
    .memory_duration = 10,

    .HP = 49,
    .strength = 14,
};
