// FIXME: next() should never return starting coord

const std = @import("std");
const mem = std.mem;

usingnamespace @import("types.zig");
const state = @import("state.zig");

const NodeState = enum { Open, Closed };
const Node = struct {
    c: Coord,
    n: usize,
    state: NodeState = .Open,
};
const NodeArrayList = std.ArrayList(Node);

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
    nodes: [HEIGHT][WIDTH]?Node = [_][WIDTH]?Node{[_]?Node{null} ** WIDTH} ** HEIGHT,
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
        s.nodes[start.y][start.x] = n;
        s.open.append(s.nodes[start.y][start.x].?) catch unreachable;
        return s;
    }

    pub fn deinit(self: *Self) void {
        self.open.deinit();
    }

    pub fn next(self: *Self) ?Coord {
        if (self.open.items.len == 0) {
            return null;
        }

        self.nodes[self.current.c.y][self.current.c.x].?.state = .Closed;

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

                var in_ol = false;

                if (self.nodes[coord.y][coord.x]) |oldnode| switch (oldnode.state) {
                    .Open => if (oldnode.n < new.n) {
                        continue;
                    } else {
                        in_ol = true;
                    },
                    .Closed => continue,
                };

                self.nodes[coord.y][coord.x] = new;
                if (!in_ol)
                    self.open.append(self.nodes[coord.y][coord.x].?) catch unreachable;
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
