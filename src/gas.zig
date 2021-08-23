const std = @import("std");
const math = std.math;

const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const Poison = Gas{
    .color = 0xa7e234,
    .dissipation_rate = 0.01,
    .opacity = 0.05,
    .trigger = triggerPoison,
    .id = 0,
};

pub const Paralysis = Gas{
    .color = 0xaaaaff,
    .dissipation_rate = 0.05,
    .opacity = 0.03,
    .trigger = triggerParalysis,
    .id = 1,
};

// TODO: rename to Fog
pub const SmokeGas = Gas{
    .color = 0xffffff,
    .dissipation_rate = 0.01,
    .opacity = 0.3,
    .trigger = triggerNone,
    .id = 2,
};

pub const Confusion = Gas{
    .color = 0x33cbca,
    .dissipation_rate = 0.05,
    .opacity = 0.0,
    .trigger = triggerConfusion,
    .id = 3,
};

pub const Slow = Gas{
    .color = 0x8e77dd,
    .dissipation_rate = 0.02,
    .opacity = 0.0,
    .trigger = triggerSlow,
    .id = 4,
};

pub const Healing = Gas{
    .color = 0xbb97aa,
    .dissipation_rate = 0.02,
    .opacity = 0.0,
    .trigger = triggerHealing,
    .id = 5,
};

pub const Dust = Gas{
    .color = 0xd2b48c,
    .dissipation_rate = 0.07,
    .opacity = 0.1,
    .trigger = triggerDust,
    .id = 6,
};

pub const Gases = [_]Gas{ Poison, Paralysis, SmokeGas, Confusion, Slow, Healing, Dust };
pub const GAS_NUM: usize = Gases.len;

// Ensure that each gas's ID matches the index that it appears as in Gases.
comptime {
    for (&Gases) |gas, i|
        if (i != gas.id) @compileError("Gas's ID doesn't match index");
}

fn triggerNone(_: *Mob, __: f64) void {}

fn triggerPoison(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Poison, 0, Status.MAX_DURATION, false);
}

fn triggerParalysis(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Paralysis, 0, Status.MAX_DURATION, false);
}

fn triggerConfusion(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Confusion, 0, Status.MAX_DURATION, false);
}

fn triggerSlow(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Slow, 0, Status.MAX_DURATION, false);
}

fn triggerHealing(mob: *Mob, quantity: f64) void {
    mob.HP *= 1.1 * (quantity + 1.0);
    mob.HP = math.clamp(mob.HP, 0, mob.max_HP);
}

fn triggerDust(mob: *Mob, quantity: f64) void {}
