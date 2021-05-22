// TODO: add state to machines
// STYLE: remove pub marker from trigger funcs

const std = @import("std");
const assert = std.debug.assert;

const state = @import("state.zig");
const gas = @import("gas.zig");
const rng = @import("rng.zig");
usingnamespace @import("types.zig");

pub const GasVentProp = Prop{ .name = "gas vent", .tile = '=' };

// FIXME: remove this. This is temporary until we get books, prefab rooms,
// knowledge systems, etc.
pub const GoldCoins = Machine{
    .name = "a pile of gold coins",
    .tile = '*',
    .walkable = true,
    .opacity = 0.0,
    .on_trigger = triggerGoldCoins,
    .should_be_avoided = false,
};

// TODO: Maybe define a "Doormat" prop that stairs have? And doormats should have
// a very welcoming message on it, of course
pub const StairUp = Machine{
    .name = "ascending staircase",
    .tile = '>',
    .walkable = true,
    .opacity = 0.0,
    .on_trigger = triggerStairUp,
    .should_be_avoided = true,
};

pub const StairDown = Machine{
    .name = "descending staircase",
    .tile = '<',
    .walkable = true,
    .opacity = 0.0,
    .on_trigger = triggerStairDown,
    .should_be_avoided = true,
};

pub const AlarmTrap = Machine{
    .name = "alarm trap",
    .tile = '^',
    .walkable = true,
    .opacity = 0.0,
    .on_trigger = triggerAlarmTrap,
    .should_be_avoided = true,
};

pub const CausticGasTrap = Machine{
    .name = "caustic gas trap",
    .tile = '^',
    .walkable = true,
    .opacity = 0.0,
    .on_trigger = triggerCausticGasTrap,
    .should_be_avoided = true,
};

pub const NormalDoor = Machine{
    .name = "door",
    .tile = '+', // TODO: red background?
    .walkable = true,
    .opacity = 1.0,
    .on_trigger = triggerNone,
    .should_be_avoided = false,
};

pub fn triggerNone(_: *Mob, __: *Machine) void {}

pub fn triggerAlarmTrap(culprit: *Mob, machine: *Machine) void {
    if (culprit.allegiance == .Sauron) {
        return;
    }

    culprit.noise += 1000; // muahahaha
    state.message(.Trap, "You hear a loud clanging noise!", .{});
}

pub fn triggerCausticGasTrap(culprit: *Mob, machine: *Machine) void {
    if (culprit.allegiance == .Sauron) {
        return;
    }

    for (machine.props) |maybe_prop| {
        if (maybe_prop) |vent| {
            state.dungeon.atGas(vent.coord)[gas.CausticGas.id] = 1.0;
        }
    }

    state.message(.Trap, "Poisonous gas seeps through the gas vents!", .{});
}

pub fn triggerStairUp(culprit: *Mob, machine: *Machine) void {
    assert(machine.coord.z >= 1);

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

pub fn triggerStairDown(culprit: *Mob, machine: *Machine) void {
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

pub fn triggerGoldCoins(culprit: *Mob, machine: *Machine) void {
    if (!culprit.coord.eq(state.player.coord)) {
        return;
    }

    // FIXME: this is a horrible hack due to machine's lack of state
    state.score += rng.range(usize, 100, 255);
    state.dungeon.at(machine.coord).surface = null;

    state.message(.Aquire, "You now have {} gold.", .{state.score});
}
