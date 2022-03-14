const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const items = @import("items.zig");
usingnamespace @import("types.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");

const ATTACKER_ENRAGED_BONUS: isize = 20;
const ATTACKER_HELD_NBONUS: isize = 20;

const DEFENDER_UNLIT_BONUS: isize = 5;
const DEFENDER_INVIGORATED_BONUS: isize = 10;
const DEFENDER_ENRAGED_NBONUS: isize = 10;
const DEFENDER_OPEN_SPACE_BONUS: isize = 10;
const DEFENDER_FLANKED_NBONUS: isize = 10;
const DEFENDER_HELD_NBONUS: isize = 10;
const DEFENDER_STEALTH_BONUS: isize = 5;

pub fn damageOutput(attacker: *const Mob, recipient: *const Mob, weapon_damage: usize, is_stab: bool) usize {
    const recipient_armor = recipient.inventory.armor orelse &items.NoneArmor;
    const max_damage = weapon_damage - (weapon_damage * recipient_armor.shave / 100);

    var damage: usize = 0;
    damage += rng.rangeClumping(usize, max_damage / 2, max_damage, 2);
    damage += if (attacker.isUnderStatus(.Enraged) != null) damage / 5 else 0;
    damage += damage * (attacker.strength() / 2) / 100;

    if (is_stab) {
        damage = utils.percentOf(usize, damage, 600);
    }

    return damage;
}

pub fn chanceOfMissileLanding(attacker: *const Mob) usize {
    var chance: isize = @intCast(isize, attacker.base_missile);

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfMeleeLanding(attacker: *const Mob) usize {
    var chance: isize = @intCast(isize, attacker.base_melee);

    chance += if (attacker.isUnderStatus(.Enraged) != null) ATTACKER_ENRAGED_BONUS else 0;

    chance -= if (attacker.isUnderStatus(.Held)) |_| ATTACKER_HELD_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfAttackEvaded(defender: *const Mob, attacker: ?*const Mob) usize {
    if (attacker) |a|
        if (!defender.isAwareOfAttack(a.coord)) return 0;
    if (defender.immobile) return 0;

    const tile_light = state.dungeon.lightAt(defender.coord).*;

    var nearby_walls: isize = 0;
    for (&CARDINAL_DIRECTIONS) |d| if (defender.coord.move(d, state.mapgeometry)) |neighbor| {
        if (!state.is_walkable(neighbor, .{ .ignore_mobs = true, .right_now = true }))
            nearby_walls += 1;
    };

    var chance: isize = @intCast(isize, defender.base_evasion);

    chance += @intCast(isize, defender.stealth()) * DEFENDER_STEALTH_BONUS;
    chance += if (defender.isUnderStatus(.Invigorate)) |_| DEFENDER_INVIGORATED_BONUS else 0;
    chance += if (!defender.isFlanked() and nearby_walls == 0) DEFENDER_OPEN_SPACE_BONUS else 0;
    chance += if (!tile_light) DEFENDER_UNLIT_BONUS else 0;

    chance -= if (defender.inventory.armor) |a| if (a.evasion_penalty) |pen| @intCast(isize, pen) else 0 else 0;
    chance -= if (defender.isUnderStatus(.Held)) |_| DEFENDER_HELD_NBONUS else 0;
    chance -= if (defender.isUnderStatus(.Enraged) != null) DEFENDER_ENRAGED_NBONUS else 0;
    chance -= if (defender.isFlanked()) DEFENDER_FLANKED_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}
