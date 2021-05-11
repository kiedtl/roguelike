const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

usingnamespace @import("types.zig");
const state = @import("state.zig");

const Path = struct { from: Coord, to: Coord };

const Node = struct {
    coord: Coord,
    parent: ?Coord,
    g: usize,
    h: usize,

    pub fn f(n: *const Node) usize {
        return n.g + n.h;
    }
};

const NodeArrayList = std.ArrayList(Node);

var cache: std.AutoHashMap(Path, Direction) = undefined;

fn coord_in_list(coord: Coord, list: *NodeArrayList) ?usize {
    for (list.items) |item, index|
        if (coord.eq(item.coord))
            return index;
    return null;
}

pub fn initCache(a: *mem.Allocator) void {
    cache = std.AutoHashMap(Path, Direction).init(a);
}

pub fn deinitCache() void {
    cache.clearAndFree();
}

pub fn nextDirectionTo(from: Coord, to: Coord, limit: Coord, is_walkable: fn (Coord) bool) ?Direction {
    const pathobj = Path{ .from = from, .to = to };

    if (!cache.contains(pathobj)) {
        // TODO: do some tests and figure out what's the practical limit to memory
        // usage, and reduce the buffer's size to that.
        var membuf: [65535 * 10]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

        const pth = path(from, to, limit, is_walkable, &fba.allocator) orelse return null;

        var first: Coord = undefined;
        var second = from;

        for (pth.items[1..]) |coord| {
            first = second;
            second = coord;

            const d = Direction.from_coords(first, second) catch unreachable;
            cache.put(Path{ .from = first, .to = to }, d) catch unreachable;
        }

        pth.deinit();
    }

    return cache.get(pathobj).?;
}

pub fn path(start: Coord, goal: Coord, limit: Coord, is_walkable: fn (Coord) bool, alloc: *std.mem.Allocator) ?CoordArrayList {
    var open_list = NodeArrayList.init(alloc);
    var closed_list = NodeArrayList.init(alloc);

    open_list.append(Node{
        .coord = start,
        .g = 0,
        .h = start.distance(goal),
        .parent = null,
    }) catch unreachable;

    while (open_list.items.len > 0) {
        var best: usize = 0;
        for (open_list.items) |node, index| {
            if (node.f() < open_list.items[best].f()) {
                best = index;
            }
        }

        var current_node = open_list.orderedRemove(best);

        if (current_node.coord.eq(goal)) {
            open_list.deinit();

            var list = CoordArrayList.init(alloc);
            var current = current_node;
            while (true) {
                list.append(current.coord) catch unreachable;

                if (current.parent) |parent| {
                    current = if (coord_in_list(parent, &closed_list)) |i|
                        closed_list.items[i]
                    else
                        unreachable;
                } else {
                    break;
                }
            }

            closed_list.deinit();
            std.mem.reverse(Coord, list.items);
            return list;
        }

        closed_list.append(current_node) catch unreachable;

        const neighbors = DIRECTIONS;
        for (neighbors) |neighbor| {
            var coord = current_node.coord;

            if (!coord.move(neighbor, limit)) continue;
            if (!is_walkable(coord) and !goal.eq(coord)) continue;
            if (coord_in_list(coord, &closed_list)) |_| continue;

            const penalty: usize = if (neighbor.is_diagonal()) 14 else 10;

            const node = Node{
                .coord = coord,
                .parent = current_node.coord,
                .g = current_node.g + penalty,
                .h = coord.distance(goal),
            };

            if (coord_in_list(coord, &open_list)) |index| {
                if (node.g > open_list.items[index].g) {
                    continue;
                } else {
                    _ = open_list.orderedRemove(index);
                }
            }

            open_list.append(node) catch unreachable;
        }
    }

    open_list.deinit();
    closed_list.deinit();
    return null;
}

// ------------------------------- tests ------------------------------------

const expectEqSlice = std.testing.expectEqualSlices;
const expectEq = std.testing.expectEqual;

fn dummy_is_walkable(_: Coord) bool {
    return true;
}

test "basic and cached pathfinding" {
    @panic("Tests are broken, TODO: fix");
}
