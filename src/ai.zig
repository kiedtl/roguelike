const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const math = std.math;
const meta = std.meta;

const alert = @import("alert.zig");
const colors = @import("colors.zig");
const ui = @import("ui.zig");
const fov = @import("fov.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const err = @import("err.zig");
const utils = @import("utils.zig");
const items = @import("items.zig");
const spells = @import("spells.zig");
const mapgen = @import("mapgen.zig");
const dijkstra = @import("dijkstra.zig");
const buffer = @import("buffer.zig");
const rng = @import("rng.zig");
const types = @import("types.zig");

const Dungeon = types.Dungeon;
const Mob = types.Mob;
const EnemyRecord = types.EnemyRecord;
const SuspiciousTileRecord = types.SuspiciousTileRecord;
const Coord = types.Coord;
const Direction = types.Direction;
const Status = types.Status;

const StackBuffer = buffer.StackBuffer;
const SpellOptions = spells.SpellOptions;

const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// ----------------------------------------------------------------------------

const NOISE_FORGET_AGE = 30;
const NOISE_DONE_CHECKING = 5;

fn flingRandomSpell(me: *Mob, target: *Mob) void {
    const spell = rng.chooseUnweighted(SpellOptions, me.spells);
    spell.spell.use(me, me.coord, target.coord, spell);
}

// Find the nearest enemy.
pub fn currentEnemy(me: *Mob) *EnemyRecord {
    assert(me.ai.phase == .Hunt or me.ai.phase == .Flee);
    assert(me.enemyList().items.len > 0);

    var nearest: usize = 0;
    var nearest_distance: usize = 10000;
    var i: usize = 0;

    while (i < me.enemyList().items.len) : (i += 1) {
        const distance = me.coord.distance(me.enemyList().items[i].lastSeenOrCoord());
        if (distance < nearest_distance) {
            nearest = i;
            nearest_distance = distance;
        }
    }

    const target = &me.enemyList().items[nearest];
    assert(me.isHostileTo(target.mob));

    return target;
}

pub fn calculateMorale(self: *Mob) isize {
    var base: isize = 6;

    // Bonuses depending on self's condition {{{
    if (self.hasStatus(.Enraged)) base += 4;
    if (self.hasStatus(.Fast)) base += 4;
    if (self.hasStatus(.Invigorate)) base += 4;
    // }}}

    // Negative bonuses depending on self's condition {{{
    //
    // XXX: keep neg bonuses here in sync with the positive bonuses below, so
    // that the joy of realizing that enemy is below 50% health can be
    // properly canceled out by the fact that the mob themself is also
    // below 50% health
    //
    if (self.HP < (self.max_HP / 2)) base -= 2;
    if (self.HP < (self.max_HP / 4)) base -= 2;

    if (self.hasStatus(.Blind)) base -= 2;
    if (self.hasStatus(.Debil)) base -= 2;
    if (self.hasStatus(.Daze)) base -= 2;
    if (self.hasStatus(.Disorient)) base -= 2;

    if (self.hasStatus(.Daze)) base -= 2;
    if (self.hasStatus(.Pain)) base -= 2;
    if (self.hasStatus(.Slow)) base -= 2;

    if (self.hasStatus(.Fire) and !self.isFullyResistant(.rFire))
        base -= 6;

    if (self.ai.phase == .Flee) base -= 12;

    if (self.squad != null and self.squad.?.leader.?.ai.phase == .Flee)
        base -= 16;

    if (self.hasStatus(.Fear)) base -= 16;
    // }}}

    // Bonuses/neg bonuses depending on enemy's condition {{{
    for (self.enemyList().items) |enemy_record| {
        const enemy = enemy_record.mob;

        if (enemy.hasStatus(.Intimidating)) base -= 12;

        if (enemy.hasStatus(.Enraged)) base -= 4;
        if (enemy.hasStatus(.Fast)) base -= 4;
        if (enemy.hasStatus(.Invigorate)) base -= 4;

        if (enemy.hasStatus(.Sleeping)) base += 2;
        if (enemy.hasStatus(.Blind)) base += 2;
        if (enemy.hasStatus(.Debil)) base += 2;

        if (enemy.hasStatus(.Disorient) and
            (self.squad != null and self.squad.?.members.len >= 4))
        {
            base += 2;
        }

        if (enemy.hasStatus(.Fear)) base += 4;
        if (enemy.hasStatus(.Daze)) base += 4;
        if (enemy.hasStatus(.Pain)) base += 4;
        if (enemy.hasStatus(.Fire) and !enemy.isFullyResistant(.rFire)) base += 4;
        if (enemy.hasStatus(.Slow)) base += 4;

        // XXX: keep bonuses here in sync with the negative bonuses below, so
        // that the joy of realizing that enemy is below 50% health can be
        // properly canceled out by the fact that the mob themself is also
        // below 50% health
        //
        if (enemy.HP < (enemy.max_HP / 2)) base += 4;
        if (enemy.HP < (enemy.max_HP / 4)) base += 4;

        if (enemy.ai.phase == .Flee) base += 6;

        // Bonus if enemy is paralysed and mob can reach enemy before paralysis
        // runs out
        //
        // FIXME: check to reach enemy is irrelevant if mob isn't a melee brute
        //
        if (enemy.isUnderStatus(.Paralysis)) |para_info| {
            // FIXME: distance check is misleading if enemy is faster than mob
            //    (This won't be true once status .Tmp durations are fixed, and
            //     decrement at the same rate for fast and slow mobs.)
            if (para_info.duration == .Tmp and
                para_info.duration.Tmp > enemy.coord.distance(self.coord))
            {
                base += 8;
            } else {
                base += 4;
            }
        }
    }
    // }}}

    // Bonuses/neg bonuses depending on enemy's condition {{{
    for (self.allies.items) |ally| {
        base += 2;

        if (ally.hasStatus(.Enraged)) base += 4;
        if (ally.hasStatus(.Fast)) base += 4;
        if (ally.hasStatus(.Invigorate)) base += 4;

        if (ally.hasStatus(.Sleeping)) base -= 1;
        if (ally.hasStatus(.Blind)) base -= 2;
        if (ally.hasStatus(.Daze)) base -= 2;
        if (ally.hasStatus(.Debil)) base -= 1;

        if (ally.hasStatus(.Disorient)) base -= 2;

        if (ally.hasStatus(.Fear)) base -= 2;
        if (ally.hasStatus(.Pain)) base -= 2;
        if (ally.hasStatus(.Slow)) base -= 2;

        if (ally.hasStatus(.Fire) and !ally.isFullyResistant(.rFire)) base -= 4;
        if (ally.hasStatus(.Paralysis)) base -= 4;

        if (ally.HP < (ally.max_HP / 2)) base -= 1;
        if (ally.HP < (ally.max_HP / 4)) base -= 2;

        if (ally.ai.phase == .Flee) base -= 2;
    }
    // }}}

    return base;
}

pub fn shouldFlee(me: *Mob) bool {
    if (me.ai.is_fearless or me.life_type != .Living)
        return false;

    return calculateMorale(me) < 0;
}

pub fn isEnemyKnown(mob: *const Mob, enemy: *const Mob) bool {
    return for (mob.enemyListConst().items) |enemyrecord| {
        if (enemyrecord.mob == enemy) break true;
    } else false;
}

pub fn tryRest(mob: *Mob) void {
    if (mob.hasStatus(.Pain)) {
        var directions = DIRECTIONS;
        rng.shuffle(Direction, &directions);
        for (&directions) |direction|
            if (mob.coord.move(direction, state.mapgeometry)) |dest_coord| {
                if (mob.teleportTo(dest_coord, direction, true)) {
                    if (state.player.cansee(mob.coord)) {
                        state.message(.Unimportant, "{c} writhes in agony.", .{mob});
                    }

                    // if (rng.percent(@as(usize, 50))) {
                    //     mob.makeNoise(.Scream, .Louder);
                    // }
                }
            };
    }

    mob.rest();
}

// Notify nearest ally of a hostile.
pub fn alertAllyOfHostile(mob: *Mob) void {
    const hostile = mob.enemyList().items[0];
    for (mob.allies.items) |ally| {
        if (!isEnemyKnown(ally, hostile.mob)) {
            updateEnemyRecord(ally, hostile);
            break;
        }
    }
}

// Use Dijkstra Maps to move away from a coordinate.
// TODO: make it possible to move away from multiple coordinates, i.e. flee from
// multiple enemies
//
pub fn keepDistance(mob: *Mob, from: Coord, distance: usize) bool {
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

        for (mob.enemyList().items) |enemy| {
            const coord = enemy.lastSeenOrCoord();
            flee_dijkmap[coord.y][coord.x] = 0;
        }

        dijkstra.dijkRollUphill(&flee_dijkmap, &DIRECTIONS, &walkability_map);
        dijkstra.dijkMultiplyMap(&flee_dijkmap, -1.25);
        dijkstra.dijkRollUphill(&flee_dijkmap, &DIRECTIONS, &walkability_map);

        var direction: ?Direction = null;
        var lowest_val: f64 = 999;
        const directions: []const Direction = if (mob.isUnderStatus(.Disorient)) |_|
            &CARDINAL_DIRECTIONS
        else
            &DIRECTIONS;
        for (directions) |d| if (mob.coord.move(d, state.mapgeometry)) |neighbor| {
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
        mob.facing = mob.coord.closestDirectionTo(from, state.mapgeometry);
    }

    return moved;
}

// Same as updateEnemyRecord, just better interface
pub fn updateEnemyKnowledge(mob: *Mob, enemy: *Mob, last_seen: ?Coord) void {
    const memory = if (mob.squad != null and mob.squad.?.leader != null)
        mob.squad.?.leader.?.memory_duration
    else
        mob.memory_duration;

    updateEnemyRecord(mob, .{
        .mob = enemy,
        .counter = memory,
        .last_seen = last_seen orelse enemy.coord,
    });
}

pub fn updateEnemyRecord(mob: *Mob, new: EnemyRecord) void {
    // Avoid updating record (and thus printing an animation) if the mob is
    // already dead
    //
    // (this can happen if the mob was attacked via stab, killed, but then
    // fight() is still informing mob of attack)
    if (mob.should_be_dead()) {
        return;
    }

    // Search for an existing record.
    for (mob.enemyList().items) |*enemyrec| {
        if (enemyrec.mob == new.mob) {
            enemyrec.counter = mob.memory_duration;
            enemyrec.last_seen = new.mob.coord;
            return;
        }
    }

    // No existing record, append.
    mob.enemyList().append(new) catch unreachable;

    // Animation
    if (new.mob == state.player and state.player.cansee(mob.coord)) {
        ui.Animation.blinkMob(&.{mob}, '!', colors.AQUAMARINE, .{ .repeat = 2, .delay = 100 });
    }
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

    if (mob.hasStatus(.Amnesia)) {
        mob.ai.phase = .Work;
        return;
    }

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;
        const fitem = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(fitem).mob) |othermob| {
            if (othermob.is_dead) {
                err.bug("Mob {s} is dead but walking around!", .{othermob.displayName()});
            }

            if (othermob == mob) continue;

            if (!othermob.ai.flag(.IgnoredByEnemies) and
                mob.isHostileTo(othermob) and
                (!mob.ai.flag(.IgnoresEnemiesUnknownToLeader) or mob.squad.?.leader.?.cansee(othermob.coord)))
            {
                updateEnemyRecord(mob, .{
                    .mob = othermob,
                    .counter = mob.memory_duration,
                    .last_seen = othermob.coord,
                });
            }
        }
    };

    // Decrement enemy counters. (If we're part of a squad, just let the squad
    // leader do that to avoid every squad member decrementing counters and
    // forgetting about enemy too quickly.)
    //
    // FIXME: iterating over a container with a loop that potentially modifies
    // that container is just begging for trouble.
    //
    var i: usize = 0;
    while (i < mob.enemyList().items.len) {
        const enemy = &mob.enemyList().items[i];

        if (enemy.last_seen) |last_seen| {
            if (mob.cansee(last_seen) and !enemy.mob.coord.eq(last_seen)) {
                enemy.last_seen = null;
            }
        }

        if (enemy.counter == 0 or
            !mob.isHostileTo(enemy.mob) or
            enemy.mob.coord.z != mob.coord.z or
            enemy.mob.ai.flag(.IgnoredByEnemies) or
            (mob.ai.flag(.IgnoresEnemiesUnknownToLeader) and !mob.squad.?.leader.?.cansee(enemy.mob.coord)) or
            enemy.mob.is_dead)
        {
            _ = mob.enemyList().orderedRemove(i);
        } else {
            if (mob.ai.phase != .Flee and mob.isAloneOrLeader() and
                enemy.last_seen == null)
            {
                enemy.counter -= 1;
            }
            i += 1;
        }
    }

    if (mob.ai.is_combative and mob.enemyList().items.len > 0) {
        mob.ai.phase = .Hunt;
    }

    if ((mob.ai.phase == .Hunt or mob.ai.phase == .Flee) and
        mob.enemyList().items.len == 0)
    {
        // No enemies sighted, we're done hunting.
        mob.ai.phase = .Work;
    }
}

