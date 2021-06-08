const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const rng = @import("rng.zig");
const items = @import("items.zig");
const machines = @import("machines.zig");
const materials = @import("materials.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

// Dimensions include the first wall, so a minimum width of 2 guarantee that
// there will be one empty space in the room, minimum.
const MIN_ROOM_WIDTH: usize = 4;
const MIN_ROOM_HEIGHT: usize = 4;
const MAX_ROOM_WIDTH: usize = 10;
const MAX_ROOM_HEIGHT: usize = 10;

// FIXME: these '- 1's shouldn't have to be there, but, uh, weird things happen
// if they're removed.
const LIMIT = Room{ .start = Coord.new(0, 0), .width = state.WIDTH, .height = state.HEIGHT };
const DISTANCES = [2][6]usize{ .{ 0, 1, 2, 3, 4, 8 }, .{ 3, 8, 4, 3, 2, 1 } };

fn _place_prop(coord: Coord, prop_template: *const Prop) *Prop {
    var prop = prop_template.*;
    prop.coord = coord;
    state.props.append(prop) catch unreachable;
    const propptr = state.props.lastPtr().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Prop = propptr };
    return state.props.lastPtr().?;
}

fn _place_machine(coord: Coord, machine_template: *const Machine) void {
    var machine = machine_template.*;
    machine.coord = coord;
    state.machines.append(machine) catch unreachable;
    const machineptr = state.machines.lastPtr().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = machineptr };
}

fn _place_normal_door(coord: Coord) void {
    var door = machines.NormalDoor;
    door.coord = coord;
    state.machines.append(door) catch unreachable;
    const doorptr = state.machines.lastPtr().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = doorptr };
    state.dungeon.at(coord).type = .Floor;
}

// STYLE: make top level public func, call directly, rename placePlayer
fn _add_player(coord: Coord, alloc: *mem.Allocator) void {
    var echoring = items.EcholocationRing;
    echoring.worn_since = state.ticks;
    state.rings.append(echoring) catch @panic("OOM");
    const echoringptr = state.rings.lastPtr().?;

    var player = ElfTemplate;
    player.init(alloc);
    player.occupation.phase = .SawHostile;
    player.coord = coord;
    player.inventory.r_rings[0] = echoringptr;
    state.mobs.append(player) catch unreachable;
    state.dungeon.at(coord).mob = state.mobs.lastPtr().?;
    state.player = state.mobs.lastPtr().?;
}

fn _room_intersects(rooms: *const RoomArrayList, room: *const Room, ignore: *const Room) bool {
    if (room.start.x == 0 or room.start.y == 0)
        return true;
    if (room.start.x >= state.WIDTH or room.start.y >= state.HEIGHT)
        return true;
    if (room.end().x >= state.WIDTH or room.end().y >= state.HEIGHT)
        return true;

    for (rooms.items) |otherroom| {
        // Yes, I understand that this is ugly. No, I don't care.
        if (otherroom.start.eq(ignore.start))
            if (otherroom.width == ignore.width)
                if (otherroom.height == ignore.height)
                    continue;
        if (room.intersects(&otherroom, 1)) return true;
    }

    return false;
}

fn _excavate_prefab(room: *const Room, fab: *const Prefab) void {
    var y: usize = 0;
    while (y < fab.height) : (y += 1) {
        var x: usize = 0;
        while (x < fab.width) : (x += 1) {
            const rc = Coord.new2(room.start.z, x + room.start.x, y + room.start.y);
            assert(rc.x < WIDTH);
            assert(rc.y < HEIGHT);

            const tt: ?TileType = switch (fab.content[y][x]) {
                .Any => null,
                .Wall, .Connection => .Wall,
                .Lamp, .Floor => .Floor,
                .Water => .Water,
                .Lava => .Lava,
                .Window => @panic("todo"),
            };
            if (tt) |_tt| state.dungeon.at(rc).type = _tt;

            switch (fab.content[y][x]) {
                .Lamp => _place_machine(rc, &machines.Lamp),
                .Window => @panic("todo"),
                else => {},
            }
        }
    }
}

fn _excavate_room(room: *const Room) void {
    var y = room.start.y;
    while (y < room.end().y) : (y += 1) {
        var x = room.start.x;
        while (x < room.end().x) : (x += 1) {
            const c = Coord.new2(room.start.z, x, y);
            assert(c.x < WIDTH and c.y < HEIGHT);
            state.dungeon.at(c).type = .Floor;
        }
    }
}

