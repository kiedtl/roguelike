const std = @import("std");
const math = std.math;
const mem = std.mem;
const assert = std.debug.assert;

pub const Direction = enum {
    North,
    South,
    East,
    West,
    NorthEast,
    NorthWest,
    SouthEast,
    SouthWest,

    const Self = @This();

    pub fn is_diagonal(self: Self) bool {
        return switch (self) {
            .North, .South, .East, .West => false,
            else => true,
        };
    }

    pub fn opposite(self: *const Self) Self {
        return switch (self.*) {
            .North => .South,
            .South => .North,
            .East => .West,
            .West => .East,
            .NorthEast => .SouthWest,
            .NorthWest => .SouthEast,
            .SouthEast => .NorthWest,
            .SouthWest => .NorthEast,
        };
    }

    pub fn turnleft(self: *const Self) Self {
        return switch (self.*) {
            .North => .West,
            .South => .East,
            .East => .North,
            .West => .South,
            else => unreachable,
        };
    }

    pub fn turnright(self: *const Self) Self {
        return self.turnleft().opposite();
    }
};

pub const CARDINAL_DIRECTIONS = [_]Direction{ .North, .South, .East, .West };
pub const DIRECTIONS = [_]Direction{ .North, .South, .East, .West, .NorthEast, .NorthWest, .SouthEast, .SouthWest };

