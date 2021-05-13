const std = @import("std");
const heap = std.heap;
const mem = std.mem;

const rng = @import("rng.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

fn _add_guard_station(stationy: usize, stationx: usize, d: Direction, alloc: *mem.Allocator) void {
    var guard = GuardTemplate;
    guard.occupation.work_area = CoordArrayList.init(alloc);
    guard.occupation.work_area.append(Coord.new(stationx, stationy)) catch unreachable;
    guard.occupation.work_area.append(Coord.new(stationx, stationy)) catch unreachable;
    guard.fov = CoordArrayList.init(alloc);
    guard.memory = CoordCharMap.init(alloc);
    guard.coord = Coord.new(stationx, stationy);
    guard.facing = d;
    state.dungeon[stationy][stationx].mob = guard;
}

pub fn add_guard_stations(alloc: *mem.Allocator) void {
    // --- Guard route patterns ---
    const patterns = [_][9]TileType{
        // ###
        // #G.
        // #..
        [_]TileType{ .Wall, .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Floor, .Floor },
        // ###
        // .G#
        // .##
        [_]TileType{ .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Floor, .Wall, .Wall },
        // ###
        // #G.
        // ###
        [_]TileType{ .Wall, .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Wall, .Wall },
    };
    // Too lazy to combine this with the previous constant in a struct
    const pattern_directions = [_]Direction{ .East, .West, .East };

    var y: usize = 1;
    while (y < (state.HEIGHT - 1)) : (y += 1) {
        var x: usize = 1;
        while (x < (state.WIDTH - 1)) : (x += 1) {
            const neighbors = [_]TileType{
                state.dungeon[y - 1][x - 1].type,
                state.dungeon[y - 1][x - 0].type,
                state.dungeon[y - 1][x + 1].type,
                state.dungeon[y + 0][x - 1].type,
                state.dungeon[y + 0][x - 0].type,
                state.dungeon[y + 0][x + 1].type,
                state.dungeon[y + 1][x - 1].type,
                state.dungeon[y + 1][x - 0].type,
                state.dungeon[y + 1][x + 1].type,
            };

            for (patterns) |pattern, index| {
                if (std.mem.eql(TileType, &neighbors, &pattern)) {
                    const d = pattern_directions[index];
                    _add_guard_station(y, x, d, alloc);
                    break;
                }
            }
        }
    }
}

fn _add_player(coord: Coord, alloc: *mem.Allocator) void {
    state.player = coord;

    var player = ElfTemplate;
    player.occupation.work_area = CoordArrayList.init(alloc);
    player.occupation.phase = .SawHostile;
    player.fov = CoordArrayList.init(alloc);
    player.memory = CoordCharMap.init(alloc);
    player.coord = state.player;
    state.dungeon[state.player.y][state.player.x].mob = player;
}

const MAX_TUNNEL_LENGTH: usize = 12;

const MIN_ROOM_WIDTH: usize = 3;
const MIN_ROOM_HEIGHT: usize = 3;
const MAX_ROOM_WIDTH: usize = 10;
const MAX_ROOM_HEIGHT: usize = 10;

const Room = struct {
    start: Coord,
    width: usize,
    height: usize,

    pub fn end(self: *const Room) Coord {
        return Coord.new(self.start.x + self.width, self.start.y + self.height);
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

    pub fn attach(self: *const Room, d: Direction, width: usize, height: usize) Room {
        return switch (d) {
            .North => Room{
                .start = Coord.new(self.start.x + (self.width / 2), utils.saturating_sub(self.start.y, height + 1)),
                .height = utils.saturating_sub(self.start.y, height),
                .width = width,
            },
            .East => Room{
                .start = Coord.new(self.end().x + 1, self.start.y + (self.height / 2)),
                .height = height,
                .width = width,
            },
            .South => Room{
                .start = Coord.new(self.start.x + (self.width / 2) + 1, self.end().y),
                .height = height,
                .width = width,
            },
            .West => Room{
                .start = Coord.new(utils.saturating_sub(self.start.x, width + 1), self.start.y + (self.height / 2)),
                .width = utils.saturating_sub(self.start.x, width),
                .height = height,
            },
            else => @panic("unimplemented"),
        };
    }
};

var rooms: std.ArrayList(Room) = undefined;

fn _room_intersects(room: *const Room, ignore: Coord) bool {
    if (room.start.x == 0 or room.start.y == 0)
        return true;
    if (room.start.x >= state.WIDTH or room.start.y >= state.HEIGHT)
        return true;
    if (room.end().x >= state.WIDTH or room.end().y >= state.HEIGHT)
        return true;

    {
        var y = utils.saturating_sub(room.start.y, 1);
        while (y < room.end().y + 1) : (y += 1) {
            var x = utils.saturating_sub(room.start.x, 1);
            while (x < room.end().x + 1) : (x += 1) {
                if (Coord.new(x, y).eq(ignore))
                    continue;

                if (state.dungeon[y][x].type != .Wall)
                    return true;
            }
        }
    }

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
            state.dungeon[y][x].type = .Floor;
        }
    }
}