fn _place_rooms(rooms: *RoomArrayList, fabs: *const PrefabArrayList, level: usize, allocator: *mem.Allocator) void {
    // parent is non-const because we might need to update connectors on it.
    var parent = rng.chooseUnweighted(Room, rooms.items);

    var fab: ?Prefab = null;
    var distance = rng.choose(usize, &DISTANCES[0], &DISTANCES[1]) catch unreachable;
    var child: Room = undefined;
    var side = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);

    if (rng.onein(3)) {
        if (parent.prefab != null and distance == 0) distance += 1;

        var child_w = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
        var child_h = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);
        child = parent.attach(side, child_w, child_h, distance, null) orelse return;

        while (_room_intersects(rooms, &child, &parent) or child.overflowsLimit(&LIMIT)) {
            if (child_w < MIN_ROOM_WIDTH or child_h < MIN_ROOM_HEIGHT)
                return;

            child_w -= 1;
            child_h -= 1;
            child = parent.attach(side, child_w, child_h, distance, null).?;
        }

        _excavate_room(&child);
    } else {
        if (distance == 0) distance += 1;

        var child_w = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
        var child_h = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);
        fab = rng.chooseUnweighted(Prefab, fabs.items);
        child = parent.attach(side, fab.?.width, fab.?.height, distance, &fab.?) orelse return;
        child.prefab = fab;

        if (_room_intersects(rooms, &child, &parent) or child.overflowsLimit(&LIMIT))
            return;

        _excavate_prefab(&child, &fab.?);
    }

    rooms.append(child) catch unreachable;

    // --- add machines ---

    if (rng.onein(2)) {
        const trap_coord = child.randomCoord();
        var trap: Machine = undefined;
        if (rng.onein(3)) {
            trap = machines.AlarmTrap;
        } else {
            trap = if (rng.onein(3)) machines.PoisonGasTrap else machines.ParalysisGasTrap;
            var num_of_vents = rng.range(usize, 1, 3);
            while (num_of_vents > 0) : (num_of_vents -= 1) {
                const prop = _place_prop(child.randomCoord(), &machines.GasVentProp);
                trap.props[num_of_vents] = prop;
            }
        }
        _place_machine(trap_coord, &trap);
    }

    if (rng.onein(6)) {
        _place_machine(child.randomCoord(), &machines.GoldCoins);
    }

    // --- add corridors ---

    if (distance > 0) corridor: {
        var cor = Coord.new2(level, 0, 0);
        if (parent.prefab) |*f| {
            const con = f.connectorFor(side) orelse break :corridor;
            cor.x = parent.start.x + con.x;
            cor.y = parent.start.y + con.y;
            f.useConnector(con) catch unreachable;
        } else if (child.prefab) |*f| {
            const con = f.connectorFor(side.opposite()) orelse break :corridor;
            cor.x = child.start.x + con.x;
            cor.y = child.start.y + con.y;
            f.useConnector(con) catch unreachable;
        } else {
            const rsx = math.max(parent.start.x, child.start.x);
            const rex = math.min(parent.end().x, child.end().x);
            const rsy = math.max(parent.start.y, child.start.y);
            const rey = math.min(parent.end().y, child.end().y);
            cor.x = rng.range(usize, math.min(rsx, rex), math.max(rsx, rex) - 1);
            cor.y = rng.range(usize, math.min(rsy, rey), math.max(rsy, rey) - 1);
        }

        var corridor = switch (side) {
            .North => Room{ .start = Coord.new2(level, cor.x, child.end().y), .height = parent.start.y - (child.end().y - 1), .width = 1 },
            .South => Room{ .start = Coord.new2(level, cor.x, parent.end().y), .height = child.start.y - (parent.end().y - 1), .width = 1 },
            .West => Room{ .start = Coord.new2(level, child.end().x, cor.y), .height = 1, .width = parent.start.x - (child.end().x - 1) },
            .East => Room{ .start = Coord.new2(level, parent.end().x, cor.y), .height = 1, .width = child.start.x - (parent.end().x - 1) },
            else => unreachable,
        };

        _excavate_room(&corridor);

        // When using a prefab, the corridor doesn't include the connectors. Excavate
        // the connector manually.
        state.dungeon.at(cor).type = .Floor;

        if (distance == 1) _place_normal_door(corridor.start);
    }
}

pub fn placeRandomRooms(fabs: *const PrefabArrayList, level: usize, num: usize, allocator: *mem.Allocator) void {
    var rooms = RoomArrayList.init(allocator);

    const width = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
    const height = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);
    const x = rng.range(usize, 1, state.WIDTH / 2);
    const y = rng.range(usize, 1, state.HEIGHT / 2);
    const first = Room{ .start = Coord.new2(level, x, y), .width = width, .height = height };
    _excavate_room(&first);
    rooms.append(first) catch unreachable;

    if (level == PLAYER_STARTING_LEVEL) {
        const p = Coord.new2(PLAYER_STARTING_LEVEL, first.start.x + 1, first.start.y + 1);
        _add_player(p, allocator);
    }

    var c = num;
    while (c > 0) : (c -= 1) _place_rooms(&rooms, fabs, level, allocator);

    state.dungeon.rooms[level] = rooms;
}

