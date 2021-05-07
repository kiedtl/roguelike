const std = @import("std");
const math = std.math;

const state = @import("state.zig");
usingnamespace @import("types.zig");

fn tile_opacity(coord: Coord) f64 {
    const tile = state.dungeon[coord.y][coord.x];
    return if (tile.type == .Wall) 1.0 else 0.0;
}

// This was supposed to be a raytracer.
// I have no idea what it is now.
pub fn naive(center: Coord, radius: usize, limit: Coord, buf: *CoordArrayList) void {
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

            cumulative_opacity += tile_opacity(line_coord);
            buf.append(line_coord) catch unreachable;
        }
    }
}

// Ported from doryen-fov Rust crate
// TODO: provide link here
const MULT0 = [8]isize{ 1, 0, 0, -1, -1, 0, 0, 1 };
const MULT1 = [8]isize{ 0, 1, -1, 0, 0, -1, 1, 0 };
const MULT2 = [8]isize{ 0, 1, 1, 0, 0, -1, -1, 0 };
const MULT3 = [8]isize{ 1, 0, 0, 1, -1, 0, 0, -1 };

fn _cast_light(cx: isize, cy: isize, row: isize, start_p: f64, end: f64, radius: isize, r2: isize, xx: isize, xy: isize, yx: isize, yy: isize, id: isize, limit: Coord, buf: *CoordArrayList) void {
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
                    _cast_light(cx, cy, j + 1, start, l_slope, radius, r2, xx, xy, yx, yy, id + 1, limit, buf);
                    new_start = r_slope;
                }
            }
        }
        if (blocked) {
            break;
        }
    }
}

pub fn shadowcast(coord: Coord, max_radius_p: usize, limit: Coord, buf: *CoordArrayList) void {
    var max_radius = max_radius_p;
    if (max_radius_p == 0) {
        const max_radius_x = math.max(limit.x - coord.x, coord.x);
        const max_radius_y = math.max(limit.y - coord.y, coord.y);
        max_radius = @floatToInt(usize, math.sqrt(@intToFloat(f64, max_radius_x * max_radius_x + max_radius_y * max_radius_y))) + 1;
    }

    const r2 = max_radius * max_radius;
    const octants = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7 };
    for (octants) |oct| {
        _cast_light(@intCast(isize, coord.x), @intCast(isize, coord.y), 1, 1.0, 0.0, @intCast(isize, max_radius), @intCast(isize, r2), MULT0[oct], MULT1[oct], MULT2[oct], MULT3[oct], 0, limit, buf);
    }
    buf.append(coord) catch unreachable;
}
