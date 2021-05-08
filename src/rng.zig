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

pub fn shuffle(comptime T: type, arr: []T) void {
    rng.random.shuffle(T, arr);
}

pub fn choose(comptime T: type, arr: []const T, weights: []const usize) !T {
    if (arr.len != weights.len) return error.InvalidWeights;

    var weight_total: usize = 0;
    var selected = arr[0];

    for (arr) |item, index| {
        const weight = weights[index];
        const rnd = rng.random.int(usize) % (weight_total + weight);
        if (rnd >= weight_total) // probability is weight/(total+weight)
            selected = item;
        weight_total += weight;
    }

    return selected;
}
