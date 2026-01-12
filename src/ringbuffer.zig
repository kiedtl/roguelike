const std = @import("std");
const testing = std.testing;

const serde = @import("serde.zig");

// Well, it's something like a ring buffer
pub fn RingBuffer(comptime T: type, size: usize) type {
    return struct {
        len: usize = size,
        buffer: [size]?T = undefined,
        top: usize = 0,
        const Self = @This();

        pub const Iterator = struct {
            rbuf: *const Self,
            counter: usize,
            top: usize,

            pub fn next(self: *Iterator) ?T {
                if (self.counter == self.rbuf.len) return null;
                const o = self.top;
                self.top = self.rbuf.prevIndex(o);
                self.counter += 1;
                return self.rbuf.buffer[o];
            }
        };

        pub fn init(self: *Self) void {
            self.len = size;
            for (&self.buffer) |*i| i.* = null;
            self.top = 0;
        }

        pub fn append(self: *Self, item: T) void {
            self.top = self.nextIndex(self.top);
            self.buffer[self.top] = item;
        }

        pub fn current(self: *const Self) ?T {
            return self.buffer[self.top];
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .rbuf = self, .counter = 0, .top = self.top };
        }

        pub fn nextIndex(self: *const Self, index: usize) usize {
            return if (index == (self.len - 1)) 0 else index + 1;
        }

        pub fn prevIndex(self: *const Self, index: usize) usize {
            return if (index == 0) self.len - 1 else index - 1;
        }

        pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = fmt;
            _ = options;
            try writer.print("rb({}):[", .{value.len});
            for (value.buffer, 0..) |val, i| {
                if (i == value.top) {
                    try writer.print("\x1b[1m", .{});
                }
                try writer.print("{}\x1b[m", .{val});
                if (i != value.len - 1)
                    try writer.print(", ", .{});
            }
            try writer.print("]", .{});
        }

        pub fn serialize(self: *const @This(), ser: *serde.Serializer, out: anytype) !void {
            try ser.serializeScalar(usize, self.top, out);
            for (self.buffer) |item|
                try ser.serialize(?T, &item, out);
        }

        pub fn deserialize(ser: *serde.Deserializer, out: *@This(), in: anytype, alloc: std.mem.Allocator) !void {
            out.init();
            out.top = try ser.deserializeQ(usize, in, alloc);
            for (&out.buffer) |*sl|
                sl.* = try ser.deserializeQ(?T, in, alloc);
        }
    };
}

test "basic RingBuffer usage" {
    var t = RingBuffer(usize, 4){};

    try testing.expectEqual(t.len, 4);

    t.append(1);
    try testing.expectEqual(t.current().?, 1);
    t.append(2);
    try testing.expectEqual(t.current().?, 2);
    t.append(3);
    try testing.expectEqual(t.current().?, 3);
    t.append(4);
    try testing.expectEqual(t.current().?, 4);
    t.append(5);
    try testing.expectEqual(t.current().?, 5);

    const items = [_]usize{ 5, 4, 3, 2 };
    var ctr: usize = 0;
    var iter = t.iterator();
    while (iter.next()) |item| {
        try testing.expectEqual(item, items[ctr]);
        ctr += 1;
    }
    try testing.expectEqual(ctr, items.len);
}
