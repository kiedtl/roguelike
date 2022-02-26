const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const math = std.math;
const meta = std.meta;

const state = @import("state.zig");
const err = @import("err.zig");
const utils = @import("utils.zig");
const items = @import("items.zig");
const spells = @import("spells.zig");
const mapgen = @import("mapgen.zig");
const dijkstra = @import("dijkstra.zig");
const buffer = @import("buffer.zig");
const rng = @import("rng.zig");
usingnamespace @import("types.zig");

const StackBuffer = buffer.StackBuffer;
const SpellInfo = spells.SpellInfo;

fn flingRandomSpell(me: *Mob, target: *Mob) void {
    const spell = rng.chooseUnweighted(SpellInfo, me.spells.slice());
    spell.spell.use(me, me.coord, target.coord, .{
        .status_duration = spell.duration,
        .status_power = spell.power,
    }, null);
}

// Find the nearest enemy.
pub fn currentEnemy(me: *Mob) *EnemyRecord {
    assert(me.ai.phase == .Hunt or me.ai.phase == .Flee);
    assert(me.enemies.items.len > 0);

    var nearest: usize = 0;
    var nearest_distance: usize = 10000;
    var i: usize = 0;

    while (i < me.enemies.items.len) : (i += 1) {
        const distance = me.coord.distance(me.enemies.items[i].last_seen);
        if (distance < nearest_distance) {
            nearest = i;
            nearest_distance = distance;
        }
    }

    return &me.enemies.items[nearest];
}

// Flee if:
//      - mob is at half of health and enemy's HP is ×4 as high as mob's HP
//      - mob's HP is 1/5 of normal and enemy's HP is greater than mob's
//      - mob has .Fear or .Fire status effect
//
// TODO: flee if flanked and there are no allies in sight
pub fn shouldFlee(me: *Mob) bool {
    var result = false;

    const enemy = currentEnemy(me).mob;

    if (me.HP <= (me.max_HP / 2) and enemy.HP > (me.HP * 4))
        result = true;

    if (me.HP <= (me.max_HP / 5) and me.HP < enemy.HP)
        result = true;

    if (me.isUnderStatus(.Fear) != null or me.isUnderStatus(.Fire) != null)
        result = true;

    return result;
}

// Notify nearest ally of a hostile.
pub fn alertAllyOfHostile(mob: *Mob) void {
    const hostile = mob.enemies.items[0];
    if (mob.allies.items.len > 0) {
        updateEnemyRecord(mob.allies.items[0], hostile);
    }
}

// Are we at least <distance> away from mob?
//   - No?
//     - Move away from the hostile.
//
pub fn keepDistance(mob: *Mob, from: Coord, distance: usize) void {
    var moved = false;

    const current_distance = mob.coord.distance(from);

    if (current_distance < distance) {
        var walkability_map: [HEIGHT][WIDTH]bool = undefined;
        for (walkability_map) |*row, y| for (row) |*cell, x| {
            const coord = Coord.new2(mob.coord.z, x, y);
            cell.* = state.is_walkable(coord, .{ .mob = mob });
        };

        var flee_dijkmap: [HEIGHT][WIDTH]?f64 = undefined;
        for (flee_dijkmap) |*row| for (row) |*cell| {
            cell.* = null;
        };

        for (mob.enemies.items) |enemy| {
            const coord = enemy.last_seen;
            flee_dijkmap[coord.y][coord.x] = 0;
        }

        dijkstra.dijkRollUphill(&flee_dijkmap, &DIRECTIONS, &walkability_map);
        dijkstra.dijkMultiplyMap(&flee_dijkmap, -1.25);
        dijkstra.dijkRollUphill(&flee_dijkmap, &DIRECTIONS, &walkability_map);

        var direction: ?Direction = null;
        var lowest_val: f64 = 999;
        for (&DIRECTIONS) |d| if (mob.coord.move(d, state.mapgeometry)) |neighbor| {
            if (flee_dijkmap[neighbor.y][neighbor.x]) |v| {
                if (v < lowest_val) {
                    lowest_val = v;
                    direction = d;
                }
            }
        };

        if (direction) |d| {
            moved = mob.moveInDirection(d);
        } else {
            moved = false;
        }
    } else {
        moved = false;
    }

    if (!moved) {
        _ = mob.rest();
        mob.facing = mob.coord.closestDirectionTo(from, state.mapgeometry);
    }
}

pub fn dummyWork(m: *Mob, _: *mem.Allocator) void {
    _ = m.rest();
}

