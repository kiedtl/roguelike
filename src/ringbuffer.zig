const std = @import("std");
const testing = std.testing;

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
                if (self.counter == 0) return null;
                const o = self.top;
                self.top = self.rbuf.nextIndex(o);
                self.counter -= 1;
                return self.rbuf.buffer[o];
            }
        };

        pub fn init(self: *Self) void {
            for (self.buffer) |*i| i.* = null;
            self.top = 0;
        }

        pub fn append(self: *Self, item: T) void {
            self.top = self.nextIndex(self.top);
            self.buffer[self.top] = item;
        }

        pub fn current(self: *Self) ?T {
            return self.buffer[self.top];
        }

        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .rbuf = self, .counter = self.len, .top = self.top };
        }

        pub fn nextIndex(self: *const Self, index: usize) usize {
            var n = index +% 1;
            if (n >= self.buffer.len) n = 0;
            return n;
        }
    };
}

test "basic RingBuffer usage" {
    var t = RingBuffer(usize, 4){};

    testing.expectEqual(t.len, 4);

    t.append(1);
    testing.expectEqual(t.current().?, 1);
    t.append(2);
    testing.expectEqual(t.current().?, 2);
    t.append(3);
    testing.expectEqual(t.current().?, 3);
    t.append(4);
    testing.expectEqual(t.current().?, 4);
    t.append(5);
    testing.expectEqual(t.current().?, 5);

    const items = [_]usize{ 5, 2, 3, 4 };
    var ctr: usize = 0;
    var iter = t.iterator();
    while (iter.next()) |item| {
        testing.expectEqual(item, items[ctr]);
        ctr += 1;
    }
}
