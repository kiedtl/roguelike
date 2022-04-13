// Procedurally generated ASCII trees.
//
// (c) Kiëd Llaentenn 2022.
//
// Licensed under the MIT license, except for createBlob() and rangeClumping(),
// which is under Brogue's license.
//
const std = @import("std");
const math = std.math;

const HEIGHT = 30;
const WIDTH = 80;

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };
pub const mapgeometry = Coord.new(WIDTH, HEIGHT);

pub var rng: std.rand.Isaac64 = undefined;

const bgstr = "\x1b[48;2;0;0;0m";
const greenstr = "\x1b[38;2;120;240;150m";
const ygreenstr = "\x1b[38;2;30;200;10m";
const ldgreenstr = "\x1b[38;2;50;175;120m";
const dgreenstr = "\x1b[38;2;0;65;30m";
const brownstr = "\x1b[38;2;124;53;26m";
const lbrownstr = "\x1b[38;2;184;143;86m";

const Tile = union(enum) {
    Grass: u21,
    Leaf: struct { ch: u21, tree_id: usize, color: []const u8 },
    Branch: struct { ch: u21, tree_id: usize },
    Trunk: usize,

    pub fn treeId(self: @This()) ?usize {
        return switch (self) {
            .Leaf => |l| l.tree_id,
            .Branch => |b| b.tree_id,
            .Trunk => |t| t,
            else => null,
        };
    }
};

