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

// -----------------------------------------------------------------------------

const NONE_WEAPON = Weapon{
    .id = "",
    .name = "",
    .damage = 0,
    .strs = &[_]DamageStr{
        items._dmgstr(080, "hurl", "hurls", " at kiedtl"),
    },
};

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
    armor: ?*const Armor = null,
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
};

pub const ExecutionerTemplate = MobTemplate{
    .mob = .{
        .id = "executioner",
        .species = &GoblinSpecies,
        .tile = 'א',
        .ai = AI{
            .profession_name = "executioner",
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
        },

        .max_HP = 7,
        .memory_duration = 5,
        .stats = .{ .Willpower = 3 },
    },
    .weapon = &items.KnoutWeapon,
};

pub const DestroyerTemplate = MobTemplate{
    .mob = .{
        .id = "destroyer",
        .species = &GoblinSpecies,
        .tile = 'ד',
        .ai = AI{
            .profession_name = "destroyer",
            .profession_description = "wandering",
            .work_fn = ai.wanderWork,
            .fight_fn = ai.meleeFight,
        },

        .max_HP = 8,
        .memory_duration = 5,
        .stats = .{ .Willpower = 4, .Evade = 10, .Melee = 70 },
    },
    .weapon = &items.KnoutWeapon,
    .armor = &items.HauberkArmor,
};

pub const WatcherTemplate = MobTemplate{
    .mob = .{
        .id = "watcher",
        .species = &ImpSpecies,
        .tile = 'ש',
        .ai = AI{
            .profession_name = "watcher",
            .profession_description = "guarding",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.watcherFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{.FearsDarkness},
        },
        .max_HP = 6,
        .memory_duration = 10,
        .stats = .{ .Willpower = 3, .Evade = 30, .Speed = 60 },
    },
};

pub const ShriekerTemplate = MobTemplate{
    .mob = .{
        .id = "shrieker",
        .species = &ImpSpecies,
        .tile = 'ל',
        .ai = AI{
            .profession_name = "shrieker",
            .profession_description = "guarding",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.shriekerFight,
            .is_curious = false,
            .flags = &[_]AI.Flag{.FearsDarkness},
        },
        .max_HP = 3,
        .memory_duration = 15,
        .stats = .{ .Willpower = 4, .Evade = 40, .Speed = 50 },
    },
};

pub const GuardTemplate = MobTemplate{
    .mob = .{
        .id = "guard",
        .species = &GoblinSpecies,
        .tile = 'ה',
        .ai = AI{
            .profession_name = "guard",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
        },

        .max_HP = 8,
        .memory_duration = 5,

        .stats = .{ .Willpower = 2 },
    },
    .weapon = &items.BludgeonWeapon,
    .armor = &items.GambesonArmor,
};

pub const SentinelTemplate = MobTemplate{
    .mob = .{
        .id = "sentinel",
        .species = &GoblinSpecies,
        .tile = 'ת',
        .ai = AI{
            .profession_name = "sentinel",
            .profession_description = "guarding",
            .work_fn = ai.guardWork,
            .fight_fn = ai.meleeFight,
        },

        .max_HP = 12,
        .memory_duration = 5,

        .stats = .{ .Willpower = 2, .Melee = 70 },
    },
    .weapon = &items.SwordWeapon,
    .armor = &items.GambesonArmor,
};

pub const JavelineerTemplate = MobTemplate{
    .mob = .{
        .id = "javelineer",
        .species = &GoblinSpecies,
        .tile = 'j',
        .ai = AI{
            .profession_name = "javelineer",
            .profession_description = "guarding",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.rangedFight,
            .flee_effect = .{
                .status = .Enraged,
                .duration = .{ .Tmp = 10 },
                .exhausting = true,
            },
        },

        .max_HP = 8,
        .memory_duration = 6,
        .stats = .{ .Willpower = 2, .Evade = 10, .Missile = 80, .Speed = 110, .Vision = 5 },
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.GambesonArmor,
    .projectile = &items.JavelinProj,
};

pub const DefenderTemplate = MobTemplate{
    .mob = .{
        .id = "defender",
        .species = &HumanSpecies,
        .tile = 'ץ',
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
        },

        .max_HP = 8,
        .memory_duration = 4,
        .stats = .{ .Willpower = 4, .Evade = 10, .Missile = 90 },
    },
    .weapon = &items.SwordWeapon,
    .armor = &items.HauberkArmor,
    .projectile = &items.NetProj,
};

