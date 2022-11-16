const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

pub const GREY: u32 = 0xafafaf;
pub const DARK_GREY: u32 = 0x8a8a8a;
pub const OFF_WHITE: u32 = 0xe6e6e6;
pub const WHITE: u32 = 0xffffff;
pub const BG_GREY: u32 = 0x1e1e1e;
pub const BLACK: u32 = 0x000000;
pub const CONCRETE: u32 = 0x9f8f74;
pub const LIGHT_CONCRETE: u32 = 0xefdfc4;
pub const PINK: u32 = 0xffc0cb;
pub const DOBALENE_BLUE: u32 = 0xb5d0ff;
pub const LIGHT_STEEL_BLUE: u32 = 0xb0c4de;
pub const PALE_VIOLET_RED: u32 = 0xdb7093;
pub const LIGHT_PALE_VIOLET_RED: u32 = 0xfb90b3;
pub const AQUAMARINE: u32 = 0x7fffd4;
pub const GOLD: u32 = 0xddb733;
pub const LIGHT_GOLD: u32 = 0xfdd753;
pub const COPPER_RED: u32 = 0x985744;

pub const BG: u32 = percentageOf(CONCRETE, 10);

// Interpolate linearly between two vals.
fn interpolate(a: u32, b: u32, f: f64) u32 {
    const aa = @intToFloat(f64, a) / 255;
    const ab = @intToFloat(f64, b) / 255;
    return @floatToInt(u32, (aa + f * (ab - aa)) * 255);
}

pub fn mix(a: u32, b: u32, frac: f64) u32 {
    assert(frac <= 100);

    const ar = (a >> 16) & 0xFF;
    const ag = (a >> 8) & 0xFF;
    const ab = (a >> 0) & 0xFF;
    const br = (b >> 16) & 0xFF;
    const bg = (b >> 8) & 0xFF;
    const bb = (b >> 0) & 0xFF;
    const rr = interpolate(ar, br, frac);
    const rg = interpolate(ag, bg, frac);
    const rb = interpolate(ab, bb, frac);
    return (rr << 16) | (rg << 8) | rb;
}

pub fn percentageOf(color: u32, _p: usize) u32 {
    const percentage = @intCast(u32, math.clamp(_p, 0, 100));
    const r = math.min(((color >> 16) & 0xFF) * percentage / 100, 0xFF);
    const g = math.min(((color >> 8) & 0xFF) * percentage / 100, 0xFF);
    const b = math.min(((color >> 0) & 0xFF) * percentage / 100, 0xFF);
    return (r << 16) | (g << 8) | b;
}

pub fn darken(color: u32, by: u32) u32 {
    const r = ((color >> 16) & 0xFF) / by;
    const g = ((color >> 8) & 0xFF) / by;
    const b = ((color >> 0) & 0xFF) / by;
    return (r << 16) | (g << 8) | b;
}

pub fn filterGrayscale(color: u32) u32 {
    const r = @intToFloat(f64, ((color >> 16) & 0xFF));
    const g = @intToFloat(f64, ((color >> 8) & 0xFF));
    const b = @intToFloat(f64, ((color >> 0) & 0xFF));
    const brightness = @floatToInt(u32, 0.299 * r + 0.587 * g + 0.114 * b);
    return (brightness << 16) | (brightness << 8) | brightness;
}
