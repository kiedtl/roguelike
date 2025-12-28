const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const sort = std.sort;
const meta = std.meta;
const math = std.math;
const enums = std.enums;

const ai = @import("ai.zig");
const alert = @import("alert.zig");
const colors = @import("colors.zig");
const combat = @import("combat.zig");
const dijkstra = @import("dijkstra.zig");
const err = @import("err.zig");
const explosions = @import("explosions.zig");
const fire = @import("fire.zig");
const font = @import("font.zig");
const gas = @import("gas.zig");
const main = @import("root");
const materials = @import("materials.zig");
const mobs = @import("mobs.zig");
const player = @import("player.zig");
const rng = @import("rng.zig");
const scores = @import("scores.zig");
const spells = @import("spells.zig");
const state = @import("state.zig");
const tsv = @import("tsv.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const AIJob = types.AIJob;
const Container = types.Container;
const Coord = types.Coord;
const Direction = types.Direction;
const Item = types.Item;
const Machine = types.Machine;
const Material = types.Material;
const Mob = types.Mob;
const PropArrayList = types.PropArrayList;
const PropPtrAList = std.ArrayList(*Prop);
const Prop = types.Prop;
const Rect = types.Rect;
const Resistance = types.Resistance;
const Squad = types.Squad;
const Stat = types.Stat;
const StatusDataInfo = types.StatusDataInfo;
const Vial = types.Vial;
const Weapon = types.Weapon;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;

const StackBuffer = @import("buffer.zig").StackBuffer;

// ---

pub var props: PropArrayList = undefined;
pub var prison_item_props: PropPtrAList = undefined;
pub var laboratory_item_props: PropPtrAList = undefined;
pub var laboratory_props: PropPtrAList = undefined;
pub var vault_props: PropPtrAList = undefined;
pub var statue_props: PropPtrAList = undefined;
pub var weapon_props: PropPtrAList = undefined;
pub var bottle_props: PropPtrAList = undefined;
pub var tools_props: PropPtrAList = undefined;
pub var armors_props: PropPtrAList = undefined;

pub const Stair = struct {
    stairtype: Type,
    locked: bool = false,

    pub const Type = union(enum) { Up: usize, Down, Access };

    pub fn newUp(dest: usize) types.SurfaceItem {
        return types.SurfaceItem{ .Stair = @This(){ .stairtype = .{ .Up = dest } } };
    }

    pub fn newDown() types.SurfaceItem {
        return types.SurfaceItem{ .Stair = @This(){ .stairtype = .Down } };
    }
};

pub const Terrain = struct {
    id: []const u8,
    name: []const u8,
    fg: u32,
    fg_dance: ?colors.ColorDance = null,
    bg: u32 = colors.BG,
    bg_dance: ?colors.ColorDance = null,
    tile: u21,
    sprite: ?font.Sprite = null,
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
    effects: []const StatusDataInfo = &[_]StatusDataInfo{},
    flammability: usize = 0,
    fire_retardant: bool = false,
    is_path_penalized: bool = false,
    trample_cloud: ?gas.GasCreationOpts = null,
    trample_into: ?*const Terrain = null,
    luminescence: usize = 0,
    gas: ?gas.GasCreationOpts = null,
    opacity: usize = 0,

    // 2025-03-01: Apparently not used anywhere, dunno what it was for I should
    // check git history at some point.
    repairable: bool = true,

    for_levels: []const []const u8,
    placement: TerrainPlacement,
    weight: usize,

    pub const TerrainPlacement = union(enum) {
        EntireRoom,
        RoomSpotty: usize, // place_num = min(number, room_area * number / 100),
        RoomBlob,
        RoomPortion,
    };
};

pub const CAVERN_TERRAIN_TEMPLATE = Terrain{ .id = "t_caverns_1", .for_levels = &[_][]const u8{"CAV"}, .placement = .RoomBlob, .weight = 3, .flammability = 5, .fg = undefined, .tile = undefined, .name = undefined };

pub var CavernsTerrain1 = CAVERN_TERRAIN_TEMPLATE;
pub var CavernsTerrain2 = CAVERN_TERRAIN_TEMPLATE;
pub var CavernsTerrain3 = CAVERN_TERRAIN_TEMPLATE;
pub var CavernsTerrain4 = CAVERN_TERRAIN_TEMPLATE;

pub const DefaultTerrain = Terrain{
    .id = "t_default",
    .name = "",
    .fg = colors.DOBALENE_BLUE,
    .tile = '·',

    // for_levels and placement have no effect, since this is the default
    // terrain.
    .for_levels = &[_][]const u8{"ANY"},
    .placement = .EntireRoom,

    .weight = 1,
};

pub const SladeTerrain = Terrain{
    .id = "t_slade",
    .name = "slade",
    .fg = 0xb00bb0, // polished slade
    .tile = '·',
    .stats = .{},

    .for_levels = &[_][]const u8{"LAI"},
    .placement = .EntireRoom,
    .weight = 0,
};

// pub const CarpetTerrain = Terrain{
//     .id = "t_carpet",
//     .name = "carpet",
//     .fg = 0xdaa520, // goldenish
//     .tile = '÷',
//     .flammability = 30,

//     .for_levels = &[_][]const u8{"PRI"},
//     .placement = .EntireRoom,
//     .weight = 8,
// };

pub const MetalTerrain = Terrain{
    .id = "t_metal",
    .name = "metal",
    .fg = 0x8094ae, // steel blue
    .tile = '∷',
    .sprite = .S_G_T_Metal,
    .resists = .{ .rElec = -25 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .Conductive, .duration = .{ .Ctx = null } },
    },

    .for_levels = &[_][]const u8{ "WRK", "LAB", "HLD" },
    .placement = .EntireRoom,
    .weight = 6,
};

pub const FireproofMetalTerrain = Terrain{
    .id = "t_metal_fireproof",
    .name = "fireproofed metal",
    .fg = 0xa0849e,
    .tile = '∷',
    .sprite = .S_G_T_Metal,
    .resists = .{ .rElec = -25, .rFire = 50 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .Conductive, .duration = .{ .Ctx = null } },
    },
    .for_levels = &[_][]const u8{}, // Only appears in some prefabs
    .placement = .EntireRoom,
    .weight = 0,
};

pub const CopperTerrain = Terrain{
    .id = "t_copper",
    .name = "copper",
    .fg = 0x998883,
    .tile = ':',
    .resists = .{ .rElec = -25 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .CopperWeapon, .duration = .{ .Ctx = null } },
    },

    .for_levels = &[_][]const u8{ "PRI", "WRK", "LAB", "HLD" },
    .placement = .RoomPortion,
    .weight = 8,
};

pub const WoodTerrain = Terrain{
    .id = "t_wood",
    .name = "wood",
    .fg = 0xdaa520, // wood
    .tile = '·',
    .resists = .{ .rFire = -25, .rElec = 50 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .CopperWeapon, .duration = .{ .Ctx = null } },
    },
    .flammability = 30,

    .for_levels = &[_][]const u8{"PRI"},
    .placement = .EntireRoom,
    .weight = 5,
};

pub const ShallowWaterTerrain = Terrain{
    .id = "t_water_shallow",
    .name = "shallow water",

    .fg = 0x4c4c7c,
    .fg_dance = .{ .each = 0x000415, .all = 10 },
    .bg = 0x34347c, // medium blue
    .bg_dance = .{ .each = 0x050505, .all = 6 },
    .tile = '≈',

    .resists = .{ .rFire = 25, .rElec = -25 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .Conductive, .duration = .{ .Ctx = null } },
    },
    .fire_retardant = true,

    .for_levels = &[_][]const u8{"CAV"},
    .placement = .RoomBlob,
    .weight = 3,
};