pub const LeadTurtleTemplate = MobTemplate{
    .mob = .{
        .id = "lead_turtle",
        .species = &Species{
            .name = "lead turtle",
            .default_attack = &Weapon{
                .reach = 2,
                .damage = 4,
                .strs = &items.BITING_STRS,
            },
        },
        .tile = 't',
        .life_type = .Construct,
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .max_HP = 20,
        .memory_duration = 20,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rElec = -100, .rPois = RESIST_IMMUNE, .rFire = RESIST_IMMUNE, .Armor = 60, .rFume = 100 },
        .stats = .{ .Willpower = 5, .Melee = 100, .Speed = 250, .Vision = 4 },
    },

    .statuses = &[_]StatusDataInfo{.{ .status = .Sleeping, .duration = .Prm }},
};

pub const IronWaspTemplate = MobTemplate{
    .mob = .{
        .id = "iron_wasp",
        .species = &Species{
            .name = "iron wasp",
            .default_attack = &Weapon{
                .damage = 1,
                .effects = &[_]StatusDataInfo{
                    .{ .status = .Poison, .duration = .{ .Tmp = 5 } },
                },
                .strs = &[_]DamageStr{
                    items._dmgstr(005, "jab", "jabs", ""),
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
        },
        .max_HP = 2,
        .memory_duration = 3,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = 50, .rFume = 100 },
        .stats = .{ .Willpower = 1, .Evade = 50, .Speed = 55, .Vision = 3 },
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
                .damage = 1,
                .ego = .Copper,
                .damage_kind = .Electric,
                .strs = &[_]DamageStr{
                    items._dmgstr(005, "jab", "jabs", ""),
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
        },
        .max_HP = 5,
        .memory_duration = 7,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rElec = 25, .rFire = 50, .rFume = 100 },
        .stats = .{ .Willpower = 0, .Evade = 40, .Speed = 60, .Vision = 5 },
    },

    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm }, .{ .status = .Noisy, .duration = .Prm },
    },
};

pub const PatrolTemplate = MobTemplate{
    .mob = .{
        .id = "patrol",
        .species = &GoblinSpecies,
        .tile = 'ק',
        .ai = AI{
            .profession_name = "patrol",
            .profession_description = "patrolling",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
            .flags = &[_]AI.Flag{.FearsDarkness},
        },

        .max_HP = 8,
        .memory_duration = 3,
        .stats = .{ .Willpower = 2, .Evade = 10, .Speed = 110 },
    },
    .weapon = &items.GlaiveWeapon,
    .armor = &items.GambesonArmor,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
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
        .allegiance = .OtherGood,
        .base_night_vision = true,
        .deg360_vision = true,
        .no_show_fov = true,

        .max_HP = 14,
        .memory_duration = 10,

        .stats = .{ .Willpower = 3, .Missile = 60, .Evade = 10, .Vision = 8, .Sneak = 4 },
    },
    .weapon = &items.DaggerWeapon,
    //.backup_weapon = &items.RapierWeapon,
    .armor = &items.RobeArmor,
    //.evocables = &[_]Evocable{items.FlamethrowerEvoc},
    //.cloak = &items.ThornsCloak,
};

pub const GoblinTemplate = MobTemplate{
    .mob = .{
        .id = "goblin",
        .species = &GoblinSpecies,
        .tile = 'g',
        .ai = AI{
            .profession_name = "cave goblin",
            .profession_description = "wandering",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
        },
        .allegiance = .OtherEvil,
        .max_HP = 12,
        .memory_duration = 8,
        .stats = .{ .Willpower = 4, .Evade = 15, .Vision = 6 },
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.GambesonArmor,
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
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 3, .spell = &spells.CAST_ENRAGE_DUSTLING, .power = 9 },
        },
        .max_MP = 6,

        .max_HP = 15,
        .memory_duration = 8,
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
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 8, .spell = &spells.BOLT_AIRBLAST, .power = 6 },
            .{ .MP_cost = 2, .spell = &spells.CAST_HASTE_DUSTLING, .power = 10 },
        },
        .max_MP = 15,

        .max_HP = 13,
        .memory_duration = 10,
        .stats = .{ .Willpower = 6, .Speed = 120, .Vision = 6 },
    },
    .armor = &items.HauberkArmor,
    .statuses = &[_]StatusDataInfo{.{ .status = .NightVision, .duration = .Prm }},
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
            .default_attack = &Weapon{ .damage = 1, .strs = &items.FIST_STRS },
        },
        .tile = 'ð',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.meleeFight,
        },
        .max_HP = 2,
        .memory_duration = 3,
        .life_type = .Construct,
        .blood = .Dust,
        .blood_spray = gas.Dust.id,
        .corpse = .None,
        .innate_resists = .{ .rFire = -25, .rElec = -25, .rFume = 100 },
        .stats = .{ .Willpower = 4, .Melee = 50, .Speed = 80, .Vision = 3 },
    },
    .statuses = &[_]StatusDataInfo{.{ .status = .NightVision, .duration = .Prm }},
    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "dustling", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
};

