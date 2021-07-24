const std = @import("std");
const math = std.math;

const items = @import("items.zig");
usingnamespace @import("types.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");

const CHANCE_OF_AUTO_HIT = 20;
const CHANCE_OF_AUTO_MISS = 20;

const DEFENDER_HELD_BONUS: isize = 60;
const GREATER_DEXTERITY_BONUS: isize = 10;
const DOUBLE_GREATER_DEXTERITY_BONUS: isize = 20;
const FULL_LIGHT_BONUS: isize = 10;

const ATTACKER_HELD_NBONUS: isize = 14;
const DIM_LIGHT_NBONUS: isize = 10;
const LOW_DEXTERITY_NBONUS: isize = 10;
const LOW_STRENGTH_NBONUS: isize = 10;

const GREATER_DEXTERITY_DODGE_BONUS: isize = 10;
const DOUBLE_GREATER_DEXTERITY_DODGE_BONUS: isize = 10;

// TODO: weapon/armor penalties

pub fn chanceOfAttackLanding(attacker: *const Mob, defender: *const Mob) usize {
    if (!defender.isAwareOfAttack(attacker.coord)) return 100;

    if (rng.onein(CHANCE_OF_AUTO_HIT)) return 100;
    if (rng.onein(CHANCE_OF_AUTO_MISS)) return 0;

    const tile_light = state.dungeon.lightIntensityAt(defender.coord).*;
    const attacker_weapon = attacker.inventory.wielded orelse &items.UnarmedWeapon;

    var chance: isize = 60;

    chance += if (defender.isUnderStatus(.Held)) |_| DEFENDER_HELD_BONUS else 0;
    chance += if (attacker.dexterity() > defender.dexterity()) GREATER_DEXTERITY_BONUS else 0;
    chance += if (attacker.dexterity() > (defender.dexterity() * 2)) DOUBLE_GREATER_DEXTERITY_BONUS else 0;
    chance += @intCast(isize, Mob.MAX_ACTIVITY_BUFFER_SZ - defender.turnsSinceRest()) * 3;
    chance += if (tile_light == 100) FULL_LIGHT_BONUS else 0;

    chance -= if (attacker.isUnderStatus(.Held)) |_| ATTACKER_HELD_NBONUS else 0;
    chance -= if (tile_light < attacker.night_vision) DIM_LIGHT_NBONUS else 0;
    chance -= if (attacker.dexterity() < attacker_weapon.required_dexterity) LOW_DEXTERITY_NBONUS else 0;
    chance -= if (attacker.strength() < attacker_weapon.required_strength) LOW_STRENGTH_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfAttackDodged(defender: *const Mob, attacker: *const Mob) usize {
    if (!defender.isAwareOfAttack(attacker.coord)) return 0;
    if (defender.isUnderStatus(.Held)) |_| return 0;

    const neighboring_walls = @intCast(isize, state.dungeon.neighboringWalls(defender.coord, true));

    var chance: isize = 10;

    chance += if (defender.dexterity() > attacker.dexterity()) GREATER_DEXTERITY_DODGE_BONUS else 0;
    chance += if (defender.dexterity() > (attacker.dexterity() * 2)) DOUBLE_GREATER_DEXTERITY_DODGE_BONUS else 0;
    chance += (9 - neighboring_walls) * 3;

    return @intCast(usize, math.clamp(chance, 0, 100));
}
