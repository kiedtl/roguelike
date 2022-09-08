// Spells are, basically, any ranged attack that doesn't come from a projectile.
//
// They can be fired by machines as well as monsters; when fired by monsters,
// they could be "natural" abilities (e.g., a drake's breath).
//

const std = @import("std");
const meta = std.meta;
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;

const ai = @import("ai.zig");
const colors = @import("colors.zig");
const ui = @import("ui.zig");
const dijkstra = @import("dijkstra.zig");
const types = @import("types.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const explosions = @import("explosions.zig");
const items = @import("items.zig");
const gas = @import("gas.zig");
const mobs = @import("mobs.zig");
const sound = @import("sound.zig");
const state = @import("state.zig");
const utils = @import("utils.zig");
const rng = @import("rng.zig");

const Coord = types.Coord;
const Tile = types.Tile;
const Item = types.Item;
const Ring = types.Ring;
const Weapon = types.Weapon;
const StatusDataInfo = types.StatusDataInfo;
const Armor = types.Armor;
const SurfaceItem = types.SurfaceItem;
const Mob = types.Mob;
const Status = types.Status;
const Machine = types.Machine;
const Direction = types.Direction;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// -----------------------------------------------------------------------------

// Create spell that summons creatures from a corpse.
fn createCorpseCreationSpell(
    comptime mob_id: []const u8,
    comptime name: []const u8,
    comptime msg_name: []const u8,
    template: *const mobs.MobTemplate,
) Spell {
    return Spell{
        .id = "sp_call_" ++ mob_id,
        .name = "call " ++ name,
        .cast_type = .Smite,
        .smite_target_type = .Corpse,
        .effect_type = .{ .Custom = struct {
            fn f(caster_coord: Coord, _: Spell, _: SpellOptions, coord: Coord) void {
                const caster = state.dungeon.at(caster_coord).mob.?;

                const corpse = state.dungeon.at(coord).surface.?.Corpse;
                state.dungeon.at(coord).surface = null;

                const spawn_loc: ?Coord = for (&CARDINAL_DIRECTIONS) |d| {
                    if (coord.move(d, state.mapgeometry)) |neighbor| {
                        if (state.is_walkable(neighbor, .{ .right_now = true })) {
                            break neighbor;
                        }
                    }
                } else null;

                if (spawn_loc) |loc| {
                    const m = mobs.placeMob(state.GPA.allocator(), template, loc, .{});

                    if (caster.squad) |caster_squad| {
                        caster_squad.members.append(m) catch {};
                        if (m.squad) |previous_squad| {
                            for (previous_squad.members.constSlice()) |sub_member| {
                                if (caster_squad.members.append(sub_member)) {
                                    sub_member.squad = caster_squad;
                                } else |_| {
                                    sub_member.squad = null;
                                }
                            }
                        }
                        m.squad = caster_squad;
                    }

                    if (state.player.cansee(coord)) {
                        state.message(
                            .SpellCast,
                            msg_name ++ "s bursts out of the {s} corpse!",
                            .{corpse.displayName()},
                        );
                    }
                }
            }
        }.f },
    };
}

pub const CAST_CREATE_BLOAT = createCorpseCreationSpell("bloat", "bloat", "Bloats", &mobs.BloatTemplate);
pub const CAST_CREATE_EMBERLING = createCorpseCreationSpell("emberling", "emberling", "Emberlings", &mobs.EmberlingTemplate);
pub const CAST_CREATE_SPARKLING = createCorpseCreationSpell("sparkling", "sparkling", "Sparklings", &mobs.SparklingTemplate);

pub const CAST_ALERT_ALLY = Spell{
    .id = "sp_alert_ally",
    .name = "alert ally",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = struct {
        fn f(caster: *Mob, _: SpellOptions, _: Coord) bool {
            const hostile = caster.enemyList().items[0];
            return for (caster.allies.items) |ally| {
                if (!ai.isEnemyKnown(ally, hostile.mob)) {
                    break true;
                }
            } else false;
        }
    }.f,
    .effect_type = .{
        .Custom = struct {
            fn f(caster_coord: Coord, _: Spell, _: SpellOptions, _: Coord) void {
                ai.alertAllyOfHostile(state.dungeon.at(caster_coord).mob.?);
            }
        }.f,
    },
};

pub const CAST_CALL_UNDEAD = Spell{
    .id = "sp_call_undead",
    .name = "call undead",
    .cast_type = .Smite,
    .checks_will = true,
    .effect_type = .{
        .Custom = struct {
            fn f(caster_coord: Coord, _: Spell, opts: SpellOptions, target: Coord) void {
                _ = opts;
                const caster = state.dungeon.at(caster_coord).mob.?;
                const target_mob = state.dungeon.at(target).mob.?;

                // Find the closest undead ally
                var mob: ?*Mob = null;
                var y: usize = 0;
                undead_search: while (y < HEIGHT) : (y += 1) {
                    var x: usize = 0;
                    while (x < WIDTH) : (x += 1) {
                        const coord = Coord.new2(caster_coord.z, x, y);
                        if (state.dungeon.at(coord).mob) |candidate| {
                            if (candidate.allegiance == caster.allegiance and
                                (candidate.life_type == .Undead or
                                candidate.ai.flag(.CalledWithUndead)) and
                                candidate.ai.phase != .Hunt)
                            {
                                mob = candidate;
                                break :undead_search;
                            }
                        }
                    }
                }

                if (mob) |undead| {
                    if (undead.ai.phase == .Work) {
                        undead.sustiles.append(.{ .coord = target, .unforgettable = true }) catch err.wat();
                    } else if (undead.ai.phase == .Investigate) {
                        ai.updateEnemyKnowledge(undead, target_mob, null);
                    } else unreachable;

                    if (undead.coord.distance(target) > 20 and
                        undead.isUnderStatus(.Fast) == null)
                    {
                        undead.addStatus(.Fast, 0, .{ .Tmp = 10 });
                    }

                    if (undead.ai.work_area.items.len > 0) {
                        undead.ai.work_area.items[0] = target;
                    }

                    ui.Animation.apply(.{ .EncircleChar = .{
                        .coord = caster_coord,
                        .char = '!',
                        .fg = colors.PALE_VIOLET_RED,
                    } });
                    if (target_mob == state.player and state.player.cansee(caster_coord) and
                        !state.player.cansee(undead.coord))
                    {
                        state.message(.Info, "You feel like something is searching for you.", .{});
                    }
                } else {
                    if (target_mob == state.player and state.player.cansee(caster_coord)) {
                        state.message(.Unimportant, "Nothing seems to happen...", .{});
                    }
                }
            }
        }.f,
    },
};

// TODO: generalize into a healing spell?
pub const CAST_REGEN = Spell{
    .id = "sp_regen",
    .name = "regenerate",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = struct {
        // Only use the spell if the caster's HP is below
        // the (regeneration_amount * 2).
        //
        // TODO: we should have a way to flag this spell as an "emergency"
        // spell, ensuring it's only used when the caster is clearly losing a
        // fight
        fn f(caster: *Mob, opts: SpellOptions, _: Coord) bool {
            return caster.HP <= (opts.power * 2);
        }
    }.f,
    .noise = .Loud,
    .effect_type = .Heal,
};

// Spells that give specific status to specific class of mobs. {{{

fn _createSpecificStatusSp(comptime id: []const u8, name: []const u8, s: Status) Spell {
    return Spell{
        .id = "sp_haste_" ++ id,
        .name = "haste " ++ name,
        .cast_type = .Smite,
        .smite_target_type = .{ .SpecificMob = id },
        .effect_type = .{ .Status = s },
    };
}

pub const CAST_HASTE_EMBERLING = _createSpecificStatusSp("emberling", "emberling", .Fast);
pub const CAST_HASTE_SPARKLING = _createSpecificStatusSp("sparkling", "sparkling", .Fast);
pub const CAST_HASTE_DUSTLING = _createSpecificStatusSp("dustling", "dustling", .Fast);
pub const CAST_ENRAGE_DUSTLING = _createSpecificStatusSp("dustling", "dustling", .Enraged);

// }}}

pub const CAST_FIREBLAST = Spell{
    .id = "sp_fireblast",
    .name = "vomit flames",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = struct {
        fn f(caster: *Mob, opts: SpellOptions, target: Coord) bool {
            return opts.power >= target.distance(caster.coord);
        }
    }.f,
    .noise = .Loud,
    .effect_type = .{ .Custom = struct {
        fn f(caster: Coord, _: Spell, opts: SpellOptions, target: Coord) void {
            if (state.player.cansee(target)) {
                const caster_m = state.dungeon.at(caster).mob.?;
                state.message(.SpellCast, "{c} belches forth flames!", .{caster_m});
            }
            explosions.fireBurst(target, opts.power);
        }
    }.f },
};

pub const BOLT_AIRBLAST = Spell{
    .id = "sp_airblast",
    .name = "airblast",
    .cast_type = .Bolt,
    .bolt_dodgeable = false,
    .bolt_multitarget = false,
    .check_has_effect = struct {
        fn f(caster: *Mob, opts: SpellOptions, c: Coord) bool {
            return caster.coord.distance(c) < opts.power;
        }
    }.f,
    .noise = .Loud,
    .effect_type = .{ .Custom = struct {
        fn f(caster_c: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
            if (state.dungeon.at(coord).mob) |victim| {
                state.message(.Combat, "The blast of air hits {}!", .{victim});
                const distance = victim.coord.distance(caster_c);
                assert(distance < opts.power);
                const knockback = opts.power - distance;
                const direction = caster_c.closestDirectionTo(coord, state.mapgeometry);
                combat.throwMob(state.dungeon.at(caster_c).mob, victim, direction, knockback);
            } else err.wat();
        }
    }.f },
};

pub const CAST_MASS_DISMISSAL = Spell{
    .id = "sp_mass_dismissal",
    .name = "mass dismissal",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = _hasEffectMassDismissal,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectMassDismissal },
};
fn _hasEffectMassDismissal(caster: *Mob, _: SpellOptions, _: Coord) bool {
    for (caster.enemyList().items) |enemy_record| {
        if (caster.cansee(enemy_record.mob.coord) and
            enemy_record.mob.life_type == .Living and
            enemy_record.mob.isUnderStatus(.Fear) == null)
        {
            return true;
        }
    }
    return false;
}
fn _effectMassDismissal(caster: Coord, _: Spell, opts: SpellOptions, _: Coord) void {
    const caster_mob = state.dungeon.at(caster).mob.?;

    for (caster_mob.enemyList().items) |enemy_record| {
        if (caster_mob.cansee(enemy_record.mob.coord) and
            enemy_record.mob.life_type == .Living and
            enemy_record.mob.isUnderStatus(.Fear) == null)
        {
            if (!willSucceedAgainstMob(caster_mob, enemy_record.mob))
                continue;
            enemy_record.mob.addStatus(.Fear, 0, .{ .Tmp = opts.power });
        }
    }
}