pub fn main() anyerror!void {
    // Initialize the RNG from the current timestamp
    rng = std.rand.Isaac64.init(@intCast(u64, std.time.milliTimestamp()));

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    // blob_map is what createBlob will use as a temporary buffer for its
    // cellular automata.
    //
    // map is where we'll copy the finished blob to, and what we'll display.
    var blob_map: [WIDTH][HEIGHT]usize = undefined;
    var map: [WIDTH][HEIGHT]Tile = undefined;

    // Create some grass for a nice background.
    //
    for (map) |*row| for (row) |*cell| {
        const ch: u21 = switch (range(usize, 1, 5)) {
            0 => '.',
            1 => ',',
            2 => ':',
            3 => ';',
            4 => 't',
            5 => ' ',
            else => unreachable,
        };
        cell.* = .{ .Grass = ch };
    };

    // Create 40 blobs.
    //
    var i: usize = 0;
    while (i < 40) : (i += 1) {
        // Create a blob with a minimum dimension of 3x3, and a maximum dimension
        // of 6x6..8x8. We're doing 15 cellular automata iterations, and it's 60%
        // seeded. the fffffttttt stuff is the birth and survival settings
        // (f == false and t == true), so fffftttttt means "cells with <5 neighbors
        // die, and the rest live".
        //
        // createBlob() return the location of the best blob on blob_map.
        const blob_dim = range(usize, 6, 8);
        const blob_location = createBlob(&blob_map, 15, 3, 3, blob_dim, blob_dim, 60, "ffffffttt", "ffffttttt");

        // Choose a random spot to create the tree.
        const map_location = Coord.new(
            range(usize, 2, WIDTH - 2),
            range(usize, 2, HEIGHT - 2),
        );

        // Since we don't want to get stuck in an infinite loop trying to find
        // a suitable trunk location, let's give up after 5000 tries, skipping
        // this blob.
        //
        var tries: usize = 0;
        const trunk = while (tries < 5000) : (tries += 1) {
            const bh = blob_location.height;
            const bw = blob_location.width;

            // Try to get one in the middle of the tree blob.
            const attempt_blob = Coord.new(
                rangeClumping(usize, bw * 30 / 100, bw * 60 / 100, 2),
                rangeClumping(usize, bh * 30 / 100, bh * 60 / 100, 2),
            );

            // Go over each neighbor, counting the number of adjacent leaves.
            //
            // If we're not surrounded by leaves, probably not a good spot.
            var leaf_neighbors: usize = 0;
            for (&DIRECTIONS) |d| if (attempt_blob.move(d, mapgeometry)) |neighbor| {
                if (neighbor.x >= blob_location.end().x or neighbor.y >= blob_location.end().y)
                    continue;
                if (blob_map[neighbor.x][neighbor.y] != 0)
                    leaf_neighbors += 1;
            };
            if (leaf_neighbors < 7) continue;

            // Sometimes blobs run off the map, and we might have chosen a
            // location in that area. Don't return those.
            const attempt = attempt_blob.add(map_location);
            if (attempt.x < WIDTH and attempt.y < HEIGHT)
                break attempt;
        } else continue;

        const leaf_color: []const u8 = switch (range(usize, 0, 7)) {
            0...2 => greenstr,
            3...4 => ygreenstr,
            5...6 => ldgreenstr,
            7 => lbrownstr,
            else => unreachable,
        };

        std.log.info("placing blob at {},{} (trunk: {},{})", .{
            map_location.x, map_location.y, trunk.x, trunk.y,
        });

        // ...and copy the blob over to the map.
        //
        var map_y: usize = 0;
        var blob_y = blob_location.start.y;
        while (blob_y < blob_location.end().y) : ({
            blob_y += 1;
            map_y += 1;
        }) {
            var map_x: usize = 0;
            var blob_x = blob_location.start.x;
            while (blob_x < blob_location.end().x) : ({
                blob_x += 1;
                map_x += 1;
            }) {
                const coord = Coord.new(map_x, map_y).add(map_location);
                if (coord.x >= WIDTH or coord.y >= HEIGHT)
                    continue;

                if (blob_map[blob_x][blob_y] != 0) {
                    map[coord.x][coord.y] = .{ .Leaf = .{
                        .ch = '%',
                        .tree_id = i,
                        .color = leaf_color,
                    } };
                }
            }
        }

        map[trunk.x][trunk.y] = .{ .Trunk = i };

        var dijk = Dijkstra.init(trunk, gpa.allocator());
        defer dijk.deinit();
        while (dijk.next()) |node| {
            const coord = node.c;

            if (map[coord.x][coord.y].treeId() == null or
                map[coord.x][coord.y].treeId().? != i)
            {
                dijk.skip();
                continue;
            }

            if (map[node.c.x][node.c.y] == .Leaf) {
                if (node.direction_taken == .North or
                    node.direction_taken == .South)
                {
                    const leafch = leafChar(node.direction_taken, node.n);
                    map[node.c.x][node.c.y].Leaf.ch = leafch;
                } else {
                    if (node.c.x != trunk.x) {
                        const leafch = if (node.c.x < trunk.x) @as(u21, '<') else '>';
                        map[node.c.x][node.c.y].Leaf.ch = leafch;
                    }
                }
            }

            if (node.parent) |parent| {
                if (map[parent.c.x][parent.c.y] == .Leaf) {
                    const parent_leafch = leafChar(parent.direction_taken, parent.n);
                    map[parent.c.x][parent.c.y].Leaf.ch = parent_leafch;

                    var trunk_neighbor: ?Coord = null;
                    var leafy_neighbors: usize = 0;
                    for (&DIRECTIONS) |d| if (parent.c.move(d, mapgeometry)) |neighbor| {
                        const neighbor_tile = map[neighbor.x][neighbor.y];
                        if (neighbor_tile.treeId() == null or neighbor_tile.treeId().? != i)
                            continue;
                        if (neighbor_tile == .Trunk) {
                            trunk_neighbor = neighbor;
                        } else if (neighbor_tile == .Leaf) {
                            leafy_neighbors += 1;
                        }
                    };

                    if (range(usize, 0, 100) < 15 and trunk_neighbor != null and leafy_neighbors >= 4) {
                        const d_from = trunk_neighbor.?.closestDirectionTo(parent.c, mapgeometry);
                        const parent_branchch: u21 = switch (d_from) {
                            .East, .West => '─',
                            .South, .North => '│',
                            .SouthWest, .NorthEast => '╱',
                            .NorthWest, .SouthEast => '╲',
                        };
                        map[parent.c.x][parent.c.y] = .{ .Branch = .{
                            .ch = parent_branchch,
                            .tree_id = i,
                        } };
                    }
                }
            }
        }
    }

    {
        const stdout = std.io.getStdOut().writer();

        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                try switch (map[x][y]) {
                    .Grass => |ch| stdout.print("{s}{s}{u}\x1b[m", .{ bgstr, dgreenstr, ch }),
                    .Leaf => |l| stdout.print("{s}{s}{u}\x1b[m", .{ bgstr, l.color, l.ch }),
                    .Branch => |b| stdout.print("{s}{s}{u}\x1b[m", .{ bgstr, brownstr, b.ch }),
                    .Trunk => stdout.print("{s}{s}O\x1b[m", .{ brownstr, bgstr }),
                };
            }
            try stdout.print("\n", .{});
        }
    }
}