pub const WaterTerrain = Terrain{
    .id = "t_water",
    .name = "deep water",

    .fg = 0x454854,
    .fg_dance = .{ .each = 0x000415, .all = 10 }, // Stolen from Brogue lol
    .bg = 0x252a50,
    .bg_dance = .{ .each = 0x050505, .all = 6 }, // Stolen from Brogue. Seeing a pattern?
    .tile = '≈',

    .resists = .{ .rFire = 50, .rElec = -50 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .Conductive, .duration = .{ .Ctx = null } },
        .{ .status = .Noisy, .duration = .{ .Ctx = null } },
        .{ .status = .Water, .duration = .{ .Ctx = null } },
    },
    .fire_retardant = true,
    .is_path_penalized = true,

    .for_levels = &[_][]const u8{},
    .placement = .RoomBlob,
    .weight = 0,
};

pub const GlowingWaterTerrain = Terrain{
    .id = "t_water_glowing",
    .name = "glowing water",

    .fg = 0x108341,
    .fg_dance = .{ .each = 0x001808, .all = 10 },
    .bg = 0x25502a,
    .bg_dance = .{ .each = 0x060907, .all = 6 },
    .tile = '≈',

    .resists = .{ .rFire = 25, .rElec = -50, .rAcid = -50 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .Noisy, .duration = .{ .Ctx = null } },
        .{ .status = .Water, .duration = .{ .Ctx = null } },
    },
    .is_path_penalized = true,
    .luminescence = 60,
    .gas = .{ .id = gas.Fire.id, .amount = 200, .chance = 1200 },

    .for_levels = &[_][]const u8{},
    .placement = .RoomBlob,
    .weight = 0,
};

pub const DeadFungiTerrain = Terrain{
    .id = "t_f_dead",
    .name = "dead fungi",
    .fg = 0xaaaaaa,
    .tile = '"',
    .opacity = 60,
    .resists = .{ .rFire = -25 },
    .flammability = 30,
    .repairable = false,

    .for_levels = &[_][]const u8{ "PRI", "SIN", "CAV", "WRK" },
    .placement = .RoomBlob,
    .weight = 5,
};

pub const TallFungiTerrain = Terrain{
    .id = "t_f_tall",
    .name = "tall fungi",
    .fg = 0x0a8505,
    .tile = '&',
    .opacity = 100,
    .flammability = 20,
    .repairable = false,

    .for_levels = &[_][]const u8{ "PRI", "CAV" },
    .placement = .RoomBlob,
    .weight = 7,
};

pub const PillarTerrain = Terrain{
    .id = "t_pillar",
    .name = "pillar",
    .fg = 0xffffff,
    .tile = '8',
    .stats = .{ .Evade = 25 },
    .opacity = 50,
    .repairable = false,

    .for_levels = &[_][]const u8{ "PRI", "WRK", "LAB", "HLD" },
    .placement = .{ .RoomSpotty = 5 },
    .weight = 8,
};

pub const TERRAIN = [_]*const Terrain{
    &DefaultTerrain,
    &SladeTerrain,
    // &CarpetTerrain,
    &MetalTerrain,
    &FireproofMetalTerrain,
    &CopperTerrain,
    &WoodTerrain,
    &ShallowWaterTerrain,
    &WaterTerrain,
    &DeadFungiTerrain,
    &TallFungiTerrain,
    &PillarTerrain,
};

pub const ToolChest = Container{ .id = "tool_chest", .name = "tool chest", .tile = 'æ', .capacity = 1, .type = .Evocables };
pub const Wardrobe = Container{ .id = "wardrobe", .name = "wardrobe", .tile = 'Æ', .capacity = 1, .type = .Wearables, .item_repeat = 0 };
pub const PotionShelf = Container{ .id = "potion_chest", .name = "potion chest", .tile = 'æ', .capacity = 3, .type = .Drinkables, .item_repeat = 0 };
pub const WeaponRack = Container{ .id = "weapon_rack", .name = "weapon rack", .tile = 'π', .capacity = 1, .type = .Smackables, .item_repeat = 0 };
pub const LabCabinet = Container{ .id = "cabinet", .name = "cabinet", .tile = 'π', .capacity = 5, .type = .Utility, .item_repeat = 70 };
pub const VOreCrate = Container{ .id = "crate", .name = "crate", .tile = '∐', .capacity = 14, .type = .VOres, .item_repeat = 60 };

pub const LOOT_CONTAINERS = [_]*const Container{ &WeaponRack, &PotionShelf, &Wardrobe };
pub const LOOT_CONTAINER_WEIGHTS = [LOOT_CONTAINERS.len]usize{ 1, 8, 4 };
pub const ALL_CONTAINERS = [_]*const Container{ &ToolChest, &Wardrobe, &PotionShelf, &WeaponRack, &LabCabinet, &VOreCrate };

pub const MACHINES = [_]Machine{
    SteamVent,
    ResearchCore,
    TurbinePowerSupply,
    SparklingWorkstation,
    Brazier,
    Lamp,
    NormalDoor,
    LabDoor,
    VaultDoor,
    LockedDoor,
    SladeDoor,
    HeavyLockedDoor,
    IronVaultDoor,
    GoldVaultDoor,
    ParalysisGasTrap,
    DisorientationGasTrap,
    SeizureGasTrap,
    BlindingGasTrap,
    SirenTrap,
    LightPressurePlate,
    Press,
    Auger,
    Mine,
    Candle,
    Shrine,
    Alarm,
    Drain,
    FirstAidStation,
    EtherealBarrier,
    ProtectionSigil,
    SanctuarySigil,
    CombatDummyRepairLever,
    FireTestLever,
    Sparkplug,
    FireGasPump,
    Piston,
    DustlingProducer,
};

pub const SteamVent = Machine{
    .id = "steam_vent",
    .name = "steam vent",

    .powered_tile = '=',
    .unpowered_tile = '=',

    .power_drain = 0,
    .power = 100,

    .powered_walkable = true,
    .unpowered_walkable = true,
    .porous = true,
    .detect_with_heat = true,

    .on_power = struct {
        pub fn f(machine: *Machine) void {
            if (state.ticks % 40 == 0) {
                state.dungeon.atGas(machine.coord)[gas.Steam.id] += 200;
            }
        }
    }.f,
};

pub const ResearchCore = Machine{
    .id = "research_core",
    .name = "research core",

    .powered_tile = '█',
    .unpowered_tile = '▓',

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerResearchCore,
};

pub const TurbinePowerSupply = Machine{
    .id = "turbine_power_supply",
    .name = "turbine controller",

    .powered_tile = '≡',
    .unpowered_tile = '≡',
    .powered_sprite = .S_G_M_Machine,
    .unpowered_sprite = .S_G_M_Machine,

    .power_drain = 0,
    .power = 100, // Start out fully powered

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .on_power = powerTurbinePowerSupply,
};

pub const SparklingWorkstation = Machine{
    .id = "sparkling_workstation",
    .name = "workstation",

    .powered_tile = '¼',
    .unpowered_tile = '¼',

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = struct {
        fn f(m: *Machine) void {
            const alchemist: ?*Mob = for (&DIRECTIONS) |d| {
                if (m.coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.dungeon.at(neighbor).mob) |mob| {
                        if (mem.eql(u8, mob.id, "alchemist")) {
                            break mob;
                        }
                    }
                }
            } else null;

            if (alchemist) |mob| {
                if (mob.hasJob(.WRK_WrkstationBusyWork) == null)
                    mob.newJob(.WRK_WrkstationBusyWork);
            }
        }
    }.f,
};

