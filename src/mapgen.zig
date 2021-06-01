const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;

const rng = @import("rng.zig");
const machines = @import("machines.zig");
const materials = @import("materials.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

const MIN_ROOM_WIDTH: usize = 3;
const MIN_ROOM_HEIGHT: usize = 3;
const MAX_ROOM_WIDTH: usize = 10;
const MAX_ROOM_HEIGHT: usize = 10;

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

fn _add_player(coord: Coord, alloc: *mem.Allocator) void {
    var player = ElfTemplate;
    player.init(alloc);
    player.occupation.phase = .SawHostile;
    player.coord = coord;
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

fn _replace_tiles(room: *const Room, tile: Tile) void {
    var y = room.start.y;
    while (y < room.end().y) : (y += 1) {
        var x = room.start.x;
        while (x < room.end().x) : (x += 1) {
            const c = Coord.new2(room.start.z, x, y);
            if (y >= HEIGHT or x >= WIDTH) continue;
            if (state.dungeon.at(c).type == tile.type) continue;
            state.dungeon.at(c).* = tile;
        }
    }
}

fn _excavate(room: *const Room, ns: bool, ew: bool) void {
    _replace_tiles(room, Tile{ .type = .Floor });
}

fn _place_rooms(rooms: *RoomArrayList, level: usize, count: usize, allocator: *mem.Allocator) void {
    const limit = Room{ .start = Coord.new(0, 0), .width = state.WIDTH, .height = state.HEIGHT };
    const distances = [2][6]usize{ .{ 0, 1, 2, 3, 4, 8 }, .{ 3, 8, 4, 3, 2, 1 } };
    const side = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);

    const parent = rng.chooseUnweighted(Room, rooms.items);
    const distance = rng.choose(usize, &distances[0], &distances[1]) catch unreachable;

    sides: {
        var child_w = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
        var child_h = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);
        var child = parent.attach(side, child_w, child_h, distance);

        while (_room_intersects(rooms, &child, &parent) or child.overflowsLimit(&limit)) {
            if (child_w < MIN_ROOM_WIDTH or child_h < MIN_ROOM_HEIGHT)
                break :sides;

            child_w -= 1;
            child_h -= 1;
            child = parent.attach(side, child_w, child_h, distance);
        }

        _excavate(&child, true, true);
        rooms.append(child) catch unreachable;

        // --- add mobs ---

        if (rng.onein(14)) {
            const post_x = rng.range(usize, child.start.x + 1, child.end().x - 1);
            const post_y = rng.range(usize, child.start.y + 1, child.end().y - 1);
            const post_coord = Coord.new2(level, post_x, post_y);
            var watcher = WatcherTemplate;
            watcher.init(allocator);
            watcher.occupation.work_area.append(post_coord) catch unreachable;
            watcher.coord = post_coord;
            watcher.facing = .North;
            state.mobs.append(watcher) catch unreachable;
            state.dungeon.at(post_coord).mob = state.mobs.lastPtr().?;
        }

        // --- add machines ---

        if (rng.onein(4)) {
            const trap_x = rng.range(usize, child.start.x + 1, child.end().x - 1);
            const trap_y = rng.range(usize, child.start.y + 1, child.end().y - 1);
            const trap_coord = Coord.new2(level, trap_x, trap_y);
            var trap: Machine = undefined;
            if (rng.onein(3)) {
                trap = machines.AlarmTrap;
            } else {
                trap = machines.PoisonGasTrap;
                var num_of_vents = rng.range(usize, 1, 3);
                while (num_of_vents > 0) : (num_of_vents -= 1) {
                    const vent_x = rng.range(usize, child.start.x + 1, child.end().x - 1);
                    const vent_y = rng.range(usize, child.start.y + 1, child.end().y - 1);
                    const vent_coord = Coord.new2(level, vent_x, vent_y);
                    trap.props[num_of_vents] = _place_prop(vent_coord, &machines.GasVentProp);
                }
            }
            _place_machine(trap_coord, &trap);
        }

        if (rng.onein(6)) {
            const loot_x = rng.range(usize, child.start.x + 1, child.end().x - 1);
            const loot_y = rng.range(usize, child.start.y + 1, child.end().y - 1);
            const loot_coord = Coord.new2(level, loot_x, loot_y);
            _place_machine(loot_coord, &machines.GoldCoins);
        }

        // --- add corridors ---

        if (distance > 0) {
            const rsx = math.max(parent.start.x, child.start.x);
            const rex = math.min(parent.end().x, child.end().x);
            const x = rng.range(usize, math.min(rsx, rex), math.max(rsx, rex) - 1);
            const rsy = math.max(parent.start.y, child.start.y);
            const rey = math.min(parent.end().y, child.end().y);
            const y = rng.range(usize, math.min(rsy, rey), math.max(rsy, rey) - 1);

            var corridor = switch (side) {
                .North => Room{ .start = Coord.new2(level, x, child.end().y), .height = parent.start.y - child.end().y, .width = 1 },
                .South => Room{ .start = Coord.new2(level, x, parent.end().y), .height = child.start.y - parent.end().y, .width = 1 },
                .West => Room{ .start = Coord.new2(level, child.end().x, y), .height = 1, .width = parent.start.x - child.end().x },
                .East => Room{ .start = Coord.new2(level, parent.end().x, y), .height = 1, .width = child.start.x - parent.end().x },
                else => unreachable,
            };

            _excavate(&corridor, side == .East or side == .West, side == .North or side == .South);
            rooms.append(corridor) catch unreachable;

            if (distance == 1) _place_normal_door(corridor.start);
        }
    }

    if (count > 0) _place_rooms(rooms, level, count - 1, allocator);
}

