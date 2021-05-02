const std = @import("std");
const rng = @import("rng.zig");

const Direction = enum {
    North,
    South,
    East,
    West,

    const Self = @This();

    pub fn opposite(self: *const Self) Self {
        return switch (self.*) {
            .North => .South,
            .South => .North,
            .East => .West,
            .West => .East,
        };
    }

    pub fn turnleft(self: *const Self) Self {
        return switch (self.*) {
            .North => .West,
            .South => .East,
            .East => .North,
            .West => .South,
        };
    }

    pub fn turnright(self: *const Self) Self {
        return self.turnleft().opposite();
    }
};
const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };

const Coord = struct {
    x: usize,
    y: usize,

    const Self = @This();

    pub fn new(x: usize, y: usize) Coord {
        return .{ .x = x, .y = y };
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
        }

        const newx = @intCast(usize, @intCast(isize, self.x) + dx);
        const newy = @intCast(usize, @intCast(isize, self.y) + dy);

        if (0 < newx and newx < (limit.x - 1)) {
            if (0 < newy and newy < (limit.y - 1)) {
                self.x = newx;
                self.y = newy;
                return true;
            }
        }

        return false;
    }
};

const Mob = struct {
    name: []u8,
    tile: u32,
    HP: usize,
    AC: usize,
    EV: usize,
    max_HP: usize,
};

const TileType = enum {
    Wall = 0,
    Floor = 1,
    Route = 2,
};

const Tile = struct {
    type: TileType,
};

// Y, X
const HEIGHT = 40;
const WIDTH = 100;
var dungeon = [_][WIDTH]Tile{[_]Tile{Tile{ .type = .Wall }} ** WIDTH} ** HEIGHT;

fn find_guard_routes() void {
    // --- Guard route patterns ---
    const patterns = [_][9]TileType{
        // ###
        // #G.
        // #..
        [_]TileType{ .Wall, .Wall, .Wall, .Wall, .Floor, .Floor, .Wall, .Floor, .Floor },
    };

    var y = 1;
    while (y < (HEIGHT - 1)) : (y += 1) {
        var x = 1;
        while (x < (WIDTH - 1)) : (x += 1) {}
    }
}

fn generate() void {
    const center_weight = 20;
    const fill_goal = @intToFloat(f64, WIDTH * HEIGHT) * 0.35;
    const prev_direction_weight = 90;
    const max_iterations = 5000;

    var prev_direction: Direction = .North;
    var filled: usize = 0;
    var iterations: usize = 0;
    var walker = Coord.new(WIDTH / 2, HEIGHT / 2);

    while (true) {
        // probability of going in a direction
        var north: usize = 100;
        var south: usize = 100;
        var east: usize = 100;
        var west: usize = 100;

        if (WIDTH > HEIGHT) {
            east += ((WIDTH * 100) / HEIGHT);
            west += ((WIDTH * 100) / HEIGHT);
        } else if (HEIGHT > WIDTH) {
            north += ((HEIGHT * 100) / WIDTH);
            south += ((HEIGHT * 100) / WIDTH);
        }

        // weight the random walk against map edges
        if (@intToFloat(f64, walker.x) < (@intToFloat(f64, WIDTH) * 0.25)) {
            // walker is at far left
            east += center_weight;
        } else if (@intToFloat(f64, walker.x) > (@intToFloat(f64, WIDTH) * 0.75)) {
            // walker is at far right
            west += center_weight;
        }

        if (@intToFloat(f64, walker.y) < (@intToFloat(f64, HEIGHT) * 0.25)) {
            // walker is at the top
            south += center_weight;
        } else if (@intToFloat(f64, walker.y) > (@intToFloat(f64, HEIGHT) * 0.75)) {
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

        if (walker.move(direction, Coord.new(WIDTH, HEIGHT))) {
            if (dungeon[walker.y][walker.x].type == .Wall) {
                filled += 1;
                dungeon[walker.y][walker.x].type = .Floor;
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

fn print() void {
    for (dungeon) |level| {
        for (level) |tile| {
            switch (tile.type) {
                .Wall => std.debug.print("\x1b[7m \x1b[m", .{}),
                .Floor => std.debug.print(".", .{}),
                .Route => std.debug.print("%", .{}),
            }
        }
        std.debug.print("\n", .{});
    }
}

pub fn main() anyerror!void {
    rng.init();
    generate();
    print();
}
