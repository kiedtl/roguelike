usingnamespace @import("types.zig");

pub const CausticGas = Gas{
    .color = 0xee82ee, // violet
    .dissipation_rate = 0.01,
    .opacity = 1.0,
};

pub const SmokeGas = Gas{
    .color = 0xcacbca,
    .dissipation_rate = 0.01,
    .opacity = 1.0,
};

pub const Gases = [_]Gas{ CausticGas, SmokeGas };
pub const GAS_NUM: usize = Gases.len;
