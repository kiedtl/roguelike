const std = @import("std");
const math = std.math;
const sort = std.sort;
const assert = std.debug.assert;

const rng = @import("rng.zig");

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
pub const RED: u32 = 0xebafaf;
pub const PALE_VIOLET_RED: u32 = 0xdb7093;
pub const LIGHT_PALE_VIOLET_RED: u32 = 0xfb90b3;
pub const AQUAMARINE: u32 = 0x7fffd4;
pub const GOLD: u32 = 0xddb733;
pub const LIGHT_GOLD: u32 = 0xfdd753;
pub const COPPER_RED: u32 = 0x985744;

pub const BG: u32 = percentageOf(CONCRETE, 10);
pub const BG_L: u32 = percentageOf(CONCRETE, 30);
pub const ABG: u32 = percentageOf(LIGHT_STEEL_BLUE, 20);
pub const ABG_L: u32 = percentageOf(LIGHT_STEEL_BLUE, 40);

pub const ColorDance = struct {
    each: u24,
    all: u8,

    pub fn apply(self: @This(), to: u32, n: anytype) u32 {
        const common = rng.rangeManaged(n, u24, 0, self.all);
        const r = (to >> 16) + rng.rangeManaged(n, u24, 0, self.each >> 16) + common;
        const g = ((to >> 8) & 0xFF) + rng.rangeManaged(n, u24, 0, (self.each >> 8) & 0xFF) + common;
        const b = (to & 0xFF) + rng.rangeManaged(n, u24, 0, (self.each) & 0xFF) + common;
        return r << 16 | g << 8 | b;
    }
};

// Interpolate linearly between two vals.
fn interpolate(a: u32, b: u32, f: f64) u32 {
    const aa = @as(f64, @floatFromInt(a)) / 255;
    const ab = @as(f64, @floatFromInt(b)) / 255;
    return @as(u32, @intFromFloat((aa + f * (ab - aa)) * 255));
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

// How could I forget that percentageOf clamps the value...
pub fn percentageOf2(color: u32, percentage: u32) u32 {
    const r: u32 = @min(((color >> 16) & 0xFF) * percentage / 100, 0xFF);
    const g: u32 = @min(((color >> 8) & 0xFF) * percentage / 100, 0xFF);
    const b: u32 = @min(((color >> 0) & 0xFF) * percentage / 100, 0xFF);
    return (r << 16) | (g << 8) | b;
}

pub fn percentageOf(color: u32, _p: usize) u32 {
    const percentage: u32 = @intCast(math.clamp(_p, 0, 100));
    const r: u32 = @min(((color >> 16) & 0xFF) * percentage / 100, 0xFF);
    const g: u32 = @min(((color >> 8) & 0xFF) * percentage / 100, 0xFF);
    const b: u32 = @min(((color >> 0) & 0xFF) * percentage / 100, 0xFF);
    return (r << 16) | (g << 8) | b;
}

pub fn darken(color: u32, by: u32) u32 {
    const r = ((color >> 16) & 0xFF) / by;
    const g = ((color >> 8) & 0xFF) / by;
    const b = ((color >> 0) & 0xFF) / by;
    return (r << 16) | (g << 8) | b;
}

pub fn brightness(color: u32) u32 {
    const r = @as(f64, @floatFromInt(((color >> 16) & 0xFF)));
    const g = @as(f64, @floatFromInt(((color >> 8) & 0xFF)));
    const b = @as(f64, @floatFromInt(((color >> 0) & 0xFF)));
    return @intFromFloat(0.299 * r + 0.587 * g + 0.114 * b);
}

pub fn filterGrayscale(color: u32) u32 {
    const bri = brightness(color);
    return (bri << 16) | (bri << 8) | bri;
}

pub fn filterBluescale(color: u32) u32 {
    const bri = brightness(color);
    const newrg = bri * 60 / 100;
    return (newrg << 16) | (newrg << 8) | bri;
}
