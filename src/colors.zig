const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

pub const GREY: u32 = 0xafafaf;
pub const WHITE: u32 = 0xffffff;
pub const BG_GREY: u32 = 0x1e1e1e;
pub const BLACK: u32 = 0x000000;
pub const CONCRETE: u32 = 0x968f74;
pub const LIGHT_CONCRETE: u32 = 0xe6dfc4;
pub const PINK: u32 = 0xffc0cb;

// Interpolate linearly between two vals.
//
// (addendum 22-03-03: I have no idea what this means)
//
fn interpolate(a: u32, b: u32, f: f64) u32 {
    const aa = @intToFloat(f64, a) / 255;
    const ab = @intToFloat(f64, b) / 255;
    return @floatToInt(u32, (aa + f * (ab - aa)) * 255);
}

pub fn mix(a: u32, b: u32, frac: f64) u32 {
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

pub fn percentageOf(color: u32, _p: usize) u32 {
    const percentage = math.clamp(_p, 0, 100);
    var r = ((color >> 16) & 0xFF) * @intCast(u32, percentage) / 100;
    var g = ((color >> 08) & 0xFF) * @intCast(u32, percentage) / 100;
    var b = ((color >> 00) & 0xFF) * @intCast(u32, percentage) / 100;
    r = math.clamp(r, 0, 0xFF);
    g = math.clamp(g, 0, 0xFF);
    b = math.clamp(b, 0, 0xFF);
    return (r << 16) | (g << 8) | b;
}

pub fn darken(color: u32, by: u32) u32 {
    const r = ((color >> 16) & 0xFF) / by;
    const g = ((color >> 08) & 0xFF) / by;
    const b = ((color >> 00) & 0xFF) / by;
    return (r << 16) | (g << 8) | b;
}

pub fn filterGrayscale(color: u32) u32 {
    const r = @intToFloat(f64, ((color >> 16) & 0xFF));
    const g = @intToFloat(f64, ((color >> 08) & 0xFF));
    const b = @intToFloat(f64, ((color >> 00) & 0xFF));
    const brightness = @floatToInt(u32, 0.299 * r + 0.587 * g + 0.114 * b);
    return (brightness << 16) | (brightness << 8) | brightness;
}