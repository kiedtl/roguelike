usingnamespace @import("types.zig");

pub const IronBarricade = Material{
    .name = "iron barricade",
    .description = "TODO",
    .density = 3.0, // FIXME: not accurate!
    .color_fg = 0x272727, // bg of basalt floor
    .color_bg = 0x708070,
    .glyph = '#',
    .melting_point = 700, // FIXME: not accurate
    .combust_point = null,
    .specific_heat = 0.55, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 0.3,
};

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
    .opacity = 1.0,
};