pub fn placeGuards(level: usize, allocator: *mem.Allocator) void {
    var squads: usize = rng.range(usize, 3, 5);
    while (squads > 0) : (squads -= 1) {
        const room = rng.chooseUnweighted(Room, state.dungeon.rooms[level].items);
        const patrol_units = rng.range(usize, 2, 4) % math.max(room.width, room.height);
        var patrol_warden: ?*Mob = null;

        var placed_units: usize = 0;
        while (placed_units < patrol_units) {
            const rnd = room.randomCoord();

            if (state.dungeon.at(rnd).mob == null) {
                var guard = GuardTemplate;
                guard.init(allocator);
                guard.occupation.work_area.append(rnd) catch unreachable;
                guard.coord = rnd;
                state.mobs.append(guard) catch unreachable;
                const mobptr = state.mobs.lastPtr().?;
                state.dungeon.at(rnd).mob = mobptr;

                if (patrol_warden) |warden| {
                    warden.squad_members.append(mobptr) catch unreachable;
                } else {
                    patrol_warden = mobptr;
                }

                placed_units += 1;
            }
        }
    }

    for (state.dungeon.rooms[level].items) |room| {
        if (rng.onein(14)) {
            const post_coord = room.randomCoord();
            var watcher = WatcherTemplate;
            watcher.init(allocator);
            watcher.occupation.work_area.append(post_coord) catch unreachable;
            watcher.coord = post_coord;
            watcher.facing = .North;
            state.mobs.append(watcher) catch unreachable;
            state.dungeon.at(post_coord).mob = state.mobs.lastPtr().?;
        }
    }
}

pub fn placeLights(level: usize) void {
    for (state.dungeon.rooms[level].items) |room| {
        // Don't light small rooms.
        if ((room.width * room.height) < 16)
            continue;

        var spacing: usize = rng.range(usize, 0, 2);
        var y: usize = 0;
        while (y < room.height) : (y += 1) {
            if (spacing == 0) {
                spacing = rng.range(usize, 4, 8);

                const coord1 = Coord.new2(level, room.start.x, room.start.y + y);
                var lamp1 = machines.Lamp;
                lamp1.luminescence -= rng.range(usize, 0, 30);

                const coord2 = Coord.new2(level, room.end().x - 1, room.start.y + y);
                var lamp2 = machines.Lamp;
                lamp2.luminescence -= rng.range(usize, 0, 30);

                if (!state.dungeon.hasMachine(coord1) and
                    state.dungeon.neighboringWalls(coord1, false) == 1 and
                    state.dungeon.neighboringMachines(coord1) == 0 and
                    state.dungeon.at(coord1).type == .Floor)
                {
                    _place_machine(coord1, &lamp1);
                }

                if (!state.dungeon.hasMachine(coord2) and
                    state.dungeon.neighboringWalls(coord2, false) == 1 and
                    state.dungeon.neighboringMachines(coord2) == 0 and
                    state.dungeon.at(coord2).type == .Floor)
                {
                    _place_machine(coord2, &lamp2);
                }
            }

            spacing -= 1;
        }
    }
}

pub fn placeRandomStairs(level: usize) void {
    if (level == (state.LEVELS - 1)) {
        return;
    }

    var placed: usize = 0;
    while (placed < 5) {
        const rand_x = rng.range(usize, 1, state.WIDTH - 1);
        const rand_y = rng.range(usize, 1, state.HEIGHT - 1);
        const above = Coord.new2(level, rand_x, rand_y);
        const below = Coord.new2(level + 1, rand_x, rand_y);

        if (state.dungeon.at(below).type != .Wall and state.dungeon.at(above).type != .Wall) { // FIXME
            _place_machine(above, &machines.StairDown);
            _place_machine(below, &machines.StairUp);
        }

        placed += 1;
    }
}

pub fn cellularAutomata(level: usize, wall_req: usize, isle_req: usize) void {
    var old: [HEIGHT][WIDTH]TileType = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1)
                old[y][x] = state.dungeon.at(Coord.new2(level, x, y)).type;
        }
    }

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);

            var neighbor_walls: usize = if (old[coord.y][coord.x] == .Wall) 1 else 0;
            for (&DIRECTIONS) |direction| {
                var new = coord;
                if (!new.move(direction, state.mapgeometry))
                    continue;
                if (old[new.y][new.x] == .Wall)
                    neighbor_walls += 1;
            }

            if (neighbor_walls >= wall_req) {
                state.dungeon.at(coord).type = .Wall;
            } else if (neighbor_walls <= isle_req) {
                state.dungeon.at(coord).type = .Wall;
            } else {
                state.dungeon.at(coord).type = .Floor;
            }
        }
    }
}

