const std = @import("std");
const math = std.math;

const state = @import("state.zig");
usingnamespace @import("types.zig");

// This was supposed to be a raytracer.
// I have no idea what it is now.
pub fn naive(center: Coord, radius: usize, limit: Coord, opacity: fn (Coord) f64, buf: *CoordArrayList) void {
    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const circle = center.draw_circle(radius, limit, &fba.allocator);

    for (circle.items) |coord| {
        const line = center.draw_line(coord, limit, &fba.allocator);
        var cumulative_opacity: f64 = 0.0;

        for (line.items) |line_coord| {
            if (cumulative_opacity >= 1.0) {
                break;
            }

            cumulative_opacity += opacity(line_coord);
            buf.append(line_coord) catch unreachable;
        }
    }
}

pub fn octants(d: Direction, wide: bool) [8]?usize {
    return if (wide) switch (d) {
        .North => [_]?usize{ 1, 0, 3, 2, null, null, null, null },
        .South => [_]?usize{ 6, 7, 4, 5, null, null, null, null },
        .East => [_]?usize{ 3, 2, 5, 4, null, null, null, null },
        .West => [_]?usize{ 0, 1, 6, 7, null, null, null, null },
        .NorthEast => [_]?usize{ 0, 3, 2, 5, null, null, null, null },
        .NorthWest => [_]?usize{ 3, 0, 1, 6, null, null, null, null },
        .SouthEast => [_]?usize{ 2, 5, 4, 7, null, null, null, null },
        .SouthWest => [_]?usize{ 1, 6, 7, 4, null, null, null, null },
    } else switch (d) {
        .North => [_]?usize{ 0, 3, null, null, null, null, null, null },
        .South => [_]?usize{ 7, 4, null, null, null, null, null, null },
        .East => [_]?usize{ 2, 5, null, null, null, null, null, null },
        .West => [_]?usize{ 1, 6, null, null, null, null, null, null },
        .NorthEast => [_]?usize{ 3, 2, null, null, null, null, null, null },
        .NorthWest => [_]?usize{ 1, 0, null, null, null, null, null, null },
        .SouthEast => [_]?usize{ 5, 4, null, null, null, null, null, null },
        .SouthWest => [_]?usize{ 6, 7, null, null, null, null, null, null },
    };
}

// Ported from doryen-fov Rust crate
// TODO: provide link here
pub fn shadowcast(coord: Coord, octs: [8]?usize, radius: usize, limit: Coord, tile_opacity: fn (Coord) f64, buf: *CoordArrayList) void {
    // Area of coverage by each octant (the MULT constant does the job of
    // converting between octants, I think?):
    //
    //                               North
    //                                 |
    //                            \0000|3333/
    //                            1\000|333/2
    //                            11\00|33/22
    //                            111\0|3/222
    //                            1111\|/2222
    //                       West -----@------ East
    //                            6666/|\5555
    //                            666/7|4\555
    //                            66/77|44\55
    //                            6/777|444\5
    //                            /7777|4444\
    //                                 |
    //                               South
    //
    // Don't ask me how the octants were all displaced from what should've been
    // their positions, I inherited(?) this problem from the doryen-fov Rust
    // crate, from which this shadowcasting code was ported.
    //
    const MULT = [4][8]isize{
        [_]isize{ 1, 0, 0, -1, -1, 0, 0, 1 },
        [_]isize{ 0, 1, -1, 0, 0, -1, 1, 0 },
        [_]isize{ 0, 1, 1, 0, 0, -1, -1, 0 },
        [_]isize{ 1, 0, 0, 1, -1, 0, 0, -1 },
    };

    var max_radius = radius;
    if (max_radius == 0) {
        const max_radius_x = math.max(limit.x - coord.x, coord.x);
        const max_radius_y = math.max(limit.y - coord.y, coord.y);
        max_radius = @floatToInt(usize, math.sqrt(@intToFloat(f64, max_radius_x * max_radius_x + max_radius_y * max_radius_y))) + 1;
    }

    const r2 = max_radius * max_radius;
    for (octs) |maybe_oct| {
        if (maybe_oct) |oct| {
            _cast_light(@intCast(isize, coord.x), @intCast(isize, coord.y), 1, 1.0, 0.0, @intCast(isize, max_radius), @intCast(isize, r2), MULT[0][oct], MULT[1][oct], MULT[2][oct], MULT[3][oct], limit, buf, tile_opacity);
        }
    }

    // Adding the current coord doesn't seem like a good idea
    // TODO: enumerate the reasons here in a coherent way
    //buf.append(coord) catch unreachable;
}

fn _cast_light(cx: isize, cy: isize, row: isize, start_p: f64, end: f64, radius: isize, r2: isize, xx: isize, xy: isize, yx: isize, yy: isize, limit: Coord, buf: *CoordArrayList, tile_opacity: fn (Coord) f64) void {
    if (start_p < end) {
        return;
    }
    var start = start_p;
    var new_start: f64 = 0.0;

    var j: isize = row;
    var stepj: isize = if (row < radius) 1 else -1;

    while (j < radius) : (j += stepj) {
        const dy = -j;
        var dx = -j - 1;
        var blocked = false;

        while (dx <= 0) {
            dx += 1;

            const cur_x = cx + dx * xx + dy * xy;
            const cur_y = cy + dx * yx + dy * yy;

            if (cur_x >= 0 and cur_x < @intCast(isize, limit.x) and cur_y >= 0 and cur_y < @intCast(isize, limit.y)) {
                //const off = @intCast(usize, cur_x) + @intCast(usize, cur_y) * limit.x;
                const coord = Coord.new(@intCast(usize, cur_x), @intCast(usize, cur_y));
                const l_slope = (@intToFloat(f64, dx) - 0.5) / (@intToFloat(f64, dy) + 0.5);
                const r_slope = (@intToFloat(f64, dx) + 0.5) / (@intToFloat(f64, dy) - 0.5);

                if (start < r_slope) {
                    continue;
                } else if (end > l_slope) {
                    break;
                }

                if (dx * dx + dy * dy <= r2) {
                    buf.append(coord) catch unreachable;
                }

                if (blocked) {
                    if (tile_opacity(coord) >= 1.0) {
                        new_start = r_slope;
                        continue;
                    } else {
                        blocked = false;
                        start = new_start;
                    }
                } else if (tile_opacity(coord) >= 1.0 and j < radius) {
                    blocked = true;
                    _cast_light(cx, cy, j + 1, start, l_slope, radius, r2, xx, xy, yx, yy, limit, buf, tile_opacity);
                    new_start = r_slope;
                }
            }
        }
        if (blocked) {
            break;
        }
    }
}