// If mob's squad leader is dead, assume leadership.
pub fn checkForLeadership(mob: *Mob) void {
    if (mob.squad) |squad| {
        if (squad.leader.?.is_dead) {
            squad.leader = mob;
        }
    }
}

// Get a list of all nearby allies, visible or not.
pub fn checkForAllies(mob: *Mob) void {
    const vision = mob.stat(.Vision);

    // Reset the ally list.
    mob.allies.shrinkRetainingCapacity(0);

    // We're iterating over FOV because it's the lazy thing to do.
    for (mob.fov) |row, y| for (row) |_, x| {
        const fitem = Coord.new2(mob.coord.z, x, y);

        if (fitem.distance(mob.coord) > vision or
            !fov.quickLOSCheck(mob.coord, fitem, Dungeon.tileOpacity))
        {
            continue;
        }

        if (state.dungeon.at(fitem).mob) |othermob| {
            if (othermob != mob and othermob.allegiance == mob.allegiance) {
                mob.allies.append(othermob) catch err.wat();
            }
        }
    };

    // Sort allies according to distance.
    std.sort.insertionSort(*Mob, mob.allies.items, mob, struct {
        fn f(me: *Mob, a: *Mob, b: *Mob) bool {
            return a.coord.distance(me.coord) > b.coord.distance(me.coord);
        }
    }.f);
}

