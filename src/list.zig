const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const testing = std.testing;

const serializer = @import("serializer.zig");
// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;

// Basic node that can be used for scalar data.
pub fn ScalarNode(comptime T: type) type {
    return struct {
        const Self = @This();

        __prev: ?*Self = null,
        __next: ?*Self = null,
        data: T,
    };
}

pub fn LinkedList(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => {},
        else => @compileError("Expected struct, got '" ++ @typeName(T) ++ "'"),
    }

    if (!@hasField(T, "__next"))
        @compileError("Struct '" ++ @typeName(T) ++ "' does not have a '__next' field");
    if (!@hasField(T, "__prev"))
        @compileError("Struct '" ++ @typeName(T) ++ "' does not have a '__prev' field");

    return struct {
        const Self = @This();

        pub const Iterator = struct {
            current: ?*T,
            reverse: bool = false,

            pub fn next(iter: *Iterator) ?*T {
                const current = iter.current;

                if (current) |c| {
                    if (iter.reverse) {
                        iter.current = c.__prev;
                    } else {
                        iter.current = c.__next;
                    }
                    return c;
                } else {
                    return null;
                }
            }
        };

        head: ?*T,
        tail: ?*T,
        allocator: mem.Allocator,

        pub const ChildType = T;

        pub fn init(allocator: mem.Allocator) Self {
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
            while (current.__next) |next| {
                self.allocator.destroy(current);
                current = next;
            }

            self.allocator.destroy(current);
        }

        // Make a copy of data and allocate it on the heap, then append to the
        // list.
        pub fn append(self: *Self, data: T) !void {
            var node = try self.allocator.create(T);
            node.* = data;

            if (self.tail) |tail| {
                assert(tail.__next == null);

                node.__prev = tail;
                node.__next = null;
                tail.__next = node;
                self.tail = node;
            } else {
                node.__prev = null;
                node.__next = null;
                self.head = node;
                self.tail = node;
            }
        }

        pub fn appendAndReturn(self: *Self, data: T) !*T {
            try self.append(data);
            return self.last() orelse @panic("/dev/sda is on fire");
        }

        pub fn remove(self: *Self, node: *T) void {
            if (node.__prev) |prevn| prevn.__next = node.__next;
            if (node.__next) |nextn| nextn.__prev = node.__prev;

            if (self.head == node) self.head = node.__next;
            if (self.tail == node) self.tail = node.__prev;

            self.allocator.destroy(node);
        }

        pub fn nth(self: *Self, n: usize) ?*T {
            var i: usize = 0;
            var iter = self.iterator();
            while (iter.next()) |item| : (i += 1) {
                if (i == n) {
                    return item;
                }
            }
            return null;
        }

        pub fn first(self: *Self) ?*T {
            return if (self.head) |head| head else null;
        }

        pub fn last(self: *Self) ?*T {
            return if (self.tail) |tail| tail else null;
        }

        // TODO: allow const iteration
        pub fn iterator(self: *const Self) Iterator {
            return Iterator{ .current = self.head };
        }

        // TODO: allow const iteration
        pub fn iteratorReverse(self: *const Self) Iterator {
            return Iterator{ .current = self.tail, .reverse = true };
        }

        pub fn len(self: *const Self) usize {
            var iter = self.iterator();
            var i: usize = 0;
            while (iter.next()) |_| i += 1;
            return i;
        }

        pub fn serialize(self: *const @This(), ser: *serializer.Serializer, out: anytype) !void {
            var iter = self.iterator();
            var i: usize = 0;
            while (iter.next()) |_| i += 1;
            try ser.serializeScalar(usize, i, out);

            iter = self.iterator();
            while (iter.next()) |item| try ser.serialize(T, item, out);
        }

        pub fn deserialize(ser: *serializer.Serializer, out: *@This(), in: anytype, alloc: mem.Allocator) !void {
            //out.* = @This().init(alloc);
            const neededlen = try ser.deserializeQ(usize, in, alloc);
            std.log.info("len: {}", .{neededlen});

            if (neededlen > out.len()) {
                var i = out.len();
                while (i < neededlen) : (i += 1) try out.append(undefined);
            }

            var i: usize = 0;
            while (i < neededlen) : (i += 1) {
                try ser.deserialize(T, out.nth(i).?, in, alloc);
            }
        }

        // Deserialization stuff
        pub const __SER_PointerDataIter = struct {
            i: Iterator,
            c: usize = 0,

            pub fn new(of: *const Self) __SER_PointerDataIter {
                return __SER_PointerDataIter{
                    .i = Iterator{ .current = of.head },
                    .c = 0,
                };
            }

            pub fn next(self: *@This()) ?serializer.PointerData2 {
                if (self.i.next()) |item| {
                    self.c += 1;
                    return .{ .ptr = @intFromPtr(item), .ind = self.c - 1, .ptrtype = @typeName(*T) };
                } else {
                    return null;
                }
            }
        };
    };
}

test "basic LinkedList test" {
    const Node = ScalarNode(usize);
    const List = LinkedList(Node);

    var list = List.init(testing.allocator);
    defer list.deinit();

    const datas = [_]usize{ 5, 22, 623, 1, 36 };
    for (datas) |data| {
        try list.append(Node{ .data = data });
        try testing.expectEqual(data, list.last().?.data);
    }

    try testing.expectEqual(datas[0], list.first().?.data);
    try testing.expectEqual(datas[4], list.last().?.data);

    // TODO: separate iterator test into its own test
    var index: usize = 0;
    var iter = list.iterator();
    while (iter.next()) |node| : (index += 1) {
        try testing.expectEqual(datas[index], node.data);
    }

    iter = list.iterator();
    while (iter.next()) |node| {
        if (node.data % 2 == 0)
            list.remove(node);
    }

    try testing.expectEqual(list.nth(0).?.data, 5);
    try testing.expectEqual(list.nth(1).?.data, 623);
    try testing.expectEqual(list.nth(2).?.data, 1);
}

test "LinkedList reverse iterator" {
    const Node = ScalarNode(usize);
    var list = LinkedList(Node).init(testing.allocator);
    defer list.deinit();

    try list.append(Node{ .data = 0 });
    try list.append(Node{ .data = 1 });
    try list.append(Node{ .data = 2 });
    try list.append(Node{ .data = 3 });
    try list.append(Node{ .data = 4 });

    const data = [_]usize{ 4, 3, 2, 1, 0 };
    var i: usize = 0;
    var iter = list.iteratorReverse();
    while (iter.next()) |number| : (i += 1)
        try testing.expectEqual(number.data, data[i]);

    try testing.expectEqual(i, data.len);
}

test "basic nth() usage" {
    const Node = ScalarNode(usize);
    const List = LinkedList(Node);

    var list = List.init(testing.allocator);
    defer list.deinit();

    try list.append(Node{ .data = 23 });
    try list.append(Node{ .data = 0 });
    try list.append(Node{ .data = 98 });
    try list.append(Node{ .data = 11 });
    try list.append(Node{ .data = 12 });
    try list.append(Node{ .data = 72 });

    try testing.expectEqual(list.nth(0).?.data, 23);
    try testing.expectEqual(list.nth(1).?.data, 0);
    try testing.expectEqual(list.nth(2).?.data, 98);
    try testing.expectEqual(list.nth(3).?.data, 11);
    try testing.expectEqual(list.nth(4).?.data, 12);
    try testing.expectEqual(list.nth(5).?.data, 72);
}