pub const CinderWormTemplate = MobTemplate{
    .mob = .{
        .id = "cinder_worm",
        .species = &Species{
            .name = "cinder worm",
            .default_attack = &Weapon{
                .damage = 1,
                .delay = 150,
                .strs = &items.BITING_STRS,
            },
        },
        .tile = '¢',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
        },
        .max_HP = 8,

        .spells = &[_]SpellOptions{
            // Have cooldown period that matches time needed for flames to
            // die out, so that the worm isn't constantly vomiting fire when
            // its surroundings are already in flames
            //
            // TODO: check this in spells.zig
            .{ .MP_cost = 10, .spell = &spells.CAST_FIREBLAST, .power = 4 },
        },
        .max_MP = 10,

        .memory_duration = 5,
        .blood = .Ash,
        .blood_spray = gas.SmokeGas.id,
        .corpse = .None,
        .innate_resists = .{ .rFire = RESIST_IMMUNE, .rElec = 25, .rFume = 100 },
        .stats = .{ .Willpower = 6, .Melee = 80, .Speed = 80, .Vision = 4 },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Fire, .duration = .Prm },
        .{ .status = .Noisy, .duration = .Prm },
    },
};

const WAR_OLG_CLAW_WEAPON = Weapon{
    .damage = 1,
    .strs = &items.CLAW_STRS,
};

pub const WarOlgTemplate = MobTemplate{
    .mob = .{
        .id = "war_olg",
        .species = &Species{
            .name = "war olg",
            .default_attack = &Weapon{ .damage = 1, .strs = &items.BITING_STRS },
            .aux_attacks = &[_]*const Weapon{
                &WAR_OLG_CLAW_WEAPON,
                &WAR_OLG_CLAW_WEAPON,
            },
        },
        .tile = 'ò',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.guardWork,
            .fight_fn = ai.mageFight,
            .is_fearless = true, // don't just run away when you've got a regen spell, dumbass
        },
        .max_HP = 15,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 3, .spell = &spells.CAST_REGEN, .power = 3 },
        },
        .max_MP = 3,

        .memory_duration = 3,
        .stats = .{ .Willpower = 2, .Melee = 90, .Vision = 4 },
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
        .max_HP = 5,
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
                .flags = &[_]AI.Flag{ .AwakesNearAllies, .SocialFighter },
            },

            .base_night_vision = true,

            .spells = &[_]SpellOptions{spell},
            .max_MP = 4,

            .max_HP = 12,
            .memory_duration = 10000,
            .life_type = .Construct,
            .blood = null,
            .corpse = .Wall,
            .immobile = true,
            .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rFire = 25, .rElec = 25, .Armor = 20 },
            .stats = .{ .Willpower = opts.willpower, .Evade = 0, .Vision = 6 },
        },

        .statuses = &[_]StatusDataInfo{.{ .status = .Sleeping, .duration = .Prm }},
    };
}

pub const IronSpireTemplate = createSpireTemplate("iron", '1', .{ .MP_cost = 4, .spell = &spells.BOLT_IRON, .power = 3 }, .{});
pub const TorporSpireTemplate = createSpireTemplate("torpor", '2', .{ .MP_cost = 4, .spell = &spells.CAST_FEEBLE, .duration = 4 }, .{ .willpower = 7 });
pub const LightningSpireTemplate = createSpireTemplate("lightning", '3', .{ .MP_cost = 4, .spell = &spells.BOLT_LIGHTNING, .power = 2 }, .{});
pub const CalciteSpireTemplate = createSpireTemplate("calcite", '4', .{ .MP_cost = 4, .spell = &spells.CAST_CALL_UNDEAD }, .{ .willpower = 8 });
pub const SentrySpireTemplate = createSpireTemplate("sentry", '5', .{ .MP_cost = 4, .spell = &spells.CAST_ALERT_ALLY }, .{});
// }}}

pub const KyaniteStatueTemplate = MobTemplate{
    .ignore_conflicting_tiles = true, // conflicts w/ other statues

    .mob = .{
        .id = "kyanite_statue",
        .species = &Species{ .name = "kyanite statue", .default_attack = &NONE_WEAPON },
        .tile = '☻',
        .ai = AI{
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_curious = false,
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
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .Armor = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 9, .Vision = 20 },
    },
};

pub const NebroStatueTemplate = MobTemplate{
    .ignore_conflicting_tiles = true, // conflicts w/ other statues

    .mob = .{
        .id = "nebro_statue",
        .species = &Species{ .name = "nebro statue", .default_attack = &NONE_WEAPON },
        .tile = '☻',
        .ai = AI{
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_curious = false,
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
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .Armor = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 9, .Vision = 20 },
    },
};