pub fn checkForNoises(mob: *Mob) void {
    if (!mob.ai.is_curious) {
        return;
    }

    if (mob.hasStatus(.Amnesia)) {
        mob.ai.phase = .Work;
        return;
    }

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(mob.coord.z, x, y);
            if (mob.canHear(coord)) |sound| {
                if (sound.mob_source) |othermob| {
                    // Just because one guard made some noise running over to
                    // the player doesn't mean we want to whole level to
                    // run over and investigate the guard's noise.
                    //
                    if (sound.type == .Movement and !mob.isHostileTo(othermob))
                        continue;

                    if (state.dungeon.at(coord).prison)
                        continue;
                }

                if (utils.findFirstNeedlePtr(mob.sustiles.items, coord, struct {
                    fn f(r: *SuspiciousTileRecord, c: Coord) bool {
                        return c.eq(r.coord);
                    }
                }.f)) |record| {
                    // Reset everything
                    record.age = 0;
                    record.time_stared_at = 0;
                } else {
                    mob.sustiles.append(.{ .coord = coord }) catch err.wat();
                }
            }
        }
    }

    // Increment counters, remove dead ones
    var new_sustiles = std.ArrayList(SuspiciousTileRecord).init(state.GPA.allocator());
    for (mob.sustiles.items) |*record| {
        record.age += 1;

        if ((record.unforgettable or record.age < NOISE_FORGET_AGE) and
            record.time_stared_at < NOISE_DONE_CHECKING)
        {
            new_sustiles.append(record.*) catch err.wat();
        }
    }
    mob.sustiles.deinit();
    mob.sustiles = new_sustiles;

    // Sort coords according to newest sound.
    std.sort.insertionSort(SuspiciousTileRecord, mob.sustiles.items, mob, struct {
        fn f(_: *Mob, a: SuspiciousTileRecord, b: SuspiciousTileRecord) bool {
            // return a.coord.distance(me.coord) > b.coord.distance(me.coord);
            return state.dungeon.soundAt(a.coord).when < state.dungeon.soundAt(b.coord).when;
        }
    }.f);

    // Start investigating or go back to work?
    if (mob.ai.phase == .Work and mob.sustiles.items.len > 0) {
        mob.ai.phase = .Investigate;
    } else if (mob.ai.phase == .Investigate and mob.sustiles.items.len == 0) {
        mob.ai.phase = .Work;
    }
}