pub fn updateEnemyRecord(mob: *Mob, new: EnemyRecord) void {
    // Search for an existing record.
    for (mob.enemies.items) |*enemyrec, i| {
        if (enemyrec.mob == new.mob) {
            enemyrec.counter = mob.memory_duration;
            enemyrec.last_seen = new.mob.coord;
            return;
        }
    }

    // No existing record, append.
    mob.enemies.append(new) catch unreachable;
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
// If then mob is an ally, add it to the ally list.
//
pub fn checkForHostiles(mob: *Mob) void {
    assert(!mob.is_dead);

    // Reset the ally list.
    mob.allies.shrinkRetainingCapacity(0);

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;
        const fitem = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(fitem).mob) |othermob| {
            assert(!othermob.is_dead); // Dead mobs should be corpses (ie items)

            if (othermob == mob) continue;

            // Stealth check
            if (rng.range(usize, 0, 100) < othermob.stealth() * 10)
                continue;

            if (othermob.isHostileTo(mob)) {
                updateEnemyRecord(mob, .{
                    .mob = othermob,
                    .counter = mob.memory_duration,
                    .last_seen = othermob.coord,
                });
            } else if (othermob.allegiance == mob.allegiance) {
                mob.allies.append(othermob) catch err.wat();
            }
        }
    };

    // Decrement enemy counters.
    //
    // FIXME: iterating over a container with a loop that potentially modifies
    // that container is just begging for trouble.
    var i: usize = 0;
    while (i < mob.enemies.items.len) {
        const enemy = &mob.enemies.items[i];
        if (enemy.counter == 0 or
            !mob.isHostileTo(enemy.mob) or
            enemy.mob.is_dead)
        {
            _ = mob.enemies.orderedRemove(i);
        } else {
            if (!mob.cansee(enemy.last_seen) and mob.ai.phase != .Flee)
                enemy.counter -= 1;
            i += 1;
        }
    }

    if (mob.ai.is_combative and mob.enemies.items.len > 0) {
        mob.ai.phase = .Hunt;
    }

    if ((mob.ai.phase == .Hunt or mob.ai.phase == .Flee) and
        mob.enemies.items.len == 0)
    {
        // No enemies sighted, we're done hunting.
        mob.ai.phase = .Work;
    }

    // Sort allies/enemies according to distance.
    const _sortFunc = struct {
        fn _sortEnemies(me: *Mob, a: EnemyRecord, b: EnemyRecord) bool {
            return a.mob.coord.distance(me.coord) > b.mob.coord.distance(me.coord);
        }
        fn _sortAllies(me: *Mob, a: *Mob, b: *Mob) bool {
            return a.coord.distance(me.coord) > b.coord.distance(me.coord);
        }
    };
    std.sort.insertionSort(EnemyRecord, mob.enemies.items, mob, _sortFunc._sortEnemies);
    std.sort.insertionSort(*Mob, mob.allies.items, mob, _sortFunc._sortAllies);
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

