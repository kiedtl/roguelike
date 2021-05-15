const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const AlarmTrap = Machine{
    .name = "alarm trap",
    .tile = '^',
    .walkable = true,
    .opacity = 0.0,
    .on_trigger = triggerAlarmTrap,
};

pub const NormalDoor = Machine{
    .name = "door",
    .tile = '+', // TODO: red background?
    .walkable = true,
    .opacity = 1.0,
    .on_trigger = triggerNone,
};

pub fn triggerNone(_: *Mob, __: *Machine) void {}

pub fn triggerAlarmTrap(culprit: *Mob, machine: *Machine) void {
    if (culprit.allegiance == .Sauron) {
        return;
    }

    culprit.noise += 1000; // muahahaha
}
