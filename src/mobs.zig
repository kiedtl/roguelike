const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const ai = @import("ai.zig");
const state = @import("state.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const buffer = @import("buffer.zig");
const dijkstra = @import("dijkstra.zig");
const rng = @import("rng.zig");
const spells = @import("spells.zig");
const err = @import("err.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const MinMax = types.MinMax;
const minmax = types.minmax;
const Coord = types.Coord;
const Rect = types.Rect;
const Item = types.Item;
const Ring = types.Ring;
const DamageStr = types.DamageStr;
const Weapon = types.Weapon;
const Resistance = types.Resistance;
const StatusDataInfo = types.StatusDataInfo;
const Armor = types.Armor;
const SurfaceItem = types.SurfaceItem;
const Squad = types.Squad;
const Mob = types.Mob;
const AI = types.AI;
const AIPhase = types.AIPhase;
const Species = types.Species;
const Status = types.Status;
const Direction = types.Direction;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const Evocable = items.Evocable;
const Cloak = items.Cloak;
const Projectile = items.Projectile;
const StackBuffer = buffer.StackBuffer;
const SpellOptions = spells.SpellOptions;
const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;

// -----------------------------------------------------------------------------

pub const spawns = @import("mobs/spawns.zig");
pub const templates_test = @import("mobs/templates_test.zig");

// -----------------------------------------------------------------------------

pub const PLAYER_VISION = 12;
pub const RESIST_IMMUNE = 1000;
pub const WILL_IMMUNE = 1000;

pub const HumanSpecies = Species{ .name = "human" };
pub const GoblinSpecies = Species{ .name = "goblin" };
pub const ImpSpecies = Species{ .name = "imp" };

pub const MobTemplate = struct {
    ignore_conflicting_tiles: bool = false,

    mob: Mob,
    weapon: ?*const Weapon = null,
    backup_weapon: ?*const Weapon = null,
    armor: ?Armor = null,
    cloak: ?*const Cloak = null,
    statuses: []const StatusDataInfo = &[_]StatusDataInfo{},
    projectile: ?*const Projectile = null,
    evocables: []const Evocable = &[_]Evocable{},
    squad: []const []const SquadMember = &[_][]const SquadMember{},

    pub const SquadMember = struct {
        // FIXME: when Zig's #131 issue is resolved, change this to a
        // *MobTemplate instead of the mob's ID
        mob: []const u8,
        weight: usize = 1, // percentage
        count: MinMax(usize),
    };

    pub fn mobAreaRect(self: MobTemplate, coord: Coord) Rect {
        const l = self.mob.multitile orelse 1;
        return Rect{ .start = coord, .width = l, .height = l };
    }
};

// Combat dummies for tutorial {{{
pub const CombatDummyNormal = MobTemplate{
    .mob = .{
        .id = "combat_dummy_normal",
        .species = &HumanSpecies, // Too lazy to create own species
        .tile = '0',
        .ai = AI{
            .profession_name = "combat dummy",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.combatDummyFight,
        },
        .deaf = true,
        .immobile = true,
        .life_type = .Construct,
        .max_HP = 1,
        .stats = .{ .Vision = 3 },
    },
};
pub const CombatDummyPrisoner = MobTemplate{
    .mob = .{
        .id = "combat_dummy_prisoner",
        .species = &GoblinSpecies,
        .tile = 'g',
        .ai = AI{
            .profession_name = "cave goblin",
            .profession_description = "wandering",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
        },
        .faction = .CaveGoblins,
        .max_HP = 12,
        .memory_duration = 8,
        .stats = .{ .Willpower = 4, .Evade = 15, .Vision = 6 },
        .prisoner_status = types.Prisoner{ .of = .Necromancer },
    },
    .weapon = &items.MaceWeapon,
    .armor = items.GambesonArmor,
};
// }}}

pub const WrithingHulkTemplate = MobTemplate{
    .mob = .{
        .id = "hulk_writhing",
        .species = &Species{
            .name = "writhing hulk",
            .default_attack = &Weapon{
                .name = "tentacle",
                .damage = 1,
                .strs = &[_]DamageStr{items._dmgstr(1, "strike", "strikes", "")},
            },
        },
        .tile = 'H',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.hulkWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },
        .base_night_vision = true,

        .corpse = .None,
        .max_HP = 7,
        .memory_duration = 10,
        .innate_resists = .{ .rElec = 25, .rFire = 25 },
        .stats = .{ .Willpower = 2, .Melee = 100, .Vision = 5 },
    },
};

pub const SwollenHulkTemplate = MobTemplate{
    .mob = .{
        .id = "hulk_swollen",
        .species = &Species{
            .name = "swollen hulk",
            .default_attack = &Weapon{
                .name = "tentacle",
                .damage = 2,
                .strs = &[_]DamageStr{items._dmgstr(1, "batter", "batters", "")},
            },
        },
        .tile = 'H',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.hulkWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },
        .multitile = 2,
        .base_night_vision = true,

        .corpse = .None,
        .slain_trigger = .{ .Disintegrate = &[_]*const MobTemplate{
            &WrithingHulkTemplate,
            &WrithingHulkTemplate,
            &WrithingHulkTemplate,
            &WrithingHulkTemplate,
        } },
        .max_HP = 28,
        .memory_duration = 10,
        .innate_resists = .{ .rElec = 25, .rFire = 25 },
        .stats = .{ .Willpower = 2, .Melee = 100, .Speed = 200, .Vision = 5 },
    },
};

pub const ThrashingHulkTemplate = MobTemplate{
    .mob = .{
        .id = "hulk_thrashing",
        .species = &Species{
            .name = "thrashing hulk",
            .default_attack = &Weapon{
                .name = "tentacle",
                .damage = 4,
                .strs = &[_]DamageStr{items._dmgstr(1, "thrash", "thrashes", "")},
            },
        },
        .tile = 'H',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.hulkWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },
        .multitile = 3,
        .base_night_vision = true,

        .corpse = .None,
        .slain_trigger = .{ .Disintegrate = &[_]*const MobTemplate{
            &SwollenHulkTemplate,
            &WrithingHulkTemplate,
            &WrithingHulkTemplate,
            &WrithingHulkTemplate,
            &WrithingHulkTemplate,
            &WrithingHulkTemplate,
        } },
        .max_HP = 63,
        .memory_duration = 10,
        .innate_resists = .{ .rElec = 25, .rFire = 25 },
        .stats = .{ .Willpower = 2, .Melee = 100, .Speed = 300, .Vision = 5 },
    },
};

pub const ExecutionerTemplate = MobTemplate{
    .mob = .{
        .id = "executioner",
        .species = &GoblinSpecies,
        .tile = 'x',
        .ai = AI{
            .profession_name = "executioner",
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 5,
        .memory_duration = 5,
        .stats = .{ .Willpower = 2 },
    },
    .weapon = &items.W_KNOUT_3,
};

pub const WatcherTemplate = MobTemplate{
    .mob = .{
        .id = "watcher",
        .species = &ImpSpecies,
        .tile = 'w',
        .ai = AI{
            .profession_name = "watcher",
            .profession_description = "guarding",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.watcherFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .FearsDarkness, .NoRaiseAllyMorale },
        },
        .max_HP = 4,
        .memory_duration = 10,
        .stats = .{ .Willpower = 2, .Evade = 30 },
    },
};

