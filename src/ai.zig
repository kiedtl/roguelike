const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const state = @import("state.zig");
const astar = @import("astar.zig");
usingnamespace @import("types.zig");

fn _find_coord(coord: Coord, array: *CoordArrayList) usize {
    for (array.items) |item, index| {
        if (item.eq(coord))
            return index;
    }
    unreachable;
}

pub fn dummyWork(_: *Mob, __: *mem.Allocator) void {}

pub fn guardWork(_mob: *Mob, alloc: *mem.Allocator) void {
    var mob = _mob;
    assert(state.dungeon[mob.coord.y][mob.coord.x].mob != null);
    assert(mob.occupation.phase == .Work);

    var from = mob.occupation.work_area.items[0];
    var to = mob.occupation.work_area.items[1];

    if (from.eq(to)) {
        return;
    }

    // Swap from and to if we've reached to
    if (mob.coord.eq(to)) {
        const tmp = mob.occupation.work_area.items[0];
        mob.occupation.work_area.items[0] = mob.occupation.work_area.items[1];
        mob.occupation.work_area.items[1] = tmp;

        from = mob.occupation.work_area.items[0];
        to = mob.occupation.work_area.items[1];
    }

    const direction = astar.nextDirectionTo(mob.coord, to, state.mapgeometry, state.is_walkable).?;

    const prev_facing = mob.facing;

    if (state.mob_move(mob.coord, direction)) |newptr|
        mob = newptr;

    var newdirection: Direction = switch (mob.facing) {
        .North => .NorthEast,
        .East => .SouthEast,
        .South => .SouthWest,
        .West => .NorthWest,
        .NorthEast => .East,
        .SouthEast => .South,
        .SouthWest => .West,
        .NorthWest => .North,
    };

    if (prev_facing == newdirection) {
        // TODO: factor into Direction.oppositeAdjacent
        newdirection = switch (newdirection) {
            .North => .NorthWest,
            .East => .NorthEast,
            .South => .SouthEast,
            .West => .SouthWest,
            .NorthEast => .North,
            .SouthEast => .East,
            .SouthWest => .South,
            .NorthWest => .West,
        };
    }

    _ = state.mob_gaze(mob.coord, newdirection);
}
