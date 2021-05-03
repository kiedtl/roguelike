const std = @import("std");

const rng = @import("rng.zig");
const mapgen = @import("mapgen.zig");
const types = @import("types.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

fn print() void {
    for (state.dungeon) |level| {
        for (level) |tile| {
            var ch: u21 = switch (tile.type) {
                .Wall => '#',
                .Floor => '.',
            };

            if (tile.mob) |mob| {
                ch = mob.tile;
            }

            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(ch, &buf) catch unreachable;
            std.debug.print("{}", .{buf});
        }
        std.debug.print("\n", .{});
    }
}

pub fn main() anyerror!void {
    rng.init();
    mapgen.drunken_walk();
    mapgen.add_guard_stations();
    print();
}