pub const GuardTemplate = MobTemplate{
    .mob = .{
        .id = "guard",
        .species = &GoblinSpecies,
        .tile = 'g',
        .ai = AI{
            .profession_name = "guard",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 5,
        .memory_duration = 7,

        .stats = .{ .Willpower = 1 },
    },
    .weapon = &items.W_BLUDG_1,
};

pub const ArmoredGuardTemplate = MobTemplate{
    .mob = .{
        .id = "armored_guard",
        .species = &GoblinSpecies,
        .tile = 'G',
        .ai = AI{
            .profession_name = "armored guard",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 7,
        .memory_duration = 7,

        .stats = .{ .Willpower = 2, .Melee = 70 },
        .innate_resists = .{ .Armor = 15 },
    },
    .weapon = &items.W_BLUDG_2,
};

pub fn createEnforcerTemplate(comptime minion: []const u8) MobTemplate {
    return MobTemplate{
        .mob = .{
            .id = "enforcer_" ++ minion,
            .species = &GoblinSpecies,
            .tile = 'E',
            .ai = AI{
                .profession_name = "enforcer",
                .profession_description = "guarding",
                .work_fn = ai.patrolWork,
                .fight_fn = ai.mageFight,
                .spellcaster_backup_action = .Melee,
                .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
            },

            .spells = &[_]SpellOptions{
                .{ .MP_cost = 15, .spell = &spells.BOLT_PULL_FOE },
            },
            .max_MP = 15,

            .max_HP = 7,
            .memory_duration = 7,

            .stats = .{ .Willpower = 2, .Melee = 70 },
            .innate_resists = .{ .Armor = 15, .rElec = 50 },
        },
        .weapon = &items.W_SPROD_1,

        .squad = &[_][]const MobTemplate.SquadMember{
            &[_]MobTemplate.SquadMember{
                .{ .mob = minion, .weight = 1, .count = minmax(usize, 1, 2) },
            },
        },
    };
}
pub const EnforcerGTemplate = createEnforcerTemplate("guard");
pub const EnforcerAGTemplate = createEnforcerTemplate("armored_guard");

pub const JavelineerTemplate = MobTemplate{
    .mob = .{
        .id = "javelineer",
        .species = &GoblinSpecies,
        .tile = 'j',
        .ai = AI{
            .profession_name = "javelineer",
            .profession_description = "guarding",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .flee_effect = .{
                .status = .Enraged,
                .duration = .{ .Tmp = 10 },
                .exhausting = true,
            },
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 4, .spell = &spells.BOLT_JAVELIN, .power = 1, .duration = 3 },
        },
        .max_MP = 10,

        .max_HP = 6,
        .memory_duration = 5,
        .stats = .{ .Willpower = 2, .Evade = 10, .Missile = 80, .Vision = 5 },
    },
    .weapon = &items.W_BLUDG_2,
    .armor = items.GambesonArmor,
};

pub const DefenderTemplate = MobTemplate{
    .mob = .{
        .id = "defender",
        .species = &HumanSpecies,
        .tile = 'd',
        .ai = AI{
            .profession_name = "defender",
            .profession_description = "guarding",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.rangedFight,
            .is_curious = false,
            .flee_effect = .{
                .status = .Enraged,
                .duration = .{ .Tmp = 10 },
                .exhausting = true,
            },
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 6,
        .memory_duration = 6,
        .stats = .{ .Willpower = 3, .Evade = 10, .Missile = 90 },
    },
    .weapon = &items.W_SWORD_1,
    .armor = items.HauberkArmor,
    .projectile = &items.NetProj,
};

pub const LeadTurtleTemplate = MobTemplate{
    .mob = .{
        .id = "lead_turtle",
        .species = &Species{
            .name = "lead turtle",
            .default_attack = &Weapon{ .name = "lead jaw", .damage = 3, .strs = &items.BITING_STRS },
        },
        .tile = 't',
        .life_type = .Construct,
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
            .flags = &[_]AI.Flag{ .DetectWithHeat, .DetectWithElec },
        },

        .max_HP = 15,
        .memory_duration = 10,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rElec = -100, .rFire = RESIST_IMMUNE, .Armor = 60, .rFume = 100 },
        .stats = .{ .Willpower = 1, .Melee = 100, .Speed = 250, .Vision = 5 },
    },

    .statuses = &[_]StatusDataInfo{.{ .status = .Sleeping, .duration = .Prm }},
};

pub const IronWaspTemplate = MobTemplate{
    .mob = .{
        .id = "iron_wasp",
        .species = &Species{
            .name = "iron wasp",
            .default_attack = &Weapon{
                .name = "stinger",
                .damage = 1,
                .effects = &[_]StatusDataInfo{
                    .{ .status = .Disorient, .duration = .{ .Tmp = 3 } },
                },
                .strs = &[_]DamageStr{
                    items._dmgstr(5, "jab", "jabs", ""),
                    items._dmgstr(100, "sting", "stings", ""),
                },
            },
        },
        .tile = 'y',
        .life_type = .Construct,
        .ai = AI{
            .profession_description = "resting",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
            .flags = &[_]AI.Flag{ .DetectWithHeat, .DetectWithElec },
        },
        .max_HP = 1,
        .memory_duration = 5,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rFire = 50, .rFume = 100 },
        .stats = .{ .Willpower = 1, .Evade = 50, .Melee = 50, .Speed = 50, .Vision = 3 },
    },

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "iron_wasp", .weight = 1, .count = minmax(usize, 1, 3) },
        },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm },
        .{ .status = .Noisy, .duration = .Prm },
    },
};

pub const CopperHornetTemplate = MobTemplate{
    .mob = .{
        .id = "copper_hornet",
        .species = &Species{
            .name = "copper hornet",
            .default_attack = &Weapon{
                .name = "copper tail",
                .damage = 1,
                .ego = .Copper,
                .damage_kind = .Electric,
                .strs = &[_]DamageStr{
                    items._dmgstr(5, "jab", "jabs", ""),
                    items._dmgstr(100, "sting", "stings", ""),
                },
            },
        },
        .tile = 'ÿ',
        .life_type = .Construct,
        .ai = AI{
            .profession_description = "resting",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
            .flags = &[_]AI.Flag{.DetectWithElec},
        },
        .max_HP = 3,
        .memory_duration = 5,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rElec = 25, .rFire = 50, .rFume = 100 },
        .stats = .{ .Willpower = 0, .Evade = 40, .Speed = 50, .Vision = 5 },
    },

    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm }, .{ .status = .Noisy, .duration = .Prm },
    },
};

pub const PatrolTemplate = MobTemplate{
    .mob = .{
        .id = "patrol",
        .species = &GoblinSpecies,
        .tile = 'g',
        .ai = AI{
            .profession_name = "patrol",
            .profession_description = "patrolling",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
            .flags = &[_]AI.Flag{ .FearsDarkness, .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 5,
        .memory_duration = 8,
        .stats = .{ .Willpower = 1 },
    },
    .weapon = &items.W_BLUDG_1,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "patrol", .weight = 4, .count = minmax(usize, 1, 1) },
            .{ .mob = "patrol", .weight = 1, .count = minmax(usize, 1, 2) },
        },
    },
};

pub const PlayerTemplate = MobTemplate{
    .mob = .{
        .id = "player",
        .species = &HumanSpecies,
        .tile = '@',
        .prisoner_status = .{ .of = .Necromancer },
        .ai = AI{
            .profession_name = "[this is a bug]",
            .profession_description = "[this is a bug]",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.meleeFight,
            .is_combative = false,
            .is_curious = false,
        },
        .faction = .Player,
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .max_HP = 12,
        .memory_duration = 10,

        .max_MP = 20,

        .stats = .{ .Willpower = 4, .Missile = 60, .Evade = 10, .Vision = PLAYER_VISION, .Potential = 50 },
    },
    .weapon = &items.DaggerWeapon,
    // .backup_weapon = &items.ShadowMaulWeapon,
    // .armor = items.FumingVestArmor,
    //.evocables = &[_]Evocable{items.EldritchLanternEvoc},
    //.cloak = &items.ThornsCloak,
};

pub const GoblinTemplate = MobTemplate{
    .mob = .{
        .id = "goblin",
        .species = &GoblinSpecies,
        .tile = 'i',
        .ai = AI{
            .profession_name = "prisoner",
            .profession_description = "wandering",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
            .flags = &[_]AI.Flag{.AvoidsEnemies},
        },
        .faction = .CaveGoblins,
        .max_HP = 6,
        .memory_duration = 8,
        .stats = .{ .Willpower = 4, .Evade = 15, .Vision = 8 },
    },
};

pub const ConvultTemplate = MobTemplate{
    .mob = .{
        .id = "convult",
        .species = &HumanSpecies,
        .tile = 'Ç',
        .ai = AI{
            .profession_name = "convult",
            .profession_description = "watching",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .KeepDistance,
            .flags = &[_]AI.Flag{.ScansForCorpses},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 3, .spell = &spells.CAST_ENRAGE_DUSTLING, .power = 9 },
        },
        .max_MP = 6,
        .max_drainable_MP = 8,

        .max_HP = 7,
        .memory_duration = 5,
        .stats = .{ .Willpower = 3, .Vision = 4 },
    },
    // Disabled for now, needs playtesting
    //.statuses = &[_]StatusDataInfo{.{ .status = .NightVision, .duration = .Prm }},
};

pub const VapourMageTemplate = MobTemplate{
    .mob = .{
        .id = "vapour_mage",
        .species = &HumanSpecies,
        .tile = 'Ð',
        .ai = AI{
            .profession_name = "vapour mage",
            .profession_description = "watching",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .KeepDistance,
            .flags = &[_]AI.Flag{.ScansForCorpses},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 8, .spell = &spells.BOLT_AIRBLAST, .power = 6 },
            .{ .MP_cost = 2, .spell = &spells.CAST_FIREPROOF_DUSTLING, .power = 10 },
        },
        .max_MP = 15,
        .max_drainable_MP = 10,
        .base_night_vision = true,

        .max_HP = 5,
        .memory_duration = 5,
        .stats = .{ .Willpower = 6, .Speed = 200, .Vision = 6 },
    },
    .armor = items.HauberkArmor,
    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "dustling", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
};

