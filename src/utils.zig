const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const mem = std.mem;

pub fn saturating_sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return switch (@typeInfo(@TypeOf(a))) {
        .ComptimeInt, .Int => if ((a -% b) > a) 0 else a - b,
        .ComptimeFloat, .Float => if ((a - b) > a) 0 else a - b,
        else => @compileError("Type '" ++ @typeName(a) ++ "' not supported"),
    };
}

// interpolate linearly between two vals
fn interpolate(a: u32, b: u32, f: f64) u32 {
    const aa = @intToFloat(f64, a) / 255;
    const ab = @intToFloat(f64, b) / 255;
    return @floatToInt(u32, (aa + f * (ab - aa)) * 255);
}

// STYLE: move to separate colors module
pub fn mixColors(a: u32, b: u32, frac: f64) u32 {
    assert(frac <= 100);

    const ar = (a >> 16) & 0xFF;
    const ag = (a >> 08) & 0xFF;
    const ab = (a >> 00) & 0xFF;
    const br = (b >> 16) & 0xFF;
    const bg = (b >> 08) & 0xFF;
    const bb = (b >> 00) & 0xFF;
    const rr = interpolate(ar, br, frac);
    const rg = interpolate(ag, bg, frac);
    const rb = interpolate(ab, bb, frac);
    return (rr << 16) | (rg << 8) | rb;
}

pub fn percentageOfColor(color: u32, _p: usize) u32 {
    const percentage = math.clamp(_p, 0, 100);
    var r = ((color >> 16) & 0xFF) * @intCast(u32, percentage) / 100;
    var g = ((color >> 08) & 0xFF) * @intCast(u32, percentage) / 100;
    var b = ((color >> 00) & 0xFF) * @intCast(u32, percentage) / 100;
    r = math.clamp(r, 0, 0xFF);
    g = math.clamp(g, 0, 0xFF);
    b = math.clamp(b, 0, 0xFF);
    return (r << 16) | (g << 8) | b;
}

pub fn darkenColor(color: u32, by: u32) u32 {
    const r = ((color >> 16) & 0xFF) / by;
    const g = ((color >> 08) & 0xFF) / by;
    const b = ((color >> 00) & 0xFF) / by;
    return (r << 16) | (g << 8) | b;
}

pub fn findById(haystack: anytype, _needle: anytype) ?usize {
    const needle = _needle[0..mem.lenZ(_needle)];

    for (haystack) |straw, i| {
        const id = straw.id[0..mem.lenZ(straw.id)];
        std.log.warn("searching for '{}', got '{}'", .{ needle, straw.id });
        if (mem.eql(u8, needle, straw.id)) return i;
    }

    return null;
}
