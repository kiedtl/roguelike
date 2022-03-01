const std = @import("std");
const mem = std.mem;

const ai = @import("ai.zig");
const state = @import("state.zig");
const items = @import("items.zig");
const buffer = @import("buffer.zig");
const spells = @import("spells.zig");
const err = @import("err.zig");
usingnamespace @import("types.zig");

const Evocable = items.Evocable;
const Cloak = items.Cloak;
const Projectile = items.Projectile;
const StackBuffer = buffer.StackBuffer;
const SpellOptions = spells.SpellOptions;

pub const HumanSpecies = Species{ .name = "human" };
pub const GoblinSpecies = Species{ .name = "goblin" };
pub const ImpSpecies = Species{ .name = "imp" };
pub const BurningBruteSpecies = Species{
    .name = "burning brute",
    .default_attack = &items.ClawWeapon,
    .aux_attacks = &[_]*const Weapon{
        &items.ClawWeapon,
        &items.KickWeapon,
    },
};

pub const MobTemplate = struct {
    id: []const u8,
    mob: Mob,
    weapon: ?*const Weapon = null,
    backup_weapon: ?*const Weapon = null,
    armor: ?*const Armor = null,
    cloak: ?*const Cloak = null,
    statuses: []const StatusDataInfo = &[_]StatusDataInfo{},
    projectile: ?*const Projectile = null,
    evocables: []const Evocable = &[_]Evocable{},
};

pub const ExecutionerTemplate = MobTemplate{
    .id = "executioner",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'א',
        .ai = AI{
            .profession_name = "executioner",
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,

        .willpower = 3,
        .base_dexterity = 18,
        .hearing = 7,
        .max_HP = 40,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 20,
    },
    .weapon = &items.KnoutWeapon,
};