pub const DustlingTemplate = MobTemplate{
    .mob = .{
        .id = "dustling",
        .species = &Species{
            .name = "dustling",
            .default_attack = &Weapon{ .name = "fist", .damage = 1, .strs = &items.FIST_STRS },
        },
        .tile = 'ð',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
        },
        .max_HP = 1,
        .memory_duration = 4,
        .life_type = .Construct,
        .blood = .Dust,
        .blood_spray = gas.Dust.id,
        .corpse = .None,
        .base_night_vision = true,
        .innate_resists = .{ .rFire = -25, .rElec = -25, .rFume = 100 },
        .stats = .{ .Willpower = 4, .Melee = 50, .Vision = 3 },
    },
    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "dustling", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
};

const WAR_OLG_CLAW_WEAPON = Weapon{
    .name = "claw",
    .damage = 1,
    .strs = &items.CLAW_STRS,
};

pub const WarOlgTemplate = MobTemplate{
    .mob = .{
        .id = "war_olg",
        .species = &Species{
            .name = "war olg",
            .default_attack = &WAR_OLG_CLAW_WEAPON,
            .aux_attacks = &[_]*const Weapon{&WAR_OLG_CLAW_WEAPON},
        },
        .tile = 'o',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.guardWork,
            .fight_fn = ai.mageFight,
            .is_fearless = true, // don't just run away when you've got a regen spell, dumbass
            // (TODO: it should cast regen *while* running away, no?)
        },
        .max_HP = 7,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 5, .spell = &spells.CAST_REGEN, .power = 2 },
        },
        .max_MP = 3,

        .memory_duration = 5,
        .stats = .{ .Willpower = 2, .Melee = 50, .Vision = 5 },
    },
};

pub const MellaentTemplate = MobTemplate{
    .mob = .{
        .id = "mellaent",
        .species = &Species{ .name = "mellaent" },
        .tile = 'b',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
            .is_combative = false,
            .is_curious = false,
        },
        .max_HP = 3,
        .stats = .{ .Willpower = 1, .Evade = 40, .Speed = 120, .Vision = 8 },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Corona, .power = 50, .duration = .Prm },
    },
};

// Spires {{{
fn createSpireTemplate(
    comptime name: []const u8,
    tile: u32,
    spell: SpellOptions,
    opts: struct {
        willpower: usize = WILL_IMMUNE,
    },
) MobTemplate {
    assert(spell.MP_cost == 4);
    return MobTemplate{
        .mob = .{
            .id = name ++ "_spire",
            .species = &Species{ .name = name ++ " spire" },
            .tile = tile,
            .ai = AI{
                .profession_description = "watching",
                .work_fn = ai.spireWork,
                .fight_fn = ai.mageFight,
                .is_curious = false,
                .spellcaster_backup_action = .KeepDistance,
                .flags = &[_]AI.Flag{ .AwakesNearAllies, .SocialFighter, .DetectWithElec },
            },

            .base_night_vision = true,

            .spells = &[_]SpellOptions{spell},
            .max_MP = 4,

            .max_HP = 10,
            .memory_duration = 77,
            .life_type = .Construct,
            .blood = null,
            .corpse = .Wall,
            .immobile = true,
            .innate_resists = .{ .rFume = 100, .rFire = 25, .rElec = 25, .Armor = 20 },
            .stats = .{ .Willpower = opts.willpower, .Evade = 0, .Vision = 8 },
        },

        .statuses = &[_]StatusDataInfo{.{ .status = .Sleeping, .duration = .Prm }},
    };
}

pub const IronSpireTemplate = createSpireTemplate("iron", '1', .{ .MP_cost = 4, .spell = &spells.BOLT_IRON, .power = 2 }, .{});
pub const LightningSpireTemplate = createSpireTemplate("lightning", '2', .{ .MP_cost = 4, .spell = &spells.BOLT_LIGHTNING, .power = 2 }, .{});
pub const CalciteSpireTemplate = createSpireTemplate("calcite", '3', .{ .MP_cost = 4, .spell = &spells.CAST_CALL_UNDEAD }, .{ .willpower = 8 });
pub const SentrySpireTemplate = createSpireTemplate("sentry", '4', .{ .MP_cost = 4, .spell = &spells.CAST_ALERT_ALLY }, .{});
// }}}

pub const KyaniteStatueTemplate = MobTemplate{
    .ignore_conflicting_tiles = true, // conflicts w/ other statues

    .mob = .{
        .id = "kyanite_statue",
        .species = &Species{ .name = "kyanite statue", .default_attack = &items.NONE_WEAPON },
        .tile = '☻',
        .ai = AI{
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .IgnoredByEnemies, .SocialFighter2, .NoRaiseAllyMorale },
            .spellcaster_backup_action = .KeepDistance,
        },
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 7, .spell = &spells.CAST_FREEZE, .duration = 5 },
        },
        .max_MP = 7,

        .max_HP = 100,
        .memory_duration = 1,
        .life_type = .Construct,
        .blood = null,
        .corpse = .Wall,
        .immobile = true,
        .innate_resists = .{ .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .Armor = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 9, .Vision = 20 },
    },
};

pub const NebroStatueTemplate = MobTemplate{
    .ignore_conflicting_tiles = true, // conflicts w/ other statues

    .mob = .{
        .id = "nebro_statue",
        .species = &Species{ .name = "nebro statue", .default_attack = &items.NONE_WEAPON },
        .tile = '☻',
        .ai = AI{
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .IgnoredByEnemies, .SocialFighter2, .NoRaiseAllyMorale },
            .spellcaster_backup_action = .KeepDistance,
        },
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 7, .spell = &spells.CAST_FAMOUS, .duration = 8, .power = 50 },
        },
        .max_MP = 7,

        .max_HP = 100,
        .memory_duration = 1,
        .life_type = .Construct,
        .blood = null,
        .corpse = .Wall,
        .immobile = true,
        .innate_resists = .{ .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .Armor = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 9, .Vision = 20 },
    },
};

pub const CrystalStatueTemplate = MobTemplate{
    .ignore_conflicting_tiles = true, // conflicts w/ other statues

    .mob = .{
        .id = "crystal_statue",
        .species = &Species{ .name = "crystal statue", .default_attack = &items.NONE_WEAPON },
        .tile = '☻',
        .ai = AI{
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .IgnoredByEnemies, .SocialFighter2, .NoRaiseAllyMorale },
            .spellcaster_backup_action = .KeepDistance,
        },
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 7, .spell = &spells.CAST_FERMENT, .duration = 14, .power = 0 },
        },
        .max_MP = 7,

        .max_HP = 100,
        .memory_duration = 1,
        .life_type = .Construct,
        .blood = null,
        .corpse = .Wall,
        .immobile = true,
        .innate_resists = .{ .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .Armor = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 9, .Vision = 20 },
    },
};

pub const AlchemistTemplate = MobTemplate{
    .mob = .{
        .id = "alchemist",
        .species = &HumanSpecies,
        .tile = 'a',
        .ai = AI{
            .profession_name = "alchemist",
            .profession_description = "experimenting",
            .work_fn = ai.guardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .Flee,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 50, .spell = &spells.CAST_AWAKEN_CONSTRUCT },
        },
        .max_MP = 51,

        .max_HP = 7,
        .memory_duration = 6,

        .stats = .{ .Willpower = 2, .Evade = 10, .Vision = 6 },
    },
};

