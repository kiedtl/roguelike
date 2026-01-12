// Serialize a matrix using run-length encoding.

const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const serde = @import("../serde.zig");

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

// Serialize a matrix with run-length encoding. The matrix's cells must have
// values that are not significant in and of itself, but only their presence is
// significant. Example is the matrix storing light data, since it's a simple
// true or false value (is there light on the tile?), or a matrix storing data
// on if a mob can see a specific tile.
//
// Matrices that cannot be serialized with this set of functions include gas
// data (since it matters if the gas value is 24 or 13).
//
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
    ser: *serde.Serializer,
    out: anytype,
) serde.Error!void {
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
    ser: *serde.Deserializer,
    out: *[height][width]Elem,
    in: anytype,
    alloc: mem.Allocator,
) serde.Error!void {
    var i = try ser.deserializeQ(u16, in, alloc);
    while (i > 0) : (i -= 1) {
        const run = try ser.deserializeQ(Run(RunValue), in, alloc);
        for (0..run.length) |xi|
            out[run.y][run.x + xi] = (convert_run_value)(run.x, run.y, run.length, run.value);
    }
}

// // Serialize a matrix in its entirety, but only if there's at least one
// // significant value in there.
// pub fn serializeSparseMatrix(
//     // Element of the matrix. E.g. for [][]u8, Elem = u8.
//     comptime Elem: type,

//     // Whether the value in the matrix is important and should be serialized.
//     is_important: *const fn (*const Elem) ?bool,

//     // The type that will be serialized.
//     comptime SerValue: type,

//     // Convert the matrix value to the type to be serialized.
//     extract_value: *const fn (usize, usize, *const Elem) SerValue,

//     // ..
//     comptime height: usize,
//     comptime width: usize,
//     matrix: *const [height][width]Elem,
//     ser: *serde.Serializer,
//     out: anytype,
// ) serde.Error!void {
//     const any_significant = b: for (0..height) |y| {
//         for (0..width) |x|
//             if ((is_important)(&matrix[y][x]))
//                 break :b true;
//     } else false;

//     if (any_significant) {
//         try ser.serializeScalar(u1, 1, out);
//         for (0..height) |y|
//             for (0..width) |x| {
//                 const v = (extract_value)(&matrix[y][x]);
//                 try ser.serializeScalar(SerValue, v, out);
//             };
//     } else {
//         try ser.serializeScalar(u1, 0, out);
//     }
// }