pub const CrystalStatueTemplate = MobTemplate{
    .ignore_conflicting_tiles = true, // conflicts w/ other statues

    .mob = .{
        .id = "crystal_statue",
        .species = &Species{ .name = "crystal statue", .default_attack = &NONE_WEAPON },
        .tile = '☻',
        .ai = AI{
            .profession_description = "gazing",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.statueFight,
            .is_curious = false,
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
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .Armor = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 9, .Vision = 20 },
    },
};

pub const BartenderTemplate = MobTemplate{
    .ignore_conflicting_tiles = true,
    .mob = .{
        .id = "bartender",
        .species = &HumanSpecies,
        .tile = 'a',
        .ai = AI{
            .profession_name = "bartender",
            .profession_description = "serving",
            .work_fn = ai.bartenderWork,
            .fight_fn = ai.shriekerFight,
            .is_combative = true,
            .is_curious = false,
        },

        .no_show_fov = true,
        .max_HP = 10,
        .memory_duration = 28,

        .stats = .{ .Willpower = 10, .Vision = 20, .Evade = 10 },
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
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
        },

        .max_HP = 10,
        .memory_duration = 7,

        .stats = .{ .Willpower = 2, .Evade = 10 },
    },
};

pub const CleanerTemplate = MobTemplate{
    .mob = .{
        .id = "cleaner",
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

        .max_HP = 10,
        .memory_duration = 5,
        .stats = .{ .Willpower = 2, .Evade = 10 },
    },
};

pub const HaulerTemplate = MobTemplate{
    .mob = .{
        .id = "hauler",
        .species = &GoblinSpecies,
        .tile = 'h',
        .ai = AI{
            .profession_name = "hauler",
            .profession_description = "hauling",
            .work_fn = ai.haulerWork,
            .fight_fn = null,
            .is_combative = false,
            .is_curious = false,
            .work_phase = .HaulerScan,
        },

        .max_HP = 10,
        .memory_duration = 8,
        .stats = .{ .Willpower = 2, .Evade = 10, .Speed = 60 },
    },
};

pub const AncientMageTemplate = MobTemplate{
    .mob = .{
        .id = "ancient_mage",
        .species = &HumanSpecies,
        .tile = 'Ã',
        .undead_prefix = "",
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
            .{ .MP_cost = 0, .spell = &spells.CAST_MASS_DISMISSAL, .power = 15 },
            .{ .MP_cost = 8, .spell = &spells.BOLT_CRYSTAL, .power = 4 },
            .{ .MP_cost = 9, .spell = &spells.CAST_SUMMON_ENEMY },
        },
        .max_MP = 30,

        .deaf = false,
        .life_type = .Undead,

        .max_HP = 30,
        .memory_duration = 8,
        .blood = null,
        .corpse = .None,
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rElec = 75 },
        .stats = .{ .Willpower = 10, .Evade = 20, .Speed = 120 },
    },
    .weapon = &items.BoneGreatMaceWeapon,
    .armor = &items.HauberkArmor,
    .cloak = &items.SilCloak,
};

pub const SpectreMageTemplate = MobTemplate{
    .mob = .{
        .id = "spectre_mage",
        .species = &HumanSpecies,
        .tile = 'Ƨ',
        .ai = AI{
            .profession_name = "spectre mage",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .spellcaster_backup_action = .KeepDistance,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 15, .spell = &spells.CAST_CONJ_SPECTRAL_SWORD },
        },
        .max_MP = 15,

        .max_HP = 10,
        .memory_duration = 6,
        .stats = .{ .Willpower = 6, .Vision = 5 },
    },
    .armor = &items.HauberkArmor,
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
        },

        .max_HP = 7,
        .memory_duration = 5,
        .stats = .{ .Willpower = 1, .Melee = 70, .Vision = 5 },
    },
    .weapon = &items.BludgeonWeapon,
    .armor = &items.GambesonArmor,
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
        },

        .max_HP = 10,
        .memory_duration = 4,
        .stats = .{ .Willpower = 2, .Melee = 80, .Evade = 15, .Vision = 5 },
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.CuirassArmor,
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
            .flags = &[_]AI.Flag{.CalledWithUndead},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 25, .spell = &spells.CAST_HASTE_UNDEAD, .duration = 5 },
        },
        .max_MP = 20,

        .max_HP = 7,
        .memory_duration = 6,
        .stats = .{ .Willpower = 4, .Vision = 5, .Melee = 40 },
    },
    .weapon = &items.BoneMaceWeapon,

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
            .flags = &[_]AI.Flag{.CalledWithUndead},
        },

        .max_HP = 10,
        .memory_duration = 5,
        .stats = .{ .Willpower = 6, .Melee = 70, .Evade = 10, .Vision = 5 },
    },
    .weapon = &items.BoneSwordWeapon,
    .armor = &items.HauberkArmor,

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
            .flags = &[_]AI.Flag{.CalledWithUndead},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 10, .spell = &spells.CAST_HEAL_UNDEAD },
            .{ .MP_cost = 20, .spell = &spells.CAST_HASTE_UNDEAD, .duration = 12 },
        },
        .max_MP = 20,

        .max_HP = 10,
        .memory_duration = 6,
        .stats = .{ .Willpower = 8, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.BoneSwordWeapon,
    .armor = &items.HauberkArmor,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "skeletal_blademaster", .weight = 6, .count = minmax(usize, 2, 4) },
            .{ .mob = "skeletal_axemaster", .weight = 4, .count = minmax(usize, 2, 4) },
        },
    },
};