pub fn guardGlanceRandom(mob: *Mob) void {
    if (rng.onein(6)) {
        mob.facing = rng.chooseUnweighted(Direction, &DIRECTIONS);
    }
}

pub fn guardGlanceRight(mob: *Mob) void {
    mob.facing = switch (mob.facing) {
        .North => .NorthEast,
        .NorthEast => .East,
        .East => .SouthEast,
        .SouthEast => .South,
        .South => .SouthWest,
        .SouthWest => .West,
        .West => .NorthWest,
        .NorthWest => .North,
    };
}

pub fn guardGlanceAround(mob: *Mob) void {
    if (rng.tenin(15)) return;

    if (rng.boolean()) {
        // Glance right
        mob.facing = switch (mob.facing) {
            .North => .NorthEast,
            .NorthEast => .East,
            .East => .SouthEast,
            .SouthEast => .South,
            .South => .SouthWest,
            .SouthWest => .West,
            .West => .NorthWest,
            .NorthWest => .North,
        };
    } else {
        // Glance left
        mob.facing = switch (mob.facing) {
            .North => .NorthWest,
            .NorthWest => .West,
            .West => .SouthWest,
            .SouthWest => .South,
            .South => .SouthEast,
            .SouthEast => .East,
            .East => .NorthEast,
            .NorthEast => .North,
        };
    }
}

fn guardGlanceLeftRight(mob: *Mob, prev_direction: Direction) void {
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

    mob.facing = newdirection;
}

pub fn coronerWork(mob: *Mob, _: mem.Allocator) void {
    // All done?
    if (mob.ai.work_area.items.len == 0) {
        tryRest(mob);
        guardGlanceAround(mob);
        return;
    }

    const current_task = mob.ai.work_area.items[mob.ai.work_area.items.len - 1];

    if (mob.cansee(current_task)) {
        if (state.dungeon.corpseAt(current_task)) |current_corpse| {
            if (current_corpse.killed_by) |killer| {
                alert.announceEnemyAlert(killer);
            }
            current_corpse.is_death_verified = true;
        }
        _ = mob.ai.work_area.pop();
        tryRest(mob);
    } else if (mob.nextDirectionTo(current_task) == null) {
        _ = mob.ai.work_area.pop();
        tryRest(mob);
    } else {
        mob.tryMoveTo(current_task);
    }
}

pub fn patrolWork(mob: *Mob, _: mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.ai.phase == .Work);

    var to = mob.ai.work_area.items[0];

    if (mob.cansee(to)) {
        // OK, reached our destination. Time to choose another one!
        var tries: usize = 30;
        while (tries > 0) : (tries -= 1) {
            const room = rng.chooseUnweighted(mapgen.Room, state.rooms[mob.coord.z].items);
            const point = room.rect.randomCoord();

            if (state.dungeon.at(point).prison or room.is_vault != null)
                continue;

            if (mob.nextDirectionTo(point)) |_| {
                mob.ai.work_area.items[0] = point;
                break;
            }
        }

        tryRest(mob);
        return;
    }

    const prev_facing = mob.facing;
    mob.tryMoveTo(to);
    guardGlanceLeftRight(mob, prev_facing);
}