fn _room(direction: Direction, room: *const Room) void {
    const width = rng.range(usize, MIN_ROOM_WIDTH, MAX_ROOM_WIDTH);
    const height = rng.range(usize, MIN_ROOM_HEIGHT, MAX_ROOM_HEIGHT);

    const newroom = room.attach(direction, width, height);

    if (_room_intersects(&newroom, room.start)) return;

    rooms.append(newroom) catch unreachable;
    _excavate(&newroom);
}

fn _tunnel(coord: Coord, previous: Direction) void {
    var directions = CARDINAL_DIRECTIONS;
    rng.shuffle(Direction, &directions);

    for (directions) |direction| {
        var newcoord = coord;
        if (!newcoord.move(direction, state.mapgeometry))
            continue;

        var newcoord2 = newcoord;
        if (!newcoord2.move(direction, state.mapgeometry))
            continue;

        // TODO: give slight chance to connect anyway
        if (state.dungeon[newcoord2.y][newcoord2.x].type != .Wall)
            if (rng.range(usize, 0, 4) != 0) continue;

        const room = Room{ .start = newcoord2, .width = 1, .height = 1 };
        if (_room_intersects(&room, coord)) {
            continue;
        }

        state.dungeon[newcoord.y][newcoord.x].type = .Floor;
        state.dungeon[newcoord2.y][newcoord2.x].type = .Floor;

        if (rng.range(usize, 0, 3) == 0) {
            var door = newcoord2;
            if (door.move(direction, state.mapgeometry)) {
                _room(direction, &room);
                state.dungeon[door.y][door.x].type = .Floor;
            }
        } else {
            _tunnel(newcoord2, direction);
        }
    }
}

fn _remove_deadends(n: usize) void {
    var y: usize = 0;
    while (y < state.HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < state.WIDTH) : (x += 1) {
            var walls: usize = 0;

            for (CARDINAL_DIRECTIONS) |d| {
                var coord = Coord.new(x, y);
                if (!coord.move(d, state.mapgeometry))
                    continue;
                if (state.dungeon[coord.y][coord.x].type == .Wall)
                    walls += 1;
            }

            if (walls >= 3) {
                state.dungeon[y][x].type = .Wall;
            }
        }
    }

    if (n > 0) {
        _remove_deadends(n - 1);
    }
}

