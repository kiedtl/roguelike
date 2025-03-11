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
const alert = @import("alert.zig");
const colors = @import("colors.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const explosions = @import("explosions.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const mobs = @import("mobs.zig");
const player = @import("player.zig");
const rng = @import("rng.zig");
const sound = @import("sound.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const AIJob = types.AIJob;
const Coord = types.Coord;
const Damage = types.Damage;
const DamageMessage = types.DamageMessage;
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

// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const StackBuffer = @import("buffer.zig").StackBuffer;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// -----------------------------------------------------------------------------

// Create spell that summons creatures from a corpse.
fn newCorpseSpell(
    comptime mob_id: []const u8,
    comptime name: []const u8,
    comptime msg_name: []const u8,
    template: *const mobs.MobTemplate,
    animation: Spell.Animation.Particle,
) Spell {
    return Spell{
        .id = "sp_call_" ++ mob_id,
        .name = "call " ++ name,
        .cast_type = .Smite,
        .smite_target_type = .Corpse,
        .animation = .{ .Particles = animation },
        .effects = &[_]Effect{.{
            .Custom = struct {
                fn f(caster_coord: Coord, _: SpellOptions, coord: Coord) void {
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
                        const m = mobs.placeMob(state.alloc, template, loc, .{});

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

                        // TODO: remove?
                        if (state.player.cansee(coord)) {
                            state.message(
                                .SpellCast,
                                msg_name ++ " bursts out of the {s} corpse!",
                                .{corpse.displayName()},
                            );
                        }
                    }
                }
            }.f,
        }},
    };
}

pub const CAST_CREATE_BLOAT = newCorpseSpell("bloat", "bloat", "Bloats", &mobs.BloatTemplate, .{ .name = "chargeover-purple-green" });
pub const CAST_CREATE_EMBERLING = newCorpseSpell("emberling", "emberling", "Emberlings", &mobs.EmberlingTemplate, .{ .name = "spawn-emberlings" });
pub const CAST_CREATE_SPARKLING = newCorpseSpell("sparkling", "sparkling", "Sparklings", &mobs.SparklingTemplate, .{ .name = "spawn-sparklings" });

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
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_coord: Coord, _: SpellOptions, _: Coord) void {
                ai.alertAllyOfHostile(state.dungeon.at(caster_coord).mob.?);
            }
        }.f,
    }},
};

pub const CAST_SCHEDULE_ALARM_PULL = Spell{
    .id = "sp_alarm",
    .name = "find alarm",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .noise = .Loud,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(_: Coord, _: SpellOptions, target: Coord) void {
                const mob = state.dungeon.at(target).mob.?;
                if (mob.hasJob(.ALM_PullAlarm) == null) {
                    mob.newJob(.ALM_PullAlarm);
                    mob.newestJob().?.ctx.set(*Mob, AIJob.CTX_ALARM_TARGET, ai.closestEnemy(mob).mob);
                }
            }
        }.f,
    }},
};

pub const CAST_ALERT_SIREN = Spell{
    .id = "sp_alert_siren",
    .name = "sound siren",
    .cast_type = .Smite,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(_: Coord, opts: SpellOptions, target: Coord) void {
                state.message(.Info, "You hear an ominous alarm blaring.", .{});
                alert.queueThreatResponse(.{ .Assault = .{
                    .waves = opts.power,
                    .target = state.dungeon.at(target).mob.?,
                } });
            }
        }.f,
    }},
};

// Power is the index into mobs.ANGELS. Yes, a weird hack.
//
pub const CAST_MOTH_TRANSFORM = Spell{
    .id = "sp_moth_transform",
    .name = "transform",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = struct {
        // No hostiles can see me change, unless I can't see them
        fn f(caster: *Mob, _: SpellOptions, _: Coord) bool {
            return for (caster.enemyList().items) |enemy| {
                if (enemy.mob.canSeeMob(caster) and caster.canSeeMob(enemy.mob))
                    break false;
            } else true;
        }
    }.f,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_coord: Coord, opts: SpellOptions, _: Coord) void {
                const caster = state.dungeon.at(caster_coord).mob.?;
                state.dungeon.at(caster_coord).mob = null; // Hack
                const new = mobs.placeMob(state.alloc, mobs.ANGELS[opts.power], caster.coord, .{});
                new.enemies = caster.enemyList().clone() catch err.oom();
                caster.coord = Coord.new2(0, 0, 0);
                caster.deinitNoCorpse();
            }
        }.f,
    }},
};

pub const BLAST_DISRUPTING_AOE = 5;

// Power affects duration of Torment Undead, as well as amount of disruption.
//
pub const BLAST_DISRUPTING = Spell{
    .id = "sp_disrupting_blast",
    .name = "disrupting blast",
    .animation = .{ .Particles = .{ .name = "explosion-green" } },
    .cast_type = .{ .Blast = .{ .aoe = BLAST_DISRUPTING_AOE } },
    .smite_target_type = .Self,
    .checks_will = true,
    .check_has_effect = struct {
        // There must be hostile undead visible and in range.
        //
        fn f(caster: *Mob, _: SpellOptions, _: Coord) bool {
            return for (caster.enemyList().items) |enemy| {
                if (caster.canSeeMob(enemy.mob) and
                    enemy.mob.life_type == .Undead and
                    enemy.mob.distance(caster) <= BLAST_DISRUPTING_AOE)
                {
                    break true;
                }
            } else false;
        }
    }.f,
    .effects = &[_]Effect{
        .{ .Status = .TormentUndead },
        .{ .Custom = struct {
            fn f(_: Coord, opts: SpellOptions, target_coord: Coord) void {
                if (state.dungeon.at(target_coord).mob) |target|
                    if (target.life_type == .Undead)
                        combat.disruptIndividualUndead(target, opts.power);
            }
        }.f },
    },
};

pub const CAST_ROLLING_BOULDER_DAMAGE = 3;
pub const CAST_ROLLING_BOULDER = Spell{
    .id = "sp_rolling_boulder",
    .name = "rolling boulder",
    .animation = .{ .Particles = .{ .name = "chargeover-walls", .target = .Origin } },
    .cast_type = .Smite,
    .check_has_effect = struct {
        // Enemy must be far away, must have line of fire, must have adjacent
        // space that's free, must have adjacent wall, and there must be no
        // allies in view.
        fn f(caster: *Mob, _: SpellOptions, target: Coord) bool {
            const d = caster.coordMT(target).closestDirectionTo(target, state.mapgeometry);
            const n = caster.coord.move(d, state.mapgeometry).?;
            return state.is_walkable(n, .{ .right_now = true }) and
                state.dungeon.neighboringWalls(caster.coord, true) > 0 and
                target.distance(caster.coord) >= 4 and
                utils.hasStraightPath(n, target);
        }
    }.f,
    .effects = &[_]Effect{
        .{
            .Custom = struct {
                fn f(caster_coord: Coord, _: SpellOptions, target_coord: Coord) void {
                    const caster = state.dungeon.at(caster_coord).mob.?;
                    const target = state.dungeon.at(target_coord).mob.?;
                    // Remove a single wall, for flavor.
                    var directions = DIRECTIONS;
                    rng.shuffle(Direction, &directions);
                    for (&directions) |d| if (caster_coord.move(d, state.mapgeometry)) |neighbor| {
                        if (state.dungeon.at(neighbor).type == .Wall) {
                            state.dungeon.at(neighbor).type = .Floor;
                            break;
                        }
                    };
                    const d = caster.coordMT(target_coord).closestDirectionTo(target_coord, state.mapgeometry);
                    const n = caster.coord.move(d, state.mapgeometry).?;
                    const b = mobs.placeMob(state.alloc, &mobs.RollingBoulderTemplate, n, .{});
                    b.newJob(.ATK_Homing);
                    b.newestJob().?.ctx.set(*Mob, AIJob.CTX_HOMING_TARGET, target);
                    b.newestJob().?.ctx.set(f64, AIJob.CTX_HOMING_SPEED, 0.6);
                    b.newestJob().?.ctx.set(bool, AIJob.CTX_HOMING_BLAST, false);
                }
            }.f,
        },
    },
};