pub const EmberMageTemplate = MobTemplate{
    .mob = .{
        .id = "ember_mage",
        .species = &HumanSpecies,
        .tile = 'Ë',
        .ai = AI{
            .profession_name = "ember mage",
            .profession_description = "watching",
            // Stand still and don't be curious; don't want emberling followers
            // to burn the world down
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .spellcaster_backup_action = .Melee,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 05, .spell = &spells.CAST_CREATE_EMBERLING },
            .{ .MP_cost = 10, .spell = &spells.CAST_FLAMMABLE, .power = 20 },
        },
        .max_MP = 15,

        .max_HP = 6,
        .memory_duration = 5,
        .stats = .{ .Willpower = 4, .Evade = 0, .Vision = 5 },
    },
    .weapon = &items.BludgeonWeapon,
    .cloak = &items.SilCloak,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "emberling", .weight = 1, .count = minmax(usize, 2, 4) },
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
            .is_curious = false,
            .spellcaster_backup_action = .KeepDistance,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 15, .spell = &spells.CAST_CREATE_EMBERLING },
            .{ .MP_cost = 01, .spell = &spells.CAST_FLAMMABLE, .power = 20 },
            .{ .MP_cost = 15, .spell = &spells.CAST_FRY, .power = 7 },
            .{ .MP_cost = 10, .spell = &spells.CAST_HASTE_EMBERLING, .power = 7 },
        },
        .max_MP = 15,

        .max_HP = 8,
        .memory_duration = 7,
        .stats = .{ .Willpower = 6, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.HauberkArmor,
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
            .is_curious = false,
            .spellcaster_backup_action = .Melee,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 6, .spell = &spells.CAST_CREATE_SPARKLING },
            // About five turn's delay until next cast (power<3> - MP_cost<8> = 5)
            .{ .MP_cost = 8, .spell = &spells.BOLT_PARALYSE, .power = 1 },
        },
        .max_MP = 10,

        .max_HP = 6,
        .memory_duration = 5,
        .stats = .{ .Willpower = 4, .Evade = 0, .Vision = 5 },
    },
    .weapon = &items.BludgeonWeapon,
    .cloak = &items.FurCloak,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "sparkling", .weight = 1, .count = minmax(usize, 2, 3) },
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
            .is_curious = false,
            .spellcaster_backup_action = .KeepDistance,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 06, .spell = &spells.CAST_CREATE_SPARKLING },
            .{ .MP_cost = 10, .spell = &spells.BOLT_PARALYSE, .power = 2 },
            .{ .MP_cost = 03, .spell = &spells.CAST_DISCHARGE },
            .{ .MP_cost = 15, .spell = &spells.CAST_HASTE_SPARKLING, .power = 7 },
        },
        .max_MP = 15,

        .max_HP = 8,
        .memory_duration = 7,
        .stats = .{ .Willpower = 6, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.HauberkArmor,
    .cloak = &items.FurCloak,

    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "sparkling", .weight = 1, .count = minmax(usize, 2, 4) },
        },
    },
};

pub const BloatTemplate = MobTemplate{
    .mob = .{
        .id = "bloat",
        .species = &Species{
            .name = "bloat",
            .default_attack = &Weapon{ .damage = 1, .strs = &items.FIST_STRS },
        },
        .tile = 'n',
        .undead_prefix = "",
        .ai = AI{
            .profession_description = "dormant",
            .work_fn = ai.dummyWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .max_HP = 28,
        .memory_duration = 10,

        //.deaf = true,
        .life_type = .Undead,
        .blood = null,
        .blood_spray = gas.Miasma.id,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 6, .Melee = 80, .Speed = 150, .Vision = 5 },
    },

    .statuses = &[_]StatusDataInfo{
        .{ .status = .Sleeping, .duration = .Prm },
        .{ .status = .NightVision, .duration = .Prm },
    },
};

