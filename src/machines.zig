// TODO: rename this file to surfaces.zig
// TODO: add state to machines
// STYLE: remove pub marker from power funcs

const std = @import("std");
const assert = std.debug.assert;

const main = @import("root");
const state = @import("state.zig");
const gas = @import("gas.zig");
const rng = @import("rng.zig");
usingnamespace @import("types.zig");

const STEEL_SUPPORT_COLOR: u32 = 0xa6c2d4;
const COPPER_COIL_COLOR: u32 = 0xd96c00;

pub const STATUES = [_]Prop{
    GoldStatue,
    RealgarStatue,
    IronStatue,
    SodaliteStatue,
    HematiteStatue,
};

pub const PROPS = [_]Prop{
    GoldStatue,
    RealgarStatue,
    IronStatue,
    SodaliteStatue,
    HematiteStatue,
    WorkstationProp,
    MediumSieve,
    SteelGasReservoir,
    SteelSupport_NE2_Prop,
    SteelSupport_SE2_Prop,
    SteelSupport_NSE2_Prop,
    SteelSupport_NSW2_Prop,
    SteelSupport_NSE2W2_Prop,
    SteelSupport_E2W2_Prop,
    LeftCopperCoilProp,
    RightCopperCoilProp,
    UpperCopperCoilProp,
    LowerCopperCoilProp,
    FullCopperCoilProp,
    GasVentProp,
    BedProp,
    IronBarProp,
};

pub const MACHINES = [_]Machine{
    PowerSupply,
    HealingGasPump,
    Brazier,
    StairExit,
    StairUp,
    NormalDoor,
    LockedDoor,
    ParalysisGasTrap,
    PoisonGasTrap,
    ConfusionGasTrap,
    AlarmTrap,
    RestrictedMachinesOpenLever,
};

pub const CONTAINERS = [_]Container{
    Bin, Barrel, Cabinet, Chest,
};

pub const Bin = Container{ .name = "bin", .tile = '╳', .capacity = 14, .type = .Casual };
pub const Barrel = Container{ .name = "barrel", .tile = 'ʊ', .capacity = 7, .type = .Eatables };
pub const Cabinet = Container{ .name = "cabinet", .tile = 'π', .capacity = 5, .type = .Wearables };
pub const Chest = Container{ .name = "chest", .tile = 'æ', .capacity = 7, .type = .Valuables };

pub const GoldStatue = Prop{ .id = "gold_statue", .name = "gold statue", .tile = '☺', .fg = 0xfff720, .walkable = false };
pub const RealgarStatue = Prop{ .id = "realgar_statue", .name = "realgar statue", .tile = '☺', .fg = 0xff343f, .walkable = false };
pub const IronStatue = Prop{ .id = "iron_statue", .name = "iron statue", .tile = '☻', .fg = 0xcacad2, .walkable = false };
pub const SodaliteStatue = Prop{ .id = "sodalite_statue", .name = "sodalite statue", .tile = '☺', .fg = 0xa4cfff, .walkable = false };
pub const HematiteStatue = Prop{ .id = "hematite_statue", .name = "hematite statue", .tile = '☺', .fg = 0xff7f70, .walkable = false };

pub const StairDstProp = Prop{
    .id = "stair_dst",
    .name = "downward stair",
    .tile = '×',
    .fg = 0xffffff,
    .walkable = true,
};

pub const WorkstationProp = Prop{
    .id = "workstation",
    .name = "workstation",
    .tile = '░',
    .fg = 0xffffff,
    .walkable = true,
};

pub const MediumSieve = Prop{
    .id = "medium_sieve",
    .name = "medium_sieve",
    .tile = '▒',
    .fg = 0xffe7e7,
    .walkable = false,
    .function = .ActionPoint,
};

pub const SteelGasReservoir = Prop{
    .id = "steel_gas_reservoir",
    .name = "steel gas reservoir",
    .tile = '■',
    .fg = 0xd7d7ff,
    .walkable = false,
};

pub const SteelSupport_NE2_Prop = Prop{
    .id = "steel_support_ne2",
    .name = "steel support",
    .tile = '╘',
    .fg = STEEL_SUPPORT_COLOR,
    .walkable = false,
};

pub const SteelSupport_SE2_Prop = Prop{
    .id = "steel_support_se2",
    .name = "steel support",
    .tile = '╒',
    .fg = STEEL_SUPPORT_COLOR,
    .walkable = false,
};