pub const CAST_SUMMON_ENEMY = Spell{
    .id = "sp_summon_enemy",
    .name = "summon enemy",
    .cast_type = .Smite,
    .smite_target_type = .Mob,
    .checks_will = true,
    .needs_visible_target = false,
    .check_has_effect = _hasEffectSummonEnemy,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectSummonEnemy },
};
fn _hasEffectSummonEnemy(caster: *Mob, _: SpellOptions, target: Coord) bool {
    const mob = state.dungeon.at(target).mob.?;
    return (mob == state.player or mob.ai.phase == .Flee) and
        !caster.cansee(mob.coord);
}
fn _effectSummonEnemy(caster: Coord, _: Spell, _: SpellOptions, coord: Coord) void {
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

        state.messageAboutMob(target_mob, caster, .SpellCast, "are dragged back to the {s}!", .{caster_mob.displayName()}, "is dragged back to the {s}!", .{caster_mob.displayName()});
    }
}

pub const CAST_AURA_DISPERSAL = Spell{
    .id = "sp_dismissal_aura",
    .name = "aura of dispersal",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = _hasEffectAuraDispersal,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectAuraDispersal },
};
fn _hasEffectAuraDispersal(caster: *Mob, _: SpellOptions, target: Coord) bool {
    for (&DIRECTIONS) |d| if (target.move(d, state.mapgeometry)) |neighbor| {
        if (state.dungeon.at(neighbor).mob) |mob|
            if (mob.isHostileTo(caster)) {
                return true;
            };
    };
    return false;
}
fn _effectAuraDispersal(caster: Coord, _: Spell, _: SpellOptions, _: Coord) void {
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
                    mob.addStatus(.Daze, 0, .{ .Tmp = 2 });
                    if (state.player.cansee(mob.coord) or state.player.cansee(caster))
                        had_visible_effect = true;
                }
            };
    };

    if (had_visible_effect)
        state.message(.SpellCast, "Space bends horribly around the {s}!", .{
            caster_mob.displayName(),
        });
}

