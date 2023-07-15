// Utility funcs for panicking.
//

const build_options = @import("build_options");
const std = @import("std");

const ui = @import("ui.zig");
const state = @import("state.zig");
const rng = @import("rng.zig");
const sentry = @import("sentry.zig");

pub fn ensure(expr: bool, comptime err_message: []const u8, args: anytype) !void {
    if (!expr) {
        std.log.err("[non-fatal] " ++ err_message, args);
        return error.OhNoes;
    }
}

pub fn bug(comptime fmt: []const u8, args: anytype) noreturn {
    @setCold(true);

    ui.deinit() catch {};
    std.log.err("Fatal bug encountered. (Seed: {})", .{rng.seed});
    std.log.err("BUG: " ++ fmt, args);

    if (!state.sentry_disabled) {
        var membuf: [65535]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);
        var alloc = fba.allocator();

        sentry.captureError(
            build_options.release,
            build_options.dist,
            "Fatal bug",
            std.fmt.allocPrint(alloc, fmt, args) catch unreachable,
            &[_]sentry.SentryEvent.TagSet.Tag{.{
                .name = "seed",
                .value = std.fmt.allocPrint(alloc, "{}", .{rng.seed}) catch unreachable,
            }},
            @errorReturnTrace(),
            @returnAddress(),
            alloc,
        ) catch |err| {
            std.log.err("zig-sentry: Fail: {s}", .{@errorName(err)});
        };
    }

    @panic("Aborting");
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    @setCold(true);

    ui.deinit() catch {};
    std.log.err(fmt, args);

    std.os.abort();
    unreachable;
}

pub fn oom() noreturn {
    @setCold(true);
    @panic("Out of memory! Please close a few browser tabs.");
}

pub fn todo() noreturn {
    @setCold(true);
    @panic("TODO");
}

// Replacement for `unreachable`, since `unreachable` will continue to execute
// in unsafe release modes, which is unacceptable.
//
// Plus it gives the opportunity to print out a goofy message.
pub fn wat() noreturn {
    @setCold(true);
    @panic("Pigs are flying! The sky is falling! Unreachable code entered!");
}