fn leafChar(direction: Direction, dist: usize) u21 {
    return switch (direction) {
        .West => if (dist == 1) @as(u21, '⇐') else '←',
        .East => if (dist == 1) @as(u21, '⇒') else '→',
        .North => if (dist == 1) @as(u21, '⇑') else '↑',
        .South => if (dist == 1) @as(u21, '⇓') else '↓',
        .NorthWest => '↖',
        .NorthEast => '↗',
        .SouthEast => '↘',
        .SouthWest => '↙',
    };
}

// Ported from BrogueCE (src/brogue/Grid.c)
// (c) Contributors to BrogueCE. I do not claim authorship of the following function.
fn createBlob(
    grid: *[WIDTH][HEIGHT]usize,
    rounds: usize,
    min_blob_width: usize,
    min_blob_height: usize,
    max_blob_width: usize,
    max_blob_height: usize,
    percent_seeded: usize,
    birth_params: *const [9]u8,
    survival_params: *const [9]u8,
) Rect {
    const S = struct {
        fn cellularAutomataRound(buf: *[WIDTH][HEIGHT]usize, births: *const [9]u8, survivals: *const [9]u8) void {
            var buf2: [WIDTH][HEIGHT]usize = undefined;
            for (buf) |*col, x| for (col) |*cell, y| {
                buf2[x][y] = cell.*;
            };

            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                var y: usize = 0;
                while (y < HEIGHT) : (y += 1) {
                    const coord = Coord.new(x, y);

                    var nb_count: usize = 0;

                    for (&DIRECTIONS) |direction|
                        if (coord.move(direction, mapgeometry)) |neighbor| {
                            if (buf2[neighbor.x][neighbor.y] != 0) {
                                nb_count += 1;
                            }
                        };

                    if (buf2[x][y] == 0 and births[nb_count] == 't') {
                        buf[x][y] = 1; // birth
                    } else if (buf2[x][y] != 0 and survivals[nb_count] == 't') {
                        // survival
                    } else {
                        buf[x][y] = 0; // death
                    }
                }
            }
        }

        fn fillContiguousRegion(buf: *[WIDTH][HEIGHT]usize, x: usize, y: usize, value: usize) usize {
            var num: usize = 1;

            const coord = Coord.new(x, y);
            buf[x][y] = value;

            // Iterate through the four cardinal neighbors.
            for (&CARDINAL_DIRECTIONS) |direction| {
                if (coord.move(direction, mapgeometry)) |neighbor| {
                    if (buf[neighbor.x][neighbor.y] == 1) { // If the neighbor is an unmarked region cell,
                        num += fillContiguousRegion(buf, neighbor.x, neighbor.y, value); // then recurse.
                    }
                } else {
                    break;
                }
            }

            return num;
        }
    };

    var i: usize = 0;
    var j: usize = 0;
    var k: usize = 0;

    var blob_num: usize = 0;
    var blob_size: usize = 0;
    var top_blob_num: usize = 0;
    var top_blob_size: usize = 0;

    var top_blob_min_x: usize = 0;
    var top_blob_min_y: usize = 0;
    var top_blob_max_x: usize = 0;
    var top_blob_max_y: usize = 0;

    var blob_width: usize = 0;
    var blob_height: usize = 0;

    var found_cell_this_line = false;

    // Generate blobs until they satisfy the provided restraints
    var first = true; // Zig, get a do-while already
    while (first or blob_width < min_blob_width or blob_height < min_blob_height or top_blob_num == 0) {
        first = false;

        for (grid) |*col| for (col) |*cell| {
            cell.* = 0;
        };

        // Fill relevant portion with noise based on the percentSeeded argument.
        i = 0;
        while (i < max_blob_width) : (i += 1) {
            j = 0;
            while (j < max_blob_height) : (j += 1) {
                grid[i][j] = if (range(usize, 0, 100) < percent_seeded) 1 else 0;
            }
        }

        // Some iterations of cellular automata
        k = 0;
        while (k < rounds) : (k += 1) {
            S.cellularAutomataRound(grid, birth_params, survival_params);
        }

        // Now to measure the result. These are best-of variables; start them out at worst-case values.
        top_blob_size = 0;
        top_blob_num = 0;
        top_blob_min_x = max_blob_width;
        top_blob_max_x = 0;
        top_blob_min_y = max_blob_height;
        top_blob_max_y = 0;

        // Fill each blob with its own number, starting with 2 (since 1 means floor), and keeping track of the biggest:
        blob_num = 2;

        i = 0;
        while (i < WIDTH) : (i += 1) {
            j = 0;
            while (j < HEIGHT) : (j += 1) {
                if (grid[i][j] == 1) { // an unmarked blob
                    // Mark all the cells and returns the total size:
                    blob_size = S.fillContiguousRegion(grid, i, j, blob_num);
                    if (blob_size > top_blob_size) { // if this blob is a new record
                        top_blob_size = blob_size;
                        top_blob_num = blob_num;
                    }
                    blob_num += 1;
                }
            }
        }

        // Figure out the top blob's height and width:
        // First find the max & min x:
        i = 0;
        while (i < WIDTH) : (i += 1) {
            found_cell_this_line = false;
            j = 0;
            while (j < HEIGHT) : (j += 1) {
                if (grid[i][j] == top_blob_num) {
                    found_cell_this_line = true;
                    break;
                }
            }

            if (found_cell_this_line) {
                if (i < top_blob_min_x) {
                    top_blob_min_x = i;
                }

                if (i > top_blob_max_x) {
                    top_blob_max_x = i;
                }
            }
        }

        // Then the max & min y:
        j = 0;
        while (j < HEIGHT) : (j += 1) {
            found_cell_this_line = false;
            i = 0;
            while (i < WIDTH) : (i += 1) {
                if (grid[i][j] == top_blob_num) {
                    found_cell_this_line = true;
                    break;
                }
            }

            if (found_cell_this_line) {
                if (j < top_blob_min_y) {
                    top_blob_min_y = j;
                }

                if (j > top_blob_max_y) {
                    top_blob_max_y = j;
                }
            }
        }

        blob_width = (top_blob_max_x - top_blob_min_x) + 1;
        blob_height = (top_blob_max_y - top_blob_min_y) + 1;
    }

    // Replace the winning blob with 1's, and everything else with 0's:
    i = 0;
    while (i < WIDTH) : (i += 1) {
        j = 0;
        while (j < HEIGHT) : (j += 1) {
            if (grid[i][j] == top_blob_num) {
                grid[i][j] = 1;
            } else {
                grid[i][j] = 0;
            }
        }
    }

    return .{
        .start = Coord.new(top_blob_min_x, top_blob_min_y),
        .width = blob_width,
        .height = blob_height,
    };
}

