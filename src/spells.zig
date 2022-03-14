// Spells are, basically, any ranged attack that doesn't come from a projectile.
//
// They can be fired by machines as well as monsters; when fired by monsters,
// they could be "natural" abilities (e.g., a drake's breath).
//

const std = @import("std");
const meta = std.meta;
const math = std.math;

usingnamespace @import("types.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const items = @import("items.zig");
const gas = @import("gas.zig");
const mobs = @import("mobs.zig");
const sound = @import("sound.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");
const rng = @import("rng.zig");

pub const CAST_MASS_DISMISSAL = Spell{
    .name = "mass dismissal",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = _hasEffectMassDismissal,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectMassDismissal },
};
fn _hasEffectMassDismissal(caster: *Mob, spell: SpellOptions, target: Coord) bool {
    for (caster.enemies.items) |enemy_record| {
        if (caster.cansee(enemy_record.mob.coord) and
            !enemy_record.mob.is_undead and
            enemy_record.mob.isUnderStatus(.Fear) == null)
        {
            return true;
        }
    }
    return false;
}
fn _effectMassDismissal(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const caster_mob = state.dungeon.at(caster).mob.?;

    for (caster_mob.enemies.items) |enemy_record| {
        if (caster_mob.cansee(enemy_record.mob.coord) and
            !enemy_record.mob.is_undead and
            enemy_record.mob.isUnderStatus(.Fear) == null)
        {
            if (!willSucceedAgainstMob(caster_mob, enemy_record.mob))
                continue;
            enemy_record.mob.addStatus(.Fear, 0, opts.power, false);
        }
    }
}

pub const CAST_SUMMON_ENEMY = Spell{
    .name = "summon enemy",
    .cast_type = .Smite,
    .smite_target_type = .Mob,
    .checks_will = true,
    .needs_visible_target = false,
    .check_has_effect = _hasEffectSummonEnemy,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectSummonEnemy },
};
fn _hasEffectSummonEnemy(caster: *Mob, spell: SpellOptions, target: Coord) bool {
    const mob = state.dungeon.at(target).mob.?;
    return (mob == state.player or mob.ai.phase == .Flee) and
        !caster.cansee(mob.coord);
}
fn _effectSummonEnemy(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const caster_mob = state.dungeon.at(caster).mob.?;
    const target_mob = state.dungeon.at(coord).mob.?;

    // Find a spot in caster's LOS
    var new: ?Coord = null;
    var farthest_dist: usize = 0;
    for (caster_mob.fov) |row, y| {
        for (row) |cell, x| {
            const fitem = Coord.new2(caster_mob.coord.z, x, y);
            const dist = fitem.distance(caster);
            if (cell == 0 or dist == 1)
                continue;
            if (state.is_walkable(fitem, .{ .right_now = true })) {
                if (dist > farthest_dist) {
                    farthest_dist = dist;
                    new = fitem;
                }
            }
        }
    }

    if (new) |newcoord| {
        _ = target_mob.teleportTo(newcoord, null, true);

        state.messageAboutMob(target_mob, caster, .SpellCast, "are dragged back to the {}!", .{caster_mob.displayName()}, "is dragged back to the {}!", .{caster_mob.displayName()});
    }
}

pub const CAST_AURA_DISPERSAL = Spell{
    .name = "aura of dismissal",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = _hasEffectAuraDispersal,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectAuraDispersal },
};
fn _hasEffectAuraDispersal(caster: *Mob, spell: SpellOptions, target: Coord) bool {
    for (&DIRECTIONS) |d| if (target.move(d, state.mapgeometry)) |neighbor| {
        if (state.dungeon.at(neighbor).mob) |mob|
            if (mob.isHostileTo(caster)) {
                return true;
            };
    };
    return false;
}
fn _effectAuraDispersal(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const caster_mob = state.dungeon.at(caster).mob.?;
    var had_visible_effect = false;
    for (&DIRECTIONS) |d| if (caster.move(d, state.mapgeometry)) |neighbor| {
        if (state.dungeon.at(neighbor).mob) |mob|
            if (mob.isHostileTo(caster_mob)) {
                // Find a new home
                var new: ?Coord = null;
                var farthest_dist: usize = 0;
                for (caster_mob.fov) |row, y| {
                    for (row) |cell, x| {
                        const fitem = Coord.new2(caster_mob.coord.z, x, y);
                        const dist = fitem.distance(caster);
                        if (cell == 0 or dist == 1)
                            continue;
                        if (state.is_walkable(fitem, .{ .right_now = true })) {
                            if (dist > farthest_dist) {
                                farthest_dist = dist;
                                new = fitem;
                            }
                        }
                    }
                }
                if (new) |newcoord| {
                    _ = mob.teleportTo(newcoord, null, true);
                    mob.addStatus(.Daze, 2, 0, false);
                    mob.takeDamage(.{ .amount = 10, .source = .RangedAttack });
                    if (state.player.cansee(mob.coord) or state.player.cansee(caster))
                        had_visible_effect = true;
                }
            };
    };

    if (had_visible_effect)
        state.message(.SpellCast, "Space bends horribly around the {}!", .{
            caster_mob.displayName(),
        });
}