pub const CAST_CONJ_SPECTRAL_SWORD = Spell{
    .id = "sp_conj_ss",
    .name = "conjure spectral sword",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .noise = .Quiet,
    .effect_type = .{
        .Custom = struct {
            fn f(_: Coord, _: Spell, _: SpellOptions, coord: Coord) void {
                for (&CARDINAL_DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.is_walkable(neighbor, .{ .right_now = true })) {
                        // FIXME: passing allocator directly is anti-pattern?
                        _ = mobs.placeMob(state.GPA.allocator(), &mobs.SpectralSwordTemplate, neighbor, .{});
                    }
                };
            }
        }.f,
    },
};

pub const CAST_CONJ_BALL_LIGHTNING = Spell{
    .id = "sp_conj_bl",
    .name = "conjure ball lightning",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .noise = .Quiet,
    .effect_type = .{ .Custom = _effectConjureBL },
};
fn _effectConjureBL(_: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
    for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, .{ .right_now = true })) {
            // FIXME: passing allocator directly is anti-pattern?
            const w = mobs.placeMob(state.GPA.allocator(), &mobs.BallLightningTemplate, neighbor, .{});
            w.addStatus(.Lifespan, 0, .{ .Tmp = opts.power });
            return;
        }
    };
}

pub const BOLT_PARALYSE = Spell{
    .id = "sp_elec_paralyse",
    .name = "paralysing zap",
    .cast_type = .Bolt,
    .noise = .Medium,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .effect_type = .{ .Custom = struct {
        fn f(caster_c: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
            if (state.dungeon.at(coord).mob) |victim| {
                victim.takeDamage(.{
                    .amount = opts.power,
                    .source = .RangedAttack,
                    .by_mob = state.dungeon.at(caster_c).mob,
                    .kind = .Electric,
                    .blood = false,
                }, .{ .strs = &items.SHOCK_STRS });
                const dmg_taken = victim.last_damage.?.amount;
                victim.addStatus(.Paralysis, 0, .{ .Tmp = dmg_taken });
            }
        }
    }.f },
};