// Zap animation used despite this being a smite spell... lol
//
pub const CAST_REBUKE_EARTH_DEMON = Spell{
    .id = "sp_rebuke_earth_demon",
    .name = "rebuke earth demon",
    .animation = .{ .Particles = .{ .name = "lzap-green" } },
    .cast_type = .Smite,
    .smite_target_type = .{ .SpecificMob = "revgenunkim" },
    .effects = &[_]Effect{
        .{ .Damage = .{ .kind = .Holy, .msg = .{ .basic = true } } },
        .{ .Custom = struct {
            fn f(caster_coord: Coord, _: SpellOptions, target_coord: Coord) void {
                const caster = state.dungeon.at(caster_coord).mob.?;
                const target = state.dungeon.at(target_coord).mob.?;
                combat.rebukeEarthDemon(caster, target);
            }
        }.f },
    },
};

pub const CAST_CALL_UNDEAD = Spell{
    .id = "sp_call_undead",
    .name = "call undead",
    .cast_type = .Smite,
    .checks_will = true,
    .animation = .{ .Particles = .{ .name = "beams-call-undead" } },
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_coord: Coord, opts: SpellOptions, target: Coord) void {
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
                            if (candidate.faction == caster.faction and
                                (candidate.life_type == .Undead or candidate.ai.flag(.CalledWithUndead)) and
                                !candidate.ai.flag(.NotCalledWithUndead) and
                                candidate.isAloneOrLeader() and
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
    }},
};

pub const CAST_ENGINE = Spell{
    .id = "sp_sprint_engine",
    .name = "overpowered engine",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = struct {
        // Enemy must be far far away
        fn f(caster: *Mob, opts: SpellOptions, _: Coord) bool {
            return ai.closestEnemy(caster).mob.distance(caster) > opts.power;
        }
    }.f,
    .noise = .Louder,
    .effects = &[_]Effect{.{ .Status = .Fast }},
};

pub const CAST_DIVINE_REGEN = Spell{
    .id = "sp_regen_divine",
    .name = "divine regeneration",
    .cast_type = .Smite,
    .smite_target_type = .AngelAlly,
    .check_has_effect = struct {
        // Only use the spell if the target's HP is below
        // the (regeneration_amount * 2).
        //
        // TODO: we should have a way to flag this spell as an "emergency"
        // spell, ensuring it's only used when the caster is clearly losing a
        // fight
        fn f(_: *Mob, opts: SpellOptions, target: Coord) bool {
            return state.dungeon.at(target).mob.?.HP <= (opts.power * 2);
        }
    }.f,
    .noise = .Loud,
    .effects = &[_]Effect{.Heal},
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
            return caster.HP <= (opts.power * 3);
        }
    }.f,
    .noise = .Loud,
    .effects = &[_]Effect{.Heal},
};

// Spells that give specific status to specific class of mobs. {{{

fn _createSpecificStatusSp(comptime id: []const u8, name: []const u8, anim: []const u8, status_str: []const u8, s: Status) Spell {
    return Spell{
        .id = "sp_" ++ status_str ++ "_" ++ id,
        .name = status_str ++ " " ++ name,
        .animation = .{ .Particles = .{ .name = anim } },
        .cast_type = .Smite,
        .smite_target_type = .{ .SpecificAlly = id },
        .effects = &[_]Effect{.{ .Status = s }},
    };
}

pub const CAST_ENRAGE_BONE_RAT = _createSpecificStatusSp("bone_rat", "bone rat", "glow-white-gray", "enrage", .Enraged);
pub const CAST_FIREPROOF_EMBERLING = _createSpecificStatusSp("emberling", "emberling", "glow-cream", "fireproof", .Fireproof);
pub const CAST_FIREPROOF_DUSTLING = _createSpecificStatusSp("dustling", "dustling", "glow-cream", "fireproof", .Fireproof);
pub const CAST_ENRAGE_DUSTLING = _createSpecificStatusSp("dustling", "dustling", "glow-cream", "enrage", .Enraged);

// Only works if angel's AI routine is ai.meleeFight
// FIXME: I feel really bad about hardcoding this :/
//
pub const CAST_ENRAGE_ANGEL = Spell{
    .id = "sp_enrage_angel",
    .name = "enrage angel",
    .animation = .{ .Particles = .{ .name = "glow-cream" } },
    .cast_type = .Smite,
    .smite_target_type = .AngelAlly,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            return state.dungeon.at(target).mob.?.ai.fight_fn == ai.meleeFight;
        }
    }.f,
    .effects = &[_]Effect{.{ .Status = .Enraged }},
};

// }}}

pub const CAST_AWAKEN_CONSTRUCT = Spell{
    .id = "sp_awaken_construct",
    .name = "awaken construct",
    .cast_type = .Smite,
    .smite_target_type = .ConstructAlly,
    .animation = .{ .Particles = .{ .name = "zap-awaken-construct" } },
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            return state.dungeon.at(target).mob.?.hasStatus(.Sleeping);
        }
    }.f,
    .noise = .Silent,
    .effects = &[_]Effect{.{ .Custom = struct {
        fn f(_: Coord, _: SpellOptions, target: Coord) void {
            state.dungeon.at(target).mob.?.cancelStatus(.Sleeping);
        }
    }.f }},
};

pub const CAST_FIREBLAST = Spell{
    .id = "sp_fireblast",
    .name = "vomit flames",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .animation = .{ .Particles = .{ .name = "explosion-fire1", .target = .Power } },
    .check_has_effect = struct {
        fn f(caster: *Mob, opts: SpellOptions, target: Coord) bool {
            return opts.power >= target.distance(caster.coord);
        }
    }.f,
    .noise = .Loud,
    .effects = &[_]Effect{
        .{ .FireBlast = .{ .radius = .Power, .damage = .{ .Fixed = 0 } } },
    },
};

// Could make this will-checked, but it'd never succeed against angels then.
pub const CAST_RESIST_WRATH_CHANCE: usize = 20;
pub const CAST_RESIST_WRATH = Spell{
    .id = "sp_resist_wrath",
    .name = "resist divine wrath",
    .cast_type = .Smite,
    //.animation = .{ .Particles = .{ .name = "chargeover-orange-red" } },
    .noise = .Silent,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target_coord: Coord) bool {
            const target = state.dungeon.at(target_coord).mob orelse return false;
            // In practice would be good to have an "AngelEnemy" smite target,
            // but too much complexity for one spell I think.
            return target.innate_resists.rHoly == mobs.RESIST_IMMUNE and
                target.life_type == .Spectral;
        }
    }.f,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_coord: Coord, opts: SpellOptions, target_coord: Coord) void {
                const caster = state.dungeon.at(caster_coord).mob.?;
                const target = state.dungeon.at(target_coord).mob.?;
                if (rng.percent(CAST_RESIST_WRATH_CHANCE)) {
                    // Only use animation if it succeeds.
                    ui.Animation.apply(.{ .Particle = .{
                        .name = "zap-resist-divine-wrath",
                        .coord = caster_coord,
                        .target = .{ .C = target_coord },
                    } });

                    target.takeDamage(.{
                        .amount = opts.power,
                        .by_mob = caster,
                        .kind = .Irresistible,
                        .blood = false,
                        .source = .RangedAttack,
                    }, .{
                        .strs = &[_]types.DamageStr{
                            items._dmgstr(1, "desperately resist", "desperately resists", ""),
                        },
                    });
                }
            }
        }.f,
    }},
};

