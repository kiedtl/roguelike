// TODO: add state to machines

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;
const math = std.math;
const enums = std.enums;

const display = @import("display.zig");
const dijkstra = @import("dijkstra.zig");
const spells = @import("spells.zig");
const colors = @import("colors.zig");
const err = @import("err.zig");
const main = @import("root");
const utils = @import("utils.zig");
const state = @import("state.zig");
const explosions = @import("explosions.zig");
const gas = @import("gas.zig");
const tsv = @import("tsv.zig");
const rng = @import("rng.zig");
const materials = @import("materials.zig");
const types = @import("types.zig");

const Rect = types.Rect;
const Coord = types.Coord;
const Direction = types.Direction;
const Item = types.Item;
const Weapon = types.Weapon;
const Mob = types.Mob;
const Machine = types.Machine;
const PropArrayList = types.PropArrayList;
const Container = types.Container;
const Material = types.Material;
const Vial = types.Vial;
const Prop = types.Prop;
const Stat = types.Stat;
const Resistance = types.Resistance;
const StatusDataInfo = types.StatusDataInfo;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const StackBuffer = @import("buffer.zig").StackBuffer;

// ---

pub var props: PropArrayList = undefined;
pub var prison_item_props: PropArrayList = undefined;
pub var laboratory_item_props: PropArrayList = undefined;
pub var laboratory_props: PropArrayList = undefined;
pub var vault_props: PropArrayList = undefined;
pub var statue_props: PropArrayList = undefined;
pub var weapon_props: PropArrayList = undefined;

pub const Terrain = struct {
    id: []const u8,
    name: []const u8,
    color: u32,
    tile: u21,
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
    effects: []const StatusDataInfo = &[_]StatusDataInfo{},
    flammability: usize = 0,
    fire_retardant: bool = false,
    repairable: bool = true,
    luminescence: usize = 0,
    opacity: usize = 0,

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

pub const DefaultTerrain = Terrain{
    .id = "t_default",
    .name = "",
    .color = colors.DOBALENE_BLUE,
    .tile = '·',

    // for_levels and placement have no effect, since this is the default
    // terrain.
    .for_levels = &[_][]const u8{"ANY"},
    .placement = .EntireRoom,

    .weight = 20,
};

pub const CarpetTerrain = Terrain{
    .id = "t_carpet",
    .name = "carpet",
    .color = 0xdaa520, // goldenish
    .tile = '÷',
    .stats = .{ .Sneak = 3 },
    .flammability = 30,

    .for_levels = &[_][]const u8{ "PRI", "QRT" },
    .placement = .EntireRoom,
    .weight = 8,
};

pub const GravelTerrain = Terrain{
    .id = "t_gravel",
    .name = "gravel",
    .color = 0xdadada,
    .tile = ',',
    .stats = .{ .Sneak = -1 },

    .for_levels = &[_][]const u8{"CAV"},
    .placement = .EntireRoom,
    .weight = 5,
};

pub const MetalTerrain = Terrain{
    .id = "t_metal",
    .name = "metal",
    .color = 0x8094ae, // steel blue
    .tile = '∷',
    .resists = .{ .rElec = -25 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .Conductive, .duration = .{ .Ctx = null } },
    },

    .for_levels = &[_][]const u8{ "PRI", "LAB", "QRT" },
    .placement = .EntireRoom,
    .weight = 6,
};

pub const CopperTerrain = Terrain{
    .id = "t_copper",
    .name = "copper",
    .color = 0x783724, // copperish red
    .tile = ':',
    .resists = .{ .rElec = -25 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .CopperWeapon, .duration = .{ .Ctx = null } },
    },

    .for_levels = &[_][]const u8{ "PRI", "LAB", "QRT" },
    .placement = .EntireRoom,
    .weight = 8,
};

pub const WoodTerrain = Terrain{
    .id = "t_wood",
    .name = "wood",
    .color = 0xdaa520, // wood
    .tile = '·',
    .stats = .{ .Sneak = -1 },
    .resists = .{ .rFire = -25, .rElec = 25 },
    .flammability = 40,

    .for_levels = &[_][]const u8{ "PRI", "QRT" },
    .placement = .RoomPortion,
    .weight = 5,
};