pub const BOLT_BLINKBOLT = Spell{
    .id = "sp_elec_blinkbolt",
    .name = "living lightning",
    .cast_type = .Bolt,
    .noise = .Loud,
    .bolt_animation = .{
        .Type2 = .{
            .chars = ui.Animation.ELEC_LINE_CHARS,
            .fg = ui.Animation.ELEC_LINE_FG,
            .bg = ui.Animation.ELEC_LINE_BG,
            .bg_mix = ui.Animation.ELEC_LINE_MIX,
            .approach = 1,
        },
    },
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .effect_type = .{ .Custom = struct {
        fn f(caster_c: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
            if (state.dungeon.at(coord).mob) |victim| {
                victim.takeDamage(.{
                    .amount = opts.power,
                    .source = .RangedAttack,
                    .by_mob = state.dungeon.at(caster_c).mob,
                    .kind = .Electric,
                    .blood = false,
                }, .{ .strs = &items.SHOCK_STRS });
            }
        }
    }.f },
    .bolt_last_coord_effect = struct {
        pub fn f(caster_coord: Coord, _: SpellOptions, coord: Coord) void {
            if (state.is_walkable(coord, .{ .right_now = true })) {
                const caster = state.dungeon.at(caster_coord).mob.?;
                _ = caster.teleportTo(coord, null, true);
            }
        }
    }.f,
};

pub const BOLT_IRON = Spell{
    .id = "sp_iron_bolt",
    .name = "iron arrow",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_multitarget = false,
    .bolt_animation = .{ .Simple = .{ .char = '+' } },
    .noise = .Medium,
    .effect_type = .{ .Custom = struct {
        fn f(caster_c: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
            if (state.dungeon.at(coord).mob) |victim| {
                victim.takeDamage(.{
                    .amount = opts.power,
                    .source = .RangedAttack,
                    .by_mob = state.dungeon.at(caster_c).mob,
                }, .{ .noun = "The iron arrow" });
            }
        }
    }.f },
};

pub const BOLT_CRYSTAL = Spell{
    .id = "sp_crystal_shard",
    .name = "crystal shard",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_multitarget = false,
    .noise = .Medium,
    .effect_type = .{ .Custom = _effectBoltCrystal },
};
fn _effectBoltCrystal(caster_c: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
    if (state.dungeon.at(coord).mob) |victim| {
        const damage = rng.rangeClumping(usize, opts.power / 2, opts.power, 2);
        victim.takeDamage(.{
            .amount = damage,
            .source = .RangedAttack,
            .by_mob = state.dungeon.at(caster_c).mob,
        }, .{ .noun = "The crystal shard" });
    } else err.wat();
}

