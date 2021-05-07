const std = @import("std");

const rng = @import("rng.zig");
const mapgen = @import("mapgen.zig");
const display = @import("display.zig");
const termbox = @import("termbox.zig");
const types = @import("types.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

// Install a panic handler that tries to shutdown termbox before calling the
// default panic handler.
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    display.deinit() catch |e| {};
    std.builtin.default_panic(msg, error_return_trace);
}

pub fn handle_key(ev: termbox.tb_event) bool {
    if (ev.key != 0) {
        if (ev.key == termbox.TB_KEY_CTRL_C)
            return true;
    } else if (ev.ch != 0) {
        const did_anything = switch (ev.ch) {
            'h' => state.mob_move(state.player, .West),
            'j' => state.mob_move(state.player, .South),
            'k' => state.mob_move(state.player, .North),
            'l' => state.mob_move(state.player, .East),
            else => false,
        };

        if (did_anything) {
            state.tick();
            display.draw();
        }
    } else
        unreachable;

    return false;
}

pub fn main() anyerror!void {
    if (display.init()) {} else |err| switch (err) {
        error.AlreadyInitialized => unreachable,
        error.TTYOpenFailed => @panic("Could not open TTY"),
        error.UnsupportedTerminal => @panic("Unsupported terminal"),
        error.PipeTrapFailed => @panic("Internal termbox error"),
    }
    defer display.deinit() catch unreachable;

    var gpa = std.heap.GeneralPurposeAllocator(.{
        // Probably should enable this later on to track memory usage, if
        // allocations become too much
        .enable_memory_limit = false,
        .safety = true,

        // Probably would enable this later, as we might want to run the ticks()
        // on other dungeon levels in another thread
        .thread_safe = true,

        .never_unmap = false,
    }){};
    defer std.debug.assert(!gpa.deinit());

    rng.init();
    mapgen.drunken_walk();
    mapgen.add_guard_stations(&gpa.allocator);
    mapgen.add_player(&gpa.allocator);

    state.tick();
    defer state.freeall();

    display.draw();

    while (true) {
        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) {
            @panic("Fatal termbox error");
        }

        switch (@intCast(usize, t)) {
            termbox.TB_EVENT_KEY => {
                if (handle_key(ev))
                    break;
            },
            termbox.TB_EVENT_RESIZE => display.draw(),
            else => {},
        }
    }
}
