const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const items = @import("items.zig");
usingnamespace @import("types.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");

const CHANCE_OF_AUTO_HIT = 14;
const CHANCE_OF_AUTO_MISS = 14;

const ATTACKER_ENRAGED_BONUS: isize = 20;
const ATTACKER_HELD_NBONUS: isize = 20;

const DEFENDER_UNLIT_BONUS: isize = 10;
const DEFENDER_ENRAGED_NBONUS: isize = 10;
const DEFENDER_FLANKED_NBONUS: isize = 10;
const DEFENDER_HELD_NBONUS: isize = 10;
const DEFENDER_STEALTH_BONUS: isize = 7;

pub fn damageOutput(attacker: *const Mob, recipient: *const Mob, weapon_damages: Damages, main_damage: DamageType, is_stab: bool) usize {
    const recipient_armor = recipient.inventory.armor orelse &items.NoneArmor;
    const max_damage = weapon_damages.resultOf(&recipient_armor.resists).sum();

    var damage: usize = 0;
    damage += rng.rangeClumping(usize, max_damage / 2, max_damage, 2);
    damage += if (attacker.isUnderStatus(.Enraged) != null) damage / 5 else 0;
    damage += damage * (attacker.strength() / 2) / 100;

    if (is_stab) {
        const bonus = DamageType.stabBonus(main_damage);
        damage = utils.percentOf(usize, damage, bonus);
    }

    return damage;
}

pub fn chanceOfAttackLanding(attacker: *const Mob) usize {
    if (rng.onein(CHANCE_OF_AUTO_HIT)) return 100;
    if (rng.onein(CHANCE_OF_AUTO_MISS)) return 0;

    var chance: isize = 80;

    chance += if (attacker.isUnderStatus(.Enraged) != null) ATTACKER_ENRAGED_BONUS else 0;

    chance -= if (attacker.isUnderStatus(.Held)) |_| ATTACKER_HELD_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfAttackDodged(defender: *const Mob, attacker: ?*const Mob) usize {
    if (attacker) |a|
        if (!defender.isAwareOfAttack(a.coord)) return 0;
    if (defender.immobile) return 0;

    const tile_light = state.dungeon.lightAt(defender.coord).*;

    var neighboring_walls: isize = 0;
    for (&CARDINAL_DIRECTIONS) |d| if (defender.coord.move(d, state.mapgeometry)) |neighbor| {
        if (!state.is_walkable(neighbor, .{ .ignore_mobs = true, .right_now = true }))
            neighboring_walls += 1;
    };

    var chance: isize = @intCast(isize, defender.dexterity());

    chance += (4 - neighboring_walls) * 4; // +4-16%
    chance += @intCast(isize, defender.stealth()) * DEFENDER_STEALTH_BONUS;
    chance += if (!tile_light) DEFENDER_UNLIT_BONUS else 0;

    chance -= if (defender.isUnderStatus(.Held)) |_| DEFENDER_HELD_NBONUS else 0;
    chance -= if (defender.isUnderStatus(.Enraged) != null) DEFENDER_ENRAGED_NBONUS else 0;
    chance -= if (defender.isFlanked()) DEFENDER_FLANKED_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}