pub fn guardWork(mob: *Mob, _: mem.Allocator) void {
    var post = mob.ai.work_area.items[0];

    // Choose a nearby room to watch as well, if we haven't already.
    if (mob.ai.work_area.items.len < 2) {
        const cur_room = switch (state.layout[mob.coord.z][post.y][post.x]) {
            .Unknown => {
                // Give up, don't patrol
                tryRest(mob);
                mob.ai.work_area.append(post) catch unreachable;
                return;
            },
            .Room => |r| state.rooms[mob.coord.z].items[r],
        };

        // Chance to not patrol, or only patrol current room
        if (rng.tenin(25)) {
            tryRest(mob);
            mob.ai.work_area.append(post) catch unreachable;
            return;
        } else if (rng.tenin(15)) {
            var tries: usize = 200;
            var farthest: Coord = post;
            while (tries > 0) : (tries -= 1) {
                const rndcoord = cur_room.rect.randomCoord();
                if (!state.is_walkable(rndcoord, .{ .mob = mob, .right_now = true }) or
                    state.dungeon.at(rndcoord).prison or
                    mob.nextDirectionTo(rndcoord) == null)
                {
                    continue;
                }

                if (rndcoord.distance(post) > farthest.distance(post)) {
                    farthest = rndcoord;
                }
            }

            mob.ai.work_area.append(farthest) catch unreachable;
        } else {
            var nearest: ?mapgen.Room = null;
            var nearest_distance: usize = 99999;
            for (state.rooms[mob.coord.z].items) |room| {
                if (room.rect.start.eq(cur_room.rect.start) or room.type != .Room) {
                    continue;
                }

                const dist = room.rect.start.distance(cur_room.rect.start);
                if (dist < nearest_distance) {
                    nearest = room;
                    nearest_distance = dist;
                }
            }

            // In rare cases, such as the tutorial map, there might be only one
            // room. In that case just rest skip turn.
            //assert(nearest != null);
            if (nearest == null) {
                tryRest(mob);
                return;
            }

            var tries: usize = 500;
            const post2 = while (tries > 0) : (tries -= 1) {
                const rndcoord = nearest.?.rect.randomCoord();
                if (!state.is_walkable(rndcoord, .{ .mob = mob, .right_now = true }) or
                    state.dungeon.at(rndcoord).prison)
                {
                    continue;
                }

                if (mob.nextDirectionTo(rndcoord)) |_| {
                    break rndcoord;
                }
            } else {
                // Give up, don't patrol
                tryRest(mob);
                mob.ai.work_area.append(post) catch unreachable;
                return;
            };

            mob.ai.work_area.append(post2) catch unreachable;
        }
    }

    if (mob.coord.eq(post)) {
        tryRest(mob);

        if (rng.onein(10)) {
            const tmp = mob.ai.work_area.items[0];
            mob.ai.work_area.items[0] = mob.ai.work_area.items[1];
            mob.ai.work_area.items[1] = tmp;
        }

        guardGlanceAround(mob);
    } else {
        // We're not at our post, return there
        const prev_facing = mob.facing;
        mob.tryMoveTo(post);
        guardGlanceLeftRight(mob, prev_facing);
    }
}

pub fn suicideWork(mob: *Mob, _: mem.Allocator) void {
    tryRest(mob);
    mob.HP = 0;
}

pub fn dummyWork(m: *Mob, _: mem.Allocator) void {
    tryRest(m);
}

pub fn standStillAndGuardWork(mob: *Mob, _: mem.Allocator) void {
    const post = mob.ai.work_area.items[0];

    if (mob.coord.eq(post)) {
        tryRest(mob);

        guardGlanceAround(mob);
    } else {
        // We're not at our post, return there
        const prev_facing = mob.facing;
        mob.tryMoveTo(post);
        guardGlanceLeftRight(mob, prev_facing);
    }
}

pub fn combatDummyWork(mob: *Mob, _: mem.Allocator) void {
    guardGlanceRight(mob);
    tryRest(mob);
}

pub fn spireWork(mob: *Mob, _: mem.Allocator) void {
    guardGlanceRight(mob);
    tryRest(mob);

    if (mob.allies.items.len == 0) {
        mob.addStatus(.Sleeping, 0, .Prm);
    }
}

pub fn watcherWork(mob: *Mob, _: mem.Allocator) void {
    const post = mob.ai.work_area.items[0];

    if (mob.coord.eq(post)) {
        tryRest(mob);

        guardGlanceRandom(mob);
    } else {
        const prev_facing = mob.facing;
        mob.tryMoveTo(post);
        guardGlanceLeftRight(mob, prev_facing);
    }
}