pub const BOLT_LIGHTNING = Spell{
    .id = "sp_elec_bolt",
    .name = "bolt of electricity",
    .cast_type = .Bolt,
    .bolt_dodgeable = false,
    .bolt_multitarget = true,
    //.bolt_animation = .{ .Type2 = .{ .chars = "EFHIKLMNTVWXYZ\\/|-=+#", .fg = 0x73c5ff } },
    .bolt_animation = .{
        .Type2 = .{
            .chars = ui.Animation.ELEC_LINE_CHARS,
            .fg = ui.Animation.ELEC_LINE_FG,
            .bg = ui.Animation.ELEC_LINE_BG,
            .bg_mix = ui.Animation.ELEC_LINE_MIX,
            .approach = 2,
        },
    },
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .noise = .Loud,
    .effect_type = .{ .Custom = struct {
        fn f(caster_c: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
            if (state.dungeon.at(coord).mob) |victim| {
                const avg_dmg = opts.power;
                const dmg = rng.rangeClumping(usize, avg_dmg / 2, avg_dmg * 2, 2);
                victim.takeDamage(.{
                    .amount = dmg,
                    .source = .RangedAttack,
                    .kind = .Electric,
                    .blood = false,
                    .by_mob = state.dungeon.at(caster_c).mob,
                }, .{ .noun = "The lightning bolt" });
            }
        }
    }.f },
};

pub const BOLT_FIREBALL = Spell{
    .id = "sp_fireball",
    .name = "fireball",
    .cast_type = .Bolt,
    // Has effect if:
    //    mob isn't fire-immune
    // && mob isn't on fire
    // && caster isn't near mob
    .check_has_effect = struct {
        fn f(caster: *Mob, opts: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return caster.coord.distance(mob.coord) > opts.power and
                !mob.isFullyResistant(.rFire) and
                mob.isUnderStatus(.Fire) == null;
        }
    }.f,
    .noise = .Loud,
    .effect_type = .{ .Custom = struct {
        fn f(_: Coord, _: Spell, opts: SpellOptions, target: Coord) void {
            explosions.fireBurst(target, opts.power);
            state.dungeon.at(target).mob.?.addStatus(.Fire, 0, .{ .Tmp = opts.duration });
        }
    }.f },
};

pub const CAST_HASTE_UNDEAD = Spell{
    .id = "sp_hasten_undead",
    .name = "hasten undead",
    .cast_type = .Smite,
    .smite_target_type = .UndeadAlly,
    .effect_type = .{ .Status = .Fast },
    .checks_will = false,
};

pub const CAST_HEAL_UNDEAD = Spell{
    .id = "sp_heal_undead",
    .name = "heal undead",
    .cast_type = .Smite,
    .smite_target_type = .UndeadAlly,
    .check_has_effect = _hasEffectHealUndead,
    .effect_type = .{ .Custom = _effectHealUndead },
    .checks_will = false,
};
fn _hasEffectHealUndead(caster: *Mob, _: SpellOptions, target: Coord) bool {
    const mob = state.dungeon.at(target).mob.?;
    return mob.HP < (mob.max_HP / 2) and utils.getNearestCorpse(caster) != null;
}
fn _effectHealUndead(caster: Coord, _: Spell, _: SpellOptions, coord: Coord) void {
    const caster_mob = state.dungeon.at(caster).mob.?;
    const corpse_coord = utils.getNearestCorpse(caster_mob).?;
    const corpse_name = state.dungeon.at(corpse_coord).surface.?.Corpse.displayName();
    state.dungeon.at(corpse_coord).surface = null;

    const ally = state.dungeon.at(coord).mob.?;
    ally.HP = math.clamp(ally.HP + ((ally.max_HP - ally.HP) / 2), 0, ally.max_HP);

    state.message(.SpellCast, "The {s} corpse dissolves away, healing the {s}!", .{
        corpse_name, ally.displayName(),
    });
}

pub const CAST_HASTEN_ROT = Spell{
    .id = "sp_hasten_rot",
    .name = "hasten rot",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _effectHastenRot },
    .checks_will = false,
};
fn _effectHastenRot(_: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    state.dungeon.at(coord).surface = null;

    state.dungeon.atGas(coord)[gas.Miasma.id] = @intToFloat(f64, opts.power) / 100;
    if (state.player.cansee(coord)) {
        state.message(.SpellCast, "The {s} corpse explodes in a blast of foul miasma!", .{
            corpse.displayName(),
        });
    }
}

