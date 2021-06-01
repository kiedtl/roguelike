const std = @import("std");
const mem = std.mem;

usingnamespace @import("types.zig");

const Node = struct {
    c: Coord,
    n: usize,
};
const NodeArrayList = std.ArrayList(Node);

fn coordInList(coord: Coord, list: *NodeArrayList) ?usize {
    for (list.items) |item, index| if (coord.eq(item.c)) return index;
    return null;
}

pub const Dijkstra = struct {
    center: Coord,
    current: Node,
    max: usize,
    limit: Coord,
    is_valid: fn (Coord) bool,
    open: NodeArrayList,
    closed: NodeArrayList,

    const Self = @This();

    pub fn init(c: Coord, l: Coord, m: usize, f: fn (Coord) bool, a: *mem.Allocator) Self {
        const n = Node{ .c = c, .n = 0 };
        var s = Self{
            .center = c,
            .current = n,
            .max = m,
            .limit = l,
            .is_valid = f,
            .open = NodeArrayList.init(a),
            .closed = NodeArrayList.init(a),
        };
        s.open.append(n) catch unreachable;
        return s;
    }

    pub fn deinit(self: *Self) void {
        self.open.deinit();
        self.closed.deinit();
    }

    pub fn next(self: *Self) ?Coord {
        if (self.open.items.len == 0) {
            return null;
        }

        self.closed.append(self.current) catch unreachable;

        const neighbors = DIRECTIONS;
        for (neighbors) |neighbor| {
            var coord = self.current;
            coord.n += 1;

            if (!coord.c.move(neighbor, self.limit)) continue;
            if (coord.n > self.max) continue;
            if (!self.is_valid(coord.c)) continue;
            if (coordInList(coord.c, &self.closed)) |_| continue;
            if (coordInList(coord.c, &self.open)) |_| continue;

            self.open.append(coord) catch unreachable;
        }

        self.current = self.open.pop();
        return self.current.c;
    }
};
