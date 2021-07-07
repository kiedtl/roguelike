// Yes, yes, I know Zig has a `rand` module. But, hey, reinventing the wheel is
// fun!!

const std = @import("std");
const rand = std.rand;
const math = std.math;

var rng: rand.Isaac64 = undefined;

pub fn init() void {
    rng = rand.Isaac64.init(0xdefaced_cafe);
}

pub fn int(comptime T: type) T {
    return rng.random.int(T);
}

pub fn boolean() bool {
    return rng.random.int(u1) == 1;
}

pub fn onein(number: usize) bool {
    return range(@TypeOf(number), 1, number) == 1;
}

// Ported from BrogueCE's source. (src/brogue/Math.c:40, randClumpedRange())
pub fn rangeClumping(comptime T: type, min: T, max: T, clump: T) T {
    std.debug.assert(max >= min);
    if (clump <= 1) return range(T, min, max);

    const sides = (max - min) / clump;
    var i: usize = 0;
    var total: usize = 0;

    while (i < (max - min) % clump) : (i += 1) total += range(T, 0, sides + 1);
    while (i < clump) : (i += 1) total += range(T, 0, sides);

    return total + min;
}

// STYLE: change to range(min: anytype, max: @TypeOf(min)) @TypeOf(min)
pub fn range(comptime T: type, min: T, max: T) T {
    std.debug.assert(max >= min);
    const diff = (max + 1) - min;
    return if (diff > 0) (int(T) % diff) + min else min;
}

pub fn shuffle(comptime T: type, arr: []T) void {
    rng.random.shuffle(T, arr);
}

pub fn chooseUnweighted(comptime T: type, arr: []const T) T {
    return arr[range(usize, 0, arr.len - 1)];
}

pub fn choose(comptime T: type, arr: []const T, weights: []const usize) !T {
    if (arr.len != weights.len) return error.InvalidWeights;

    var weight_total: usize = 0;
    var selected = arr[0];

    for (arr) |item, index| {
        const weight = weights[index];
        if (weight == 0) continue;

        const rnd = rng.random.int(usize) % (weight_total + weight);
        if (rnd >= weight_total) // probability is weight/(total+weight)
            selected = item;

        weight_total += weight;
    }

    return selected;
}

test "range" {
    const testing = std.testing;

    init();

    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const r_u8 = range(u8, 10, 200);
        const r_usize = range(usize, 34234, 89821);

        std.testing.expect(r_u8 >= 10 and r_u8 < 200);
        std.testing.expect(r_usize >= 34234 and r_usize < 89821);
    }
}

// When piped into `jp -input csv -type bar`, visualizes the results of
// rangeClumping(). Was a great help in helping the author to understand exactly
// what a Gaussian distribution is, and what effects the clumping factor
// had on the results.
//
//pub fn main() anyerror!void {
//    init();
//    const max = 25;
//    var occurs = [_]usize{0} ** (max + 1);
//    for ([_]usize{0} ** 2000) |_, i| {
//        occurs[rangeClumping(usize, 0, max, 5)] += 1;
//    }
//    for (&occurs) |occurance, number| {
//        std.debug.print("{},{}\n", .{ number, occurance });
//    }
//}
