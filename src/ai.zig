const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const state = @import("state.zig");
const spells = @import("spells.zig");
const dijkstra = @import("dijkstra.zig");
const astar = @import("astar.zig");
const rng = @import("rng.zig");
usingnamespace @import("types.zig");

fn currentEnemy(me: *Mob) *EnemyRecord {
    assert(me.occupation.phase == .SawHostile or me.occupation.phase == .Flee);
    assert(me.enemies.items.len > 0);

    return &me.enemies.items[me.enemies.items.len - 1];
}

fn _find_coord(coord: Coord, array: *CoordArrayList) usize {
    for (array.items) |item, index| {
        if (item.eq(coord))
            return index;
    }
    unreachable;
}

pub fn dummyWork(m: *Mob, _: *mem.Allocator) void {
    _ = m.rest();
}

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
    assert(!mob.is_dead);

    if (!mob.occupation.is_combative)
        return;

    vigilance: for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;

        const fitem = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(fitem).mob) |othermob| {
            if (!othermob.isHostileTo(mob)) continue;

            assert(!othermob.is_dead); // Dead mobs should be corpses (ie items)

            // Search for an existing record.
            for (mob.enemies.items) |*enemy, i| {
                if (@ptrToInt(enemy.mob) == @ptrToInt(othermob)) {
                    enemy.counter = mob.memory_duration;
                    enemy.last_seen = othermob.coord;
                    continue :vigilance;
                }
            }

            // No existing record, append.
            mob.enemies.append(.{
                .mob = othermob,
                .counter = mob.memory_duration,
                .last_seen = othermob.coord,
            }) catch unreachable;
        }
    };

    // Decrement counters.
    //
    // FIXME: iterating over a container with a loop that potentially modifies
    // that container is just begging for trouble.
    var i: usize = 0;
    while (i < mob.enemies.items.len) {
        const enemy = &mob.enemies.items[i];
        if (enemy.counter == 0 or enemy.mob.is_dead) {
            _ = mob.enemies.orderedRemove(i);
        } else {
            if (!mob.cansee(enemy.last_seen))
                enemy.counter -= 1;
            i += 1;
        }
    }

    if (mob.enemies.items.len > 0) {
        mob.occupation.phase = .SawHostile;
    }

    if ((mob.occupation.phase == .SawHostile or mob.occupation.phase == .Flee) and
        mob.enemies.items.len == 0)
    {
        // No enemies sighted, we're done hunting.
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

    if (mob.cansee(to)) {
        // OK, reached our destination. Time to choose another one!
        while (true) {
            const room = rng.chooseUnweighted(Room, state.dungeon.rooms[mob.coord.z].items);
            const point = room.randomCoord();

            if (mob.nextDirectionTo(point)) |_| {
                mob.occupation.work_area.items[0] = point;
                break;
            }
        }

        _ = mob.rest();
        return;
    }

    if (!mob.isCreeping()) {
        _ = mob.rest();
        return;
    }

    const prev_facing = mob.facing;
    mob.tryMoveTo(to);
    _guard_glance(mob, prev_facing);
}

pub fn watcherWork(mob: *Mob, alloc: *mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.occupation.phase == .Work);

    var post = mob.occupation.work_area.items[0];

    if (mob.coord.eq(post)) {
        _ = mob.rest();
        return;
    } else {
        // We're not at our post, return there
        if (!mob.isCreeping()) {
            _ = mob.rest();
            return;
        }

        const prev_facing = mob.facing;
        mob.tryMoveTo(post);
        _guard_glance(mob, prev_facing);
    }
}

pub fn interactionLaborerWork(mob: *Mob, _: *mem.Allocator) void {
    assert(mob.occupation.work_area.items.len == 1);

    const machine = mob.occupation.work_area.items[0];
    assert(!mob.coord.eq(machine)); // Machine should not be walkable, right?

    mob.tryMoveTo(machine);
}

pub fn cleanerWork(mob: *Mob, _: *mem.Allocator) void {
    switch (mob.occupation.work_phase) {
        .CleanerScan => {
            _ = mob.rest();

            var y: usize = 0;
            while (y < HEIGHT) : (y += 1) {
                var x: usize = 0;
                while (x < WIDTH) : (x += 1) {
                    const coord = Coord.new2(mob.coord.z, x, y);
                    var clean = true;

                    var spattering = state.dungeon.at(coord).spatter.iterator();
                    while (spattering.next()) |entry| {
                        const num = entry.value.*;
                        if (entry.value.* > 0) {
                            clean = false;
                            break;
                        }
                    }

                    if (!clean) {
                        mob.occupation.target = coord;
                        mob.occupation.work_phase = .CleanerClean;
                        break;
                    }
                }
            }
        },
        .CleanerClean => {
            const target = mob.occupation.target.?;
            if (target.distance(mob.coord) > 1) {
                if (!mob.isCreeping()) {
                    _ = mob.rest();
                } else {
                    mob.tryMoveTo(target);
                }
            } else {
                _ = mob.rest();

                var was_clean = true;
                var spattering = state.dungeon.at(target).spatter.iterator();

                while (spattering.next()) |entry| {
                    const spatter = entry.key;
                    const num = entry.value.*;
                    if (num > 0) {
                        was_clean = false;
                        state.dungeon.at(target).spatter.set(spatter, num - 1);
                    }
                }

                if (was_clean)
                    mob.occupation.work_phase = .CleanerScan;
            }
        },
        .CleanerIdle => {
            _ = mob.rest();

            if (rng.onein(2))
                mob.occupation.work_phase = .CleanerScan;
        },
    }
}

