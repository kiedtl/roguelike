// Utility funcs for panicking.
//

const build_options = @import("build_options");
const std = @import("std");

const ui = @import("ui.zig");
const state = @import("state.zig");

pub fn ensure(expr: bool, comptime err_message: []const u8, args: anytype) !void {
    if (!expr) {
        state.message(.Info, "[Error] A bug occurred, send the game log to kiedtl.", .{});
        std.log.err("[non-fatal] " ++ err_message, args);
        return error.OhNoes;
    }
}

pub fn bug(comptime fmt: []const u8, args: anytype) noreturn {
    @branchHint(.cold);

    // ui.deinit() catch {}; // Panic already deinits UI
    std.log.err("Fatal bug encountered. (Seed: {})", .{state.seed});
    std.log.err("BUG: " ++ fmt, args);

    if (comptime @import("builtin").os.tag != .windows) {
        if (!state.sentry_disabled) {
            const sentry = @import("sentry.zig");
            var membuf: [65535]u8 = undefined;
            var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);
            const alloc = fba.allocator();

            sentry.captureError(
                build_options.release,
                build_options.dist,
                "Fatal bug",
                std.fmt.allocPrint(alloc, fmt, args) catch unreachable,
                &[_]sentry.SentryEvent.TagSet.Tag{.{
                    .name = "seed",
                    .value = std.fmt.allocPrint(alloc, "{}", .{state.seed}) catch unreachable,
                }},
                @errorReturnTrace(),
                @returnAddress(),
                alloc,
            ) catch |err| {
                std.log.err("zig-sentry: Fail: {s}", .{@errorName(err)});
            };
        }
    }

    @panic("Aborting");
}

pub fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    @branchHint(.cold);

    std.log.err(fmt, args);
    ui.deinit() catch {};

    std.posix.abort();
    unreachable;
}

pub fn oom() noreturn {
    @branchHint(.cold);
    @panic("Out of memory! Please close a few browser tabs.");
}

pub fn todo() noreturn {
    @branchHint(.cold);
    @panic("TODO");
}

// Replacement for `unreachable`, since `unreachable` will continue to execute
// in unsafe release modes, which is unacceptable.
//
// Plus it gives the opportunity to print out a goofy message.
pub fn wat() noreturn {
    @branchHint(.cold);
    @panic("Pigs are flying! The sky is falling! Unreachable code entered!");
}