fn range(comptime T: type, min: T, max: T) T {
    std.debug.assert(max >= min);
    const diff = (max + 1) - min;
    return if (diff > 0) @mod(rng.random().int(T), diff) + min else min;
}

fn rangeClumping(comptime T: type, min: T, max: T, clump: T) T {
    std.debug.assert(max >= min);
    if (clump <= 1) return range(T, min, max);

    const sides = @divTrunc(max - min, clump);
    var i: T = 0;
    var total: T = 0;

    while (i < @mod(max - min, clump)) : (i += 1) total += range(T, 0, sides + 1);
    while (i < clump) : (i += 1) total += range(T, 0, sides);

    return total + min;
}

pub const Coord = struct { // {{{
    x: usize,
    y: usize,
    z: usize,

    const Self = @This();

    pub inline fn new(x: usize, y: usize) Coord {
        return .{ .z = 0, .x = x, .y = y };
    }

    pub inline fn difference(a: Self, b: Self) Self {
        return Coord.new(
            math.max(a.x, b.x) - math.min(a.x, b.x),
            math.max(a.y, b.y) - math.min(a.y, b.y),
        );
    }

    pub inline fn distance(a: Self, b: Self) usize {
        const diff = a.difference(b);

        // Euclidean: d = sqrt(dx^2 + dy^2)
        //
        // return math.sqrt((diff.x * diff.x) + (diff.y * diff.y));

        // Manhattan: d = dx + dy
        // return diff.x + diff.y;

        // Chebyshev: d = max(dx, dy)
        return math.max(diff.x, diff.y);
    }

    pub inline fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
    }

    pub inline fn add(a: Self, b: Self) Self {
        return Coord.new(a.x + b.x, a.y + b.y);
    }

    pub fn move(self: *const Self, direction: Direction, limit: Self) ?Coord {
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

        if ((newx >= 0 and @intCast(usize, newx) < limit.x) and
            (newy >= 0 and @intCast(usize, newy) < limit.y))
        {
            return Coord.new(@intCast(usize, newx), @intCast(usize, newy));
        } else {
            return null;
        }
    }

    pub fn closestDirectionTo(self: Coord, to: Coord, limit: Coord) Direction {
        var closest_distance: usize = 10000000000;
        var closest_direction: Direction = .North;

        for (&DIRECTIONS) |direction| if (self.move(direction, limit)) |neighbor| {
            const diff = neighbor.difference(to);
            const dist = diff.x + diff.y;

            if (dist < closest_distance) {
                closest_distance = dist;
                closest_direction = direction;
            }
        };

        return closest_direction;
    }
}; // }}}