pub fn wanderWork(mob: *Mob, alloc: *mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.occupation.phase == .Work);

    var to = mob.occupation.work_area.items[0];

    if (mob.cansee(to) or !state.is_walkable(to, .{ .right_now = true })) {
        // OK, reached our destination. Time to choose another one!
        const map = Room{
            .start = Coord.new2(mob.coord.z, 1, 1),
            .width = WIDTH - 1,
            .height = HEIGHT - 1,
        };

        var tries: usize = 0;
        while (tries < 50) : (tries += 1) {
            const point = map.randomCoord();

            if (!state.is_walkable(point, .{ .right_now = true })) continue;

            if (mob.nextDirectionTo(point)) |_| {
                mob.occupation.work_area.items[0] = point;
                break;
            }
        }

        _ = mob.rest();
        return;
    }

    if (!mob.isCreeping()) {
        _ = mob.rest();
        return;
    }

    mob.tryMoveTo(to);
}

pub fn goofingAroundWork(mob: *Mob, alloc: *mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.occupation.phase == .Work);

    var to = mob.occupation.work_area.items[0];

    if (mob.coord.eq(to) or !state.is_walkable(to, .{ .right_now = true })) {
        // OK, reached our destination. Time to choose another one!
        const room_i = switch (state.layout[mob.coord.z][mob.coord.y][mob.coord.x]) {
            .Unknown => return,
            .Room => |r| r,
        };
        const room = &state.dungeon.rooms[mob.coord.z].items[room_i];

        var tries: usize = 0;
        while (tries < 10) : (tries += 1) {
            const point = room.randomCoord();

            if (!state.is_walkable(point, .{ .right_now = true })) continue;

            if (mob.nextDirectionTo(point)) |_| {
                mob.occupation.work_area.items[0] = point;
                break;
            }
        }

        _ = mob.rest();
        return;
    }

    if (!mob.isCreeping()) {
        _ = mob.rest();
        return;
    }

    mob.tryMoveTo(to);
}

// - Move towards hostile, bapping it if we can.
pub fn meleeFight(mob: *Mob, alloc: *mem.Allocator) void {
    const target = currentEnemy(mob).mob;
    if (mob.coord.distance(target.coord) == 1) {
        _ = mob.fight(target);
    } else {
        mob.tryMoveTo(target.coord);
    }
}

// - Are there allies within view?
//    - Yes: are they attacking the hostile?
//        - Yes: paralyze the hostile
pub fn statueFight(mob: *Mob, alloc: *mem.Allocator) void {
    assert(mob.spells.len > 0);

    const target = currentEnemy(mob).mob;

    if (!target.cansee(mob.coord)) {
        _ = mob.rest();
        return;
    }

    // Check if there's an ally that satisfies the following conditions
    //      - Isn't the current mob
    //      - Isn't another immobile mob
    //      - Is either investigating a noise, or
    //      - Is attacking the hostile mob
    var ally = false;
    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;
        const fitem = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(fitem).mob) |othermob| {
            const phase = othermob.occupation.phase;

            if (@ptrToInt(othermob) != @ptrToInt(mob) and
                !othermob.immobile and
                othermob.allegiance == mob.allegiance and
                ((phase == .SawHostile and
                othermob.enemies.items.len > 0 and // mob's phase may not have been reset yet
                othermob.enemies.items[0].mob.coord.eq(target.coord)) or
                (phase == .GoTo)))
            {
                ally = true;
                break;
            }
        }
    };

    if (ally and rng.onein(4)) {
        const spell = mob.spells.data[0];
        spell.spell.use(mob, target.coord, .{
            .status_duration = spell.duration,
            .status_power = spell.power,
        }, "The {0} glitters at you!");
    } else {
        _ = mob.rest();
    }
}

// - Can we see the hostile?
//      - No:
//          - Move towards the hostile.
//      - Yes?
//          - Are we at least PREFERRED_DISTANCE away from mob?
//              - No?
//                  - Move away from the hostile.
//          - Shout!
//
pub fn flee(mob: *Mob, alloc: *mem.Allocator) void {
    const PREFERRED_DISTANCE: usize = 4;

    const target = currentEnemy(mob).mob;

    if (!mob.cansee(target.coord)) {
        mob.tryMoveTo(target.coord);
        return;
    }

    const current_distance = mob.coord.distance(target.coord);

    if (current_distance < PREFERRED_DISTANCE) {
        var flee_to: ?Coord = null;
        var emerg_flee_to: ?Coord = null;

        // Find next space to flee to.
        var dijk = dijkstra.Dijkstra.init(
            mob.coord,
            state.mapgeometry,
            PREFERRED_DISTANCE,
            state.is_walkable,
            .{},
            alloc,
        );
        defer dijk.deinit();
        while (dijk.next()) |coord| {
            if (coord.distance(target.coord) <= current_distance)
                continue;

            if (mob.nextDirectionTo(coord) == null)
                continue;

            const walls = state.dungeon.neighboringWalls(coord, true);

            if (walls > 2) {
                if (walls < 4) {
                    emerg_flee_to = coord;
                }
                continue;
            }

            flee_to = coord;
            break;
        }

        var moved = false;
        if (flee_to orelse emerg_flee_to) |dst| {
            const oldd = mob.facing;
            moved = mob.moveInDirection(mob.nextDirectionTo(dst).?);
            mob.facing = oldd;
        }

        if (!moved) {
            if (mob.coord.distance(target.coord) == 1) {
                mob.fight(target);
            } else {
                _ = mob.rest();
            }
        }

        mob.makeNoise(Mob.NOISE_YELL);
    } else {
        _ = mob.rest();
        mob.makeNoise(Mob.NOISE_YELL);
    }
}
