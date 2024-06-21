const std = @import("std");
const mem = std.mem;
const testing = std.testing;
const math = std.math;
const assert = std.debug.assert;

const fire = @import("fire.zig");
const types = @import("types.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");

const Mob = types.Mob;
const Coord = types.Coord;
const Rect = types.Rect;
const Direction = types.Direction;
const Path = types.Path;
const CoordArrayList = types.CoordArrayList;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

var cache: std.AutoHashMap(Path, Direction) = undefined;

const NodeState = enum { Open, Closed, Unexplored };

const Node = struct {
    parent: ?*Node = null,
    g: usize = 0,
    h: usize = 0,
    state: NodeState = .Unexplored,

    pub inline fn f(n: *const Node) usize {
        return n.g + n.h;
    }

    pub fn betterThan(_: void, a: *Node, b: *Node) math.Order {
        const af = a.f();
        const bf = b.f();
        return if (af < bf) math.Order.lt else if (bf > af) math.Order.gt else math.Order.eq;
    }
};

const NodeArrayList = std.ArrayList(Node);
const NodePriorityQueue = std.PriorityQueue(*Node, void, Node.betterThan);

// Do some pointer stuff to extract x/y coordinates from a node's pointer
// location relative to the matrix start
//
// Thanks to /u/aotdev for pointing this trick out to me
inline fn coordFromPtr(node: *Node, matrix_start: *Node, z: usize) Coord {
    const off = (@ptrToInt(node) - @ptrToInt(matrix_start)) / @sizeOf(Node);
    const x = off % WIDTH;
    const y = off / WIDTH;
    return Coord.new2(z, x, y);
}

// Manhattan: d = dx + dy
inline fn manhattanHeuristic(a: Coord, b: Coord) usize {
    const diff = a.difference(b);
    return diff.x + diff.y;
}

pub fn dummyPenaltyFunc(_: Coord, _: state.IsWalkableOptions) usize {
    return 0;
}

pub fn basePenaltyFunc(coord: Coord, opts: state.IsWalkableOptions) usize {
    var c: usize = 0;

    if (state.dungeon.at(coord).surface) |surface| switch (surface) {
        .Machine => |m| {
            c += m.pathfinding_penalty;
        },
        .Container => |_| c += 30,
        else => {},
    };

    if (state.dungeon.terrainAt(coord).is_path_penalized) {
        c += 50;
    }

    if (opts.mob) |mob| {
        if (mob.ai.flag(.FearsDarkness)) {
            if (!state.dungeon.lightAt(coord).*)
                c += 50;
        }

        if (mob.ai.flag(.FearsLight)) {
            if (state.dungeon.lightAt(coord).*)
                c += 50;
        }

        if (mob.ai.flag(.AvoidsEnemies)) {
            if (utils.getHostileAt(mob, coord)) |_| {
                c += 20;
            } else |_| {}
        }

        if (!fire.fireIsSafeFor(mob, state.dungeon.fireAt(coord).*))
            c += 50;
    }

    return c;
}

pub fn path(
    start: Coord,
    goal: Coord,
    limit: Coord,
    is_walkable: fn (Coord, state.IsWalkableOptions) bool,
    opts: state.IsWalkableOptions,
    penaltyFunc: fn (Coord, state.IsWalkableOptions) usize,
    directions: []const Direction,
    alloc: std.mem.Allocator,
) ?CoordArrayList {
    if (start.z != goal.z) {
        // TODO: add support for pathfinding between levels?
        return null;
    }

    var open_list = NodePriorityQueue.init(alloc, {});
    var nodes: [HEIGHT][WIDTH]Node = [_][WIDTH]Node{[_]Node{.{}} ** WIDTH} ** HEIGHT;

    nodes[start.y][start.x] = Node{
        .g = 0,
        .h = manhattanHeuristic(start, goal),
        .parent = null,
        .state = .Open,
    };
    open_list.add(&nodes[start.y][start.x]) catch unreachable;

    // Shouldn't need this var...
    const goal_rect = goal.asRect();

    // Special handling for multitile creatures
    const mt_l: ?usize = if (opts.mob != null and opts.mob.?.multitile != null) opts.mob.?.multitile.? else null;

    // Special handling for slinking terrors
    const need_walls = opts.mob != null and opts.mob.?.ai.flag(.WallLover) and
        state.dungeon.neighboringWalls(opts.mob.?.coord, true) > 0;

    while (open_list.count() > 0) {
        var current_node: *Node = open_list.remove();
        const cur_coord = coordFromPtr(current_node, &nodes[0][0], start.z);

        if (cur_coord.eq(goal) or
            (mt_l != null and Rect.new(cur_coord, mt_l.?, mt_l.?).intersects(&goal_rect, 1))) // uhg
        {
            open_list.deinit();

            var list = CoordArrayList.init(alloc);
            var current = current_node;
            while (true) {
                const coord = coordFromPtr(current, &nodes[0][0], start.z);
                list.append(coord) catch unreachable;
                if (current.parent) |parent| {
                    current = parent;
                } else break;
            }

            std.mem.reverse(Coord, list.items);
            return list;
        }

        current_node.state = .Closed;

        const neighbors = directions;
        for (neighbors) |neighbor| {
            if (cur_coord.move(neighbor, limit)) |coord| {
                if (nodes[coord.y][coord.x].state == .Closed)
                    continue;

                if (!is_walkable(coord, opts) and !goal.eq(coord))
                    continue;

                if (need_walls and state.dungeon.neighboringWalls(coord, true) == 0 and !goal.eq(coord))
                    continue;

                const cost = (if (neighbor.is_diagonal()) @as(usize, 7) else 5) +
                    (penaltyFunc)(coord, opts);
                const new_g = current_node.g + cost;

                if (nodes[coord.y][coord.x].state == .Open and nodes[coord.y][coord.x].g < new_g)
                    continue;

                const node = Node{
                    .parent = current_node,
                    .g = new_g,
                    .h = manhattanHeuristic(coord, goal),
                    .state = .Open,
                };

                const old_state = nodes[coord.y][coord.x].state;
                nodes[coord.y][coord.x] = node;
                if (old_state != .Open) // not in open list already
                    open_list.add(&nodes[coord.y][coord.x]) catch unreachable;
            }
        }
    }

    open_list.deinit();
    return null;
}

test "coordFromPtr" {
    var nodes: [HEIGHT][WIDTH]Node = [_][WIDTH]Node{[_]Node{.{}} ** WIDTH} ** HEIGHT;
    const begin = &nodes[0][0];
    const z = 0;

    const cases = [_]Coord{
        Coord.new2(z, 0, 0),
        Coord.new2(z, 1, 1),
        Coord.new2(z, 5, 9),
        Coord.new2(z, 15, 20),
    };

    for (&cases) |expected| {
        const got = coordFromPtr(&nodes[expected.y][expected.x], begin, z);
        try testing.expectEqual(expected, got);
    }
}
