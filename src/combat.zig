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
const DIRECTIONS = types.DIRECTIONS;
const CoordArrayList = types.CoordArrayList;

pub const CHANCE_FOR_DIP_EFFECT = 33;

const ATTACKER_ENRAGED_BONUS: isize = 20;
const ATTACKER_OPENMELEE_BONUS: isize = 10;
const ATTACKER_HELD_NBONUS: isize = 20;
const ATTACKER_STUN_NBONUS: isize = 10;

const DEFENDER_UNLIT_BONUS: isize = 5;
const DEFENDER_INVIGORATED_BONUS: isize = 10;
const DEFENDER_OPEN_SPACE_BONUS: isize = 10;
const DEFENDER_ENRAGED_NBONUS: isize = 10;
const DEFENDER_FLANKED_NBONUS: isize = 10;
const DEFENDER_HELD_NBONUS: isize = 10;
const DEFENDER_STUN_NBONUS: isize = 10;

pub fn damageOfMeleeAttack(attacker: *const Mob, w_damage: usize, is_stab: bool) usize {
    var damage: usize = w_damage;
    damage += if (attacker.isUnderStatus(.Enraged) != null) damage / 5 else 0;

    if (is_stab) {
        damage = utils.percentOf(usize, damage, 600);
    }

    return damage;
}

pub fn chanceOfMissileLanding(attacker: *const Mob) usize {
    var chance: isize = attacker.stat(.Missile);

    chance -= if (attacker.isUnderStatus(.Stun)) |_| ATTACKER_STUN_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn chanceOfMeleeLanding(attacker: *const Mob, defender: ?*const Mob) usize {
    if (defender) |d| if (!d.isAwareOfAttack(attacker.coord)) return 100;

    var nearby_walls: isize = 0;
    for (&DIRECTIONS) |d| if (attacker.coord.move(d, state.mapgeometry)) |neighbor| {
        if (!state.is_walkable(neighbor, .{ .ignore_mobs = true, .right_now = true }))
            nearby_walls += 1;
    };

    var chance: isize = attacker.stat(.Melee);

    chance += if (attacker.isUnderStatus(.Enraged) != null) ATTACKER_ENRAGED_BONUS else 0;
    chance += if (attacker.isUnderStatus(.OpenMelee) != null and nearby_walls <= 3) ATTACKER_OPENMELEE_BONUS else 0;

    chance -= if (attacker.isUnderStatus(.Held)) |_| ATTACKER_HELD_NBONUS else 0;
    chance -= if (attacker.isUnderStatus(.Stun)) |_| ATTACKER_STUN_NBONUS else 0;

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

    chance += if (defender.isUnderStatus(.Invigorate)) |_| DEFENDER_INVIGORATED_BONUS else 0;
    chance += if (!defender.isFlanked() and nearby_walls == 0) DEFENDER_OPEN_SPACE_BONUS else 0;
    chance += if (!tile_light) DEFENDER_UNLIT_BONUS else 0;

    chance -= if (defender.isUnderStatus(.Held)) |_| DEFENDER_HELD_NBONUS else 0;
    chance -= if (defender.isUnderStatus(.Stun)) |_| DEFENDER_STUN_NBONUS else 0;
    chance -= if (defender.isUnderStatus(.Enraged) != null) DEFENDER_ENRAGED_NBONUS else 0;
    chance -= if (defender.isFlanked()) DEFENDER_FLANKED_NBONUS else 0;

    return @intCast(usize, math.clamp(chance, 0, 100));
}

pub fn throwMob(thrower: ?*Mob, throwee: *Mob, direction: Direction, distance: usize) void {
    state.messageAboutMob(throwee, throwee.coord, .Combat, "are knocked back!", .{}, "is knocked back!", .{});

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

    // Give damage
    if (slammed_into_something) {
        throwee.takeDamage(.{
            .amount = throwee.HP / 20,
            .by_mob = thrower,
        });

        if (slammed_into_mob) |othermob| {
            othermob.takeDamage(.{
                .amount = othermob.HP / 20,
                .by_mob = thrower,
            });
        }
    }
}
