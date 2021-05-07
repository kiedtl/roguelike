const std = @import("std");

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
