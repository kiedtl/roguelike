const ai = @import("../ai.zig");
const mobs = @import("../mobs.zig");
const spells = @import("../spells.zig");
const types = @import("../types.zig");

const SpellOptions = spells.SpellOptions;
const MobTemplate = mobs.MobTemplate;
const AI = types.AI;

pub const Dummy_L_Immobile = MobTemplate{
    .mob = .{
        .id = "dummy_l_immobile",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <immobile>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.combatDummyFight,
        },
        .immobile = true,
        .max_HP = 1,
    },
};

pub const Dummy_L_Immobile_Omniscient = MobTemplate{
    .mob = .{
        .id = "dummy_l_immobile_omniscient",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <immobile>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.combatDummyFight,
        },
        .deg360_vision = true,
        .immobile = true,
        .max_HP = 1,
    },
};

pub const Dummy_L_Meleedude = MobTemplate{
    .mob = .{
        .id = "dummy_l_meleedude",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <meleedude>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.meleeFight,
        },
        .max_HP = 1,
        .stats = .{ .Melee = 100, .Evade = 100 },
    },
};

pub const Dummy_L_Javelineer = MobTemplate{
    .mob = .{
        .id = "dummy_l_javelineer",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <javelineer>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.mageFight,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 4, .spell = &spells.BOLT_JAVELIN, .power = 1, .duration = 3 },
        },
        .max_MP = 10,

        .max_HP = 1,
        .stats = .{ .Missile = 100 },
    },
};

pub const Dummy_L_Javelineer_SF = MobTemplate{
    .mob = .{
        .id = "dummy_l_javelineer_sf",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <javelineer>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.mageFight,
            .flags = &[_]AI.Flag{.SocialFighter},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 4, .spell = &spells.BOLT_JAVELIN, .power = 1, .duration = 3 },
        },
        .max_MP = 10,

        .max_HP = 1,
        .stats = .{ .Missile = 100 },
    },
};

pub const Dummy_L_Javelineer_SF2 = MobTemplate{
    .mob = .{
        .id = "dummy_l_javelineer_sf2",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <javelineer>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.mageFight,
            .flags = &[_]AI.Flag{.SocialFighter2},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 4, .spell = &spells.BOLT_JAVELIN, .power = 1, .duration = 3 },
        },
        .max_MP = 10,

        .max_HP = 1,
        .stats = .{ .Missile = 100 },
    },
};

pub const Dummy_L_Ignored = MobTemplate{
    .mob = .{
        .id = "dummy_l_ignored",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <ignored>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.combatDummyFight,
            .flags = &[_]AI.Flag{.IgnoredByEnemies},
        },
        .max_HP = 1,
    },
};

pub const Dummy_C_Immobile = MobTemplate{
    .mob = .{
        .id = "dummy_c_immobile",
        .species = &mobs.HumanSpecies,
        .tile = '0',
        .ai = AI{
            .profession_name = "dummy <immobile>",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.combatDummyFight,
        },
        .immobile = true,
        .life_type = .Construct,
        .max_HP = 1,
    },
};

pub const MOBS = [_]*const MobTemplate{
    &Dummy_L_Immobile,
    &Dummy_L_Immobile_Omniscient,
    &Dummy_L_Meleedude,
    &Dummy_L_Javelineer,
    &Dummy_L_Javelineer_SF,
    &Dummy_L_Javelineer_SF2,
    &Dummy_L_Ignored,
    &Dummy_C_Immobile,
};
