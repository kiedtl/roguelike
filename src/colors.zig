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
pub const STEEL_BLUE: u32 = 0x8094ae;
pub const RED: u32 = 0xebafaf;
pub const PALE_VIOLET_RED: u32 = 0xdb7093;
pub const LIGHT_PALE_VIOLET_RED: u32 = 0xfb90b3;
pub const AQUAMARINE: u32 = 0x7fffd4;
pub const GOLD: u32 = 0xddb733;
pub const LIGHT_GOLD: u32 = 0xfdd753;
pub const COPPER_RED: u32 = 0x985744;
pub const NIGHT_BLUE: u32 = 0x5919d3;
pub const POLISHED_SLADE: u32 = 0xa01bcf;

pub const DARK_GREEN = 0x075f00;
pub const GREEN = 0x37af00;
pub const LIGHT_GREEN = 0x37af00;

pub const BG: u32 = percentageOf(CONCRETE, 10);
pub const BG_L: u32 = percentageOf(CONCRETE, 30);
pub const ABG: u32 = percentageOf(LIGHT_STEEL_BLUE, 20);
pub const ABG_L: u32 = percentageOf(LIGHT_STEEL_BLUE, 40);

pub const ColorDance = struct {
    each: u24,
    all: u8,

    pub fn apply(self: @This(), to: u32, n: anytype) u32 {
        const common = rng.rangeManaged(n, u8, 0, self.all);
        const each_r, const each_g, const each_b = decompose(self.each);
        const cr, const cg, const cb = decompose(to);
        const r = cr +| rng.rangeManaged(n, u8, 0, each_r) +| common;
        const g = cg +| rng.rangeManaged(n, u8, 0, each_g) +| common;
        const b = cb +| rng.rangeManaged(n, u8, 0, each_b) +| common;
        assert(r <= 255 and g <= 255 and b <= 255);
        return compose(r, g, b);
    }
};

pub fn compose(r: u8, g: u8, b: u8) u24 {
    return (@as(u24, @intCast(r)) << 16) | (@as(u24, @intCast(g)) << 8) | b;
}

pub fn decompose(c: u32) struct { u8, u8, u8 } {
    return .{ @intCast(c >> 16), @intCast((c >> 8) & 0xFF), @intCast(c & 0xFF) };
}

pub fn decomposeIntoFloat(c: u32) struct { f32, f32, f32 } {
    return .{
        @as(f32, @floatFromInt(c >> 16)) / 255.0,
        @as(f32, @floatFromInt((c >> 8) & 0xFF)) / 255.0,
        @as(f32, @floatFromInt(c & 0xFF)) / 255.0,
    };
}

// Interpolate linearly between two vals.
fn interpolate(a: u32, b: u32, f: f64) u32 {
    const aa = @as(f64, @floatFromInt(a)) / 255;
    const ab = @as(f64, @floatFromInt(b)) / 255;
    return @as(u32, @intFromFloat((aa + f * (ab - aa)) * 255));
}

pub fn mix(a: u32, b: u32, pfrac: f64) u32 {
    const frac = math.clamp(pfrac, 0.0, 1.0);
    const ar, const ag, const ab = decompose(a);
    const br, const bg, const bb = decompose(b);
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

pub fn brightnessf(color: u32) f64 {
    const r = @as(f64, @floatFromInt(((color >> 16) & 0xFF))) / 255.0;
    const g = @as(f64, @floatFromInt(((color >> 8) & 0xFF))) / 255.0;
    const b = @as(f64, @floatFromInt(((color >> 0) & 0xFF))) / 255.0;
    return 0.299 * r + 0.587 * g + 0.114 * b;
}

// Returns integer in range 0..255, reflecting received brightness of color.
pub fn brightness(color: u32) u32 {
    return @intFromFloat(brightnessf(color) * 255.0);
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

pub fn filterGreenscale(color: u32) u32 {
    const bri = brightness(color);
    // Percentages are derived from the color 0x506057
    const r: u8 = @intCast(bri * 833 / 1000);
    const g: u8 = @intCast(bri);
    const b: u8 = @intCast(bri * 906 / 1000);
    return compose(r, g, b);
}
