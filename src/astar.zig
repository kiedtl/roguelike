const std = @import("std");
const mem = std.mem;
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
        var membuf: [65535]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

        const directions = path(from, to, limit, is_walkable, &fba.allocator) orelse return null;

        var cur = from;
        for (directions.items) |direction| {
            cache.put(Path{ .from = cur, .to = to }, direction) catch unreachable;
            assert(cur.move(direction, limit));
        }
    }

    return cache.get(pathobj).?;
}

pub fn path(start: Coord, goal: Coord, limit: Coord, is_walkable: fn (Coord) bool, alloc: *std.mem.Allocator) ?DirectionArrayList {
    if (!is_walkable(goal))
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
            var list = DirectionArrayList.init(alloc);
            // var current = current_node;
            // while (true) {
            //     list.append(current.coord) catch unreachable;

            //     if (current.parent) |parent| {
            //         current = if (coord_in_list(parent, &open_list)) |i|
            //             open_list.items[i]
            //         else if (coord_in_list(parent, &closed_list)) |i|
            //             closed_list.items[i]
            //         else
            //             unreachable;
            //     } else {
            //         break;
            //     }
            // }
            var from: Node = undefined;
            var to = current_node;
            while (true) {
                if (to.parent) |parent| {
                    from = to;
                    to = if (coord_in_list(parent, &open_list)) |i|
                        open_list.items[i]
                    else if (coord_in_list(parent, &closed_list)) |i|
                        closed_list.items[i]
                    else
                        unreachable;
                } else {
                    break;
                }

                const d = Direction.from_coords(from.coord, to.coord) catch unreachable;
                list.append(d.opposite()) catch unreachable;
            }
            //std.mem.reverse(Coord, list.items);
            return list;
        }

        const neighbors = DIRECTIONS;
        for (neighbors) |neighbor| {
            var coord = current_node.coord;
            if (!coord.move(neighbor, limit) or !is_walkable(coord)) {
                continue;
            }

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

// ------------------------------- tests ------------------------------------

const expectEqSlice = std.testing.expectEqualSlices;
const expectEq = std.testing.expectEqual;

fn dummy_is_walkable(_: Coord) bool {
    return true;
}

fn _ensure(goal: Coord, expect: []const Direction, al: *mem.Allocator) void {
    const start = Coord.new(0, 0);
    const limit = Coord.new(9, 9);

    const res = path(start, goal, limit, dummy_is_walkable, al).?;
    expectEqSlice(Direction, res.items, expect);
    const res2 = nextDirectionTo(start, goal, limit, dummy_is_walkable).?;
    expectEq(res2, res.items[0]);
    res.deinit();
}

test "basic and cached pathfinding" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(!gpa.deinit());
    const al = &gpa.allocator;

    initCache(al);
    defer deinitCache();

    _ensure(Coord.new(1, 0), &[_]Direction{.East}, al);
    _ensure(Coord.new(2, 3), &[_]Direction{ .SouthEast, .SouthEast, .South }, al);
}
