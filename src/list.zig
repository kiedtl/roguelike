const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const testing = std.testing;

pub fn LinkedList(comptime T: type) type {
    return struct {
        const Self = @This();

        pub const Node = struct {
            prev: ?*Node,
            next: ?*Node,
            data: T,

            pub fn free(self: *Node, allocator: *mem.Allocator) void {
                var slice: []u8 = undefined;
                slice.ptr = @intToPtr([*]u8, @ptrToInt(self));
                slice.len = @sizeOf(Node);
                allocator.free(slice);
            }
        };

        pub const Iterator = struct {
            current: ?*Node,

            fn nextNode(iter: *Iterator) ?*Node {
                const current = iter.current;

                if (current) |c| {
                    iter.current = c.next;
                    return c;
                } else {
                    return null;
                }
            }

            pub fn next(iter: *Iterator) ?T {
                return if (iter.nextNode()) |node| node.data else null;
            }

            pub fn nextPtr(iter: *Iterator) ?*T {
                return if (iter.nextNode()) |node| &node.data else null;
            }
        };

        head: ?*Node,
        tail: ?*Node,
        allocator: *mem.Allocator,

        pub fn init(allocator: *mem.Allocator) Self {
            return Self{
                .head = null,
                .tail = null,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.head == null) {
                return;
            }

            var current = self.head.?;
            while (current.next) |next| {
                current.free(self.allocator);
                current = next;
            }

            current.free(self.allocator);
        }

        pub fn append(self: *Self, data: T) !void {
            var node = try self.allocator.create(Node);
            node.data = data;

            if (self.tail) |tail| {
                assert(tail.next == null);

                node.prev = tail;
                node.next = null;
                tail.next = node;
                self.tail = node;
            } else {
                node.prev = null;
                node.next = null;
                self.head = node;
                self.tail = node;
            }
        }

        pub fn first(self: *Self) ?T {
            return if (self.head) |head| head.data else null;
        }

        pub fn last(self: *Self) ?T {
            return if (self.tail) |tail| tail.data else null;
        }

        pub fn firstPtr(self: *Self) ?*T {
            return if (self.head) |head| &head.data else null;
        }

        pub fn lastPtr(self: *Self) ?*T {
            return if (self.tail) |tail| &tail.data else null;
        }

        pub fn iterator(self: *Self) Iterator {
            return Iterator{ .current = self.head };
        }
    };
}

test "basic LinkedList test" {
    const List = LinkedList(usize);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer testing.expect(!gpa.deinit());

    var list = List.init(&gpa.allocator);
    defer list.deinit();

    const datas = [_]usize{ 5, 21, 623, 1, 36 };
    for (datas) |data| {
        list.append(data) catch unreachable;
        testing.expectEqual(data, list.last().?);
    }

    testing.expectEqual(datas[0], list.first().?);
    testing.expectEqual(datas[0], list.firstPtr().?.*);
    testing.expectEqual(datas[4], list.last().?);
    testing.expectEqual(datas[4], list.lastPtr().?.*);

    var index: usize = 0;
    var iter = list.iterator();
    while (iter.next()) |data| : (index += 1) {
        testing.expectEqual(datas[index], data);
    }
}
