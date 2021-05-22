pub fn saturating_sub(a: anytype, b: @TypeOf(a)) @TypeOf(a) {
    return if ((a -% b) > a) 0 else a - b;
}

// interpolate linearly between two vals
fn interpolate(a: u32, b: u32, f: f64) u32 {
    const aa = @intToFloat(f64, a) / 255;
    const ab = @intToFloat(f64, b) / 255;
    return @floatToInt(u32, (aa + f * (ab - aa)) * 255);
}

// STYLE: move to separate colors module
pub fn mixColors(a: u32, b: u32, frac: f64) u32 {
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
