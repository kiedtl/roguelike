const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const items = @import("items.zig");
const types = @import("types.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const display = @import("display.zig");
const utils = @import("utils.zig");

const DamageStr = types.DamageStr;
const Mob = types.Mob;
const Coord = types.Coord;
const Direction = types.Direction;
const Path = types.Path;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const DIRECTIONS = types.DIRECTIONS;
const CoordArrayList = types.CoordArrayList;

pub const CHANCE_FOR_DIP_EFFECT = 33;

const ATTACKER_ENRAGED_BONUS: isize = 20;
const ATTACKER_OPENMELEE_BONUS: isize = 10;
const ATTACKER_FEAR_NBONUS: isize = 10;
const ATTACKER_HELD_NBONUS: isize = 20;
const ATTACKER_STUN_NBONUS: isize = 15;

const DEFENDER_UNLIT_BONUS: isize = 5;
const DEFENDER_INVIGORATED_BONUS: isize = 10;
const DEFENDER_OPEN_SPACE_BONUS: isize = 10;
const DEFENDER_ENRAGED_NBONUS: isize = 10;
const DEFENDER_FLANKED_NBONUS: isize = 10;
const DEFENDER_HELD_NBONUS: isize = 10;
const DEFENDER_STUN_NBONUS: isize = 15;

pub fn damageOfMeleeAttack(attacker: *const Mob, w_damage: usize, is_stab: bool) usize {
    var damage: usize = w_damage;
    damage += if (attacker.isUnderStatus(.Enraged) != null) math.min(1, damage / 2) else 0;
    damage += if (attacker.isUnderStatus(.Invigorate) != null) math.min(1, damage / 2) else 0;

    if (is_stab) {
        damage = utils.percentOf(usize, damage, 600);
    }

    return damage;
}

pub fn chanceOfMissileLanding(attacker: *const Mob) usize {
    var chance: isize = attacker.stat(.Missile);

    chance -= if (attacker.isUnderStatus(.Debil)) |_| ATTACKER_STUN_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfMeleeLanding(attacker: *const Mob, defender: ?*const Mob) usize {
    if (defender) |d| if (isAttackStab(attacker, d)) return 100;

    var nearby_walls: isize = 0;
    for (&DIRECTIONS) |d| if (attacker.coord.move(d, state.mapgeometry)) |neighbor| {
        if (!state.is_walkable(neighbor, .{ .ignore_mobs = true, .right_now = true }))
            nearby_walls += 1;
    };

    var chance: isize = attacker.stat(.Melee);

    chance += if (attacker.isUnderStatus(.Enraged) != null) ATTACKER_ENRAGED_BONUS else 0;
    chance += if (attacker.isUnderStatus(.OpenMelee) != null and nearby_walls <= 3) ATTACKER_OPENMELEE_BONUS else 0;

    chance -= if (attacker.isUnderStatus(.Fear)) |_| ATTACKER_FEAR_NBONUS else 0;
    chance -= if (attacker.isUnderStatus(.Held)) |_| ATTACKER_HELD_NBONUS else 0;
    chance -= if (attacker.isUnderStatus(.Debil)) |_| ATTACKER_STUN_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfAttackEvaded(defender: *const Mob, attacker: ?*const Mob) usize {
    if (attacker) |a| if (isAttackStab(a, defender)) return 0;
    if (defender.immobile) return 0;

    const tile_light = state.dungeon.lightAt(defender.coord).*;

    var nearby_walls: isize = 0;
    for (&CARDINAL_DIRECTIONS) |d| if (defender.coord.move(d, state.mapgeometry)) |neighbor| {
        if (!state.is_walkable(neighbor, .{ .ignore_mobs = true, .right_now = true }))
            nearby_walls += 1;
    };

    var chance: isize = defender.stat(.Evade);

    chance += if (defender.isUnderStatus(.Invigorate)) |_| DEFENDER_INVIGORATED_BONUS else 0;
    chance += if (!defender.isFlanked() and nearby_walls == 0) DEFENDER_OPEN_SPACE_BONUS else 0;
    chance += if (!tile_light) DEFENDER_UNLIT_BONUS else 0;

    chance -= if (defender.isUnderStatus(.Held)) |_| DEFENDER_HELD_NBONUS else 0;
    chance -= if (defender.isUnderStatus(.Debil)) |_| DEFENDER_STUN_NBONUS else 0;
    chance -= if (defender.isUnderStatus(.Enraged) != null) DEFENDER_ENRAGED_NBONUS else 0;
    chance -= if (defender.isFlanked()) DEFENDER_FLANKED_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn throwMob(thrower: ?*Mob, throwee: *Mob, direction: Direction, distance: usize) void {
    const previous_coord = throwee.coord;

    var slammed_into_mob: ?*Mob = null;
    var slammed_into_something = false;
    var i: usize = 0;
    var dest_coord = throwee.coord;
    while (i < distance) : (i += 1) {
        const new = dest_coord.move(direction, state.mapgeometry) orelse break;
        if (!state.is_walkable(new, .{ .right_now = true })) {
            if (state.dungeon.at(new).mob) |mob| {
                assert(mob != throwee);
                slammed_into_mob = mob;
            }
            slammed_into_something = true;
            break;
        }
        dest_coord = new;
    }

    if (!dest_coord.eq(throwee.coord))
        assert(throwee.teleportTo(dest_coord, null, true));

    // Give damage and print messages

    display.Animation.apply(.{ .TraverseLine = .{
        .start = previous_coord,
        .end = dest_coord,
        .char = throwee.tile,
        .path_char = '×',
    } });

    if (thrower) |thrower_mob| {
        state.message(.Combat, "{c} knocks {} back!", .{ thrower_mob, throwee });
    } else {
        state.message(.Combat, "{c} is/are knocked back!", .{throwee});
    }

    if (slammed_into_something) {
        throwee.takeDamage(.{ .amount = 3.0, .by_mob = thrower }, .{ .basic = true });

        if (slammed_into_mob) |othermob| {
            othermob.takeDamage(.{ .amount = 3.0, .by_mob = throwee }, .{
                .strs = &[_]DamageStr{
                    items._dmgstr(0, "slam into", "slams into", ""),
                },
            });
        }
    }
}

// Check if an attack is a stab attack.
//
// Return true if:
// - Mob was in .Work AI phase
// - Is in Investigate/Hunt phase and:
//   - is incapitated by a status effect (e.g. Paralysis)
//
// Return false if:
// - Attacker isn't right next to defender
//
// Player is always aware of attacks. Stabs are there in the first place to
// "reward" the player for catching a hostile off guard, but allowing enemies
// to stab a paralyzed player is too harsh of a punishment.
//
pub fn isAttackStab(attacker: *const Mob, defender: *const Mob) bool {
    if (defender.coord.eq(state.player.coord))
        return false;

    return switch (defender.ai.phase) {
        .Flee, .Hunt, .Investigate => b: {
            if (defender.isUnderStatus(.Paralysis)) |_| break :b true;
            if (defender.isUnderStatus(.Daze)) |_| break :b true;

            if (defender.ai.phase == .Flee and !defender.cansee(attacker.coord)) {
                break :b true;
            }

            break :b false;
        },
        .Work => true,
    };
}

// Algorithm to shave damage due to resistance
pub fn shaveDamage(amount: f64, resist: isize) f64 {
    var new_amount: f64 = 0;
    var ctr = @floatToInt(usize, amount);
    while (ctr > 0) : (ctr -= 1) {
        new_amount += 1;

        if (resist > 0) {
            if (rng.percent(resist)) {
                new_amount -= 1;
            }
        } else if (resist < 0) {
            if (rng.percent(-resist)) {
                new_amount += 1;
            }
        }
    }
    return new_amount;
}

test {
    try rng.init(std.testing.allocator);

    var i: usize = 10;
    while (i > 0) : (i -= 1) {
        var resist = rng.range(isize, -4, 4) * 25;
        var damage = @intToFloat(f64, rng.range(usize, 1, 9));
        var ndmg = shaveDamage(damage, resist);
        _ = ndmg;
        // std.log.warn("damage: {}\tresist: {}\tnew: {}\tshaved: {}", .{
        //     damage, resist, ndmg, @intCast(isize, damage) - @intCast(isize, ndmg),
        // });
    }
}