pub const CoronerTemplate = MobTemplate{
    .mob = .{
        .id = "coroner",
        .species = &GoblinSpecies,
        .tile = 'ö',
        .ai = AI{
            .profession_name = "coroner",
            .profession_description = "doing autopsy",
            .work_fn = ai.workerWork,
            .fight_fn = ai.workerFight, //ai.coronerFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 8,
        .memory_duration = 6,

        .stats = .{ .Willpower = 1 },
    },
};

pub const CleanerTemplate = MobTemplate{
    .mob = .{
        .id = "cleaner",
        .species = &GoblinSpecies,
        .tile = 'ë',
        .ai = AI{
            .profession_name = "cleaner",
            .profession_description = "cleaning",
            .work_fn = ai.workerWork,
            .fight_fn = ai.workerFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 10,
        .memory_duration = 6,
        .stats = .{ .Willpower = 2, .Evade = 10 },
    },
};

pub const EngineerTemplate = MobTemplate{
    .mob = .{
        .id = "engineer",
        .species = &GoblinSpecies,
        .tile = 'ë',
        .ai = AI{
            .profession_name = "engineer",
            .profession_description = "building",
            .work_fn = ai.workerWork,
            .fight_fn = ai.workerFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 10,
        .memory_duration = 6,
        .stats = .{ .Willpower = 2, .Evade = 10 },
    },
};

pub const HaulerTemplate = MobTemplate{
    .mob = .{
        .id = "hauler",
        .species = &GoblinSpecies,
        .tile = 'ü',
        .ai = AI{
            .profession_name = "hauler",
            .profession_description = "hauling",
            .work_fn = ai.haulerWork,
            .fight_fn = ai.workerFight,
            .is_curious = false,
            .work_phase = .HaulerScan,
            .flags = &[_]AI.Flag{ .ScansForJobs, .ScansForCorpses },
        },

        .max_HP = 10,
        .memory_duration = 6,
        // extra speed doesn't really make sense, but is necessary to prevent it
        // from being behind on order
        .stats = .{ .Willpower = 2, .Evade = 10, .Speed = 50 },
    },
};

pub const AncientMageTemplate = MobTemplate{
    .mob = .{
        .id = "ancient_mage",
        .species = &HumanSpecies,
        .tile = 'Ã',
        .ai = AI{
            .profession_name = "ancient mage",
            .profession_description = "watching",
            .work_fn = ai.guardWork,
            .fight_fn = ai.mageFight,
            .is_fearless = true,
            .spellcaster_backup_action = .KeepDistance,
        },

        .spells = &[_]SpellOptions{
            // On spell ordering: our priorities are:
            //    - Disperse nearby enemies.
            //    - Cast crystal spears at anything we can see.
            //    - If we still have MP, or we couldn't cast spears at anyone,
            //      summon nonvisible enemies. This is after BOLT_CRYSTAL to
            //      ensure that the mob doesn't waste time summoning enemies
            //      while a hundred goblins are trying to tear it apart.
            .{ .MP_cost = 0, .spell = &spells.CAST_AURA_DISPERSAL },
            .{ .MP_cost = 7, .spell = &spells.BOLT_CRYSTAL, .power = 3 },
            .{ .MP_cost = 0, .spell = &spells.CAST_MASS_DISMISSAL, .power = 15 },
            .{ .MP_cost = 9, .spell = &spells.CAST_SUMMON_ENEMY },
        },
        .max_MP = 30,
        .max_drainable_MP = 50,
        .base_night_vision = true,

        .deaf = false,
        .life_type = .Undead,

        .max_HP = 20,
        .memory_duration = 8,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rFume = 100, .rElec = 75 },
        .stats = .{ .Willpower = 10, .Evade = 20, .Speed = 150 },
    },
    .weapon = &items.W_MACES_3,
    .armor = items.HauberkArmor,
    .cloak = &items.SilCloak,
};

pub const RecruitTemplate = MobTemplate{
    .mob = .{
        .id = "recruit",
        .species = &GoblinSpecies,
        .tile = 'c',
        .ai = AI{
            .profession_name = "recruit",
            .profession_description = "resting",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .flee_effect = .{ .status = .Enraged, .duration = .{ .Tmp = 10 }, .exhausting = true },
            .flags = &[_]AI.Flag{.ScansForCorpses},
        },

        .max_HP = 5,
        .memory_duration = 6,
        .stats = .{ .Willpower = 1, .Melee = 80, .Evade = 5, .Vision = 6 },
    },
    .weapon = &items.W_BLUDG_1,
    .armor = items.GambesonArmor,
};

pub const WarriorTemplate = MobTemplate{
    .mob = .{
        .id = "warrior",
        .species = &GoblinSpecies,
        .tile = 'W',
        .ai = AI{
            .profession_name = "warrior",
            .profession_description = "resting",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .flee_effect = .{ .status = .Enraged, .duration = .{ .Tmp = 10 }, .exhausting = true },
            .flags = &[_]AI.Flag{.ScansForCorpses},
        },

        .max_HP = 8,
        .memory_duration = 6,
        .stats = .{ .Willpower = 2, .Melee = 90, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.W_MACES_2,
    .armor = items.CuirassArmor,
};

pub const HunterTemplate = MobTemplate{
    .mob = .{
        .id = "hunter",
        .species = &GoblinSpecies,
        .tile = 'H',
        .ai = AI{
            .profession_name = "hunter",
            .profession_description = "resting",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.meleeFight,
            .flee_effect = .{ .status = .Enraged, .duration = .{ .Tmp = 20 }, .exhausting = true },
            .flags = &[_]AI.Flag{.ScansForCorpses},
        },

        .max_HP = 8,
        .memory_duration = 20,
        .stats = .{ .Willpower = 3, .Melee = 70, .Speed = 150, .Vision = 8 },
    },
    .weapon = &items.W_MACES_2,
    .armor = items.GambesonArmor,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "stalker", .weight = 4, .count = minmax(usize, 3, 6) },
        },
    },
};

pub const BoneMageTemplate = MobTemplate{
    .mob = .{
        .id = "bone_mage",
        .species = &HumanSpecies,
        .tile = 'm',
        .ai = AI{
            .profession_name = "bone mage",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .Melee,
            .flags = &[_]AI.Flag{ .CalledWithUndead, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 25, .spell = &spells.CAST_ENRAGE_BONE_RAT, .duration = 5 },
        },
        .max_MP = 20,
        .max_drainable_MP = 12,

        .max_HP = 4,
        .memory_duration = 6,
        .stats = .{ .Willpower = 4, .Vision = 6, .Melee = 40 },
    },
    .weapon = &items.W_BLUDG_1,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "bone_rat", .weight = 4, .count = minmax(usize, 1, 2) },
        },
    },
};

pub const DeathKnightTemplate = MobTemplate{
    .mob = .{
        .id = "death_knight",
        .species = &HumanSpecies,
        .tile = 'k',
        .ai = AI{
            .profession_name = "death knight",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .flee_effect = .{ .status = .Enraged, .duration = .{ .Tmp = 10 }, .exhausting = true },
            .flags = &[_]AI.Flag{ .CalledWithUndead, .ScansForCorpses },
        },

        .max_HP = 8,
        .memory_duration = 8,
        .innate_resists = .{ .Armor = 25 },
        .stats = .{ .Willpower = 6, .Melee = 65, .Martial = 1, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.W_MSWRD_1,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "skeleton", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
};

pub const DeathMageTemplate = MobTemplate{
    .mob = .{
        .id = "death_mage",
        .species = &HumanSpecies,
        .tile = 'M',
        .ai = AI{
            .profession_name = "death mage",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .KeepDistance,
            .flags = &[_]AI.Flag{ .CalledWithUndead, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 10, .spell = &spells.CAST_HEAL_UNDEAD },
            .{ .MP_cost = 20, .spell = &spells.CAST_ENRAGE_UNDEAD, .duration = 10 },
        },
        .max_MP = 20,
        .max_drainable_MP = 18,

        .max_HP = 6,
        .memory_duration = 10,
        .stats = .{ .Willpower = 8, .Evade = 10 },
    },
    .weapon = &items.W_SWORD_2,
    .armor = items.HauberkArmor,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "skeletal_blademaster", .weight = 6, .count = minmax(usize, 2, 4) },
        },
    },
};

pub const EmberMageTemplate = MobTemplate{
    .mob = .{
        .id = "ember_mage",
        .species = &HumanSpecies,
        .tile = 'È',
        .ai = AI{
            .profession_name = "ember mage",
            .profession_description = "watching",
            // Stand still and don't be curious; don't want emberling followers
            // to burn the world down
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .Melee,
            .flags = &[_]AI.Flag{ .DetectWithHeat, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 5, .spell = &spells.CAST_CREATE_EMBERLING },
            .{ .MP_cost = 10, .spell = &spells.CAST_FLAMMABLE, .power = 10 },
        },
        .max_MP = 15,
        .max_drainable_MP = 12,

        .max_HP = 5,
        .memory_duration = 6,
        .stats = .{ .Willpower = 4, .Vision = 6 },
    },
    .weapon = &items.W_BLUDG_1,
    .cloak = &items.SilCloak,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "emberling", .weight = 9, .count = minmax(usize, 1, 2) },
            .{ .mob = "emberling", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
};

