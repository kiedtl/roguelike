// Serialize a matrix using run-length encoding.

const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const serializer = @import("../serializer.zig");

pub fn Run(comptime T: type) type {
    // We choose u8 because it can record a Coord losslessly.
    const state = @import("../state.zig");
    assert(state.HEIGHT < math.maxInt(u8));
    assert(state.WIDTH < math.maxInt(u8));

    return struct {
        x: u8,
        y: u8,
        length: u8,
        value: T,
    };
}

pub fn serializeMatrix(
    // Element of the matrix. E.g. for [][]u8, Elem = u8.
    comptime Elem: type,

    // The value recorded as being part of the run if it matters during
    // deserialization.
    // - Example: for a [][]u8, it might only matter if the cell value is >0 --
    //   in which case, RunValue can be void.
    // - Example: for a [][]SomeType, it might matter during deserialization if
    //   SomeType.foo is 25 or 50, in which case RunValue will have to store this
    //   information and can be usize.
    // Only the first value in a run is recorded.
    comptime RunValue: type,
    extract_run_value: *const fn (usize, usize, *const Elem) ?RunValue,
    comptime height: usize,
    comptime width: usize,
    matrix: *const [height][width]Elem,
    ser: *serializer.Serializer,
    out: anytype,
) serializer.Error!void {
    var is_in_run = false;
    var ctr: u16 = 0;
    for (0..height) |y|
        for (0..width) |x| {
            if ((extract_run_value)(x, y, &matrix[y][x]) != null) {
                is_in_run = true;
            } else {
                if (is_in_run) {
                    is_in_run = false;
                    ctr += 1;
                }
            }

            if (is_in_run) {
                ctr += 1;
                is_in_run = false;
            }
        };

    try ser.serializeScalar(u16, ctr, out);

    var run: ?Run(RunValue) = null;
    for (0..height) |y|
        for (0..width) |x| {
            if ((extract_run_value)(x, y, &matrix[y][x])) |val| {
                if (run) |*r| {
                    r.length += 1;
                } else {
                    run = Run(RunValue){
                        .x = @intCast(x),
                        .y = @intCast(y),
                        .length = 1,
                        .value = val,
                    };
                }
            } else {
                if (run) |*r| {
                    try ser.serialize(Run(RunValue), r, out);
                    run = null;
                }
            }

            if (run) |*r| {
                try ser.serialize(Run(RunValue), r, out);
                run = null;
            }
        };
}

pub fn deserializeMatrix(
    comptime Elem: type,
    comptime RunValue: type,
    convert_run_value: *const fn (usize, usize, usize, RunValue) Elem,
    comptime height: usize,
    comptime width: usize,
    ser: *serializer.Serializer,
    out: *[height][width]Elem,
    in: anytype,
    alloc: mem.Allocator,
) serializer.Error!void {
    var i = try ser.deserializeQ(u16, in, alloc);
    while (i > 0) : (i -= 1) {
        const run = try ser.deserializeQ(Run(RunValue), in, alloc);
        for (0..run.length) |xi|
            out[run.y][run.x + xi] = (convert_run_value)(run.x, run.y, run.length, run.value);
    }
}
