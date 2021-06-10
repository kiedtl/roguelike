// TODO: add state to machines
// STYLE: remove pub marker from power funcs

const std = @import("std");
const assert = std.debug.assert;

const state = @import("state.zig");
const gas = @import("gas.zig");
const rng = @import("rng.zig");
usingnamespace @import("types.zig");

pub const GasVentProp = Prop{ .name = "gas vent", .tile = '=' };

pub const BedProp = Prop{
    .id = "bed",
    .name = "bed",
    .tile = 'Θ',
    .fg = 0xdaa520,
    .opacity = 0.6,
    .walkable = false,
};

pub const IronBarProp = Prop{
    .name = "iron bars",
    .tile = '≡',
    .fg = 0x000012,
    .bg = 0xdadada,
    .opacity = 0.3,
    .walkable = false,
};

pub const PROPS = [_]Prop{ GasVentProp, BedProp, IronBarProp };

pub const Lamp = Machine{
    .name = "a lamp",

    .powered_tile = '•',
    .unpowered_tile = '•',

    .power_drain = 0,
    .power_add = 15,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0.3,
    .unpowered_opacity = 0.0,

    // maximum, could be much lower (see mapgen:_light_room)
    .powered_luminescence = 75,
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
    .powered_tile = '>',
    .unpowered_tile = '>',
    .on_power = powerStairUp,
};

pub const StairDown = Machine{
    .name = "descending staircase",
    .powered_tile = '<',
    .unpowered_tile = '<',
    .on_power = powerStairDown,
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

pub fn powerNone(_: *Machine) void {}

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

pub fn powerStairExit(machine: *Machine) void {
    assert(machine.coord.z == 0);
    if (machine.last_interaction) |culprit| {
        if (!culprit.coord.eq(state.player.coord)) return;
        quit = true;
    }
}

pub fn powerStairUp(machine: *Machine) void {
    assert(machine.coord.z >= 1);
    if (machine.last_interaction) |culprit| {
        if (!culprit.coord.eq(state.player.coord)) return;

        const uplevel = Coord.new2(machine.coord.z - 1, machine.coord.x, machine.coord.y);

        var dest: ?Coord = null;
        for (&CARDINAL_DIRECTIONS) |d| {
            var desttmp = uplevel;
            if (desttmp.move(d, state.mapgeometry) and state.is_walkable(desttmp))
                dest = desttmp;
        }

        if (dest) |spot| {
            const moved = culprit.teleportTo(spot);
            assert(moved);
            state.message(.Move, "You ascend.", .{});
        }
    }
}

pub fn powerStairDown(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (!culprit.coord.eq(state.player.coord)) return;

        const downlevel = Coord.new2(machine.coord.z + 1, machine.coord.x, machine.coord.y);
        assert(downlevel.z < state.LEVELS);

        var dest: ?Coord = null;
        for (&CARDINAL_DIRECTIONS) |d| {
            var desttmp = downlevel;
            if (desttmp.move(d, state.mapgeometry) and state.is_walkable(desttmp))
                dest = desttmp;
        }

        if (dest) |spot| {
            const moved = culprit.teleportTo(spot);
            assert(moved);
            state.message(.Move, "You descend.", .{});
        }
    }
}