pub const BrimstoneMageTemplate = MobTemplate{
    .mob = .{
        .id = "brimstone_mage",
        .species = &HumanSpecies,
        .tile = 'R',
        .ai = AI{
            .profession_name = "brimstone mage",
            .profession_description = "watching",
            // Stand still and don't be curious; don't want emberling followers
            // to burn the world down
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .KeepDistance,
            .flags = &[_]AI.Flag{ .DetectWithHeat, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 15, .spell = &spells.CAST_CREATE_EMBERLING },
            .{ .MP_cost = 1, .spell = &spells.CAST_FLAMMABLE, .power = 20 },
            .{ .MP_cost = 7, .spell = &spells.BOLT_FIREBALL, .power = 2, .duration = 3 },
        },
        .max_MP = 15,
        .max_drainable_MP = 18,

        .max_HP = 7,
        .memory_duration = 8,
        .stats = .{ .Willpower = 6, .Evade = 10 },
    },
    .weapon = &items.W_MACES_2,
    .armor = items.HauberkArmor,
    .cloak = &items.SilCloak,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "emberling", .weight = 1, .count = minmax(usize, 2, 4) },
        },
    },
};

pub const SparkMageTemplate = MobTemplate{
    .mob = .{
        .id = "spark_mage",
        .species = &GoblinSpecies,
        .tile = 'P',
        .ai = AI{
            .profession_name = "spark mage",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .Melee,
            .flags = &[_]AI.Flag{ .DetectWithElec, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 20, .spell = &spells.CAST_CREATE_SPARKLING },
            .{ .MP_cost = 15, .spell = &spells.BOLT_PARALYSE, .power = 2 },
        },
        .max_MP = 10,
        .max_drainable_MP = 12,

        .max_HP = 5,
        .memory_duration = 6,
        .stats = .{ .Willpower = 4, .Vision = 6 },
    },
    .weapon = &items.W_BLUDG_1,
    .cloak = &items.FurCloak,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "sparkling", .weight = 1, .count = minmax(usize, 1, 1) },
        },
    },
};

pub const LightningMageTemplate = MobTemplate{
    .mob = .{
        .id = "lightning_mage",
        .species = &GoblinSpecies,
        .tile = 'L',
        .ai = AI{
            .profession_name = "lightning mage",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .KeepDistance,
            .flags = &[_]AI.Flag{ .DetectWithElec, .ScansForCorpses },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 12, .spell = &spells.CAST_CREATE_SPARKLING },
            .{ .MP_cost = 8, .spell = &spells.BOLT_PARALYSE, .power = 3 },
            .{ .MP_cost = 6, .spell = &spells.CAST_DISCHARGE },
        },
        .max_MP = 15,
        .max_drainable_MP = 18,

        .max_HP = 7,
        .memory_duration = 8,
        .stats = .{ .Willpower = 6, .Evade = 10 },
    },
    .weapon = &items.W_MACES_2,
    .armor = items.HauberkArmor,
    .cloak = &items.FurCloak,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "sparkling", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
};

pub const BloatTemplate = MobTemplate{
    .mob = .{
        .id = "bloat",
        .species = &Species{
            .name = "bloat",
            .default_attack = &Weapon{ .name = "fist", .damage = 1, .strs = &items.FIST_STRS },
        },
        .tile = 'n',
        .ai = AI{
            .profession_description = "dormant",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .max_HP = 21,
        .memory_duration = 8,
        .max_drainable_MP = 8,

        //.deaf = true,
        .life_type = .Undead,
        .blood = null,
        .blood_spray = gas.Miasma.id,
        .corpse = .None,
        .base_night_vision = true,

        .innate_resists = .{ .rFume = 100 },
        .stats = .{ .Willpower = 4, .Melee = 80, .Speed = 150 },
    },

    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm },
    },
};

// pub const ThrashingSculptorTemplate = MobTemplate{
//     .mob = .{
//         .id = "thrashing_sculptor",
//         .species = &Species{
//             .name = "thrashing sculptor",
//             .default_attack = &Weapon{ .damage = 0, .knockback = 2, .strs = &items.CLAW_STRS },
//         },
//         .tile = 'T',
//         .ai = AI{
//             .profession_description = "dormant",
//             .work_fn = ai.watcherWork,
//             .fight_fn = ai.mageFight,
//             .is_fearless = true,
//             .spellcaster_backup_action = .Melee,
//             .flags = &[_]AI.Flag{.MovesDiagonally},
//         },

//         .spells = &[_]SpellOptions{
//             .{ .MP_cost = 10, .spell = &spells.CAST_CREATE_BLOAT },
//         },
//         .max_MP = 10,

//         .max_HP = 12,
//         .memory_duration = 20,
//         .base_night_vision = true,

//         .life_type = .Undead,
//         .corpse = .None,

//         .innate_resists = .{ .rFume = 100 },
//         .stats = .{ .Willpower = 5, .Evade = 20, .Melee = 100, .Vision = 6 },
//     },
// };

pub const SkeletonTemplate = MobTemplate{
    .mob = .{
        .id = "skeleton",
        .species = &Species{
            .name = "skeleton",
            .default_attack = &Weapon{ .name = "fist", .damage = 1, .strs = &items.FIST_STRS },
        },
        .tile = 'l',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
            .flags = &[_]AI.Flag{.CalledWithUndead},
        },

        .max_HP = 4,
        .memory_duration = 6,
        .max_drainable_MP = 8,

        .deaf = true,
        .life_type = .Undead,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rFire = -25 },
        .stats = .{ .Willpower = 3, .Vision = 5 },
    },
};

pub const StalkerTemplate = MobTemplate{
    .mob = .{
        .id = "stalker",
        .species = &Species{
            .name = "stalker",
            .default_attack = &Weapon{
                .name = "bonk",
                .damage = 0,
                .strs = &[_]DamageStr{items._dmgstr(0, "ram", "rams", "")},
            },
        },
        .tile = 's',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.stalkerFight,
            .is_curious = false,
            .is_fearless = true,
            .flags = &[_]AI.Flag{ .DetectWithElec, .AvoidsEnemies },
            .spellcaster_backup_action = .KeepDistance,
        },
        .life_type = .Construct,
        .deg360_vision = true,
        .base_night_vision = true,

        // XXX: synchronize MP costs w/ mob speed so that it gets one shot every 3 turns
        .spells = &[_]SpellOptions{
            .{ .MP_cost = 15, .spell = &spells.BOLT_LIGHTNING, .power = 1 },
        },
        .max_MP = 5,

        .blood = null,
        .corpse = .None,

        .max_HP = 2,
        .memory_duration = 2, // Forget about enemies quickly in absence of hunter captain
        .innate_resists = .{ .rFume = 100, .rElec = RESIST_IMMUNE },
        .stats = .{ .Willpower = 0, .Evade = 50, .Speed = 20, .Vision = 4 },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm },
    },
};

pub const BoneRatTemplate = MobTemplate{
    .mob = .{
        .id = "bone_rat",
        .species = &Species{
            .name = "bone rat",
            .default_attack = &Weapon{ .name = "teeth", .damage = 1, .strs = &items.BITING_STRS },
        },
        .tile = 'r',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .deaf = true,
        .life_type = .Undead,
        .max_drainable_MP = 5,

        .max_HP = 2,
        .memory_duration = 4,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rFire = -25 },
        .stats = .{ .Willpower = 0, .Evade = 5, .Speed = 50, .Vision = 4 },
    },

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "bone_rat", .count = minmax(usize, 0, 1) },
        },
    },
};

pub const EmberlingTemplate = MobTemplate{
    .mob = .{
        .id = "emberling",
        .species = &Species{
            .name = "emberling",
            .default_attack = &Weapon{ .name = "red-hot claw", .damage = 1, .damage_kind = .Fire, .strs = &items.CLAW_STRS, .delay = 120 },
        },
        .tile = 'è',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_curious = false,
            .is_fearless = true,
            .flags = &[_]AI.Flag{.DetectWithHeat},
        },
        .life_type = .Construct,

        .blood = null,
        .corpse = .None,

        .max_HP = 2,
        .memory_duration = 4,
        .innate_resists = .{ .rFume = 100, .rFire = RESIST_IMMUNE },
        .stats = .{ .Willpower = 1, .Evade = 5, .Vision = 5, .Melee = 50 },
    },
    // XXX: Emberlings are never placed alone, this determines number of
    // summoned emberlings from CAST_CREATE_EMBERLING
    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            // disabled
            .{ .mob = "emberling", .weight = 1, .count = minmax(usize, 0, 0) },
        },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm },
        .{ .status = .Fire, .duration = .Prm },
        .{ .status = .Noisy, .duration = .Prm },
    },
};

