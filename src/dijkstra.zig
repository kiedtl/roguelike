const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const types = @import("types.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");

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

        // Add it twice to fix a quirk of next() ignoring the very first item in
        // the open list. Silly hack.
        s.open.writeItem(n) catch unreachable;
        s.open.writeItem(n) catch unreachable;

        s.node_ns[start.y][start.x] = 0;
        s.node_states[start.y][start.x] = .Open;
    }

    pub fn deinit(self: *Self) void {
        self.open.deinit();
    }

    // All the commented out printf debugging is fallout from trying to
    // investigate a 4 year old bug over the course of 4 hours.

    pub fn next(self: *Self) ?Coord {
        if (self.open.readableLength() == 0) {
            return null;
        } else {
            _ = self.open.readItem().?;
        }

        self.node_states[self.current.c.y][self.current.c.x] = .Closed;

        // std.log.warn("Coord {},{}", .{ self.current.c.x, self.current.c.y });
        // std.log.warn("Queue: {any}", .{self.open.readableSlice(0)});

        if (self.current.n <= self.max and !self.skip_current) {
            // std.log.warn(" - searching", .{});
            for (&DIRECTIONS) |d| if (self.current.c.move(d, self.limit)) |coord| {
                if (self.node_states[coord.y][coord.x] == .Closed or
                    !self.is_valid(coord, self.is_valid_opts))
                {
                    // std.log.warn("  * skipping {},{}. state = {}, n = {}/{}", .{ coord.x, coord.y, self.node_states[coord.y][coord.x], self.current.n + 1, self.max });
                    continue;
                }

                if (self.node_states[coord.y][coord.x] != .Open) {
                    self.open.writeItem(.{ .c = coord, .n = self.current.n + 1 }) catch unreachable;
                    // std.log.warn("  * adding   {},{}. state = {}, n = {}/{}", .{ coord.x, coord.y, self.node_states[coord.y][coord.x], self.current.n + 1, self.max });
                    // } else std.log.warn("  * reusing  {},{}. state = {}, n = {}/{}", .{ coord.x, coord.y, self.node_states[coord.y][coord.x], self.current.n + 1, self.max });
                }

                self.node_ns[coord.y][coord.x] = self.current.n + 1;
                self.node_states[coord.y][coord.x] = .Open;
            };
        }

        // if (self.skip_current)
        //     std.log.warn("ignoring {},{}", .{ self.current.c.x, self.current.c.y });

        self.skip_current = false;

        if (self.open.readableLength() == 0) {
            // std.log.warn("-> done", .{});
            return null;
        } else {
            self.current = self.open.peekItem(0);
            // std.log.warn("-> returning {},{}", .{ self.current.c.x, self.current.c.y });
            return self.current.c;
        }
    }

    pub fn skip(self: *Self) void {
        self.skip_current = true;
    }
};

// -----------------------------------------------------------------------------

const testing = std.testing;
const snap = utils.testing.snap;
const Snap = utils.testing.Snap;

test "Dijkstra visits each cell once" {
    try chk(
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
        \\00000000000000000000
    , Coord.new(0, 0), @max(TW, TH), struct {
        pub fn f(_: *Dijkstra, buf: *[TH][TW]u8, coord: Coord) void {
            buf[coord.y][coord.x] += 1;
        }
    }.f, snap(@src(),
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
        \\11111111111111111111
    ));
}

test "Dijkstra from a corner" {
    try chk(null, Coord.new(0, 0), 5, struct {
        pub fn f(_: *Dijkstra, buf: *[TH][TW]u8, coord: Coord) void {
            buf[coord.y][coord.x] = '.';
        }
    }.f, snap(@src(),
        \\.......#############
        \\.......#############
        \\.......#############
        \\.......#############
        \\.......#############
        \\.......#############
        \\.......#############
        \\####################
        \\####################
        \\####################
    ));
}

test "Dijkstra from the middle" {
    try chk(null, Coord.new(TW / 2, TH / 2), 3, struct {
        pub fn f(_: *Dijkstra, buf: *[TH][TW]u8, coord: Coord) void {
            buf[coord.y][coord.x] = '.';
        }
    }.f, snap(@src(),
        \\####################
        \\######.........#####
        \\######.........#####
        \\######.........#####
        \\######.........#####
        \\######.........#####
        \\######.........#####
        \\######.........#####
        \\######.........#####
        \\######.........#####
    ));
}

test "Dijkstra distances, skip_current" {
    try chk(
        \\....................
        \\...########.........
        \\...#......#.........
        \\...#...#..#.........
        \\...#...#.#######....
        \\...#...#............
        \\...#...########.....
        \\...#......#.........
        \\...########.........
        \\....................
    , Coord.new(5, 6), 15, struct {
        pub fn f(dijk: *Dijkstra, buf: *[TH][TW]u8, coord: Coord) void {
            if (buf[coord.y][coord.x] == '#') {
                buf[coord.y][coord.x] = '@';
                dijk.skip();
            } else {
                const char: u8 = @intCast(switch (dijk.current.n) {
                    0...9 => |c| c + '0',
                    else => |c| c + 'a',
                });
                buf[coord.y][coord.x] = char;
            }
        }
    }.f, snap(@src(),
        \\....................
        \\...@@@@@@@@.........
        \\...@444456@...qqqqq.
        \\...@333@56@...qpppq.
        \\...@222@6@@@@@@@opq.
        \\...@111@7789klmnopq.
        \\...@101@@@@@@@@nopq.
        \\...@111234@.qpooopq.
        \\...@@@@@@@@.qpppppq.
        \\............qqqqqqq.
    ));
}

test "Dijkstra distances, skip_current contained in room" {
    try chk(
        \\....................
        \\...########.........
        \\...#......#.........
        \\...#...#..#.........
        \\...#...#.#######....
        \\...#...#..#.........
        \\...#...########.....
        \\...#......#.........
        \\...########.........
        \\....................
    , Coord.new(5, 6), 15, struct {
        pub fn f(dijk: *Dijkstra, buf: *[TH][TW]u8, coord: Coord) void {
            if (buf[coord.y][coord.x] == '#') {
                buf[coord.y][coord.x] = '@';
                dijk.skip();
            } else buf[coord.y][coord.x] = '\'';
        }
    }.f, snap(@src(),
        \\....................
        \\...@@@@@@@@.........
        \\...@''''''@.........
        \\...@'''@''@.........
        \\...@'''@'@@#####....
        \\...@'''@''@.........
        \\...@'''@@@@####.....
        \\...@''''''@.........
        \\...@@@@@@@@.........
        \\....................
    ));
}

const TW = 20;
const TH = 10;

fn chk(
    init: ?[]const u8,
    start: Coord,
    lim: usize,
    func: *const fn (*Dijkstra, *[TH][TW]u8, Coord) void,
    s: Snap,
) !void {
    var buf: [TH][TW]u8 = undefined;
    for (0..TH) |y| {
        for (0..TW) |x| {
            if (init) |init_str|
                buf[y][x] = init_str[y * (TW + 1) + x]
            else
                buf[y][x] = '#';
        }
    }

    var dijk: Dijkstra = undefined;
    dijk.init(start, Coord.new(TW, TH), lim, dummyIsValid, .{}, testing.allocator);
    defer dijk.deinit();

    while (dijk.next()) |coord|
        func(&dijk, &buf, coord);

    try utils.testing.expectEqual(utils.testing.mapToString(TH, TW, &buf), s);
}