pub const Brazier = Machine{
    .id = "light_brazier",
    .name = "brazier",

    .powered_tile = '╋',
    .unpowered_tile = '┽',
    .powered_sprite = .S_O_M_PriLight,
    .unpowered_sprite = .S_O_M_PriLight,

    .powered_fg = 0xeee088,
    .unpowered_fg = 0xffffff,

    .powered_bg = 0xb7b7b7,
    .unpowered_bg = 0xaaaaaa,

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 1.0,
    .unpowered_opacity = 1.0,

    // maximum, could be much lower (see mapgen:placeLights)
    .powered_luminescence = 100,
    .unpowered_luminescence = 0,

    .detect_with_elec = true,
    .detect_with_heat = true, // Inefficient incandescent bulbs!

    .flammability = 20,
    .on_power = powerNone,
};

pub const Lamp = Machine{
    .id = "light_lamp",
    .name = "lamp",

    .powered_tile = '•',
    .unpowered_tile = '○',
    .powered_sprite = .S_O_M_LabLight,
    .unpowered_sprite = .S_O_M_LabLight,
    .show_on_hud = true,

    .powered_fg = 0xffdf12,
    .unpowered_fg = 0x88e0ee,

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 1.0,
    .unpowered_opacity = 1.0,

    .detect_with_elec = true,
    .detect_with_heat = false, // Efficient LED bulbs!

    // maximum, could be lower (see mapgen:placeLights)
    .powered_luminescence = 100,
    .unpowered_luminescence = 0,

    .flammability = 20,
    .on_power = powerNone,
};

pub const ParalysisGasTrap = Machine.createGasTrap("paralysing gas", &gas.Paralysis);
pub const DisorientationGasTrap = Machine.createGasTrap("disorienting gas", &gas.Disorient);
pub const SeizureGasTrap = Machine.createGasTrap("seizure gas", &gas.Seizure);
pub const BlindingGasTrap = Machine.createGasTrap("tear gas", &gas.Blinding);

pub const SirenTrap = Machine{
    .id = "trap_siren",
    .name = "siren trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .evoke_confirm = "*Really* trigger the siren trap?",
    .on_power = struct {
        pub fn f(machine: *Machine) void {
            if (machine.last_interaction) |mob| {
                if (mob.faction == .Necromancer) return;
                if (state.player.cansee(machine.coord))
                    state.message(.Info, "{c} triggers the siren trap!", .{mob});
                state.dungeon.at(machine.coord).surface = null;
                alert.queueThreatResponse(.{ .Assault = .{ .waves = 3, .target = mob } });
                state.message(.Info, "You hear an ominous alarm blaring.", .{});
                machine.disabled = true;
                state.dungeon.at(machine.coord).surface = null;
            }
        }
    }.f,
};

pub const LightPressurePlate = Machine{
    .id = "trap_light_plate",
    .name = "lamp pressure plate",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .powered_fg = colors.GOLD,
    .unpowered_fg = null,
    .power_drain = 16, // Calibrated to drain in 6.5ish turns, i.e. interval of placement
    .detect_with_elec = true,
    .detect_with_heat = false, // Efficient LED bulbs!
    .powered_luminescence = 60,
    .unpowered_luminescence = 0,
    .show_on_hud = true,
    .on_power = struct {
        pub fn f(machine: *Machine) void {
            for (&DIRECTIONS) |d| if (machine.coord.move(d, state.mapgeometry)) |neighbor| {
                if (state.dungeon.machineAt(neighbor)) |mach| {
                    if (mem.eql(u8, mach.id, machine.id) and
                        mach.power == 0 and machine.power == 100)
                    {
                        mach.power = machine.power;
                    }
                }
            };
        }
    }.f,
};

pub fn createTheaterMachine(id: []const u8, name: []const u8, tile: u21, utile: u21, fg: u32, ufg: u32, bg: ?u32, ubg: ?u32, pdrain: usize, opacity: f32, uopacity: f32, flame: usize, porous: bool) Machine {
    return Machine{
        .id = id,
        .name = name,

        .powered_tile = tile,
        .unpowered_tile = utile,
        .powered_fg = fg,
        .unpowered_fg = ufg,
        .powered_bg = bg,
        .unpowered_bg = ubg,

        .power_drain = pdrain,
        .power = 0,
        .powered_walkable = false,
        .unpowered_walkable = false,
        .powered_opacity = opacity,
        .unpowered_opacity = uopacity,
        .flammability = flame,
        .porous = porous,
        .on_power = powerNone,
    };
}

pub const Press = createTheaterMachine("press", "mechanical press", 'Θ', 'Θ', 0xaaaaaa, colors.COPPER_RED, null, null, 50, 0, 1, 5, true);
pub const Auger = createTheaterMachine("auger", "mechanical auger", 'φ', 'φ', 0xaaaaaa, colors.AQUAMARINE, null, null, 50, 0, 1, 3, true);

pub const NormalDoor = Machine{
    .id = "door_normal",
    .name = "door",

    .powered_tile = '\'',
    .unpowered_tile = '+',
    .powered_fg = 0xffaaaa,
    .unpowered_fg = 0xffaaaa,
    .powered_bg = 0x7a2914,
    .unpowered_bg = 0x7a2914,

    .powered_sprite = .S_G_M_DoorOpen,
    .unpowered_sprite = .S_G_M_DoorShut,
    .powered_sfg = 0xba7964,
    .unpowered_sfg = 0xba7964,
    .powered_sbg = colors.BG,
    .unpowered_sbg = colors.BG,

    .power_drain = 49,
    .powered_walkable = true,
    .unpowered_walkable = true,
    .powered_opacity = 0.2,
    .unpowered_opacity = 1.0,
    .flammability = 30, // wooden door is flammable
    .porous = true,
    .on_power = powerNone,
};

pub const LabDoor = Machine{
    .id = "door_lab",
    .name = "door",

    .powered_tile = '+',
    .unpowered_tile = 'x',
    .powered_fg = 0xffdf10,
    .powered_sprite = .S_O_M_LabDoorOpen,

    // Not used since door is always powered, but defined for fabedit's benefit
    .unpowered_fg = 0xffdf10,
    .unpowered_sprite = .S_O_M_LabDoorShut,

    .power_drain = 0,
    .power = 100,
    .powered_walkable = false,
    .unpowered_walkable = true,
    .powered_opacity = 1.0,
    .unpowered_opacity = 0.0,
    .flammability = 0, // metal door not flammable
    .fireproof = true,
    .porous = true,
    .detect_with_elec = true,
    .on_power = powerLabDoor,
};

pub const VaultDoor = Machine{ // TODO: rename to QuartersDoor
    .id = "door_qrt",
    .name = "iron door",

    .powered_tile = '░',
    .unpowered_tile = '+',
    .powered_fg = 0xaaaaaa,
    .unpowered_bg = 0xffffff,
    .unpowered_fg = colors.BG,

    .powered_sprite = .S_O_M_QrtDoorOpen,
    .unpowered_sprite = .S_O_M_QrtDoorShut,
    .powered_sfg = 0xffffff,
    .powered_sbg = colors.BG,
    .unpowered_sfg = 0xffffff,
    .unpowered_sbg = colors.BG,

    .power_drain = 49,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .powered_opacity = 0.0,
    .unpowered_opacity = 1.0,
    .flammability = 0, // metal door, not flammable
    .fireproof = true,
    .porous = true,
    .on_power = powerNone,
};

pub const LockedDoor = Machine{
    .id = "door_locked",
    .name = "locked door",

    .powered_tile = '\'',
    .unpowered_tile = '+',
    .powered_fg = 0x5588ff,
    .unpowered_fg = 0x5588ff,
    .powered_bg = 0x14297a,
    .unpowered_bg = 0x14297a,

    .powered_sprite = .S_G_M_DoorOpen,
    .unpowered_sprite = .S_G_M_DoorShut,
    .powered_sfg = 0x6479ba,
    .unpowered_sfg = 0x6479ba,
    .powered_sbg = colors.BG,
    .unpowered_sbg = colors.BG,

    .power_drain = 90,
    .restricted_to = .Necromancer,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .flammability = 30, // also wooden door
    .porous = true,
    .on_power = powerNone,
    .pathfinding_penalty = 5,
    .evoke_confirm = "Break down the locked door?",
    .player_interact = .{
        .name = "break down",
        .needs_power = false,
        .success_msg = "You break down the door.",
        .no_effect_msg = "(This is a bug.)",
        .max_use = 1,
        .func = struct {
            fn f(machine: *Machine, by: *Mob) bool {
                assert(by == state.player);
                machine.disabled = true;
                state.player.makeNoise(.Crash, .Loud);
                state.dungeon.at(machine.coord).surface = null;
                return true;
            }
        }.f,
    },
};