pub const BOLT_AIRBLAST = Spell{
    .id = "sp_airblast",
    .name = "airblast",
    .animation = .{ .Particles = .{ .name = "zap-air-messy" } },
    .cast_type = .Bolt,
    .bolt_multitarget = false,
    .check_has_effect = struct {
        fn f(caster: *Mob, opts: SpellOptions, c: Coord) bool {
            return caster.coord.distance(c) < opts.power;
        }
    }.f,
    .noise = .Loud,
    .effects = &[_]Effect{.{ .Custom = struct {
        fn f(caster_c: Coord, opts: SpellOptions, coord: Coord) void {
            if (state.dungeon.at(coord).mob) |victim| {
                state.message(.Combat, "The blast of air hits {}!", .{victim});
                const distance = victim.coord.distance(caster_c);
                assert(distance < opts.power);
                const knockback = opts.power - distance;
                const direction = caster_c.closestDirectionTo(coord, state.mapgeometry);
                combat.throwMob(state.dungeon.at(caster_c).mob, victim, direction, knockback);
            } else err.wat();
        }
    }.f }},
};

pub const BOLT_FIERY_JAVELIN = Spell{
    .id = "sp_javelin_fire",
    .name = "fiery javelin",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_missable = true,
    .bolt_multitarget = false,
    .animation = .{ .Particles = .{ .name = "zap-bolt-fiery" } },
    .noise = .Loud,
    .effects = &[_]Effect{
        .{ .Damage = .{ .msg = .{ .noun = "The blazing javelin", .strs = &items.PIERCING_STRS } } },
        .{ .Damage = .{ .kind = .Fire, .msg = .{ .noun = "The blazing javelin", .strs = &items.PIERCING_STRS } } },
    },
};

pub const BOLT_JAVELIN = Spell{
    .id = "sp_javelin",
    .name = "javelin",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_missable = true,
    .bolt_multitarget = false,
    .animation = .{ .Particles = .{ .name = "zap-bolt" } },
    .noise = .Medium,
    .check_has_effect = struct {
        fn f(caster: *Mob, _: SpellOptions, target: Coord) bool {
            return caster.distance2(target) >= 2;
        }
    }.f,
    .effects = &[_]Effect{
        .{ .Damage = .{ .msg = .{ .noun = "The javelin", .strs = &items.PIERCING_STRS } } },
        .{ .Status = .Disorient },
    },
};

pub const BOLT_BOLT = Spell{
    .id = "sp_bolt",
    .name = "crossbow",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_missable = true,
    .bolt_multitarget = false,
    .animation = .{ .Particles = .{ .name = "zap-bolt" } },
    .noise = .Medium,
    .effects = &[_]Effect{
        .{ .Damage = .{ .msg = .{ .noun = "The bolt", .strs = &items.PIERCING_STRS } } },
    },
};

pub const BOLT_SPEEDING = Spell{
    .id = "sp_speeding",
    .name = "speeding bolt",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_missable = true,
    .bolt_multitarget = true, // Yes, TRUE, I did this deliberately :P
    .animation = .{ .Particles = .{ .name = "zap-speeding-bolt" } },
    .noise = .Medium,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_coord: Coord, _: SpellOptions, target: Coord) void {
                const victim = state.dungeon.at(target).mob orelse return;
                // NOTE: update spell description if tweaking this.
                const damage = math.clamp(target.distance(caster_coord) / 2, 1, 5);
                victim.takeDamage(.{
                    .amount = damage,
                    .source = .RangedAttack,
                    .by_mob = state.dungeon.at(caster_coord).mob,
                    .kind = .Irresistible,
                    .blood = false,
                }, .{
                    .noun = "The speeding bolt",
                    .strs = &items.PIERCING_STRS,
                });
            }
        }.f,
    }},
};

pub const CAST_MASS_DISMISSAL = Spell{
    .id = "sp_mass_dismissal",
    .name = "mass dismissal",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .check_has_effect = _hasEffectMassDismissal,
    .noise = .Quiet,
    .effects = &[_]Effect{.{ .Custom = _effectMassDismissal }},
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
fn _effectMassDismissal(caster: Coord, opts: SpellOptions, _: Coord) void {
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

pub const BOLT_PULL_FOE = Spell{
    .id = "sp_pull_enemy",
    .name = "yank foe",
    .cast_type = .Smite,
    .animation = .{ .Particles = .{ .name = "zap-pull-foe" } },
    .smite_target_type = .Mob,
    .needs_visible_target = true,
    .check_has_effect = struct {
        fn f(caster: *Mob, _: SpellOptions, target: Coord) bool {
            const target_m = state.dungeon.at(target).mob.?;
            const need_to = caster.distance(target_m) > 1 and !caster.canMelee(target_m);
            if (!need_to) return false;

            // Is there a place to yoink our enemy
            for (&DIRECTIONS) |d| if (caster.coord.move(d, state.mapgeometry)) |n| {
                if (utils.hasClearLOF(target_m.coord, n))
                    return true;
            };

            return false;
        }
    }.f,
    .noise = .Quiet,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_coord: Coord, _: SpellOptions, coord: Coord) void {
                const target_mob = state.dungeon.at(coord).mob.?;

                var dest = caster_coord;
                for (&DIRECTIONS) |d|
                    if (caster_coord.move(d, state.mapgeometry)) |n|
                        if (utils.hasClearLOF(target_mob.coord, n) and
                            n.distance(coord) < dest.distance(coord))
                        {
                            dest = n;
                        };

                _ = target_mob.teleportTo(dest, null, true, false);
            }
        }.f,
    }},
};