pub const CAST_RESURRECT_FIRE = Spell{
    .id = "sp_burnt_offering",
    .name = "burnt offering",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _resurrectFire },
    .checks_will = false,
};
fn _resurrectFire(_: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (corpse.raiseAsUndead(coord)) {
        if (state.player.cansee(coord)) {
            state.message(.SpellCast, "The {s} rises, burning with an unearthly flame!", .{
                corpse.displayName(),
            });
        }
        corpse.addStatus(.Fire, 0, .Prm);
        corpse.addStatus(.Fast, 0, .Prm);
        corpse.addStatus(.Shove, 0, .Prm);
        corpse.addStatus(.Explosive, opts.power, .Prm);
        corpse.addStatus(.Lifespan, opts.power, .{ .Tmp = 20 });
    }
}

pub const CAST_RESURRECT_FROZEN = Spell{
    .id = "sp_raise_frozen",
    .name = "frozen resurrection",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _resurrectFrozen },
    .checks_will = false,
};
fn _resurrectFrozen(_: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (corpse.raiseAsUndead(coord)) {
        if (state.player.cansee(coord)) {
            state.message(.SpellCast, "The {s} glows with a cold light!", .{
                corpse.displayName(),
            });
        }
        corpse.tile = 'Z';
        corpse.immobile = true;
        corpse.max_HP = corpse.max_HP * 2;
        corpse.HP = corpse.max_HP;
        corpse.innate_resists.rFire = -2;
        corpse.stats.Evade = 0;
        corpse.deg360_vision = true;

        corpse.addStatus(.Fast, 0, .Prm);
        corpse.addStatus(.Lifespan, 0, .{ .Tmp = opts.power });
    }
}

pub const CAST_POLAR_LAYER = Spell{
    .id = "sp_polar_casing",
    .name = "polar casing",
    .cast_type = .Smite,
    .smite_target_type = .Mob,
    .check_has_effect = _hasEffectPolarLayer,
    .effect_type = .{ .Custom = _effectPolarLayer },
    .checks_will = false,
};
fn _hasEffectPolarLayer(_: *Mob, _: SpellOptions, target: Coord) bool {
    return state.dungeon.neighboringWalls(target, false) > 0;
}
fn _effectPolarLayer(_: Coord, _: Spell, opts: SpellOptions, coord: Coord) void {
    const mob = state.dungeon.at(coord).mob.?;
    for (&CARDINAL_DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.dungeon.at(neighbor).type == .Wall) {
            state.dungeon.at(neighbor).type = .Floor;
            // FIXME: passing allocator directly is anti-pattern?
            const w = mobs.placeMob(state.GPA.allocator(), &mobs.LivingIceTemplate, neighbor, .{});
            w.addStatus(.Lifespan, 0, .{ .Tmp = opts.power });
        }
    };

    if (mob == state.player) {
        state.message(.SpellCast, "The walls near you transmute into living ice!", .{});
    } else if (state.player.cansee(mob.coord)) {
        state.message(.SpellCast, "The walls near the {s} transmute into living ice!", .{mob.displayName()});
    }
}

pub const CAST_RESURRECT_NORMAL = Spell{
    .id = "sp_raise",
    .name = "resurrection",
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effect_type = .{ .Custom = _resurrectNormal },
    .checks_will = false,
};
fn _resurrectNormal(_: Coord, _: Spell, _: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (corpse.raiseAsUndead(coord)) {
        if (state.player.cansee(coord)) {
            state.message(.SpellCast, "The {s} rises from the dead!", .{
                corpse.displayName(),
            });
        }
    }
}

pub const CAST_DISCHARGE = Spell{
    .id = "sp_discharge",
    .name = "static discharge",
    .cast_type = .Smite,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .effect_type = .{ .Custom = struct {
        fn f(caster_c: Coord, _: Spell, _: SpellOptions, coord: Coord) void {
            if (state.dungeon.at(coord).mob) |victim| {
                var empty_spaces: usize = 0;
                for (&DIRECTIONS) |d| if (victim.coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.dungeon.at(neighbor).mob == null and
                        state.dungeon.at(neighbor).surface == null and
                        state.dungeon.at(neighbor).type == .Floor)
                    {
                        empty_spaces += 1;
                    }
                };
                const damage = math.clamp(empty_spaces / 2, 1, 4);
                victim.takeDamage(.{
                    .amount = damage,
                    .source = .RangedAttack,
                    .by_mob = state.dungeon.at(caster_c).mob,
                    .kind = .Electric,
                    .blood = false,
                }, .{ .basic = true });
            }
        }
    }.f },
};