pub fn placeRandomRooms(level: usize, num: usize, allocator: *mem.Allocator) void {
    var rooms = RoomArrayList.init(allocator);

    const width = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
    const height = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);
    const x = rng.range(usize, 1, state.WIDTH / 2);
    const y = rng.range(usize, 1, state.HEIGHT / 2);
    const first = Room{ .start = Coord.new2(level, x, y), .width = width, .height = height };
    _excavate(&first, true, true);
    rooms.append(first) catch unreachable;

    if (level == PLAYER_STARTING_LEVEL) {
        const p = Coord.new2(PLAYER_STARTING_LEVEL, first.start.x + 1, first.start.y + 1);
        _add_player(p, allocator);
    }

    _place_rooms(&rooms, level, num, allocator);

    state.dungeon.rooms[level] = rooms;
}

pub fn placePatrolSquads(level: usize, allocator: *mem.Allocator) void {
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

// pub fn drunken_walk() void {
//     const center_weight = 20;
//     const fill_goal = @intToFloat(f64, state.WIDTH * state.HEIGHT) * 0.35;
//     const prev_direction_weight = 90;
//     const max_iterations = 5000;

//     var prev_direction: Direction = .North;
//     var filled: usize = 0;
//     var iterations: usize = 0;
//     var walker = Coord.new(state.WIDTH / 2, state.HEIGHT / 2);

//     while (true) {
//         // probability of going in a direction
//         var north: usize = 100;
//         var south: usize = 100;
//         var east: usize = 100;
//         var west: usize = 100;

//         if (state.WIDTH > state.HEIGHT) {
//             east += ((state.WIDTH * 100) / state.HEIGHT);
//             west += ((state.WIDTH * 100) / state.HEIGHT);
//         } else if (state.HEIGHT > state.WIDTH) {
//             north += ((state.HEIGHT * 100) / state.WIDTH);
//             south += ((state.HEIGHT * 100) / state.WIDTH);
//         }

//         // weight the random walk against map edges
//         if (@intToFloat(f64, walker.x) < (@intToFloat(f64, state.WIDTH) * 0.25)) {
//             // walker is at far left
//             east += center_weight;
//         } else if (@intToFloat(f64, walker.x) > (@intToFloat(f64, state.WIDTH) * 0.75)) {
//             // walker is at far right
//             west += center_weight;
//         }

//         if (@intToFloat(f64, walker.y) < (@intToFloat(f64, state.HEIGHT) * 0.25)) {
//             // walker is at the top
//             south += center_weight;
//         } else if (@intToFloat(f64, walker.y) > (@intToFloat(f64, state.HEIGHT) * 0.75)) {
//             // walker is at the bottom
//             north += center_weight;
//         }

//         // Don't break into a previously-built enclosure
//         // TODO

//         // weight the walker to previous direction
//         switch (prev_direction) {
//             .North => north += prev_direction_weight,
//             .South => south += prev_direction_weight,
//             .West => west += prev_direction_weight,
//             .East => east += prev_direction_weight,
//             else => unreachable,
//         }

//         // normalize probabilities
//         const total = north + south + east + west;
//         north = north * 100 / total;
//         south = south * 100 / total;
//         east = east * 100 / total;
//         west = west * 100 / total;

//         // choose direction
//         var directions = CARDINAL_DIRECTIONS;
//         rng.shuffle(Direction, &directions);

//         const direction = rng.choose(Direction, &CARDINAL_DIRECTIONS, &[_]usize{ north, south, east, west }) catch unreachable;

//         if (walker.move(direction, Coord.new(state.WIDTH, state.HEIGHT))) {
//             if (state.dungeon[walker.y][walker.x].type == .Wall) {
//                 filled += 1;
//                 state.dungeon[walker.y][walker.x].type = .Floor;
//                 prev_direction = direction;
//             } else {
//                 prev_direction = direction.opposite();
//                 if (rng.boolean()) {
//                     prev_direction = direction.turnright();
//                 } else {
//                     prev_direction = direction.turnleft();
//                 }
//             }
//         } else {
//             prev_direction = direction.opposite();
//         }

//         iterations += 1;
//         if (filled > fill_goal or iterations > max_iterations)
//             break;
//     }
// }