pub const SteelSupport_NSE2_Prop = Prop{
    .id = "steel_support_nse2",
    .name = "steel support",
    .tile = '╞',
    .fg = STEEL_SUPPORT_COLOR,
    .walkable = false,
};

pub const SteelSupport_NSW2_Prop = Prop{
    .id = "steel_support_nsw2",
    .name = "steel support",
    .tile = '╡',
    .fg = STEEL_SUPPORT_COLOR,
    .walkable = false,
};

pub const SteelSupport_NSE2W2_Prop = Prop{
    .id = "steel_support_nse2w2",
    .name = "steel support",
    .tile = '╪',
    .fg = STEEL_SUPPORT_COLOR,
    .walkable = false,
};

pub const SteelSupport_E2W2_Prop = Prop{
    .id = "steel_support_e2w2",
    .name = "steel support",
    .tile = '═',
    .fg = STEEL_SUPPORT_COLOR,
    .walkable = false,
};

pub const LeftCopperCoilProp = Prop{
    .id = "left_copper_coil",
    .name = "half copper coil",
    .tile = '▌',
    .fg = COPPER_COIL_COLOR,
    .walkable = false,
};

pub const RightCopperCoilProp = Prop{
    .id = "right_copper_coil",
    .name = "half copper coil",
    .tile = '▐',
    .fg = COPPER_COIL_COLOR,
    .walkable = false,
};

pub const LowerCopperCoilProp = Prop{
    .id = "lower_copper_coil",
    .name = "half copper coil",
    .tile = '▄',
    .fg = COPPER_COIL_COLOR,
    .walkable = false,
};

pub const UpperCopperCoilProp = Prop{
    .id = "upper_copper_coil",
    .name = "half copper coil",
    .tile = '▀',
    .fg = COPPER_COIL_COLOR,
    .walkable = false,
};

pub const FullCopperCoilProp = Prop{
    .id = "full_copper_coil",
    .name = "large copper coil",
    .tile = '█',
    .fg = COPPER_COIL_COLOR,
    .walkable = false,
};

pub const GasVentProp = Prop{
    .name = "gas vent",
    .tile = '=',
    .fg = 0xffffff,
    .bg = 0x888888,
    .walkable = false,
    .opacity = 1.0,
};

pub const BedProp = Prop{
    .id = "bed",
    .name = "bed",
    .tile = 'Θ',
    .fg = 0xdaa520,
    .opacity = 0.6,
    .walkable = true,
};

pub const IronBarProp = Prop{
    .name = "iron bars",
    .tile = '≡',
    .fg = 0x000012,
    .bg = 0xdadada,
    .opacity = 0.0,
    .walkable = false,
};

pub const PowerSupply = Machine{
    .id = "power_supply",
    .name = "machine",

    .powered_tile = '█',
    .unpowered_tile = '▓',

    .power_drain = 100,
    .power_add = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .powered_luminescence = 99,
    .unpowered_luminescence = 5,

    .on_power = powerPowerSupply,
};

pub const HealingGasPump = Machine{
    .id = "healing_gas_pump",
    .name = "machine",

    .powered_tile = '█',
    .unpowered_tile = '▓',

    .power_drain = 100,
    .power_add = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .on_power = powerHealingGasPump,
};

pub const Brazier = Machine{
    .name = "a brazier",

    .powered_tile = '╋',
    .unpowered_tile = '┽',

    .powered_fg = 0xeee088,
    .unpowered_fg = 0xffffff,

    .powered_bg = 0xb7b7b7,
    .unpowered_bg = 0xaaaaaa,

    .power_drain = 10,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 1.0,
    .unpowered_opacity = 1.0,

    // maximum, could be much lower (see mapgen:placeLights)
    .powered_luminescence = 90,
    .unpowered_luminescence = 0,

    .on_power = powerNone,
};

pub const StairExit = Machine{
    .id = "stair_exit",
    .name = "exit staircase",
    .powered_tile = '»',
    .unpowered_tile = '»',
    .on_power = powerStairExit,
};

// TODO: Maybe define a "Doormat" prop that stairs have? And doormats should have
// a very welcoming message on it, of course
pub const StairUp = Machine{
    .name = "ascending staircase",
    .powered_tile = '▲',
    .unpowered_tile = '▲',
    .on_power = powerStairUp,
};

pub const AlarmTrap = Machine{
    .name = "alarm trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .on_power = powerAlarmTrap,
};

pub const PoisonGasTrap = Machine{
    .name = "poison gas trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .on_power = powerPoisonGasTrap,
};

