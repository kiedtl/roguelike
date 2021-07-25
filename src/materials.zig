usingnamespace @import("types.zig");
const state = @import("state.zig");

pub const Basalt = Material{
    .name = "basalt",
    .description = "TODO",
    .density = 2.9,
    .color_fg = 0x404040,
    .color_bg = 0x948f7f,
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
    .tileset = 1,
    .melting_point = 1229,
    .combust_point = null,
    .specific_heat = 0.91,
    .luminescence = 0,
    .opacity = 1.0,
};

const Pattern = struct { p: []const u8, t: [2]u21 };

const PATTERNS = [_]Pattern{
    //###
    //###
    //###
    .{ .p = "#########", .t = .{ '#', '#' } },

    //.#.
    //###
    //.#.
    .{ .p = ".#.###.#.", .t = .{ '#', '╋' } },

    //???
    //###
    //.#.
    .{ .p = "???###.#.", .t = .{ '#', '┳' } },
    //?.?
    //###
    //.##
    .{ .p = "?.?###.##", .t = .{ '#', '┳' } },
    //?.?
    //###
    //##.
    .{ .p = "?.?#####.", .t = .{ '#', '┳' } },
    //.#.
    //###
    //???
    .{ .p = ".#.###???", .t = .{ '#', '┻' } },
    //##.
    //###
    //?.?
    .{ .p = "##.###?.?", .t = .{ '#', '┻' } },
    //.##
    //###
    //?.?
    .{ .p = ".#####?.?", .t = .{ '#', '┻' } },
    //?#.
    //?##
    //?#.
    .{ .p = "?#.?##?#.", .t = .{ '#', '┣' } },
    //?##
    //.##
    //?#.
    .{ .p = "?##.##?#.", .t = .{ '#', '┣' } },
    //?#.
    //.##
    //?##
    .{ .p = "?#..##?##", .t = .{ '#', '┣' } },
    //.#?
    //##?
    //.#?
    .{ .p = ".#?##?.#?", .t = .{ '#', '┫' } },
    //##?
    //##.
    //.#?
    .{ .p = "##?##..#?", .t = .{ '#', '┫' } },
    //.#?
    //##.
    //##?
    .{ .p = ".#?##.##?", .t = .{ '#', '┫' } },

    //..?
    //.##
    //?#?
    .{ .p = "..?.##?#?", .t = .{ '#', '┏' } },
    //?..
    //##.
    //?#?
    .{ .p = "?..##.?#?", .t = .{ '#', '┓' } },
    //?#?
    //.##
    //..?
    .{ .p = "?#?.##..?", .t = .{ '#', '┗' } },
    //?#?
    //##.
    //?..
    .{ .p = "?#?##.?..", .t = .{ '#', '┛' } },

    //???
    //?##
    //?#.
    .{ .p = "????##?#.", .t = .{ '#', '┏' } },
    //???
    //##?
    //.#?
    .{ .p = "???##?.#?", .t = .{ '#', '┓' } },
    //?#.
    //?##
    //???
    .{ .p = "?#.?##???", .t = .{ '#', '┗' } },
    //.#?
    //##?
    //???
    .{ .p = ".#?##????", .t = .{ '#', '┛' } },

    //?#?
    //.#.
    //...
    .{ .p = "?#?.#....", .t = .{ '#', '┃' } },
    //...
    //.#.
    //?#?
    .{ .p = "....#.?#?", .t = .{ '#', '┃' } },

    //##?
    //##.
    //##?
    .{ .p = "##?##.##?", .t = .{ '#', '┃' } },
    //?##
    //.##
    //?##
    .{ .p = "?##.##?##", .t = .{ '#', '┃' } },
    //?#?
    //.#.
    //?#?
    .{ .p = "?#?.#.?#?", .t = .{ '#', '┃' } },

    //###
    //###
    //?.?
    .{ .p = "######?.?", .t = .{ '#', '━' } },
    //?.?
    //###
    //###
    .{ .p = "?.?######", .t = .{ '#', '━' } },
    //?.?
    //###
    //?.?
    .{ .p = "?.?###?.?", .t = .{ '#', '━' } },

    //?..
    //##.
    //?..
    .{ .p = "?..##.?..", .t = .{ '#', '━' } },
    //..?
    //.##
    //..?
    .{ .p = "..?.##..?", .t = .{ '#', '━' } },
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
