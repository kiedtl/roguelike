usingnamespace @import("types.zig");

pub const EcholocationRing = Ring{
    .name = "echolocation",
    .status = .Echolocation,
    .status_start_power = 10,
    .status_max_power = 25,
    .status_power_increase = 10,
};
