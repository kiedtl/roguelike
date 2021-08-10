const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

usingnamespace @import("types.zig");
const state = @import("state.zig");

var cache: std.AutoHashMap(Path, Direction) = undefined;

const NodeState = enum { Open, Closed };

const Node = struct {
    coord: Coord,
    parent: ?*Node,
    g: usize,
    h: usize,
    state: NodeState,

    pub inline fn f(n: *const Node) usize {
        return n.g + n.h;
    }

    pub fn betterThan(a: *Node, b: *Node) bool {
        return a.f() < b.f();
    }
};

const NodeArrayList = std.ArrayList(Node);
const NodePriorityQueue = std.PriorityQueue(*Node);

// Manhattan: d = dx + dy
inline fn manhattanHeuristic(a: Coord, b: Coord) usize {
    const diff = a.difference(b);
    return diff.x + diff.y;
}

fn pathfindingPenalty(coord: Coord, opts: state.IsWalkableOptions) usize {
    var c: usize = 0;

    if (state.dungeon.at(coord).surface) |surface| switch (surface) {
        .Machine => |m| c += m.pathfinding_penalty,
        .Container => |_| c += 30,
        .Prop => c += 15,
        else => {},
    };

    if (opts.mob) |mob|
        if (state.dungeon.lightIntensityAt(coord).* < mob.night_vision) {
            c += 10;
        };

    return c;
}

pub fn path(
    start: Coord,
    goal: Coord,
    limit: Coord,
    is_walkable: fn (Coord, state.IsWalkableOptions) bool,
    opts: state.IsWalkableOptions,
    alloc: *std.mem.Allocator,
) ?CoordArrayList {
    if (start.z != goal.z) {
        // TODO: add support for pathfinding between levels
        return null;
    }

    var open_list = NodePriorityQueue.init(alloc, Node.betterThan);
    var nodes: [HEIGHT][WIDTH]?Node = [_][WIDTH]?Node{[_]?Node{null} ** WIDTH} ** HEIGHT;

    nodes[start.y][start.x] = Node{
        .coord = start,
        .g = 0,
        .h = manhattanHeuristic(start, goal),
        .parent = null,
        .state = .Open,
    };
    open_list.add(&nodes[start.y][start.x].?) catch unreachable;

    while (open_list.count() > 0) {
        var current_node: *Node = open_list.remove();

        if (current_node.coord.eq(goal)) {
            open_list.deinit();

            var list = CoordArrayList.init(alloc);
            var current = current_node.*;
            while (true) {
                list.append(current.coord) catch unreachable;
                if (current.parent) |parent| {
                    current = parent.*;
                } else break;
            }

            std.mem.reverse(Coord, list.items);
            return list;
        }

        current_node.state = .Closed;

        const neighbors = DIRECTIONS;
        neighbor: for (neighbors) |neighbor| {
            if (current_node.coord.move(neighbor, state.mapgeometry)) |coord| {
                if (nodes[coord.y][coord.x]) |*other_node|
                    if (other_node.state == .Closed)
                        continue;

                if (!is_walkable(coord, opts) and !goal.eq(coord)) continue;

                const cost = (if (neighbor.is_diagonal()) @as(usize, 7) else 5) +
                    pathfindingPenalty(coord, opts);
                const new_g = current_node.g + cost;

                if (nodes[coord.y][coord.x]) |*other_node|
                    if (other_node.g < new_g)
                        continue;

                const node = Node{
                    .coord = coord,
                    .parent = current_node,
                    .g = new_g,
                    .h = manhattanHeuristic(coord, goal),
                    .state = .Open,
                };

                const in_ol = if (nodes[coord.y][coord.x]) |*on| on.state == .Open else false;
                nodes[coord.y][coord.x] = node;
                if (!in_ol) open_list.add(&nodes[coord.y][coord.x].?) catch unreachable;
            }
        }
    }

    open_list.deinit();
    return null;
}
