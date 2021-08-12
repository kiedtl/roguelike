usingnamespace @import("types.zig");
const state = @import("state.zig");

// TODO: realgar, change this material to the stone realgar is found in
pub const Basalt = Material{
    .name = "basalt",
    .description = "TODO",
    .density = 2.9,
    .color_fg = 0x505050,
    .color_bg = 0x9e9e9e,
    .color_floor = 0x9e9e9e,
    .tileset = 0,
    .melting_point = 983,
    .combust_point = null,
    .specific_heat = 0.84, // FIXME: not accurate!
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Dobalene = Material{
    .name = "dobalene",
    .description = "TODO",
    .density = 2.3,
    .color_fg = 0x89abff,
    .color_bg = null,
    .color_floor = 0xabcdff,
    .tileset = 1,
    .melting_point = 8219,
    .combust_point = null,
    .specific_heat = 0.91,
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
    .specific_heat = 0.91, // not accurate
    .luminescence = 0,
    .opacity = 1.0,
};

pub const Marble = Material{
    .name = "marble",
    .description = "TODO",
    .density = 2.78,
    .color_fg = 0xffffff,
    .color_bg = null,
    .color_floor = 0xfafafa,
    .tileset = 2,
    .melting_point = 825,
    .combust_point = null,
    .specific_heat = 0.91, // not accurate
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
    .{ .p = ".#.###.#.", .t = .{ '#', '╋', '█' } },

    //???
    //###
    //.#.
    .{ .p = "???###.#.", .t = .{ '#', '┳', '█' } },
    //?.?
    //###
    //.##
    .{ .p = "?.?###.##", .t = .{ '#', '┳', '█' } },
    //?.?
    //###
    //##.
    .{ .p = "?.?#####.", .t = .{ '#', '┳', '█' } },
    //.#.
    //###
    //???
    .{ .p = ".#.###???", .t = .{ '#', '┻', '█' } },
    //##.
    //###
    //?.?
    .{ .p = "##.###?.?", .t = .{ '#', '┻', '█' } },
    //.##
    //###
    //?.?
    .{ .p = ".#####?.?", .t = .{ '#', '┻', '█' } },
    //?#.
    //?##
    //?#.
    .{ .p = "?#.?##?#.", .t = .{ '#', '┣', '█' } },
    //?##
    //.##
    //?#.
    .{ .p = "?##.##?#.", .t = .{ '#', '┣', '█' } },
    //?#.
    //.##
    //?##
    .{ .p = "?#..##?##", .t = .{ '#', '┣', '█' } },
    //.#?
    //##?
    //.#?
    .{ .p = ".#?##?.#?", .t = .{ '#', '┫', '█' } },
    //##?
    //##.
    //.#?
    .{ .p = "##?##..#?", .t = .{ '#', '┫', '█' } },
    //.#?
    //##.
    //##?
    .{ .p = ".#?##.##?", .t = .{ '#', '┫', '█' } },

    //..?
    //.##
    //?#?
    .{ .p = "..?.##?#?", .t = .{ '#', '┏', '█' } },
    //?..
    //##.
    //?#?
    .{ .p = "?..##.?#?", .t = .{ '#', '┓', '█' } },
    //?#?
    //.##
    //..?
    .{ .p = "?#?.##..?", .t = .{ '#', '┗', '█' } },
    //?#?
    //##.
    //?..
    .{ .p = "?#?##.?..", .t = .{ '#', '┛', '█' } },

    //???
    //?##
    //?#.
    .{ .p = "????##?#.", .t = .{ '#', '┏', '█' } },
    //???
    //##?
    //.#?
    .{ .p = "???##?.#?", .t = .{ '#', '┓', '█' } },
    //?#.
    //?##
    //???
    .{ .p = "?#.?##???", .t = .{ '#', '┗', '█' } },
    //.#?
    //##?
    //???
    .{ .p = ".#?##????", .t = .{ '#', '┛', '█' } },

    //?#?
    //.#.
    //...
    .{ .p = "?#?.#....", .t = .{ '#', '┃', '█' } },
    //...
    //.#.
    //?#?
    .{ .p = "....#.?#?", .t = .{ '#', '┃', '█' } },

    //##?
    //##.
    //##?
    .{ .p = "##?##.##?", .t = .{ '#', '┃', '█' } },
    //?##
    //.##
    //?##
    .{ .p = "?##.##?##", .t = .{ '#', '┃', '█' } },
    //?#?
    //.#.
    //?#?
    .{ .p = "?#?.#.?#?", .t = .{ '#', '┃', '█' } },

    //###
    //###
    //?.?
    .{ .p = "######?.?", .t = .{ '#', '━', '█' } },
    //?.?
    //###
    //###
    .{ .p = "?.?######", .t = .{ '#', '━', '█' } },
    //?.?
    //###
    //?.?
    .{ .p = "?.?###?.?", .t = .{ '#', '━', '█' } },

    //?..
    //##.
    //?..
    .{ .p = "?..##.?..", .t = .{ '#', '━', '█' } },
    //..?
    //.##
    //..?
    .{ .p = "..?.##..?", .t = .{ '#', '━', '█' } },
};

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