pub const ShallowWaterTerrain = Terrain{
    .id = "t_water",
    .name = "shallow water",
    .color = 0x3c73b1, // medium blue
    .tile = '≈',
    .stats = .{ .Sneak = -2 },
    .resists = .{ .rFire = 50, .rElec = -50 },
    .effects = &[_]StatusDataInfo{
        .{ .status = .Conductive, .duration = .{ .Ctx = null } },
    },
    .fire_retardant = true,

    .for_levels = &[_][]const u8{"CAV"},
    .placement = .RoomBlob,
    .weight = 3,
};

pub const DeadFungiTerrain = Terrain{
    .id = "t_f_dead",
    .name = "dead fungi",
    .color = 0xaaaaaa,
    .tile = '"',
    .opacity = 60,
    .resists = .{ .rFire = -25 },
    .flammability = 30,
    .repairable = false,

    .for_levels = &[_][]const u8{"ANY"},
    .placement = .RoomBlob,
    .weight = 5,
};

pub const TallFungiTerrain = Terrain{
    .id = "t_f_tall",
    .name = "tall fungi",
    .color = 0x0a8505,
    .tile = '&',
    .opacity = 100,
    .flammability = 20,
    .repairable = false,

    .for_levels = &[_][]const u8{ "PRI", "QRT" },
    .placement = .RoomBlob,
    .weight = 7,
};

pub const PillarTerrain = Terrain{
    .id = "t_pillar",
    .name = "pillar",
    .color = 0xffffff,
    .tile = '8',
    .stats = .{ .Evade = 25 },
    .opacity = 50,
    .repairable = false,

    .for_levels = &[_][]const u8{ "PRI", "LAB", "QRT" },
    .placement = .{ .RoomSpotty = 5 },
    .weight = 8,
};

pub const PlatformTerrain = Terrain{
    .id = "t_platform",
    .name = "platform",
    .color = 0xffffff,
    .tile = '_',
    .stats = .{ .Evade = -10, .Melee = 10, .Missile = 20, .Vision = 3 },
    .opacity = 20,

    .for_levels = &[_][]const u8{ "PRI", "LAB", "QRT" },
    .placement = .{ .RoomSpotty = 5 },
    .weight = 8,
};

pub const TERRAIN = [_]*const Terrain{
    &DefaultTerrain,
    &CarpetTerrain,
    &GravelTerrain,
    &MetalTerrain,
    &CopperTerrain,
    &WoodTerrain,
    &ShallowWaterTerrain,
    &DeadFungiTerrain,
    &TallFungiTerrain,
    &PillarTerrain,
    &PlatformTerrain,
};

pub const MACHINES = [_]Machine{
    SteamVent,
    ResearchCore,
    ElevatorMotor,
    Extractor,
    BlastFurnace,
    TurbinePowerSupply,
    Brazier,
    Lamp,
    StairExit,
    NormalDoor,
    LabDoor,
    VaultDoor,
    LockedDoor,
    IronVaultDoor,
    GoldVaultDoor,
    ParalysisGasTrap,
    PoisonGasTrap,
    ConfusionGasTrap,
    SeizureGasTrap,
    BlindingGasTrap,
    Mine,
    CapacitorArray,
    RechargingStation,
    Drain,
    Fountain,
    WaterBarrel,
};