pub const SparklingTemplate = MobTemplate{
    .mob = .{
        .id = "sparkling",
        .species = &Species{
            .name = "sparkling",
            .default_attack = &Weapon{ .name = "shock prod", .damage = 1, .damage_kind = .Electric, .strs = &items.SHOCK_STRS, .delay = 120 },
        },
        .tile = 'p',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .is_fearless = true,
            .spellcaster_backup_action = .Melee,
            .flags = &[_]AI.Flag{.DetectWithElec},
        },
        .life_type = .Construct,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 3, .spell = &spells.BOLT_BLINKBOLT, .power = 1 },
        },
        .max_MP = 6,

        .blood = null,
        .corpse = .None,

        .max_HP = 2,
        .memory_duration = 4,
        .innate_resists = .{ .rFume = 100, .rElec = RESIST_IMMUNE },
        .stats = .{ .Willpower = 1, .Evade = 5, .Vision = 5 },
    },
    // XXX: Sparklings are never placed alone, this determines number of
    // summoned sparklings from CAST_CREATE_SPARKLING
    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            // disabled
            .{ .mob = "sparkling", .weight = 1, .count = minmax(usize, 0, 0) },
        },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm },
    },
};

pub const SkeletalBlademasterTemplate = MobTemplate{
    .mob = .{
        .id = "skeletal_blademaster",
        .species = &HumanSpecies,
        .tile = 'ƀ',
        .ai = AI{
            .profession_name = "skeletal blademaster",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .deaf = true,
        .life_type = .Undead,
        .max_drainable_MP = 10,

        .max_HP = 9,
        .memory_duration = 6,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rFire = -25, .Armor = 35 },
        .stats = .{ .Willpower = 4, .Melee = 90, .Martial = 2, .Vision = 6 },
    },
    .weapon = &items.W_MSWRD_1,
};

pub const TorturerNecromancerTemplate = MobTemplate{
    .mob = .{
        .id = "necromancer",
        .species = &HumanSpecies,
        .tile = 'Ñ',
        .ai = AI{
            .profession_name = "necromancer",
            .profession_description = "tormenting",
            .work_fn = ai.tortureWork,
            .fight_fn = ai.mageFight,
            .is_fearless = true,
            .spellcaster_backup_action = .KeepDistance,
            .flags = &[_]AI.Flag{.ScansForCorpses},
        },
        .no_show_fov = false,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 5, .spell = &spells.CAST_RESURRECT_NORMAL },
            .{ .MP_cost = 2, .spell = &spells.CAST_PAIN, .duration = 5, .power = 2 },
            .{ .MP_cost = 1, .spell = &spells.CAST_FEAR, .duration = 10 },
        },
        .max_MP = 10,
        .max_drainable_MP = 14,

        .max_HP = 8,
        .memory_duration = 8,
        .stats = .{ .Willpower = 8, .Evade = 10 },
    },
    .weapon = &items.W_BLUDG_1,
    .armor = items.GambesonArmor,
};

// pub const FrozenFiendTemplate = MobTemplate{
//     .mob = .{
//         .id = "frozen_fiend",
//         .species = &Species{ .name = "frozen fiend" },
//         .tile = 'F',
//         .ai = AI{
//             .profession_description = "patrolling",
//             .work_fn = ai.patrolWork,
//             .fight_fn = ai.mageFight,
//             .is_fearless = true,
//             .spellcaster_backup_action = .Melee,
//         },

//         .spells = &[_]SpellOptions{
//             .{ .MP_cost = 2, .spell = &spells.CAST_POLAR_LAYER, .power = 14 },
//             .{ .MP_cost = 3, .spell = &spells.CAST_RESURRECT_FROZEN, .power = 21 },
//         },
//         .max_MP = 15,

//         .max_HP = 15,
//         .memory_duration = 10,
//         .blood = null,
//         .corpse = .None,

//         .innate_resists = .{ .rElec = 75, .rFire = -25 },
//         .stats = .{ .Willpower = 8, .Evade = 10 },
//     },
//     .weapon = &items.MorningstarWeapon,
//     .armor = items.HauberkArmor,
// };

pub const LivingIceTemplate = MobTemplate{
    .mob = .{
        .id = "living_ice",
        .species = &Species{
            .name = "living ice",
            .default_attack = &Weapon{
                .name = "icy blast",
                .damage = 1,
                .strs = &[_]DamageStr{
                    items._dmgstr(10, "hit", "hits", ""),
                },
            },
        },
        .tile = 'I',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.meleeFight,
            .is_curious = false,
            .is_fearless = true,
            .flags = &[_]AI.Flag{.NoRaiseAllyMorale},
        },

        .deg360_vision = true,
        .no_show_fov = true,
        .immobile = true,
        .max_HP = 12,
        .memory_duration = 1,

        .life_type = .Construct,

        .blood = .Water,
        .corpse = .Wall,

        .innate_resists = .{ .rFire = -50, .rElec = RESIST_IMMUNE, .Armor = 50, .rFume = 100 },
        .stats = .{ .Willpower = 5, .Melee = 100, .Vision = 2 },
    },
    // This status should be added by whatever spell created it.
    //.statuses = &[_]StatusDataInfo{.{ .status = .Lifespan, .duration = .{.Tmp=10} }},
};

pub const BallLightningTemplate = MobTemplate{
    .mob = .{
        .id = "ball_lightning",
        .species = &Species{ .name = "ball lightning" },
        .tile = '*',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.ballLightningWorkOrFight,
            .fight_fn = ai.ballLightningWorkOrFight,
            .is_curious = false,
            .is_fearless = true,
            .flags = &[_]AI.Flag{.DetectWithElec},
        },

        .deaf = true,
        .deg360_vision = true,
        .no_show_fov = true,
        .immobile = false,
        .max_HP = 1,
        .memory_duration = 1,

        .life_type = .Construct,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFire = 50, .rElec = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = WILL_IMMUNE, .Speed = 20, .Vision = 20 },
    },
    // This status should be added by whatever spell created it.
    .statuses = &[_]StatusDataInfo{
        .{ .status = .ExplosiveElec, .power = 5, .duration = .Prm },
    },
};

pub const SpectralSwordTemplate = MobTemplate{
    .mob = .{
        .id = "spec_sword",
        .species = &Species{ .name = "spectral sword" },
        .tile = '|',
        .ai = AI{
            .profession_description = "[this is a bug]",
            .work_fn = ai.suicideWork,
            .fight_fn = ai.combatDummyFight,
            .flags = &[_]AI.Flag{.IgnoredByEnemies},
            .is_curious = false,
            .is_fearless = true,
        },

        .deaf = true,
        .deg360_vision = true,
        .no_show_fov = true,
        .base_night_vision = true,
        .max_HP = 1,
        .memory_duration = 999999,

        .life_type = .Spectral,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .Armor = RESIST_IMMUNE, .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .rFume = 100, .rAcid = RESIST_IMMUNE },
        .stats = .{ .Willpower = WILL_IMMUNE, .Vision = 20 },
    },
};

pub const SpectralSabreTemplate = MobTemplate{
    .mob = .{
        .id = "spec_sabre",
        .species = &Species{
            .name = "spectral sabre",
            .default_attack = &Weapon{
                .name = "blade",
                .damage = 1,
                .strs = &[_]DamageStr{items._dmgstr(1, "nick", "nicks", "")},
            },
        },
        .tile = ')',
        .ai = AI{
            .profession_description = "hovering",
            .work_fn = ai.suicideWork,
            .fight_fn = ai.meleeFight,
            .is_curious = false,
            .is_fearless = true,
            .flags = &[_]AI.Flag{ .IgnoresEnemiesUnknownToLeader, .ForceNormalWork },
        },

        .deaf = true,
        .deg360_vision = true,
        .no_show_fov = true,
        .base_night_vision = true,
        .max_HP = 1,
        .memory_duration = 1,

        .life_type = .Spectral,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rAcid = RESIST_IMMUNE },
        .stats = .{ .Willpower = WILL_IMMUNE, .Melee = 50, .Speed = 50, .Vision = 20 },
    },
};

pub const SpectralTotemTemplate = MobTemplate{
    .mob = .{
        .id = "spec_totem",
        .species = &Species{ .name = "spectral totem" },
        .tile = 'Д',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .KeepDistance,
            .is_curious = false,
            .is_fearless = true,
            .work_phase = .NC_Guard,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 7, .spell = &spells.BOLT_CONJURE },
        },
        .max_MP = 7,

        .deaf = true,
        .deg360_vision = true,
        .base_night_vision = true,

        .immobile = true,
        .faction = .Night,
        .max_HP = 15,
        .memory_duration = 999999,

        .life_type = .Spectral,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .Armor = 75, .rElec = RESIST_IMMUNE, .rFire = -50, .rAcid = RESIST_IMMUNE },
        .stats = .{ .Willpower = 10, .Conjuration = 2, .Vision = 7 },
    },
};

