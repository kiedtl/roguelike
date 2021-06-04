const std = @import("std");
const math = std.math;

const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const Poison = Gas{
    .color = 0xa7e234,
    .dissipation_rate = 0.01,
    .opacity = 0.3,
    .trigger = triggerPoison,
    .id = 0,
};

pub const Paralysis = Gas{
    .color = 0xffffff,
    .dissipation_rate = 0.05,
    .opacity = 0.2,
    .trigger = triggerParalysis,
    .id = 1,
};

pub const SmokeGas = Gas{
    .color = 0xffffff,
    .dissipation_rate = 0.01,
    .opacity = 1.0,
    .trigger = triggerNone,
    .id = 2,
};

pub const Gases = [_]Gas{ Poison, Paralysis, SmokeGas };
pub const GAS_NUM: usize = Gases.len;

// Ensure that each gas's ID matches the index that it appears as in Gases.
comptime {
    for (&Gases) |gas, i|
        if (i != gas.id) @compileError("Gas's ID doesn't match index");
}

fn triggerNone(_: *Mob, __: f64) void {}

fn triggerPoison(idiot: *Mob, quantity: f64) void {
    idiot.takeDamage(.{ .amount = idiot.HP * 0.11 });

    if (idiot.coord.eq(state.player.coord)) {
        state.message(.Damage, "You choke on the poisonous gas.", .{});
    }
}

fn triggerParalysis(idiot: *Mob, quantity: f64) void {
    idiot.addStatus(.Paralysis, 0);
}