//pub const Cabinet = Container{ .name = "cabinet", .tile = 'π', .capacity = 4, .type = .Wearables };
pub const WeaponRack = Container{ .name = "weapon rack", .tile = 'π', .capacity = 3, .type = .Weapons };
pub const LabCabinet = Container{ .name = "cabinet", .tile = 'π', .capacity = 4, .type = .Utility, .item_repeat = 70 };
pub const VOreCrate = Container{ .name = "crate", .tile = '∐', .capacity = 14, .type = .VOres, .item_repeat = 60 };

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

    .on_power = struct {
        pub fn f(machine: *Machine) void {
            if (state.ticks % 40 == 0) {
                state.dungeon.atGas(machine.coord)[gas.Steam.id] += 2;
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

pub const ElevatorMotor = Machine{
    .id = "elevator_motor",
    .name = "motor",

    .powered_tile = '⊛',
    .unpowered_tile = '⊚',

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerElevatorMotor,
};

pub const Extractor = Machine{
    .id = "extractor",
    .name = "machine",

    .powered_tile = '⊟',
    .unpowered_tile = '⊞',

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerExtractor,
};

pub const BlastFurnace = Machine{
    .id = "blast_furnace",
    .name = "blast furnace",

    .powered_tile = '≡',
    .unpowered_tile = '≡',

    .power_drain = 0,
    .power = 0,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_luminescence = 100,
    .unpowered_luminescence = 0,
    .dims = true,

    .on_power = powerBlastFurnace,
};

pub const TurbinePowerSupply = Machine{
    .id = "turbine_power_supply",
    .name = "turbine controller",

    .powered_tile = '≡',
    .unpowered_tile = '≡',

    .power_drain = 0,
    .power = 100, // Start out fully powered

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .on_power = powerTurbinePowerSupply,
};

pub const Brazier = Machine{
    .name = "brazier",

    .powered_tile = '╋',
    .unpowered_tile = '┽',

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
    .powered_luminescence = 60,
    .unpowered_luminescence = 0,

    .flammability = 20,
    .on_power = powerNone,
};

pub const Lamp = Machine{
    .name = "lamp",

    .powered_tile = '•',
    .unpowered_tile = '○',

    .powered_fg = 0xffdf12,
    .unpowered_fg = 0x88e0ee,

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 1.0,
    .unpowered_opacity = 1.0,

    // maximum, could be lower (see mapgen:placeLights)
    .powered_luminescence = 100,
    .unpowered_luminescence = 0,

    .flammability = 20,
    .on_power = powerNone,
};

pub const StairExit = Machine{
    .id = "stair_exit",
    .name = "exit staircase",
    .powered_tile = '«',
    .unpowered_tile = '«',
    .on_power = powerStairExit,
};

pub const PoisonGasTrap = Machine.createGasTrap("poison gas", &gas.Poison);
pub const ParalysisGasTrap = Machine.createGasTrap("paralysing gas", &gas.Paralysis);
pub const ConfusionGasTrap = Machine.createGasTrap("confusing gas", &gas.Confusion);
pub const SeizureGasTrap = Machine.createGasTrap("seizure gas", &gas.Seizure);
pub const BlindingGasTrap = Machine.createGasTrap("tear gas", &gas.Blinding);

pub const NormalDoor = Machine{
    .id = "door_normal",
    .name = "door",
    .powered_tile = '\'',
    .unpowered_tile = '+',
    .powered_fg = 0xffaaaa,
    .unpowered_fg = 0xffaaaa,
    .powered_bg = 0x7a2914,
    .unpowered_bg = 0x7a2914,
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
    .unpowered_fg = 0xffbfff,
    .power_drain = 0,
    .power = 100,
    .powered_walkable = false,
    .unpowered_walkable = true,
    .powered_opacity = 1.0,
    .unpowered_opacity = 0.0,
    .flammability = 0, // metal door not flammable
    .porous = true,
    .on_power = powerLabDoor,
};

pub const VaultDoor = Machine{
    .id = "door_qrt",
    .name = "door",
    .powered_tile = '░',
    .unpowered_tile = '+',
    .powered_fg = 0xaaaaaa,
    .unpowered_bg = 0xffffff,
    .unpowered_fg = 0x000000,
    .power_drain = 49,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .powered_opacity = 0.0,
    .unpowered_opacity = 1.0,
    .flammability = 10, // heavy wood/metal door
    .porous = true,
    .on_power = powerNone,
};

pub const LockedDoor = Machine{
    .id = "door_locked",
    .name = "locked door",
    .powered_tile = '\'',
    .unpowered_tile = '+',
    .powered_fg = 0xaaaaff,
    .unpowered_fg = 0xaaaaff,
    .powered_bg = 0x29147a,
    .unpowered_bg = 0x29147a,
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
                state.dungeon.at(machine.coord).surface = null;
                return true;
            }
        }.f,
    },
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
        .power_drain = 0,
        .restricted_to = .OtherGood,
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

pub const CapacitorArray = Machine{
    .id = "capacitor_array",
    .name = "capacitor array",
    .announce = true,
    .powered_tile = 'C',
    .unpowered_tile = 'x',
    .powered_fg = 0x10243e,
    .unpowered_fg = 0x10243e,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .bg = 0xb0c4de,
    .power_drain = 0,
    .power = 100,
    .on_power = powerNone,
    .flammability = 20,
    .evoke_confirm = "Really discharge the capacitor array?",
    .player_interact = .{
        .name = "discharge",
        .success_msg = "You discharge the capacitor.",
        .no_effect_msg = null,
        .max_use = 1,
        .func = struct {
            fn f(_: *Machine, by: *Mob) bool {
                assert(by == state.player);

                if (state.player.resistance(.rElec) <= 0) {
                    display.drawAlertThenLog("Cannot discharge without rElec.", .{});
                    return false;
                }

                var affected = StackBuffer(Coord, 128).init(null);
                var gen = Generator(Rect.rectIter).init(state.mapRect(by.coord.z));
                while (gen.next()) |coord| if (state.player.cansee(coord)) {
                    if (utils.getHostileAt(state.player, coord)) |hostile| {
                        if (hostile.resistance(.rElec) <= 0) {
                            hostile.takeDamage(.{
                                .amount = 27.0,
                                .by_mob = state.player,
                                .blood = false,
                                .source = .RangedAttack,
                                .kind = .Electric,
                            }, .{ .basic = true });
                            affected.append(coord) catch err.wat();
                        }
                    } else |_| {}
                };

                if (affected.len == 0) {
                    display.drawAlertThenLog("No electricity-vulnerable monsters in sight.", .{});
                    return false;
                } else {
                    state.player.makeNoise(.Explosion, .Loudest);
                    display.Animation.blink(affected.constSlice(), '*', display.Animation.ELEC_LINE_FG, .{}).apply();
                }

                return true;
            }
        }.f,
    },
};

pub const RechargingStation = Machine{
    .id = "recharging_station",
    .name = "recharging station",
    .announce = true,
    .powered_tile = 'R',
    .unpowered_tile = 'x',
    .powered_fg = 0x000000,
    .unpowered_fg = 0x000000,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .bg = 0x90a3b7,
    .power_drain = 0,
    .power = 100,
    .on_power = powerNone,
    .flammability = 20,
    .player_interact = .{
        .name = "recharge",
        .success_msg = "All evocables recharged.",
        .no_effect_msg = "No evocables to recharge!",
        .max_use = 1,
        .func = interact1RechargingStation,
    },
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
        .needs_power = false,
        .max_use = 1,
        .func = interact1Drain,
    },
};