pub fn cleanerWork(mob: *Mob, _: mem.Allocator) void {
    switch (mob.ai.work_phase) {
        .CleanerScan => {
            if (mob.ai.work_area.items.len > 0 and
                mob.coord.distance(mob.ai.work_area.items[0]) > 1)
            {
                mob.tryMoveTo(mob.ai.work_area.items[0]);
            } else {
                tryRest(mob);
            }

            for (state.tasks.items) |*task, id|
                if (!task.completed and task.assigned_to == null) {
                    switch (task.type) {
                        .Clean => |_| {
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
                mob.tryMoveTo(target);
            } else {
                tryRest(mob);

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

pub fn haulerWork(mob: *Mob, alloc: mem.Allocator) void {
    switch (mob.ai.work_phase) {
        .HaulerScan => {
            if (mob.ai.work_area.items.len > 0 and
                mob.coord.distance(mob.ai.work_area.items[0]) > 1)
            {
                mob.tryMoveTo(mob.ai.work_area.items[0]);
            } else {
                tryRest(mob);
            }

            for (state.tasks.items) |*task, id|
                if (!task.completed and task.assigned_to == null) {
                    switch (task.type) {
                        .Haul => |_| {
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
                mob.tryMoveTo(itemcoord);
            } else {
                const item = state.dungeon.getItem(itemcoord) catch {
                    // Somehow the item disappeared, resume job-hunting
                    tryRest(mob);
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
                mob.tryMoveTo(dest);
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

pub fn stayNearLeaderWork(mob: *Mob, _: mem.Allocator) void {
    assert(mob.squad != null);
    assert(mob.squad.?.leader != null);

    const leader = mob.squad.?.leader.?;
    assert(!leader.is_dead);

    if (mob.coord.distance(leader.coord) > 1) {
        if (state.nextSpotForMob(leader.coord, mob)) |nearest| {
            // Disabled assertion: it can be the leader's coord, since you could push past it
            //assert(!nearest.eq(leader.coord));

            mob.tryMoveTo(nearest);
        } else tryRest(mob);
    } else {
        tryRest(mob);
    }
}

pub fn bartenderWork(mob: *Mob, _: mem.Allocator) void {
    const post = mob.ai.work_area.items[0];

    if (!mob.coord.eq(post)) {
        // We're not at our post, return there
        mob.tryMoveTo(post);
        return;
    }

    for (mob.allies.items) |ally| {
        if ((ally.isUnderStatus(.Drunk) == null or
            (ally.isUnderStatus(.Drunk).?.duration == .Tmp and
            ally.isUnderStatus(.Drunk).?.duration.Tmp <= 4)) and
            ally.life_type == .Living)
        {
            spells.CAST_BARTENDER_FERMENT.use(mob, mob.coord, ally.coord, .{
                .MP_cost = 0,
                .spell = &spells.CAST_BARTENDER_FERMENT,
                .duration = Status.MAX_DURATION,
            });
            return;
        }
    }

    tryRest(mob);
}

pub fn hulkWork(mob: *Mob, _: mem.Allocator) void {
    switch (rng.range(usize, 0, 99)) {
        00...75 => tryRest(mob),
        76...90 => if (!mob.moveInDirection(rng.chooseUnweighted(Direction, &DIRECTIONS))) tryRest(mob),
        91...99 => mob.tryMoveTo(state.player.coord),
        else => unreachable,
    }
}

pub fn wanderWork(mob: *Mob, _: mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.ai.phase == .Work);

    const station = mob.ai.work_area.items[0];
    const dest = mob.ai.target orelse mob.coord;

    if (mob.coord.eq(dest) or !state.is_walkable(dest, .{ .right_now = true, .mob = mob })) {
        if (rng.tenin(15)) {
            tryRest(mob);
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

            if (!state.is_walkable(point, .{ .right_now = true, .mob = mob }) or
                state.dungeon.at(point).prison)
                continue;

            if (mob.nextDirectionTo(point)) |_| {
                mob.ai.target = point;
                break;
            }
        }

        tryRest(mob);
        return;
    }

    mob.tryMoveTo(dest);
}

// - Get list of prisoners within view.
// - Sort according to distance.
// - Go through list.
//      - Skip ones that are already affected by Fear.
//      - When cast spell, return.
pub fn tortureWork(mob: *Mob, _: mem.Allocator) void {
    const post = mob.ai.work_area.items[0];

    if (!mob.coord.eq(post)) {
        // We're not at our post, return there
        mob.tryMoveTo(post);
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
            .spell = &spells.CAST_PAIN,
            .duration = rng.range(usize, 10, 20),
            .power = 0,
        });
        return;
    }

    tryRest(mob);
}

pub fn ballLightningWorkOrFight(mob: *Mob, _: mem.Allocator) void {
    var walkability_map: [HEIGHT][WIDTH]bool = undefined;
    for (walkability_map) |*row, y| for (row) |*cell, x| {
        const coord = Coord.new2(mob.coord.z, x, y);
        cell.* = state.is_walkable(coord, .{ .mob = mob });
    };

    var conductivity_dijkmap: [HEIGHT][WIDTH]?f64 = undefined;
    for (conductivity_dijkmap) |*row, y| for (row) |*cell, x| {
        const coord = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(coord).mob) |othermob| {
            const rElec = othermob.resistance(.rElec);
            cell.* = switch (rElec) {
                100 => -4,
                125 => -8,
                150 => -16,
                else => 0,
            };
            if (mob.isHostileTo(othermob) and rElec <= 0) {
                cell.* = cell.*.? - 8;
            }
        } else cell.* = null;
    };

    dijkstra.dijkRollUphill(&conductivity_dijkmap, &DIRECTIONS, &walkability_map);

    var direction: ?Direction = null;
    var lowest_val: f64 = 999;
    for (&DIRECTIONS) |d| if (mob.coord.move(d, state.mapgeometry)) |neighbor| {
        if (conductivity_dijkmap[neighbor.y][neighbor.x]) |v| {
            if (v < lowest_val) {
                lowest_val = v;
                direction = d;
            }
        }
    };
    direction = direction orelse rng.chooseUnweighted(Direction, &DIRECTIONS);

    if (!mob.moveInDirection(direction.?)) {
        tryRest(mob);
    }
}

// For combat dummies
pub fn combatDummyFight(mob: *Mob, _: mem.Allocator) void {
    tryRest(mob);
}

// Check if we can evoke anything.
// - Move towards hostile, bapping it if we can.
pub fn meleeFight(mob: *Mob, _: mem.Allocator) void {
    assert(state.dungeon.at(mob.coord).mob != null);

    const target = currentEnemy(mob).mob;

    if (mob.canMelee(target)) {
        _ = mob.fight(target, .{});
    } else if (!mob.immobile) {
        mob.tryMoveTo(target.coord);
    } else {
        tryRest(mob);
    }
}

pub fn watcherFight(mob: *Mob, alloc: mem.Allocator) void {
    const target = currentEnemy(mob).mob;

    mob.makeNoise(.Shout, .Loud);

    if (!mob.cansee(target.coord)) {
        mob.tryMoveTo(target.coord);
    } else {
        if (!keepDistance(mob, target.coord, 8))
            meleeFight(mob, alloc);
    }
}

pub fn shriekerFight(mob: *Mob, alloc: mem.Allocator) void {
    const target = currentEnemy(mob).mob;

    mob.makeNoise(.Shout, .Loud);

    const mob_lit = state.dungeon.lightAt(mob.coord).*;
    const target_lit = state.dungeon.lightAt(target.coord).*;

    if (!mob.cansee(target.coord) and
        // Can't lure me to darker areas!
        (target_lit or !mob_lit))
    {
        mob.tryMoveTo(target.coord);
    } else {
        alertAllyOfHostile(mob);
        if (!keepDistance(mob, target.coord, 8))
            meleeFight(mob, alloc);
    }
}

pub fn coronerFight(mob: *Mob, alloc: mem.Allocator) void {
    const target = currentEnemy(mob).mob;
    alert.announceEnemyAlert(target);
    shriekerFight(mob, alloc);
}

pub fn stalkerFight(mob: *Mob, alloc: mem.Allocator) void {
    const target = currentEnemy(mob).mob;

    if (mob.squad != null and
        mem.eql(u8, mob.squad.?.leader.?.id, "hunter"))
    {
        if (!mob.cansee(target.coord)) {
            mob.tryMoveTo(target.coord);
        } else {
            const dist = @intCast(usize, mob.stat(.Vision) - 1);
            if (!keepDistance(mob, target.coord, dist))
                tryRest(mob);
        }
    } else if (mob.enemyList().items.len == 1) {
        mageFight(mob, alloc);
    } else {
        work(mob, alloc);
    }
}

// - Iterate through enemies. Foreach:
//      - Is it adjacent, or does it have the status bestowed by our projectiles?
//          - No:  Can we throw a projectile at it?
//                  - Yes: Throw net.
//                  - No:  Move towards enemy.
//                    - TODO: try to smartly move into a position where net
//                      can be fired, not brainlessly move towards foe.
//          - Yes: Can we attack the nearest enemy?
//                  - No:  Move towards enemy.
//                  - Yes: Attack.
//
pub fn rangedFight(mob: *Mob, alloc: mem.Allocator) void {
    const target = currentEnemy(mob).mob;

    // if we can't see the enemy, move towards it
    if (!mob.cansee(target.coord))
        mob.tryMoveTo(target.coord);

    // hack to give breathing space to enemy who just got projectile thrown at it
    const spare_enemy_proj = rng.tenin(25);

    const inventory = mob.inventory.pack.constSlice();
    const proj_item: ?usize = for (inventory) |item, id| {
        if (meta.activeTag(item) == .Projectile) break id;
    } else null;
    const proj_status: ?Status = if (proj_item) |i|
        inventory[i].Projectile.effect.Status.status
    else
        null;

    if (target.coord.distance(mob.coord) == 1 or
        spare_enemy_proj or proj_item == null or
        target.isUnderStatus(proj_status.?) != null or
        !utils.hasClearLOF(mob.coord, target.coord))
    {
        // attack
        if (mob.canMelee(target)) {
            _ = mob.fight(target, .{});
        } else {
            mob.tryMoveTo(target.coord);
        }
    } else {
        // fire projectile
        const item = mob.inventory.pack.orderedRemove(proj_item.?) catch err.wat();
        mob.throwItem(&item, target.coord, alloc);
    }
}

fn _isValidTargetForSpell(caster: *Mob, spell: SpellOptions, target: *Mob) bool {
    assert(!target.is_dead);

    if (spell.spell.needs_cardinal_direction_target and
        (target.coord.x != caster.coord.x and target.coord.y != caster.coord.y))
        return false;

    if (spell.spell.needs_visible_target and !caster.cansee(target.coord))
        return false;

    if (spell.spell.cast_type == .Smite) {
        switch (spell.spell.smite_target_type) {
            .UndeadAlly => if (target.life_type != .Undead) return false,
            .SpecificAlly => |id| if (!mem.eql(u8, id, target.id)) return false,
            else => {},
        }
    }

    if (spell.spell.cast_type == .Bolt)
        if (!utils.hasClearLOF(caster.coord, target.coord))
            return false;

    if (meta.activeTag(spell.spell.effect_type) == .Status) {
        if (target.isUnderStatus(spell.spell.effect_type.Status)) |_|
            return false;
    }

    if (spell.spell.check_has_effect) |func| {
        if (!(func)(caster, spell, target.coord))
            return false;
    }

    return true;
}

fn _findValidTargetForSpell(caster: *Mob, spell: SpellOptions) ?Coord {
    if (spell.spell.cast_type == .Smite and
        spell.spell.smite_target_type == .Self)
    {
        if (_isValidTargetForSpell(caster, spell, caster))
            return caster.coord
        else
            return null;
    } else if (spell.spell.cast_type == .Smite and
        spell.spell.smite_target_type == .Corpse)
    {
        return utils.getNearestCorpse(caster);
    } else if (spell.spell.cast_type == .Smite and
        (spell.spell.smite_target_type == .UndeadAlly or spell.spell.smite_target_type == .SpecificAlly))
    {
        return for (caster.allies.items) |ally| {
            if (_isValidTargetForSpell(caster, spell, ally))
                return ally.coord;
        } else null;
    } else {
        return for (caster.enemyList().items) |enemy_record| {
            if (_isValidTargetForSpell(caster, spell, enemy_record.mob))
                return enemy_record.mob.coord;
        } else null;
    }
}

pub fn mageFight(mob: *Mob, alloc: mem.Allocator) void {
    if (mob.ai.flag(.SocialFighter) or mob.ai.flag(.SocialFighter2)) {
        // Check if there's an ally that satisfies the following conditions
        //      - Isn't the current mob
        //      - Isn't another immobile mob
        //      - Is either investigating or attacking
        const found_ally = for (mob.allies.items) |ally| {
            if (ally != mob and !ally.immobile and
                (!mob.ai.flag(.SocialFighter) or ally.ai.phase == .Hunt or ally.ai.phase == .Investigate))
            {
                break true;
            }
        } else false;

        if (!found_ally) {
            tryRest(mob);
            return;
        }
    }

    for (mob.spells) |spell| {
        if (spell.MP_cost > mob.MP) continue;
        if (_findValidTargetForSpell(mob, spell)) |coord| {
            spell.spell.use(mob, mob.coord, coord, spell);
            return;
        }
    }

    switch (mob.ai.spellcaster_backup_action) {
        .Melee => meleeFight(mob, alloc),
        .KeepDistance => if (!mob.immobile) {
            const dist = @intCast(usize, mob.stat(.Vision) -| 1);
            const moved = keepDistance(mob, currentEnemy(mob).mob.coord, dist);
            if (!moved) meleeFight(mob, alloc);
        } else {
            tryRest(mob);
        },
    }
}

pub fn flee(mob: *Mob, alloc: mem.Allocator) void {
    const FLEE_GOAL = 40;

    assert(mob.stat(.Vision) < FLEE_GOAL);

    const target = currentEnemy(mob);

    alertAllyOfHostile(mob);

    if (!keepDistance(mob, target.lastSeenOrCoord(), FLEE_GOAL)) {
        if (mob.canMelee(target.mob)) {
            meleeFight(mob, alloc);
        } else {
            tryRest(mob);
        }
    }

    if (mob.hasStatus(.Fear)) {
        mob.makeNoise(.Scream, .Loud);
    } else {
        if (mob.allegiance == .Necromancer) { // Only shout if dungeon full of frens
            mob.makeNoise(.Shout, .Loud);
        }
    }

    const dist = target.mob.coord.distance(mob.coord);
    if (dist <= mob.stat(.Vision)) {
        // Don't forget about him!
        mob.facing = mob.coord.closestDirectionTo(target.mob.coord, state.mapgeometry);
    } else if (dist >= FLEE_GOAL) {
        // Forget about him
        target.counter = 0;
    }
}

pub fn work(mob: *Mob, alloc: mem.Allocator) void {
    var work_fn = mob.ai.work_fn;
    if (!mob.isAloneOrLeader() and !mob.ai.flag(.ForceNormalWork)) {
        work_fn = stayNearLeaderWork;
    }
    if (mob.hasStatus(.Insane)) {
        work_fn = struct {
            pub fn f(p_mob: *Mob, _: mem.Allocator) void {
                if (!p_mob.moveInDirection(rng.chooseUnweighted(Direction, &DIRECTIONS)))
                    tryRest(p_mob);
            }
        }.f;
    }

    (work_fn)(mob, alloc);
}

pub fn main(mob: *Mob, alloc: mem.Allocator) void {
    checkForLeadership(mob);

    checkForAllies(mob);
    checkForHostiles(mob);
    checkForNoises(mob);

    // Should I wake up?
    if (mob.isUnderStatus(.Sleeping)) |_| {
        switch (mob.ai.phase) {
            .Hunt, .Investigate => mob.cancelStatus(.Sleeping),
            .Work => {
                if ((mob.ai.flag(.AwakesNearAllies) and mob.allies.items.len > 0)) {
                    mob.cancelStatus(.Sleeping);
                } else {
                    tryRest(mob);
                    return;
                }
            },
            .Flee => err.bug("Fleeing mob was put to sleep...?", .{}),
        }
    }

    // Randomly shout if insane
    if (mob.hasStatus(.Insane)) {
        if (rng.onein(10))
            mob.makeNoise(.Shout, .Loud);
    }

    // Should I flee (or stop fleeing?)
    if (mob.ai.phase == .Hunt and shouldFlee(mob)) {
        mob.ai.phase = .Flee;

        if (mob.isUnderStatus(.Exhausted) == null) {
            if (mob.ai.flee_effect) |s| {
                if (mob.isUnderStatus(s.status) == null) {
                    mob.applyStatus(s, .{});
                }
            }
        }
    } else if (mob.ai.phase == .Flee and !shouldFlee(mob)) {
        mob.ai.phase = .Hunt;
    }

    if (mob.ai.phase == .Work) {
        work(mob, alloc);
    } else if (mob.ai.phase == .Investigate) {
        // Even non-curious mobs can investigate, e.g. stalkers sent by player
        //
        // FIXME: 2022-10-21: add this assertion back, as stalkers no longer investigate
        //
        //assert(mob.ai.is_curious);

        assert(mob.sustiles.items.len > 0);

        const target = mob.sustiles.items[mob.sustiles.items.len - 1];

        if (mob.cansee(target.coord)) {
            for (mob.sustiles.items) |*record| {
                if (mob.cansee(record.coord)) {
                    record.time_stared_at += 1;
                }
            }

            guardGlanceAround(mob);

            tryRest(mob);
        } else {
            mob.facing = mob.coord.closestDirectionTo(target.coord, state.mapgeometry);
            mob.tryMoveTo(target.coord);
        }
    } else if (mob.ai.phase == .Hunt) {
        assert(mob.ai.is_combative);
        assert(mob.enemyList().items.len > 0);

        (mob.ai.fight_fn.?)(mob, alloc);

        const target = mob.enemyList().items[0].mob;
        mob.facing = mob.coord.closestDirectionTo(target.coord, state.mapgeometry);
    } else if (mob.ai.phase == .Flee) {
        flee(mob, alloc);
    } else unreachable;
}