pub const SladeDoor = Machine{
    .id = "door_slade",
    .name = "slade door",

    .powered_tile = '\'',
    .unpowered_tile = '+',
    .powered_fg = 0xaaaaff,
    .unpowered_fg = 0xaaaaff,
    .powered_bg = 0x29147a,
    .unpowered_bg = 0x29147a,

    .powered_sprite = .S_G_M_DoorOpen,
    .unpowered_sprite = .S_G_M_DoorShut,
    .powered_sfg = 0x775599,
    .unpowered_sfg = 0x775599,
    .powered_sbg = colors.BG,
    .unpowered_sbg = colors.BG,

    .power_drain = 100,
    .restricted_to = .Night,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .powered_opacity = 0.0,
    .unpowered_opacity = 0.0,
    .porous = false,

    .on_power = struct {
        fn f(m: *Machine) void {
            if (m.last_interaction) |mob| {
                if (mob.multitile != null) return;
                for (&DIRECTIONS) |d| if (m.coord.move(d, state.mapgeometry)) |neighbor| {
                    // A bit hackish
                    if (neighbor.distance(mob.coord) == 2 and state.is_walkable(neighbor, .{ .mob = mob })) {
                        _ = mob.teleportTo(neighbor, null, true, true);
                        return;
                    }
                };

                // const orig = mob.coord;
                // if (state.player.cansee(orig)) {
                //     state.message(.Info, "{c} phases through the door.", .{});
                // }
                // if (state.player.cansee(dest)) {
                //     state.message(.Info, "{c} phases through the door.", .{});
                // }
            }
        }
    }.f,

    .player_interact = .{
        .name = "[this is a bug]",
        .needs_power = false,
        .success_msg = null,
        .no_effect_msg = null,
        .max_use = 0,
        .func = struct {
            fn f(machine: *Machine, by: *Mob) bool {
                assert(by == state.player);

                if (!player.hasAlignedNC()) {
                    if (!ui.drawYesNoPrompt("Trespass on the Lair?", .{}))
                        return false;
                    machine.disabled = true;
                    state.player.makeNoise(.Crash, .Loud);
                    state.dungeon.at(machine.coord).surface = null;
                    scores.recordUsize(.RaidedLairs, 1);
                    if (state.player.hasStatus(.Sceptre)) {
                        state.message(.Info, "You shatter the slade door with the Sceptre. ($b-8 rep$.)", .{});
                        player.repPtr().* -= 8;
                    } else {
                        state.message(.Info, "You break down the slade door. ($b-2 rep$.)", .{});
                        player.repPtr().* -= 2;
                    }
                } else {
                    assert(machine.addPower(by));
                }

                return true;
            }
        }.f,
    },
};

pub const HeavyLockedDoor = Machine{
    .id = "door_locked_heavy",
    .name = "locked steel door",

    .powered_tile = '\'',
    .unpowered_tile = '+',
    .powered_fg = 0xaaffaa,
    .unpowered_fg = 0xaaffaa,
    .powered_bg = 0x297a14,
    .unpowered_bg = 0x297a14,

    .powered_sprite = .S_G_M_DoorOpen,
    .unpowered_sprite = .S_G_M_DoorShut,
    .powered_sfg = 0x64ba79,
    .unpowered_sfg = 0x64ba79,
    .powered_sbg = colors.BG,
    .unpowered_sbg = colors.BG,

    .power_drain = 90,
    .restricted_to = .Necromancer,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .powered_opacity = 0,
    .unpowered_opacity = 1.0,
    .flammability = 0, // not a wooden door at all
    .fireproof = true, // CAV_fried_dustling relies on this
    .porous = false, // CAV_fried_dustling relies on this.
    .on_power = powerNone,
    .pathfinding_penalty = 5,
};

fn createVaultDoor(comptime id_suffix: []const u8, comptime name_prefix: []const u8, color: u32, alarm_chance: usize) Machine {
    return Machine{
        .id = "door_vault_" ++ id_suffix,
        .name = name_prefix ++ " door",

        .powered_tile = ' ',
        .unpowered_tile = '+',
        .powered_fg = colors.percentageOf(color, 130),
        .unpowered_fg = colors.percentageOf(color, 130),
        .powered_bg = colors.percentageOf(color, 40),
        .unpowered_bg = colors.percentageOf(color, 40),

        .powered_sprite = .S_O_M_QrtDoorOpen,
        .unpowered_sprite = .S_O_M_QrtDoorShut,
        .powered_sfg = colors.percentageOf(color, 150),
        .unpowered_sfg = colors.percentageOf(color, 150),
        .powered_sbg = colors.BG,
        .unpowered_sbg = colors.BG,

        .power_drain = 0,
        .restricted_to = .Player,
        .powered_walkable = true,
        .unpowered_walkable = false,
        .powered_opacity = 0,
        .unpowered_opacity = 1.0,

        // Prevent player from tossing coagulation at closed door to empty
        // everything inside with no risk
        //
        .porous = false,

        .evoke_confirm = "Really open a treasure vault door?",
        .on_power = struct {
            pub fn f(machine: *Machine) void {
                machine.disabled = true;
                state.dungeon.at(machine.coord).surface = null;

                if (rng.percent(alarm_chance)) {
                    state.message(.Important, "The alarm goes off!!", .{});
                    state.markMessageNoisy();
                    state.player.makeNoise(.Alarm, .Loudest);
                }
            }
        }.f,
    };
}

pub const IronVaultDoor = createVaultDoor("iron", "iron", colors.COPPER_RED, 30);
pub const GoldVaultDoor = createVaultDoor("gold", "golden", colors.GOLD, 60);
pub const MarbleVaultDoor = createVaultDoor("marble", "marble", colors.OFF_WHITE, 90);
pub const TavernVaultDoor = createVaultDoor("tavern", "tavern", 0x77440f, 100);

pub const Mine = Machine{
    .name = "mine",
    .powered_fg = 0xff34d7,
    .unpowered_fg = 0xff3434,
    .powered_tile = '^',
    .unpowered_tile = '^',
    .power_drain = 0, // Stay powered on once activated
    .on_power = powerMine,
    .flammability = 100,
    .pathfinding_penalty = 10,
};

pub const Candle = Machine{
    .id = "candle",
    .name = "candle",
    .announce = true,
    .powered_tile = 'C',
    .unpowered_tile = 'C',
    .powered_fg = 0,
    .unpowered_fg = 0,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .powered_luminescence = 100, // Just for theme
    .unpowered_luminescence = 0, // ...
    .bg = 0xffe766,
    .power_drain = 0,
    .power = 100,
    .on_power = powerNone,
    .player_interact = .{
        .name = "extinguish",
        .success_msg = "You feel the Power ruling this place weaken.",
        .no_effect_msg = null,
        .expended_msg = null,
        .max_use = 1,
        .func = struct {
            fn f(self: *Machine, by: *Mob) bool {
                state.destroyed_candles += 1;
                self.bg = colors.percentageOf(self.bg.?, 50);
                self.unpowered_fg = self.bg;
                self.power = 0;

                var gen = state.mapRect(by.coord.z).iter();
                while (gen.next()) |coord| if (state.player.cansee(coord)) {
                    if (utils.getHostileAt(state.player, coord)) |hostile| {
                        if (mem.startsWith(u8, hostile.id, "hulk_")) {
                            hostile.addStatus(.Paralysis, 0, .Prm);
                        }
                    } else |_| {}
                };

                //ui.Animation.apply(.{ .Particle = .{ .name = "beams-candle-extinguish", .coord = self.coord, .target = .{ .Z = 0 } } });
                ui.Animation.apply(.{ .Particle = .{ .name = "chargeover-doublegold-candles", .coord = self.coord, .target = .{ .Z = 0 } } });
                state.message(.Info, "You extinguish the candle.", .{});
                scores.recordUsize(.CandlesDestroyed, 1);

                return true;
            }
        }.f,
    },
};

