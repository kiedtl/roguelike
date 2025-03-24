const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const math = std.math;
const meta = std.meta;

const alert = @import("alert.zig");
const astar = @import("astar.zig");
const buffer = @import("buffer.zig");
const colors = @import("colors.zig");
const combat = @import("combat.zig");
const dijkstra = @import("dijkstra.zig");
const err = @import("err.zig");
const fov = @import("fov.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const mapgen = @import("mapgen.zig");
const mobs = @import("mobs.zig");
const rng = @import("rng.zig");
const spells = @import("spells.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const tasks = @import("tasks.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const AIJob = types.AIJob;
const CoordArrayList = types.CoordArrayList;
const Coord = types.Coord;
const Direction = types.Direction;
const Dungeon = types.Dungeon;
const EnemyRecord = types.EnemyRecord;
const minmax = types.minmax;
const Mob = types.Mob;
const Status = types.Status;
const SuspiciousTileRecord = types.SuspiciousTileRecord;

const StackBuffer = buffer.StackBuffer;
const SpellOptions = spells.SpellOptions;

const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// ----------------------------------------------------------------------------

pub const caverns = @import("ai/caverns.zig");

// ----------------------------------------------------------------------------

const NOISE_FORGET_AGE = 30;
const NOISE_DONE_CHECKING = 5;

fn flingRandomSpell(me: *Mob, target: *Mob) void {
    const spell = rng.chooseUnweighted(SpellOptions, me.spells);
    spell.spell.use(me, me.coord, target.coord, spell);
}

// Find the nearest enemy.
pub fn _getClosestEnemy(me: *Mob, require_visible: bool) *EnemyRecord {
    assert(me.ai.phase == .Hunt or me.ai.phase == .Flee);
    assert(me.enemyList().items.len > 0);

    var nearest: usize = 0;
    var nearest_distance: usize = 10000;
    var i: usize = 0;

    while (i < me.enemyList().items.len) : (i += 1) {
        const enemy = me.enemyList().items[i];
        const distance = me.distance2(enemy.lastSeenOrCoord());
        if (require_visible and !me.canSeeMob(enemy.mob)) continue;
        if (distance < nearest_distance) {
            nearest = i;
            nearest_distance = distance;
        }
    }

    const target = &me.enemyList().items[nearest];
    assert(me.isHostileTo(target.mob));

    return target;
}

pub fn closestEnemy(me: *Mob) *EnemyRecord {
    return _getClosestEnemy(me, false);
}

pub fn closestVisibleEnemy(me: *Mob) *EnemyRecord {
    return _getClosestEnemy(me, true);
}

pub fn calculateMorale(self: *Mob) isize {
    var base: isize = 5;

    // Bonuses depending on self's condition {{{
    if (self.hasStatus(.Enraged)) base += 12;
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
    if (self.HP < (self.max_HP / 2)) base -= 3;
    if (self.HP < (self.max_HP / 4) or self.HP == 1) base -= 3;

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

        if (self.ai.flag(.Coward) and enemy_record.attacked_me) base -= 10;

        if (enemy.hasStatus(.Intimidating)) base -= 10;

        if (enemy.hasStatus(.Enraged)) base -= 3;
        if (enemy.hasStatus(.Fast)) base -= 3;
        if (enemy.hasStatus(.Invigorate)) base -= 3;

        if (enemy.hasStatus(.Sleeping)) base += 2;
        if (enemy.hasStatus(.Blind)) base += 2;
        if (enemy.hasStatus(.Debil)) base += 2;

        // If enemy is disoriented and we can surround, good
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
        if (enemy.HP < (enemy.max_HP / 2)) base += 2;
        if (enemy.HP < (enemy.max_HP / 4)) base += 3;

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

    // Bonuses/neg bonuses depending on ally's condition {{{
    for (self.allies.items) |ally| {
        if (ally.ai.flag(.NoRaiseAllyMorale))
            continue;

        base += 1;

        if (ally.hasStatus(.Enraged)) base += 4;
        if (ally.hasStatus(.Fast)) base += 4;
        if (ally.hasStatus(.Invigorate)) base += 4;

        if (ally.HP < (ally.max_HP / 2)) base -= 1;
        if (ally.HP < (ally.max_HP / 4) or ally.HP == 1) base -= 2;

        // Doesn't make sense to subtract morale here, because a sleeping ally
        // is just as good as a regular one.
        //
        //if (ally.hasStatus(.Sleeping)) base -= 1;

        if (ally.hasStatus(.Blind)) base -= 2;
        if (ally.hasStatus(.Daze)) base -= 2;
        if (ally.hasStatus(.Debil)) base -= 1;

        if (ally.hasStatus(.Disorient)) base -= 2;

        if (ally.hasStatus(.Fear)) base -= 2;
        if (ally.hasStatus(.Pain)) base -= 2;
        if (ally.hasStatus(.Slow)) base -= 2;

        if (ally.hasStatus(.Fire) and !ally.isFullyResistant(.rFire)) base -= 4;
        if (ally.hasStatus(.Paralysis)) base -= 4;

        // "Ohno what have they done to my friend ?!??"
        if (ally.hasStatus(.Insane)) base -= 4;

        // Should be higher for realism, but then causes morale cascades easily
        if (ally.ai.phase == .Flee) base -= 2;
    }
    // }}}

    return base;
}

pub fn shouldFlee(me: *Mob) bool {
    if (me.ai.is_fearless or me.life_type != .Living) {
        assert(!me.bflee_flag);
        return false;
    }

    return me.bflee_flag or me.morale < 0;
}

pub fn shouldCallForReinforcements(mob: *Mob) bool {
    assert(!mob.bflee_flag);
    assert(mob.ai.phase == .Flee);

    if (!mob.ai.is_combative or mob.faction != .Necromancer or
        mob.life_type != .Living or !mob.isAloneOrLeader() or
        mob.hasStatus(.Insane))
    {
        return false;
    }

    var fleeing_allies: usize = 0;
    for (mob.allies.items) |ally| {
        if (ally.ai.is_combative and ally.ai.phase == .Flee and
            // Just added this condition here to prevent the hypothetical
            // situation of a snowballing group of guards running to staircase,
            // and in process making everyone else flee to staircase as well.
            //
            // Not sure if it's effective or desirable to prevent this, or if this
            // would even happen.
            //
            !ally.bflee_flag)
        {
            fleeing_allies += 1;
        }
    }

    return fleeing_allies >= 4;
}

pub fn isEnemyKnown(mob: *const Mob, enemy: *const Mob) bool {
    return for (mob.enemyListConst().items) |enemyrecord| {
        if (enemyrecord.mob == enemy) break true;
    } else false;
}

pub fn beginFlee(mob: *Mob) void {
    assert(mob.ai.phase != .Flee);
    mob.ai.phase = .Flee;
    for (mob.enemyList().items) |*enemy| {
        enemy.counter = mob.memory_duration * 2;
        enemy.last_seen = null;
    }
    mob.bflee_flag = false;

    if (mob.isUnderStatus(.Exhausted) == null) {
        if (mob.ai.flee_effect) |s| {
            if (mob.isUnderStatus(s.status) == null) {
                mob.applyStatus(s, .{});
            }
        }
    }
}

pub fn endFlee(mob: *Mob) void {
    assert(mob.ai.phase == .Flee);
    mob.ai.phase = .Hunt;
    for (mob.enemyList().items) |*enemy| {
        enemy.counter = mob.memory_duration;
    }
}

pub fn tryRest(mob: *Mob) void {
    if (mob.hasStatus(.Pain)) {
        var directions = DIRECTIONS;
        rng.shuffle(Direction, &directions);
        for (&directions) |direction|
            if (mob.coord.move(direction, state.mapgeometry)) |dest_coord| {
                if (mob.teleportTo(dest_coord, direction, true, false)) {
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
    const hostile = &mob.enemyList().items[0];
    for (mob.allies.items) |ally| {
        if (!isEnemyKnown(ally, hostile.mob)) {
            updateEnemyKnowledge(ally, hostile.mob, hostile.last_seen);
            hostile.alerted_allies += 1;
            break;
        }
    }
}

// Use Dijkstra Maps to move away from a coordinate.
// TODO: make it possible to move away from multiple coordinates, i.e. flee from
// multiple enemies
//
pub fn runAwayFromEnemies(mob: *Mob, min_dist: usize) bool {
    var moved = false;
    const closest_enemy = closestVisibleEnemy(mob).lastSeenOrCoord();

    if (mob.distance2(closest_enemy) < min_dist) {
        var walkability_map: [HEIGHT][WIDTH]bool = undefined;
        for (&walkability_map, 0..) |*row, y| for (row, 0..) |*cell, x| {
            const coord = Coord.new2(mob.coord.z, x, y);
            cell.* = state.is_walkable(coord, .{ .mob = mob });
        };

        var flee_dijkmap = [1][WIDTH]?f64{[1]?f64{null} ** WIDTH} ** HEIGHT;

        for (mob.enemyList().items) |enemy| {
            // Only run away from visible enemies.
            const coord = enemy.last_seen orelse continue;
            flee_dijkmap[coord.y][coord.x] = 0;
        }

        dijkstra.dijkRollUphill(&flee_dijkmap, &DIRECTIONS, &walkability_map);
        dijkstra.dijkMultiplyMap(&flee_dijkmap, -1.25);
        dijkstra.dijkRollUphill(&flee_dijkmap, &DIRECTIONS, &walkability_map);

        var direction: ?Direction = null;
        var lowest_val: f64 = 99999;
        const directions: []const Direction = if (mob.isUnderStatus(.Disorient)) |_|
            &DIAGONAL_DIRECTIONS
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
        mob.facing = mob.coord.closestDirectionTo(closest_enemy, state.mapgeometry);
    }

    return moved;
}

// Same as updateEnemyRecord, just better interface
pub fn updateEnemyKnowledge(mob: *Mob, enemy: *Mob, last_seen: ?Coord) void {
    const mob_or_leader = mob.selfOrLeader();
    var memory = mob_or_leader.memory_duration;
    if (mob_or_leader.ai.phase == .Flee)
        memory *= 2;

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

    assert(!new.mob.is_dead);

    // Search for an existing record.
    for (mob.enemyList().items) |*enemyrec| {
        if (enemyrec.mob == new.mob) {
            enemyrec.counter = new.counter;
            enemyrec.last_seen = new.mob.coord;
            return;
        }
    }

    // No existing record, append.
    var bnew = new;
    bnew.request_help_when_finish = false;
    mob.enemyList().append(bnew) catch unreachable;

    // Remove any sustiles related to this enemy
    //
    // Both to avoid unnecessary investigation and prevent redundant threat reporting
    while (true) {
        var completed = true;
        for (mob.sustiles.items, 0..) |susrecord, i|
            if (susrecord.sound) |s| if (s.mob_source) |src| if (src == new.mob) {
                completed = false;
                _ = mob.sustiles.orderedRemove(i);
                break;
            };
        if (completed) break;
    }

    // Animation
    if (new.mob == state.player and state.player.cansee(mob.coord)) {
        ui.Animation.blinkMob(&.{mob}, '!', colors.AQUAMARINE, .{ .repeat = 2, .delay = 100 });
    }
}

pub fn checkForCorpses(mob: *Mob) void {
    if (mob.hasStatus(.Insane) or !mob.ai.flag(.ScansForCorpses) or
        // Don't queue scan corpse jobs if we're heading for the stairs,
        // because then we're in Big Panic and don't have time to mourn our
        // dead...
        //
        // Real reason is because flee code expects the "Leave floor" job to
        // be the current job, and we shouldn't be adding more jobs in that
        // state.
        (mob.ai.phase == .Flee and mob.bflee_flag))
    {
        return;
    }

    tasks.scanForCorpses(mob);
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

    if (mob.hasStatus(.Amnesia) and mob.ai.phase != .Flee) {
        mob.ai.phase = .Work;
        return;
    }

    const has_nonundead_ally = for (mob.allies.items) |ally| {
        if (ally.life_type != .Undead) break true;
    } else false;

    for (mob.fov, 0..) |row, y| for (row, 0..) |cell, x| {
        if (cell == 0) continue;
        const fitem = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(fitem).mob) |othermob| if (mob != othermob and mob.canSeeMob(othermob)) {
            if (othermob.is_dead) {
                err.bug("Mob {s} is dead but walking around!", .{othermob.displayName()});
            }

            if (!othermob.ai.flag(.IgnoredByEnemies) and
                mob.isHostileTo(othermob) and
                (!mob.ai.flag(.IgnoresEnemiesUnknownToLeader) or mob.squad.?.leader.?.cansee(othermob.coord)) and
                !(othermob.hasStatus(.RingDeception) and !has_nonundead_ally))
            {
                updateEnemyKnowledge(mob, othermob, othermob.coord);
            }
        };
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

        if (enemy.counter == 0 or !mob.isHostileTo(enemy.mob) or
            enemy.mob.coord.z != mob.coord.z or
            enemy.mob.ai.flag(.IgnoredByEnemies) or
            (mob.ai.flag(.IgnoresEnemiesUnknownToLeader) and
                !mob.squad.?.leader.?.cansee(enemy.mob.coord)) or
            (enemy.mob.hasStatus(.RingDeception) and !has_nonundead_ally) or
            enemy.mob.is_dead)
        {
            const e = mob.enemyList().orderedRemove(i);
            e.reportMajorThreat(mob);
        } else if (enemy.mob.faction == .Night and
            mob.nextDirectionTo(enemy.mob.coordMT(mob.coord)) == null)
        {
            const e = mob.enemyList().orderedRemove(i);
            e.reportMajorThreat(mob);
        } else {
            if (mob.isAloneOrLeader() and
                (enemy.last_seen == null or mob.ai.phase == .Flee) and
                (mob.life_type != .Undead or !enemy.mob.hasStatus(.Corruption)))
            {
                enemy.counter -= 1;
            }
            i += 1;
        }
    }

    if (mob.ai.is_combative and mob.enemyList().items.len > 0 and mob.ai.phase != .Flee) {
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
    for (mob.fov, 0..) |row, y| for (row, 0..) |_, x| {
        const fitem = Coord.new2(mob.coord.z, x, y);
        if (fitem.distance(mob.coord) > vision) continue;

        if (state.dungeon.at(fitem).mob) |othermob| {
            if (othermob != mob and othermob.faction == mob.faction and
                fov.quickLOSCheck(mob.coord, fitem, Dungeon.tileOpacity))
            {
                mob.allies.append(othermob) catch err.wat();
            }
        }
    };

    // Sort allies according to distance.
    std.sort.insertion(*Mob, mob.allies.items, mob, struct {
        fn f(me: *Mob, a: *Mob, b: *Mob) bool {
            return a.coord.distance(me.coord) > b.coord.distance(me.coord);
        }
    }.f);
}

pub fn checkForNoises(mob: *Mob) void {
    if (mob.deaf) {
        return;
    }

    if (mob.hasStatus(.Amnesia)) {
        mob.ai.phase = .Work;
        return;
    }

    const vision = mob.stat(.Vision);

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(mob.coord.z, x, y);
            if (!mob.ai.is_curious and mob.distance2(coord) > vision)
                continue;

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
    var new_sustiles = std.ArrayList(SuspiciousTileRecord).init(state.alloc);
    for (mob.sustiles.items) |*record| {
        record.age += 1;

        if ((record.unforgettable or record.age < NOISE_FORGET_AGE) and
            record.time_stared_at < NOISE_DONE_CHECKING)
        {
            new_sustiles.append(record.*) catch err.wat();
        } else {
            if (record.sound) |sound| if (sound.mob_source) |_| {
                alert.reportThreat(mob, .Unknown, .Noise);
            };
        }
    }
    mob.sustiles.deinit();
    mob.sustiles = new_sustiles;

    // Sort coords according to newest sound.
    std.sort.insertion(SuspiciousTileRecord, mob.sustiles.items, mob, struct {
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

fn getCurrentRoom(mob: *Mob) ?usize {
    return switch (state.layout[mob.coord.z][mob.coord.y][mob.coord.x]) {
        .Unknown => null,
        .Room => |r| r,
    };
}

pub fn glanceAt(me: *Mob, at: *Mob) void {
    me.facing = me.coordMT(at.coord).closestDirectionTo(at.coordMT(me.coord), state.mapgeometry);
}

pub fn guardGlanceRandom(mob: *Mob) void {
    if (rng.onein(6)) {
        mob.facing = rng.chooseUnweighted(Direction, &DIRECTIONS);
    }
}

pub fn isMobFacingStupid(mob: *Mob) bool {
    if (mob.coord.move(mob.facing, state.mapgeometry)) |n| {
        return Dungeon.isTileOpaque(n);
    } else return true;
}

pub fn guardGlanceRight(mob: *Mob) void {
    var tries: usize = 0;
    while ((tries == 0 or isMobFacingStupid(mob)) and tries < 10) : (tries += 1)
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

pub fn guardGlanceLeft(mob: *Mob) void {
    var tries: usize = 0;
    while ((tries == 0 or isMobFacingStupid(mob)) and tries < 10) : (tries += 1)
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

pub fn guardGlanceAround(mob: *Mob) void {
    if (rng.tenin(15)) return;

    if (rng.boolean()) {
        guardGlanceRight(mob);
    } else {
        guardGlanceLeft(mob);
    }
}

fn guardGlanceLeftRight(mob: *Mob, _: Direction) void {
    if (mob.last_attempted_move) |last_move| {
        // zig fmt: off
        const directions = switch (last_move) {
            .North =>     [_]Direction{ .NorthEast, .North,     .NorthWest, .North     },
            .South =>     [_]Direction{ .SouthEast, .South,     .SouthWest, .South     },
            .East =>      [_]Direction{ .SouthEast, .East,      .NorthEast, .East      },
            .West =>      [_]Direction{ .SouthWest, .West,      .NorthWest, .West      },
            .NorthEast => [_]Direction{ .North,     .NorthEast, .East,      .NorthEast },
            .NorthWest => [_]Direction{ .North,     .NorthWest, .West,      .NorthWest },
            .SouthEast => [_]Direction{ .South,     .SouthEast, .East,      .SouthEast },
            .SouthWest => [_]Direction{ .South,     .SouthWest, .West,      .SouthWest },
        };
        // zig fmt: on

        mob.glance_flag +%= 1;
        mob.facing = directions[mob.glance_flag];
    }
}

fn tryChooseRandomPatrolDest(mob: *Mob) ?Coord {
    var tries: usize = 5;
    while (tries > 0) : (tries -= 1) {
        const room = rng.chooseUnweighted(mapgen.Room, state.rooms[mob.coord.z].items);
        const point = room.rect.randomCoord();

        if (state.dungeon.at(point).prison or room.is_vault != null or room.is_lair)
            continue;

        if (mob.nextDirectionTo(point)) |_| {
            return point;
        }
    }

    return null;
}

pub fn sunMothWork(mob: *Mob) void {
    patrolWork(mob);
}

pub fn patrolWork(mob: *Mob) void {
    assert(state.dungeon.at(mob.coord).mob != null);
    assert(mob.ai.phase == .Work);

    const to = mob.ai.work_area.items[0];

    if (mob.cansee(to)) {
        if (tryChooseRandomPatrolDest(mob)) |point|
            mob.ai.work_area.items[0] = point;
        tryRest(mob);
        guardGlanceAround(mob);
        return;
    }

    const old_room = getCurrentRoom(mob);

    const prev_facing = mob.facing;
    mob.tryMoveTo(to);
    guardGlanceLeftRight(mob, prev_facing);

    const new_room = getCurrentRoom(mob);

    if (mob.faction == .Necromancer) {
        const genthreat = alert.getThreat(.General).level;
        if (genthreat > alert.GENERAL_THREAT_LOOK_CAREFULLY2 and
            old_room != null and new_room != null and
            old_room.? != new_room.? and
            state.rooms[mob.coord.z].items[new_room.?].type == .Room and
            !state.rooms[mob.coord.z].items[new_room.?].is_extension_room)
        {
            mob.newJob(.GRD_SweepRoom);
            mob.newestJob().?.ctx.set(usize, AIJob.CTX_ROOM_ID, new_room.?);
        } else if (genthreat > alert.GENERAL_THREAT_LOOK_CAREFULLY) {
            mob.newJob(.GRD_LookAround);
            // crashes, idk
            // mob.delegateJob();
        }
    }
}

pub fn guardWork(mob: *Mob) void {
    const post = mob.ai.work_area.items[0];

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
        } else if (rng.tenin(15) or state.rooms[mob.coord.z].items.len == 1) {
            var tries: usize = 100;
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

            assert(nearest != null);

            var tries: usize = 100;
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

pub fn suicideWork(mob: *Mob) void {
    tryRest(mob);
    mob.HP = 0;
}

pub fn dummyWork(m: *Mob) void {
    tryRest(m);
}

pub fn standStillAndGuardWork(mob: *Mob) void {
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

pub fn combatDummyWork(mob: *Mob) void {
    guardGlanceRight(mob);
    tryRest(mob);
}

pub fn spireWork(mob: *Mob) void {
    guardGlanceRight(mob);
    tryRest(mob);

    if (mob.allies.items.len == 0) {
        mob.addStatus(.Sleeping, 0, .Prm);
    }
}

pub fn watcherWork(mob: *Mob) void {
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

// Fallback AI for when a worker doesn't have any jobs.
//
// All it does is make the worker scan for jobs, and leave the floor after
// a few turns if it didn't find anything.
//
pub fn workerWork(mob: *Mob) void {
    assert(mob.jobs.len == 0);
    mob.newJob(.WRK_LeaveFloor);
    mob.newJob(.WRK_ScanJobs);
    // Kinda silly, we should get started working on this very turn.
    // Dunno if that might introduce any bugs though.
    tryRest(mob);
}

pub fn haulerWork(mob: *Mob) void {
    switch (mob.ai.work_phase) {
        .HaulerScan => {
            if (mob.ai.work_area.items.len > 0 and
                mob.coord.distance(mob.ai.work_area.items[0]) > 1)
            {
                mob.tryMoveTo(mob.ai.work_area.items[0]);
            } else {
                tryRest(mob);
            }

            for (state.tasks.items, 0..) |*task, id|
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
                    const spot = state.nextAvailableSpaceForItem(mob.coord, state.alloc);
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

pub fn stayNearLeaderWork(mob: *Mob) void {
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

pub fn hulkWork(mob: *Mob) void {
    switch (rng.range(usize, 0, 99)) {
        0...75 => tryRest(mob),
        76...90 => if (!mob.moveInDirection(rng.chooseUnweighted(Direction, &DIRECTIONS))) tryRest(mob),
        91...99 => mob.tryMoveTo(state.player.coord),
        else => unreachable,
    }
}

pub fn wanderWork(mob: *Mob) void {
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
pub fn tortureWork(mob: *Mob) void {
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

    for (mob.fov, 0..) |row, y| for (row, 0..) |cell, x| {
        if (cell == 0) continue;
        const fitem = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(fitem).mob) |othermob| {
            if (othermob.prisoner_status != null) prisoners.append(othermob) catch break;
        }
    };

    std.sort.insertion(*Mob, prisoners.slice(), mob, _sortFunc._sortWithDistance);

    for (prisoners.constSlice()) |prisoner| {
        if (prisoner.isUnderStatus(.Pain)) |_|
            continue;

        spells.CAST_PAIN.use(mob, mob.coord, prisoner.coord, .{
            .MP_cost = 0,
            .spell = &spells.CAST_PAIN,
            .duration = rng.range(usize, 10, 20),
            .power = 0,
        });
        return;
    }

    tryRest(mob);
}

pub fn ballLightningWorkOrFight(mob: *Mob) void {
    var walkability_map: [HEIGHT][WIDTH]bool = undefined;
    for (&walkability_map, 0..) |*row, y| for (row, 0..) |*cell, x| {
        const coord = Coord.new2(mob.coord.z, x, y);
        cell.* = state.is_walkable(coord, .{ .mob = mob });
    };

    var conductivity_dijkmap: [HEIGHT][WIDTH]?f64 = undefined;
    for (&conductivity_dijkmap, 0..) |*row, y| for (row, 0..) |*cell, x| {
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

pub fn nightCreatureWork(mob: *Mob) void {
    switch (mob.ai.work_phase) {
        .NC_Guard => {
            // If this is a slinking terror and it's not close to walls, immediately
            // begin moving to the closest wall.
            if (mob.ai.flag(.WallLover) and state.dungeon.neighboringWalls(mob.coord, true) == 0) {
                assert(!mob.immobile);
                var dijk: dijkstra.Dijkstra = undefined;
                dijk.init(mob.coord, state.mapgeometry, 255, state.is_walkable, .{}, state.alloc);
                defer dijk.deinit();
                while (dijk.next()) |item|
                    if (state.dungeon.neighboringWalls(item, true) > 0) {
                        mob.ai.work_area.clearRetainingCapacity();
                        mob.ai.work_area.append(item) catch err.wat();
                        mob.ai.work_phase = .NC_MoveTo;
                        tryRest(mob);
                        return;
                    };
            }

            // If player is hated, randomly meditate on them
            if (!mob.immobile and state.night_rep[@intFromEnum(state.player.faction)] <= -10 and rng.onein(1500)) {
                updateEnemyKnowledge(mob, state.player, null);
                tryRest(mob);
                return;
            }

            if (!mob.immobile and rng.onein(2000)) {
                const cur_room: ?*mapgen.Room = switch (state.layout[mob.coord.z][mob.coord.y][mob.coord.x]) {
                    .Unknown => null,
                    .Room => |r| &state.rooms[mob.coord.z].items[r],
                };

                var possibles = StackBuffer(Coord, 2).init(null);
                for (state.rooms[mob.coord.z].items) |*room| {
                    if ((cur_room != null and room == cur_room.?) or !room.is_lair)
                        continue;

                    const point = room.rect.randomCoord();
                    if (mob.nextDirectionTo(point)) |_| {
                        possibles.append(point) catch err.wat();
                        break;
                    }
                }

                if (possibles.len > 0) {
                    const point = rng.chooseUnweighted(Coord, possibles.constSlice());
                    mob.ai.work_area.clearRetainingCapacity();
                    mob.ai.work_area.append(point) catch err.wat();
                    mob.ai.work_phase = .NC_PatrolTo;
                    mob.tryMoveTo(point);
                    return;
                }
            }
            standStillAndGuardWork(mob);
        },
        .NC_MoveTo, .NC_PatrolTo => {
            // First check for enemies that have seen us, and disable them.
            for (mob.fov, 0..) |row, y| for (row, 0..) |cell, x| if (cell != 0) {
                const fitem = Coord.new2(mob.coord.z, x, y);

                if (state.dungeon.at(fitem).mob) |othermob| {
                    if (!othermob.ai.flag(.IgnoredByEnemies) and othermob.isHostileTo(mob) and
                        !othermob.hasStatus(.Amnesia) and !Status.isMobImmune(.Amnesia, othermob) and
                        isEnemyKnown(othermob, mob))
                    {
                        spells.BOLT_AOE_AMNESIA.use(mob, mob.coord, othermob.coord, .{
                            .free = true,
                            .MP_cost = 0,
                            .spell = &spells.BOLT_AOE_AMNESIA,
                            .duration = 10,
                        });
                    }
                }
            };

            const to = mob.ai.work_area.items[0];

            if ((mob.ai.work_phase == .NC_PatrolTo and mob.cansee(to)) or
                (mob.ai.work_phase == .NC_MoveTo and mob.coord.eq(to)))
            {
                mob.ai.work_phase = .NC_Guard;
                tryRest(mob);
            } else {
                mob.tryMoveTo(to);
            }

            // Now check if there are enemies adjacent to us, and face them to
            // be disposed of next turn.
            for (&DIRECTIONS) |d| if (mob.coord.move(d, state.mapgeometry)) |neighbor| {
                if (state.dungeon.at(neighbor).mob) |othermob| {
                    if (othermob.isHostileTo(mob) and !othermob.ai.flag(.IgnoredByEnemies)) {
                        mob.facing = d;
                    }
                }
            };
        },
        else => unreachable,
    }
}

// For combat dummies
pub fn combatDummyFight(mob: *Mob) void {
    tryRest(mob);
}

// Run away and keep distance, but don't look back or update enemy's current
// position.
pub fn workerFight(mob: *Mob) void {
    // Do we really want to do this? There may be some cases I've forgotten
    // about where enemies deliberately purge knowledge of enemy...
    //
    // NOTE: 2023-08-10: not sure why we're doing this? Is it to prevent
    // forgetting the enemy too quickly?
    //
    // NOTE: 2023-10-16: aha, it's to ensure workers always flee from current
    // position of enemy, rather than last known position of enemy. I think. In
    // which case the original comment doesn't really make sense? (because the
    // memory duration isn't being affected)
    //
    if (closestEnemy(mob).last_seen == null)
        closestEnemy(mob).last_seen = closestEnemy(mob).mob.coord;

    if (!runAwayFromEnemies(mob, 16))
        tryRest(mob);

    if (closestEnemy(mob).alerted_allies < 3)
        alertAllyOfHostile(mob);
}

pub fn meleeFight(mob: *Mob) void {
    const target = closestEnemy(mob);

    if (mob.canMelee(target.mob)) {
        mob.fight(target.mob, .{});
    } else if (!mob.immobile) {
        mob.tryMoveTo(target.last_seen orelse target.mob.coord);
    } else {
        tryRest(mob);
    }
}

pub fn grueFight(mob: *Mob) void {
    const target = closestEnemy(mob).mob;

    if (mob.distance(target) == 1) {
        if (mob.HP < (mob.max_HP / 4) or rng.onein(50)) {
            const D = struct { d: Direction, dist: usize };
            var directions = StackBuffer(D, 8).init(null);
            for (&DIRECTIONS) |d| {
                const farthest = utils.getFarthestWalkableCoord(d, target.coord, .{ .only_if_breaks_lof = true });
                const distance = farthest.distance(mob.coord);
                if (distance > 2 and distance < 8)
                    directions.append(.{ .d = d, .dist = distance }) catch err.wat();
            }
            if (directions.len > 0) {
                const chosen = rng.chooseUnweighted(D, directions.constSlice());
                combat.throwMob(mob, target, chosen.d, chosen.dist);
            }
        }
        tryRest(mob);
    } else if (mob.distance(target) == 2) {
        mob.tryMoveTo(target.coord);
    } else {
        tryRest(mob);
    }
}

pub fn watcherFight(mob: *Mob) void {
    const target = closestEnemy(mob).mob;

    mob.makeNoise(.Shout, .Loud);

    if (!mob.cansee(target.coord)) {
        mob.tryMoveTo(target.coord);
    } else {
        if (runAwayFromEnemies(mob, 8)) {
            mob.facing = mob.coord.closestDirectionTo(target.coord, state.mapgeometry);
        } else {
            meleeFight(mob);
        }
    }
}

// pub fn coronerFight(mob: *Mob) void {
//     const target = closestEnemy(mob).mob;
//     alert.announceEnemyAlert(target);
//     watcherFight(mob, alloc);
// }

pub fn stalkerFight(mob: *Mob) void {
    const target = closestEnemy(mob).mob;

    if (mob.squad != null and
        mem.eql(u8, mob.squad.?.leader.?.id, "hunter"))
    {
        if (!mob.cansee(target.coord)) {
            mob.tryMoveTo(target.coord);
        } else {
            const dist: usize = @intCast(mob.stat(.Vision) - 1);
            if (!runAwayFromEnemies(mob, dist))
                tryRest(mob);
        }
    } else if (mob.enemyList().items.len == 1) {
        mageFight(mob);
    } else {
        work(mob);
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
pub fn rangedFight(mob: *Mob) void {
    const target = closestEnemy(mob).mob;

    // if we can't see the enemy, move towards it
    if (!mob.cansee(target.coord))
        mob.tryMoveTo(target.coord);

    // hack to give breathing space to enemy who just got projectile thrown at it
    const spare_enemy_proj = rng.tenin(25);

    const inventory = mob.inventory.pack.constSlice();
    const proj_item: ?usize = for (inventory, 0..) |item, id| {
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
        mob.throwItem(&item, target.coord, state.alloc);
    }
}

fn _isValidTargetForSpell(caster: *Mob, spell: SpellOptions, target: *Mob) bool {
    assert(!target.is_dead);

    if (spell.spell.checks_will and
        target.stat(.Willpower) > caster.stat(.Willpower))
        return false;

    if (spell.spell.needs_cardinal_direction_target and
        (target.coord.x != caster.coord.x and target.coord.y != caster.coord.y))
        return false;

    if (spell.spell.needs_visible_target and !caster.cansee(target.coord))
        return false;

    if (spell.spell.cast_type == .Smite) {
        switch (spell.spell.smite_target_type) {
            .AngelAlly => if (target.life_type != .Spectral and target.faction != .Holy) return false,
            .ConstructAlly => if (target.life_type != .Construct) return false,
            .UndeadAlly => if (target.life_type != .Undead) return false,
            .SpecificAlly, .SpecificMob => |id| if (!mem.eql(u8, id, target.id)) return false,
            else => {},
        }
    }

    if (spell.spell.cast_type == .Bolt) {
        var caster_c = caster.coord;
        var target_c = target.coord;
        if (caster.multitile != null and target.multitile != null) {
            caster_c = caster.coordMT(target_c);
            target_c = target.coordMT(caster_c);
            caster_c = caster.coordMT(target_c);
        } else if (caster.multitile != null or target.multitile != null) {
            caster_c = caster.coordMT(target_c);
            target_c = target.coordMT(caster_c);
            caster_c = caster.coordMT(target_c);
        }
        if (!utils.hasClearLOF(caster_c, target_c))
            return false;
    }

    var is_redundant = true;
    for (spell.spell.effects) |effect|
        switch (effect) {
            .Status => if (!target.hasStatus(effect.Status)) {
                is_redundant = false;
            },
            else => is_redundant = false,
        };
    if (is_redundant)
        return false;

    if (spell.spell.check_has_effect) |func| {
        if (!(func)(caster, spell, target.coord))
            return false;
    }

    return true;
}

fn _findValidTargetForSpell(caster: *Mob, spell: SpellOptions) ?Coord {
    if (spell.spell.cast_type == .Blast or
        (spell.spell.cast_type == .Smite and spell.spell.smite_target_type == .Self))
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
        (spell.spell.smite_target_type == .ConstructAlly or
            spell.spell.smite_target_type == .AngelAlly or
            spell.spell.smite_target_type == .UndeadAlly or
            spell.spell.smite_target_type == .SpecificAlly))
    {
        return for (caster.allies.items) |ally| {
            if (_isValidTargetForSpell(caster, spell, ally))
                return ally.coordMT(caster.coord);
        } else null;
    } else {
        return for (caster.enemyList().items) |enemy_record| {
            if (_isValidTargetForSpell(caster, spell, enemy_record.mob))
                return enemy_record.mob.coordMT(caster.coord);
        } else null;
    }
}

pub fn alchemistFight(mob: *Mob) void {
    mageFight(mob);
}

pub fn sunMothFight(mob: *Mob) void {
    if (!castAnySpell(mob)) {
        const dist: usize = @intCast(mob.stat(.Vision) + 1);
        const moved = runAwayFromEnemies(mob, dist);
        if (!moved) tryRest(mob);
    }
}

fn castAnySpell(mob: *Mob) bool {
    if (mob.ai.flag(.RandomSpells)) {
        var possibles = std.ArrayList(struct { Coord, SpellOptions }).init(state.alloc);
        defer possibles.deinit();
        for (mob.spells) |spell| {
            if (spell.MP_cost > mob.MP) continue;
            if (_findValidTargetForSpell(mob, spell)) |coord|
                possibles.append(.{ coord, spell }) catch err.wat();
        }
        if (possibles.items.len == 0)
            return false;
        const coord, const spell =
            rng.chooseUnweighted(struct { Coord, SpellOptions }, possibles.items);
        spell.spell.use(mob, mob.coordMT(coord), coord, spell);
        return true;
    } else {
        for (mob.spells) |spell| {
            if (spell.MP_cost > mob.MP) continue;
            if (_findValidTargetForSpell(mob, spell)) |coord| {
                spell.spell.use(mob, mob.coordMT(coord), coord, spell);
                return true;
            }
        }
        return false;
    }
}

pub fn mageFight(mob: *Mob) void {
    const target = closestEnemy(mob);
    mob.facing = mob.coord.closestDirectionTo(target.mob.coord, state.mapgeometry);

    if (mob.ai.flag(.SocialFighter) or mob.ai.flag(.SocialFighter2)) {
        // Check if there's an ally that satisfies the following conditions
        //      - Isn't the current mob
        //      - Isn't another immobile mob
        //      - Is either investigating or attacking
        const found_ally = for (mob.allies.items) |ally| {
            if (ally != mob and !ally.immobile and
                (mob.ai.flag(.SocialFighter2) or ally.ai.phase == .Hunt or ally.ai.phase == .Investigate))
            {
                break true;
            }
        } else false;

        if (!found_ally) {
            tryRest(mob);
            return;
        }
    }

    if (castAnySpell(mob))
        return;

    switch (mob.ai.spellcaster_backup_action) {
        .Melee => meleeFight(mob),
        .KeepDistance => if (!mob.immobile) {
            const dist: usize = @intCast(mob.stat(.Vision) -| 2);
            const moved = runAwayFromEnemies(mob, dist);
            if (!moved) meleeFight(mob);
            mob.facing = mob.coord.closestDirectionTo(target.mob.coord, state.mapgeometry);
        } else {
            tryRest(mob);
        },
        .KeepDistAlarm => {
            if (mob.hasJob(.ALM_PullAlarm)) |_| {
                assert(workJobs(mob));
            } else {
                assert(!mob.immobile);
                const dist: usize = @intCast(mob.stat(.Vision) -| 1);
                const moved = runAwayFromEnemies(mob, dist);
                if (!moved) meleeFight(mob);
            }
        },
        // .Flee => {
        //     assert(!mob.immobile);
        //     const moved = runAwayFromEnemies(mob, 1000);
        //     if (!moved) meleeFight(mob, alloc);
        // },
    }
}

pub fn flee(mob: *Mob) void {
    const FLEE_GOAL = 25;

    assert(mob.stat(.Vision) < FLEE_GOAL);

    const target = closestEnemy(mob);

    if (target.alerted_allies < 2)
        alertAllyOfHostile(mob);

    if (mob.bflee_flag) {
        // Job should be leave floor.
        assert(mob.jobs.last().?.job == .WRK_LeaveFloor);
        assert(mob.faction == .Necromancer);
        const did_not_defer = workJobs(mob);
        assert(did_not_defer);
    } else {
        if (mob.immobile or
            !runAwayFromEnemies(mob, FLEE_GOAL))
        {
            if (mob.canMelee(target.mob)) {
                meleeFight(mob);
            } else {
                tryRest(mob);
            }
        }
        if (shouldCallForReinforcements(mob)) {
            closestVisibleEnemy(mob).request_help_when_finish = true;
            mob.newJob(.WRK_LeaveFloor);
            mob.bflee_flag = true;
            for (mob.allies.items) |ally|
                if (ally.ai.phase == .Flee) {
                    ally.newJob(.WRK_LeaveFloor);
                    ally.bflee_flag = true;
                };
        }
    }

    // This can happen if the mob left the floor...
    // sucks that I need to take care of these edge cases lol
    if (mob.is_dead) return;

    if (mob.hasStatus(.Fear)) {
        mob.makeNoise(.Scream, .Loud);
    } else {
        if (mob.faction == .Necromancer) { // Only shout if dungeon full of frens
            mob.makeNoise(.Shout, .Loud);
        }
    }

    const dist = target.mob.coord.distance(mob.coord);
    if (dist <= mob.stat(.Vision)) {
        // Don't forget about him!
        mob.facing = mob.coord.closestDirectionTo(target.mob.coord, state.mapgeometry);
    }
}

pub fn _Job_WRK_LeaveFloor(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const CTX_STAIR_LOCATION = "ctx_stair_location";

    // Chosen incase we haven't done this step yet. If we have done this step of
    // choosing the stair, then its ignored
    const random_stair = if (state.dungeon.stairs[mob.coord.z].len > 0)
        rng.chooseUnweighted(Coord, state.dungeon.stairs[mob.coord.z].constSlice())
    else
        state.dungeon.entries[mob.coord.z];

    const stair = job.ctx.get(Coord, CTX_STAIR_LOCATION, random_stair);

    if (mob.distance2(stair) == 1) {
        for (mob.enemyList().items) |enemy|
            enemy.reportMajorThreat(mob);
        mob.deinitNoCorpse();
        return .Complete;
    } else {
        mob.tryMoveTo(stair);
        return .Ongoing;
    }
}

// Do some theatrical glancing around for a bit, then check for available tasks
// and complete them.
//
// NOTE: when workers first enter the floor, they DON'T have this job. Instead
// they spawn with zero jobs, and then execute workerWork(), which adds this job
// for them.
//
// This means that it takes around 2-3 turns for a worker to actually begin the
// job for which they were spawned onto the floor. (Yeah, I should fix it at
// some point... but it works, and the delay isn't really a huge issue.)
//
pub fn _Job_WRK_ScanJobs(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const CTX_TURNS_LEFT_SCANNING = "ctx_turns_left_scanning";
    const turns_left = job.ctx.get(usize, CTX_TURNS_LEFT_SCANNING, rng.range(usize, 5, 9));

    const jobtypes = tasks.getJobTypesForWorker(mob);

    // Ideally we get to work right away, but too lazy to code that right now
    if (mob.ai.task_id != null) {
        tryRest(mob);
        mob.newJob(.WRK_ScanJobs);
        mob.newJob(jobtypes.aijobtype);
        return .Complete;
    }

    for (state.tasks.items, 0..) |*task, id|
        if (!task.completed and task.assigned_to == null and task.type == jobtypes.tasktype) {
            mob.ai.task_id = id;
            task.assigned_to = mob;
            mob.newJob(.WRK_ScanJobs);
            mob.newJob(jobtypes.aijobtype);
            tryRest(mob);
            return .Complete;
        };

    tryRest(mob);
    guardGlanceAround(mob);

    if (turns_left == 0) {
        return .Complete;
    } else {
        job.ctx.set(usize, CTX_TURNS_LEFT_SCANNING, turns_left - 1);
        return .Ongoing;
    }
}

pub fn _Job_WRK_Clean(mob: *Mob, _: *AIJob) AIJob.JStatus {
    const task = state.tasks.items[mob.ai.task_id.?];
    const target = task.type.Clean;

    if (target.distance(mob.coord) > 1) {
        mob.tryMoveTo(target);
        return .Ongoing;
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
            state.tasks.items[mob.ai.task_id.?].completed = true;
            mob.ai.task_id = null;
            return .Complete;
        } else {
            return .Ongoing;
        }
    }
}

pub fn _Job_WRK_ScanCorpse(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const coord = job.ctx.get(Coord, AIJob.CTX_CORPSE_LOCATION, undefined);

    if (mob.distance2(coord) > 1) {
        mob.tryMoveTo(coord);
        return .Ongoing;
    }

    for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, .{ .mob = mob }) and rng.boolean()) {
            mob.sustiles.append(.{ .coord = coord }) catch err.wat();
        }
    };

    mob.newJob(.WRK_ReportCorpse);
    mob.newestJob().?.ctx.set(Coord, AIJob.CTX_CORPSE_LOCATION, coord);

    tryRest(mob);
    return .Complete;
}

pub fn _Job_WRK_ReportCorpse(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const coord = job.ctx.get(Coord, AIJob.CTX_CORPSE_LOCATION, undefined);
    const corpse = (state.dungeon.at(coord).surface orelse return .Complete).Corpse;

    if (mob.distance2(coord) > 1) {
        mob.tryMoveTo(coord);
        return .Ongoing;
    }

    tasks.reportTask(mob.coord.z, .{ .ExamineCorpse = corpse });
    corpse.corpse_info.is_reported = true;

    tryRest(mob);
    return .Complete;
}

// FIXME: examine corpse job will continue even if corpse is destroyed in a fire/explosion
//
pub fn _Job_WRK_ExamineCorpse(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const CTX_TURNS_LEFT_EXAMINING = "ctx_turns_left_examining";
    const turns_left = job.ctx.get(usize, CTX_TURNS_LEFT_EXAMINING, rng.range(usize, 8, 16));

    const task = &state.tasks.items[mob.ai.task_id.?];
    const corpse = task.type.ExamineCorpse;

    if (mob.distance2(corpse.coord) > 1) {
        mob.tryMoveTo(corpse.coord);
        return .Ongoing;
    } else {
        // Flip a coin and decide whether to stand still or move around the
        // corpse for dramatic effect.
        //
        if (rng.onein(4)) {
            tryRest(mob);
        } else {
            const moved = for (&DIRECTIONS) |d| {
                if (corpse.coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.is_walkable(neighbor, .{ .mob = mob }) and
                        mob.distance2(neighbor) == 1 and rng.onein(6))
                    {
                        mob.tryMoveTo(neighbor);
                        break true;
                    }
                }
            } else false;
            if (!moved) tryRest(mob);
        }

        if (turns_left == 0) {
            corpse.corpse_info.is_resolved = true;

            if (corpse.killed_by) |killed_by| {
                alert.reportThreat(mob, if (corpse.corpse_info.killer_confirmed) .{ .Specific = killed_by } else .Unknown, .Death);

                // Summon reinforcements (regardless of whether killer is
                // confirmed or not), only refraining from doing so if the
                // killer isn't the player and has been noticed dead. This is
                // to prevent floor from filling up with reinforcements from a
                // short-lived player-instigated prisoner rebellion.
                //
                if (killed_by == state.player or !killed_by.corpse_info.is_noticed) {
                    if (switch (state.layout[corpse.coord.z][corpse.coord.y][corpse.coord.x]) {
                        .Unknown => null,
                        .Room => |r| r,
                    }) |room| {
                        alert.queueThreatResponse(.{
                            .ReinforceRoom = .{ .reinforcement = .{ .Class = "C" }, .room = room, .coord = corpse.coord },
                        });
                    }
                }
            }

            mob.ai.task_id = null;
            task.completed = true;
            return .Complete;
        } else {
            job.ctx.set(usize, CTX_TURNS_LEFT_EXAMINING, turns_left - 1);
            return .Ongoing;
        }
    }
}

pub fn _Job_WRK_BuildMob(mob: *Mob, _: *AIJob) AIJob.JStatus {
    const task = &state.tasks.items[mob.ai.task_id.?];
    const coord = task.type.BuildMob.coord;

    if (mob.distance2(coord) == 0) {
        for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |n|
            if (state.is_walkable(n, .{ .mob = mob })) {
                mob.tryMoveTo(n);
                return .Ongoing;
            };
        // FAILED
        task.completed = true;
        return .Complete;
    } else if (mob.distance2(coord) > 1) {
        mob.tryMoveTo(coord);
        return .Ongoing;
    } else {
        tryRest(mob);
        if (state.dungeon.at(coord).mob) |othermob| {
            if (othermob.immobile) {
                // FAILED
                mob.ai.task_id = null;
                task.completed = true;
                return .Complete;
            } else {
                return .Ongoing;
            }
        } else {
            _ = mobs.placeMob(state.alloc, task.type.BuildMob.mob, coord, task.type.BuildMob.opts);
            mob.ai.task_id = null;
            task.completed = true;
            return .Complete;
        }
    }
}

pub fn _Job_WRK_WrkstationBusyWork(mob: *Mob, j: *AIJob) AIJob.JStatus {
    var didstuff = false;
    const origcoord = mob.coord;
    for (&DIRECTIONS) |d| if (mob.coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.dungeon.at(neighbor).surface) |surface|
            if (surface == .Machine and surface.Machine.power == 0 and
                !state.is_walkable(neighbor, .{ .mob = mob }) and
                rng.onein(8))
            {
                const r = mob.moveInDirection(d);
                err.ensure(r, "{cf}: Busywork failed", .{mob}) catch {};
                err.ensure(mob.coord.eq(origcoord), "{cf}: Busywork caused movement", .{mob}) catch {};
                if (r) didstuff = true;
                break;
            };
    };

    if (!didstuff) tryRest(mob);

    return j.checkTurnsLeft(7);
}

// Specifically for rolling boulder, and only for rolling boulder.
//
// If generalizing, make sure to change the bit which transforms into SoH.
//
pub fn _Job_ATK_Homing(homer: *Mob, job: *AIJob) AIJob.JStatus {
    const MAX_ANGLE_CHANGE = 40.0 * math.pi / 180.0;

    const S = struct {
        pub fn _die(me: *Mob) AIJob.JStatus {
            if (state.player.canSeeMob(me)) {
                const verb = if (mem.eql(u8, me.id, "rolling_boulder")) "stops" else "dissipates";
                state.message(.CombatUnimportant, "{c} {s}.", .{ me, verb });
            }
            state.dungeon.atGas(me.coord)[gas.SmokeGas.id] += gas.MIN_GAS_SPREAD - 1;
            me.deinitNoCorpse();
            return .Complete;
        }

        pub fn _dieWithVictim(me: *Mob, target: *Mob, damage: usize, is_blast: bool) AIJob.JStatus {
            if (is_blast) {
                if (state.player.canSeeMob(me))
                    state.message(.SpellCast, "{c} explodes!!", .{me});
                spells.BLAST_HELLFIRE.use(me, me.coord, me.coord, .{
                    .power = damage,
                    .free = true,
                    .MP_cost = 0,
                    .no_message = true,
                });
            } else {
                target.takeDamage(.{
                    .amount = damage,
                    .by_mob = me,
                    .kind = .Physical,
                    .blood = false,
                    .source = .MeleeAttack,
                }, .{
                    .strs = &[_]types.DamageStr{
                        items._dmgstr(10, "slam", "slams", ""),
                    },
                });
            }
            me.deinitNoCorpse();
            return .Complete;
        }

        pub fn _calcAngle(from: Coord, to: Coord) f64 {
            const dx: f64 = @floatFromInt(@as(isize, @intCast(to.x)) - @as(isize, @intCast(from.x)));
            const dy: f64 = @floatFromInt(@as(isize, @intCast(to.y)) - @as(isize, @intCast(from.y)));
            return math.atan2(dy, dx);
        }
    };

    // Code written with assumption that this is false
    assert(homer.multitile == null);

    // target, speed, and is_blast should be set by spawner (e.g. spells.CAST_ROLLING_BOULDER)
    const target = job.ctx.getOrNone(*Mob, AIJob.CTX_HOMING_TARGET).?;
    const target_coord = target.coordMT(homer.coord);
    const damage = job.ctx.getOrNone(usize, AIJob.CTX_HOMING_DAMAGE).?;
    const speed = job.ctx.getOrNone(f64, AIJob.CTX_HOMING_SPEED).?;
    const is_blast = job.ctx.getOrNone(bool, AIJob.CTX_HOMING_BLAST).?;
    const angle = job.ctx.get(f64, AIJob.CTX_HOMING_ANGLE, S._calcAngle(homer.coord, target_coord));

    const min_distance: usize =
        if (mem.eql(u8, homer.id, "rolling_boulder")) 1 else spells.BLAST_HELLFIRE_AOE;

    // Do a check before-hand, in case target very helpfully moved
    if (homer.coord.distanceManhattan(target_coord) == min_distance) {
        return S._dieWithVictim(homer, target, damage, is_blast);
    }

    const x = (@max(1, speed) * @cos(angle)) + @as(f64, @floatFromInt(homer.coord.x));
    const y = (@max(1, speed) * @sin(angle)) + @as(f64, @floatFromInt(homer.coord.y));
    const dest = Coord.new2(homer.coord.z, @intFromFloat(x), @intFromFloat(y));

    // Semi-duplicated from src/combat/throwMob()
    var slammed_into_mob: ?*Mob = null;
    var slammed_into_something = false;
    var last_viable_coord = homer.coord;
    const line = homer.coord.drawLine(dest, state.mapgeometry, 0);
    for (line.constSlice(), 0..) |path, i| {
        if (i == 0) continue; // Skip the current coord
        if (!state.is_walkable(path, .{ .mob = homer, .right_now = true })) {
            if (state.dungeon.at(path).mob) |mob|
                slammed_into_mob = mob;
            slammed_into_something = true;
            break;
        }
        last_viable_coord = path;
    }

    ui.Animation.apply(.{ .TraverseLine = .{
        .start = homer.coord,
        .end = dest,
        .char = homer.tile,
        .path_char = '°',
    } });

    const r = homer.teleportTo(last_viable_coord, null, false, false);
    assert(r);

    if (slammed_into_something) {
        if (slammed_into_mob) |victim| {
            return S._dieWithVictim(homer, victim, damage, is_blast);
        } else {
            return S._die(homer);
        }
    }

    // Check again after movement. So that victim can't force the
    // boulder/sphere to play catch-up.
    if (homer.coord.distanceManhattan(target.coordMT(homer.coord)) == min_distance) {
        return S._dieWithVictim(homer, target, damage, is_blast);
    }

    // Now set new variables, and potentially transform
    job.ctx.set(f64, AIJob.CTX_HOMING_SPEED, speed * 2);

    // Don't turn too sharply
    const angle_d = angle - S._calcAngle(homer.coord, target.coord);
    const new_angle =
        if (angle_d > MAX_ANGLE_CHANGE)
            angle + MAX_ANGLE_CHANGE
        else if (angle_d < -MAX_ANGLE_CHANGE)
            angle - MAX_ANGLE_CHANGE
        else
            angle - angle_d;
    job.ctx.set(f64, AIJob.CTX_HOMING_ANGLE, new_angle);

    if (rng.onein(5) and mem.eql(u8, homer.id, "rolling_boulder")) {
        if (state.player.canSeeMob(homer))
            state.message(.SpellCast, "The boulder transforms into a sphere of hellfire!", .{});
        homer.deinitNoCorpse();

        const soh = mobs.placeMob(state.alloc, &mobs.SphereHellfireTemplate, homer.coord, .{});
        soh.newJob(.ATK_Homing);
        soh.newestJob().?.ctx.set(*Mob, AIJob.CTX_HOMING_TARGET, target);
        soh.newestJob().?.ctx.set(usize, AIJob.CTX_HOMING_DAMAGE, damage);
        soh.newestJob().?.ctx.set(void, AIJob.CTX_OVERRIDE_FIGHT, {});
        soh.newestJob().?.ctx.set(f64, AIJob.CTX_HOMING_SPEED, speed * 2);
        soh.newestJob().?.ctx.set(bool, AIJob.CTX_HOMING_BLAST, true);

        return .Complete;
    }

    return .Ongoing;
}

pub fn _Job_GRD_LookAround(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const CTX_TURNS_LEFT_LOOKING = "ctx_turns_left_examining";
    const turns_left = job.ctx.get(usize, CTX_TURNS_LEFT_LOOKING, rng.range(usize, 2, 4));

    if (rng.onein(3)) {
        const dirs = if (mob.hasStatus(.Disorient)) &DIAGONAL_DIRECTIONS else &DIRECTIONS;
        if (!mob.moveInDirection(rng.chooseUnweighted(Direction, dirs)))
            tryRest(mob);
    } else tryRest(mob);
    guardGlanceRandom(mob);

    if (turns_left == 0) {
        return .Complete;
    } else {
        job.ctx.set(usize, CTX_TURNS_LEFT_LOOKING, turns_left - 1);
        return .Ongoing;
    }
}

pub fn _Job_GRD_SweepRoom(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const CTX_ROOM_MAP = "ctx_room_map";
    const CTX_ROOM_SWEEP_DEST = "ctx_room_sweep_dest";

    const room_id = job.ctx.get(usize, AIJob.CTX_ROOM_ID, getCurrentRoom(mob) orelse undefined);
    const room = state.rooms[mob.coord.z].items[room_id];
    const room_map = job.ctx.getPtr(CoordArrayList, CTX_ROOM_MAP, CoordArrayList.init(state.alloc));
    const room_dst = job.ctx.get(Coord, CTX_ROOM_SWEEP_DEST, room.rect.middle());

    for (mob.fov, 0..) |row, y| for (row, 0..) |cell, x| {
        if (cell == 0) continue;
        const fitem = Coord.new2(mob.coord.z, x, y);
        room_map.append(fitem) catch err.wat();
    };

    if (mob.cansee(room_dst)) {
        var tries = room.rect.height * (room.rect.width / 2);
        while (tries > 0) : (tries -= 1) {
            const ctry = room.rect.randomCoord();
            const seen = for (room_map.items) |c| {
                if (c.eq(ctry)) break true;
            } else false;
            if (!seen and !state.dungeon.at(ctry).prison and
                mob.nextDirectionTo(ctry) != null)
            {
                tryRest(mob);
                job.ctx.set(Coord, CTX_ROOM_SWEEP_DEST, ctry);
                return .Ongoing;
            }
        }

        tryRest(mob);
        return .Complete;
    } else {
        const prev_facing = mob.facing;
        mob.tryMoveTo(room_dst);
        guardGlanceLeftRight(mob, prev_facing);
        return .Ongoing;
    }
}

pub fn _Job_ALM_PullAlarm(mob: *Mob, job: *AIJob) AIJob.JStatus {
    if (state.alarm_locations[mob.coord.z].len == 0)
        return .Complete;

    if (job.ctx.getOrNone(Coord, AIJob.CTX_ALARM_COORD) == null) {
        var closest: ?Coord = null;
        var closest_dist: usize = 0xFFFF;
        for (state.alarm_locations[mob.coord.z].constSlice()) |alarm_loc| {
            const path = astar.path(mob.coord, alarm_loc, state.mapgeometry, state.is_walkable, .{ .ignore_mobs = true }, astar.basePenaltyFunc, mob.availableDirections(), state.alloc) orelse continue;
            defer path.deinit();
            if (path.items.len < closest_dist) {
                closest_dist = path.items.len;
                closest = alarm_loc;
            }
        }

        job.ctx.set(Coord, AIJob.CTX_ALARM_COORD, closest orelse return .Complete);
    }

    const alarm = job.ctx.getOrNone(Coord, AIJob.CTX_ALARM_COORD).?;

    if (mob.distance2(alarm) == 1) {
        // Repeatedly try to move into machine to power it
        // TODO: refactor in reusable func, I assume we'll be doing this a lot
        if (mob.nextDirectionTo(alarm)) |d| {
            if (!mob.moveInDirection(d)) {
                tryRest(mob);
                return .Ongoing;
            } else {
                return .Complete;
            }
        } else {
            tryRest(mob);
            return .Ongoing;
        }
    } else {
        mob.tryMoveTo(alarm);
        return .Ongoing;
    }
}

pub fn _Job_SPC_TellPlayer(mob: *Mob, job: *AIJob) AIJob.JStatus {
    if (!state.player.canSeeMob(mob)) {
        mob.tryMoveTo(state.player.coord);
        return .Ongoing;
    }

    mob.facing = mob.coord.closestDirectionTo(state.player.coord, state.mapgeometry);
    state.dialog(mob, job.ctx.getOrNone([]const u8, AIJob.CTX_DIALOG).?);
    tryRest(mob);
    return .Complete;
}

pub fn _Job_SPC_NCAlignment(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const CTX_DIALOG1_GIVEN = "dialog1_given";
    const CTX_DIALOG2_GIVEN = "dialog2_given";

    // If player pissed us off then we won't help them.
    if (state.night_rep[@intFromEnum(state.player.faction)] < 0) {
        tryRest(mob);
        return .Complete;
    }

    var path: ?Coord = null;
    for (state.rooms[mob.coord.z].items) |*room| {
        if (!room.is_lair)
            continue;

        const point = room.rect.randomCoord();
        if (mob.nextDirectionTo(point)) |_| {
            path = point;
            break;
        }
    }

    mob.facing = mob.coord.closestDirectionTo(state.player.coord, state.mapgeometry);

    if (path != null) {
        if (mob.canSeeMob(state.player) and state.player.canSeeMob(mob) and
            !job.ctx.get(bool, CTX_DIALOG2_GIVEN, false))
        {
            //state.dialog(mob, "I appreciate it.");
            job.ctx.set(bool, CTX_DIALOG1_GIVEN, true);
            job.ctx.set(bool, CTX_DIALOG2_GIVEN, true);
        }
        mob.ai.work_area.clearRetainingCapacity();
        mob.ai.work_area.append(path.?) catch err.wat();
        mob.ai.work_phase = .NC_MoveTo;
        mob.tryMoveTo(path.?);
        mob.prisoner_status = null;
        state.night_rep[@intFromEnum(state.player.faction)] = 1;
        return .Complete;
    } else if (mob.canSeeMob(state.player) and state.player.canSeeMob(mob) and
        !job.ctx.get(bool, CTX_DIALOG1_GIVEN, false))
    {
        state.dialog(mob, "You, human. Let me out of this cage, please?");
        job.ctx.set(bool, CTX_DIALOG1_GIVEN, true);
        tryRest(mob);
        return .Ongoing;
    } else {
        return .Defer;
    }
}

// A hack to make sure that counterattacks will happen if Revgenunkim (or other
// similar creatures) overrun a level. Because this game doesn't have "fuses"
// and won't have them either (they're hard to serialize)
//
pub fn _Job_SPC_InviteCounterattack(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const timer = job.ctx.get(usize, AIJob.CTX_COUNTERATTACK_TIMER, 50);

    if (timer > 0) {
        job.ctx.set(usize, AIJob.CTX_COUNTERATTACK_TIMER, timer - 1);
        return .Defer;
    }
    tryRest(mob);

    var mod_ancient_mage = mobs.AncientMageTemplate;
    mod_ancient_mage.squad = &[_][]const mobs.MobTemplate.SquadMember{
        &[_]mobs.MobTemplate.SquadMember{
            .{ .mob = "skeletal_blademaster", .weight = 1, .count = minmax(usize, 2, 5) },
            .{ .mob = "skeletal_arbalist", .weight = 1, .count = minmax(usize, 2, 4) },
        },
    };

    // Ordering is deliberate.
    //
    // - Place Ancient Mage first, bailing out if that's not possible.
    // - Place Necromancer second, they'll resurrect Revgen and make things more fun
    // - Death mage and death knight last. Death mage first because it's stronger.
    //

    const am = mobs.placeMobNearStairs(&mod_ancient_mage, mob.coord.z, .{}) catch return .Ongoing;

    for (&[_]*const mobs.MobTemplate{
        &mobs.TorturerNecromancerTemplate,
        &mobs.DeathMageTemplate,
        &mobs.DeathKnightTemplate,
    }) |t|
        if (state.nextSpotForMob(am.coord, null)) |spot| {
            const m = mobs.placeMob(state.alloc, t, spot, .{});
            m.ai.work_fn = patrolWork;
        } else break;

    return .Complete;
}

pub fn workJobs(mob: *Mob) bool {
    assert(mob.jobs.len > 0);
    const real_work_fn = (mob.jobs.last().?.job.func());
    const ind = mob.jobs.len - 1;
    const r = (real_work_fn)(mob, &mob.jobs.slice()[ind]);
    switch (r) {
        .Ongoing => return true,
        .Complete => {
            if (!mob.is_dead) { // Some jobs involve suicide (ie leaving floor)
                var job = mob.jobs.orderedRemove(ind) catch err.wat();
                job.deinit();
            }
            return true;
        },
        .Defer => return false,
    }
}

pub fn work(mob: *Mob) void {
    if (mob.hasStatus(.Insane)) {
        if (mob.immobile or
            !mob.moveInDirection(rng.chooseUnweighted(Direction, &DIRECTIONS)))
        {
            tryRest(mob);
        }
        return;
    }

    if (mob.ai.flag(.ScansForJobs))
        tasks.scanForCleaningJobs(mob);

    if (mob.jobs.len > 0) {
        if (workJobs(mob))
            return;
    }

    var work_fn = mob.ai.work_fn;

    if (!mob.isAloneOrLeader() and !mob.ai.flag(.ForceNormalWork)) {
        work_fn = stayNearLeaderWork;
    }

    (work_fn)(mob);
}

pub fn main(mob: *Mob) void {
    checkForLeadership(mob);

    checkForAllies(mob);
    checkForHostiles(mob);
    checkForNoises(mob);
    checkForCorpses(mob);

    // Should I wake up?
    if (mob.isUnderStatus(.Sleeping)) |_| {
        var wakeywakey = false;

        switch (mob.ai.phase) {
            .Hunt, .Investigate => wakeywakey = true,
            .Work => {
                if ((mob.ai.flag(.AwakesNearAllies) and mob.allies.items.len > 0)) {
                    wakeywakey = true;
                }
            },
            .Flee => err.bug("Fleeing mob was put to sleep...?", .{}),
        }

        const WAKING_STATUSES = [_]Status{
            .Pain, .Daze, .Enraged, .Fire, .Fear, .Water,
        };
        for (WAKING_STATUSES) |st|
            if (mob.hasStatus(st)) {
                wakeywakey = true;
                break;
            };

        if (wakeywakey) {
            mob.cancelStatus(.Sleeping);
        } else {
            tryRest(mob);
            return;
        }
    }

    // Randomly shout if insane
    if (mob.hasStatus(.Insane)) {
        if (rng.onein(10))
            mob.makeNoise(.Shout, .Loud);
    }

    // Should I flee (or stop fleeing?)
    if (mob.ai.phase == .Hunt and shouldFlee(mob)) {
        beginFlee(mob);
    } else if (mob.ai.phase == .Flee and !shouldFlee(mob)) {
        endFlee(mob);
    }

    if (mob.ai.phase == .Work) {
        work(mob);
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

        if (mob.newestJob()) |job|
            if (job.ctx.getOrNone(void, AIJob.CTX_OVERRIDE_FIGHT)) |_|
                if (workJobs(mob))
                    return;

        (mob.ai.fight_fn)(mob);
    } else if (mob.ai.phase == .Flee) {
        flee(mob);
    } else unreachable;
}
