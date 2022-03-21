const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const items = @import("items.zig");
const types = @import("types.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");

const Mob = types.Mob;
const Coord = types.Coord;
const Direction = types.Direction;
const Path = types.Path;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const CoordArrayList = types.CoordArrayList;

const ATTACKER_ENRAGED_BONUS: isize = 20;
const ATTACKER_HELD_NBONUS: isize = 20;

const DEFENDER_UNLIT_BONUS: isize = 5;
const DEFENDER_INVIGORATED_BONUS: isize = 10;
const DEFENDER_ENRAGED_NBONUS: isize = 10;
const DEFENDER_OPEN_SPACE_BONUS: isize = 10;
const DEFENDER_FLANKED_NBONUS: isize = 10;
const DEFENDER_HELD_NBONUS: isize = 10;
const DEFENDER_CAMOFLAGE_BONUS: isize = 5;

pub fn damageOfMeleeAttack(attacker: *const Mob, w_damage: usize, is_stab: bool) usize {
    var damage: usize = 0;
    damage += rng.rangeClumping(usize, w_damage / 2, w_damage, 2);
    damage += if (attacker.isUnderStatus(.Enraged) != null) damage / 5 else 0;
    damage += damage * (@intCast(usize, attacker.stat(.Strength)) / 2) / 100;

    if (is_stab) {
        damage = utils.percentOf(usize, damage, 600);
    }

    return damage;
}

pub fn chanceOfMissileLanding(attacker: *const Mob) usize {
    var chance: isize = attacker.stat(.Missile);

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfMeleeLanding(attacker: *const Mob, defender: ?*const Mob) usize {
    if (defender) |d| if (!d.isAwareOfAttack(attacker.coord)) return 100;

    var chance: isize = attacker.stat(.Melee);

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

    var chance: isize = defender.stat(.Evade);

    chance += @intCast(isize, defender.stat(.Camoflage)) * DEFENDER_CAMOFLAGE_BONUS;
    chance += if (defender.isUnderStatus(.Invigorate)) |_| DEFENDER_INVIGORATED_BONUS else 0;
    chance += if (!defender.isFlanked() and nearby_walls == 0) DEFENDER_OPEN_SPACE_BONUS else 0;
    chance += if (!tile_light) DEFENDER_UNLIT_BONUS else 0;

    chance -= if (defender.inventory.armor) |a| if (a.evasion_penalty) |pen| @intCast(isize, pen) else 0 else 0;
    chance -= if (defender.isUnderStatus(.Held)) |_| DEFENDER_HELD_NBONUS else 0;
    chance -= if (defender.isUnderStatus(.Enraged) != null) DEFENDER_ENRAGED_NBONUS else 0;
    chance -= if (defender.isFlanked()) DEFENDER_FLANKED_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}