pub fn patrolWork(mob: *Mob, alloc: *mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.ai.phase == .Work);

    var to = mob.ai.work_area.items[0];

    if (mob.cansee(to)) {
        // OK, reached our destination. Time to choose another one!
        var tries: usize = 30;
        while (tries > 0) : (tries -= 1) {
            const room = rng.chooseUnweighted(mapgen.Room, state.rooms[mob.coord.z].items);
            const point = room.rect.randomCoord();

            if (mob.nextDirectionTo(point)) |_| {
                mob.ai.work_area.items[0] = point;
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

pub fn guardWork(mob: *Mob, alloc: *mem.Allocator) void {
    var post = mob.ai.work_area.items[0];

    if (mob.coord.eq(post)) {
        _ = mob.rest();
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

pub fn watcherWork(mob: *Mob, alloc: *mem.Allocator) void {
    var post = mob.ai.work_area.items[0];

    if (mob.coord.eq(post)) {
        _ = mob.rest();

        if (rng.onein(6)) {
            mob.facing = rng.chooseUnweighted(Direction, &DIRECTIONS);
        }
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
    assert(mob.ai.work_area.items.len == 1);

    const machine_coord = mob.ai.work_area.items[0];
    if (state.dungeon.at(machine_coord).broken) {
        // Oops, our machine disappeared, probably because of an explosion
        _ = mob.rest();
        return;
    }
    const machine = state.dungeon.at(machine_coord).surface.?.Machine;
    assert(!mob.coord.eq(machine_coord)); // Machine should not be walkable

    if (!machine.isPowered() and rng.onein(2)) {
        mob.tryMoveTo(machine_coord);
    } else {
        _ = mob.rest();
    }
}

pub fn cleanerWork(mob: *Mob, _: *mem.Allocator) void {
    switch (mob.ai.work_phase) {
        .CleanerScan => {
            if (mob.ai.work_area.items.len > 0 and
                mob.coord.distance(mob.ai.work_area.items[0]) > 1 and
                mob.isCreeping())
            {
                mob.tryMoveTo(mob.ai.work_area.items[0]);
            } else {
                _ = mob.rest();
            }

            for (state.tasks.items) |*task, id|
                if (!task.completed and task.assigned_to == null) {
                    switch (task.type) {
                        .Clean => |c| {
                            mob.ai.task_id = id;
                            task.assigned_to = mob;
                            mob.ai.work_phase = .CleanerClean;
                            break;
                        },
                        else => {},
                    }
                };
        },
        .CleanerClean => {
            const task = state.tasks.items[mob.ai.task_id.?];
            const target = task.type.Clean;

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

                if (was_clean) {
                    mob.ai.work_phase = .CleanerScan;
                    state.tasks.items[mob.ai.task_id.?].completed = true;
                    mob.ai.task_id = null;
                }
            }
        },
        else => unreachable,
    }
}

pub fn engineerWork(mob: *Mob, _: *mem.Allocator) void {
    switch (mob.ai.work_phase) {
        .EngineerScan => {
            if (mob.ai.work_area.items.len > 0 and
                mob.coord.distance(mob.ai.work_area.items[0]) > 1 and
                mob.isCreeping())
            {
                mob.tryMoveTo(mob.ai.work_area.items[0]);
            } else {
                _ = mob.rest();
            }

            // Sometimes engineers get stuck in never-ending loops of trying
            // to repair a square, noticing that another engineer is on that
            // square, moving away, then coming back to repair that square
            // only to find the other engineer has returned as well.
            //
            // Introduce some randomness to hopefully fix this issue most of the
            // time.
            if (rng.onein(4)) return;

            var closest_task: ?usize = null;
            var closest_task_dist: usize = 999;

            for (state.tasks.items) |*task, id|
                if (!task.completed and task.assigned_to == null) {
                    switch (task.type) {
                        .Repair => |c| if (mob.coord.distance(c) < closest_task_dist) {
                            closest_task = id;
                            closest_task_dist = mob.coord.distance(c);
                        },
                        else => {},
                    }
                };

            if (closest_task) |id| {
                mob.ai.task_id = id;
                state.tasks.items[id].assigned_to = mob;
                mob.ai.work_phase = .EngineerRepair;
            }
        },
        .EngineerRepair => {
            const task = state.tasks.items[mob.ai.task_id.?];
            const target = task.type.Repair;

            if (target.distance(mob.coord) > 1) {
                if (!mob.isCreeping()) {
                    _ = mob.rest();
                } else {
                    mob.tryMoveTo(target);
                }
            } else {
                _ = mob.rest();

                // If there's a mob in the way, just pretend we're finished and
                // move on
                //
                if (state.dungeon.at(target).mob == null) {
                    state.dungeon.at(target).broken = false;
                }

                mob.ai.work_phase = .EngineerScan;
                state.tasks.items[mob.ai.task_id.?].completed = true;
                mob.ai.task_id = null;
            }
        },
        else => unreachable,
    }
}

pub fn haulerWork(mob: *Mob, alloc: *mem.Allocator) void {
    switch (mob.ai.work_phase) {
        .HaulerScan => {
            if (mob.ai.work_area.items.len > 0 and
                mob.coord.distance(mob.ai.work_area.items[0]) > 1 and
                mob.isCreeping())
            {
                mob.tryMoveTo(mob.ai.work_area.items[0]);
            } else {
                _ = mob.rest();
            }

            for (state.tasks.items) |*task, id|
                if (!task.completed and task.assigned_to == null) {
                    switch (task.type) {
                        .Haul => |c| {
                            mob.ai.task_id = id;
                            task.assigned_to = mob;
                            mob.ai.work_phase = .HaulerTake;
                            break;
                        },
                        else => {},
                    }
                };
        },
        .HaulerTake => {
            const task = state.tasks.items[mob.ai.task_id.?];
            const itemcoord = task.type.Haul.from;

            if (itemcoord.distance(mob.coord) > 1) {
                if (!mob.isCreeping()) {
                    _ = mob.rest();
                } else {
                    mob.tryMoveTo(itemcoord);
                }
            } else {
                const item = state.dungeon.getItem(itemcoord) catch |_| {
                    // Somehow the item disappeared, resume job-hunting
                    _ = mob.rest();
                    state.tasks.items[mob.ai.task_id.?].completed = true;
                    mob.ai.task_id = null;
                    mob.ai.work_phase = .HaulerScan;
                    return;
                };
                mob.inventory.pack.append(item) catch unreachable;
                mob.declareAction(.Grab);
                mob.ai.work_phase = .HaulerDrop;
            }
        },
        .HaulerDrop => {
            const task = state.tasks.items[mob.ai.task_id.?];
            const dest = task.type.Haul.to;

            if (dest.distance(mob.coord) > 1) {
                if (!mob.isCreeping()) {
                    _ = mob.rest();
                } else {
                    mob.tryMoveTo(dest);
                }
            } else {
                const item = mob.inventory.pack.pop() catch unreachable;
                if (!mob.dropItem(item, dest)) {
                    // Somehow the item place disappeared, dump the item somewhere.
                    // If there's no place to dump, just let the item disappear :P
                    const spot = state.nextAvailableSpaceForItem(mob.coord, alloc);
                    if (spot) |dst| _ = mob.dropItem(item, dst);
                }

                state.tasks.items[mob.ai.task_id.?].completed = true;
                mob.ai.task_id = null;
                mob.ai.work_phase = .HaulerScan;
            }
        },
        else => unreachable,
    }
}

pub fn wanderWork(mob: *Mob, alloc: *mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.ai.phase == .Work);

    const station = mob.ai.work_area.items[0];
    const dest = mob.ai.target orelse mob.coord;

    if (mob.coord.eq(dest) or !state.is_walkable(dest, .{ .right_now = true })) {
        if (rng.tenin(15)) {
            _ = mob.rest();
            return;
        }

        // OK, reached our destination. Time to choose another one!
        const room_i = switch (state.layout[mob.coord.z][station.y][station.x]) {
            .Unknown => return,
            .Room => |r| r,
        };
        const room = &state.rooms[mob.coord.z].items[room_i];

        var tries: usize = 0;
        while (tries < 5) : (tries += 1) {
            const point = room.rect.randomCoord();

            if (!state.is_walkable(point, .{ .right_now = true }) or
                state.dungeon.at(point).prison)
                continue;

            if (mob.nextDirectionTo(point)) |_| {
                mob.ai.target = point;
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

    mob.tryMoveTo(dest);
}

// - Get list of prisoners within view.
// - Sort according to distance.
// - Go through list.
//      - Skip ones that are already affected by Pain.
//      - When cast spell, return.
pub fn tortureWork(mob: *Mob, alloc: *mem.Allocator) void {
    const post = mob.ai.work_area.items[0];

    if (!mob.coord.eq(post)) {
        // We're not at our post, return there
        if (!mob.isCreeping()) {
            _ = mob.rest();
        } else {
            mob.tryMoveTo(post);
        }
        return;
    }

    const _sortFunc = struct {
        fn _sortWithDistance(me: *Mob, a: *Mob, b: *Mob) bool {
            return a.coord.distance(me.coord) > b.coord.distance(me.coord);
        }
    };

    var prisoners = StackBuffer(*Mob, 32).init(null);

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;
        const fitem = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(fitem).mob) |othermob| {
            if (othermob.prisoner_status != null) prisoners.append(othermob) catch break;
        }
    };

    std.sort.insertionSort(*Mob, prisoners.slice(), mob, _sortFunc._sortWithDistance);

    for (prisoners.constSlice()) |prisoner| {
        if (prisoner.isUnderStatus(.Pain)) |_|
            continue;

        spells.CAST_PAIN.use(mob, mob.coord, prisoner.coord, .{
            .status_duration = 10,
            .status_power = 4,
        }, null);
        return;
    }

    _ = mob.rest();
}

// Check if we can evoke anything.
// - Move towards hostile, bapping it if we can.
pub fn meleeFight(mob: *Mob, alloc: *mem.Allocator) void {
    const target = currentEnemy(mob).mob;
    assert(mob.isHostileTo(target));

    // Check if there's any evocables in our inventory that we can smack.
    //
    // TODO: handle EnemyDebuff/AllyBuff
    //
    // TODO: in the future we want to have a Evocable.willHaveEffect() function
    // that will tell us if there's any used in evoking the evocable.
    // For now though, we'll just evoke it every 10 turns.
    for (mob.inventory.pack.slice()) |item| switch (item) {
        .Evocable => |v| switch (v.purpose) {
            .SelfBuff => if ((state.ticks - v.last_used) > 5 and v.charges > 0) {
                mob.evokeOrRest(v);
                return;
            },
            else => {},
        },
        else => {},
    };

    if (mob.coord.distance(target.coord) == 1) {
        _ = mob.fight(target);
    } else {
        mob.tryMoveTo(target.coord);
    }
}

pub fn watcherFight(mob: *Mob, alloc: *mem.Allocator) void {
    const target = currentEnemy(mob).mob;

    if (!mob.cansee(target.coord)) {
        mob.tryMoveTo(target.coord);
    } else {
        alertAllyOfHostile(mob);
        keepDistance(mob, target.coord, 8);
    }

    mob.makeNoise(.Shout, .Loud);
}

// - Iterate through enemies. Foreach:
//      - Is it .Held?
//          - No:
//              - Can we throw a net at it?
//                  - Yes:
//                    - Action: Throw net.
//                  - No:
//                    - Action: Move towards enemy.
//                    - TODO: try to smartly move into a position where net
//                      can be fired, not brainlessly move towards foe.
// - Can we attack the nearest enemy?
//      - No:
//          - Action: Move towards enemy.
//      - Yes:
//          - Action: Attack.
//
pub fn sentinelFight(mob: *Mob, alloc: *mem.Allocator) void {
    const target = currentEnemy(mob).mob;

    // if we can't see the enemy because it's outside of our range of vision,
    // move towards it
    if (!mob.cansee(target.coord) and mob.coord.distance(target.coord) > mob.vision)
        mob.tryMoveTo(target.coord);

    // hack to give breathing space to enemy who just escaped net
    const spare_enemy_net = rng.tenin(25);

    const net_item: ?usize = for (mob.inventory.pack.constSlice()) |item, id| {
        if (meta.activeTag(item) == .Projectile and
            mem.eql(u8, item.Projectile.id, "net"))
        {
            break id;
        }
    } else null;

    if (target.coord.distance(mob.coord) == 1 or
        target.isUnderStatus(.Held) != null or
        spare_enemy_net or net_item == null or
        !utils.hasClearLOF(mob.coord, target.coord))
    {
        // attack
        if (mob.coord.distance(target.coord) == 1) {
            _ = mob.fight(target);
        } else {
            mob.tryMoveTo(target.coord);
        }
    } else {
        // fire net
        const item = mob.inventory.pack.orderedRemove(net_item.?) catch err.wat();
        const s = mob.throwItem(&item, target.coord, alloc);
        assert(s);
    }
}

pub fn mageFight(mob: *Mob, alloc: *mem.Allocator) void {
    const spell = rng.chooseUnweighted(SpellInfo, mob.spells.slice());

    const spell_status: ?Status = if (std.meta.activeTag(spell.spell.effect_type) == .Status)
        spell.spell.effect_type.Status
    else
        null;

    for (mob.enemies.items) |enemy_record| {
        const enemy = enemy_record.mob;

        // Skip mobs that have already been afflicted, or just
        // skip them according to our tender mercies if we can't
        // tell if they've been cast at last time
        if (spell_status) |status| {
            if (enemy.isUnderStatus(status)) |_|
                continue;
        } else if (rng.onein(3)) {
            continue;
        }

        spell.spell.use(mob, mob.coord, enemy.coord, .{
            .status_duration = 10,
            .status_power = 4,
        }, null);
        return;
    }

    // We didn't find an enemy to cast at, just fling at the first enemy
    flingRandomSpell(mob, currentEnemy(mob).mob);
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
    //      - Is seen by the target
    //      - Is either investigating a noise, or
    //      - Is attacking the hostile mob
    const found_ally = for (mob.allies.items) |ally| {
        if (ally.immobile and target.cansee(ally.coord) and
            ((ally.ai.phase == .Hunt and ally.enemies.items.len > 0) or
            (ally.ai.phase == .Investigate)))
        {
            break true;
        }
    } else false;

    if (found_ally and rng.onein(10)) {
        const spell = mob.spells.data[0];
        spell.spell.use(mob, mob.coord, target.coord, .{
            .status_duration = spell.duration,
            .status_power = spell.power,
        }, "The {0} glitters ominously!");
    } else {
        _ = mob.rest();
    }
}

pub fn flee(mob: *Mob, alloc: *mem.Allocator) void {
    const target = currentEnemy(mob).mob;

    alertAllyOfHostile(mob);
    keepDistance(mob, target.coord, 20);

    mob.makeNoise(.Shout, .Loud);
}