pub const NightReaperTemplate = MobTemplate{
    .mob = .{
        .id = "night_reaper",
        .species = &Species{ .name = "night reaper" },
        .tile = 'Я',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.nightCreatureWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .is_fearless = true,
            .spellcaster_backup_action = .Melee,
            .work_phase = .NC_Guard,
            .flags = &[_]AI.Flag{ .AvoidsEnemies, .FearsLight },
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 8, .spell = &spells.BOLT_AOE_INSANITY, .duration = 10 },
        },
        .max_MP = 16,

        .base_night_vision = true,

        .faction = .Night,
        .max_HP = 10,
        .memory_duration = 10,

        .life_type = .Spectral,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rElec = 25, .rAcid = RESIST_IMMUNE }, // -25% rFire from shadow mail
        .stats = .{ .Willpower = 10, .Melee = 80, .Evade = 15, .Vision = 8 },
    },
    .weapon = &items.ShadowMaulWeapon,
    .armor = items.ShadowMailArmor,
};

pub const GrueTemplate = MobTemplate{
    .mob = .{
        .id = "grue",
        .species = &Species{ .name = "grue" },
        .tile = 'Ю',
        .ai = AI{
            .profession_description = "TODO: remove profession descriptions",
            .work_fn = ai.nightCreatureWork,
            .fight_fn = ai.grueFight,
            .is_curious = false,
            .is_fearless = true,
            .work_phase = .NC_Guard,
            .flags = &[_]AI.Flag{ .AvoidsEnemies, .FearsLight },
        },

        .base_night_vision = true,
        .deg360_vision = true,

        .faction = .Night,
        .max_HP = 20,
        .memory_duration = 99999,

        .life_type = .Spectral,
        .blood = null,
        .blood_spray = gas.Darkness.id,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rFire = -25, .rElec = 25, .rAcid = RESIST_IMMUNE },
        .stats = .{ .Willpower = 10, .Spikes = 2, .Vision = 7 },
    },
};

const SLINKING_TERROR_CLAW_WEAPON = Weapon{
    .name = "ethereal claw",
    .damage = 1,
    .ego = .NC_Insane,
    .martial = true,
    .strs = &items.CLAW_STRS,
};

pub const SlinkingTerrorTemplate = MobTemplate{
    .mob = .{
        .id = "slinking_terror",
        .species = &Species{
            .name = "slinking terror",
            .default_attack = &SLINKING_TERROR_CLAW_WEAPON,
            .aux_attacks = &[_]*const Weapon{
                &SLINKING_TERROR_CLAW_WEAPON,
                &SLINKING_TERROR_CLAW_WEAPON,
            },
        },
        .tile = 'Ж',
        .ai = AI{
            .profession_description = "TODO: remove profession descriptions",
            .work_fn = ai.nightCreatureWork,
            .fight_fn = ai.meleeFight,
            .is_curious = false,
            .is_fearless = true,
            .work_phase = .NC_Guard,
            .flags = &[_]AI.Flag{ .AvoidsEnemies, .FearsLight, .WallLover },
        },

        .base_night_vision = true,
        .deg360_vision = true,

        .faction = .Night,
        .max_HP = 8,
        .memory_duration = 99999,

        .life_type = .Spectral,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rFire = -25, .rElec = 25, .rAcid = RESIST_IMMUNE },
        .stats = .{ .Willpower = 10, .Melee = 80, .Martial = 1, .Vision = 7 },
    },
};

const CREEPING_DEATH_CLAW_WEAPON = Weapon{
    .name = "ethereal claw",
    .damage = 1,
    .ego = .NC_Insane,
    .strs = &items.CLAW_STRS,
};

pub const CreepingDeathTemplate = MobTemplate{
    .mob = .{
        .id = "creeping_death",
        .species = &Species{
            .name = "creeping_death",
            .default_attack = &Weapon{
                .damage = 1,
                .ego = .NC_Insane,
                .strs = &items.BITING_STRS,
            },
            .aux_attacks = &[_]*const Weapon{
                &CREEPING_DEATH_CLAW_WEAPON,
                &CREEPING_DEATH_CLAW_WEAPON,
            },
        },
        .tile = 'Э',
        .ai = AI{
            .profession_description = "TODO: remove profession descriptions",
            .work_fn = ai.nightCreatureWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .is_fearless = true,
            .work_phase = .NC_Guard,
            .spellcaster_backup_action = .Melee,
            .flags = &[_]AI.Flag{ .AvoidsEnemies, .FearsLight },
        },

        .base_night_vision = true,
        .deg360_vision = true,

        .faction = .Night,
        .max_HP = 7,
        .memory_duration = 99999,

        .life_type = .Spectral,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFume = 100, .rFire = -25, .rElec = 25, .rAcid = RESIST_IMMUNE },
        .stats = .{ .Willpower = 8, .Melee = 90, .Vision = PLAYER_VISION + 2 },
    },
};

pub const CinderBruteTemplate = MobTemplate{
    .mob = .{
        .id = "cinder_brute",
        .species = &Species{
            .name = "cinder brute",
            .default_attack = &Weapon{
                .name = "teeth",
                .damage = 1,
                .strs = &items.BITING_STRS,
            },
        },
        .tile = '¢',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .flags = &[_]AI.Flag{.DetectWithHeat},
        },
        .max_HP = 6,

        .spells = &[_]SpellOptions{
            // Have cooldown period that matches time needed for flames to
            // die out, so that the brute isn't constantly vomiting fire when
            // its surroundings are already in flames
            //
            // TODO: check this in spells.zig
            .{ .MP_cost = 10, .spell = &spells.CAST_FIREBLAST, .power = 4 },
        },
        .max_MP = 10,

        .memory_duration = 10,
        .blood = .Ash,
        .blood_spray = gas.SmokeGas.id,
        .corpse = .None,
        .faction = .Revgenunkim,
        .innate_resists = .{ .rFire = RESIST_IMMUNE, .rElec = -25, .rFume = 100 },
        .stats = .{ .Willpower = 6, .Melee = 80, .Vision = 4 },
    },
    .statuses = &[_]StatusDataInfo{.{ .status = .Fire, .duration = .Prm }},
};

const BURNING_BRUTE_CLAW_WEAPON = Weapon{
    .name = "burning claw",
    .damage = 1,
    .strs = &items.CLAW_STRS,
};

pub const BurningBruteTemplate = MobTemplate{
    .mob = .{
        .id = "burning_brute",
        .species = &Species{
            .name = "burning brute",
            .default_attack = &BURNING_BRUTE_CLAW_WEAPON,
            .aux_attacks = &[_]*const Weapon{
                &BURNING_BRUTE_CLAW_WEAPON,
                &Weapon{ .name = "kick", .knockback = 3, .damage = 1, .strs = &items.KICK_STRS },
            },
        },
        .tile = 'B',
        .ai = AI{
            .profession_description = "sulking",
            // *must* be stand_still_and_guard, otherwise it'll spread fire
            // everywhere.
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            //.is_fearless = true, // Flee effect won't trigger otherwise.
            .flee_effect = .{ .status = .Enraged, .duration = .{ .Tmp = 10 }, .exhausting = true },
            .spellcaster_backup_action = .Melee,
            .flags = &[_]AI.Flag{.DetectWithHeat},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 2, .spell = &spells.CAST_RESURRECT_FIRE, .power = 200, .duration = 10 },
            .{ .MP_cost = 3, .spell = &spells.BOLT_FIREBALL, .power = 2, .duration = 8 },
        },
        .max_MP = 12,

        .faction = .Revgenunkim,
        .multitile = 2,
        .max_HP = 15,
        .memory_duration = 10,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rFire = RESIST_IMMUNE, .rElec = -25 },
        .stats = .{ .Willpower = 8, .Evade = 10, .Melee = 80 },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Fire, .duration = .Prm },
        .{ .status = .Noisy, .duration = .Prm },
    },
};

