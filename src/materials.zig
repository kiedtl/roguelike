usingnamespace @import("types.zig");

pub const Basalt = Material{
    .name = "basalt",
    .description = "TODO",
    .density = 2.9,
    .color_fg = 0x404040,
    .color_bg = 0x948f7f,
    .glyph = '#',
    .melting_point = 983,
    .combust_point = null,
    .specific_heat = 0.84, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Dobalene = Material{
    .name = "dobalene",
    .description = "TODO",
    .density = 2.9,
    .color_fg = 0x2345ff,
    .color_bg = null,
    .glyph = '#',
    .melting_point = 983,
    .combust_point = null,
    .specific_heat = 0.84, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 1.0,
};