pub const CAST_SUMMON_ENEMY = Spell{
    .id = "sp_summon_enemy",
    .name = "summon enemy",
    .cast_type = .Smite,
    .smite_target_type = .Mob,
    .checks_will = true,
    .needs_visible_target = false,
    .check_has_effect = _hasEffectSummonEnemy,
    .noise = .Quiet,
    .effects = &[_]Effect{.{ .Custom = _effectSummonEnemy }},
};
fn _hasEffectSummonEnemy(caster: *Mob, _: SpellOptions, target: Coord) bool {
    const mob = state.dungeon.at(target).mob.?;
    return (mob == state.player or mob.ai.phase == .Flee) and
        !caster.cansee(mob.coord);
}
fn _effectSummonEnemy(caster: Coord, _: SpellOptions, coord: Coord) void {
    const caster_mob = state.dungeon.at(caster).mob.?;
    const target_mob = state.dungeon.at(coord).mob.?;

    // Find a spot in caster's LOS
    var new: ?Coord = null;
    var farthest_dist: usize = 0;
    for (caster_mob.fov, 0..) |row, y| {
        for (row, 0..) |cell, x| {
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
        _ = target_mob.teleportTo(newcoord, null, true, false);

        state.messageAboutMob(target_mob, caster, .SpellCast, "are dragged back to the {s}!", .{caster_mob.displayName()}, "is dragged back to the {s}!", .{caster_mob.displayName()});
    }
}

pub const BLAST_DISPERSAL_AOE = 2;
pub const BLAST_DISPERSAL = Spell{
    .id = "sp_dismissal_aura",
    .name = "aura of dispersal",
    .cast_type = .{ .Blast = .{ .aoe = BLAST_DISPERSAL_AOE, .avoids_allies = true } },
    .smite_target_type = .Self,
    .check_has_effect = _hasEffectAuraDispersal,
    .noise = .Silent,
    .effects = &[_]Effect{.{ .Custom = _effectAuraDispersal }},
};
fn _hasEffectAuraDispersal(caster: *Mob, _: SpellOptions, _: Coord) bool {
    return ai.closestEnemy(caster).mob.distance(caster) <= BLAST_DISPERSAL_AOE;
}
fn _effectAuraDispersal(caster_coord: Coord, _: SpellOptions, target_coord: Coord) void {
    const caster = state.dungeon.at(caster_coord).mob.?;
    if (state.dungeon.at(target_coord).mob) |mob| {
        // Find a new home
        var new: ?Coord = null;
        var farthest_dist: usize = 0;
        for (caster.fov, 0..) |row, y| {
            for (row, 0..) |cell, x| {
                const fitem = Coord.new2(caster.coord.z, x, y);
                const dist = fitem.distance(caster_coord);
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
            _ = mob.teleportTo(newcoord, null, true, false);
            mob.addStatus(.Daze, 0, .{ .Tmp = 3 });
        }
    }
}

// pub const CAST_CONJ_SPECTRAL_SWORD = Spell{
//     .id = "sp_conj_ss",
//     .name = "conjure spectral sword",
//     .cast_type = .Smite,
//     .smite_target_type = .Self,
//     .noise = .Silent,
//     .effects = &[_]Effect{.{
//         .Custom = struct {
//             fn f(_: Coord, _: SpellOptions, coord: Coord) void {
//                 for (&CARDINAL_DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
//                     if (state.is_walkable(neighbor, .{ .right_now = true })) {
//                         // FIXME: passing allocator directly is anti-pattern?
//                         _ = mobs.placeMob(state.alloc, &mobs.SpectralSwordTemplate, neighbor, .{});
//                     }
//                 };
//             }
//         }.f,
//     }},
// };

pub fn spawnSabreSingle(caster: *Mob, coord: Coord) void {
    const rFire = @as(usize, 0) +
        (if (caster == state.player and player.hasAugment(.rFire_25)) @as(usize, 25) else 0) +
        (if (caster == state.player and player.hasAugment(.rFire_50)) @as(usize, 50) else 0);
    const rElec = @as(usize, 0) +
        (if (caster == state.player and player.hasAugment(.rElec_25)) @as(usize, 25) else 0) +
        (if (caster == state.player and player.hasAugment(.rElec_50)) @as(usize, 50) else 0);
    const Melee = @as(usize, 0) +
        (if (caster == state.player and player.hasAugment(.Melee)) @as(usize, 25) else 0);
    const Evade = @as(usize, 0) +
        (if (caster == state.player and player.hasAugment(.Evade)) @as(usize, 25) else 0);

    const ss = mobs.placeMob(state.alloc, &mobs.SpectralSabreTemplate, coord, .{});
    ss.innate_resists.rFire += @intCast(rFire);
    ss.innate_resists.rElec += @intCast(rElec);
    ss.stats.Melee += @intCast(Melee);
    ss.stats.Evade += @intCast(Evade);
    caster.addUnderling(ss);
}

pub fn spawnSabreVolley(caster: *Mob, coord: Coord) void {
    var directions = DIRECTIONS;
    rng.shuffle(Direction, &directions);

    var spawned_ctr: usize = @intCast(caster.stat(.Conjuration));

    if (state.is_walkable(coord, .{ .right_now = true })) {
        spawnSabreSingle(caster, coord);
        spawned_ctr -= 1;
    }

    for (&directions) |d| {
        if (spawned_ctr == 0)
            break;

        if (coord.move(d, state.mapgeometry)) |neighbor| {
            if (state.is_walkable(neighbor, .{ .right_now = true })) {
                spawnSabreSingle(caster, neighbor);

                spawned_ctr -= 1;
            }
        }
    }
}

pub const BOLT_CONJURE = Spell{
    .id = "sp_conj_ss_bolt",
    .name = "conjure spectral sabre",
    .cast_type = .Bolt,
    .bolt_multitarget = false,
    .animation = .{ .Particles = .{ .name = "zap-conjuration" } },
    .noise = .Silent,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_c: Coord, _: SpellOptions, coord: Coord) void {
                const caster = state.dungeon.at(caster_c).mob.?;
                spawnSabreVolley(caster, coord);
            }
        }.f,
    }},
};

pub const BOLT_HELLFIRE_ELECTRIC = Spell{
    .id = "sp_hellfire_electric",
    .name = "electric hellfire",
    .cast_type = .Bolt,
    .bolt_avoids_allies = true,
    .bolt_multitarget = false,
    .animation = .{ .Particles = .{ .name = "zap-hellfire-electric" } },
    .noise = .Loud,
    .effects = &[_]Effect{
        .{ .Damage = .{ .kind = .Holy, .msg = .{
            .noun = "The electric damnation",
            .strs = &[_]types.DamageStr{items._dmgstr(0, "sears", "sears", "")},
        } } },
        .{ .Damage = .{ .kind = .Electric, .msg = .{
            .noun = "The red lightning",
            .strs = &items.SHOCK_STRS,
        } } },
    },
};

pub const BOLT_HELLFIRE = Spell{
    .id = "sp_hellfire",
    .name = "bolt of hellfire",
    .cast_type = .Bolt,
    .bolt_aoe = 2, // XXX: Need to update particle effect if changing this
    .bolt_avoids_allies = true,
    .bolt_multitarget = false,
    .animation = .{ .Particles = .{ .name = "zap-hellfire" } },
    .noise = .Louder,
    .effects = &[_]Effect{.{ .Damage = .{ .kind = .Holy, .msg = .{
        .noun = "The tormenting fire",
        .strs = &[_]types.DamageStr{items._dmgstr(0, "engulfs", "engulfs", "")},
    } } }},
};

pub const BLAST_HELLFIRE_AOE = 2;
pub const BLAST_HELLFIRE = Spell{
    .id = "sp_hellfire_blast",
    .name = "hellfire blast",
    .cast_type = .{ .Blast = .{ .aoe = BLAST_HELLFIRE_AOE, .avoids_caster = true } },
    .animation = .{ .Particles = .{ .name = "explosion-hellfire", .target = .Origin } },
    .noise = .Loudest,
    .check_has_effect = struct {
        // There must be hostiles visible and in range.
        //
        fn f(caster: *Mob, _: SpellOptions, _: Coord) bool {
            return for (caster.enemyList().items) |enemy| {
                if (enemy.mob.innate_resists.rHoly <= 0 and
                    enemy.mob.distance(caster) <= BLAST_HELLFIRE_AOE)
                {
                    break true;
                }
            } else false;
        }
    }.f,
    .effects = &[_]Effect{.{ .Damage = .{ .kind = .Holy, .msg = .{
        .noun = "The blast of hellfire",
        .strs = &[_]types.DamageStr{items._dmgstr(0, "engulfs", "engulfs", "")},
    } } }},
};

pub const BOLT_AOE_AMNESIA = Spell{
    .id = "sp_amnesia_bolt",
    .name = "mass amnesia",
    .cast_type = .Bolt,
    .bolt_multitarget = false,
    .bolt_avoids_allies = true,
    // .checks_will = true,
    .bolt_aoe = 4, // XXX: Need to update particle effect if changing this
    .animation = .{ .Particles = .{ .name = "zap-mass-amnesia" } },
    .noise = .Silent,
    .effects = &[_]Effect{.{ .Status = .Amnesia }},
};

pub const BOLT_AOE_INSANITY = Spell{
    .id = "sp_insanity_bolt",
    .name = "mass insanity",
    .cast_type = .Bolt,
    .bolt_multitarget = false,
    .bolt_avoids_allies = true,
    .checks_will = true,
    .bolt_aoe = 4, // XXX: Need to update particle effect if changing this
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return mob.allies.items.len > 0;
        }
    }.f,
    .animation = .{ .Particles = .{ .name = "zap-mass-insanity" } },
    .noise = .Silent,
    .effects = &[_]Effect{.{ .Status = .Insane }},
};