pub const Shrine = Machine{
    .id = "shrine",
    .name = "shrine",
    .announce = true,
    .powered_tile = 'S',
    .unpowered_tile = 'S',
    .powered_fg = 0,
    .unpowered_fg = 0,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .powered_luminescence = 100, // Just for theme
    .unpowered_luminescence = 0, // ...
    .bg = 0xffe766,
    .power_drain = 0,
    .power = 100,
    .on_power = powerNone,
    .on_place = struct {
        pub fn f(machine: *Machine) void {
            //assert(state.shrine_locations[machine.coord.z] == null);
            state.shrine_locations[machine.coord.z] = machine.coord;
        }
    }.f,
    .on_delete = struct {
        pub fn f(machine: *Machine) void {
            if (state.shrine_locations[machine.coord.z]) |global_shrine_loc|
                if (machine.coord.eq(global_shrine_loc)) {
                    state.shrine_locations[machine.coord.z] = null;
                };
        }
    }.f,
    .player_interact = .{
        .name = "drain",
        .success_msg = "You drained the shrine's power.",
        .no_effect_msg = "It seems the shrine's power was hidden. Perhaps in response to a threat?",
        .expended_msg = null,
        .max_use = 1,
        .func = struct {
            fn f(self: *Machine, by: *Mob) bool {
                assert(by == state.player);

                // FIXME: we should do this when shrines go into lockdown as well
                self.bg = colors.percentageOf(self.bg.?, 50);
                self.unpowered_fg = self.bg;
                self.power = 0;

                if (state.shrines_in_lockdown[state.player.coord.z]) {
                    return false;
                } else if (state.player.resistance(.rHoly) > 0 and rng.percent(70)) {
                    state.message(.Drain, "The shrine explodes!", .{});
                    explosions.kaboom(self.coord, .{ .strength = 500, .spare_player = true });
                    return true;
                }

                state.player.max_MP += if (state.player.hasStatus(.Absorbing)) @as(usize, 5) else 2;
                const total = rng.range(usize, state.player.max_MP / 2, state.player.max_MP * 15 / 10);
                const pot: usize = @intCast(state.player.stat(.Potential));
                const amount = player.calculateDrainableMana(total);
                state.player.MP = @min(state.player.max_MP, state.player.MP + amount);

                ui.Animation.apply(.{ .Particle = .{ .name = "explosion-bluegold", .coord = self.coord, .target = .{ .Z = 0 } } });
                state.message(.Drain, "You absorbed $o{}$. / $g{}$. mana ($o{}% potential$.).", .{ amount, total, pot });
                scores.recordUsize(.ShrinesDrained, 1);

                return true;
            }
        }.f,
    },
};

pub const Alarm = Machine{
    .id = "alarm",
    .name = "alarm lever",
    .show_on_hud = true,
    .powered_tile = 'A',
    .unpowered_tile = 'A',
    .powered_fg = 0,
    .unpowered_fg = 0,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .powered_bg = 0xff5c07,
    .unpowered_bg = 0xff9144,
    .power_drain = 100,
    .power = 0,
    .on_place = struct {
        pub fn f(machine: *Machine) void {
            state.alarm_locations[machine.coord.z].append(machine.coord) catch err.wat();
        }
    }.f,
    .on_power = struct {
        pub fn f(machine: *Machine) void {
            const mob = machine.last_interaction orelse return;
            if (mob == state.player) {
                state.message(.Info, "You pull the alarm, but nothing happens.", .{});
                return;
            }

            if (state.player.canSeeMob(mob) and state.player.cansee(machine.coord)) {
                state.message(.Info, "{c} pulls the alarm!", .{mob});
            } else {
                state.message(.Info, "You hear an ominous alarm blaring.", .{});
            }

            const target = if (mob.hasJob(.ALM_PullAlarm)) |j| j.ctx.getOrNone(*Mob, AIJob.CTX_ALARM_TARGET) else null;

            alert.reportThreat(mob, if (target) |t| .{ .Specific = t } else .Unknown, .Alarm);

            // Find the closest construct ally, and wake some of the rest
            var maybe_ally: ?*Mob = null;
            var y: usize = 0;
            while (y < HEIGHT) : (y += 1) {
                var x: usize = 0;
                while (x < WIDTH) : (x += 1) {
                    const coord = Coord.new2(machine.coord.z, x, y);
                    if (state.dungeon.at(coord).mob) |candidate| {
                        if (candidate.faction == .Necromancer and
                            candidate.life_type == .Construct and
                            !candidate.hasStatus(.Insane) and
                            candidate.ai.phase != .Hunt)
                        {
                            if (maybe_ally) |previous_choice| {
                                if (previous_choice.distance2(machine.coord) > candidate.distance2(machine.coord))
                                    maybe_ally = candidate;
                            } else {
                                maybe_ally = candidate;
                            }

                            if (candidate.hasStatus(.Sleeping) and rng.onein(4)) {
                                candidate.cancelStatus(.Sleeping);
                            }
                        }
                    }
                }
            }

            const ally = maybe_ally orelse return;

            if (ally.ai.phase == .Work) {
                ally.sustiles.append(.{ .coord = machine.coord, .unforgettable = true }) catch err.wat();
            } else if (ally.ai.phase == .Investigate) {
                if (target) |t|
                    ai.updateEnemyKnowledge(ally, t, null);
            } else unreachable;

            if (ally.ai.work_area.items.len > 0) {
                // XXX: laziness: use mob.coord instead of finding an adjacent
                // tile (mob will be next to machine, hopefully)
                ally.ai.work_area.items[0] = mob.coord;
            }
        }
    }.f,
};

pub const Drain = Machine{
    .id = "drain",
    .name = "drain",
    .announce = true,
    .powered_tile = '∩',
    .unpowered_tile = '∩',
    .powered_fg = 0x888888,
    .unpowered_fg = 0x888888,
    .powered_walkable = true,
    .unpowered_walkable = true,
    .on_power = powerNone,
    .player_interact = .{
        .name = "crawl",
        .success_msg = "You crawl into the drain and emerge from another!",
        .no_effect_msg = "You crawl into the drain, but it's a dead end!",
        .expended_msg = null,
        .needs_power = false,
        .max_use = 1,
        .func = interact1Drain,
    },
};

pub const FirstAidStation = Machine{
    .id = "first_aid_station",
    .name = "first aid station",
    .announce = false,
    .powered_tile = 'F',
    .unpowered_tile = 'F',
    .powered_fg = 0x001000,
    .unpowered_fg = 0x001000,
    .bg = 0x117011,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .on_power = powerNone,
    .player_interact = .{
        .name = "quaff",
        .success_msg = null,
        .no_effect_msg = "The first aid station is empty.",
        .needs_power = false,
        .max_use = 1,
        .func = interact1FirstAidStation,
    },
};

