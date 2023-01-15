const types = @import("types.zig");
const state = @import("state.zig");
const colors = @import("colors.zig");

const Material = types.Material;
const Coord = types.Coord;

pub const MATERIALS = [_]*const Material{
    &Iron,
    &Vangenite,
    &PaintedConcrete,
    &Marble,
    &Gold,
    &Slade,
};

pub const PaintedConcrete = Material{
    .id = "painted_concrete",
    .name = "painted concrete",
    .color_fg = 0x77440f, //colors.COPPER_RED,
    .color_bg = 0xbb7711, //colors.percentageOf(colors.DOBALENE_BLUE, 40),
    .color_floor = colors.DOBALENE_BLUE,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Marble = Material{
    .id = "marble",
    .name = "marble",
    //.color_fg = 0xcacaca,
    .color_fg = 0xffffff,
    .color_bg = null,
    .color_floor = 0xcacbca,
    .sprite = .S_G_Wall_Polished,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Gold = Material{
    .id = "gold",
    .name = "gold",
    //.color_fg = colors.percentageOf(colors.GOLD, 40),
    .color_fg = colors.percentageOf(colors.GOLD, 80),
    .color_bg = null,
    .color_floor = colors.percentageOf(colors.GOLD, 40),
    .sprite = .S_G_Wall_Polished,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Slade = Material{
    .name = "slade",
    .color_fg = 0x664488,
    .color_bg = null,
    .color_floor = 0x9e9e9e,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 0.9,
};

pub const Rust = Material{
    .name = "rust",
    .color_fg = 0x0,
    .color_bg = colors.COPPER_RED,
    .color_floor = 0x0,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const LabGlass = Material{
    .id = "lab_glass",
    .name = "colored glass",
    .color_fg = 0xffd700,
    .color_bg = null,
    .color_floor = 0xffd700,
    .sprite = .S_G_Wall_Window2,
    .tileset = 3,
    .luminescence = 0,
    .opacity = 0.3,
};

pub const Glass = Material{
    .name = "glass",
    .color_fg = 0x677ba3,
    .color_bg = 0x90a3b7,
    .color_floor = 0x677ba3,
    .sprite = .S_G_Wall_Window,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 0.1,
};

pub const Hematite = Material{
    .name = "hematite",
    .color_fg = 0x802020,
    .color_bg = 0xd2d2d2,
    .color_floor = 0x802020,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Iron = Material{
    .name = "iron",
    .type = .Metal,
    .color_fg = 0xcacbca,
    .color_bg = 0xefefef,
    .color_floor = 0xcacbca,
    .tileset = 0,
    .floor_tile = '+',
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Basalt = Material{
    .name = "basalt",
    .color_fg = 0x505050,
    .color_bg = 0x9e9e9e,
    .color_floor = 0x9e9e9e,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Talonium = Material{
    .name = "talonium",
    .color_fg = 0xff9390,
    .color_bg = null,
    .color_floor = 0xff9390,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Sulon = Material{
    .name = "sulon",
    .color_fg = 0x79d28f,
    .color_bg = null,
    .color_floor = 0x79d28f,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Phosire = Material{
    .name = "phosire",
    .color_fg = 0xffb6ac,
    .color_bg = null,
    .color_floor = 0xffb6ac,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Hyalt = Material{
    .name = "hyalt",
    .color_fg = 0x50ff2e,
    .color_bg = null,
    .color_floor = 0x50ff2e,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Quaese = Material{
    .name = "quaese",
    .color_fg = 0xff81f1,
    .color_bg = null,
    .color_floor = 0xff81f1,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Catasine = Material{
    .name = "catasine",
    .color_fg = 0xf2a2b8,
    .color_bg = null,
    .color_floor = 0xf2a2b8,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Phybro = Material{
    .name = "phybro",
    .color_fg = 0xf2c088,
    .color_bg = null,
    .color_floor = 0xf2c088,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Vangenite = Material{
    .id = "vangenite",
    .name = "vangenite",
    .color_fg = 0xe0f8f2, //0xb6efe0,
    .color_bg = null,
    .color_floor = 0xb6efe0,
    .tileset = 2,
    .luminescence = 40,
    .opacity = 1.0,
};

pub const Dobalene = Material{
    .name = "dobalene",
    .color_fg = colors.DOBALENE_BLUE,
    .color_bg = null,
    .color_floor = 0xb5d0ff,
    .sprite = .S_G_Wall_Scifish,
    .tileset = 1,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Concrete = Material{
    .name = "concrete",
    .color_fg = 0x303030,
    .color_bg = colors.CONCRETE,
    .sprite = .S_G_Wall_Finished,
    .color_sfg = colors.CONCRETE,
    .color_sbg = colors.BG,
    .color_floor = 0xa79f85,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Limestone = Material{
    .name = "limestone",
    .color_fg = 0x45455f,
    .color_bg = 0xffffef,
    .color_floor = 0xffffef,
    .tileset = 0,
    .luminescence = 0,
    .opacity = 1.0,
};

const Pattern = struct { p: []const u8, t: [5]u21 };

const PATTERNS = [_]Pattern{
    //###
    //###
    //###
    .{ .p = "#########", .t = .{ '#', '#', '#', '#', '#' } },

    //.#.
    //###
    //.#.
    .{ .p = ".#.###.#.", .t = .{ '#', '╋', '┼', '#', '╬' } },

    //???
    //###
    //.#.
    .{ .p = "???###.#.", .t = .{ '#', '┳', '┬', '#', '╦' } },
    //?.?
    //###
    //.##
    .{ .p = "?.?###.##", .t = .{ '#', '┳', '┬', '#', '╦' } },
    //?.?
    //###
    //##.
    .{ .p = "?.?#####.", .t = .{ '#', '┳', '┬', '#', '╦' } },
    //.#.
    //###
    //???
    .{ .p = ".#.###???", .t = .{ '#', '┻', '┴', '#', '╩' } },
    //##.
    //###
    //?.?
    .{ .p = "##.###?.?", .t = .{ '#', '┻', '┴', '#', '╩' } },
    //.##
    //###
    //?.?
    .{ .p = ".#####?.?", .t = .{ '#', '┻', '┴', '#', '╩' } },
    //?#.
    //?##
    //?#.
    .{ .p = "?#.?##?#.", .t = .{ '#', '┣', '├', '#', '╠' } },
    //?##
    //.##
    //?#.
    .{ .p = "?##.##?#.", .t = .{ '#', '┣', '├', '#', '╠' } },
    //?#.
    //.##
    //?##
    .{ .p = "?#..##?##", .t = .{ '#', '┣', '├', '#', '╠' } },
    //.#?
    //##?
    //.#?
    .{ .p = ".#?##?.#?", .t = .{ '#', '┫', '┤', '#', '╣' } },
    //##?
    //##.
    //.#?
    .{ .p = "##?##..#?", .t = .{ '#', '┫', '┤', '#', '╣' } },
    //.#?
    //##.
    //##?
    .{ .p = ".#?##.##?", .t = .{ '#', '┫', '┤', '#', '╣' } },

    //..?
    //.##
    //?#?
    .{ .p = "..?.##?#?", .t = .{ '#', '┏', '┌', '#', '╔' } },
    //?..
    //##.
    //?#?
    .{ .p = "?..##.?#?", .t = .{ '#', '┓', '┐', '#', '╗' } },
    //?#?
    //.##
    //..?
    .{ .p = "?#?.##..?", .t = .{ '#', '┗', '└', '#', '╚' } },
    //?#?
    //##.
    //?..
    .{ .p = "?#?##.?..", .t = .{ '#', '┛', '┘', '#', '╝' } },

    //???
    //?##
    //?#.
    .{ .p = "????##?#.", .t = .{ '#', '┏', '┌', '#', '╔' } },
    //???
    //##?
    //.#?
    .{ .p = "???##?.#?", .t = .{ '#', '┓', '┐', '#', '╗' } },
    //?#.
    //?##
    //???
    .{ .p = "?#.?##???", .t = .{ '#', '┗', '└', '#', '╚' } },
    //.#?
    //##?
    //???
    .{ .p = ".#?##????", .t = .{ '#', '┛', '┘', '#', '╝' } },

    //?#?
    //.#.
    //...
    .{ .p = "?#?.#....", .t = .{ '#', '┃', '│', '┋', '║' } },
    //...
    //.#.
    //?#?
    .{ .p = "....#.?#?", .t = .{ '#', '┃', '│', '┋', '║' } },

    //##?
    //##.
    //##?
    .{ .p = "##?##.##?", .t = .{ '#', '┃', '│', '┋', '║' } },
    //?##
    //.##
    //?##
    .{ .p = "?##.##?##", .t = .{ '#', '┃', '│', '┋', '║' } },
    //?#?
    //.#.
    //?#?
    .{ .p = "?#?.#.?#?", .t = .{ '#', '┃', '│', '┋', '║' } },

    //###
    //###
    //?.?
    .{ .p = "######?.?", .t = .{ '#', '━', '─', '┅', '═' } },
    //?.?
    //###
    //###
    .{ .p = "?.?######", .t = .{ '#', '━', '─', '┅', '═' } },
    //?.?
    //###
    //?.?
    .{ .p = "?.?###?.?", .t = .{ '#', '━', '─', '┅', '═' } },

    //?..
    //##.
    //?..
    .{ .p = "?..##.?..", .t = .{ '#', '━', '─', '┅', '═' } },
    //..?
    //.##
    //..?
    .{ .p = "..?.##..?", .t = .{ '#', '━', '─', '┅', '═' } },
};

// TODO: merge with utils.findPatternMatch()
pub fn tileFor(coord: Coord, tileset: usize) u21 {
    const coords = [_]?Coord{
        coord.move(.NorthWest, state.mapgeometry),
        coord.move(.North, state.mapgeometry),
        coord.move(.NorthEast, state.mapgeometry),
        coord.move(.West, state.mapgeometry),
        coord,
        coord.move(.East, state.mapgeometry),
        coord.move(.SouthWest, state.mapgeometry),
        coord.move(.South, state.mapgeometry),
        coord.move(.SouthEast, state.mapgeometry),
    };

    patterns: for (&PATTERNS) |pattern| {
        var i: usize = 0;
        while (i < 9) : (i += 1) {
            if (pattern.p[i] == '?') continue;

            const tiletype = if (coords[i]) |c| state.dungeon.at(c).type else .Wall;
            const typech: u21 = if (tiletype == .Floor) '.' else '#';
            if (typech != pattern.p[i]) continue :patterns;
        }

        // we have a match if we haven't continued to the next iteration
        // by this point
        return pattern.t[tileset];
    }

    // we don't have a match, return the default
    return PATTERNS[0].t[tileset];
}
