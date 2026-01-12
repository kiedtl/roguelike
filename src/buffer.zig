// Originally ripped out of:
// https://github.com/fengb/zigbot9001, main.zig

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const rng = @import("rng.zig");
const serde = @import("serde.zig");

pub fn StackBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        len: usize = 0,
        data: [capacity]T = undefined,
        capacity: usize = capacity,

        const Self = @This();

        pub const empty = Self{};

        pub fn init(data: ?[]const T) Self {
            if (data) |d| {
                var b: Self = .{ .len = d.len };
                mem.copyForwards(T, &b.data, d);
                return b;
            } else {
                return .{};
            }
        }

        pub fn initFmt(comptime format: []const u8, args: anytype) Self {
            var b = Self.init(null);
            b.fmt(format, args);
            return b;
        }

        pub fn reinit(self: *Self, data: ?[]const T) void {
            self.clear();
            self.* = Self.init(data);
        }

        pub fn fmt(self: *Self, comptime format: []const u8, args: anytype) void {
            var fbs = std.io.fixedBufferStream(&self.data);
            std.fmt.format(fbs.writer(), format, args) catch unreachable;
            self.resizeTo(@intCast(fbs.getPos() catch unreachable));
        }

        pub fn slice(self: *Self) []T {
            return self.data[0..self.len];
        }

        pub fn constSlice(self: *const Self) []const T {
            return self.data[0..self.len];
        }

        pub fn orderedRemove(self: *Self, index: usize) !T {
            if (self.len == 0 or index >= self.len) {
                return error.IndexOutOfRange;
            }

            const newlen = self.len - 1;
            if (newlen == index) {
                return try self.pop();
            }

            const item = self.data[index];
            for (self.data[index..newlen], 0..) |*data, j|
                data.* = self.data[index + 1 + j];
            self.len = newlen;
            return item;
        }

        pub fn pop(self: *Self) !T {
            if (self.len == 0) return error.IndexOutOfRange;
            self.len -= 1;
            return self.data[self.len];
        }

        pub fn resizeTo(self: *Self, size: usize) void {
            assert(size < self.capacity);
            self.len = size;
        }

        pub fn clear(self: *Self) void {
            self.resizeTo(0);
        }

        pub fn append(self: *Self, item: T) !void {
            if (self.len >= capacity) {
                return error.NoSpaceLeft;
            }

            self.data[self.len] = item;
            self.len += 1;
        }

        pub fn appendSlice(self: *Self, items: []const T) !void {
            for (items) |item| try self.append(item);
        }

        pub fn eq(a: *const Self, b: *const Self) bool {
            if (a.len != b.len)
                return false;
            return for (a.constSlice(), 0..) |first, i| {
                const second = b.data[i];
                if (@typeInfo(T) == .int or
                    @typeInfo(T) == .@"enum" or
                    @typeInfo(T) == .pointer)
                {
                    if (first != second) break false;
                } else if (T == []const u8) {
                    if (!mem.eql(u8, first, second)) break false;
                } else if (@hasDecl(T, "eq")) {
                    if (!first.eq(second)) break false;
                } else {
                    @compileError(@typeName(T) ++ " doesn't define an .eq() method.");
                }
            } else true;
        }

        pub usingnamespace if (@typeInfo(T) == .int or @typeInfo(T) == .@"enum" or @typeInfo(T) == .pointer) struct {
            pub fn linearSearch(self: *const Self, value: T) ?usize {
                return for (self.constSlice(), 0..) |item, i| {
                    if (item == value) break i;
                } else null;
            }
        } else if (T == []const u8) struct {
            pub fn linearSearch(self: *const Self, value: T) ?usize {
                return for (self.constSlice(), 0..) |item, i| {
                    if (mem.eql(u8, item, value)) break i;
                } else null;
            }
        } else struct {
            pub fn linearSearch(self: *const Self, value: T, eq_fn: *const fn (a: T, b: T) bool) ?usize {
                return for (self.constSlice(), 0..) |item, i| {
                    if ((eq_fn)(value, item)) break i;
                } else null;
            }
        };

        pub fn chooseUnweighted(self: *Self) ?T {
            if (self.len == 0) return null;
            return rng.chooseUnweighted(T, self.data[0..self.len]);
        }

        pub inline fn isFull(self: *Self) bool {
            return self.len == self.capacity;
        }

        pub inline fn get(self: *Self, ind: usize) ?T {
            return if (ind >= self.len) null else self.data[ind];
        }

        pub inline fn last(self: *Self) ?T {
            return if (self.len > 0) self.data[self.len - 1] else null;
        }

        pub inline fn lastPtr(self: *Self) ?*T {
            return if (self.len > 0) &self.data[self.len - 1] else null;
        }

        pub fn jsonStringify(val: @This(), stream: anytype) !void {
            //try std.json.stringify(val.constSlice(), .{}, stream);
            try stream.write(val.constSlice());
        }

        pub fn serialize(self: *const @This(), ser: *serde.Serializer, out: anytype) !void {
            try ser.serialize([]const T, &self.constSlice(), out);
        }

        pub fn deserialize(ser: *serde.Deserializer, out: *@This(), in: anytype, alloc: mem.Allocator) !void {
            out.* = @This().init(null);
            var i = try ser.deserializeVarInt(usize, in, alloc);
            while (i > 0) : (i -= 1)
                out.append(try ser.deserializeQ(T, in, alloc)) catch unreachable;
        }
    };
}

test "orderedRemove odd" {
    var buf = StackBuffer(usize, 5).init(&[1]usize{0} ** 5);
    for (buf.slice(), 0..) |*x, i| x.* = i + 1;

    const r = try buf.orderedRemove(0);
    try std.testing.expectEqual(@as(usize, 1), r);

    try std.testing.expectEqual(@as(usize, 4), buf.len);
    try std.testing.expectEqual(@as(usize, 2), buf.data[0]);
    try std.testing.expectEqual(@as(usize, 3), buf.data[1]);
    try std.testing.expectEqual(@as(usize, 4), buf.data[2]);
    try std.testing.expectEqual(@as(usize, 5), buf.data[3]);
}

test "orderedRemove even" {
    var buf = StackBuffer(usize, 4).init(&[1]usize{0} ** 4);
    for (buf.slice(), 0..) |*x, i| x.* = i + 1;

    const r = try buf.orderedRemove(0);
    try std.testing.expectEqual(@as(usize, 1), r);

    try std.testing.expectEqual(@as(usize, 3), buf.len);
    try std.testing.expectEqual(@as(usize, 2), buf.data[0]);
    try std.testing.expectEqual(@as(usize, 3), buf.data[1]);
    try std.testing.expectEqual(@as(usize, 4), buf.data[2]);
}
