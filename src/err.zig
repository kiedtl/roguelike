// Utility funcs for panicking.
//

const std = @import("std");

pub fn bug(comptime fmt: []const u8, args: anytype) noreturn {
    std.log.err("BUG: " ++ fmt, args);
    @panic("Exiting.");
}

pub fn oom() noreturn {
    @panic("Out of memory! Please close a few browser tabs.");
}

pub fn todo() noreturn {
    @panic("TODO");
}

// Replacement for `unreachable`, since `unreachable` will continue to execute
// in release modes.
pub fn wat() noreturn {
    @panic("Pigs are flying! The sky is falling! Unreachable code entered!");
}