pub const WatcherTemplate = MobTemplate{
    .id = "watcher",
    .mob = .{
        .species = &ImpSpecies,
        .tile = 'ש',
        .ai = AI{
            .profession_name = "watcher",
            .profession_description = "guarding",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.watcherFight,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Necromancer,

        .willpower = 3,
        .base_dexterity = 30,
        .hearing = 5,
        .max_HP = 40,
        .memory_duration = 10,
        .base_speed = 60,
        .blood = .Blood,

        .base_strength = 8, // weakling!
    },
};

pub const WardenTemplate = MobTemplate{
    .id = "warden",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'ם',
        .ai = AI{
            .profession_name = "warden",
            .profession_description = "guarding",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 5,

        .willpower = 3,
        .base_dexterity = 15,
        .hearing = 7,
        .max_HP = 30,
        .memory_duration = 6,
        .base_speed = 120,
        .blood = .Blood,

        .base_strength = 20,
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.ChainmailArmor,
    .evocables = &[_]Evocable{items.WarningHornEvoc},
};

pub const GuardTemplate = MobTemplate{
    .id = "guard",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'ט',
        .ai = AI{
            .profession_name = "guard",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,

        .willpower = 2,
        .base_dexterity = 20,
        .hearing = 7,
        .max_HP = 35,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 10,
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.GambesonArmor,
};

pub const JavelineerTemplate = MobTemplate{
    .id = "javelineer",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'פ',
        .ai = AI{
            .profession_name = "javelineer",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.rangedFight,
            .is_combative = true,
            .is_curious = true,
            .flee_effect = .{
                .status = .Enraged,
                .duration = 10,
                .exhausting = true,
            },
        },
        .allegiance = .Necromancer,

        .willpower = 2,
        .base_dexterity = 15,
        .hearing = 7,
        .max_HP = 30,
        .memory_duration = 6,
        .base_speed = 110,
        .blood = .Blood,

        .base_strength = 15,
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.GambesonArmor,
    .projectile = &items.JavelinProj,
};

pub const SentinelTemplate = MobTemplate{
    .id = "sentinel",
    .mob = .{
        .species = &HumanSpecies,
        .tile = 'ל',
        .ai = AI{
            .profession_name = "sentinel",
            .profession_description = "guarding",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.rangedFight,
            .is_combative = true,
            .is_curious = false,
            .flee_effect = .{
                .status = .Enraged,
                .duration = 10,
                .exhausting = true,
            },
        },
        .allegiance = .Necromancer,

        .willpower = 5,
        .base_dexterity = 25,
        .hearing = 6,
        .max_HP = 40,
        .memory_duration = 7,
        .base_speed = 90,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.KnifeWeapon,
    .armor = &items.LeatherArmor,
    .projectile = &items.NetProj,
};

pub const PatrolTemplate = MobTemplate{
    .id = "patrol",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'ק',
        .ai = AI{
            .profession_name = "patrol",
            .profession_description = "patrolling",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,

        .willpower = 2,
        .base_dexterity = 20,
        .hearing = 7,
        .max_HP = 30,
        .memory_duration = 3,
        .base_speed = 110,
        .blood = .Blood,

        .base_strength = 20,
    },
    .weapon = &items.SpearWeapon,
    .armor = &items.GambesonArmor,
};

pub const PlayerTemplate = MobTemplate{
    .id = "player",
    .mob = .{
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
        .allegiance = .OtherGood,
        .vision = 10,
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .willpower = 6,
        .base_dexterity = 25,
        .hearing = 5,
        .max_HP = 80,
        .memory_duration = 10,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 20,
    },
    .weapon = &items.KnifeWeapon,
    .armor = &items.RobeArmor,
    //.evocables = &[_]Evocable{items.IronSpikeEvoc},
    //.cloak = &items.ThornsCloak,
};

pub const InteractionLaborerTemplate = MobTemplate{
    .id = "interaction_laborer",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'w',
        .ai = AI{
            .profession_name = "slave",
            .profession_description = "laboring",
            .work_fn = ai.interactionLaborerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .Necromancer,

        .willpower = 2,
        .base_dexterity = 15,
        .hearing = 10,
        .max_HP = 60,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 10,
    },
};

pub const GoblinTemplate = MobTemplate{
    .id = "goblin",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'g',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .OtherEvil,
        .vision = 8,

        .willpower = 3,
        .base_dexterity = 20,
        .hearing = 5,
        .max_HP = 40,
        .memory_duration = 8,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.LeatherArmor,
};

pub const KyaniteStatueTemplate = MobTemplate{
    .id = "kyanite_statue",
    .mob = .{
        .species = &Species{ .name = "kyanite statue" },
        .tile = '☺',
        .ai = AI{
            .profession_name = null,
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Necromancer,
        .vision = 20,
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 7, .spell = &spells.CAST_FREEZE, .duration = 2 },
        },
        .max_MP = 7,

        .willpower = 8,
        .base_dexterity = 0,
        .hearing = 0,
        .max_HP = 100,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .corpse = .Wall,
        .immobile = true,
        .innate_resists = .{ .rPois = 3, .rFire = 3, .rElec = 3, .rMlee = 3, .rFume = 3 },

        .base_strength = 1,
    },
};

pub const NebroStatueTemplate = MobTemplate{
    .id = "nebro_statue",
    .mob = .{
        .species = &Species{ .name = "nebro statue" },
        .tile = '☻',
        .ai = AI{
            .profession_name = null,
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Necromancer,
        .vision = 20,
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 7, .spell = &spells.CAST_FAMOUS, .duration = 5, .power = 30 },
        },
        .max_MP = 7,

        .willpower = 8,
        .base_dexterity = 0,
        .hearing = 0,
        .max_HP = 1000,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .corpse = .Wall,
        .immobile = true,
        .innate_resists = .{ .rPois = 3, .rFire = 3, .rElec = 3, .rMlee = 3, .rFume = 3 },

        .base_strength = 2,
    },
};

pub const CrystalStatueTemplate = MobTemplate{
    .id = "crystal_statue",
    .mob = .{
        .species = &Species{ .name = "crystal statue" },
        .tile = '☻',
        .ai = AI{
            .profession_name = null,
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Necromancer,
        .vision = 20,
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 7, .spell = &spells.CAST_FERMENT, .duration = 10, .power = 0 },
        },
        .max_MP = 7,

        .willpower = 8,
        .base_dexterity = 0,
        .hearing = 0,
        .max_HP = 1000,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .corpse = .Wall,
        .immobile = true,
        .innate_resists = .{ .rPois = 3, .rFire = 3, .rElec = 3, .rMlee = 3, .rFume = 3 },

        .base_strength = 2,
    },
};

pub const AlchemistTemplate = MobTemplate{
    .id = "alchemist",
    .mob = .{
        .species = &HumanSpecies,
        .tile = 'w',
        .ai = AI{
            .profession_name = "alchemist",
            .profession_description = "experimenting",
            .work_fn = ai.guardWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .Necromancer,

        .willpower = 5,
        .base_dexterity = 30,
        .hearing = 6,
        .max_HP = 65,
        .memory_duration = 7,
        .base_speed = 90,
        .blood = .Blood,

        .base_strength = 28,
    },
};

pub const CleanerTemplate = MobTemplate{
    .id = "cleaner",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'w',
        .ai = AI{
            .profession_name = "cleaner",
            .profession_description = "cleaning",
            .work_fn = ai.cleanerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
            .work_phase = .CleanerScan,
        },
        .allegiance = .Necromancer,

        .willpower = 2,
        .base_dexterity = 15,
        .hearing = 10,
        .max_HP = 60,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 10,
    },
};

pub const HaulerTemplate = MobTemplate{
    .id = "hauler",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'w',
        .ai = AI{
            .profession_name = "hauler",
            .profession_description = "hauling",
            .work_fn = ai.haulerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
            .work_phase = .HaulerScan,
        },
        .allegiance = .Necromancer,

        .willpower = 2,
        .base_dexterity = 25,
        .hearing = 8,
        .max_HP = 50,
        .memory_duration = 8,
        .base_speed = 55,
        .blood = .Blood,

        .base_strength = 10,
    },
};

