// Sometimes used for generating random mob distributions for prefabs (e.g.
// WRK_storage_misfits)
//

const std = @import("std");
const rand = std.rand;
const math = std.math;

var rng: rand.Isaac64 = undefined;

pub fn main() anyerror!void {
    const seed = @intCast(u64, std.time.milliTimestamp());
    rng = rand.Isaac64.init(seed);

    var i: usize = 0;
    while (i < 3 * 4) : (i += 1) {
        const base: u8 = if (boolean()) '1' else 'a';
        const ch = base + range(u8, 0, 3);
        try std.io.getStdOut().writer().writeByte(ch);
    }

    try std.io.getStdOut().writer().writeByte('\n');
}

pub fn int(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .Int => rng.random().int(T),
        .Float => rng.random().float(T),
        else => @compileError("Expected int or float, got " ++ @typeName(T)),
    };
}

pub fn boolean() bool {
    return rng.random().int(u1) == 1;
}

pub fn range(comptime T: type, min: T, max: T) T {
    std.debug.assert(max >= min);
    const diff = (max + 1) - min;
    return if (diff > 0) @mod(int(T), diff) + min else min;
}
