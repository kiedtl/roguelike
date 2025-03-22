const std = @import("std");
const mem = std.mem;
const testing = std.testing;

const types = @import("types.zig");
const state = @import("state.zig");

const Coord = types.Coord;
const Direction = types.Direction;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// Dijkstra maps, aka influence maps
//
// Kind of unrelated to the main purpose of this file, which is Dijkstra search.

pub fn dijkRollUphill(
    map: *[HEIGHT][WIDTH]?f64,
    directions: []const Direction,
    walkability_map: *const [HEIGHT][WIDTH]bool,
) void {
    var changes_made = true;
    while (changes_made) {
        changes_made = false;
        for (map, 0..) |*row, y| for (row, 0..) |*cell, x| {
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

const NodeState = enum(u8) { None, Open, Closed };
const Node = struct {
    c: Coord,
    n: u8,
};
const NodeList = std.fifo.LinearFifo(Node, .Dynamic);

pub fn dummyIsValid(_: Coord, _: state.IsWalkableOptions) bool {
    return true;
}

pub const Dijkstra = struct {
    current: Node,
    max: u8,
    limit: Coord,
    is_valid: *const fn (Coord, state.IsWalkableOptions) bool,
    is_valid_opts: state.IsWalkableOptions,
    open: NodeList,
    skip_current: bool = false,

    node_ns: [HEIGHT][WIDTH]u8 = undefined,
    node_states: [HEIGHT][WIDTH]NodeState = undefined,

    const Self = @This();

    pub fn init(
        s: *Dijkstra,
        start: Coord,
        limit: Coord,
        max_distance: usize,
        is_valid: *const fn (Coord, state.IsWalkableOptions) bool,
        is_valid_opts: state.IsWalkableOptions,
        allocator: mem.Allocator,
    ) void {
        const n = Node{ .c = start, .n = 0 };

        s.current = n;
        s.max = @intCast(max_distance);
        s.limit = limit;
        s.is_valid = is_valid;
        s.is_valid_opts = is_valid_opts;
        s.open = NodeList.init(allocator);

        for (0..HEIGHT) |y|
            for (0..WIDTH) |x| {
                s.node_states[y][x] = .None;
            };

        s.open.writeItem(n) catch unreachable;
        s.node_ns[start.y][start.x] = 0;
        s.node_states[start.y][start.x] = .Open;
    }

    pub fn deinit(self: *Self) void {
        self.open.deinit();
    }

    pub fn next(self: *Self) ?Coord {
        if (self.open.readableLength() == 0) {
            return null;
        }

        self.node_states[self.current.c.y][self.current.c.x] = .Closed;

        if (!self.skip_current) {
            for (&DIRECTIONS) |neighbor| if (self.current.c.move(neighbor, self.limit)) |coord| {
                const new = Node{ .c = coord, .n = self.current.n + 1 };

                if (self.node_states[coord.y][coord.x] == .Closed or
                    new.n > self.max or
                    !self.is_valid(coord, self.is_valid_opts))
                {
                    continue;
                }

                if (self.node_states[coord.y][coord.x] == .None)
                    self.open.writeItem(new) catch unreachable;

                self.node_ns[coord.y][coord.x] = self.current.n + 1;
                self.node_states[coord.y][coord.x] = .Open;
            };
        } else {
            self.skip_current = false;
        }

        if (self.open.readItem()) |cnode| {
            self.current = cnode;
            return self.current.c;
        } else {
            return null;
        }
    }

    pub fn skip(self: *Self) void {
        self.skip_current = true;
    }
};

test "Dijkstra visits each cell once" {
    var buf: [HEIGHT][WIDTH]usize = @splat(@splat(0));

    var dijk = Dijkstra.init(
        Coord.new(HEIGHT / 2, WIDTH / 2),
        state.mapgeometry,
        @max(HEIGHT, WIDTH),
        dummyIsValid,
        .{},
        testing.allocator,
    );
    defer dijk.deinit();

    while (dijk.next()) |coord|
        buf[coord.y][coord.x] += 1;

    for (0..HEIGHT) |y|
        for (0..WIDTH) |x| {
            try testing.expectEqual(1, buf[y][x]);
        };
}