pub const ParalysisGasTrap = Machine{
    .name = "paralysis gas trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .on_power = powerParalysisGasTrap,
};

pub const ConfusionGasTrap = Machine{
    .name = "confusion gas trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .on_power = powerConfusionGasTrap,
};

pub const NormalDoor = Machine{
    .name = "door",
    .powered_tile = '□',
    .unpowered_tile = '■',
    .power_drain = 49,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .powered_opacity = 0.0,
    .unpowered_opacity = 1.0,
    .on_power = powerNone,
};

pub const LockedDoor = Machine{
    .name = "locked door",
    .powered_tile = '□',
    .unpowered_tile = '■',
    .unpowered_fg = 0xcfcfff,
    .power_drain = 90,
    .restricted_to = .Sauron,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .on_power = powerNone,
};

pub const RestrictedMachinesOpenLever = Machine{
    .id = "restricted_machines_open_lever",
    .name = "lever",
    .powered_tile = '/',
    .unpowered_tile = '\\',
    .unpowered_fg = 0xdaa520,
    .powered_fg = 0xdaa520,
    .power_drain = 90,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .on_power = powerRestrictedMachinesOpenLever,
};

pub fn powerNone(_: *Machine) void {}

pub fn powerPowerSupply(machine: *Machine) void {
    var iter = state.machines.iterator();
    while (iter.nextPtr()) |mach| {
        if (mach.coord.z == machine.coord.z and mach.auto_power)
            mach.addPower(null);
    }
}

pub fn powerHealingGasPump(machine: *Machine) void {
    for (&CARDINAL_DIRECTIONS) |direction| {
        if (machine.coord.move(direction, state.mapgeometry)) |neighbor| {
            if (state.dungeon.at(neighbor).surface) |surface| {
                if (std.meta.activeTag(surface) == .Prop and surface.Prop.function == .ActionPoint)
                    state.dungeon.atGas(neighbor)[gas.Healing.id] = 1.0;
            }
        }
    }
}

pub fn powerAlarmTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Sauron) return;

        culprit.makeNoise(2048); // muahahaha
        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "You hear a loud clanging noise!", .{});
    }
}

pub fn powerPoisonGasTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Sauron) return;

        for (machine.props) |maybe_prop| {
            if (maybe_prop) |vent| {
                state.dungeon.atGas(vent.coord)[gas.Poison.id] = 1.0;
            }
        }

        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "Noxious fumes seep through the gas vents!", .{});
    }
}

pub fn powerParalysisGasTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Sauron) return;

        for (machine.props) |maybe_prop| {
            if (maybe_prop) |vent| {
                state.dungeon.atGas(vent.coord)[gas.Paralysis.id] = 1.0;
            }
        }

        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "Paralytic gas seeps out of the gas vents!", .{});
    }
}

pub fn powerConfusionGasTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Sauron) return;

        for (machine.props) |maybe_prop| {
            if (maybe_prop) |vent| {
                state.dungeon.atGas(vent.coord)[gas.Confusion.id] = 1.0;
            }
        }

        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "Confusing gas seeps out of the gas vents!", .{});
    }
}

pub fn powerStairExit(machine: *Machine) void {
    assert(machine.coord.z == 0);
    if (machine.last_interaction) |culprit| {
        if (!culprit.coord.eq(state.player.coord)) return;
        state.state = .Win;
    }
}

pub fn powerStairUp(machine: *Machine) void {
    assert(machine.coord.z >= 1);
    const culprit = machine.last_interaction.?;
    if (!culprit.coord.eq(state.player.coord)) return;

    const dst = Coord.new2(machine.coord.z - 1, machine.coord.x, machine.coord.y);
    if (culprit.teleportTo(dst, null))
        state.message(.Move, "You ascend.", .{});
}

pub fn powerRestrictedMachinesOpenLever(machine: *Machine) void {
    const room_i = switch (state.layout[machine.coord.z][machine.coord.y][machine.coord.x]) {
        .Unknown => return,
        .Room => |r| r,
    };
    const room = &state.dungeon.rooms[machine.coord.z].items[room_i];

    var y: usize = room.start.y;
    while (y < room.end().y) : (y += 1) {
        var x: usize = room.start.x;
        while (x < room.end().x) : (x += 1) {
            const coord = Coord.new2(machine.coord.z, x, y);

            if (state.dungeon.at(coord).surface) |surface| {
                switch (surface) {
                    .Machine => |m| if (m.restricted_to != null)
                        m.addPower(null),
                    else => {},
                }
            }
        }
    }
}