pub const CAST_CONJ_BALL_LIGHTNING = Spell{
    .name = "conjure ball lightning",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectConjureBL },
};
fn _effectConjureBL(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, .{ .right_now = true })) {
            // FIXME: passing allocator directly is anti-pattern?
            const w = mobs.placeMob(&state.GPA.allocator, &mobs.BallLightningTemplate, neighbor, .{});
            w.addStatus(.Lifespan, 0, opts.power, false);
            return;
        }
    };
}

pub const BOLT_CRYSTAL = Spell{
    .name = "crystal shard",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_multitarget = false,
    .noise = .Medium,
    .effect_type = .{ .Custom = _effectBoltCrystal },
};
fn _effectBoltCrystal(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    if (state.dungeon.at(coord).mob) |victim| {
        const armor = victim.inventory.armor orelse &items.NoneArmor;
        const max_damage = opts.power - (opts.power * armor.shave / 100);
        const damage = rng.rangeClumping(usize, max_damage / 2, max_damage, 2);

        victim.takeDamage(.{
            .amount = @intToFloat(f64, damage),
            .source = .RangedAttack,
        });
    } else err.wat();
}

pub const BOLT_LIGHTNING = Spell{
    .name = "bolt of electricity",
    .cast_type = .Bolt,
    .noise = .Medium,
    .effect_type = .{ .Custom = _effectBoltLightning },
};
fn _effectBoltLightning(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    if (state.dungeon.at(coord).mob) |victim| {
        const avg_dmg = opts.power;
        const dmg = rng.rangeClumping(usize, avg_dmg / 2, avg_dmg * 2, 2);
        victim.takeDamage(.{
            .amount = @intToFloat(f64, dmg),
            .source = .RangedAttack,
            .kind = .Electric,
            .blood = false,
        });
    }
}

pub const BOLT_FIRE = Spell{
    .name = "bolt of fire",
    .cast_type = .Bolt,
    .noise = .Medium,
    .effect_type = .{ .Custom = _effectBoltFire },
};
fn _effectBoltFire(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    if (state.dungeon.at(coord).mob) |victim| {
        const avg_dmg = opts.power;
        const dmg = rng.rangeClumping(usize, avg_dmg / 2, avg_dmg * 2, 2);
        victim.takeDamage(.{
            .amount = @intToFloat(f64, dmg),
            .source = .RangedAttack,
            .kind = .Fire,
            .blood = false,
        });
        victim.addStatus(.Fire, 0, opts.duration, false);
    }
}

pub const CAST_HASTE_UNDEAD = Spell{
    .name = "hasten undead",
    .cast_type = .Smite,
    .smite_target_type = .UndeadAlly,
    .effect_type = .{ .Status = .Fast },
    .checks_will = false,
};

pub const CAST_HEAL_UNDEAD = Spell{
    .name = "heal undead",
    .cast_type = .Smite,
    .smite_target_type = .UndeadAlly,
    .check_has_effect = _hasEffectHealUndead,
    .effect_type = .{ .Custom = _effectHealUndead },
    .checks_will = false,
};
fn _hasEffectHealUndead(caster: *Mob, spell: SpellOptions, target: Coord) bool {
    const mob = state.dungeon.at(target).mob.?;
    return mob.HP < (mob.max_HP / 2) and utils.getNearestCorpse(caster) != null;
}
fn _effectHealUndead(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const caster_mob = state.dungeon.at(caster).mob.?;
    const corpse_coord = utils.getNearestCorpse(caster_mob).?;
    const corpse_name = state.dungeon.at(corpse_coord).surface.?.Corpse.displayName();
    state.dungeon.at(corpse_coord).surface = null;

    const ally = state.dungeon.at(coord).mob.?;
    ally.HP = math.clamp(ally.HP + ((ally.max_HP - ally.HP) / 2), 0, ally.max_HP);

    state.message(.SpellCast, "The {} corpse dissolves away, healing the {}!", .{
        corpse_name, ally.displayName(),
    });
}