pub const CAST_BARTENDER_FERMENT = Spell{
    .id = "sp_ferment_bartender",
    .name = "ferment",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Drunk },
    //.checks_will = true,
};
pub const CAST_FEEBLE = Spell{
    .id = "sp_feeble",
    .name = "slow",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Slow },
    .checks_will = true,
};
pub const CAST_FRY = Spell{
    .id = "sp_fry",
    .name = "ignite",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Fire },
    .checks_will = true,
};
pub const CAST_FLAMMABLE = Spell{
    .id = "sp_flammable",
    .name = "flammabilification",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Flammable },
    .checks_will = true,
};
pub const CAST_FREEZE = Spell{
    .id = "sp_freeze",
    .name = "freeze",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Paralysis },
    .checks_will = true,
};
pub const CAST_FAMOUS = Spell{
    .id = "sp_famous",
    .name = "famous",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Corona },
    .checks_will = true,
};
pub const CAST_FERMENT = Spell{
    .id = "sp_ferment",
    .name = "confusion",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Disorient },
    .checks_will = true,
};
pub const CAST_FEAR = Spell{
    .id = "sp_fear",
    .name = "fear",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Fear },
    .checks_will = true,
};
pub const CAST_PAIN = Spell{
    .id = "sp_pain",
    .name = "pain",
    .cast_type = .Smite,
    .effect_type = .{ .Status = .Pain },
    .checks_will = true,
};

pub fn willSucceedAgainstMob(caster: *const Mob, target: *const Mob) bool {
    if (rng.onein(10) or caster.stat(.Willpower) < target.stat(.Willpower))
        return false;
    return (rng.rangeClumping(isize, 1, 100, 2) * caster.stat(.Willpower)) >
        (rng.rangeClumping(isize, 1, 150, 2) * target.stat(.Willpower));
}

pub fn appxChanceOfWillOverpowered(caster: *const Mob, target: *const Mob) usize {
    var defeated: usize = 0;
    var i: usize = 10_000;
    while (i > 0) : (i -= 1) {
        if (willSucceedAgainstMob(caster, target)) {
            defeated += 1;
        }
    }
    return defeated / 100;
}

pub const SpellOptions = struct {
    spell: *const Spell = undefined,
    caster_name: ?[]const u8 = null,
    duration: usize = Status.MAX_DURATION,
    power: usize = 0,
    MP_cost: usize = 1,
};