pub const ThrashingSculptorTemplate = MobTemplate{
    .mob = .{
        .id = "thrashing_sculptor",
        .species = &Species{
            .name = "thrashing sculptor",
            .default_attack = &Weapon{ .damage = 0, .knockback = 2, .strs = &items.CLAW_STRS },
        },
        .tile = 'T',
        .undead_prefix = "",
        .ai = AI{
            .profession_description = "dormant",
            .work_fn = ai.watcherWork,
            .fight_fn = ai.mageFight,
            .is_fearless = true,
            .spellcaster_backup_action = .Melee,
            .flags = &[_]AI.Flag{.MovesDiagonally},
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 10, .spell = &spells.CAST_CREATE_BLOAT },
        },
        .max_MP = 10,

        .max_HP = 10,
        .memory_duration = 20,

        .life_type = .Undead,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = 7, .Evade = 20, .Melee = 100, .Speed = 100, .Vision = 5 },
    },

    .statuses = &[_]StatusDataInfo{
        .{ .status = .NightVision, .duration = .Prm },
    },
};

pub const SkeletonTemplate = MobTemplate{
    .mob = .{
        .id = "skeleton",
        .species = &Species{
            .name = "skeleton",
            .default_attack = &Weapon{ .damage = 1, .strs = &items.FIST_STRS },
        },
        .tile = 's',
        .undead_prefix = "",
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
            .flags = &[_]AI.Flag{.CalledWithUndead},
        },

        .max_HP = 5,
        .memory_duration = 5,

        .deaf = true,
        .life_type = .Undead,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rFire = -25 },
        .stats = .{ .Willpower = 6, .Vision = 4 },
    },
};

pub const BoneRatTemplate = MobTemplate{
    .mob = .{
        .id = "bone_rat",
        .species = &Species{
            .name = "bone rat",
            .default_attack = &Weapon{ .damage = 1, .strs = &items.BITING_STRS },
        },
        .tile = 'r',
        .undead_prefix = "",
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .deaf = true,
        .life_type = .Undead,

        .max_HP = 2,
        .memory_duration = 4,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rFire = -25 },
        .stats = .{ .Willpower = 1, .Evade = 10, .Speed = 60, .Vision = 4 },
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
            .default_attack = &Weapon{
                .damage = 1,
                .damage_kind = .Fire,
                .strs = &items.CLAW_STRS,
            },
        },
        .tile = 'ë',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_curious = false,
            .is_fearless = true,
        },
        .life_type = .Construct,

        .blood = null,
        .corpse = .None,

        .max_HP = 3,
        .memory_duration = 3,
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rFire = RESIST_IMMUNE },
        .stats = .{ .Willpower = 1, .Evade = 10, .Speed = 60, .Vision = 4, .Melee = 50 },
    },
    // XXX: Emberlings are never placed alone, this determines number of
    // summoned emberlings from CAST_CREATE_EMBERLING
    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "emberling", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Fire, .duration = .Prm },
        .{ .status = .Noisy, .duration = .Prm },
    },
};

pub const SparklingTemplate = MobTemplate{
    .mob = .{
        .id = "sparkling",
        .species = &Species{
            .name = "sparkling",
            .default_attack = &Weapon{
                .damage = 1,
                .damage_kind = .Electric,
                .strs = &items.SHOCK_STRS,
            },
        },
        .tile = 'p',
        .ai = AI{
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.mageFight,
            .is_curious = false,
            .is_fearless = true,
            .spellcaster_backup_action = .Melee,
        },
        .life_type = .Construct,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 14, .spell = &spells.BOLT_BLINKBOLT, .power = 2 },
        },
        .max_MP = 14,

        .blood = null,
        .corpse = .None,

        .max_HP = 3,
        .memory_duration = 3,
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rElec = RESIST_IMMUNE },
        .stats = .{ .Willpower = 1, .Evade = 10, .Speed = 100, .Vision = 4 },
    },
    // XXX: Sparklings are never placed alone, this determines number of
    // summoned sparklings from CAST_CREATE_SPARKLING
    .squad = &[_][]const MobTemplate.SquadMember{
        &[_]MobTemplate.SquadMember{
            .{ .mob = "sparkling", .weight = 1, .count = minmax(usize, 2, 3) },
        },
    },
};

pub const SkeletalAxemasterTemplate = MobTemplate{
    .mob = .{
        .id = "skeletal_axemaster",
        .species = &HumanSpecies,
        .tile = 'á',
        .undead_prefix = "",
        .ai = AI{
            .profession_name = "skeletal axemaster",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .deaf = true,
        .life_type = .Undead,

        .max_HP = 15,
        .memory_duration = 5,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rFire = -25 },
        .stats = .{ .Willpower = 5, .Speed = 150, .Vision = 5 },
    },
    .weapon = &items.AxeWeapon,
    .armor = &items.CuirassArmor,
};