pub const EngineerTemplate = MobTemplate{
    .id = "engineer",
    .mob = .{
        .species = &GoblinSpecies,
        .tile = 'w',
        .ai = AI{
            .profession_name = "engineer",
            .profession_description = "repairing",
            .work_fn = ai.engineerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
            .work_phase = .EngineerScan,
        },
        .allegiance = .Necromancer,

        .willpower = 2,
        .base_dexterity = 25,
        .hearing = 8,
        .max_HP = 50,
        .memory_duration = 8,
        .base_speed = 55,
        .blood = .Blood,

        .base_strength = 10,
    },
    .cloak = &items.FurCloak,
};

pub const TorturerNecromancerTemplate = MobTemplate{
    .id = "torturer_necromancer",
    .mob = .{
        .species = &HumanSpecies,
        .tile = 'Ñ',
        .ai = AI{
            .profession_name = "necromancer",
            .profession_description = "tormenting",
            .work_fn = ai.tortureWork,
            .fight_fn = ai.mageFight,
            .is_combative = true,
            .is_curious = true,
            .is_fearless = true,
            .spellcaster_backup_action = .KeepDistance,
        },
        .allegiance = .Necromancer,
        .vision = 5,
        .no_show_fov = false,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 3, .spell = &spells.CAST_RESURRECT_NORMAL },
            .{ .MP_cost = 1, .spell = &spells.CAST_FEAR, .duration = 9 },
            .{ .MP_cost = 1, .spell = &spells.CAST_PAIN, .duration = 5, .power = 5 },
        },
        .max_MP = 10,

        .willpower = 10,
        .base_dexterity = 15,
        .hearing = 6,
        .max_HP = 50,
        .memory_duration = 10,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 25,
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.ChainmailArmor,
};

pub const BurningBruteTemplate = MobTemplate{
    .id = "burning_brute",
    .mob = .{
        .species = &BurningBruteSpecies,
        .tile = 'B',
        .ai = AI{
            .profession_name = null,
            .profession_description = "sulking",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.mageFight,
            .is_combative = true,
            .is_curious = true,
            //.is_fearless = true, // Flee effect won't trigger otherwise.
            .flee_effect = .{ .status = .Enraged, .duration = 10, .exhausting = true },
            .spellcaster_backup_action = .Melee,
        },
        .allegiance = .Necromancer,
        .vision = 5,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 2, .spell = &spells.CAST_RESURRECT_FIRE, .power = 200, .duration = 10 },
            .{ .MP_cost = 3, .spell = &spells.BOLT_FIRE, .power = 5, .duration = 10 },
        },
        .max_MP = 12,

        .willpower = 8,
        .base_dexterity = 20,
        .hearing = 6,
        .max_HP = 50,
        .memory_duration = 6,
        .base_speed = 100,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = 3, .rFire = 3, .rElec = -1 },

        .base_strength = 40,
    },
    .statuses = &[_]StatusDataInfo{.{ .status = .Fire, .permanent = true }},
};