pub const Fountain = Machine{
    .id = "fountain",
    .name = "fountain",
    .announce = true,
    .powered_tile = '¶',
    .unpowered_tile = '¶',
    .powered_fg = 0x00d7ff,
    .unpowered_fg = 0x00d7ff,
    .powered_walkable = true,
    .unpowered_walkable = true,
    .on_power = powerNone,
    .player_interact = .{
        .name = "quaff",
        .success_msg = "The fountain refreshes you.",
        .no_effect_msg = "The fountain is dry!",
        .needs_power = false,
        .max_use = 1,
        .func = interact1Fountain,
    },
};

pub const WaterBarrel = Machine{
    .id = "barrel_water",
    .name = "barrel of water",
    .announce = true,
    .powered_tile = 'ʊ',
    .unpowered_tile = 'ʊ',
    .powered_fg = 0x00d7ff,
    .unpowered_fg = 0x00d7ff,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .evoke_confirm = "Break open the barrel of water?",
    .on_power = struct {
        fn f(machine: *Machine) void {
            assert(machine.last_interaction.? == state.player);

            var dijk = dijkstra.Dijkstra.init(
                machine.coord,
                state.mapgeometry,
                3,
                state.is_walkable,
                .{ .ignore_mobs = true, .right_now = true },
                state.GPA.allocator(),
            );
            defer dijk.deinit();
            while (dijk.next()) |item|
                if (machine.coord.distanceManhattan(item) < 4 or
                    rng.percent(@as(usize, 20)))
                {
                    state.dungeon.at(item).terrain = &ShallowWaterTerrain;
                };

            state.message(.Info, "You break open the water barrel!", .{});

            machine.disabled = true;
            state.dungeon.at(machine.coord).surface = null;
        }
    }.f,
};

fn powerNone(_: *Machine) void {}