pub const CAST_CONJ_BALL_LIGHTNING = Spell{
    .id = "sp_conj_bl",
    .name = "conjure ball lightning",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .noise = .Quiet,
    .effects = &[_]Effect{.{ .Custom = _effectConjureBL }},
};
fn _effectConjureBL(_: Coord, opts: SpellOptions, coord: Coord) void {
    for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, .{ .right_now = true })) {
            // FIXME: passing allocator directly is anti-pattern?
            const w = mobs.placeMob(state.alloc, &mobs.BallLightningTemplate, neighbor, .{});
            w.addStatus(.Lifespan, 0, .{ .Tmp = opts.power });
            return;
        }
    };
}

pub const SUPER_DAMNATION = Spell{
    .id = "sp_damnation",
    .name = "damnation",
    .cast_type = .Smite,
    .smite_target_type = .Self,
    .noise = .Loud,
    .effects = &[_]Effect{.{ .Custom = struct {
        fn f(caster_c: Coord, opts: SpellOptions, coord: Coord) void {
            const SPELL = Spell{
                .id = "_",
                .name = "[this is a bug]",
                .animation = .{ .Particles = .{ .name = "lzap-fire-quick" } },
                .cast_type = .Bolt,
                .noise = .Medium,
                .effects = &[_]Effect{.{ .Custom = struct {
                    fn f(_caster_c: Coord, _opts: SpellOptions, _coord: Coord) void {
                        const caster = state.dungeon.at(_caster_c).mob.?;
                        if (state.dungeon.at(_coord).mob) |victim| {
                            if (victim.isHostileTo(caster)) {
                                explosions.fireBurst(_coord, 1, .{ .culprit = caster, .initial_damage = _opts.power });
                            }
                        }
                    }
                }.f }},
            };

            const directions = [_]Direction{
                opts.context_direction1.turnleft(),
                opts.context_direction1.turnright(),
            };
            for (&directions) |direction| {
                const target = utils.getFarthestWalkableCoord(direction, coord, .{ .only_if_breaks_lof = true, .ignore_mobs = true });
                SPELL.use(state.dungeon.at(caster_c).mob, coord, target, .{ .MP_cost = 0, .spell = &SPELL, .power = opts.power, .free = true, .no_message = true });
            }
        }
    }.f }},
};

pub const BOLT_PARALYSE = Spell{
    .id = "sp_elec_paralyse",
    .name = "paralysing zap",
    .animation = .{ .Particles = .{ .name = "zap-electric-charging" } },
    .cast_type = .Bolt,
    .noise = .Medium,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .effects = &[_]Effect{.{ .Custom = struct {
        fn f(caster_c: Coord, opts: SpellOptions, coord: Coord) void {
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
    }.f }},
};

pub const BOLT_SPINNING_SWORD = Spell{
    .id = "sp_spinning_sword",
    .name = "ethereal spin",
    .cast_type = .Bolt,
    .noise = .Loud,
    .animation = .{ .Particles = .{ .name = "zap-sword" } },
    // Commented out because it'll never be called
    //
    // .check_has_effect = struct {
    //     fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
    //         const mob = state.dungeon.at(target).mob.?;
    //         return !mob.isFullyResistant(.Armor);
    //     }
    // }.f,

    // Don't use new effects system, because I can't be bothered to test it, and
    // anyways no benefit is gained really (since the spell will never be
    // examined)
    //
    // .effects = &[_]Effect{
    //     .{ .Damage = .{ .msg = .{ .strs = &items.SLASHING_STRS } } },
    //     .{ .Status = .Held },
    // },
    .effects = &[_]Effect{.{ .Custom = struct {
        fn f(caster_c: Coord, opts: SpellOptions, coord: Coord) void {
            const caster = state.dungeon.at(caster_c).mob.?;
            if (state.dungeon.at(coord).mob) |victim| {
                if (!victim.isHostileTo(caster)) return;
                victim.takeDamage(.{ .amount = opts.power, .source = .RangedAttack, .by_mob = caster }, .{ .strs = &items.SLASHING_STRS });
                victim.addStatus(.Held, 0, .{ .Tmp = opts.power });
            }
        }
    }.f }},

    .bolt_last_coord_effect = struct {
        pub fn f(caster_coord: Coord, _: SpellOptions, coord: Coord) void {
            if (state.is_walkable(coord, .{ .right_now = true }))
                _ = state.dungeon.at(caster_coord).mob.?.teleportTo(coord, null, true, false);
        }
    }.f,
};

pub const BOLT_BLINKBOLT = Spell{
    .id = "sp_elec_blinkbolt",
    .name = "lightning flyover",
    .cast_type = .Bolt,
    .noise = .Loud,
    .animation = .{ .Particles = .{ .name = "zap-electric" } },
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .effects = &[_]Effect{
        .{ .Damage = .{ .kind = .Electric, .blood = false, .msg = .{ .strs = &items.SHOCK_STRS } } },
    },
    .bolt_last_coord_effect = struct {
        pub fn f(caster_coord: Coord, _: SpellOptions, coord: Coord) void {
            if (state.is_walkable(coord, .{ .right_now = true }))
                _ = state.dungeon.at(caster_coord).mob.?.teleportTo(coord, null, true, false);
        }
    }.f,
};

pub const BOLT_IRON = Spell{
    .id = "sp_iron_bolt",
    .name = "iron arrow",
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_missable = true,
    .bolt_multitarget = false,
    .animation = .{ .Particles = .{ .name = "zap-iron-inacc" } },
    .noise = .Medium,
    .effects = &[_]Effect{
        .{ .Damage = .{ .msg = .{ .noun = "The iron arrow", .strs = &items.PIERCING_STRS } } },
    },
};

pub const BOLT_CRYSTAL = Spell{
    .id = "sp_crystal_shard",
    .name = "crystal shard",
    .animation = .{ .Particles = .{ .name = "zap-crystal-chargeover" } },
    .cast_type = .Bolt,
    .bolt_dodgeable = true,
    .bolt_multitarget = false,
    .noise = .Medium,
    .effects = &[_]Effect{
        .{ .Damage = .{ .amount = .PowerRangeHalf, .msg = .{ .noun = "The crystal shard", .strs = &items.PIERCING_STRS } } },
    },
};

pub const BOLT_LIGHTNING = Spell{
    .id = "sp_elec_bolt",
    .name = "bolt of electricity",
    .animation = .{ .Particles = .{ .name = "lzap-electric" } },
    .cast_type = .Bolt,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .noise = .Loud,
    .effects = &[_]Effect{
        .{ .Damage = .{ .kind = .Electric, .blood = false, .msg = .{ .noun = "The lightning bolt", .strs = &items.SHOCK_STRS } } },
    },
};

pub const BOLT_FIREBALL = Spell{
    .id = "sp_fireball",
    .name = "fireball",
    .animation = .{ .Particles = .{ .name = "zap-fire-messy" } },
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
    .effects = &[_]Effect{
        .{ .FireBlast = .{ .radius = .{ .Fixed = 1 }, .damage = .Power } },
        .{ .Status = .Fire },
    },
};

pub const CAST_ENRAGE_UNDEAD = Spell{
    .id = "sp_enrage_undead",
    .name = "enrage undead",
    .animation = .{ .Particles = .{ .name = "glow-white-gray" } },
    .cast_type = .Smite,
    .smite_target_type = .UndeadAlly,
    .effects = &[_]Effect{.{ .Status = .Enraged }},
    .checks_will = false,
};

pub const CAST_HEAL_UNDEAD = Spell{
    .id = "sp_heal_undead",
    .name = "heal undead",
    .animation = .{ .Particles = .{ .name = "chargeover-white-pink" } },
    .cast_type = .Smite,
    .smite_target_type = .UndeadAlly,
    .check_has_effect = _hasEffectHealUndead,
    .effects = &[_]Effect{.{ .Custom = _effectHealUndead }},
    .checks_will = false,
};
fn _hasEffectHealUndead(caster: *Mob, _: SpellOptions, target: Coord) bool {
    const mob = state.dungeon.at(target).mob.?;
    return mob.HP < (mob.max_HP / 2) and utils.getNearestCorpse(caster) != null;
}
fn _effectHealUndead(caster: Coord, _: SpellOptions, coord: Coord) void {
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
    .animation = .{ .Particles = .{ .name = "glow-purple" } },
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effects = &[_]Effect{.{ .Custom = _effectHastenRot }},
    .checks_will = false,
};
fn _effectHastenRot(_: Coord, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    state.dungeon.at(coord).surface = null;

    state.dungeon.atGas(coord)[gas.Miasma.id] = opts.power;
    if (state.player.cansee(coord)) {
        state.message(.SpellCast, "The {s} corpse explodes in a blast of foul miasma!", .{
            corpse.displayName(),
        });
    }
}

pub const CAST_RESURRECT_FIRE = Spell{
    .id = "sp_burnt_offering",
    .name = "burnt offering",
    .animation = .{ .Particles = .{ .name = "glow-orange-red" } },
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effects = &[_]Effect{.{ .Custom = _resurrectFire }},
    .checks_will = false,
};
fn _resurrectFire(caster_coord: Coord, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (corpse.raiseAsUndead(coord)) {
        if (state.player.cansee(coord)) {
            state.message(.SpellCast, "The {s} rises, burning with an unearthly flame!", .{
                corpse.displayName(),
            });
        }
        corpse.faction = state.dungeon.at(caster_coord).mob.?.faction;
        corpse.addStatus(.Fire, 0, .Prm);
        corpse.addStatus(.Fast, 0, .Prm);
        corpse.addStatus(.Explosive, opts.power, .Prm);
        corpse.addStatus(.Lifespan, opts.power, .{ .Tmp = 10 });
    }
}

pub const CAST_RESURRECT_FROZEN = Spell{
    .id = "sp_raise_frozen",
    .name = "frozen resurrection",
    .animation = .{ .Particles = .{ .name = "glow-blue-dblue" } },
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effects = &[_]Effect{.{ .Custom = _resurrectFrozen }},
    .checks_will = false,
};
fn _resurrectFrozen(_: Coord, opts: SpellOptions, coord: Coord) void {
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

pub const CAST_AWAKEN_STONE = Spell{
    .id = "sp_awaken_stone",
    .name = "awaken stone",
    .animation = .{ .Particles = .{ .name = "zap-awaken-stone" } },
    .cast_type = .Smite,
    .smite_target_type = .Mob,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            return state.dungeon.neighboringWalls(target, false) > 0;
        }
    }.f,
    .effects = &[_]Effect{.{
        .Custom = struct {
            fn f(caster_coord: Coord, opts: SpellOptions, coord: Coord) void {
                const caster = state.dungeon.at(caster_coord).mob.?;

                const mob = state.dungeon.at(coord).mob.?;
                for (&CARDINAL_DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.dungeon.at(neighbor).type == .Wall) {
                        state.dungeon.at(neighbor).type = .Floor;
                        const w = mobs.placeMob(state.alloc, &mobs.LivingStoneTemplate, neighbor, .{});
                        w.faction = caster.faction;
                        w.addStatus(.Lifespan, 0, .{ .Tmp = opts.power + 1 });
                        ai.updateEnemyKnowledge(w, mob, null);
                    }
                };

                if (mob == state.player) {
                    state.message(.SpellCast, "The walls near you awaken!", .{});
                } else if (state.player.cansee(mob.coord)) {
                    state.message(.SpellCast, "The walls near {} transmute into living stone!", .{mob});
                }
            }
        }.f,
    }},
};