pub const EtherealBarrier = Machine{
    .id = "sigil_exclusion",
    .name = "sigil of exclusion",
    .powered_tile = '8',
    .unpowered_tile = ' ',
    .powered_fg = colors.AQUAMARINE,
    .power = 100, // Always powered
    .power_drain = 0,
    .powered_walkable = false,

    // Not applicable, always powered.
    .unpowered_walkable = true,
    .unpowered_fg = colors.GOLD,

    // This could be cleaned up by just having an on_unpower callback lol
    // Totally ridiculous
    .on_power = struct {
        fn f(machine: *Machine) void {
            // Reset
            machine.powered_walkable = false;
            machine.powered_fg = colors.AQUAMARINE;

            const owner = machine.ctx.get(*Mob, Machine.CTX_ETH_BARRIER_OWNER, state.player);
            const age = machine.ctx.getPtr(usize, Machine.CTX_ETH_BARRIER_AGE, 0);
            const max_age = owner.stat(.Willpower) * 2;
            if (age.* >= max_age) {
                if (state.player.cansee(machine.coord))
                    state.message(.Info, "The sigil of exclusion vanishes.", .{});
                machine.disabled = true;
                state.dungeon.atGas(machine.coord)[gas.SmokeGas.id] += gas.MIN_GAS_SPREAD - 1;
                state.dungeon.at(machine.coord).surface = null;
                return;
            }
            age.* += 1;

            if (machine.last_interaction) |mob| {
                if (owner != mob and !spells.willSucceedAgainstMob(owner, mob)) {
                    ui.Animation.blinkMob(&.{mob}, '%', colors.AQUAMARINE, .{});
                } else {
                    // Whoops, they got through lol
                    if (state.player.cansee(machine.coord))
                        state.message(.Info, "The sigil of exclusion fails.", .{});
                    machine.last_interaction = null;
                    machine.powered_walkable = true;
                    machine.powered_fg = colors.PALE_VIOLET_RED;
                }
            }
        }
    }.f,
};

pub const ProtectionSigil = Machine{
    .id = "sigil_protection",
    .name = "sigil of protection",
    .powered_tile = ':',
    .unpowered_tile = ':',
    .powered_fg = colors.AQUAMARINE,
    .unpowered_fg = colors.AQUAMARINE,
    .power_drain = 100,
    .powered_walkable = true,
    .unpowered_walkable = true,

    .on_power = struct {
        fn f(machine: *Machine) void {
            if (machine.last_interaction) |mob| {
                if (!mob.hasStatus(.Protected)) {
                    const duration: usize = @intCast(mob.stat(.Willpower) * 2);
                    mob.addStatus(.Protected, 0, .{ .Tmp = duration });
                    ui.Animation.apply(.{ .PopChar = .{ .coord = mob.coord, .char = ':', .delay = 90 } });
                    machine.disabled = true;
                    state.dungeon.at(machine.coord).surface = null;
                }
            }
        }
    }.f,
};

pub const SanctuarySigil = Machine{
    .id = "sigil_sanctuary",
    .name = "sigil of sanctuary",
    .powered_tile = ':',
    .unpowered_tile = ':',
    .powered_fg = 0xdf7239,
    .powered_walkable = true,

    // Always powered
    .power = 100,
    .power_drain = 0,
    .unpowered_walkable = true,
    .unpowered_fg = colors.AQUAMARINE,

    .on_power = struct {
        fn f(machine: *Machine) void {
            const CTX_ANGEL = "ctx_angel";

            const maybe_angel = if (machine.ctx.getOrNone(*Mob, CTX_ANGEL)) |angel|
                if (!angel.is_dead) angel else null
            else
                null;

            if (machine.last_interaction) |mob| {
                if (mob.hasStatus(.Doomed))
                    return;

                const rep = state.REP_TABLE[@intFromEnum(types.Faction.Holy)][@intFromEnum(mob.faction)];
                if (rep >= 0 and mob.resistance(.rHoly) >= 0)
                    return;

                if (rng.onein(5)) {
                    mob.addStatus(.Doomed, 0, .Prm);
                    state.dungeon.deleteSurface(machine.coord);
                } else {
                    mob.applyStatus(.{
                        .status = .Doomed,
                        .power = 0,
                        .duration = .{ .Tmp = 2 },
                        // Hack because Ctx statuses can't be applied for
                        // machines, only terrain
                        .add_duration = false,
                    }, .{});
                }

                if (maybe_angel) |angel| {
                    ai.updateEnemyKnowledge(angel, mob, null);
                    ai.updateEnemyKnowledge(mob, angel, null);
                } else {
                    const spot = state.nextSpotForMob(state.player.coord, null) orelse return;
                    const angel_template = rng.chooseUnweighted(*const mobs.MobTemplate, &mobs.ANGELS);
                    const angel = mobs.placeMob(state.alloc, angel_template, spot, .{ .job = .ATK_FightOnlyDoomed });
                    angel.newestJob().?.ctx.set(void, AIJob.CTX_OVERRIDE_FIGHT, {});

                    machine.ctx.set(*Mob, CTX_ANGEL, angel);
                }
            }
        }
    }.f,
};

pub const CombatDummyRepairLever = Machine{
    .id = "combat_dummy_repair_lever",
    .name = "combat dummy repair lever",
    .powered_tile = '/',
    .unpowered_tile = '\\',
    .powered_fg = colors.LIGHT_CONCRETE,
    .unpowered_fg = colors.CONCRETE,
    .power_drain = 100,
    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = struct {
        fn f(machine: *Machine) void {
            const dummy = utils.getSpecificMobInRoom(machine.coord, "combat_dummy") orelse {
                // ??? Where did it go? Player killed it maybe? But if that's the case,
                // engineer shouldn't be pulling the lever. (Maybe player did?)
                return;
            };
            if (state.player.canSeeMob(dummy))
                state.message(.Info, "The combat dummy suddenly re-inflates.", .{});
            dummy.takeHealing(dummy.max_HP);
            dummy.addStatus(.Sleeping, 0, .Prm);
        }
    }.f,
};

pub const FireTestLever = Machine{
    .id = "fire_test_lever",
    .name = "fireproof-test lever",
    .powered_tile = '/',
    .unpowered_tile = '\\',
    .powered_fg = colors.LIGHT_CONCRETE,
    .unpowered_fg = colors.CONCRETE,
    .power_drain = 100,
    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = struct {
        fn f(machine: *Machine) void {
            const CTX_PUMP = "ctx_pump";
            const CTX_PLUG = "ctx_plug";

            const pump = machine.ctx.get(*Machine, CTX_PUMP, utils.getSpecificMachineInRoom(machine.coord, "pump_fire_gas") orelse return);
            const plug = machine.ctx.get(*Machine, CTX_PLUG, utils.getSpecificMachineInRoom(machine.coord, "sparkplug") orelse return);

            pump.power = 100;
            plug.power = 100;
        }
    }.f,
};

pub const Sparkplug = Machine{
    .id = "sparkplug",
    .name = "sparkplug",
    .powered_tile = '#',
    .unpowered_tile = '#',
    .powered_fg = colors.PALE_VIOLET_RED,
    .unpowered_fg = colors.LIGHT_CONCRETE,
    .power_drain = 20, // Five turns of power
    .powered_walkable = false,
    .unpowered_walkable = false,
    .fireproof = true,

    .on_power = struct {
        fn f(machine: *Machine) void {
            for (&CARDINAL_DIRECTIONS) |d| if (machine.coord.move(d, state.mapgeometry)) |neighbor| {
                // Simplified is_walkable checks. We want to make sure surface item
                // is null, and we don't care if there's a mob in the tile.
                if (state.dungeon.at(neighbor).type == .Floor and
                    state.dungeon.at(neighbor).surface == null and
                    rng.onein(3))
                {
                    fire.setTileOnFire(neighbor, 3);
                    break;
                }
            };
        }
    }.f,
};

