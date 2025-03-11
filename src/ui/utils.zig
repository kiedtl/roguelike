// Used to deduplicate code in HUD and drawPlayerInfoScreen
//
// A bit idiosyncratic...

const std = @import("std");
const assert = std.debug.assert;
const fmt = std.fmt;
const mem = std.mem;

const state = @import("../state.zig");
const surfaces = @import("../surfaces.zig");
const err = @import("../err.zig");

pub const HolinessFormatter = struct {
    pub fn dewIt(self: @This()) bool {
        return self.getHoliness() < 0;
    }

    pub fn format(self: *const @This(), comptime f: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        if (comptime !mem.eql(u8, f, "")) @compileError("Unknown format string: '" ++ f ++ "'");

        if (self.dewIt()) {
            const val = self.getHoliness();
            const str = if (val < 0) "$r$~ UNCLEAN $." else err.wat();
            const clr = if (val < 0) 'p' else err.wat();
            try fmt.format(writer, "$cHoliness: $. ${u}{} {s}\n", .{ clr, val, str });
        }
    }

    fn getHoliness(_: *const @This()) isize {
        return state.player.resistance(.rHoly);
    }
};

pub const ReputationFormatter = struct {
    pub fn dewIt(_: @This()) bool {
        const rep = state.night_rep[@intFromEnum(state.player.faction)];
        return rep != 0 or state.player.isOnSlade();
    }

    pub fn format(self: *const @This(), comptime f: []const u8, _: fmt.FormatOptions, writer: anytype) !void {
        if (comptime !mem.eql(u8, f, "")) @compileError("Unknown format string: '" ++ f ++ "'");

        const rep = state.night_rep[@intFromEnum(state.player.faction)];

        if (self.dewIt()) {
            const str = if (rep == 0) "$g$~ NEUTRAL $." else if (rep > 0) "$a$~ FRIENDLY $." else if (rep >= -5) "$p$~ DISLIKED $." else "$r$~ HATED $.";
            if (state.player.isOnSlade() and rep < 1) {
                try fmt.format(writer, "$cNight rep:$. {} $r$~ TRESPASSING $.\n", .{rep});
            } else {
                try fmt.format(writer, "$cNight rep:$. {} {s}\n", .{ rep, str });
            }
        }
    }
};
