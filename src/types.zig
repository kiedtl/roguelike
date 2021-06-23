const std = @import("std");
const math = std.math;
const mem = std.mem;
const fmt = std.fmt;
const assert = std.debug.assert;
const enums = @import("std/enums.zig");

const LinkedList = @import("list.zig").LinkedList;
const RingBuffer = @import("ringbuffer.zig").RingBuffer;
const StackBuffer = @import("buffer.zig").StackBuffer;

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
const ai = @import("ai.zig");

pub const HEIGHT = 100;
pub const WIDTH = 100;
pub const LEVELS = 3;
pub const PLAYER_STARTING_LEVEL = 1; // TODO: define in data file

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const DirectionArrayList = std.ArrayList(Direction);
pub const CoordCellMap = std.AutoHashMap(Coord, termbox.tb_cell);
pub const CoordArrayList = std.ArrayList(Coord);
pub const AnnotatedCoordArrayList = std.ArrayList(AnnotatedCoord);
pub const RoomArrayList = std.ArrayList(Room);
pub const MessageArrayList = std.ArrayList(Message);
pub const StatusArray = enums.EnumArray(Status, StatusData);
pub const MobList = LinkedList(Mob);
pub const SobList = LinkedList(Sob);
pub const MobArrayList = std.ArrayList(*Mob); // STYLE: rename to MobPtrArrayList
pub const RingList = LinkedList(Ring);
pub const PotionList = LinkedList(Potion);
pub const ArmorList = LinkedList(Armor);
pub const WeaponList = LinkedList(Weapon);
pub const ProjectileList = LinkedList(Projectile);
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

    pub inline fn new2(level: usize, x: usize, y: usize) Coord {
        return .{ .z = level, .x = x, .y = y };
    }

    pub inline fn new(x: usize, y: usize) Coord {
        return .{ .z = 0, .x = x, .y = y };
    }

    pub fn distance(a: Self, b: Self) usize {
        // Euclidean: d = sqrt(dx^2 + dy^2)
        //
        // const x = math.max(a.x, b.x) - math.min(a.x, b.x);
        // const y = math.max(a.y, b.y) - math.min(a.y, b.y);
        // return math.sqrt((x * x) + (y * y));

        // Manhattan: |x1 - x2| + |y1 - y2|
        return @intCast(
            usize,
            (math.absInt(@intCast(isize, a.x) - @intCast(isize, b.x)) catch unreachable) +
                (math.absInt(@intCast(isize, a.y) - @intCast(isize, b.y)) catch unreachable),
        );
    }

    pub inline fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }

    pub inline fn add(a: Self, b: Self) Self {
        return Coord.new2(a.z, a.x + b.x, a.y + b.y);
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

test "coord.move" {
    const limit = Coord.new(9, 9);

    var c = Coord.new(0, 0);
    std.testing.expect(c.move(.East, limit));
    std.testing.expectEqual(c, Coord.new(1, 0));
}

pub const AnnotatedCoord = struct { coord: Coord, value: usize };

pub const Room = struct {
    type: RoomType = .Room,

    prefab: ?mapgen.Prefab = null,
    start: Coord,
    width: usize,
    height: usize,

    pub const RoomType = enum { Corridor, Room };

    pub fn overflowsLimit(self: *const Room, limit: *const Room) bool {
        const a = self.end().x >= limit.end().x or self.end().y >= limit.end().y;
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

    pub fn attach(self: *const Room, d: Direction, width: usize, height: usize, distance: usize, fab: ?*const mapgen.Prefab) ?Room {
        // "Preferred" X/Y coordinates to start the child at. preferred_x is only
        // valid if d == .North or d == .South, and preferred_y is only valid if
        // d == .West or d == .East.
        var preferred_x = self.start.x + (self.width / 2);
        var preferred_y = self.start.y + (self.height / 2);

        // Note: the coordinate returned by Prefab.connectorFor() is relative.

        if (self.prefab != null and fab != null) {
            const parent_con = self.prefab.?.connectorFor(d) orelse return null;
            const child_con = fab.?.connectorFor(d.opposite()) orelse return null;
            const parent_con_abs = Coord.new2(
                self.start.z,
                self.start.x + parent_con.x,
                self.start.y + parent_con.y,
            );
            preferred_x = utils.saturating_sub(parent_con_abs.x, child_con.x);
            preferred_y = utils.saturating_sub(parent_con_abs.y, child_con.y);
        } else if (self.prefab) |pafab| {
            const con = pafab.connectorFor(d) orelse return null;
            preferred_x = self.start.x + con.x;
            preferred_y = self.start.y + con.y;
        } else if (fab) |chfab| {
            const con = chfab.connectorFor(d.opposite()) orelse return null;
            preferred_x = utils.saturating_sub(self.start.x, con.x);
            preferred_y = utils.saturating_sub(self.start.y, con.y);
        }

        return switch (d) {
            .North => Room{
                .start = Coord.new2(self.start.z, preferred_x, utils.saturating_sub(self.start.y, height + distance)),
                .height = height,
                .width = width,
            },
            .East => Room{
                .start = Coord.new2(self.start.z, self.end().x + distance, preferred_y),
                .height = height,
                .width = width,
            },
            .South => Room{
                .start = Coord.new2(self.start.z, preferred_x, self.end().y + distance),
                .height = height,
                .width = width,
            },
            .West => Room{
                .start = Coord.new2(self.start.z, utils.saturating_sub(self.start.x, width + distance), preferred_y),
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

pub const MessageType = union(enum) {
    MetaError,
    Info,
    Aquire,
    Move,
    Trap,
    Damage,

    pub fn color(self: MessageType) u32 {
        return switch (self) {
            .MetaError => 0xffffff,
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
    Rest,
    Move: Direction,
    Attack: Direction,
    Teleport: Coord,
    Grab,
    Drop,
    Use,
    Throw,
    Fire,
    SwapWeapons,
};

pub const EnemyRecord = struct { mob: *Mob, counter: usize };

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

    // Allows mob to "see" presence of walls around sounds.
    //
    // Power field determines radius of effect.
    Echolocation,

    pub const MAX_DURATION: usize = 20;

    pub fn tickEcholocation(mob: *Mob) void {
        const st = mob.isUnderStatus(.Echolocation) orelse return;

        const radius = st.power;
        const z = mob.coord.z;
        const ystart = utils.saturating_sub(mob.coord.y, radius);
        const yend = math.min(mob.coord.y + radius, HEIGHT);
        const xstart = utils.saturating_sub(mob.coord.x, radius);
        const xend = math.min(mob.coord.x + radius, WIDTH);

        var tile: termbox.tb_cell = .{ .fg = 0xffffff, .ch = '#' };
        var y: usize = ystart;
        while (y < yend) : (y += 1) {
            var x: usize = xstart;
            while (x < xend) : (x += 1) {
                const coord = Coord.new2(z, x, y);
                const noise = mob.canHear(coord) orelse continue;
                for (&DIRECTIONS) |d| {
                    var neighbor = coord;
                    if (!neighbor.move(d, state.mapgeometry)) continue;
                    if (state.dungeon.neighboringWalls(neighbor, true) == 9) continue;

                    tile.ch = if (state.dungeon.at(neighbor).type == .Wall) '#' else '·';
                    _ = mob.memory.getOrPutValue(neighbor, tile) catch unreachable;
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
};

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
    // to attack the hostile mob.
    is_combative: bool,

    // The "target" in any phase.
    target: ?Coord,

    phase: OccupationPhase,
};

pub const Mob = struct { // {{{
    id: []const u8 = "",
    species: []const u8,
    tile: u21,
    allegiance: Allegiance,

    prefers_distance: usize = 0,
    squad_members: MobArrayList = undefined,

    // TODO: instead of storing the tile's representation in memory, store the
    // actual tile -- if a wall is destroyed outside of the player's FOV, the display
    // code has no way of knowing what the player remembers the destroyed tile as...
    //
    // Addendum 21-06-23: Is the above comment even true anymore (was it *ever* true)?
    // Need to do some experimenting once explosions are added.
    //
    memory: CoordCellMap = undefined,
    fov: [HEIGHT][WIDTH]usize = [1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT,
    path_cache: std.AutoHashMap(Path, Coord) = undefined,
    enemies: std.ArrayList(EnemyRecord) = undefined,

    facing: Direction = .North,
    coord: Coord = Coord.new(0, 0),

    HP: f64, // f64 so that we can regenerate <1 HP per turn
    energy: isize = 0,
    statuses: StatusArray = StatusArray.initFill(.{}),
    occupation: Occupation,
    activities: RingBuffer(Activity, 4) = .{},
    last_damage: ?Damage = null,
    inventory: Inventory = .{},
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
    base_speed: usize,
    max_HP: f64, // Should always be a whole number

    pub const Inventory = struct {
        pack: PackBuffer = PackBuffer.init(&[_]Item{}),

        r_rings: [2]?*Ring = [2]?*Ring{ null, null },
        l_rings: [2]?*Ring = [2]?*Ring{ null, null },

        armor: ?*Armor = null,
        wielded: ?*Weapon = null,
        backup: ?*Weapon = null,

        pub const PACK_SIZE: usize = 5;
        pub const PackBuffer = StackBuffer(Item, PACK_SIZE);
    };

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
                self.addStatus(ring.status, ring.currentPower());
        }
    }

    // Do stuff for various statuses that need babysitting each turn.
    pub fn tickStatuses(self: *Mob) void {
        inline for (@typeInfo(Status).Enum.fields) |status| {
            switch (@field(Status, status.name)) {
                .Echolocation => Status.tickEcholocation(self),
                else => {},
            }
        }
    }

    pub fn swapWeapons(self: *Mob) bool {
        const tmp = self.inventory.wielded;
        self.inventory.wielded = self.inventory.backup;
        self.inventory.backup = tmp;
        self.activities.append(.SwapWeapons);
        self.energy -= self.speed();
        return true;
    }

    pub fn deleteItem(self: *Mob, index: usize) !Item {
        if (index >= self.inventory.pack.len) return error.IndexOutOfRange;
        switch (self.inventory.pack.slice()[index]) {
            .Projectile => |projectile| {
                if (projectile.count > 1) {
                    projectile.count -= 1;

                    var p = projectile.*;
                    p.count = 1;
                    state.projectiles.append(p) catch unreachable;

                    return Item{ .Projectile = state.projectiles.lastPtr().? };
                } else {
                    return self.inventory.pack.orderedRemove(index) catch unreachable;
                }
            },
            else => return self.inventory.pack.orderedRemove(index) catch unreachable,
        }
    }

    pub fn grabItem(self: *Mob) bool {
        if (state.dungeon.at(self.coord).item) |item| {
            switch (item) {
                .Projectile => |projectile| {
                    var found: ?usize = null;
                    for (self.inventory.pack.constSlice()) |entry, i| switch (entry) {
                        .Projectile => |stack| if (stack.type == projectile.type and mem.eql(u8, stack.id, projectile.id)) {
                            found = i;
                        },
                        else => {},
                    };

                    if (found) |index| {
                        self.inventory.pack.slice()[index].Projectile.count += 1;
                    } else {
                        self.inventory.pack.append(item) catch |e| switch (e) {
                            error.NoSpaceLeft => return false,
                        };
                    }
                },
                else => {
                    self.inventory.pack.append(item) catch |e| switch (e) {
                        error.NoSpaceLeft => return false,
                    };
                },
            }

            state.dungeon.at(self.coord).item = null;

            self.activities.append(.Grab);
            self.energy -= self.speed();
            return true;
        } else {
            return false;
        }
    }

    pub fn quaffPotion(self: *Mob, potion: *Potion) void {
        switch (potion.type) {
            .Status => |s| self.addStatus(s, 0),
            .Gas => |s| state.dungeon.atGas(self.coord)[s] = 1.0,
            .Custom => |c| c(self),
        }
    }

    // Only destructible items can be thrown. If we allowed non-destructable
    // items to be thrown, it'd pose many issues due to the fact that there
    // can be only one item on a tile -- what should be done if a corpse it
    // thrown onto a tile that already has an item? Should one of the items be
    // destroyed, or should the thrown item be moved the nearest free tile?
    // What if that free tile is twenty items away? ...
    pub fn throwItem(self: *Mob, item: *Item, at: Coord, _energy: ?usize) bool {
        switch (item.*) {
            .Projectile, .Potion => {},
            .Weapon => @panic("W/A TODO"),
            else => return false,
        }

        const trajectory = self.coord.drawLine(at, state.mapgeometry);
        var landed: ?Coord = null;
        var energy: usize = _energy orelse self.strength;

        for (trajectory.constSlice()) |coord| {
            if (energy == 0 or (!coord.eq(self.coord) and !state.is_walkable(coord))) {
                landed = coord;
                break;
            }
            energy -= 1;
        }
        if (landed == null) landed = at;

        switch (item.*) {
            .Weapon => |_| @panic("W/A TODO"),
            .Projectile => |projectile| {
                if (state.dungeon.at(landed.?).mob) |bastard| {
                    const CHANCE_OF_AUTO_MISS = 20; // 1 in <x>
                    const CHANCE_OF_AUTO_HIT = 5; // 1 in <x>

                    // FIXME: reduce code duplication in fight() vs here
                    const is_stab = !bastard.isAwareOfAttack(self.coord);
                    const auto_miss = rng.onein(CHANCE_OF_AUTO_MISS);
                    const auto_hit = is_stab or rng.onein(CHANCE_OF_AUTO_HIT);

                    const miss = if (auto_miss)
                        true
                    else if (auto_hit)
                        false
                    else
                        (rng.rangeClumping(usize, 1, 10, 2) * self.accuracy()) <
                            (rng.rangeClumping(usize, 1, 10, 2) * bastard.dexterity);

                    if (!miss) {
                        const defender_armor = bastard.inventory.armor orelse &items.NoneArmor;
                        const max_damage = projectile.damages.resultOf(&defender_armor.resists).sum();

                        var damage = rng.rangeClumping(usize, max_damage / 2, max_damage, 2);

                        if (is_stab) {
                            const bonus = DamageType.stabBonus(projectile.main_damage);
                            damage = utils.percentOf(usize, damage, bonus);
                        }

                        bastard.takeDamage(.{ .amount = @intToFloat(f64, damage) });
                    }
                }
            },
            .Potion => |potion| {
                if (state.dungeon.at(landed.?).mob) |bastard| {
                    bastard.quaffPotion(potion);
                } else switch (potion.type) {
                    .Status => {},
                    .Gas => |s| state.dungeon.atGas(landed.?)[s] = 1.0,
                    .Custom => |f| f(null),
                }
            },
            else => unreachable,
        }

        return true;
    }

    pub fn makeNoise(self: *Mob, amount: usize) void {
        assert(!self.is_dead);
        state.dungeon.soundAt(self.coord).* += amount;
    }

    // Try to move to a destination, one step at a time.
    //
    // Unlike the other move functions (teleportTo, moveInDirection) this
    // function is guaranteed to return with a lower time energy amount than
    // when it started with.
    //
    pub fn tryMoveTo(self: *Mob, dest: Coord) void {
        const prev_energy = self.energy;

        if (self.nextDirectionTo(dest, state.is_walkable)) |d| {
            if (!self.moveInDirection(d)) _ = self.rest();
        } else _ = self.rest();

        assert(prev_energy > self.energy);
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

        if (!state.is_walkable(dest)) {
            if (state.dungeon.at(dest).mob) |othermob| {
                if (self.isHostileTo(othermob) and !othermob.is_dead) {
                    self.fight(othermob);
                    return true;
                } else if (!othermob.is_dead) {
                    return false;
                }
            } else if (state.dungeon.at(dest).surface) |surface| {
                switch (surface) {
                    .Machine => |m| if (!m.isWalkable()) {
                        m.addPower(self);
                        self.energy -= self.speed();
                        return true;
                    },
                    else => {},
                }
                return false;
            } else {
                return false;
            }
        }

        const othermob = state.dungeon.at(dest).mob;
        state.dungeon.at(dest).mob = self;
        state.dungeon.at(coord).mob = othermob;
        if (!self.isCreeping()) self.makeNoise(NOISE_MOVE);
        self.energy -= self.speed();
        self.coord = dest;

        if (state.dungeon.at(dest).surface) |surface| {
            switch (surface) {
                .Machine => |m| if (m.isWalkable()) m.addPower(self),
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
        self.facing = direction;
        return true;
    }

    pub fn rest(self: *Mob) bool {
        self.activities.append(.Rest);
        self.energy -= self.speed();
        return true;
    }

    // TODO: bonus if defender didn't move in last two turns
    // TODO: bonus if attacker didn't move in last two turns
    // TODO: nbonus if attacker moved in last two turns
    // TODO: nbonus if defender moved in last two turns
    // TODO: bonus if defender is in a certain radius (<6 cells?)
    // TODO: make missed ranged attacks land on adjacent squares
    pub fn fight(attacker: *Mob, recipient: *Mob) void {
        assert(!attacker.is_dead);
        assert(!recipient.is_dead);

        assert(attacker.dexterity <= 100);
        assert(recipient.dexterity <= 100);

        assert(attacker.strength > 0);
        assert(recipient.strength > 0);

        const CHANCE_OF_AUTO_MISS = 14; // 1 in <x>
        const CHANCE_OF_AUTO_HIT = 14; // 1 in <x>

        attacker.energy -= attacker.speed();

        if (Direction.from(attacker.coord, recipient.coord)) |d| {
            attacker.activities.append(.{ .Attack = d });
        }

        const is_stab = !recipient.isAwareOfAttack(attacker.coord);
        const auto_miss = rng.onein(CHANCE_OF_AUTO_MISS);
        const auto_hit = is_stab or rng.onein(CHANCE_OF_AUTO_HIT);

        const miss = if (auto_miss)
            true
        else if (auto_hit)
            false
        else
            (rng.rangeClumping(usize, 1, 10, 2) * attacker.accuracy()) <
                (rng.rangeClumping(usize, 1, 10, 2) * recipient.dexterity);

        if (miss) return;

        const attacker_weapon = attacker.inventory.wielded orelse &items.UnarmedWeapon;
        const attacker_extra_str = attacker.strength * 100 / attacker_weapon.required_strength;
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
            if (recipient.should_be_dead()) {
                state.message(.Damage, "The {} killed you.", .{attacker.species});
            }
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
            state.canRecieveItem,
            alloc,
        );
        defer dijk.deinit();

        while (dijk.next()) |coord| {
            // Papering over a bug here, next() should never return starting coord
            if (coord.eq(self.coord)) continue;

            assert(state.canRecieveItem(coord));
            coords.append(coord) catch |e| switch (e) {
                error.NoSpaceLeft => break,
                else => unreachable,
            };
        }

        var ctr: usize = 0;

        for (&special_invent) |maybe_item| {
            if (maybe_item) |item| {
                if (ctr >= coords.len) break;
                state.dungeon.at(coords.data[ctr]).item = item;
                ctr += 1;
            }
        }
        for (self.inventory.pack.constSlice()) |item| {
            if (ctr >= coords.len) break;
            state.dungeon.at(coords.data[ctr]).item = item;
            ctr += 1;
        }

        self.inventory.pack.clear();
        self.inventory.armor = null;
        self.inventory.wielded = null;
        self.inventory.l_rings = [_]?*Ring{ null, null };
        self.inventory.r_rings = [_]?*Ring{ null, null };
    }

    pub fn init(self: *Mob, alloc: *mem.Allocator) void {
        self.squad_members = MobArrayList.init(alloc);
        self.enemies = std.ArrayList(EnemyRecord).init(alloc);
        self.activities.init();
        self.path_cache = std.AutoHashMap(Path, Coord).init(alloc);
        self.occupation.work_area = CoordArrayList.init(alloc);
        self.memory = CoordCellMap.init(alloc);
    }

    pub fn kill(self: *Mob) void {
        self.squad_members.deinit();
        self.enemies.deinit();
        self.path_cache.clearAndFree();
        self.occupation.work_area.deinit();
        self.memory.clearAndFree();

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

            const pth = astar.path(self.coord, to, state.mapgeometry, is_walkable, &fba.allocator) orelse return null;

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
            if (!next.eq(to) and !is_walkable(next)) {
                _ = self.path_cache.remove(pathobj);
                return null;
            } else {
                return direction;
            }
        } else {
            return null;
        }
    }

    pub fn addStatus(self: *Mob, status: Status, power: usize) void {
        const p_se = self.statuses.getPtr(status);
        p_se.started = state.ticks;
        p_se.power = power;
        p_se.duration = Status.MAX_DURATION;
    }

    pub fn isUnderStatus(self: *Mob, status: Status) ?*StatusData {
        const se = self.statuses.getPtr(status);
        return if ((se.started + se.duration) < state.ticks) null else se;
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
        if (self.cansee(attacker)) return true;

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

        const line = self.coord.drawLine(coord, state.mapgeometry);
        var sound_resistance: f64 = 0.0;

        // FIXME: this lazy sound propagation formula isn't accurate. But this is
        // a game, so I can get away with it, right?
        for (line.constSlice()) |line_coord| {
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
        // Can't see stuff beyond your range of vision
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

    pub fn hasMoreEnergyThan(a: *const Mob, b: *const Mob) bool {
        return a.energy < b.energy;
    }

    pub fn speed(self: *const Mob) isize {
        return @intCast(isize, self.base_speed);
    }

    pub fn accuracy(self: *const Mob) usize {
        return self.dexterity;
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

    power_drain: usize = 100, // Power drained per turn
    power_add: usize = 100, // Power added on interact
    auto_power: bool = false,

    powered_walkable: bool = true,
    unpowered_walkable: bool = true,

    powered_opacity: f64 = 0.0,
    unpowered_opacity: f64 = 0.0,

    powered_luminescence: usize = 0,
    unpowered_luminescence: usize = 0,

    coord: Coord = Coord.new(0, 0),
    on_power: fn (*Machine) void, // Called on each turn when the machine is powered
    power: usize = 0, // percentage (0..100)
    last_interaction: ?*Mob = null,

    // FIXME: there has got to be a better way to do this
    props: [40]?*Prop = [_]?*Prop{null} ** 40,

    // TODO: is_disabled?

    pub fn addPower(self: *Machine, by: ?*Mob) void {
        self.power += self.power_add;
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
        return if (self.isPowered()) self.powered_luminescence else self.unpowered_luminescence;
    }
};

pub const Prop = struct {
    id: []const u8 = "",
    name: []const u8,
    tile: u21,
    fg: ?u32 = null,
    bg: ?u32 = null,
    walkable: bool = true,
    opacity: f64 = 0.0,
    coord: Coord = Coord.new(0, 0),
};

pub const SurfaceItemTag = enum { Machine, Prop, Sob };
pub const SurfaceItem = union(SurfaceItemTag) { Machine: *Machine, Prop: *Prop, Sob: *Sob };

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
    id: []const u8,
    name: []const u8,
    main_damage: DamageType,
    damages: Damages,
    count: usize = 1,
    type: ProjectileType,

    pub const ProjectileType = enum { Bolt };
};

pub const Weapon = struct {
    id: []const u8,
    name: []const u8,
    required_strength: usize,
    damages: Damages,
    main_damage: DamageType,
    secondary_damage: ?DamageType,
    launcher: ?Launcher = null,

    pub const Launcher = struct {
        need: Projectile.ProjectileType,
    };
};

pub const Potion = struct {
    // Potion of <name>
    name: []const u8,

    type: union(enum) {
        Status: Status,
        Gas: usize,
        Custom: fn (dork: ?*Mob) void,
    },

    color: u32,
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

// TODO: make corpse a surfaceitem? (if a mob dies over a surface item just dump it
// on a nearby tile)
pub const Item = union(enum) {
    Corpse: *Mob,
    Ring: *Ring,
    Potion: *Potion,
    Armor: *Armor,
    Weapon: *Weapon,
    Projectile: *Projectile,

    pub fn shortName(self: *const Item) !StackBuffer(u8, 128) {
        var buf = StackBuffer(u8, 128).init(&([_]u8{0} ** 128));
        var fbs = std.io.fixedBufferStream(buf.slice());
        switch (self.*) {
            .Corpse => |c| try fmt.format(fbs.writer(), "{} corpse", .{c.species}),
            .Ring => |r| try fmt.format(fbs.writer(), "ring of {}", .{r.name}),
            .Potion => |p| try fmt.format(fbs.writer(), "potion of {}", .{p.name}),
            .Armor => |a| try fmt.format(fbs.writer(), "{} armor", .{a.name}),
            .Weapon => |w| try fmt.format(fbs.writer(), "{}", .{w.name}),
            .Projectile => |p| try fmt.format(fbs.writer(), "[{}] {}", .{ p.count, p.name }),
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

    pub const LAVA_LIGHT_INTENSITY: usize = 175;
};

pub const Tile = struct {
    material: *const Material = &materials.Basalt,
    type: TileType = .Wall,
    mob: ?*Mob = null,
    marked: bool = false,
    surface: ?SurfaceItem = null,
    item: ?Item = null,

    pub fn emittedLightIntensity(self: *const Tile) usize {
        if (self.type == .Lava)
            return TileType.LAVA_LIGHT_INTENSITY;

        var l: usize = 0;
        if (self.surface) |surface| {
            switch (surface) {
                .Machine => |m| l += m.luminescence(),
                else => {},
            }
        }
        return l;
    }

    pub fn displayAs(coord: Coord) termbox.tb_cell {
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
                        .Potion => |potion| {
                            cell.ch = '¡';
                            cell.fg = potion.color;
                            cell.bg = color;
                        },
                        .Weapon => |_| {
                            cell.ch = '≥'; // TODO: use U+1F5E1?
                            cell.bg = color;
                        },
                        .Armor => |_| {
                            cell.ch = '&'; // TODO: use U+1F6E1?
                            cell.bg = color;
                        },
                        .Projectile => |_| {
                            cell.ch = '≥';
                            cell.bg = color;
                        },
                        else => cell.ch = '?',
                    }
                } else if (state.dungeon.at(coord).surface) |surfaceitem| {
                    var fg: ?u32 = null;
                    var bg: ?u32 = null;

                    const ch = switch (surfaceitem) {
                        .Machine => |m| m.tile(),
                        .Prop => |p| prop: {
                            if (p.bg) |prop_bg| bg = prop_bg;
                            if (p.fg) |prop_fg| fg = prop_fg;
                            break :prop p.tile;
                        },
                        .Sob => |s| s.tile,
                    };

                    cell.ch = ch;
                    cell.fg = fg orelse 0xffffff;
                    cell.bg = bg orelse color;
                } else {
                    cell.ch = ' ';
                    cell.bg = color;
                }
            },
        }

        if (self.type != .Wall) {
            const light = math.clamp(state.dungeon.lightIntensityAt(coord).*, 0, 100);
            const light_adj = @floatToInt(usize, math.round(@intToFloat(f64, light) / 10) * 10);
            cell.bg = math.max(utils.percentageOfColor(cell.bg, light_adj), utils.darkenColor(cell.bg, 3));
            cell.fg = math.max(utils.percentageOfColor(cell.fg, light_adj), utils.darkenColor(cell.fg, 3));
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
    gas: [LEVELS][HEIGHT][WIDTH][gas.GAS_NUM]f64 = [1][HEIGHT][WIDTH][gas.GAS_NUM]f64{[1][WIDTH][gas.GAS_NUM]f64{[1][gas.GAS_NUM]f64{[1]f64{0} ** gas.GAS_NUM} ** WIDTH} ** HEIGHT} ** LEVELS,
    sound: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    light_intensity: [LEVELS][HEIGHT][WIDTH]usize = [1][HEIGHT][WIDTH]usize{[1][WIDTH]usize{[1]usize{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    light_color: [LEVELS][HEIGHT][WIDTH]u32 = [1][HEIGHT][WIDTH]u32{[1][WIDTH]u32{[1]u32{0} ** WIDTH} ** HEIGHT} ** LEVELS,
    rooms: [LEVELS]RoomArrayList = undefined,
    // true == cave, false == rooms
    layout: [LEVELS][HEIGHT][WIDTH]bool = undefined,

    pub fn hasMachine(self: *Dungeon, c: Coord) bool {
        if (self.at(c).surface) |surface| {
            switch (surface) {
                .Machine => |_| return true,
                else => {},
            }
        }

        return false;
    }

    pub fn neighboringMachines(self: *Dungeon, c: Coord) usize {
        var machs: usize = if (self.hasMachine(c)) 1 else 0;
        for (&DIRECTIONS) |d| {
            var neighbor = c;
            if (!neighbor.move(d, state.mapgeometry)) continue;
            if (self.hasMachine(neighbor)) machs += 1;
        }
        return machs;
    }

    pub fn neighboringWalls(self: *Dungeon, c: Coord, diags: bool) usize {
        const directions = if (diags) &DIRECTIONS else &CARDINAL_DIRECTIONS;

        var walls: usize = if (self.at(c).type == .Wall) 1 else 0;
        for (directions) |d| {
            var neighbor = c;
            if (!neighbor.move(d, state.mapgeometry)) {
                walls += 1;
                continue;
            }
            if (self.at(neighbor).type == .Wall) walls += 1;
        }
        return walls;
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
    .max_HP = 20,
    .memory_duration = 10,
    .base_speed = 65,

    .HP = 20,
    .strength = 15, // weakling!
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
    .dexterity = 20,
    .hearing = 7,
    .max_HP = 30,
    .memory_duration = 3,
    .base_speed = 110,

    .HP = 30,
    .strength = 20,
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
    .dexterity = 21,
    .hearing = 5,
    .max_HP = 30,
    .memory_duration = 10,
    .base_speed = 80,

    .HP = 30,
    .strength = 19,
};

pub const InteractionLaborerTemplate = Mob{
    .id = "interaction_laborer",
    .species = "orc",
    .tile = 'o',
    .occupation = Occupation{
        .work_description = "laboring",
        .work_area = undefined,
        .work_fn = ai.interactionLaborerWork,
        .is_combative = false,
        .target = null,
        .phase = .Work,
    },
    .allegiance = .Sauron,
    .vision = 6,

    .willpower = 2,
    .dexterity = 19,
    .hearing = 10,
    .max_HP = 30,
    .memory_duration = 5,
    .base_speed = 100,

    .HP = 30,
    .strength = 10,
};

pub const GoblinTemplate = Mob{
    .species = "goblin",
    .tile = 'g',
    .occupation = Occupation{
        .work_description = "wandering",
        .work_area = undefined,
        .work_fn = ai.wanderWork,
        .is_combative = true,
        .target = null,
        .phase = .Work,
    },
    .allegiance = .NoneEvil,
    .vision = 10,

    .willpower = 3,
    .dexterity = 18,
    .hearing = 5,
    .max_HP = 35,
    .memory_duration = 8,
    .base_speed = 100,

    .HP = 35,
    .strength = 18,
};

pub const CaveRatTemplate = Mob{
    .species = "cave rat",
    .tile = '²',
    .occupation = Occupation{
        .work_description = "wandering",
        .work_area = undefined,
        .work_fn = ai.wanderWork,
        .is_combative = false,
        .target = null,
        .phase = .Work,
    },
    .allegiance = .NoneEvil,
    .vision = 6,

    .willpower = 1,
    .dexterity = 10,
    .hearing = 3,
    .max_HP = 10,
    .memory_duration = 15,
    .base_speed = 40,

    .HP = 10,
    .strength = 5,
};

pub const MOBS = [_]Mob{
    WatcherTemplate,
    GuardTemplate,
    ElfTemplate,
    InteractionLaborerTemplate,
    GoblinTemplate,
};