pub const FireGasPump = Machine{
    .id = "pump_fire_gas",
    .name = "flammable gas pump",
    .powered_tile = 'X',
    .unpowered_tile = 'I',
    .powered_fg = colors.PALE_VIOLET_RED,
    .unpowered_fg = colors.LIGHT_CONCRETE,
    .power_drain = 34, // Three turns of power
    .powered_walkable = false,
    .unpowered_walkable = false,
    .fireproof = true,

    .on_power = struct {
        fn f(machine: *Machine) void {
            state.dungeon.atGas(machine.coord)[gas.Fire.id] = 100;
        }
    }.f,
};

// Mob pushy thing
// Only knocks mobs around, not props or items!
pub const Piston = Machine{
    .id = "piston",
    .name = "piston",
    .powered_tile = '○',
    .unpowered_tile = '◙',
    .powered_fg = colors.CONCRETE,
    .unpowered_fg = colors.LIGHT_CONCRETE,
    .power_drain = 100,
    .powered_walkable = false,
    .unpowered_walkable = true,

    .on_power = struct {
        fn f(machine: *Machine) void {
            err.ensure(machine.areas.len == 1, "Piston has no associated areas", .{}) catch return;
            const mob = state.dungeon.at(machine.coord).mob orelse return;
            const target = machine.areas.constSlice()[0];
            const direc = machine.coord.closestDirectionTo(target, state.mapgeometry);
            const dist = machine.coord.distance(target);
            combat.throwMob(null, mob, direc, dist);
        }
    }.f,
};

pub const DustlingProducer = Machine{
    .id = "dustling_producer",
    .name = "dustling workshop",
    .powered_tile = '○',
    .unpowered_tile = '◙',
    .powered_fg = colors.CONCRETE,
    .unpowered_fg = colors.LIGHT_CONCRETE,
    .power_drain = 50,
    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = struct {
        fn f(machine: *Machine) void {
            err.ensure(machine.areas.len == 1, "Dustling machine w/ no areas!", .{}) catch return;
            const area = machine.areas.constSlice()[0];
            const leader = machine.ctx.getOrNone(*Mob, "ctx_leader_for_dustling");
            if (state.dungeon.at(area).mob == null and leader != null) {
                const dustling = mobs.placeMob(state.alloc, &mobs.DustlingTemplate, area, .{ .no_squads = true });
                dustling.addStatus(.Paralysis, 0, .{ .Tmp = 3 });
                leader.?.addUnderling(dustling);

                if (state.player.canSeeMob(dustling) or state.player.cansee(machine.coord))
                    state.message(.Info, "{c} emerges from the machinery.", .{dustling});

                machine.ctx.unset("ctx_leader_for_dustling");
            }
        }
    }.f,
};

fn powerNone(_: *Machine) void {}

fn powerResearchCore(machine: *Machine) void {
    // Only function on every 32nd turn, to give the impression that it takes
    // a while to process vials
    if ((state.ticks % 32) != 0 or rng.onein(3)) return;

    for (&DIRECTIONS) |direction| if (machine.coord.move(direction, state.mapgeometry)) |neighbor| {
        for (state.dungeon.itemsAt(neighbor).constSlice(), 0..) |item, i| switch (item) {
            .Vial => {
                _ = state.dungeon.itemsAt(neighbor).orderedRemove(i) catch unreachable;
                return;
            },
            else => {},
        };
    };
}

fn powerElevatorMotor(machine: *Machine) void {
    assert(machine.areas.len > 0);

    // Only function on every 32th turn or so, to give the impression that it takes
    // a while to bring up more ores
    if ((state.ticks % 32) != 0 or rng.onein(3)) return;

    for (machine.areas.constSlice()) |coord| {
        if (!state.dungeon.itemsAt(coord).isFull()) {
            var material: ?*const Material = null;

            material = (rng.choose(Vial.OreAndVial, &Vial.VIAL_ORES, &Vial.VIAL_COMMONICITY) catch unreachable).m;

            if (material) |mat| {
                state.dungeon.itemsAt(coord).append(Item{ .Boulder = mat }) catch unreachable;
            }
        }
    }
}

fn powerExtractor(machine: *Machine) void {
    assert(machine.areas.len == 2);

    // Only function on every 32th turn, to give the impression that it takes
    // a while to extract more vials
    if ((state.ticks % 32) != 0) return;

    const input = machine.areas.data[0];
    const output = machine.areas.data[1];

    if (state.dungeon.itemsAt(output).isFull())
        return;

    // TODO: don't eat items that can't be processed

    var input_item: ?Item = null;
    if (state.dungeon.hasContainer(input)) |container| {
        if (container.items.len > 0) input_item = container.items.pop() catch unreachable;
    } else {
        const t_items = state.dungeon.itemsAt(input);
        if (t_items.len > 0) input_item = t_items.pop() catch unreachable;
    }

    if (input_item != null) switch (input_item.?) {
        .Boulder => |b| for (&Vial.VIAL_ORES) |vd| if (vd.m) |m|
            if (mem.eql(u8, m.name, b.name)) {
                state.dungeon.itemsAt(output).append(Item{ .Vial = vd.v }) catch unreachable;
                state.dungeon.atGas(machine.coord)[gas.Dust.id] = rng.range(usize, 10, 20);
            },
        else => {},
    };
}

fn powerBlastFurnace(machine: *Machine) void {
    assert(machine.areas.len == 9);

    // Only function on every 8th turn, to give the impression that it takes
    // a while to smelt more ores
    if ((state.ticks % 8) != 0) return;

    const areas = machine.areas.constSlice();
    const input_areas = areas[0..4];
    const furnace_area = areas[4];
    const output_areas = areas[5..7];
    //const refuse_areas = areas[7..9];

    // Move input items to furnace
    for (input_areas) |input_area| {
        if (state.dungeon.itemsAt(furnace_area).isFull())
            break;

        var input_item: ?Item = null;
        if (state.dungeon.hasContainer(input_area)) |container| {
            if (container.items.len > 0) input_item = container.items.pop() catch unreachable;
        } else {
            const t_items = state.dungeon.itemsAt(input_area);
            if (t_items.len > 0) input_item = t_items.pop() catch unreachable;
        }

        if (input_item) |item| {
            // XXX: it may be desirable later to handle this in a cleaner manner
            assert(meta.activeTag(item) == .Boulder);

            state.dungeon.itemsAt(furnace_area).append(item) catch unreachable;
            return;
        }
    }

    // Process items in furnace area and move to output area.
    var output_spot: ?Coord = null;
    for (output_areas) |output_area| {
        if (state.dungeon.hasContainer(output_area)) |container| {
            if (!container.items.isFull()) {
                output_spot = output_area;
                break;
            }
        } else {
            if (!state.dungeon.itemsAt(output_area).isFull()) {
                output_spot = output_area;
                break;
            }
        }
    }

    if (output_spot != null and state.dungeon.itemsAt(furnace_area).len > 0) {
        const item = state.dungeon.itemsAt(furnace_area).pop() catch unreachable;

        // XXX: it may be desirable later to handle this in a cleaner manner
        assert(meta.activeTag(item) == .Boulder);

        const result_mat = item.Boulder.smelt_result.?;
        state.dungeon.itemsAt(output_spot.?).append(Item{ .Boulder = result_mat }) catch unreachable;
    }
}

fn powerTurbinePowerSupply(machine: *Machine) void {
    assert(machine.areas.len > 0);

    var steam: usize = 0;

    for (machine.areas.constSlice()) |area| {
        const prop = state.dungeon.at(area).surface.?.Prop;

        // Anathema, we're modifying a game object this way! the horrors!
        prop.tile = switch (prop.tile) {
            '◴' => rng.chooseUnweighted(u21, &[_]u21{ '◜', '◠', '◝', '◡' }),
            '◜' => '◠',
            '◠' => '◝',
            '◝' => '◟',
            '◟' => '◡',
            '◡' => '◞',
            '◞' => '◜',
            else => unreachable,
        };

        steam += state.dungeon.atGas(area)[gas.Steam.id];
    }
}