pub const Spell = struct {
    id: []const u8,
    name: []const u8,

    cast_type: union(enum) {
        Ray,

        // Line-targeted, requires line-of-fire.
        Bolt,

        // Doesn't require line-of-fire (aka smite-targeted).
        Smite,
    },

    // Only used if cast_type == .Smite.
    smite_target_type: union(enum) {
        SpecificMob: []const u8, // mob's ID
        Self,
        UndeadAlly,
        Mob,
        Corpse,
    } = .Mob,

    // Only used if cast_type == .Bolt
    bolt_dodgeable: bool = false,
    bolt_multitarget: bool = true,
    bolt_animation: ?union(enum) {
        Simple: struct {
            char: u32,
            fg: u32 = 0xffffff,
        },
        Type2: struct {
            chars: []const u8,
            fg: u32,
            bg: ?u32 = null,
            bg_mix: ?f64 = null,
            approach: ?usize = null,
        },
    } = null,

    checks_will: bool = false,
    needs_visible_target: bool = true,

    check_has_effect: ?fn (*Mob, SpellOptions, Coord) bool = null,

    noise: sound.SoundIntensity = .Silent,

    effect_type: union(enum) {
        Status: Status,
        Heal,
        Custom: fn (caster: Coord, spell: Spell, opts: SpellOptions, coord: Coord) void,
    },

    // Options effect callback for the very last coord the bolt passed through.
    //
    // Added for Blinkbolt.
    bolt_last_coord_effect: ?fn (caster: Coord, spell: SpellOptions, coord: Coord) void = null,

    pub fn use(self: Spell, caster: ?*Mob, caster_coord: Coord, target: Coord, opts: SpellOptions) void {
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
            if (opts.caster_name) |name| {
                state.message(.SpellCast, "The {s} uses $o{s}$.!", .{ name, self.name });
            } else if (caster) |c| {
                const verb: []const u8 = if (state.player == c) "use" else "uses";
                state.message(.SpellCast, "{c} {s} $o{s}$.!", .{ c, verb, self.name });
            } else {
                state.message(.SpellCast, "The giant tomato uses $o{s}$.!", .{self.name});
            }
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
                var last_processed_coord: Coord = undefined;
                var affected_tiles = types.CoordArrayList.init(state.GPA.allocator());
                defer affected_tiles.deinit();
                const line = caster_coord.drawLine(target, state.mapgeometry, 3);
                assert(line.len > 0);
                for (line.constSlice()) |c| {
                    if (!c.eq(caster_coord) and !state.is_walkable(c, .{ .right_now = true, .only_if_breaks_lof = true })) {
                        const hit_mob = state.dungeon.at(c).mob;

                        if (hit_mob) |victim| {
                            if (self.checks_will and !willSucceedAgainstMob(caster.?, victim)) {
                                const chance = 100 - appxChanceOfWillOverpowered(caster.?, victim);
                                if (state.player.cansee(victim.coord) or state.player.cansee(caster_coord)) {
                                    state.message(.SpellCast, "{c} resisted $g($c{}%$g chance)$.", .{ victim, chance });
                                }
                                continue;
                            }

                            if (self.bolt_dodgeable) {
                                if (rng.percent(combat.chanceOfAttackEvaded(victim, caster))) {
                                    state.messageAboutMob(victim, caster_coord, .CombatUnimportant, "dodge the {s}.", .{self.name}, "dodges the {s}.", .{self.name});
                                    continue;
                                }
                            }
                        }

                        affected_tiles.append(c) catch err.wat();

                        // Stop if we're not multi-targeting or if the blocking object
                        // isn't a mob
                        if (!self.bolt_multitarget or hit_mob == null)
                            break;
                    }
                    last_processed_coord = c;
                }

                if (self.bolt_animation) |anim_type| switch (anim_type) {
                    .Simple => |simple_anim| {
                        ui.Animation.apply(.{ .TraverseLine = .{
                            .start = caster_coord,
                            .end = last_processed_coord,
                            .char = simple_anim.char,
                            .fg = simple_anim.fg,
                        } });
                    },
                    .Type2 => |type2_anim| {
                        ui.Animation.apply(.{ .AnimatedLine = .{
                            .start = caster_coord,
                            .end = last_processed_coord,
                            .approach = type2_anim.approach,
                            .chars = type2_anim.chars,
                            .fg = type2_anim.fg,
                            .bg = type2_anim.bg,
                            .bg_mix = type2_anim.bg_mix,
                        } });
                    },
                };

                if (self.bolt_last_coord_effect) |func|
                    (func)(caster_coord, opts, last_processed_coord);

                for (affected_tiles.items) |coord| {
                    switch (self.effect_type) {
                        .Status => |s| if (state.dungeon.at(coord).mob) |victim| {
                            victim.addStatus(s, opts.power, .{ .Tmp = opts.duration });
                        },
                        .Heal => err.bug("Bolt of healing? really?", .{}),
                        .Custom => |cu| cu(caster_coord, self, opts, coord),
                    }
                }
            },
            .Smite => {
                switch (self.smite_target_type) {
                    .Self, .Mob, .SpecificMob, .UndeadAlly => {
                        if (state.dungeon.at(target).mob == null) {
                            err.bug("Mage used smite-targeted spell on empty target!", .{});
                        }

                        if (self.smite_target_type == .SpecificMob) {
                            const wanted_id = self.smite_target_type.SpecificMob;
                            const got_id = state.dungeon.at(target).mob.?.id;
                            if (!mem.eql(u8, got_id, wanted_id)) {
                                err.bug("Mage cast {s} at wrong mob! (Wanted {s}; got {s})", .{
                                    self.id, wanted_id, got_id,
                                });
                            }
                        }

                        const mob = state.dungeon.at(target).mob.?;

                        if (self.checks_will and !willSucceedAgainstMob(caster.?, mob)) {
                            const chance = 100 - appxChanceOfWillOverpowered(caster.?, mob);
                            if (state.player.cansee(mob.coord) or state.player.cansee(caster_coord)) {
                                state.message(.SpellCast, "{c} resisted $g($c{}%$g chance)$.", .{ mob, chance });
                            }
                            return;
                        }

                        switch (self.effect_type) {
                            .Status => |s| mob.addStatus(s, opts.power, .{ .Tmp = opts.duration }),
                            .Heal => mob.takeHealing(opts.power),
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
                            .Heal => err.bug("Mage tried to heal a corpse!!!", .{}),
                            .Custom => |c| c(caster_coord, self, opts, target),
                        }
                    },
                }
            },
        }
    }
};
