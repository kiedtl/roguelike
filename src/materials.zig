usingnamespace @import("types.zig");

pub const Basalt = Material{
    .name = "basalt",
    .description = "TODO",
    .density = 2.9,
    .color_fg = 0x505050,
    .color_bg = 0x9e9e9e,
    .glyph = '#',
    .melting_point = 1257,
    .combust_point = null,
    .specific_heat = 0.84, // FIXME: not accurate!
    .luminescence = 0,
};