fn powerHealingGasPump(machine: *Machine) void {
    assert(machine.areas.len > 0);

    for (machine.areas.constSlice()) |coord| {
        state.dungeon.atGas(coord)[gas.Healing.id] = 100;
    }
}

fn powerLabDoor(machine: *Machine) void {
    var has_mob = if (state.dungeon.at(machine.coord).mob != null) true else false;
    for (&DIRECTIONS) |d| {
        if (has_mob) break;
        if (machine.coord.move(d, state.mapgeometry)) |neighbor| {
            if (state.dungeon.at(neighbor).mob != null) has_mob = true;
        }
    }

    if (has_mob) {
        machine.powered_tile = '\\';
        machine.powered_sprite = .S_O_M_LabDoorOpen;
        machine.powered_walkable = true;
        machine.powered_opacity = 0.0;
    } else {
        machine.powered_tile = '+';
        machine.powered_sprite = .S_O_M_LabDoorShut;
        machine.powered_walkable = false;
        machine.powered_opacity = 1.0;
    }
}

fn powerMine(machine: *Machine) void {
    if (machine.last_interaction) |mob|
        if (mob == state.player) {
            // Deactivate.
            // TODO: either one of two things should be done:
            //       - Make it so that goblins won't trigger it, and make use of the
            //         restricted_to field on this machine.
            //       - Add a restricted_from field to ensure player won't trigger it.
            machine.power = 0;
            return;
        };

    if (rng.tenin(25)) {
        state.dungeon.at(machine.coord).surface = null;
        machine.disabled = true;

        explosions.kaboom(machine.coord, .{
            .strength = 3 * 100,
            .culprit = state.player,
        });
    }
}

fn interact1RechargingStation(_: *Machine, by: *Mob) bool {
    // XXX: All messages are printed in invokeRecharger().
    assert(by == state.player);

    var num_recharged: usize = 0;
    for (state.player.inventory.pack.slice()) |item| switch (item) {
        .Evocable => |e| if (e.rechargable and e.charges < e.max_charges) {
            e.charges = e.max_charges;
            num_recharged += 1;
        },
        else => {},
    };

    return num_recharged > 0;
}

fn interact1Drain(machine: *Machine, mob: *Mob) bool {
    assert(mob == state.player);

    var drains = StackBuffer(Coord, 4).init(null);
    var iter = state.mapRect(machine.coord.z).iter();
    while (iter.next()) |coord|
        if (state.dungeon.machineAt(coord)) |s|
            if (s != machine and mem.eql(u8, s.id, "drain"))
                drains.append(coord) catch break;

    if (drains.len == 0)
        return false;

    const drain = rng.chooseUnweighted(Coord, drains.constSlice());
    const succeeded = mob.teleportTo(drain, null, true, false);
    err.ensure(succeeded, "Couldn't teleport mob to drain {},{}.", .{ drain.x, drain.y }) catch return false;

    if (rng.onein(3))
        mob.addStatus(.Nausea, 0, .{ .Tmp = 10 });

    return true;
}

fn interact1FirstAidStation(m: *Machine, mob: *Mob) bool {
    assert(mob == state.player);

    const HP = state.player.HP;
    const heal_amount = @min(rng.range(usize, 3, 5), state.player.max_HP - HP);
    state.player.takeHealing(heal_amount);

    // Remove some harmful statuses.
    state.player.cancelStatus(.Nausea);
    state.player.cancelStatus(.Pain);
    state.player.cancelStatus(.Disorient);
    state.player.cancelStatus(.Blind);

    m.powered_fg = colors.filterGrayscale(m.powered_fg.?);
    m.unpowered_fg = colors.filterGrayscale(m.unpowered_fg.?);
    m.bg = colors.filterGrayscale(m.bg.?);

    return true;
}

// ----------------------------------------------------------------------------

pub fn readProps(alloc: mem.Allocator) void {
    const PropData = struct {
        id: []u8 = undefined,
        name: []u8 = undefined,
        tile: u21 = undefined,
        sprite: ?font.Sprite,
        fg: ?u32,
        bg: ?u32,
        walkable: bool,
        opacity: f64,
        flammability: usize,
        function: Prop.Function,
        holder: bool,
    };

    props = PropArrayList.init(alloc);
    prison_item_props = PropPtrAList.init(alloc);
    laboratory_item_props = PropPtrAList.init(alloc);
    laboratory_props = PropPtrAList.init(alloc);
    vault_props = PropPtrAList.init(alloc);
    statue_props = PropPtrAList.init(alloc);
    weapon_props = PropPtrAList.init(alloc);
    bottle_props = PropPtrAList.init(alloc);
    tools_props = PropPtrAList.init(alloc);
    armors_props = PropPtrAList.init(alloc);

    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("props.tsv", .{}) catch unreachable;

    var rbuf: [65535]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        PropData,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "id", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "name", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "tile", .parse_to = u21, .parse_fn = tsv.parseCharacter },
            .{ .field_name = "sprite", .parse_to = ?font.Sprite, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "fg", .parse_to = ?u32, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "bg", .parse_to = ?u32, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "walkable", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "opacity", .parse_to = f64, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "flammability", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "function", .parse_to = Prop.Function, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "holder", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true },
        },
        .{
            .sprite = null,
            .fg = null,
            .bg = null,
            .walkable = true,
            .opacity = 0.0,
            .flammability = 0,
            .function = .None,
            .holder = false,
        },
        rbuf[0..read],
        alloc,
    );

    if (!result.is_ok()) {
        err.bug(
            "Cannot read props: {} (line {}, field {})",
            .{ result.Err.type, result.Err.context.lineno, result.Err.context.field },
        );
    } else {
        const propdatas = result.unwrap();
        defer propdatas.deinit();

        for (propdatas.items) |propdata| {
            const prop = Prop{
                .id = propdata.id,
                .name = propdata.name,
                .tile = propdata.tile,
                .sprite = propdata.sprite,
                .fg = propdata.fg,
                .bg = propdata.bg,
                .walkable = propdata.walkable,
                .flammability = propdata.flammability,
                .opacity = propdata.opacity,
                .holder = propdata.holder,
                .function = propdata.function,
            };

            props.append(prop) catch unreachable;
        }

        for (props.items) |*prop| if (prop.function) |f| switch (f) {
            .Laboratory => laboratory_props.append(prop) catch err.oom(),
            .LaboratoryItem => laboratory_item_props.append(prop) catch err.oom(),
            .Vault => vault_props.append(prop) catch err.oom(),
            .Statue => statue_props.append(prop) catch err.oom(),
            .Weapons => weapon_props.append(prop) catch err.oom(),
            .Bottles => bottle_props.append(prop) catch err.oom(),
            .Tools => tools_props.append(prop) catch err.oom(),
            .Wearables => armors_props.append(prop) catch err.oom(),
            else => {},
        };

        std.log.info("Loaded {} props.", .{props.items.len});
    }
}

pub fn freeProps(alloc: mem.Allocator) void {
    for (props.items) |prop| prop.deinit(alloc);

    props.deinit();
    prison_item_props.deinit();
    laboratory_item_props.deinit();
    laboratory_props.deinit();
    vault_props.deinit();
    statue_props.deinit();
    weapon_props.deinit();
    bottle_props.deinit();
    tools_props.deinit();
    armors_props.deinit();
}

pub fn tickMachines(level: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            if (state.dungeon.at(coord).surface == null or
                meta.activeTag(state.dungeon.at(coord).surface.?) != .Machine)
                continue;

            const machine = state.dungeon.at(coord).surface.?.Machine;
            if (machine.disabled)
                continue;

            if (machine.isPowered()) {
                machine.on_power(machine);
                machine.power = machine.power -| machine.power_drain;
            }
        }
    }
}
