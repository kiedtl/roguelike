const std = @import("std");
const mem = std.mem;
const maxInt = std.math.maxInt;
const assert = std.debug.assert;

const serde = @import("../serde.zig");

const Chunk = packed struct {
    continuation: u1,
    value: u7,
};

comptime {
    assert(@sizeOf(Chunk) == @sizeOf(u8));
}

pub const VarIntError = error{VarIntContinuedTooLong};

// Variable-length-encoded unsigned integer.
pub const VarInt = struct {
    value: u64,

    pub fn from(value: u64) VarInt {
        return .{ .value = value };
    }

    pub fn serialize(self: *const VarInt, ser: *serde.Serializer, out: anytype) !void {
        var b = self.value;
        while (true) {
            const raw = b & 0b1111111;
            b >>= 7;
            const val = Chunk{
                .continuation = if (b > 0) 1 else 0,
                .value = @intCast(raw),
            };
            try ser.serializeScalar(u8, @bitCast(val), out);
            if (b == 0)
                break;
        }
    }

    pub fn deserialize(deser: *serde.Deserializer, out: *VarInt, in: anytype, alloc: mem.Allocator) !void {
        out.value = 0;
        for (0..10) |k| {
            const read = try deser.deserializeQ(u8, in, alloc);
            const chunk: Chunk = @bitCast(read);
            out.value |= @as(u64, chunk.value) << @intCast(k * 7);
            if (chunk.continuation == 0)
                return;
        }
        return error.VarIntContinuedTooLong;
    }
};

const Tester = serde.Tester;
const testing = std.testing;

test "varint_serde" {
    const Case = struct {
        value: u64,
        expect_length: usize,

        pub fn n(v: u64, l: usize) @This() {
            return .{ .value = v, .expect_length = l };
        }
    };

    // zig fmt: off
    const CASES = &[_]Case{
        Case.n(0, 1),     Case.n(12, 1),     Case.n(127, 1),
        Case.n(128, 2),   Case.n(16383, 2),
        Case.n(16384, 3), Case.n(27347, 3),
        Case.n(maxInt(u32), 5),
        Case.n(maxInt(u64), 10),
    };
    // zig fmt: on

    for (CASES) |case| {
        var tester = try Tester(VarInt).new(VarInt.from(case.value));
        defer tester.deinit();

        try tester.serialize();
        try tester.deserialize();

        if (tester.written != case.expect_length) {
            std.debug.print("Value {} should've taken {} bytes to serialize; took {} instead.", .{
                case.value, case.expect_length, tester.written,
            });
            return error.WrittenTooMuch;
        }

        try testing.expectEqual(tester.d_ser.value, tester.d_deser.value);
    }
}
