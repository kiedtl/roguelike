const ai = @import("ai.zig");
const items = @import("items.zig");
const buffer = @import("buffer.zig");
const spells = @import("spells.zig");
usingnamespace @import("types.zig");

const StackBuffer = buffer.StackBuffer;
const SpellInfo = spells.SpellInfo;

pub const MobTemplate = struct {
    id: []const u8,
    mob: Mob,
    weapon: ?*const Weapon = null,
    backup_weapon: ?*const Weapon = null,
    armor: ?*const Armor = null,
};

pub const ExecutionerTemplate = MobTemplate{
    .id = "executioner",
    .mob = .{
        .species = "human",
        .tile = 'א',
        .occupation = Occupation{
            .profession_name = "executioner",
            .profession_description = "goofing around",
            .work_fn = ai.goofingAroundWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Sauron,
        .vision = 6,
        .night_vision = 30,

        .willpower = 3,
        .dexterity = 18,
        .hearing = 7,
        .max_HP = 60,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .strength = 20,
    },
    .weapon = &items.ZinnagWeapon,
};

pub const WatcherTemplate = MobTemplate{
    .id = "watcher",
    .mob = .{
        .species = "imp",
        .tile = 'ש',
        .occupation = Occupation{
            .profession_name = "watcher",
            .profession_description = "guarding",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.flee,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Sauron,
        .vision = 7,
        .night_vision = 15,

        .willpower = 3,
        .dexterity = 17,
        .hearing = 5,
        .max_HP = 40,
        .memory_duration = 10,
        .base_speed = 60,
        .blood = .Blood,

        .strength = 15, // weakling!
    },
};

pub const GuardTemplate = MobTemplate{
    .id = "patrol",
    .mob = .{
        .species = "orc",
        .tile = 'ק',
        .occupation = Occupation{
            .profession_name = "guard",
            .profession_description = "patrolling",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .Sauron,
        .vision = 6,
        .night_vision = 35,

        .willpower = 2,
        .dexterity = 20,
        .hearing = 7,
        .max_HP = 60,
        .memory_duration = 3,
        .base_speed = 110,
        .blood = .Blood,

        .strength = 20,
    },
    .weapon = &items.SpearWeapon,
    .armor = &items.HeavyChainmailArmor,
};

pub const PlayerTemplate = MobTemplate{
    .id = "player",
    .mob = .{
        .species = "human",
        .tile = '@',
        .occupation = Occupation{
            .profession_name = "[this is a bug]",
            .profession_description = "[this is a bug]",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.meleeFight,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .Illuvatar,
        .vision = 15,
        .night_vision = 3,
        .deg360_vision = true,
        .no_show_fov = true,

        .willpower = 6,
        .dexterity = 21,
        .hearing = 5,
        .max_HP = 60,
        .memory_duration = 10,
        .base_speed = 80,
        .blood = .Blood,

        .strength = 19,
    },
    .weapon = &items.DaggerWeapon,
    .armor = &items.LeatherArmor,
};

pub const InteractionLaborerTemplate = MobTemplate{
    .id = "interaction_laborer",
    .mob = .{
        .species = "orc",
        .tile = 'o',
        .occupation = Occupation{
            .profession_name = "slave",
            .profession_description = "laboring",
            .work_fn = ai.interactionLaborerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .Sauron,
        .vision = 6,
        .night_vision = 30,

        .willpower = 2,
        .dexterity = 19,
        .hearing = 10,
        .max_HP = 60,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .strength = 10,
    },
};

pub const GoblinTemplate = MobTemplate{
    .id = "goblin",
    .mob = .{
        .species = "goblin",
        .tile = 'g',
        .occupation = Occupation{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = true,
            .is_curious = true,
        },
        .allegiance = .NoneEvil,
        .vision = 12,
        .night_vision = 0,

        .willpower = 3,
        .dexterity = 18,
        .hearing = 5,
        .max_HP = 70,
        .memory_duration = 8,
        .base_speed = 100,
        .blood = .Blood,

        .strength = 18,
    },
    .weapon = &items.ClubWeapon,
    .armor = &items.LeatherArmor,
};

pub const CaveRatTemplate = MobTemplate{
    .id = "cave_rat",
    .mob = .{
        .species = "cave rat",
        .tile = '²',
        .occupation = Occupation{
            .profession_name = null,
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .NoneEvil,
        .vision = 12,
        .night_vision = 0,

        .willpower = 1,
        .dexterity = 10,
        .hearing = 3,
        .max_HP = 15,
        .memory_duration = 15,
        .base_speed = 40,
        .blood = .Blood,

        .strength = 5,
    },
};

pub const KyaniteStatueTemplate = MobTemplate{
    .id = "kyanite_statue",
    .mob = .{
        .species = "kyanite statue",
        .tile = '☺',
        .occupation = Occupation{
            .profession_name = null,
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Sauron,
        .vision = 20,
        .night_vision = 0,
        .deg360_vision = true,
        .no_show_fov = true,
        .spells = StackBuffer(SpellInfo, 2).init(&[_]SpellInfo{
            .{ .spell = &spells.CAST_FREEZE, .duration = 2 },
        }),

        .willpower = 8,
        .dexterity = 100,
        .hearing = 0,
        .max_HP = 100,
        .regen = 100,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .immobile = true,

        .strength = 1,
    },
};

pub const NebroStatueTemplate = MobTemplate{
    .id = "nebro_statue",
    .mob = .{
        .species = "nebro statue",
        .tile = '☻',
        .occupation = Occupation{
            .profession_name = null,
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Sauron,
        .vision = 20,
        .night_vision = 0,
        .deg360_vision = true,
        .no_show_fov = true,
        .spells = StackBuffer(SpellInfo, 2).init(&[_]SpellInfo{
            .{ .spell = &spells.CAST_FAMOUS, .duration = 15, .power = 50 },
        }),

        .willpower = 8,
        .dexterity = 100,
        .hearing = 0,
        .max_HP = 1000,
        .regen = 100,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .immobile = true,

        .strength = 2,
    },
};

pub const CrystalStatueTemplate = MobTemplate{
    .id = "crystal_statue",
    .mob = .{
        .species = "crystal statue",
        .tile = '☻',
        .occupation = Occupation{
            .profession_name = null,
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_combative = true,
            .is_curious = false,
        },
        .allegiance = .Sauron,
        .vision = 20,
        .night_vision = 0,
        .deg360_vision = true,
        .no_show_fov = true,
        .spells = StackBuffer(SpellInfo, 2).init(&[_]SpellInfo{
            .{ .spell = &spells.CAST_FERMENT, .duration = 15, .power = 50 },
        }),

        .willpower = 8,
        .dexterity = 100,
        .hearing = 0,
        .max_HP = 1000,
        .regen = 100,
        .memory_duration = 1,
        .base_speed = 100,
        .blood = null,
        .immobile = true,

        .strength = 2,
    },
};

pub const CleanerTemplate = MobTemplate{
    .id = "cleaner",
    .mob = .{
        .species = "human",
        .tile = 'h',
        .occupation = Occupation{
            .profession_name = "cleaner",
            .profession_description = "cleaning",
            .work_fn = ai.cleanerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
        },
        .allegiance = .Sauron,
        .vision = 6,
        .night_vision = 30,

        .willpower = 2,
        .dexterity = 19,
        .hearing = 10,
        .max_HP = 60,
        .memory_duration = 5,
        .base_speed = 100,
        .blood = .Blood,

        .strength = 10,
    },
};

pub const MOBS = [_]MobTemplate{
    WatcherTemplate,
    ExecutionerTemplate,
    GuardTemplate,
    PlayerTemplate,
    InteractionLaborerTemplate,
    GoblinTemplate,
    CaveRatTemplate,
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
    CleanerTemplate,
};

pub const STATUES = [_]MobTemplate{
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
};