pub const SulfurFiendTemplate = MobTemplate{
    .id = "sulfur_fiend",
    .mob = .{
        .species = &Species{ .name = "sulfur fiend" },
        .tile = 'S',
        .ai = AI{
            .profession_name = null,
            .profession_description = "sulking",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.mageFight,
            .is_combative = true,
            .is_curious = true,
            .is_fearless = true,
            .spellcaster_backup_action = .KeepDistance,
        },
        .allegiance = .Necromancer,
        .vision = 5,
        .spells = &[_]SpellOptions{
            .{ .MP_cost = 1, .spell = &spells.CAST_HASTEN_ROT, .power = 150 },
            .{ .MP_cost = 4, .spell = &spells.CAST_CONJ_BALL_LIGHTNING, .power = 12 },
        },
        .max_MP = 10,

        .willpower = 10,
        .base_dexterity = 25,
        .hearing = 6,
        .max_HP = 40,
        .memory_duration = 6,
        .base_speed = 100,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = 3, .rFire = 1, .rElec = 3, .rFume = 2 },

        .base_strength = 30,
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.GambesonArmor,
};

pub const FrozenFiendTemplate = MobTemplate{
    .id = "frozen_fiend",
    .mob = .{
        .species = &Species{ .name = "frozen fiend" },
        .tile = 'F',
        .ai = AI{
            .profession_name = null,
            .profession_description = "patrolling",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.mageFight,
            .is_combative = true,
            .is_curious = true,
            .is_fearless = true,
            .spellcaster_backup_action = .Melee,
        },
        .allegiance = .Necromancer,
        .vision = 7,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 2, .spell = &spells.CAST_POLAR_LAYER, .power = 14 },
            .{ .MP_cost = 3, .spell = &spells.CAST_RESURRECT_FROZEN, .power = 21 },
        },
        .max_MP = 15,

        .willpower = 8,
        .base_dexterity = 20,
        .hearing = 6,
        .max_HP = 55,
        .memory_duration = 6,
        .base_speed = 100,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = 2, .rElec = 2 },

        .base_strength = 35,
    },
    .weapon = &items.MorningstarWeapon,
    .armor = &items.ChainmailArmor,
};