pub const CAST_HASTEN_ROT = Spell{
    .name = "hasten rot",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _effectHastenRot },
    .checks_will = false,
};
fn _effectHastenRot(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    state.dungeon.at(coord).surface = null;

    state.dungeon.atGas(coord)[gas.Miasma.id] = @intToFloat(f64, opts.power) / 100;
    if (state.player.cansee(coord)) {
        state.message(.SpellCast, "The {} corpse explodes in a blast of foul miasma!", .{
            corpse.displayName(),
        });
    }
}

pub const CAST_RESURRECT_FIRE = Spell{
    .name = "burnt offering",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _resurrectFire },
    .checks_will = false,
};
fn _resurrectFire(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (corpse.raiseAsUndead(coord)) {
        if (state.player.cansee(coord)) {
            state.message(.SpellCast, "The {} rises, burning with an unearthly flame!", .{
                corpse.displayName(),
            });
        }
        corpse.addStatus(.Fire, 0, 0, true);
        corpse.addStatus(.Fast, 0, 0, true);
        corpse.addStatus(.Shove, 0, 0, true);
        corpse.addStatus(.Explosive, opts.power, 0, true);
        corpse.addStatus(.Lifespan, opts.power, 20, false);
    }
}

pub const CAST_RESURRECT_FROZEN = Spell{
    .name = "frozen resurrection",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _resurrectFrozen },
    .checks_will = false,
};
fn _resurrectFrozen(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (corpse.raiseAsUndead(coord)) {
        if (state.player.cansee(coord)) {
            state.message(.SpellCast, "The {} glows with a cold light!", .{
                corpse.displayName(),
            });
        }
        corpse.tile = 'Z';
        corpse.immobile = true;
        corpse.max_HP = corpse.max_HP * 2;
        corpse.HP = corpse.max_HP;
        corpse.innate_resists.rFire = -2;
        corpse.base_strength = corpse.base_strength * 130 / 100;
        corpse.base_evasion = 0;
        corpse.deg360_vision = true;

        corpse.addStatus(.Fast, 0, 0, true);
        corpse.addStatus(.Lifespan, 0, opts.power, false);
    }
}

pub const CAST_POLAR_LAYER = Spell{
    .name = "polar casing",
    .cast_type = .Smite,
    .smite_target_type = .Mob,
    .check_has_effect = _hasEffectPolarLayer,
    .effect_type = .{ .Custom = _effectPolarLayer },
    .checks_will = false,
};
fn _hasEffectPolarLayer(caster: *Mob, spell: SpellOptions, target: Coord) bool {
    return state.dungeon.neighboringWalls(target, false) > 0;
}
fn _effectPolarLayer(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const mob = state.dungeon.at(coord).mob.?;
    for (&CARDINAL_DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.dungeon.at(neighbor).type == .Wall) {
            state.dungeon.at(neighbor).type = .Floor;
            // FIXME: passing allocator directly is anti-pattern?
            const w = mobs.placeMob(&state.GPA.allocator, &mobs.LivingIceTemplate, neighbor, .{});
            w.addStatus(.Lifespan, 0, opts.power, false);
        }
    };

    if (mob == state.player) {
        state.message(.SpellCast, "The walls near you transmute into living ice!", .{});
    } else if (state.player.cansee(mob.coord)) {
        state.message(.SpellCast, "The walls near the {} transmute into living ice!", .{mob.displayName()});
    }
}

pub const CAST_RESURRECT_NORMAL = Spell{
    .name = "resurrection",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _resurrectNormal },
    .checks_will = false,
};
fn _resurrectNormal(caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (corpse.raiseAsUndead(coord)) {
        if (state.player.cansee(coord)) {
            state.message(.SpellCast, "The {} is imbued with a spirit of malice and rises!", .{
                corpse.displayName(),
            });
        }
    }
}

pub const CAST_FREEZE = Spell{
    .name = "freeze",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Paralysis },
    .checks_will = true,
};
pub const CAST_FAMOUS = Spell{
    .name = "famous",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Corona },
    .checks_will = true,
};
pub const CAST_FERMENT = Spell{
    .name = "ferment",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Confusion },
    .checks_will = true,
};
pub const CAST_FEAR = Spell{
    .name = "fear",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Fear },
    .checks_will = true,
};
pub const CAST_PAIN = Spell{
    .name = "pain",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Pain },
    .checks_will = true,
};

fn willSucceedAgainstMob(caster: *const Mob, target: *const Mob) bool {
    if (rng.onein(10)) return false;
    return (rng.rangeClumping(usize, 1, 100, 2) * caster.willpower) >
        (rng.rangeClumping(usize, 1, 100, 2) * target.willpower);
}

pub const SpellOptions = struct {
    spell: *const Spell = undefined,
    caster_name: ?[]const u8 = null,
    duration: usize = Status.MAX_DURATION,
    power: usize = 0,
    MP_cost: usize = 1,
};

