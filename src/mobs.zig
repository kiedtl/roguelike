const ai = @import("ai.zig");
const items = @import("items.zig");
const buffer = @import("buffer.zig");
const spells = @import("spells.zig");
usingnamespace @import("types.zig");

const Evocable = items.Evocable;
const StackBuffer = buffer.StackBuffer;
const SpellInfo = spells.SpellInfo;

pub const MobTemplate = struct {
    id: []const u8,
    mob: Mob,
    weapon: ?*const Weapon = null,
    backup_weapon: ?*const Weapon = null,
    armor: ?*const Armor = null,
    statuses: []const StatusDataInfo = &[_]StatusDataInfo{},
    evocables: []const Evocable = &[_]Evocable{},
};

pub const ExecutionerTemplate = MobTemplate{
    .id = "executioner",
    .mob = .{
        .species = "human",
        .tile = 'א',
        .ai = AI{
            .profession_name = "executioner",
            .profession_description = "goofing around",
            .work_fn = ai.goofingAroundWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 6,
        .base_night_vision = 30,

        .willpower = 3,
        .base_dexterity = 35,
        .hearing = 7,
        .max_HP = 60,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 20,
    },
    .weapon = &items.ZinnagWeapon,
};

pub const WatcherTemplate = MobTemplate{
    .id = "watcher",
    .mob = .{
        .species = "imp",
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
        .vision = 7,
        .base_night_vision = 15,

        .willpower = 3,
        .base_dexterity = 17,
        .hearing = 5,
        .max_HP = 40,
        .memory_duration = 10,
        .base_speed = 60,
        .blood = .Blood,

        .base_strength = 15, // weakling!
    },
};

pub const WardenTemplate = MobTemplate{
    .id = "guard",
    .mob = .{
        .species = "goblin",
        .tile = 'ם',
        .ai = AI{
            .profession_name = "warden",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 5,
        .base_night_vision = 35,

        .willpower = 3,
        .base_dexterity = 20,
        .hearing = 7,
        .max_HP = 40,
        .memory_duration = 6,
        .base_speed = 120,
        .blood = .Blood,

        .base_strength = 24,
    },
    .weapon = &items.SwordWeapon,
    .armor = &items.HeavyChainmailArmor,
};

pub const GuardTemplate = MobTemplate{
    .id = "guard",
    .mob = .{
        .species = "goblin",
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
        .vision = 6,
        .base_night_vision = 30,

        .willpower = 2,
        .base_dexterity = 25,
        .hearing = 7,
        .max_HP = 50,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 20,
    },
    .weapon = &items.SwordWeapon,
    .armor = &items.HeavyChainmailArmor,
};

pub const SentinelTemplate = MobTemplate{
    .id = "sentinel",
    .mob = .{
        .species = "human",
        .tile = 'ל',
        .ai = AI{
            .profession_name = "sentinel",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.sentinelFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 8,
        .base_night_vision = 20,

        .willpower = 5,
        .base_dexterity = 30,
        .hearing = 6,
        .max_HP = 65,
        .memory_duration = 7,
        .base_speed = 90,
        .blood = .Blood,

        .base_strength = 28,
    },
    .weapon = &items.DartLauncher,
    .backup_weapon = &items.NetLauncher,
    .armor = &items.HeavyChainmailArmor,
};

pub const PatrolTemplate = MobTemplate{
    .id = "patrol",
    .mob = .{
        .species = "goblin",
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
        .vision = 6,
        .base_night_vision = 35,

        .willpower = 2,
        .base_dexterity = 25,
        .hearing = 7,
        .max_HP = 60,
        .memory_duration = 3,
        .base_speed = 110,
        .blood = .Blood,

        .base_strength = 20,
    },
    .weapon = &items.SpearWeapon,
    .armor = &items.HeavyChainmailArmor,
};

pub const PlayerTemplate = MobTemplate{
    .id = "player",
    .mob = .{
        .species = "human",
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
        .vision = 25,
        .base_night_vision = 0,
        .deg360_vision = true,
        .no_show_fov = true,

        .willpower = 6,
        .base_dexterity = 28,
        .hearing = 5,
        .max_HP = 60,
        .memory_duration = 10,
        .base_speed = 80,
        .blood = .Blood,

        .base_strength = 19,
    },
    .weapon = &items.DaggerWeapon,
    .backup_weapon = &items.NetLauncher,
    .armor = &items.LeatherArmor,
};

pub const InteractionLaborerTemplate = MobTemplate{
    .id = "interaction_laborer",
    .mob = .{
        .species = "goblin",
        .tile = 'u',
        .ai = AI{
            .profession_name = "slave",
            .profession_description = "laboring",
            .work_fn = ai.interactionLaborerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .Necromancer,
        .vision = 6,
        .base_night_vision = 30,

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
        .species = "goblin",
        .tile = 'g',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .OtherEvil,
        .vision = 12,
        .base_night_vision = 0,

        .willpower = 3,
        .base_dexterity = 43,
        .hearing = 5,
        .max_HP = 70,
        .memory_duration = 8,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.ClubWeapon,
    .armor = &items.LeatherArmor,
};

pub const CaveRatTemplate = MobTemplate{
    .id = "cave_rat",
    .mob = .{
        .species = "cave rat",
        .tile = '²',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .OtherEvil,
        .vision = 12,
        .base_night_vision = 0,

        .willpower = 1,
        .base_dexterity = 60,
        .hearing = 3,
        .max_HP = 15,
        .memory_duration = 15,
        .base_speed = 40,
        .blood = .Blood,

        .base_strength = 5,
    },
};

pub const KyaniteStatueTemplate = MobTemplate{
    .id = "kyanite_statue",
    .mob = .{
        .species = "kyanite statue",
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
        .base_night_vision = 0,
        .deg360_vision = true,
        .no_show_fov = true,
        .spells = StackBuffer(SpellInfo, 2).init(&[_]SpellInfo{
            .{ .spell = &spells.CAST_FREEZE, .duration = 2 },
        }),

        .willpower = 8,
        .base_dexterity = 100,
        .hearing = 0,
        .max_HP = 100,
        .regen = 100,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .immobile = true,
        .unbreathing = true,

        .base_strength = 1,
    },
};

pub const NebroStatueTemplate = MobTemplate{
    .id = "nebro_statue",
    .mob = .{
        .species = "nebro statue",
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
        .base_night_vision = 0,
        .deg360_vision = true,
        .no_show_fov = true,
        .spells = StackBuffer(SpellInfo, 2).init(&[_]SpellInfo{
            .{ .spell = &spells.CAST_FAMOUS, .duration = 15, .power = 50 },
        }),

        .willpower = 8,
        .base_dexterity = 100,
        .hearing = 0,
        .max_HP = 1000,
        .regen = 100,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .immobile = true,
        .unbreathing = true,

        .base_strength = 2,
    },
};

pub const CrystalStatueTemplate = MobTemplate{
    .id = "crystal_statue",
    .mob = .{
        .species = "crystal statue",
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
        .base_night_vision = 0,
        .deg360_vision = true,
        .no_show_fov = true,
        .spells = StackBuffer(SpellInfo, 2).init(&[_]SpellInfo{
            .{ .spell = &spells.CAST_FERMENT, .duration = 15, .power = 50 },
        }),

        .willpower = 8,
        .base_dexterity = 100,
        .hearing = 0,
        .max_HP = 1000,
        .regen = 100,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .immobile = true,
        .unbreathing = true,

        .base_strength = 2,
    },
};

pub const AlchemistTemplate = MobTemplate{
    .id = "alchemist",
    .mob = .{
        .species = "human",
        .tile = 'h',
        .ai = AI{
            .profession_name = "alchemist",
            .profession_description = "experimenting",
            .work_fn = ai.guardWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .Necromancer,
        .vision = 7,
        .base_night_vision = 20,

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
        .species = "human",
        .tile = 'h',
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
        .vision = 6,
        .base_night_vision = 30,

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
        .species = "goblin",
        .tile = 'u',
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
        .vision = 6,
        .base_night_vision = 30,

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

pub const TorturerNecromancerTemplate = MobTemplate{
    .id = "torturer_necromancer",
    .mob = .{
        .species = "necromancer",
        .tile = 'Ñ',
        .ai = AI{
            .profession_name = "torturer",
            .profession_description = "torturing",
            .work_fn = ai.tortureWork,
            .fight_fn = ai.mageFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 6,
        .base_night_vision = 20,
        .no_show_fov = false,
        .spells = StackBuffer(SpellInfo, 2).init(&[_]SpellInfo{
            .{ .spell = &spells.CAST_PAIN, .duration = 7, .power = 20 },
            .{ .spell = &spells.CAST_FEAR, .duration = 7 },
        }),

        .willpower = 10,
        .base_dexterity = 30,
        .hearing = 6,
        .max_HP = 80,
        .memory_duration = 10,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 25,
    },
    .weapon = &items.SwordWeapon,
    .armor = &items.HeavyChainmailArmor,
};

pub const TanusExperiment = MobTemplate{
    .id = "tanus_experiment",
    .mob = .{
        .species = "tanusian experiment",
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 6,
        .base_night_vision = 20,

        .willpower = 3,
        .base_dexterity = 43,
        .hearing = 5,
        .max_HP = 70,
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
        .species = "catalinic experiment",
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 6,
        .base_night_vision = 20,

        .willpower = 3,
        .base_dexterity = 43,
        .hearing = 5,
        .max_HP = 70,
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
        .species = "flouinian experiment",
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 6,
        .base_night_vision = 20,

        .willpower = 3,
        .base_dexterity = 43,
        .hearing = 5,
        .max_HP = 70,
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
        .species = "phytinic experiment",
        .tile = 'e',
        .ai = AI{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Necromancer,
        .vision = 6,
        .base_night_vision = 20,

        .willpower = 3,
        .base_dexterity = 43,
        .hearing = 5,
        .max_HP = 70,
        .memory_duration = 15,
        .base_speed = 100,
        .blood = .Blood,

        .base_strength = 18,
    },
    .weapon = &items.ClubWeapon,
    .armor = &items.LeatherArmor,
    .statuses = &[_]StatusDataInfo{.{ .status = .NightBlindness, .permanent = true }},
};

pub const MOBS = [_]MobTemplate{
    ExecutionerTemplate,
    WatcherTemplate,
    WardenTemplate,
    GuardTemplate,
    SentinelTemplate,
    PatrolTemplate,
    PlayerTemplate,
    InteractionLaborerTemplate,
    GoblinTemplate,
    CaveRatTemplate,
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
    AlchemistTemplate,
    CleanerTemplate,
    HaulerTemplate,
    TorturerNecromancerTemplate,
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
