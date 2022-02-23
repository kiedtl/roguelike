usingnamespace @import("types.zig");
const state = @import("state.zig");

pub const PolishedGlass = Material{
    .name = "polished glass",
    .description = "TODO",
    .density = 5.3, // FIXME: not accurate!
    .color_fg = 0x90a3b7,
    .color_bg = null,
    .color_floor = 0x677ba3,
    .tileset = 2,
    .melting_point = 1383, // FIXME: not accurate!
    .combust_point = null, // FIXME: not accurate!
    .specific_heat = 500, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 0.3,
};

pub const Glass = Material{
    .name = "glass",
    .description = "TODO",
    .density = 5.3, // FIXME: not accurate!
    .color_fg = 0x677ba3,
    .color_bg = 0x90a3b7,
    .color_floor = 0x677ba3,
    .tileset = 0,
    .melting_point = 1383, // FIXME: not accurate!
    .combust_point = null, // FIXME: not accurate!
    .specific_heat = 500, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 0.1,
};

pub const Hematite = Material{
    .name = "hematite",
    .description = "TODO",
    .density = 5.3,
    .color_fg = 0x802020,
    .color_bg = 0xd2d2d2,
    .color_floor = 0x802020,
    .tileset = 0,
    .melting_point = 1383,
    .combust_point = null,
    .smelt_result = &Iron,
    .specific_heat = 500, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Iron = Material{
    .name = "iron",
    .description = "TODO",
    .type = .Metal,
    .density = 5.3, // FIXME: not accurate!
    .color_fg = 0xcacbca,
    .color_bg = 0xefefef,
    .color_floor = 0xcacbca,
    .tileset = 0,
    .melting_point = 1383, // FIXME: not accurate!
    .combust_point = null,
    .specific_heat = 500, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 1.0,
};

// TODO: realgar, change this material to the stone realgar is found in
pub const Basalt = Material{
    .name = "basalt",
    .description = "TODO",
    .density = 2.9,
    .color_fg = 0x505050,
    .color_bg = 0x9e9e9e,
    .color_floor = 0x9e9e9e,
    .tileset = 0,
    .melting_point = 1262, // average of 1175°C and 1350°C
    .combust_point = null,
    .specific_heat = 840, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Talonium = Material{
    .name = "talonium",
    .description = "TODO",
    .density = 0.82, // TODO
    .color_fg = 0xff9390,
    .color_bg = null,
    .color_floor = 0xff9390,
    .tileset = 1,
    .melting_point = 1128, // TODO
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Sulon = Material{
    .name = "sulon",
    .description = "TODO",
    .density = 0.82, // TODO
    .color_fg = 0x79d28f,
    .color_bg = null,
    .color_floor = 0x79d28f,
    .tileset = 1,
    .melting_point = 1128, // TODO
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Phosire = Material{
    .name = "phosire",
    .description = "TODO",
    .density = 0.82, // TODO
    .color_fg = 0xffb6ac,
    .color_bg = null,
    .color_floor = 0xffb6ac,
    .tileset = 1,
    .melting_point = 1128, // TODO
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Hyalt = Material{
    .name = "hyalt",
    .description = "TODO",
    .density = 0.82, // TODO
    .color_fg = 0x50ff2e,
    .color_bg = null,
    .color_floor = 0x50ff2e,
    .tileset = 1,
    .melting_point = 1128, // TODO
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Quaese = Material{
    .name = "quaese",
    .description = "TODO",
    .density = 0.82, // TODO
    .color_fg = 0xff81f1,
    .color_bg = null,
    .color_floor = 0xff81f1,
    .tileset = 1,
    .melting_point = 1128, // TODO
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Catasine = Material{
    .name = "catasine",
    .description = "TODO",
    .density = 0.82, // TODO
    .color_fg = 0xf2a2b8,
    .color_bg = null,
    .color_floor = 0xf2a2b8,
    .tileset = 1,
    .melting_point = 1128, // TODO
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Phybro = Material{
    .name = "phybro",
    .description = "TODO",
    .density = 0.82, // TODO
    .color_fg = 0xf2c088,
    .color_bg = null,
    .color_floor = 0xf2c088,
    .tileset = 1,
    .melting_point = 1128, // TODO
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Vangenite = Material{
    .name = "vangenite",
    .description = "TODO",
    .density = 1.8,
    .color_fg = 0xb6efe0,
    .color_bg = null,
    .color_floor = 0xb6efe0,
    .tileset = 1,
    .melting_point = 1128,
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 40,
    .opacity = 1.0,
};

pub const Dobalene = Material{
    .name = "dobalene",
    .description = "TODO",
    .density = 2.3,
    .color_fg = 0xb5d0ff,
    .color_bg = null,
    .color_floor = 0xb5d0ff,
    .tileset = 1,
    .melting_point = 876,
    .combust_point = null,
    .specific_heat = 910, // TODO
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Concrete = Material{
    .name = "concrete",
    .description = "TODO",
    .density = 2.78, // not accurate
    .color_fg = 0x404040,
    .color_bg = 0x968f74,
    .color_floor = 0xa79f85,
    .tileset = 0,
    .melting_point = 825, // not accurate
    .combust_point = null,
    .specific_heat = 910, // not accurate
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Limestone = Material{
    .name = "limestone",
    .description = "TODO",
    .density = 2.78, // not accurate
    .color_fg = 0x45455f,
    .color_bg = 0xffffef,
    .color_floor = 0xffffef,
    .tileset = 0,
    .melting_point = 825, // not accurate
    .combust_point = null,
    .specific_heat = 910, // not accurate
    .luminescence = 0,
    .opacity = 1.0,
};

const Pattern = struct { p: []const u8, t: [3]u21 };

const PATTERNS = [_]Pattern{
    //###
    //###
    //###
    .{ .p = "#########", .t = .{ '#', '#', '#' } },

    //.#.
    //###
    //.#.
    .{ .p = ".#.###.#.", .t = .{ '#', '╋', '#' } },

    //???
    //###
    //.#.
    .{ .p = "???###.#.", .t = .{ '#', '┳', '#' } },
    //?.?
    //###
    //.##
    .{ .p = "?.?###.##", .t = .{ '#', '┳', '#' } },
    //?.?
    //###
    //##.
    .{ .p = "?.?#####.", .t = .{ '#', '┳', '#' } },
    //.#.
    //###
    //???
    .{ .p = ".#.###???", .t = .{ '#', '┻', '#' } },
    //##.
    //###
    //?.?
    .{ .p = "##.###?.?", .t = .{ '#', '┻', '#' } },
    //.##
    //###
    //?.?
    .{ .p = ".#####?.?", .t = .{ '#', '┻', '#' } },
    //?#.
    //?##
    //?#.
    .{ .p = "?#.?##?#.", .t = .{ '#', '┣', '#' } },
    //?##
    //.##
    //?#.
    .{ .p = "?##.##?#.", .t = .{ '#', '┣', '#' } },
    //?#.
    //.##
    //?##
    .{ .p = "?#..##?##", .t = .{ '#', '┣', '#' } },
    //.#?
    //##?
    //.#?
    .{ .p = ".#?##?.#?", .t = .{ '#', '┫', '#' } },
    //##?
    //##.
    //.#?
    .{ .p = "##?##..#?", .t = .{ '#', '┫', '#' } },
    //.#?
    //##.
    //##?
    .{ .p = ".#?##.##?", .t = .{ '#', '┫', '#' } },

    //..?
    //.##
    //?#?
    .{ .p = "..?.##?#?", .t = .{ '#', '┏', '#' } },
    //?..
    //##.
    //?#?
    .{ .p = "?..##.?#?", .t = .{ '#', '┓', '#' } },
    //?#?
    //.##
    //..?
    .{ .p = "?#?.##..?", .t = .{ '#', '┗', '#' } },
    //?#?
    //##.
    //?..
    .{ .p = "?#?##.?..", .t = .{ '#', '┛', '#' } },

    //???
    //?##
    //?#.
    .{ .p = "????##?#.", .t = .{ '#', '┏', '#' } },
    //???
    //##?
    //.#?
    .{ .p = "???##?.#?", .t = .{ '#', '┓', '#' } },
    //?#.
    //?##
    //???
    .{ .p = "?#.?##???", .t = .{ '#', '┗', '#' } },
    //.#?
    //##?
    //???
    .{ .p = ".#?##????", .t = .{ '#', '┛', '#' } },

    //?#?
    //.#.
    //...
    .{ .p = "?#?.#....", .t = .{ '#', '┃', '┋' } },
    //...
    //.#.
    //?#?
    .{ .p = "....#.?#?", .t = .{ '#', '┃', '┋' } },

    //##?
    //##.
    //##?
    .{ .p = "##?##.##?", .t = .{ '#', '┃', '┋' } },
    //?##
    //.##
    //?##
    .{ .p = "?##.##?##", .t = .{ '#', '┃', '┋' } },
    //?#?
    //.#.
    //?#?
    .{ .p = "?#?.#.?#?", .t = .{ '#', '┃', '┋' } },

    //###
    //###
    //?.?
    .{ .p = "######?.?", .t = .{ '#', '━', '┅' } },
    //?.?
    //###
    //###
    .{ .p = "?.?######", .t = .{ '#', '━', '┅' } },
    //?.?
    //###
    //?.?
    .{ .p = "?.?###?.?", .t = .{ '#', '━', '┅' } },

    //?..
    //##.
    //?..
    .{ .p = "?..##.?..", .t = .{ '#', '━', '┅' } },
    //..?
    //.##
    //..?
    .{ .p = "..?.##..?", .t = .{ '#', '━', '┅' } },
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
