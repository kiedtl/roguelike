const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const CausticGas = Gas{
    .color = 0xee82ee, // violet
    .dissipation_rate = 0.01,
    .opacity = 0.3,
    .trigger = triggerCaustic,
    .id = 0,
};

pub const SmokeGas = Gas{
    .color = 0xcacbca,
    .dissipation_rate = 0.01,
    .opacity = 1.0,
    .trigger = triggerNone,
    .id = 1,
};

// NOTE: the gas' ID *must* match the index number.
pub const Gases = [_]Gas{ CausticGas, SmokeGas };
pub const GAS_NUM: usize = Gases.len;

fn triggerNone(_: *Mob, __: f64) void {}

fn triggerCaustic(idiot: *Mob, quantity: f64) void {
    idiot.pain += 0.14 * quantity;
    idiot.HP *= 0.91;

    if (idiot.coord.eq(state.player.coord)) {
        state.message(.Damage, "You choke on the poisonous gas.", .{});
    }
}
