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
            .profession_name = "dummy",
            .profession_description = "crying",
            .work_fn = ai.combatDummyWork,
            .fight_fn = ai.combatDummyFight,
        },
        .immobile = true,
        .max_HP = 1,
    },
};
