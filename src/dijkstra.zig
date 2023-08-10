// FIXME: next() should never return starting coord

const std = @import("std");
const mem = std.mem;

const types = @import("types.zig");
const state = @import("state.zig");

const Mob = types.Mob;
const Coord = types.Coord;
const Direction = types.Direction;
const Path = types.Path;
const CoordArrayList = types.CoordArrayList;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// Dijkstra maps, aka influence maps

pub fn dijkRollUphill(
    map: *[HEIGHT][WIDTH]?f64,
    directions: []const Direction,
    walkability_map: *const [HEIGHT][WIDTH]bool,
) void {
    var changes_made = true;
    while (changes_made) {
        changes_made = false;
        for (map) |*row, y| for (row) |*cell, x| {
            if (!walkability_map[y][x] or (cell.* != null and cell.*.? == 0)) {
                continue;
            }

            const coord = Coord.new(x, y);
            const cur_val = cell.* orelse 9999;

            var lowest_neighbor: f64 = 9999;
            for (directions) |d|
                if (coord.move(d, state.mapgeometry)) |neighbor| {
                    if (map[neighbor.y][neighbor.x]) |ncell|
                        if (ncell < lowest_neighbor) {
                            lowest_neighbor = ncell;
                        };
                };
            if (cur_val > (lowest_neighbor + 1)) {
                cell.* = lowest_neighbor + 1;
                changes_made = true;
            }
        };
    }
}

// Multiply each value in the matrix by a value.
pub fn dijkMultiplyMap(map: *[HEIGHT][WIDTH]?f64, value: f64) void {
    for (map) |*row| for (row) |*cell| {
        if (cell.*) |v| cell.* = v * value;
    };
}

// Dijkstra iterator

const NodeState = enum { Open, Closed };
const Node = struct {
    c: Coord,
    n: usize,
    state: NodeState = .Open,
};
const NodeArrayList = std.ArrayList(Node);

pub fn dummyIsValid(_: Coord, _: state.IsWalkableOptions) bool {
    return true;
}

pub const Dijkstra = struct {
    center: Coord,
    current: Node,
    max: usize,
    limit: Coord,
    is_valid: fn (Coord, state.IsWalkableOptions) bool,
    is_valid_opts: state.IsWalkableOptions,
    open: NodeArrayList,
    nodes: [HEIGHT][WIDTH]?Node = [_][WIDTH]?Node{[_]?Node{null} ** WIDTH} ** HEIGHT,
    skip_current: bool = false,

    const Self = @This();

    pub fn init(
        start: Coord,
        limit: Coord,
        max_distance: usize,
        is_valid: fn (Coord, state.IsWalkableOptions) bool,
        is_valid_opts: state.IsWalkableOptions,
        allocator: mem.Allocator,
    ) Self {
        const n = Node{ .c = start, .n = 0 };
        var s = Self{
            .center = start,
            .current = n,
            .max = max_distance,
            .limit = limit,
            .is_valid = is_valid,
            .is_valid_opts = is_valid_opts,
            .open = NodeArrayList.init(allocator),
        };
        s.nodes[start.y][start.x] = n;
        s.open.append(s.nodes[start.y][start.x].?) catch unreachable;
        return s;
    }

    pub fn deinit(self: *Self) void {
        self.open.deinit();
    }

    pub fn next(self: *Self) ?Coord {
        if (self.open.items.len == 0) {
            return null;
        }

        self.nodes[self.current.c.y][self.current.c.x].?.state = .Closed;

        if (!self.skip_current) {
            for (&DIRECTIONS) |neighbor| if (self.current.c.move(neighbor, self.limit)) |coord| {
                const new = Node{ .c = coord, .n = self.current.n + 1 };

                if (self.nodes[coord.y][coord.x]) |oldnode|
                    if (oldnode.state == .Closed) continue;
                if (new.n > self.max) continue;
                if (!self.is_valid(coord, self.is_valid_opts)) continue;

                var in_ol = if (self.nodes[coord.y][coord.x]) |_| true else false;
                self.nodes[coord.y][coord.x] = new;
                if (!in_ol)
                    self.open.append(self.nodes[coord.y][coord.x].?) catch unreachable;
            };
        } else {
            self.skip_current = false;
        }

        if (self.open.items.len == 0) {
            return null;
        } else {
            self.current = self.open.orderedRemove(0);
            return self.current.c;
        }
    }

    pub fn skip(self: *Self) void {
        self.skip_current = true;
    }
};
