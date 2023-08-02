const ai = @import("../ai.zig");
const mobs = @import("../mobs.zig");
const types = @import("../types.zig");

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

pub const MOBS = [_]MobTemplate{
    Dummy_L_Immobile,
    Dummy_L_Meleedude,
    Dummy_L_Ignored,
    Dummy_C_Immobile,
};
