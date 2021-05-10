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

pub fn guardWork(mob: *Mob, alloc: *mem.Allocator) void {
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

    // TODO: cache
    var path = astar.path(mob.coord, to, state.mapgeometry, state.is_walkable, alloc).?;
    defer path.deinit();
    const direction = path.pop();

    const prev_facing = mob.facing;

    // TODO: assert that the mob_move() func returns true
    _ = state.mob_move(mob.coord, direction);

    if (prev_facing == mob.facing or prev_facing.is_adjacent(mob.facing)) {}
}