pub const Direction = enum { // {{{
    North,
    South,
    East,
    West,
    NorthEast,
    NorthWest,
    SouthEast,
    SouthWest,
}; // }}}

pub const Rect = struct {
    start: Coord,
    width: usize,
    height: usize,

    pub fn add(a: *const Rect, b: *const Rect) Rect {
        return .{
            .start = Coord.new(a.start.x + b.start.x, a.start.y + b.start.y),
            .width = a.width,
            .height = b.width,
        };
    }

    pub fn end(self: *const Rect) Coord {
        return Coord.new(self.start.x + self.width, self.start.y + self.height);
    }
};

// {{{
const NodeState = enum { Open, Closed };
const Node = struct {
    direction_taken: Direction,
    parent: ?*Node = null,
    c: Coord,
    n: usize,
    state: NodeState = .Open,
};
const NodeArrayList = std.ArrayList(Node);

pub const Dijkstra = struct {
    center: Coord,
    current: Node,
    open: NodeArrayList,
    nodes: [HEIGHT][WIDTH]?Node = [_][WIDTH]?Node{[_]?Node{null} ** WIDTH} ** HEIGHT,
    skip_current: bool = false,

    const Self = @This();

    pub fn init(
        start: Coord,
        allocator: std.mem.Allocator,
    ) Self {
        const n = Node{ .direction_taken = .North, .c = start, .n = 0 };
        var s = Self{
            .center = start,
            .current = n,
            .open = NodeArrayList.init(allocator),
        };
        s.nodes[start.y][start.x] = n;
        s.open.append(s.nodes[start.y][start.x].?) catch unreachable;
        return s;
    }

    pub fn deinit(self: *Self) void {
        self.open.deinit();
    }

    pub fn next(self: *Self) ?Node {
        if (self.open.items.len == 0) {
            return null;
        }

        const current_ptr = &self.nodes[self.current.c.y][self.current.c.x].?;
        current_ptr.state = .Closed;

        if (!self.skip_current) {
            for (&DIRECTIONS) |neighbor| if (self.current.c.move(neighbor, mapgeometry)) |coord| {
                const new = Node{
                    .direction_taken = neighbor,
                    .parent = current_ptr,
                    .c = coord,
                    .n = self.current.n + 1,
                };

                if (self.nodes[coord.y][coord.x]) |_|
                    continue;

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
            return self.current;
        }
    }

    pub fn skip(self: *Self) void {
        self.skip_current = true;
    }
};
// }}}
