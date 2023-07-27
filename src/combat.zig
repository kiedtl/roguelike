const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const ai = @import("ai.zig");
const items = @import("items.zig");
const types = @import("types.zig");
const player = @import("player.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const DamageStr = types.DamageStr;
const Mob = types.Mob;
const Coord = types.Coord;
const Direction = types.Direction;
const Weapon = types.Weapon;
const Path = types.Path;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const DIRECTIONS = types.DIRECTIONS;
const CoordArrayList = types.CoordArrayList;

pub const CHANCE_FOR_DIP_EFFECT = 33;

const ATTACKER_ENRAGED_BONUS: isize = 20;
const ATTACKER_INVIGORATED_BONUS: isize = 10;
const ATTACKER_FEAR_NBONUS: isize = 10;
const ATTACKER_HELD_NBONUS: isize = 20;
const ATTACKER_STUN_NBONUS: isize = 15;

const DEFENDER_UNLIT_BONUS: isize = 5;
const DEFENDER_ESHIELD_BONUS: isize = 7; // (per wall, so +7..49)
const DEFENDER_INVIGORATED_BONUS: isize = 10;
const DEFENDER_OPEN_SPACE_BONUS: isize = 10;
const DEFENDER_ENRAGED_NBONUS: isize = 10;
const DEFENDER_RECUPERATE_NBONUS: isize = 10;
const DEFENDER_HELD_NBONUS: isize = 10;
const DEFENDER_STUN_NBONUS: isize = 15;

pub const WeaponDamageInfo = struct {
    total: usize,
    bone_bonus: bool = false,
    bone_nbonus: bool = false,
    copper_bonus: bool = false,
};

pub fn damageOfWeapon(attacker: ?*const Mob, weapon: *const Weapon, recipient: ?*const Mob) WeaponDamageInfo {
    var damage = WeaponDamageInfo{ .total = weapon.damage };

    if (attacker != null and recipient != null) {
        // If attacker is corrupted and defender is living, +1 dmg.
        if (attacker.?.isUnderStatus(.Corruption) != null and recipient.?.life_type == .Living) {
            damage.total += 1;
        }
    }
    if (attacker != null) {
        // If copper weapon and attacker is on copper ground, +3 damage.
        if (weapon.ego == .Copper and attacker.?.isUnderStatus(.CopperWeapon) != null) {
            damage.total += 3;
            damage.copper_bonus = true;
        }
    }
    if (recipient != null) {
        // If bone weapon and defender is living and not corrupted, +1 dmg.
        if (weapon.ego == .Bone and recipient.?.life_type == .Living and
            recipient.?.isUnderStatus(.Corruption) == null)
        {
            damage.total += 1;
            damage.bone_bonus = true;
        }
        // If bone weapon and defender is undead, -1 dmg.
        if (weapon.ego == .Bone and recipient.?.life_type == .Undead) {
            damage.total -= 1;
            damage.bone_nbonus = true;
        }
    }

    return damage;
}

pub fn damageOfMeleeAttack(attacker: *const Mob, w_damage: usize, is_stab: bool) usize {
    var damage: usize = w_damage;
    damage += if (attacker.isUnderStatus(.Enraged) != null) math.min(1, damage / 2) else 0;
    damage += if (attacker.isUnderStatus(.Invigorate) != null) math.min(1, damage / 2) else 0;

    if (is_stab) {
        damage *= 10;
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
    chance += if (attacker.isUnderStatus(.Invigorate) != null) ATTACKER_INVIGORATED_BONUS else 0;
    chance -= if (attacker.isUnderStatus(.Fear)) |_| ATTACKER_FEAR_NBONUS else 0;
    chance -= if (attacker.isUnderStatus(.Held)) |_| ATTACKER_HELD_NBONUS else 0;
    chance -= if (attacker.isUnderStatus(.Debil)) |_| ATTACKER_STUN_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfAttackEvaded(defender: *const Mob, attacker: ?*const Mob) usize {
    if (attacker) |a| if (isAttackStab(a, defender)) return 0;
    if (defender.immobile) return 0;

    const walls = @intCast(isize, state.dungeon.neighboringWalls(defender.coord, true));

    var chance: isize = defender.stat(.Evade);

    chance += if (defender.hasStatus(.Invigorate)) DEFENDER_INVIGORATED_BONUS else 0;
    chance += if (defender.hasStatus(.EarthenShield)) walls * DEFENDER_ESHIELD_BONUS else 0;

    chance -= if (defender.hasStatus(.Held)) DEFENDER_HELD_NBONUS else 0;
    chance -= if (defender.hasStatus(.Debil)) DEFENDER_STUN_NBONUS else 0;
    chance -= if (defender.hasStatus(.Recuperate)) DEFENDER_RECUPERATE_NBONUS else 0;
    chance -= if (defender.hasStatus(.Enraged)) DEFENDER_ENRAGED_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn throwMob(thrower: ?*Mob, throwee: *Mob, direction: Direction, distance: usize) void {
    if (throwee.immobile or throwee.multitile != null) {
        return; // Don't do anything if throwee is immobile or multitile.
    }

    if (thrower) |enemy| {
        ai.updateEnemyKnowledge(throwee, enemy, null);
    }

    const previous_coord = throwee.coord;

    var slammed_into_mob: ?*Mob = null;
    var slammed_into_something = false;
    var i: usize = 0;
    var dest_coord = throwee.coord;
    while (i < distance) : (i += 1) {
        const new = dest_coord.move(direction, state.mapgeometry) orelse break;
        if (!state.is_walkable(new, .{ .right_now = true, .only_if_breaks_lof = true })) {
            if (state.dungeon.at(new).mob) |mob| {
                assert(mob != throwee);
                slammed_into_mob = mob;
            }
            slammed_into_something = true;
            break;
        }
        dest_coord = new;
    }

    // Do animation before actually moving mob
    //
    ui.Animation.apply(.{ .TraverseLine = .{
        .start = previous_coord,
        .end = dest_coord,
        .char = throwee.tile,
        .path_char = '×',
    } });

    if (!dest_coord.eq(throwee.coord))
        assert(throwee.teleportTo(dest_coord, null, true, false));

    // Give damage and print messages

    if (player.canSeeAny(&.{
        @as(?Coord, if (thrower) |m| m.coord else null),
        previous_coord,
        dest_coord,
    })) {
        if (thrower) |thrower_mob| {
            thrower_mob.makeNoise(.Combat, .Loud);
            state.message(.Combat, "{c} knocks {} back!", .{ thrower_mob, throwee });
            state.markMessageNoisy();
        } else {
            throwee.makeNoise(.Combat, .Loud);
            state.message(.Combat, "{c} is/are knocked back!", .{throwee});
            state.markMessageNoisy();
        }
    }

    if (slammed_into_something) {
        throwee.takeDamage(.{ .amount = 3, .by_mob = thrower }, .{ .basic = true });

        if (slammed_into_mob) |othermob| {
            othermob.takeDamage(.{ .amount = 3, .by_mob = throwee }, .{
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
    if (defender.life_type != .Living)
        return false;

    return switch (defender.ai.phase) {
        .Flee, .Hunt, .Investigate => b: {
            if (defender.isUnderStatus(.Paralysis)) |_| break :b true;
            // if (defender.isUnderStatus(.Daze)) |_| break :b true;

            if (defender.ai.phase == .Flee and !defender.cansee(attacker.coord)) {
                break :b true;
            }

            break :b false;
        },
        .Work => b: {
            if (defender.hasStatus(.Amnesia) and ai.isEnemyKnown(defender, attacker)) {
                break :b false;
            } else {
                break :b true;
            }
        },
    };
}

// Algorithm to shave damage due to resistance
pub fn shaveDamage(amount: usize, resist: isize) usize {
    //assert(amount > 0);
    assert(resist >= -100 and resist <= 100);

    const S = struct {
        pub fn _helper(a: usize, r: isize) isize {
            var n: isize = 0;
            var ctr = a;
            while (ctr > 0) : (ctr -= 1) {
                n += 1;

                if (r > 0) {
                    if (rng.percent(r)) {
                        n -= 1;
                    }
                } else if (r < 0) {
                    if (rng.percent(-r)) {
                        n += 1;
                    }
                }
            }
            return n;
        }
    };

    return @intCast(usize, @divTrunc(S._helper(amount, resist) + S._helper(amount, resist) + S._helper(amount, resist), 3));
}

// This doesn't really belong here, but where else would I put it
//
// Apply disruption effects based on how many candles have been extinguished.
pub fn disruptAllUndead(level: usize) void {
    const UNDEAD_DISRUPT_DESTROY_CHANCE = 5; // Min: 5% (one candle), max: 40% (8 candles)
    const UNDEAD_DISRUPT_MELEE_DECREASE = 2; // Min: -2% (one candle), max: -16% (8 candles)
    const UNDEAD_DISRUPT_WILL_FDECREASE = 4; // Min: -0 (one candle), max: -2 (8 candles)
    const UNDEAD_DISRUPT_HLTH_FDECREASE = 2; // Min: -0 (one candle), max: -4 (8 candles)

    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
        if (mob.coord.z != level or mob.is_dead or mob.life_type != .Undead or mob.faction != .Necromancer)
            continue;

        mob.stats.Melee -|= @intCast(isize, state.destroyed_candles * UNDEAD_DISRUPT_MELEE_DECREASE);
        mob.stats.Willpower -|= @intCast(isize, state.destroyed_candles / UNDEAD_DISRUPT_WILL_FDECREASE);
        mob.max_HP -|= state.destroyed_candles / UNDEAD_DISRUPT_HLTH_FDECREASE;

        if (mob.max_HP == 0 or rng.percent(state.destroyed_candles * UNDEAD_DISRUPT_DESTROY_CHANCE))
            mob.deinit();
    }
}

pub fn disruptIndividualUndead(mob: *Mob) void {
    assert(mob.life_type == .Undead and !mob.is_dead);

    const candles = state.destroyed_candles;
    if (candles == 0)
        return;

    // Nomenclature: NLIN == "normal linear", == chance * candles
    //               HLIN == "half linear", == chance * (candles / 2)
    //               SAME == constant chance, always same regardless of candles
    //                       (used for really strong effects)
    //
    const CHANCE_NLIN_FORGET_ENEMY = 2; // Range: 2..16
    const CHANCE_NLIN_ATTACK_ALLY = 3; // Range: 2..16
    const CHANCE_HLIN_GAIN_BLIND = 1; // Range: 1..8
    const CHANCE_HLIN_GAIN_DISORIENT = 1; // Range: 1..8
    const CHANCE_SAME_GAIN_PARALYSIS = 2; // Range: always 2

    const adjacent_ally: ?*Mob = for (&DIRECTIONS) |d| {
        if (utils.getMobInDirection(mob, d)) |othermob| {
            if (othermob.faction == mob.faction) {
                break mob;
            }
        } else |_| {}
    } else null;

    var msg: []const u8 = undefined;

    if (rng.percent(CHANCE_NLIN_FORGET_ENEMY * candles)) {
        const enemylist = mob.enemyList();
        assert(enemylist.items.len > 0);
        _ = enemylist.swapRemove(rng.range(usize, 0, enemylist.items.len - 1));
        msg = "forget enemy";
    } else if (rng.percent(CHANCE_NLIN_ATTACK_ALLY * candles) and adjacent_ally != null) {
        mob.fight(adjacent_ally.?, .{ .free_attack = true });
        msg = "attack ally";
    } else if (rng.percent(CHANCE_HLIN_GAIN_BLIND * (candles / 2))) {
        mob.addStatus(.Blind, 0, .{ .Tmp = rng.range(usize, 7, 14) });
        msg = "blindness";
    } else if (rng.percent(CHANCE_HLIN_GAIN_DISORIENT * (candles / 2))) {
        mob.addStatus(.Disorient, 0, .{ .Tmp = rng.range(usize, 7, 14) });
        msg = "disorientation";
    } else if (rng.percent(CHANCE_SAME_GAIN_PARALYSIS)) {
        mob.addStatus(.Paralysis, 0, .{ .Tmp = rng.range(usize, 7, 14) });
        msg = "paralysis";
    } else return;

    if (state.player.canSeeMob(mob)) {
        state.message(.Status, "{c} is disrupted ($b{s}$.)", .{ mob, msg });
    }
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
        //     damage, resist, ndmg, @floatToInt(isize, damage) - @floatToInt(isize, ndmg),
        // });
    }
}
