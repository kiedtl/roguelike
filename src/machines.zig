usingnamespace @import("types.zig");

pub const AlarmTrap = Machine{
    .name = "alarm trap",
    .tile = '^',
    .walkable = false,
    .coord = Coord.new(0, 0),
    .on_trigger = triggerAlarmTrap,
    .props = [_]?Prop{null} ** 40,
};

pub fn triggerNone(_: *Mob, __: *Machine) void {}

pub fn triggerAlarmTrap(culprit: *Mob, machine: *Machine) void {
    culprit.noise += 1000; // muahahaha
}
