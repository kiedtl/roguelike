// Originally ripped out of:
// https://github.com/fengb/zigbot9001, main.zig

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const rng = @import("rng.zig");

pub const StringBuf64 = StackBuffer(u8, 64);

pub fn StackBuffer(comptime T: type, comptime capacity: usize) type {
    return struct {
        data: [capacity]T = undefined,
        len: usize = 0,
        capacity: usize = capacity,

        const Self = @This();

        pub fn init(data: ?[]const T) Self {
            if (data) |d| {
                var b: Self = .{ .len = d.len };
                mem.copy(T, &b.data, d);
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
            self.resizeTo(@intCast(usize, fbs.getPos() catch unreachable));
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
            for (self.data[index..newlen]) |*data, j|
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

        pub usingnamespace if (@typeInfo(T) == .Int or @typeInfo(T) == .Enum) struct {
            pub fn linearSearch(self: *const Self, value: T) ?usize {
                return for (self.constSlice()) |item, i| {
                    if (item == value) break i;
                } else null;
            }
        } else if (T == []const u8) struct {
            pub fn linearSearch(self: *const Self, value: T) ?usize {
                return for (self.constSlice()) |item, i| {
                    if (mem.eql(u8, item, value)) break i;
                } else null;
            }
        } else struct {
            pub fn linearSearch(self: *const Self, value: T, eq_fn: fn (a: T, b: T) bool) ?usize {
                return for (self.constSlice()) |item, i| {
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

        pub inline fn last(self: *Self) ?T {
            return if (self.len > 0) self.data[self.len - 1] else null;
        }

        pub inline fn lastPtr(self: *Self) ?*T {
            return if (self.len > 0) &self.data[self.len - 1] else null;
        }
    };
}
