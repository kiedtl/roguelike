// FIXME: next() should never return starting coord

const std = @import("std");
const mem = std.mem;

usingnamespace @import("types.zig");
const state = @import("state.zig");

const Node = struct {
    c: Coord,
    n: usize,
};
const NodeArrayList = std.ArrayList(Node);

fn coordInList(coord: Coord, list: *NodeArrayList) ?usize {
    for (list.items) |item, index| if (coord.eq(item.c)) return index;
    return null;
}

pub fn dummyIsValid(_: Coord, __: state.IsWalkableOptions) bool {
    return true;
}

pub const Dijkstra = struct {
    center: Coord,
    current: Node,
    max: usize,
    limit: Coord,
    is_valid: fn (Coord, state.IsWalkableOptions) bool,
    is_valid_opts: state.IsWalkableOptions,
    open: NodeArrayList,
    closed: [HEIGHT][WIDTH]?Node = [_][WIDTH]?Node{[_]?Node{null} ** WIDTH} ** HEIGHT,
    skip_current: bool = false,

    const Self = @This();

    pub fn init(
        start: Coord,
        limit: Coord,
        max_distance: usize,
        is_valid: fn (Coord, state.IsWalkableOptions) bool,
        is_valid_opts: state.IsWalkableOptions,
        allocator: *mem.Allocator,
    ) Self {
        const n = Node{ .c = start, .n = 0 };
        var s = Self{
            .center = start,
            .current = n,
            .max = max_distance,
            .limit = limit,
            .is_valid = is_valid,
            .is_valid_opts = is_valid_opts,
            .open = NodeArrayList.init(allocator),
        };
        s.open.append(n) catch unreachable;
        return s;
    }

    pub fn deinit(self: *Self) void {
        self.open.deinit();
    }

    pub fn next(self: *Self) ?Coord {
        if (self.open.items.len == 0) {
            return null;
        }

        self.closed[self.current.c.y][self.current.c.x] = self.current;

        if (self.skip_current) {
            self.skip_current = false;
            self.current = self.open.orderedRemove(0);
            return self.current.c;
        }

        for (&DIRECTIONS) |neighbor| {
            if (self.current.c.move(neighbor, self.limit)) |coord| {
                const new = Node{ .c = coord, .n = self.current.n + 1 };

                if (new.n > self.max) continue;
                if (!self.is_valid(coord, self.is_valid_opts)) continue;
                if (self.closed[coord.y][coord.x] != null) continue;
                if (coordInList(coord, &self.open)) |_| continue;

                self.open.append(new) catch unreachable;
            }
        }

        if (self.open.items.len == 0) {
            return null;
        } else {
            self.current = self.open.orderedRemove(0);
            return self.current.c;
        }
    }

    pub fn skip(self: *Self) void {
        self.skip_current = true;
    }
};
