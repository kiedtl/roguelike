const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;

const rng = @import("rng.zig");
const machines = @import("machines.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

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

// fn _add_guard_station(stationy: usize, stationx: usize, d: Direction, alloc: *mem.Allocator) void {
//     var guard = GuardTemplate;
//     guard.occupation.work_area = CoordArrayList.init(alloc);
//     guard.occupation.work_area.append(Coord.new(stationx, stationy)) catch unreachable;
//     guard.occupation.work_area.append(Coord.new(stationx, stationy)) catch unreachable;
//     guard.fov = CoordArrayList.init(alloc);
//     guard.memory = CoordCellMap.init(alloc);
//     guard.coord = Coord.new(stationx, stationy);
//     guard.facing = d;
//     state.dungeon[stationy][stationx].mob = guard;
// }

// pub fn add_guard_stations(alloc: *mem.Allocator) void {
//     // --- Guard route patterns ---
//     const patterns = [_][9]TileType{
//         // ###
//         // #G.
//         // #..
//         [_]TileType{ .Wall, .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Floor, .Floor },
//         // ###
//         // .G#
//         // .##
//         [_]TileType{ .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Floor, .Wall, .Wall },
//         // ###
//         // #G.
//         // ###
//         [_]TileType{ .Wall, .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Wall, .Wall },
//     };
//     // Too lazy to combine this with the previous constant in a struct
//     const pattern_directions = [_]Direction{ .East, .West, .East };

//     var y: usize = 1;
//     while (y < (state.HEIGHT - 1)) : (y += 1) {
//         var x: usize = 1;
//         while (x < (state.WIDTH - 1)) : (x += 1) {
//             const neighbors = [_]TileType{
//                 state.dungeon[y - 1][x - 1].type,
//                 state.dungeon[y - 1][x - 0].type,
//                 state.dungeon[y - 1][x + 1].type,
//                 state.dungeon[y + 0][x - 1].type,
//                 state.dungeon[y + 0][x - 0].type,
//                 state.dungeon[y + 0][x + 1].type,
//                 state.dungeon[y + 1][x - 1].type,
//                 state.dungeon[y + 1][x - 0].type,
//                 state.dungeon[y + 1][x + 1].type,
//             };

//             for (patterns) |pattern, index| {
//                 if (std.mem.eql(TileType, &neighbors, &pattern)) {
//                     const d = pattern_directions[index];
//                     _add_guard_station(y, x, d, alloc);
//                     break;
//                 }
//             }
//         }
//     }
// }

fn _add_player(coord: Coord, alloc: *mem.Allocator) void {
    var player = ElfTemplate;
    player.occupation.work_area = CoordArrayList.init(alloc);
    player.occupation.phase = .SawHostile;
    player.fov = CoordArrayList.init(alloc);
    player.memory = CoordCellMap.init(alloc);
    player.coord = coord;
    state.mobs.append(player) catch unreachable;
    state.dungeon.at(coord).mob = state.mobs.lastPtr().?;
    state.player = state.mobs.lastPtr().?;
}

const MIN_ROOM_WIDTH: usize = 7;
const MIN_ROOM_HEIGHT: usize = 4;
const MAX_ROOM_WIDTH: usize = 20;
const MAX_ROOM_HEIGHT: usize = 10;

const Room = struct {
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

    pub fn attach(self: *const Room, d: Direction, width: usize, height: usize, distance: usize) Room {
        return switch (d) {
            .North => Room{
                .start = Coord.new2(self.start.z, self.start.x + (self.width / 2), utils.saturating_sub(self.start.y, height + distance)),
                .height = utils.saturating_sub(self.start.y, height),
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
                .width = utils.saturating_sub(self.start.x, width),
                .height = height,
            },
            else => @panic("unimplemented"),
        };
    }
};

var rooms: std.ArrayList(Room) = undefined;

fn _room_intersects(room: *const Room) bool {
    if (room.start.x == 0 or room.start.y == 0)
        return true;
    if (room.start.x >= state.WIDTH or room.start.y >= state.HEIGHT)
        return true;
    if (room.end().x >= state.WIDTH or room.end().y >= state.HEIGHT)
        return true;

    // {
    //     var y = utils.saturating_sub(room.start.y, 1);
    //     while (y < room.end().y + 1) : (y += 1) {
    //         var x = utils.saturating_sub(room.start.x, 1);
    //         while (x < room.end().x + 1) : (x += 1) {
    //             if (state.dungeon[y][x].type != .Wall)
    //                 return true;
    //         }
    //     }
    // }

    for (rooms.items) |otherroom| {
        if (room.intersects(&otherroom, 1)) return true;
    }

    return false;
}

fn _excavate(room: *const Room) void {
    // TODO: assert that all the excavated portions are indeed walls
    var y = room.start.y;
    while (y < room.end().y) : (y += 1) {
        var x = room.start.x;
        while (x < room.end().x) : (x += 1) {
            state.dungeon.at(Coord.new2(room.start.z, x, y)).type = .Floor;
        }
    }
}

fn _place_rooms(level: usize, count: usize, allocator: *mem.Allocator) void {
    const limit = Room{ .start = Coord.new(0, 0), .width = state.WIDTH, .height = state.HEIGHT };
    const distances = [2][5]usize{ .{ 1, 2, 3, 4, 5 }, .{ 9, 8, 3, 2, 1 } };

    sides: for (&CARDINAL_DIRECTIONS) |side| {
        if (rng.range(usize, 0, 5) == 0) continue;

        const parent = rng.chooseUnweighted(Room, rooms.items);
        const distance = rng.choose(usize, &distances[0], &distances[1]) catch unreachable;

        var child_w = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
        var child_h = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);
        var child = parent.attach(side, child_w, child_h, distance);

        while (_room_intersects(&child) or child.overflowsLimit(&limit)) {
            if (child_w < MIN_ROOM_WIDTH or child_h < MIN_ROOM_HEIGHT)
                continue :sides;

            child_w -= 1;
            child_h -= 1;
            child = parent.attach(side, child_w, child_h, distance);
        }

        _excavate(&child);
        rooms.append(child) catch unreachable;

        // --- add mobs ---

        if (rng.onein(2)) {
            const guardstart = Coord.new2(level, child.start.x + 1, child.start.y + 1);
            const guardend = Coord.new2(level, child.end().x - 1, child.end().y - 1);
            var guard = GuardTemplate;
            guard.occupation.work_area = CoordArrayList.init(allocator);
            guard.occupation.work_area.append(guardstart) catch unreachable;
            guard.occupation.work_area.append(guardend) catch unreachable;
            guard.fov = CoordArrayList.init(allocator);
            guard.memory = CoordCellMap.init(allocator);
            guard.coord = guardstart;
            guard.facing = .North;
            state.mobs.append(guard) catch unreachable;
            state.dungeon.at(guardstart).mob = state.mobs.lastPtr().?;
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

        const rsx = math.max(parent.start.x, child.start.x);
        const rex = math.min(parent.end().x, child.end().x);
        const x = rng.range(usize, math.min(rsx, rex), math.max(rsx, rex));
        const rsy = math.max(parent.start.y, child.start.y);
        const rey = math.min(parent.end().y, child.end().y);
        const y = rng.range(usize, math.min(rsy, rey), math.max(rsy, rey));

        var corridor = switch (side) {
            .North => Room{ .start = Coord.new2(level, x, child.end().y), .height = parent.start.y - child.end().y, .width = 1 },
            .South => Room{ .start = Coord.new2(level, x, parent.end().y), .height = child.start.y - parent.end().y, .width = 1 },
            .West => Room{ .start = Coord.new2(level, child.end().x, y), .height = 1, .width = parent.start.x - child.end().x },
            .East => Room{ .start = Coord.new2(level, parent.end().x, y), .height = 1, .width = child.start.x - parent.end().x },
            else => unreachable,
        };

        _excavate(&corridor);

        if (distance == 1) _place_normal_door(corridor.start);
    }

    if (count > 0) _place_rooms(level, count - 1, allocator);
}

pub fn placeRandomRooms(level: usize, allocator: *mem.Allocator) void {
    rooms = std.ArrayList(Room).init(allocator);

    const width = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
    const height = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);
    const x = rng.range(usize, 1, state.WIDTH / 2);
    const y = rng.range(usize, 1, state.HEIGHT / 2);
    const first = Room{ .start = Coord.new2(level, x, y), .width = width, .height = height };
    _excavate(&first);
    rooms.append(first) catch unreachable;

    if (level == PLAYER_STARTING_LEVEL) {
        const p = Coord.new2(PLAYER_STARTING_LEVEL, first.start.x + 1, first.start.y + 1);
        _add_player(p, allocator);
    }

    _place_rooms(level, 100, allocator);

    rooms.deinit();
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
