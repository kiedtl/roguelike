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

pub fn checkForHostiles(mob: *Mob) void {
    if (!mob.occupation.is_combative)
        return;

    for (mob.fov.items) |fitem| {
        if (state.dungeon.at(fitem).mob) |othermob| {
            if (!othermob.isHostileTo(mob)) continue;

            assert(!othermob.is_dead); // Dead mobs should be corpses (ie items)

            // FIXME: update existing records if necessary.
            mob.enemies.append(.{ .mob = othermob, .counter = mob.memory_duration });
        }
    }

    if (mob.enemies.current() != null)
        mob.occupation.phase = .SawHostile;
}

fn _guard_glance(mob: *Mob, prev_direction: Direction) void {
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

    if (prev_direction == newdirection) {
        // TODO: factor into Direction.oppositeAdjacent
        newdirection = switch (newdirection) {
            .North => .West,
            .East => .North,
            .South => .East,
            .West => .South,
            .NorthEast => .SouthEast,
            .SouthEast => .NorthEast,
            .SouthWest => .NorthWest,
            .NorthWest => .SouthWest,
        };
    }

    _ = mob.gaze(newdirection);
}

pub fn guardWork(mob: *Mob, alloc: *mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.occupation.phase == .Work);

    var from = mob.occupation.work_area.items[0];
    var to = mob.occupation.work_area.items[1];

    if (from.eq(to) and mob.coord.eq(from)) {
        _guard_glance(mob, mob.facing);
        return;
    }

    if (!mob.isCreeping()) {
        _ = mob.rest();
        return;
    }

    // Swap from and to if we've reached the goal, to walk back to the starting point.
    if (!from.eq(to) and mob.coord.eq(to)) {
        const tmp = mob.occupation.work_area.items[0];
        mob.occupation.work_area.items[0] = mob.occupation.work_area.items[1];
        mob.occupation.work_area.items[1] = tmp;

        from = mob.occupation.work_area.items[0];
        to = mob.occupation.work_area.items[1];
    }

    const prev_facing = mob.facing;

    // Walk one step closer to the other end of the guard's patrol route.
    //
    // NOTE: if the guard isn't at their patrol route or station, this has the effect
    // of bringing them one step closer back.
    if (mob.nextDirectionTo(to, state.is_walkable)) |d|
        _ = mob.moveInDirection(d);
    _guard_glance(mob, prev_facing);
}
