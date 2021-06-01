const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const state = @import("state.zig");
const astar = @import("astar.zig");
const rng = @import("rng.zig");
usingnamespace @import("types.zig");

fn _find_coord(coord: Coord, array: *CoordArrayList) usize {
    for (array.items) |item, index| {
        if (item.eq(coord))
            return index;
    }
    unreachable;
}

pub fn dummyWork(_: *Mob, __: *mem.Allocator) void {}

// For every enemy in the mob's FOV, create an "enemy record" with a pointer to
// that mob and a counter. Set the counter to the mob's memory_duration.
//
// On every turn, if that enemy is *still* in FOV, reset the counter to the
// maximum value; otherwise, decrement the counter. If the counter is zero, the
// enemy record is deleted and the mob "forgets" that there was an enemy.
//
// Thus, a mob will "remember" that an enemy was around for a maximum of
// memory_duration turns after the enemy leaves FOV. While the mob remembers, it
// will be able to track down the enemy with -perfect accuracy (though this
// might be changed later).
//
// This approach was stolen from Cogmind:
// https://old.reddit.com/r/roguelikedev/comments/57dnqk/faq_friday_49_awareness_systems/d8r1ztp/
//
pub fn checkForHostiles(mob: *Mob) void {
    if (!mob.occupation.is_combative)
        return;

    vigilance: for (mob.fov.items) |fitem| {
        if (state.dungeon.at(fitem).mob) |othermob| {
            if (!othermob.isHostileTo(mob)) continue;

            assert(!othermob.is_dead); // Dead mobs should be corpses (ie items)

            // Search for an existing record.
            for (mob.enemies.items) |*enemy, i| {
                if (@ptrToInt(enemy.mob) == @ptrToInt(othermob)) {
                    enemy.counter = mob.memory_duration;
                    continue :vigilance;
                }
            }

            // No existing record, append.
            mob.enemies.append(.{
                .mob = othermob,
                .counter = mob.memory_duration,
            }) catch unreachable;
        }

        // Check for a dead enemy and drop that record.
        if (state.dungeon.at(fitem).item) |item| {
            switch (item) {
                .Corpse => |corpse| {
                    for (mob.enemies.items) |*enemy, i| {
                        if (@ptrToInt(enemy.mob) == @ptrToInt(corpse))
                            _ = mob.enemies.orderedRemove(i);
                    }
                },
            }
        }
    }

    // Decrement counters.
    for (mob.enemies.items) |*enemy, i| {
        if (enemy.counter == 0) {
            _ = mob.enemies.orderedRemove(i);
        } else {
            enemy.counter -= 1;
        }
    }

    if (mob.enemies.items.len > 0) {
        mob.occupation.phase = .SawHostile;
    } else {
        mob.occupation.phase = .Work;
    }
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

    var to = mob.occupation.work_area.items[0];

    if (mob.coord.distance(to) < 3) {
        // OK, reached our destination. Time to choose another one!
        while (true) {
            const room = rng.chooseUnweighted(Room, state.dungeon.rooms[mob.coord.z].items);
            const point = room.randomCoord();

            if (mob.nextDirectionTo(point, state.is_walkable)) |_| {
                mob.occupation.work_area.items[0] = point;
                break;
            }
        }
        return;
    }

    if (!mob.isCreeping()) {
        _ = mob.rest();
        return;
    }

    const prev_facing = mob.facing;

    if (mob.nextDirectionTo(to, state.is_walkable)) |d|
        _ = mob.moveInDirection(d);
    _guard_glance(mob, prev_facing);
}

pub fn keeperWork(mob: *Mob, alloc: *mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.occupation.phase == .Work);

    var post = mob.occupation.work_area.items[0];

    if (mob.coord.eq(post)) {
        _guard_glance(mob, mob.facing);
        return;
    } else {
        // We're not at our post, return there
        if (!mob.isCreeping()) {
            _ = mob.rest();
            return;
        }

        const prev_facing = mob.facing;

        if (mob.nextDirectionTo(post, state.is_walkable)) |d|
            _ = mob.moveInDirection(d);
        _guard_glance(mob, prev_facing);
    }
}
