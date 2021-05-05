const std = @import("std");
const assert = std.debug.assert;
usingnamespace @import("types.zig");

const state = @import("state.zig");

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

// TODO: make this function a parameter to astar::search()
fn coord_is_walkable(coord: Coord) bool {
    if (state.dungeon[coord.y][coord.x].type == .Wall)
        return false;
    if (state.dungeon[coord.y][coord.x].mob) |_|
        return false;
    return true;
}

fn coord_in_list(coord: Coord, list: *NodeArrayList) ?usize {
    for (list.items) |item, index|
        if (coord.eq(item.coord))
            return index;
    return null;
}

pub fn path(start: Coord, goal: Coord, limit: Coord, alloc: *std.mem.Allocator) ?CoordArrayList {
    if (!coord_is_walkable(goal))
        return null;

    var open_list = NodeArrayList.init(alloc);
    defer open_list.deinit();
    var closed_list = NodeArrayList.init(alloc);
    defer closed_list.deinit();

    // Commented out because the starting position will have the player...
    //assert(coord_is_walkable(start));

    open_list.append(Node{
        .coord = start,
        .g = 0,
        .h = start.distance(goal),
        .parent = null,
    }) catch unreachable;

    while (open_list.items.len != 0) {
        var current_node_index: usize = 0;
        for (open_list.items) |node, index| {
            if (node.f() <= open_list.items[current_node_index].f()) {
                current_node_index = index;
            }
        }

        var current_node = open_list.orderedRemove(current_node_index);
        closed_list.append(current_node) catch unreachable;

        if (current_node.coord.eq(goal)) {
            var list = CoordArrayList.init(alloc);
            var current = current_node;
            while (true) {
                list.append(current.coord) catch unreachable;

                if (current.parent) |parent| {
                    current = if (coord_in_list(parent, &open_list)) |i|
                        open_list.items[i]
                    else if (coord_in_list(parent, &closed_list)) |i|
                        closed_list.items[i]
                    else
                        unreachable;
                } else {
                    break;
                }
            }
            std.mem.reverse(Coord, list.items);
            return list;
        }

        const neighbors = DIRECTIONS;
        for (neighbors) |neighbor| {
            var coord = current_node.coord;
            if (!coord.move(neighbor, limit))
                continue;

            if (!coord_is_walkable(coord))
                continue;

            if (coord_in_list(coord, &closed_list)) |_|
                continue;

            const penalty: usize = if (neighbor.is_diagonal()) 2 else 1;

            const node = Node{
                .coord = coord,
                .parent = current_node.coord,
                .g = current_node.g + 1,
                .h = coord.distance(goal) + penalty,
            };

            if (coord_in_list(coord, &open_list)) |index|
                if (node.g > open_list.items[index].g)
                    continue;

            open_list.append(node) catch unreachable;
        }
    }

    return null;
}