pub const TanusExperiment = MobTemplate{
    .id = "tanus_experiment",
    .mob = .{
        .species = &Species{ .name = "tanusian experiment" },
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,

        .willpower = 3,
        .base_dexterity = 30,
        .hearing = 5,
        .max_HP = 50,
        .memory_duration = 8,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.ClubWeapon,
    .armor = &items.LeatherArmor,
    .statuses = &[_]StatusDataInfo{.{ .status = .Backvision, .permanent = true }},
};

pub const CatalineExperiment = MobTemplate{
    .id = "cataline_experiment",
    .mob = .{
        .species = &Species{ .name = "catalinic experiment" },
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,

        .willpower = 3,
        .base_dexterity = 30,
        .hearing = 5,
        .max_HP = 50,
        .memory_duration = 8,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.ClubWeapon,
    .armor = &items.LeatherArmor,
    .statuses = &[_]StatusDataInfo{.{ .status = .NightVision, .permanent = true }},
};

pub const FlouinExperiment = MobTemplate{
    .id = "flouin_experiment",
    .mob = .{
        .species = &Species{ .name = "flouinian experiment" },
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,

        .willpower = 3,
        .base_dexterity = 30,
        .hearing = 5,
        .max_HP = 50,
        .memory_duration = 15,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.ClubWeapon,
    .armor = &items.LeatherArmor,
    .statuses = &[_]StatusDataInfo{.{ .status = .DayBlindness, .permanent = true }},
};

pub const PhytinExperiment = MobTemplate{
    .id = "phytin_experiment",
    .mob = .{
        .species = &Species{ .name = "phytinic experiment" },
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,

        .willpower = 3,
        .base_dexterity = 30,
        .hearing = 5,
        .max_HP = 50,
        .memory_duration = 15,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.ClubWeapon,
    .armor = &items.LeatherArmor,
    .statuses = &[_]StatusDataInfo{.{ .status = .NightBlindness, .permanent = true }},
};

pub const LivingIceTemplate = MobTemplate{
    .id = "living_ice",
    .mob = .{
        .species = &Species{
            .name = "living ice",
            .default_attack = &items.LivingIceHitWeapon,
        },
        .tile = '8',
        .ai = AI{
            .profession_name = null,
            .profession_description = "watching",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = false,
            .is_fearless = true,
        },
        .allegiance = .Necromancer,

        .vision = 2,
        .deg360_vision = true,
        .no_show_fov = true,
        .immobile = true,
        .willpower = 1,
        .base_dexterity = 0,
        .hearing = 5,
        .max_HP = 100,
        .memory_duration = 1,
        .base_speed = 100,

        .blood = .Water,
        .corpse = .Wall,

        .base_strength = 30,

        .innate_resists = .{ .rPois = 3, .rFire = -2, .rElec = 3, .rMlee = 1, .rFume = 3 },
    },
    // This status should be added by whatever spell created it.
    //.statuses = &[_]StatusDataInfo{.{ .status = .Lifespan, .duration = 10 }},
};

pub const BallLightningTemplate = MobTemplate{
    .id = "ball_lightning",
    .mob = .{
        .species = &Species{ .name = "ball lightning" },
        .tile = 'b',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.ballLightningWorkOrFight,
            .fight_fn = ai.ballLightningWorkOrFight,
            .is_combative = true,
            .is_curious = false,
            .is_fearless = true,
        },
        .allegiance = .Necromancer,

        .hearing = 0,
        .vision = 20,
        .deg360_vision = true,
        .no_show_fov = true,
        .immobile = false,
        .willpower = 1,
        .base_dexterity = 50,
        .deaf = true,
        .max_HP = 3,
        .memory_duration = 1,
        .base_speed = 33,

        .blood = null,
        .corpse = .None,

        .base_strength = 1,

        .innate_resists = .{ .rPois = 3, .rFire = 1, .rElec = 3, .rMlee = 1, .rFume = 3 },
    },
    // This status should be added by whatever spell created it.
    .statuses = &[_]StatusDataInfo{
        .{ .status = .ExplosiveElec, .power = 20, .permanent = true },
    },
};

pub const MOBS = [_]MobTemplate{
    ExecutionerTemplate,
    WatcherTemplate,
    WardenTemplate,
    GuardTemplate,
    JavelineerTemplate,
    SentinelTemplate,
    PatrolTemplate,
    PlayerTemplate,
    InteractionLaborerTemplate,
    GoblinTemplate,
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
    AlchemistTemplate,
    CleanerTemplate,
    EngineerTemplate,
    HaulerTemplate,
    TorturerNecromancerTemplate,
    BurningBruteTemplate,
    FrozenFiendTemplate,
    SulfurFiendTemplate,
    TanusExperiment,
    CatalineExperiment,
    FlouinExperiment,
    PhytinExperiment,
};

pub const PRISONERS = [_]MobTemplate{
    GoblinTemplate,
};

pub const STATUES = [_]MobTemplate{
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
};

pub const EXPERIMENTS = [_]MobTemplate{
    TanusExperiment,
    CatalineExperiment,
    FlouinExperiment,
    PhytinExperiment,
};

pub const PlaceMobOptions = struct {
    facing: ?Direction = null,
    phase: AIPhase = .Work,
    work_area: ?Coord = null,
};

pub fn placeMob(
    alloc: *mem.Allocator,
    template: *const MobTemplate,
    coord: Coord,
    opts: PlaceMobOptions,
) *Mob {
    var mob = template.mob;
    mob.init(alloc);
    mob.coord = coord;
    mob.ai.phase = opts.phase;

    if (template.weapon) |w| mob.inventory.wielded = items.createItem(Weapon, w.*);
    if (template.backup_weapon) |w| mob.inventory.backup = items.createItem(Weapon, w.*);
    if (template.armor) |a| mob.inventory.armor = items.createItem(Armor, a.*);
    if (template.cloak) |c| mob.inventory.cloak = c;

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
        mob.addStatus(status_info.status, status_info.power, status_info.duration, status_info.permanent);
    }

    state.mobs.append(mob) catch err.wat();
    const ptr = state.mobs.last().?;
    state.dungeon.at(coord).mob = ptr;
    return ptr;
}