pub const SkeletalBlademasterTemplate = MobTemplate{
    .mob = .{
        .id = "skeletal_blademaster",
        .species = &HumanSpecies,
        .tile = 'ƀ',
        .undead_prefix = "",
        .ai = AI{
            .profession_name = "skeletal blademaster",
            .profession_description = "watching",
            .work_fn = ai.standStillAndGuardWork,
            .fight_fn = ai.meleeFight,
            .is_fearless = true,
        },

        .deaf = true,
        .life_type = .Undead,

        .max_HP = 12,
        .memory_duration = 6,
        .blood = null,
        .corpse = .None,

        // Will have rElec-25 from Cuirass
        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFume = 100, .rFire = -25 },
        // Melee is 100% but in practice will be 90% due to penalty from rapier
        .stats = .{ .Willpower = 4, .Melee = 100, .Speed = 110, .Vision = 5 },
    },
    .weapon = &items.RapierWeapon,
    .armor = &items.CuirassArmor,
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
        },
        .no_show_fov = false,

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 5, .spell = &spells.CAST_RESURRECT_NORMAL },
            .{ .MP_cost = 2, .spell = &spells.CAST_PAIN, .duration = 5, .power = 1 },
            .{ .MP_cost = 1, .spell = &spells.CAST_FEAR, .duration = 10 },
        },
        .max_MP = 10,

        .max_HP = 15,
        .memory_duration = 10,
        .stats = .{ .Willpower = 8, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.GambesonArmor,
};

const BURNING_BRUTE_CLAW_WEAPON = Weapon{
    .damage = 2,
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
                &Weapon{ .knockback = 3, .damage = 1, .strs = &items.KICK_STRS },
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
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 2, .spell = &spells.CAST_RESURRECT_FIRE, .power = 200, .duration = 10 },
            .{ .MP_cost = 3, .spell = &spells.BOLT_FIREBALL, .power = 2, .duration = 5 },
        },
        .max_MP = 12,

        .max_HP = 20,
        .memory_duration = 6,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = RESIST_IMMUNE, .rElec = -25 },
        .stats = .{ .Willpower = 8, .Evade = 10, .Melee = 80, .Vision = 6 },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Fire, .duration = .Prm },
        .{ .status = .Noisy, .duration = .Prm },
    },
};

pub const SulfurFiendTemplate = MobTemplate{
    .mob = .{
        .id = "sulfur_fiend",
        .species = &Species{ .name = "sulfur fiend" },
        .tile = 'S',
        .ai = AI{
            .profession_description = "sulking",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.mageFight,
            .is_fearless = true,
            .spellcaster_backup_action = .KeepDistance,
        },
        .spells = &[_]SpellOptions{
            .{ .MP_cost = 1, .spell = &spells.CAST_HASTEN_ROT, .power = 150 },
            .{ .MP_cost = 6, .spell = &spells.CAST_CONJ_BALL_LIGHTNING, .power = 12 },
        },
        .max_MP = 10,

        .max_HP = 15,
        .memory_duration = 6,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = 50, .rElec = RESIST_IMMUNE, .rFume = 80 },
        .stats = .{ .Willpower = 10, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.MaceWeapon,
    .armor = &items.HauberkArmor,
    .statuses = &[_]StatusDataInfo{.{ .status = .Noisy, .duration = .Prm }},
};

pub const FrozenFiendTemplate = MobTemplate{
    .mob = .{
        .id = "frozen_fiend",
        .species = &Species{ .name = "frozen fiend" },
        .tile = 'F',
        .ai = AI{
            .profession_description = "patrolling",
            .work_fn = ai.patrolWork,
            .fight_fn = ai.mageFight,
            .is_fearless = true,
            .spellcaster_backup_action = .Melee,
        },

        .spells = &[_]SpellOptions{
            .{ .MP_cost = 2, .spell = &spells.CAST_POLAR_LAYER, .power = 14 },
            .{ .MP_cost = 3, .spell = &spells.CAST_RESURRECT_FROZEN, .power = 21 },
        },
        .max_MP = 15,

        .max_HP = 20,
        .memory_duration = 6,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = 75, .rElec = 75, .rFire = -25 },
        .stats = .{ .Willpower = 8, .Evade = 10, .Vision = 6 },
    },
    .weapon = &items.MorningstarWeapon,
    .armor = &items.HauberkArmor,
};

