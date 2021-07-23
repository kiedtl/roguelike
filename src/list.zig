const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const testing = std.testing;

// STYLE: change <name>Ptr to <name>Ref

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

            pub fn nextNode(iter: *Iterator) ?*Node {
                const current = iter.current;
                var result: ?*Node = undefined;

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

        pub fn remove(self: *Self, node: *Node) void {
            if (node.prev) |prevn| prevn.next = node.next;
            if (node.next) |nextn| nextn.prev = node.prev;

            if (self.head == node) self.head = node.next;
            if (self.tail == node) self.tail = node.prev;

            node.free(self.allocator);
        }

        pub fn nth(self: *Self, n: usize) ?T {
            var i: usize = 0;
            var iter = self.iterator();
            while (iter.next()) |item| : (i += 1) {
                if (i == n) {
                    return item;
                }
            }
            return null;
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

        // TODO: allow const iteration
        pub fn iterator(self: *Self) Iterator {
            return Iterator{ .current = self.head };
        }
    };
}

// Use a GPA for tests as then we get an error when there's a memory leak
const GPA = std.heap.GeneralPurposeAllocator(.{});

test "basic LinkedList test" {
    const List = LinkedList(usize);

    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

    var list = List.init(&gpa.allocator);
    defer list.deinit();

    const datas = [_]usize{ 5, 22, 623, 1, 36 };
    for (datas) |data| {
        try list.append(data);
        testing.expectEqual(data, list.last().?);
    }

    testing.expectEqual(datas[0], list.first().?);
    testing.expectEqual(datas[0], list.firstPtr().?.*);
    testing.expectEqual(datas[4], list.last().?);
    testing.expectEqual(datas[4], list.lastPtr().?.*);

    // TODO: separate iterator test into its own test
    var index: usize = 0;
    var iter = list.iterator();
    while (iter.next()) |data| : (index += 1) {
        testing.expectEqual(datas[index], data);
    }

    iter = list.iterator();
    while (iter.nextNode()) |node| {
        if (node.data % 2 == 0)
            list.remove(node);
    }

    testing.expectEqual(list.nth(0), 5);
    testing.expectEqual(list.nth(1), 623);
    testing.expectEqual(list.nth(2), 1);
}

test "basic nth() usage" {
    const List = LinkedList(usize);

    var gpa = GPA{};
    defer testing.expect(!gpa.deinit());

    var list = List.init(&gpa.allocator);
    defer list.deinit();

    try list.append(23);
    try list.append(0);
    try list.append(98);
    try list.append(11);
    try list.append(12);
    try list.append(72);

    testing.expectEqual(list.nth(0), 23);
    testing.expectEqual(list.nth(1), 0);
    testing.expectEqual(list.nth(2), 98);
    testing.expectEqual(list.nth(3), 11);
    testing.expectEqual(list.nth(4), 12);
    testing.expectEqual(list.nth(5), 72);
}
