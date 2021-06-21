const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

usingnamespace @import("types.zig");
const state = @import("state.zig");

const NodePriorityQueue = std.PriorityQueue(Node);

const Node = struct {
    coord: Coord,
    parent: ?Coord,
    g: usize,
    h: usize,

    pub fn f(n: *const Node) usize {
        return n.g + n.h;
    }

    pub fn betterThan(a: Node, b: Node) bool {
        return a.f() < b.f();
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

pub fn path(start: Coord, goal: Coord, limit: Coord, is_walkable: fn (Coord) bool, alloc: *std.mem.Allocator) ?CoordArrayList {
    if (start.z != goal.z) {
        // TODO: add support for pathfinding between levels
        return null;
    }

    var open_list = NodePriorityQueue.init(alloc, Node.betterThan);
    var closed_list: [HEIGHT][WIDTH]?Node = [_][WIDTH]?Node{[_]?Node{null} ** WIDTH} ** HEIGHT;

    open_list.add(Node{
        .coord = start,
        .g = 0,
        .h = start.distance(goal),
        .parent = null,
    }) catch unreachable;

    while (open_list.count() > 0) {
        var current_node = open_list.remove();

        if (current_node.coord.eq(goal)) {
            open_list.deinit();

            var list = CoordArrayList.init(alloc);
            var current = current_node;
            while (true) {
                list.append(current.coord) catch unreachable;
                if (current.parent) |parent| {
                    current = closed_list[parent.y][parent.x].?;
                } else break;
            }

            std.mem.reverse(Coord, list.items);
            return list;
        }

        closed_list[current_node.coord.y][current_node.coord.x] = current_node;

        const neighbors = DIRECTIONS;
        neighbor: for (neighbors) |neighbor| {
            var coord = current_node.coord;

            if (!coord.move(neighbor, limit)) continue;
            if (!is_walkable(coord) and !goal.eq(coord)) continue;
            if (closed_list[coord.y][coord.x]) |_| continue;

            const node = Node{
                .coord = coord,
                .parent = current_node.coord,
                .g = current_node.g + 1,
                .h = coord.distance(goal),
            };

            var iter = open_list.iterator();
            while (iter.next()) |item| {
                if (item.coord.eq(coord)) {
                    if (node.g > item.g) continue :neighbor;
                    _ = open_list.removeIndex(iter.count - 1);
                }
            }

            open_list.add(node) catch unreachable;
        }
    }

    open_list.deinit();
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