pub const Coord = struct {
    x: usize,
    y: usize,

    const Self = @This();

    pub fn new(x: usize, y: usize) Coord {
        return .{ .x = x, .y = y };
    }

    pub fn distance(a: Self, b: Self) usize {
        // d = sqrt(dx^2 + dy^2)
        const x = math.max(a.x, b.x) - math.min(a.x, b.x);
        const y = math.max(a.y, b.y) - math.min(a.y, b.y);
        return math.sqrt((x * x) + (y * y));
    }

    pub fn hash(a: Self) u64 {}

    pub fn eq(a: Self, b: Self) bool {
        return a.x == b.x and a.y == b.y;
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

    fn insert_if_valid(x: isize, y: isize, buf: *CoordArrayList, limit: Coord) void {
        if (x < 0 or y < 0)
            return;
        if (x > @intCast(isize, limit.x) or y > @intCast(isize, limit.y))
            return;

        buf.append(Coord.new(@intCast(usize, x), @intCast(usize, y))) catch unreachable;
    }

    pub fn draw_line(from: Coord, to: Coord, limit: Coord, alloc: *mem.Allocator) CoordArrayList {
        var buf = CoordArrayList.init(alloc);

        // plotLine(x0, y0, x1, y1)
        // dx = x1 - x0
        // dy = y1 - y0
        // D = 2*dy - dx
        // y = y0

        // for x from x0 to x1
        // plot(x,y)
        // if D > 0
        //     y = y + 1
        //     D = D - 2*dx
        // end if
        // D = D + 2*dy

        // int dx = abs(x1-x0), sx = x0<x1 ? 1 : -1;
        // int dy = abs(y1-y0), sy = y0<y1 ? 1 : -1;
        // int err = (dx>dy ? dx : -dy)/2, e2;
        //  
        // for(;;){
        //      setPixel(x0,y0);
        //      if (x0==x1 && y0==y1) break;
        //      e2 = err;
        //      if (e2 >-dx) { err -= dy; x0 += sx; }
        //      if (e2 < dy) { err += dx; y0 += sy; }
        // }

        //        buf[index] = from;
        //        index += 1;

        //        const xstart = @intCast(isize, from.x);
        //        const xend = @intCast(isize, to.x);
        //        const ystart = @intCast(isize, from.y);
        //        const yend = @intCast(isize, to.y);
        //        var y = ystart;
        //        var x = xstart;

        //        const stepx: isize = if (to.x < from.x) -1 else 1;
        //        const stepy: isize = if (to.y < from.y) -1 else 1;

        //        const dx: isize = math.absInt(@intCast(isize, to.x) - @intCast(isize, from.x)) catch unreachable;
        //        const dy: isize = math.absInt(@intCast(isize, to.y) - @intCast(isize, from.y)) catch unreachable;
        //        var delta = 2 * dy - dx;
        //        //var err = @divTrunc(if (dx > dy) dx else -dy, 2);

        //        //while (true) {
        //        while (x != xend) : (x += stepx) {
        //            insert_if_valid(x, y, &buf, limit);

        //            // if (x == xend or y == yend)
        //            //     break;

        //            // var err2 = err;
        //            // if (err2 > -dx) {
        //            //     err -= dy;
        //            //     x += stepx;
        //            // }

        //            // if (err2 < dx) {
        //            //     err += dy;
        //            //     y += stepy;
        //            // }

        //            if (delta > 0) {
        //                y += stepy * delta;
        //                delta -= 2 * dx;
        //            }

        //            delta += 2 * dy;
        //        }

        // const xstart = @intCast(isize, math.min(from.x, to.x));
        // const xend = @intCast(isize, math.max(from.x, to.x));
        // const ystart = @intCast(isize, math.min(from.y, to.y));
        // const yend = @intCast(isize, math.max(from.y, to.y));

        // const xstart = @intCast(isize, from.x);
        // const xend = @intCast(isize, to.x);
        // const ystart = @intCast(isize, from.y);
        // const yend = @intCast(isize, to.y);
        // const slope = @intToFloat(f64, ystart - yend) / @intToFloat(f64, xstart - xend);
        // const stepx: isize = if (xstart < xend) 1 else -1;
        // const stepy: isize = if (ystart < yend) 1 else -1;

        // var err: f64 = 0.0;

        // var x = xstart;
        // var y = ystart;

        // while (x != xend) : (x += stepx) {
        //     insert_if_valid(x, y, &buf, limit);

        //     // err += slope;
        //     // if (err >= 0.5) {
        //     //     y += stepy;
        //     //     err -= 1;
        //     // }

        //     if (err + slope < 0.5) {
        //         err += slope;
        //     } else {
        //         y += stepy;
        //         err += slope;
        //     }
        // }

        // dx = abs(x1 - x0)
        // dy = abs(y1 - y0)
        // x, y = x0, y0
        // sx = -1 if x0 > x1 else 1
        // sy = -1 if y0 > y1 else 1
        // if dx > dy:
        //      err = dx / 2.0
        //      while x != x1:
        //           self.set(x, y)
        //           err -= dy
        //           if err < 0:
        //               y += sy
        //               err += dx
        //           x += sx
        // else:
        //      err = dy / 2.0
        //      while y != y1:
        //           self.set(x, y)
        //           err -= dx
        //           if err < 0:
        //               x += sx
        //               err += dy
        //           y += sy
        // self.set(x, y)

        const xstart = @intCast(isize, from.x);
        const xend = @intCast(isize, to.x);
        const ystart = @intCast(isize, from.y);
        const yend = @intCast(isize, to.y);
        const stepx: isize = if (xstart < xend) 1 else -1;
        const stepy: isize = if (ystart < yend) 1 else -1;
        const dx = @intToFloat(f64, math.absInt(xend - xstart) catch unreachable);
        const dy = @intToFloat(f64, math.absInt(yend - ystart) catch unreachable);

        var err: f64 = 0.0;
        var x = @intCast(isize, from.x);
        var y = @intCast(isize, from.y);

        if (dx > dy) {
            err = dx / 2.0;
            while (x != xend) {
                insert_if_valid(x, y, &buf, limit);
                err -= dy;
                if (err < 0) {
                    y += stepy;
                    err += dx;
                }
                x += stepx;
            }
        } else {
            err = dy / 2.0;
            while (y != yend) {
                insert_if_valid(x, y, &buf, limit);
                err -= dx;
                if (err < 0) {
                    x += stepx;
                    err += dy;
                }
                y += stepy;
            }
        }

        return buf;
    }

    pub fn draw_circle(center: Coord, radius: usize, limit: Coord, alloc: *mem.Allocator) CoordArrayList {
        const circum = @floatToInt(usize, math.ceil(math.tau * @intToFloat(f64, radius)));

        var buf = CoordArrayList.init(alloc);

        const x: isize = @intCast(isize, center.x);
        const y: isize = @intCast(isize, center.y);

        var f: isize = 1 - @intCast(isize, radius);
        var ddf_x: isize = 0;
        var ddf_y: isize = -2 * @intCast(isize, radius);
        var dx: isize = 0;
        var dy: isize = @intCast(isize, radius);

        insert_if_valid(x, y + @intCast(isize, radius), &buf, limit);
        insert_if_valid(x, y - @intCast(isize, radius), &buf, limit);
        insert_if_valid(x + @intCast(isize, radius), y, &buf, limit);
        insert_if_valid(x - @intCast(isize, radius), y, &buf, limit);

        while (dx < dy) {
            if (f >= 0) {
                dy -= 1;
                ddf_y += 2;
                f += ddf_y;
            }

            dx += 1;
            ddf_x += 2;
            f += ddf_x + 1;

            insert_if_valid(x + dx, y + dy, &buf, limit);
            insert_if_valid(x - dx, y + dy, &buf, limit);
            insert_if_valid(x + dx, y - dy, &buf, limit);
            insert_if_valid(x - dx, y - dy, &buf, limit);
            insert_if_valid(x + dy, y + dx, &buf, limit);
            insert_if_valid(x - dy, y + dx, &buf, limit);
            insert_if_valid(x + dy, y - dx, &buf, limit);
            insert_if_valid(x - dy, y - dx, &buf, limit);
        }

        return buf;
    }
};

pub const CoordCharMap = std.AutoHashMap(Coord, u21);
pub const CoordArrayList = std.ArrayList(Coord);

pub const Slave = struct {
    prison_start: Coord,
    prison_end: Coord,
};

pub const Guard = struct {
    patrol_start: Coord,
    patrol_end: Coord,
};

pub const OccupationTag = enum {
    Guard,
    // Cook,
    // Miner,
    // Architect,
    Slave,
    // None,
};

pub const Allegiance = enum {
    Sauron,
    Illuvatar,
    Self,
    NoneEvil,
    NoneGood,
};

pub const Occupation = union(OccupationTag) {
    Guard: Guard,
    Slave: Slave,
};

pub const Mob = struct {
    tile: u21,
    occupation: Occupation,
    allegiance: Allegiance,
    memory: CoordCharMap,
    fov: CoordArrayList,
    vision: usize,

    pub fn cansee(self: *const Mob, mob_coord: Coord, coord: Coord) bool {
        if (mob_coord.distance(coord) > self.vision)
            return false;

        for (self.fov.items) |fovcoord| {
            if (coord.eq(fovcoord))
                return true;
        }

        return false;
    }
};

pub const TileType = enum {
    Wall = 0,
    Floor = 1,
};

pub const Tile = struct {
    type: TileType,
    mob: ?Mob,
    marked: bool,
};

// ---------- Mob templates ----------

pub const GuardTemplate = Mob{
    .tile = 'א',
    .occupation = Occupation{
        .Guard = Guard{
            .patrol_start = Coord.new(0, 0),
            .patrol_end = Coord.new(0, 0),
        },
    },
    .allegiance = .Sauron,
    .fov = undefined,
    .memory = undefined,
    .vision = 4,
};

pub const ElfTemplate = Mob{
    .tile = '@',
    .occupation = Occupation{
        .Slave = Slave{
            .prison_start = Coord.new(0, 0),
            .prison_end = Coord.new(0, 0),
        },
    },
    .allegiance = .Illuvatar,
    .fov = undefined,
    .memory = undefined,
    .vision = 25,
};
