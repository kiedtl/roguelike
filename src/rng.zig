// FIXME: using f64 as T for range/rangeClumping returns, shall we say, incorrect
// values

const std = @import("std");
const assert = std.debug.assert;
const sort = std.sort;
const math = std.math;

var rng: std.Random.DefaultPrng = undefined;
var rng2: std.Random.DefaultPrng = undefined;
pub var using_temp = false;
pub const seed = &@import("state.zig").seed;

//seed = 0xdefaced_cafe;

pub fn init() void {
    rng = @TypeOf(rng).init(seed.*);
}

pub fn useTemp(tseed: u64) void {
    assert(!using_temp);
    const t = rng;
    rng = rng2;
    rng2 = t;
    rng = @TypeOf(rng).init(tseed);
    using_temp = true;
}

pub fn useNorm() void {
    assert(using_temp);
    const t = rng2;
    rng2 = rng;
    rng = t;
    using_temp = false;
}

pub fn int(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int => rng.random().int(T),
        .float => rng.random().float(T),
        else => @compileError("Expected int or float, got " ++ @typeName(T)),
    };
}

pub fn intManaged(myrng: anytype, comptime T: type) T {
    return switch (@typeInfo(T)) {
        .int => myrng.int(T),
        .float => myrng.float(T),
        else => @compileError("Expected int or float, got " ++ @typeName(T)),
    };
}

pub fn boolean() bool {
    return rng.random().int(u1) == 1;
}

pub fn percent(number: anytype) bool {
    const n = if (@TypeOf(number) == comptime_int) @as(usize, number) else number;
    return range(@TypeOf(n), 1, 100) < @min(100, n);
}

// TODO: make generic
pub fn tenin(number: usize) bool {
    assert(number >= 10);
    return range(@TypeOf(number), 1, number) <= 10;
}

// TODO: make generic
pub fn onein(number: usize) bool {
    return range(@TypeOf(number), 1, number) == 1;
}

pub fn oneInManaged(myrng: anytype, number: anytype) bool {
    const T = if (@TypeOf(number) == comptime_int) usize else @TypeOf(number);
    return rangeManaged(myrng, T, 1, number) == 1;
}

// Ported from BrogueCE's source. (src/brogue/Math.c:40, randClumpedRange())
pub fn rangeClumping(comptime T: type, min: T, max: T, clump: T) T {
    std.debug.assert(max >= min);
    if (clump <= 1) return range(T, min, max);

    const sides = @divTrunc(max - min, clump);
    var i: T = 0;
    var total: T = 0;

    while (i < @mod(max - min, clump)) : (i += 1) total += range(T, 0, sides + 1);
    while (i < clump) : (i += 1) total += range(T, 0, sides);

    return total + min;
}

// STYLE: change to range(min: anytype, max: @TypeOf(min)) @TypeOf(min)
pub fn range(comptime T: type, min: T, max: T) T {
    std.debug.assert(max >= min);
    const diff = (max + 1) - min;
    return if (diff > 0) @mod(int(T), diff) + min else min;
}

pub fn rangeManaged(myrng: anytype, comptime T: type, min: T, max: T) T {
    std.debug.assert(max >= min);
    const diff = (max + 1) - min;
    return if (diff > 0) @mod(intManaged(myrng, T), diff) + min else min;
}

pub fn shuffle(comptime T: type, arr: []T) void {
    // Commented out: As of Zig 0.13.0-dev (close to release of Zig 0.14.0),
    // this hangs indefinitely while shuffling list of Prefabs (which are large
    // structs, dunno if that has anything to do with this).
    //
    //rng.random().shuffle(T, arr);

    var i: usize = arr.len - 1;
    while (i > 0) : (i -= 1) {
        const j = range(usize, 0, i);
        const temp = arr[i];
        arr[i] = arr[j];
        arr[j] = temp;
    }
}

pub fn chooseUnweighted(comptime T: type, arr: []const T) T {
    return arr[range(usize, 0, arr.len - 1)];
}

// TODO: reduce duplicate code between choose2 and choose
pub fn choose(comptime T: type, arr: []const T, weights: []const usize) !T {
    if (arr.len != weights.len) return error.InvalidWeights;

    var weight_total: usize = 0;
    var selected = arr[0];

    for (arr, 0..) |item, index| {
        const weight = weights[index];
        if (weight == 0) continue;

        const rnd = rng.random().int(usize) % (weight_total + weight);
        if (rnd >= weight_total) // probability is weight/(total+weight)
            selected = item;

        weight_total += weight;
    }

    return selected;
}

// TODO: reduce duplicate code between choose2 and choose
// FIXME: this can never return an error, fix the return type.
pub fn choose2(comptime T: type, arr: []const T, comptime weight_field: []const u8) !T {
    var weight_total: usize = 0;
    var selected = arr[0];

    for (arr) |item| {
        const weight = @field(item, weight_field);
        if (weight == 0) continue;

        const rnd = rng.random().int(usize) % (weight_total + weight);
        if (rnd >= weight_total) // probability is weight/(total+weight)
            selected = item;

        weight_total += weight;
    }

    return selected;
}

// TODO: reduce duplicate code between choose2 and choose
pub fn chooseInd2(comptime T: type, arr: []const T, comptime weight_field: []const u8) usize {
    var weight_total: usize = 0;
    var selected: usize = 0;

    for (arr, 0..) |item, ind| {
        const weight = @field(item, weight_field);
        if (weight == 0) continue;

        const rnd = rng.random().int(usize) % (weight_total + weight);
        if (rnd >= weight_total) // probability is weight/(total+weight)
            selected = ind;

        weight_total += weight;
    }

    return selected;
}

test "range" {
    const testing = std.testing;

    seed.* = 2384928349;
    init();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const r_u8 = range(u8, 10, 200);
        const r_usize = range(usize, 34234, 89821);

        try testing.expect(r_u8 >= 10 and r_u8 <= 200);
        try testing.expect(r_usize >= 34234 and r_usize <= 89821);
    }
}

// When piped into `jp -input csv -type bar`, visualizes the results of
// rangeClumping(). Was a great help in helping the author to understand exactly
// what a Gaussian distribution is, and what effects the clumping factor
// had on the results.
//
// pub fn main() anyerror!void {
//     init();
//     const max = 25;
//     var occurs = [_]usize{0} ** (max + 1);
//     for (0..10_000) |_| {
//         occurs[rangeClumping(usize, 0, max, 4)] += 1;
//     }
//     for (&occurs, 0..) |occurance, number| {
//         std.debug.print("{},{}\n", .{ number, occurance });
//     }
// }
