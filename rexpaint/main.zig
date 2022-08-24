const std = @import("std");
const RexMap = @import("RexMap.zig");

pub fn main() anyerror!void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const map = try RexMap.initFromFile(arena.allocator(), "data/logo.xp");
    defer map.deinit();

    var y: usize = 0;
    while (y < map.height) : (y += 1) {
        var x: usize = 0;
        while (x < map.width) : (x += 1) {
            const tile = map.get(0, x, y);

            if (tile.bg.r == 255 and tile.bg.g == 0 and tile.bg.b == 255) {
                std.debug.print("\x1b[m ", .{});
                continue;
            }

            std.debug.print("\x1b[38;2;{};{};{}m\x1b[48;2;{};{};{}m", .{ tile.fg.r, tile.fg.g, tile.fg.b, tile.bg.r, tile.bg.g, tile.bg.b });

            var utf8_out: [4]u8 = undefined;
            const utf8_len = try std.unicode.utf8Encode(RexMap.DEFAULT_TILEMAP[tile.ch], &utf8_out);
            if (utf8_len > 0) {
                std.debug.print("{s}", .{utf8_out[0..utf8_len]});
            } else {
                std.debug.print(" ", .{});
            }
        }
        std.debug.print("\x1b[m\n", .{});
    }

    std.debug.print("\x1b[m\n", .{});
}
