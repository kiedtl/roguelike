usingnamespace @import("types.zig");

pub const CausticGas = Gas{
    .color = 0xee82ee, // violet
    .dissipation_rate = 0.01,
    .opacity = 0.3,
    .id = 0,
};

pub const SmokeGas = Gas{
    .color = 0xcacbca,
    .dissipation_rate = 0.01,
    .opacity = 1.0,
    .id = 1,
};

// NOTE: the gas' ID *must* match the index number.
pub const Gases = [_]Gas{ CausticGas, SmokeGas };
pub const GAS_NUM: usize = Gases.len;