pub const LivingIceTemplate = MobTemplate{
    .mob = .{
        .id = "living_ice",
        .species = &Species{
            .name = "living ice",
            .default_attack = &Weapon{
                .damage = 3,
                .strs = &[_]DamageStr{
                    items._dmgstr(010, "hit", "hits", ""),
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
        },

        .deg360_vision = true,
        .no_show_fov = true,
        .immobile = true,
        .max_HP = 20,
        .memory_duration = 1,

        .life_type = .Construct,

        .blood = .Water,
        .corpse = .Wall,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = -50, .rElec = RESIST_IMMUNE, .Armor = 50, .rFume = 100 },
        .stats = .{ .Willpower = 5, .Melee = 100, .Vision = 2 },
    },
    // This status should be added by whatever spell created it.
    //.statuses = &[_]StatusDataInfo{.{ .status = .Lifespan, .duration = .{.Tmp=10} }},
};

pub const BallLightningTemplate = MobTemplate{
    .mob = .{
        .id = "ball_lightning",
        .species = &Species{ .name = "ball lightning" },
        .tile = 'י',
        .ai = AI{
            .profession_description = "wandering",
            .work_fn = ai.ballLightningWorkOrFight,
            .fight_fn = ai.ballLightningWorkOrFight,
            .is_curious = false,
            .is_fearless = true,
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

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = 50, .rElec = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = WILL_IMMUNE, .Speed = 30, .Vision = 20 },
    },
    // This status should be added by whatever spell created it.
    .statuses = &[_]StatusDataInfo{
        .{ .status = .ExplosiveElec, .power = 5, .duration = .Prm },
    },
};

pub const SpectralSwordTemplate = MobTemplate{
    .mob = .{
        .id = "spec_sword",
        .species = &Species{
            .name = "spectral sword",
            .default_attack = &Weapon{
                .damage = 1,
                .strs = &[_]DamageStr{items._dmgstr(001, "nick", "nicks", "")},
            },
        },
        .tile = 'ƨ',
        .ai = AI{
            .profession_description = "[this is a bug]",
            .work_fn = ai.suicideWork,
            .fight_fn = ai.meleeFight,
            .is_curious = false,
            .is_fearless = true,
        },

        .deaf = true,
        .deg360_vision = true,
        .no_show_fov = true,
        .max_HP = 1,
        .memory_duration = 5,

        .life_type = .Construct,
        .blood = null,
        .corpse = .None,

        .innate_resists = .{ .rPois = RESIST_IMMUNE, .rFire = RESIST_IMMUNE, .rElec = RESIST_IMMUNE, .rFume = 100 },
        .stats = .{ .Willpower = WILL_IMMUNE, .Melee = 50, .Speed = 60, .Vision = 20 },
    },
    .statuses = &[_]StatusDataInfo{
        .{ .status = .Corona, .power = 10, .duration = .Prm },
        .{ .status = .NightVision, .duration = .Prm },
    },
};

pub const MOBS = [_]MobTemplate{
    ExecutionerTemplate,
    DestroyerTemplate,
    WatcherTemplate,
    ShriekerTemplate,
    GuardTemplate,
    SentinelTemplate,
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
    CinderWormTemplate,
    WarOlgTemplate,
    MellaentTemplate,
    IronSpireTemplate,
    TorporSpireTemplate,
    LightningSpireTemplate,
    CalciteSpireTemplate,
    SentrySpireTemplate,
    KyaniteStatueTemplate,
    NebroStatueTemplate,
    CrystalStatueTemplate,
    AlchemistTemplate,
    BartenderTemplate,
    CleanerTemplate,
    HaulerTemplate,
    AncientMageTemplate,
    SpectreMageTemplate,
    RecruitTemplate,
    WarriorTemplate,
    BoneMageTemplate,
    DeathKnightTemplate,
    DeathMageTemplate,
    EmberMageTemplate,
    BrimstoneMageTemplate,
    SparkMageTemplate,
    LightningMageTemplate,
    BloatTemplate,
    ThrashingSculptorTemplate,
    SkeletonTemplate,
    BoneRatTemplate,
    EmberlingTemplate,
    SparklingTemplate,
    SkeletalAxemasterTemplate,
    SkeletalBlademasterTemplate,
    TorturerNecromancerTemplate,
    BurningBruteTemplate,
    FrozenFiendTemplate,
    SulfurFiendTemplate,
};

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
    allegiance: ?types.Allegiance = null,
};

pub fn placeMob(
    alloc: mem.Allocator,
    template: *const MobTemplate,
    coord: Coord,
    opts: PlaceMobOptions,
) *Mob {
    assert(state.dungeon.at(coord).mob == null);

    var mob = template.mob;
    mob.init(alloc);

    mob.coord = coord;
    mob.allegiance = opts.allegiance orelse mob.allegiance;
    mob.ai.phase = opts.phase;

    if (template.weapon) |w| mob.equipItem(.Weapon, Item{ .Weapon = items.createItem(Weapon, w.*) });
    if (template.backup_weapon) |w| mob.equipItem(.Backup, Item{ .Weapon = items.createItem(Weapon, w.*) });
    if (template.armor) |a| mob.equipItem(.Armor, Item{ .Armor = items.createItem(Armor, a.*) });
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

    state.dungeon.at(coord).mob = mob_ptr;

    return mob_ptr;
}

pub fn placeMobSurrounding(c: Coord, t: *const MobTemplate, opts: PlaceMobOptions) void {
    for (&DIRECTIONS) |d| if (c.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, .{ .right_now = true })) {
            _ = placeMob(state.GPA.allocator(), t, neighbor, opts);
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