pub const MOBS = [_]MobTemplate{
    CombatDummyNormal,
    CombatDummyPrisoner,
    WrithingHulkTemplate,
    SwollenHulkTemplate,
    ThrashingHulkTemplate,
    // CoronerTemplate,
    ExecutionerTemplate,
    WatcherTemplate,
    GuardTemplate,
    ArmoredGuardTemplate,
    EnforcerGTemplate,
    EnforcerAGTemplate,
    JavelineerTemplate,
    DefenderTemplate,
    LeadTurtleTemplate,
    IronWaspTemplate,
    CopperHornetTemplate,
    PatrolTemplate,
    PlayerTemplate,
    GoblinTemplate,
    ConvultTemplate,
    VapourMageTemplate,
    DustlingTemplate,
    WarOlgTemplate,
    MellaentTemplate,
    IronSpireTemplate,
    LightningSpireTemplate,
    CalciteSpireTemplate,
    SentrySpireTemplate,
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
    AlchemistTemplate,
    CleanerTemplate,
    HaulerTemplate,
    AncientMageTemplate,
    //SpectreMageTemplate,
    RecruitTemplate,
    WarriorTemplate,
    HunterTemplate,
    BoneMageTemplate,
    DeathKnightTemplate,
    DeathMageTemplate,
    EmberMageTemplate,
    BrimstoneMageTemplate,
    SparkMageTemplate,
    LightningMageTemplate,
    BloatTemplate,
    // ThrashingSculptorTemplate,
    SkeletonTemplate,
    StalkerTemplate,
    BoneRatTemplate,
    EmberlingTemplate,
    SparklingTemplate,
    SkeletalBlademasterTemplate,
    TorturerNecromancerTemplate,
    // FrozenFiendTemplate,
    BallLightningTemplate,
    SpectralSwordTemplate,
    SpectralSabreTemplate,
    SpectralTotemTemplate,
    NightReaperTemplate,
    GrueTemplate,
    SlinkingTerrorTemplate,
    CreepingDeathTemplate,
    CinderBruteTemplate,
    BurningBruteTemplate,
} ++ templates_test.MOBS;

pub const PRISONERS = [_]MobTemplate{
    GoblinTemplate,
};

pub const STATUES = [_]MobTemplate{
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
};

pub fn findMobById(raw_id: anytype) ?*const MobTemplate {
    const id = utils.used(raw_id);
    return for (&MOBS) |*mobt| {
        if (mem.eql(u8, mobt.mob.id, id))
            break mobt;
    } else null;
}

pub const PlaceMobOptions = struct {
    facing: ?Direction = null,
    phase: AIPhase = .Work,
    work_area: ?Coord = null,
    no_squads: bool = false,
    faction: ?types.Faction = null,
    prisoner_of: ?types.Faction = null,
    prm_status1: ?Status = null,
    prm_status2: ?Status = null,
    job: ?types.AIJob.Type = null,
    tag: ?u8 = null,
};

pub fn placeMob(
    alloc: mem.Allocator,
    template: *const MobTemplate,
    coord: Coord,
    opts: PlaceMobOptions,
) *Mob {
    {
        var gen = Generator(Rect.rectIter).init(template.mobAreaRect(coord));
        while (gen.next()) |mobcoord| {
            if (state.dungeon.at(mobcoord).mob) |other|
                err.bug("Attempting to place {s} in tile occupied by {f}", .{ template.mob.id, other });
        }
    }

    var mob = template.mob;
    mob.init(alloc);

    mob.coord = coord;
    mob.faction = opts.faction orelse mob.faction;
    mob.ai.phase = opts.phase;
    mob.tag = opts.tag;

    if (opts.job) |j| {
        mob.newJob(j);
    }

    if (opts.prisoner_of) |f|
        mob.prisoner_status = types.Prisoner{ .of = f };
    if (opts.prm_status1) |s|
        mob.addStatus(s, 0, .Prm);
    if (opts.prm_status2) |s|
        mob.addStatus(s, 0, .Prm);

    if (template.weapon) |w| mob.equipItem(.Weapon, Item{ .Weapon = w });
    if (template.backup_weapon) |w| mob.equipItem(.Backup, Item{ .Weapon = w });
    if (template.armor) |a| mob.equipItem(.Armor, Item{ .Armor = items.createItem(Armor, a) });
    if (template.cloak) |c| mob.equipItem(.Cloak, Item{ .Cloak = c });

    if (opts.facing) |dir| mob.facing = dir;
    mob.ai.work_area.append(opts.work_area orelse coord) catch err.wat();

    for (template.evocables) |evocable_template| {
        var evocable = items.createItem(Evocable, evocable_template);
        evocable.charges = evocable.max_charges;
        mob.inventory.pack.append(Item{ .Evocable = evocable }) catch err.wat();
    }

    if (template.projectile) |proj| {
        while (!mob.inventory.pack.isFull()) {
            mob.inventory.pack.append(Item{ .Projectile = proj }) catch err.wat();
        }
    }

    for (template.statuses) |status_info| {
        mob.addStatus(status_info.status, status_info.power, status_info.duration);
    }

    state.mobs.append(mob) catch err.wat();
    const mob_ptr = state.mobs.last().?;

    // ---
    // --------------- `mob` mustn't be modified after this point! --------------
    // ---

    if (!opts.no_squads and template.squad.len > 0) {
        // TODO: allow placing squads next to multitile creatures.
        //
        // AFAIK the only thing that needs to be changed is skipping over all of
        // the squad leader's tiles instead of just the main one when choosing
        // tiles to place squadlings on.
        //
        assert(mob.multitile == null);

        const squad_template = rng.chooseUnweighted([]const MobTemplate.SquadMember, template.squad);

        var squad_member_weights = StackBuffer(usize, 20).init(null);
        for (squad_template) |s| squad_member_weights.append(s.weight) catch err.wat();

        const squad_mob_info = rng.choose(
            MobTemplate.SquadMember,
            squad_template,
            squad_member_weights.constSlice(),
        ) catch err.wat();
        const squad_mob = findMobById(squad_mob_info.mob) orelse err.bug("Mob {s} specified in template couldn't be found.", .{squad_mob_info.mob});

        const squad_mob_count = rng.range(usize, squad_mob_info.count.min, squad_mob_info.count.max);

        var i: usize = squad_mob_count;

        const squad = Squad.allocNew();

        while (i > 0) : (i -= 1) {
            var dijk = dijkstra.Dijkstra.init(coord, state.mapgeometry, 3, state.is_walkable, .{ .right_now = true }, alloc);
            defer dijk.deinit();

            const s_coord = while (dijk.next()) |child| {
                // This *should* hold true but for some reason it doesn't. Too
                // lazy to investigate.
                //assert(state.dungeon.at(child).mob == null);
                if (child.eq(coord)) continue; // Don't place in leader's coord
                if (state.dungeon.at(child).mob == null)
                    break child;
            } else null;

            if (s_coord) |c| {
                const underling = placeMob(alloc, squad_mob, c, .{ .no_squads = true });
                underling.squad = squad;
                squad.members.append(underling) catch err.wat();
            }
        }

        squad.leader = mob_ptr;
        mob_ptr.squad = squad;
    }

    {
        var gen = Generator(Rect.rectIter).init(mob_ptr.areaRect());
        while (gen.next()) |mobcoord|
            state.dungeon.at(mobcoord).mob = mob_ptr;
    }

    return mob_ptr;
}

pub fn placeMobNearStairs(template: *const MobTemplate, level: usize, opts: PlaceMobOptions) !*Mob {
    var coords = StackBuffer(Coord, types.Dungeon.MAX_STAIRS + 1).init(null);
    for (state.dungeon.stairs[level].constSlice()) |stair|
        if (state.nextSpotForMob(stair, null)) |coord|
            coords.append(coord) catch err.wat();
    if (state.nextSpotForMob(state.dungeon.entries[level], null)) |coord|
        coords.append(coord) catch err.wat();

    const coord = coords.chooseUnweighted() orelse return error.NoSpace;
    return placeMob(state.gpa.allocator(), template, coord, opts);
}

pub fn placeMobSurrounding(c: Coord, t: *const MobTemplate, opts: PlaceMobOptions) void {
    for (&DIRECTIONS) |d| if (c.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, .{ .right_now = true })) {
            const m = placeMob(state.gpa.allocator(), t, neighbor, opts);
            m.cancelStatus(.Sleeping);
        }
    };
}

//comptime {
//    @setEvalBranchQuota(MOBS.len * MOBS.len * 10);

//    inline for (&MOBS) |monster| {
//        // Ensure no monsters have conflicting tiles
//        const pu: ?[]const u8 = inline for (&MOBS) |othermonster| {
//            if (!mem.eql(u8, monster.mob.id, othermonster.mob.id) and
//                monster.mob.tile == othermonster.mob.tile and
//                !monster.ignore_conflicting_tiles and
//                !othermonster.ignore_conflicting_tiles)
//            {
//                break othermonster.mob.id;
//            }
//        } else null;
//        if (pu) |prevuse| {
//            @compileError("Monster " ++ prevuse ++ " tile conflicts w/ " ++ monster.mob.id);
//        }

//        // Ensure that no resist is equal to 100
//        //
//        // (Because that usually means that I intended to make them immune to
//        // that damage type, but forgot that terrain and spells can affect that
//        // resist and occasionally make them less-than-immune.)
//        if (monster.mob.innate_resists.rFire == 100 or
//            monster.mob.innate_resists.rElec == 100 or
//            monster.mob.innate_resists.Armor == 100)
//        {
//            @compileError("Monster " ++ monster.mob.id ++ " has false immunity in one or more resistances");
//        }
//    }
//}