fn powerResearchCore(machine: *Machine) void {
    // Only function on every 32nd turn, to give the impression that it takes
    // a while to process vials
    if ((state.ticks % 32) != 0 or rng.onein(3)) return;

    for (&DIRECTIONS) |direction| if (machine.coord.move(direction, state.mapgeometry)) |neighbor| {
        for (state.dungeon.itemsAt(neighbor).constSlice()) |item, i| switch (item) {
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

    var input = machine.areas.data[0];
    var output = machine.areas.data[1];

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
                state.dungeon.atGas(machine.coord)[gas.Dust.id] = rng.range(f64, 0.1, 0.2);
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

    var steam: f64 = 0.0;

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
        state.dungeon.atGas(coord)[gas.Healing.id] = 1.0;
    }
}

fn powerStairExit(machine: *Machine) void {
    assert(machine.coord.z == 0);
    if (machine.last_interaction) |culprit| {
        if (!culprit.coord.eq(state.player.coord)) return;
        state.state = .Win;
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
        machine.powered_walkable = true;
        machine.powered_opacity = 0.0;
    } else {
        machine.powered_tile = '+';
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

    var drains = StackBuffer(*Machine, 32).init(null);
    for (state.dungeon.map[state.player.coord.z]) |*row| {
        for (row) |*tile| {
            if (tile.surface) |s|
                if (meta.activeTag(s) == .Machine and
                    s.Machine != machine and
                    mem.eql(u8, s.Machine.id, "drain"))
                {
                    drains.append(s.Machine) catch err.wat();
                };
        }
    }

    if (drains.len == 0) {
        return false;
    }
    const drain = rng.chooseUnweighted(*Machine, drains.constSlice());

    const succeeded = mob.teleportTo(drain.coord, null, true);
    assert(succeeded);

    if (rng.onein(3)) {
        mob.addStatus(.Nausea, 0, .{ .Tmp = 10 });
    }

    return true;
}

fn interact1Fountain(_: *Machine, mob: *Mob) bool {
    assert(mob == state.player);

    const HP = state.player.HP;
    state.player.HP = math.clamp(HP + ((state.player.max_HP - HP) / 2), 0, state.player.max_HP);

    // Remove some harmful statuses.
    state.player.cancelStatus(.Fire);
    state.player.cancelStatus(.Poison);
    state.player.cancelStatus(.Nausea);
    state.player.cancelStatus(.Pain);

    return true;
}

// ----------------------------------------------------------------------------

pub fn readProps(alloc: mem.Allocator) void {
    const PropData = struct {
        id: []u8 = undefined,
        name: []u8 = undefined,
        tile: u21 = undefined,
        fg: ?u32 = undefined,
        bg: ?u32 = undefined,
        walkable: bool = undefined,
        opacity: f64 = undefined,
        flammability: usize = undefined,
        function: Function = undefined,
        holder: bool = undefined,

        pub const Function = enum { Laboratory, Vault, LaboratoryItem, Statue, Weapons, None };
    };

    props = PropArrayList.init(alloc);
    prison_item_props = PropArrayList.init(alloc);
    laboratory_item_props = PropArrayList.init(alloc);
    laboratory_props = PropArrayList.init(alloc);
    vault_props = PropArrayList.init(alloc);
    statue_props = PropArrayList.init(alloc);
    weapon_props = PropArrayList.init(alloc);

    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("props.tsv", .{
        .read = true,
        .lock = .None,
    }) catch unreachable;

    var rbuf: [65535]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        PropData,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "id", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "name", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "tile", .parse_to = u21, .parse_fn = tsv.parseCharacter },
            .{ .field_name = "fg", .parse_to = ?u32, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = null },
            .{ .field_name = "bg", .parse_to = ?u32, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = null },
            .{ .field_name = "walkable", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = true },
            .{ .field_name = "opacity", .parse_to = f64, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0.0 },
            .{ .field_name = "flammability", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "function", .parse_to = PropData.Function, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = .None },
            .{ .field_name = "holder", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = false },
        },
        .{},
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
                .fg = propdata.fg,
                .bg = propdata.bg,
                .walkable = propdata.walkable,
                .flammability = propdata.flammability,
                .opacity = propdata.opacity,
                .holder = propdata.holder,
            };

            switch (propdata.function) {
                .Laboratory => laboratory_props.append(prop) catch err.oom(),
                .LaboratoryItem => laboratory_item_props.append(prop) catch err.oom(),
                .Vault => vault_props.append(prop) catch err.oom(),
                .Statue => statue_props.append(prop) catch err.oom(),
                .Weapons => weapon_props.append(prop) catch err.oom(),
                else => {},
            }

            props.append(prop) catch unreachable;
        }

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