pub const Spell = struct {
    name: []const u8,

    cast_type: union(enum) {
        Ray,

        // Line-targeted, requires line-of-fire.
        Bolt,

        // Doesn't require line-of-fire (aka smite-targeted).
        Smite,
    },

    // Only used if cast_type == .Smite.
    smite_target_type: enum {
        Self, UndeadAlly, Mob, Corpse
    } = .Mob,

    // Only used if cast_type == .Bolt
    bolt_dodgeable: bool = false,
    bolt_multitarget: bool = true,

    checks_will: bool = false,
    needs_visible_target: bool = true,

    check_has_effect: ?fn (*Mob, SpellOptions, Coord) bool = null,

    noise: sound.SoundIntensity = .Silent,

    effect_type: union(enum) {
        Status: Status,
        Custom: fn (caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void,
    },

    pub fn use(self: Spell, caster: ?*Mob, caster_coord: Coord, target: Coord, opts: SpellOptions, comptime message: ?[]const u8) void {
        if (caster) |caster_mob| {
            if (opts.MP_cost > caster_mob.MP) {
                err.bug("Spellcaster casting spell without enough MP!", .{});
            }

            caster_mob.MP -= opts.MP_cost;
        }

        if (self.checks_will and caster == null) {
            err.bug("Non-mob entity attempting to cast will-checked spell!", .{});
        }

        if (state.player.cansee(caster_coord)) {
            const name = opts.caster_name orelse
                if (caster) |c| c.displayName() else "giant tomato";
            state.message(
                .SpellCast,
                message orelse "The {0} gestures ominously!",
                .{name},
            );
        }

        if (caster) |_| {
            caster.?.declareAction(.Cast);
            caster.?.makeNoise(.Combat, self.noise);
        } else {
            state.dungeon.soundAt(caster_coord).* = .{
                .intensity = self.noise,
                .type = .Combat,
                .state = .New,
                .when = state.ticks,
            };
        }

        switch (self.cast_type) {
            .Ray => err.todo(),
            .Bolt => {
                // Fling a bolt and let it hit whatever
                const line = caster_coord.drawLine(target, state.mapgeometry);
                for (line.constSlice()) |c| {
                    if (!c.eq(caster_coord) and !state.is_walkable(c, .{ .right_now = true })) {
                        const hit_mob = state.dungeon.at(c).mob;

                        if (hit_mob) |victim| {
                            if (self.checks_will) {
                                if (!willSucceedAgainstMob(caster.?, victim))
                                    continue;
                            }

                            if (self.bolt_dodgeable) {
                                if (rng.percent(combat.chanceOfAttackEvaded(victim, caster))) {
                                    state.messageAboutMob(victim, caster_coord, .CombatUnimportant, "dodge the {}.", .{self.name}, "dodges the {}.", .{self.name});
                                    continue;
                                }
                            }

                            if (victim == state.player) {
                                state.message(.Combat, "The {} hits you!", .{self.name});
                            } else if (state.player.cansee(victim.coord)) {
                                state.message(.Combat, "The {} hits the {}!", .{
                                    self.name, victim.displayName(),
                                });
                            } else if (state.player.cansee(caster_coord)) {
                                state.message(.Combat, "The {} hits something!", .{self.name});
                            }
                        }

                        switch (self.effect_type) {
                            .Status => |s| if (hit_mob) |victim| {
                                victim.addStatus(s, opts.power, opts.duration, false);
                            },
                            .Custom => |cu| cu(caster_coord, self, opts, c),
                        }

                        if (!self.bolt_multitarget or hit_mob == null)
                            break;
                    }
                }
            },
            .Smite => {
                switch (self.smite_target_type) {
                    .Self, .Mob, .UndeadAlly => {
                        if (state.dungeon.at(target).mob == null) {
                            err.bug("Mage used smite-targeted spell on empty target!", .{});
                        }

                        const mob = state.dungeon.at(target).mob.?;

                        if (self.checks_will) {
                            if (!willSucceedAgainstMob(caster.?, mob))
                                return;
                        }

                        switch (self.effect_type) {
                            .Status => |s| mob.addStatus(s, opts.power, opts.duration, false),
                            .Custom => |c| c(caster_coord, self, opts, target),
                        }
                    },
                    .Corpse => {
                        if (state.dungeon.at(target).surface == null or
                            meta.activeTag(state.dungeon.at(target).surface.?) != .Corpse)
                        {
                            err.bug("Mage used smite-targeted spell on empty target!", .{});
                        }

                        switch (self.effect_type) {
                            .Status => err.bug("Mage tried to induce a status on a corpse!!", .{}),
                            .Custom => |c| c(caster_coord, self, opts, target),
                        }
                    },
                }
            },
        }
    }
};
