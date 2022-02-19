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

const FULL_LIGHT_BONUS: isize = 14;

const ATTACKER_HELD_NBONUS: isize = 21;
const DIM_LIGHT_NBONUS: isize = 14;

const DEFENDER_HELD_NBONUS: isize = 14;

pub fn damageOutput(attacker: *const Mob, recipient: *const Mob, is_stab: bool) usize {
    const weapon = attacker.inventory.wielded orelse &items.UnarmedWeapon;

    const recipient_armor = recipient.inventory.armor orelse &items.NoneArmor;
    const max_damage = weapon.damages.resultOf(&recipient_armor.resists).sum();

    var damage: usize = 0;
    damage += rng.rangeClumping(usize, max_damage / 2, max_damage, 2);

    if (is_stab) {
        const bonus = DamageType.stabBonus(weapon.main_damage);
        damage = utils.percentOf(usize, damage, bonus);
    }

    return damage;
}

pub fn chanceOfAttackLanding(attacker: *const Mob, defender: *const Mob) usize {
    if (!defender.isAwareOfAttack(attacker.coord)) return 100;

    if (rng.onein(CHANCE_OF_AUTO_HIT)) return 100;
    if (rng.onein(CHANCE_OF_AUTO_MISS)) return 0;

    const tile_light = state.dungeon.lightIntensityAt(defender.coord).*;
    const attacker_weapon = attacker.inventory.wielded orelse &items.UnarmedWeapon;

    var chance: isize = 60;

    chance += if (tile_light == 100) FULL_LIGHT_BONUS else 0;

    chance -= if (attacker.isUnderStatus(.Held)) |_| ATTACKER_HELD_NBONUS else 0;
    chance -= if (!attacker.vision_range().contains(tile_light)) DIM_LIGHT_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfAttackDodged(defender: *const Mob, attacker: ?*const Mob) usize {
    if (attacker) |a|
        if (!defender.isAwareOfAttack(a.coord)) return 0;
    if (defender.immobile) return 0;

    const neighboring_walls = @intCast(isize, state.dungeon.neighboringWalls(defender.coord, true));

    var chance: isize = @intCast(isize, defender.dexterity());

    chance += (9 - neighboring_walls) * 3; // +3-27%
    chance -= if (defender.isUnderStatus(.Held)) |_| DEFENDER_HELD_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}