pub const CAST_RESURRECT_NORMAL = Spell{
    .id = "sp_raise",
    .name = "resurrection",
    .animation = .{ .Particles = .{ .name = "pulse-twice-explosion", .target = .Origin, .coord_is_target = true } },
    .cast_type = .Smite,
    .smite_target_type = .Corpse,
    .effects = &[_]Effect{.{ .Custom = _resurrectNormal }},
    .checks_will = false,
};
fn _resurrectNormal(_: Coord, _: SpellOptions, coord: Coord) void {
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
    .animation = .{ .Particles = .{ .name = "pulse-twice-electric-explosion" } },
    .cast_type = .Smite,
    .check_has_effect = struct {
        fn f(_: *Mob, _: SpellOptions, target: Coord) bool {
            const mob = state.dungeon.at(target).mob.?;
            return !mob.isFullyResistant(.rElec);
        }
    }.f,
    .effects = &[_]Effect{.{ .Custom = struct {
        fn f(caster_c: Coord, _: SpellOptions, coord: Coord) void {
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
    }.f }},
};

pub const CAST_BARTENDER_FERMENT = Spell{
    .id = "sp_ferment_bartender",
    .name = "ferment",
    .cast_type = .Smite,
    .effects = &[_]Effect{.{ .Status = .Drunk }},
    //.checks_will = true,
};
pub const CAST_FLAMMABLE = Spell{
    .id = "sp_flammable",
    .name = "flammabilification",
    .animation = .{ .Particles = .{ .name = "glow-orange-red" } },
    .cast_type = .Smite,
    .effects = &[_]Effect{.{ .Status = .Flammable }},
    .checks_will = true,
};

pub const CAST_FREEZE = Spell{
    .id = "sp_freeze",
    .name = "freeze",
    .cast_type = .Smite,
    .effects = &[_]Effect{.{ .Status = .Paralysis }},
    .needs_cardinal_direction_target = true,
    .checks_will = true,
    .animation = .{ .Particles = .{ .name = "zap-statues" } },
};
pub const CAST_FAMOUS = Spell{
    .id = "sp_famous",
    .name = "famous",
    .cast_type = .Smite,
    .effects = &[_]Effect{.{ .Status = .Corona }},
    .needs_cardinal_direction_target = true,
    .checks_will = true,
    .animation = .{ .Particles = .{ .name = "zap-statues" } },
};
pub const CAST_FERMENT = Spell{
    .id = "sp_ferment",
    .name = "confusion",
    .cast_type = .Smite,
    .effects = &[_]Effect{.{ .Status = .Disorient }},
    .needs_cardinal_direction_target = true,
    .checks_will = true,
    .animation = .{ .Particles = .{ .name = "zap-statues" } },
};

pub const CAST_FEAR = Spell{
    .id = "sp_fear",
    .name = "fear",
    .animation = .{ .Particles = .{ .name = "glow-pink" } },
    .cast_type = .Smite,
    .effects = &[_]Effect{.{ .Status = .Fear }},
    .checks_will = true,
};
pub const CAST_PAIN = Spell{
    .id = "sp_pain",
    .name = "pain",
    .animation = .{ .Particles = .{ .name = "glow-pink" } },
    .cast_type = .Smite,
    .effects = &[_]Effect{.{ .Status = .Pain }},
    .checks_will = true,
};

pub fn willSucceedAgainstMobStats(cw: isize, tw: isize) bool {
    if (tw == mobs.WILL_IMMUNE or cw < tw)
        return false;
    return (rng.rangeClumping(isize, 1, 100, 2) * cw) >
        (rng.rangeClumping(isize, 1, 150, 2) * tw);
}

pub fn willSucceedAgainstMob(caster: *const Mob, target: *const Mob) bool {
    const tw = target.stat(.Willpower);
    const cw = switch (caster.stat(.Willpower)) {
        mobs.WILL_IMMUNE => 10,
        else => |w| w,
    };
    return willSucceedAgainstMobStats(cw, tw);
}

// Will range is 1...10, for convenience we make the table 11 so that we don't
// have to do TABLE[will-1][other_will-1]
//
pub var AVG_WILL_CHANCES: [11][11]usize = undefined;

pub fn initAvgWillChances() void {
    var atk: usize = 1;
    while (atk < AVG_WILL_CHANCES.len) : (atk += 1) {
        var def: usize = 1;
        while (def < AVG_WILL_CHANCES[atk].len) : (def += 1) {
            var defeated: usize = 1;
            var i: usize = 10_000;
            while (i > 0) : (i -= 1) {
                const cw: isize = @intCast(atk);
                const tw: isize = @intCast(def);
                if (willSucceedAgainstMobStats(cw, tw)) {
                    defeated += 1;
                }
            }
            AVG_WILL_CHANCES[atk][def] = defeated / 100;
        }
    }
}

pub fn checkAvgWillChances(caster: *Mob, target: *Mob) usize {
    const tw = target.stat(.Willpower);
    const cw = switch (caster.stat(.Willpower)) {
        mobs.WILL_IMMUNE => 10,
        else => |w| w,
    };
    return AVG_WILL_CHANCES[@intCast(cw)][@intCast(tw)];
}

pub const SpellOptions = struct {
    spell: *const Spell = undefined,
    caster_name: ?[]const u8 = null,
    duration: usize = Status.MAX_DURATION,
    power: usize = 0,
    MP_cost: usize = 1,
    free: bool = false,

    no_message: bool = false,

    context_direction1: Direction = undefined,
};

pub const Effect = union(enum) {
    Status: Status,
    Heal,
    Damage: struct {
        kind: Damage.DamageKind = .Physical,
        amount: EffectNumber = .Power,
        msg: DamageMessage = .{},
        blood: bool = true,
    },
    FireBlast: struct {
        radius: EffectNumber,
        damage: EffectNumber,
    },
    Custom: *const fn (caster: Coord, opts: SpellOptions, coord: Coord) void,

    pub const EffectNumber = union(enum) {
        Fixed: usize,
        Power,
        PowerRangeHalf,

        pub fn get(self: EffectNumber, spellcfg: SpellOptions) usize {
            return switch (self) {
                .Power => spellcfg.power,
                .PowerRangeHalf => rng.rangeClumping(usize, spellcfg.power / 2, spellcfg.power, 2),
                .Fixed => |n| n,
            };
        }
    };

    pub fn execute(self: Effect, spellcfg: SpellOptions, caster: ?*Mob, caster_c: Coord, target_c: Coord) void {
        switch (self) {
            .Status => |s| if (state.dungeon.at(target_c).mob) |victim|
                victim.addStatus(s, spellcfg.power, .{ .Tmp = spellcfg.duration }),
            .Damage => |d| if (state.dungeon.at(target_c).mob) |victim| {
                victim.takeDamage(.{
                    .kind = d.kind,
                    .amount = d.amount.get(spellcfg),
                    .source = .RangedAttack,
                    .by_mob = caster,
                    .blood = d.blood,
                }, d.msg);
            },
            .Heal => if (state.dungeon.at(target_c).mob) |victim|
                victim.takeHealing(spellcfg.power),
            .FireBlast => |b| explosions.fireBurst(target_c, b.radius.get(spellcfg), .{
                .initial_damage = b.damage.get(spellcfg),
                .culprit = caster,
            }),
            .Custom => |c| c(caster_c, spellcfg, target_c),
        }
    }
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

        // Area-of-effect centering on caster.
        Blast: struct {
            aoe: usize,
            avoids_allies: bool = false,
            avoids_caster: bool = false,
            checks_will: bool = false,
        },
    },

    // Only used if cast_type == .Smite.
    smite_target_type: union(enum) {
        SpecificAlly: []const u8, // mob's ID
        Self,
        ConstructAlly,
        UndeadAlly,
        AngelAlly,
        Mob,
        SpecificMob: []const u8, // mob's ID
        Corpse,
    } = .Mob,

    // Only used if cast_type == .Bolt
    bolt_missable: bool = false,
    bolt_dodgeable: bool = false,
    bolt_multitarget: bool = true,
    bolt_avoids_allies: bool = false,
    bolt_aoe: usize = 1,

    animation: ?Animation = null,

    checks_will: bool = false,
    needs_visible_target: bool = true,
    needs_cardinal_direction_target: bool = false,

    check_has_effect: ?*const fn (*Mob, SpellOptions, Coord) bool = null,

    noise: sound.SoundIntensity = .Silent,

    effects: []const Effect,

    // Options effect callback for the very last coord the bolt passed through.
    //
    // Added for Blinkbolt.
    bolt_last_coord_effect: ?*const fn (caster: Coord, spell: SpellOptions, coord: Coord) void = null,

    pub const Animation = union(enum) {
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
        Particles: Particle,

        pub const Particle = struct {
            name: []const u8,
            coord_is_target: bool = false,
            target: union(enum) {
                Target,
                Power,
                Z: usize,
                Origin,
            } = .Target,
        };
    };

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

        if (!opts.no_message and state.player.cansee(caster_coord)) {
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
            if (!opts.free) {
                caster.?.declareAction(.Cast);
            }
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
                var actual_target = target;
                var missed = false;

                // If the bolt can miss and the caster's Missile% check fails,
                // change the destination by a random angle.
                if (self.bolt_missable and caster != null and
                    !rng.percent(combat.chanceOfMissileLanding(caster.?)))
                {
                    missed = true;
                    if (state.dungeon.at(target).mob) |victim|
                        state.messageAboutMob(caster.?, target, .CombatUnimportant, "missed {}.", .{victim}, "missed {}.", .{victim});
                    const dist = caster_coord.distanceEuclidean(target);
                    const diff_x = @as(f64, @floatFromInt(target.x)) - @as(f64, @floatFromInt(caster_coord.x));
                    const diff_y = @as(f64, @floatFromInt(target.y)) - @as(f64, @floatFromInt(caster_coord.y));
                    const prev_angle = math.atan2(diff_y, diff_x);
                    const angle_vary = @as(f64, @floatFromInt(rng.range(usize, 5, 15))) * math.pi / 180.0;
                    const new_angle = if (rng.boolean()) prev_angle + angle_vary else prev_angle - angle_vary;
                    // std.log.warn("prev_angle: {}, new_angle: {}, x_off: {}, y_off: {}", .{
                    //     prev_angle,                             new_angle,
                    //     math.round(math.cos(new_angle) * dist), math.round(math.sin(new_angle) * dist),
                    // });
                    const new_x = @as(isize, @intCast(caster_coord.x)) + @as(isize, @intFromFloat(math.round(math.cos(new_angle) * dist)));
                    const new_y = @as(isize, @intCast(caster_coord.y)) + @as(isize, @intFromFloat(math.round(math.sin(new_angle) * dist)));
                    actual_target = Coord.new2(target.z, @intCast(new_x), @intCast(new_y));
                }

                // Fling a bolt and let it hit whatever
                var last_processed_coord: Coord = undefined;
                var affected_tiles = StackBuffer(Coord, 128).init(null);
                const line = caster_coord.drawLine(actual_target, state.mapgeometry, 3);
                assert(line.len > 0);
                for (line.constSlice()) |c| {
                    if (!c.eq(caster_coord) and !state.is_walkable(c, .{ .right_now = true, .only_if_breaks_lof = true })) {
                        const hit_mob = state.dungeon.at(c).mob;

                        if (hit_mob) |victim| {
                            if (missed) {
                                continue;
                            } else if (self.bolt_dodgeable and rng.percent(combat.chanceOfAttackEvaded(victim, caster))) {
                                state.messageAboutMob(victim, caster_coord, .CombatUnimportant, "dodge the {s}.", .{self.name}, "dodges the {s}.", .{self.name});
                                continue;
                            }
                        }

                        affected_tiles.append(c) catch err.wat();

                        // Stop if we're not multi-targeting or if the blocking object
                        // isn't a mob.
                        if (!self.bolt_multitarget or hit_mob == null) {
                            break;
                        }
                    }
                    last_processed_coord = c;
                }

                // Now we apply AOE effects if applicable
                if (self.bolt_aoe > 1) {
                    var gen = utils.iterCircle(last_processed_coord, self.bolt_aoe);
                    while (gen.next()) |aoecoord| {
                        if (affected_tiles.linearSearch(aoecoord, Coord.eqNotInline) == null)
                            affected_tiles.append(aoecoord) catch err.wat();
                    }
                }

                if (self.animation) |anim_type| switch (anim_type) {
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
                    .Particles => |particle_anim| {
                        ui.Animation.apply(.{ .Particle = .{
                            .name = particle_anim.name,
                            .coord = if (particle_anim.coord_is_target) last_processed_coord else caster_coord,
                            .target = switch (particle_anim.target) {
                                .Target => .{ .C = last_processed_coord },
                                .Power => .{ .Z = opts.power },
                                .Z => |n| .{ .Z = n },
                                .Origin => .{ .C = caster_coord },
                            },
                        } });
                    },
                };

                if (self.bolt_last_coord_effect) |func|
                    (func)(caster_coord, opts, last_processed_coord);

                for (affected_tiles.constSlice()) |coord| {
                    //
                    // If there's a mob on the tile, see if it resisted the effect.
                    //
                    if (state.dungeon.at(coord).mob) |victim| {
                        if (self.bolt_avoids_allies and
                            (victim == caster.? or !victim.isHostileTo(caster.?)))
                        {
                            continue;
                        }

                        if (self.checks_will and !willSucceedAgainstMob(caster.?, victim)) {
                            const chance = 100 - checkAvgWillChances(caster.?, victim);
                            if (state.player.cansee(victim.coord) or state.player.cansee(caster_coord)) {
                                state.message(.SpellCast, "{c} resisted $g($c{}%$g chance)$.", .{ victim, chance });
                            }
                            continue;
                        }
                    }

                    for (self.effects) |effect| {
                        effect.execute(opts, caster, caster_coord, coord);
                    }
                }
            },
            .Blast => |blast_opts| {
                assert(target.eq(caster_coord));

                var affected_tiles = StackBuffer(Coord, 128).init(null);
                if (!blast_opts.avoids_caster)
                    affected_tiles.append(caster_coord) catch err.wat();

                // Now we apply AOE effects if applicable
                if (blast_opts.aoe > 1) {
                    var gen = utils.iterCircle(caster_coord, blast_opts.aoe);
                    while (gen.next()) |aoecoord|
                        if (affected_tiles.linearSearch(aoecoord, Coord.eqNotInline) == null and
                            (!aoecoord.eq(caster_coord) or !blast_opts.avoids_caster))
                        {
                            affected_tiles.append(aoecoord) catch err.wat();
                        };
                }

                var farthest_affected = caster_coord;
                for (affected_tiles.constSlice()) |affected|
                    if (affected.distance(caster_coord) > farthest_affected.distance(caster_coord)) {
                        farthest_affected = affected;
                    };

                if (self.animation) |anim_type| switch (anim_type) {
                    .Particles => |particle_anim| {
                        assert(!particle_anim.coord_is_target);
                        ui.Animation.apply(.{ .Particle = .{
                            .name = particle_anim.name,
                            .coord = caster_coord,
                            .target = switch (particle_anim.target) {
                                .Target => .{ .C = farthest_affected },
                                .Power => .{ .Z = opts.power },
                                .Z => |n| .{ .Z = n },
                                .Origin => .{ .C = caster_coord },
                            },
                        } });
                    },
                    else => err.wat(),
                };

                for (affected_tiles.constSlice()) |coord| {
                    //
                    // If there's a mob on the tile, see if it resisted the effect.
                    //
                    if (state.dungeon.at(coord).mob) |victim| {
                        if (blast_opts.avoids_allies and
                            (victim == caster.? or !victim.isHostileTo(caster.?)))
                        {
                            continue;
                        }

                        if (self.checks_will and !willSucceedAgainstMob(caster.?, victim)) {
                            const chance = 100 - checkAvgWillChances(caster.?, victim);
                            if (state.player.cansee(victim.coord) or state.player.cansee(caster_coord)) {
                                state.message(.SpellCast, "{c} resisted $g($c{}%$g chance)$.", .{ victim, chance });
                            }
                            continue;
                        }
                    }

                    for (self.effects) |effect| {
                        effect.execute(opts, caster, caster_coord, coord);
                    }
                }
            },
            .Smite => {
                if (self.animation) |anim_type| switch (anim_type) {
                    .Simple => |simple_anim| {
                        ui.Animation.apply(.{ .TraverseLine = .{
                            .start = caster_coord,
                            .end = target,
                            .char = simple_anim.char,
                            .fg = simple_anim.fg,
                        } });
                    },
                    .Type2 => |type2_anim| {
                        ui.Animation.apply(.{ .AnimatedLine = .{
                            .start = caster_coord,
                            .end = target,
                            .approach = type2_anim.approach,
                            .chars = type2_anim.chars,
                            .fg = type2_anim.fg,
                            .bg = type2_anim.bg,
                            .bg_mix = type2_anim.bg_mix,
                        } });
                    },
                    .Particles => |particle_anim| {
                        ui.Animation.apply(.{ .Particle = .{
                            .name = particle_anim.name,
                            .coord = if (particle_anim.coord_is_target) target else caster_coord,
                            .target = switch (particle_anim.target) {
                                .Target => .{ .C = target },
                                .Power => .{ .Z = opts.power },
                                .Z => |n| .{ .Z = n },
                                .Origin => .{ .C = caster_coord },
                            },
                        } });
                    },
                };

                switch (self.smite_target_type) {
                    .AnyTile => {
                        assert(!self.checks_will);

                        for (self.effects) |effect|
                            effect.execute(opts, caster, caster_coord, target);
                    },
                    .Self, .Mob, .AngelAlly, .SpecificMob, .SpecificAlly, .ConstructAlly, .UndeadAlly => {
                        if (state.dungeon.at(target).mob == null) {
                            err.bug("Mage used smite-targeted spell on empty target!", .{});
                        }

                        const target_mob = state.dungeon.at(target).mob.?;

                        // Do some basic validation base on what the target should be.
                        switch (self.smite_target_type) {
                            .SpecificAlly,
                            .SpecificMob,
                            => |wanted_id| if (!mem.eql(u8, target_mob.id, wanted_id)) {
                                err.bug("Mage cast {s} at wrong mob! (Wanted {s}; got {s})", .{
                                    self.id, wanted_id, got_id,
                                });
                            },
                            .AngelAlly => if (target_mob.faction != .Holy and target_mob.life_type != .Spectral)
                                err.bug("Mage cast {s} at wrong mob! (Wanted angelic ally; got {s})", .{
                                    self.id, target_mob.id,
                                }),
                            else => {},
                        }

                        // Will-checks
                        if (self.checks_will and !willSucceedAgainstMob(caster.?, target_mob)) {
                            const chance = 100 - checkAvgWillChances(caster.?, target_mob);
                            if (state.player.cansee(target_mob.coord) or state.player.cansee(caster_coord)) {
                                state.message(.SpellCast, "{c} resisted $g($c{}%$g chance)$.", .{ target_mob, chance });
                            }
                            return;
                        }

                        for (self.effects) |effect|
                            effect.execute(opts, caster, caster_coord, target);
                    },
                    .Corpse => {
                        if (state.dungeon.at(target).surface == null or
                            meta.activeTag(state.dungeon.at(target).surface.?) != .Corpse)
                        {
                            err.bug("Mage used smite-targeted spell on empty target!", .{});
                        }

                        for (self.effects) |effect| switch (effect) {
                            .Status => err.bug("Mage tried to induce a status on a corpse!!", .{}),
                            .Damage => err.bug("Mage tried to smack a corpse!!!", .{}),
                            .Heal => err.bug("Mage tried to heal a corpse!!!", .{}),
                            else => effect.execute(opts, caster, caster_coord, target),
                        };
                    },
                }
            },
        }
    }
};