pub fn tunneler(allocator: *mem.Allocator) void {
    rooms = std.ArrayList(Room).init(allocator);

    const midx = rng.range(usize, 0, state.WIDTH / 2);
    const midy = rng.range(usize, 0, state.HEIGHT / 2);

    _tunnel(Coord.new(midx, midy), .East);
    _remove_deadends(500);

    const room_index = rng.range(usize, 0, rooms.items.len);
    const room = &rooms.items[room_index];
    _add_player(Coord.new(room.start.x + 1, room.start.y + 1), allocator);

    for (rooms.items) |nroom, i| {
        if (i == room_index) continue;

        const guardstart = Coord.new(nroom.start.x + 1, nroom.start.y + 1);
        const guardend = Coord.new(nroom.end().x - 1, nroom.end().y - 1);

        var guard = GuardTemplate;
        guard.occupation.work_area = CoordArrayList.init(allocator);
        guard.occupation.work_area.append(guardstart) catch unreachable;
        guard.occupation.work_area.append(guardend) catch unreachable;
        guard.fov = CoordArrayList.init(allocator);
        guard.memory = CoordCharMap.init(allocator);
        guard.coord = guardstart;
        guard.facing = .North;
        state.dungeon[guardstart.y][guardstart.x].mob = guard;
    }

    rooms.deinit();
}

pub fn drunken_walk() void {
    const center_weight = 20;
    const fill_goal = @intToFloat(f64, state.WIDTH * state.HEIGHT) * 0.35;
    const prev_direction_weight = 90;
    const max_iterations = 5000;

    var prev_direction: Direction = .North;
    var filled: usize = 0;
    var iterations: usize = 0;
    var walker = Coord.new(state.WIDTH / 2, state.HEIGHT / 2);

    while (true) {
        // probability of going in a direction
        var north: usize = 100;
        var south: usize = 100;
        var east: usize = 100;
        var west: usize = 100;

        if (state.WIDTH > state.HEIGHT) {
            east += ((state.WIDTH * 100) / state.HEIGHT);
            west += ((state.WIDTH * 100) / state.HEIGHT);
        } else if (state.HEIGHT > state.WIDTH) {
            north += ((state.HEIGHT * 100) / state.WIDTH);
            south += ((state.HEIGHT * 100) / state.WIDTH);
        }

        // weight the random walk against map edges
        if (@intToFloat(f64, walker.x) < (@intToFloat(f64, state.WIDTH) * 0.25)) {
            // walker is at far left
            east += center_weight;
        } else if (@intToFloat(f64, walker.x) > (@intToFloat(f64, state.WIDTH) * 0.75)) {
            // walker is at far right
            west += center_weight;
        }

        if (@intToFloat(f64, walker.y) < (@intToFloat(f64, state.HEIGHT) * 0.25)) {
            // walker is at the top
            south += center_weight;
        } else if (@intToFloat(f64, walker.y) > (@intToFloat(f64, state.HEIGHT) * 0.75)) {
            // walker is at the bottom
            north += center_weight;
        }

        // Don't break into a previously-built enclosure
        // TODO

        // weight the walker to previous direction
        switch (prev_direction) {
            .North => north += prev_direction_weight,
            .South => south += prev_direction_weight,
            .West => west += prev_direction_weight,
            .East => east += prev_direction_weight,
            else => unreachable,
        }

        // normalize probabilities
        const total = north + south + east + west;
        north = north * 100 / total;
        south = south * 100 / total;
        east = east * 100 / total;
        west = west * 100 / total;

        // choose direction
        var directions = CARDINAL_DIRECTIONS;
        rng.shuffle(Direction, &directions);

        const direction = rng.choose(Direction, &CARDINAL_DIRECTIONS, &[_]usize{ north, south, east, west }) catch unreachable;

        if (walker.move(direction, Coord.new(state.WIDTH, state.HEIGHT))) {
            if (state.dungeon[walker.y][walker.x].type == .Wall) {
                filled += 1;
                state.dungeon[walker.y][walker.x].type = .Floor;
                prev_direction = direction;
            } else {
                prev_direction = direction.opposite();
                if (rng.boolean()) {
                    prev_direction = direction.turnright();
                } else {
                    prev_direction = direction.turnleft();
                }
            }
        } else {
            prev_direction = direction.opposite();
        }

        iterations += 1;
        if (filled > fill_goal or iterations > max_iterations)
            break;
    }
}