pub fn fillBar(level: usize, height: usize) void {
    // add a horizontal bar of floors in the center of the map as it may
    // prevent a continuous vertical wall from forming during cellular automata,
    // thus preventing isolated sections
    const halfway = HEIGHT / 2;
    var y: usize = halfway;
    while (y < (halfway + height)) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            state.dungeon.at(Coord.new2(level, x, y)).type = .Floor;
        }
    }
}

pub fn fillRandom(level: usize, floor_chance: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const t: TileType = if (rng.range(usize, 0, 100) > floor_chance) .Wall else .Floor;
            state.dungeon.at(Coord.new2(level, x, y)).type = t;
        }
    }
}

pub const Prefab = struct {
    allow_spawning: bool = true,
    allow_traps: bool = true,

    height: usize = 0,
    width: usize = 0,
    content: [20][20]FabTile = undefined,
    connections: [40]?Connection = undefined,

    pub const FabTile = enum {
        Wall, Lamp, Floor, Connection, Water, Lava, Window, Any
    };

    pub const Connection = struct {
        c: Coord,
        d: Direction,
        used: bool = false,
    };

    pub fn useConnector(self: *Prefab, c: Coord) !void {
        for (self.connections) |maybe_con, i| {
            const con = maybe_con orelse break;
            if (con.c.eq(c)) {
                if (con.used) return error.ConnectorAlreadyUsed;
                self.connections[i].?.used = true;
                return;
            }
        }
        return error.NoSuchConnector;
    }

    pub fn connectorFor(self: *const Prefab, d: Direction) ?Coord {
        for (self.connections) |maybe_con| {
            const con = maybe_con orelse break;
            if (con.d == d and !con.used) return con.c;
        }
        return null;
    }

    pub fn parse(from: []const u8) !Prefab {
        var f: Prefab = .{};
        for (f.content) |*row| mem.set(FabTile, row, .Wall);
        mem.set(?Connection, &f.connections, null);

        var ci: usize = 0; // index for f.connections
        var w: usize = 0;
        var y: usize = 0;

        var lines = mem.tokenize(from, "\n");
        while (lines.next()) |line| {
            switch (line[0]) {
                '%' => {}, // ignore comments
                '@' => @panic("TODO"), // TODO
                else => {
                    if (y > f.content.len) return error.FabTooTall;

                    var x: usize = 0;
                    var utf8 = (try std.unicode.Utf8View.init(line)).iterator();
                    while (utf8.nextCodepointSlice()) |encoded_codepoint| : (x += 1) {
                        if (x > f.content[0].len) return error.FabTooWide;

                        const c = try std.unicode.utf8Decode(encoded_codepoint);

                        f.content[y][x] = switch (c) {
                            '#' => .Wall,
                            '•' => .Lamp,
                            '.' => .Floor,
                            '*' => con: {
                                f.connections[ci] = .{
                                    .c = Coord.new(x, y),
                                    .d = .North,
                                };
                                ci += 1;

                                break :con .Connection;
                            },
                            '~' => .Water,
                            '≈' => .Lava,
                            ';' => .Window,
                            '?' => .Any,
                            else => return error.InvalidFabTile,
                        };
                    }

                    if (x > w) w = x;
                    y += 1;
                },
            }
        }

        f.width = w;
        f.height = y;

        for (&f.connections) |*con, i| {
            if (con.*) |c| {
                if (c.c.x == 0) {
                    f.connections[i].?.d = .West;
                } else if (c.c.y == 0) {
                    f.connections[i].?.d = .North;
                } else if (c.c.y == (f.height - 1)) {
                    f.connections[i].?.d = .South;
                } else if (c.c.x == (f.width - 1)) {
                    f.connections[i].?.d = .East;
                } else {
                    return error.InvalidConnection;
                }
            }
        }

        return f;
    }
};

pub const PrefabArrayList = std.ArrayList(Prefab);

// FIXME: error handling
pub fn readPrefabs(alloc: *mem.Allocator) PrefabArrayList {
    var buf: [2048]u8 = undefined;
    var fabs = PrefabArrayList.init(alloc);

    const fabs_dir = std.fs.cwd().openDir("prefabs", .{
        .iterate = true,
    }) catch unreachable;

    var fabs_dir_iterator = fabs_dir.iterate();
    while (fabs_dir_iterator.next() catch unreachable) |fab_file| {
        if (fab_file.kind != .File) continue;

        var fab_f = fabs_dir.openFile(fab_file.name, .{
            .read = true,
            .lock = .None,
        }) catch unreachable;
        defer fab_f.close();

        const read = fab_f.readAll(buf[0..]) catch unreachable;
        const f = Prefab.parse(buf[0..read]) catch unreachable;
        fabs.append(f) catch @panic("OOM");
    }

    return fabs;
}
