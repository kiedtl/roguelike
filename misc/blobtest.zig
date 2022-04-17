// Tool for testing out blobs
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

const Tile = union(enum) { Wall, Floor };

pub fn main() anyerror!void {
    rng = std.rand.Isaac64.init(@intCast(u64, std.time.milliTimestamp()));

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var blob_map: [WIDTH][HEIGHT]usize = undefined;
    var map: [WIDTH][HEIGHT]Tile = undefined;

    var i: usize = 0;
    while (i < 20) : (i += 1) {
        const blob_location = createBlob(
            &blob_map,
            10, // iters
            range(usize, 2, 8), // min
            range(usize, 2, 8), // min
            range(usize, 9, 20), // max
            range(usize, 9, 20), // max
            55, // seeded
            "ffffffftt", // birth
            "ffffttttt", // survival
        );

        const map_location = Coord.new(
            range(usize, 2, WIDTH - 2),
            range(usize, 2, HEIGHT - 2),
        );

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
                    map[coord.x][coord.y] = .Wall;
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
                    .Floor => stdout.print("{s}{s} \x1b[m", .{ bgstr, dgreenstr }),
                    .Wall => stdout.print("{s}{s}#\x1b[m", .{ bgstr, greenstr }),
                };
            }
            try stdout.print("\n", .{});
        }
    }
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
