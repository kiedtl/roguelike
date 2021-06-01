const std = @import("std");

const rng = @import("rng.zig");
const gas = @import("gas.zig");
const astar = @import("astar.zig");
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

fn initGame() void {
    if (display.init()) {} else |err| switch (err) {
        error.AlreadyInitialized => unreachable,
        error.TTYOpenFailed => @panic("Could not open TTY"),
        error.UnsupportedTerminal => @panic("Unsupported terminal"),
        error.PipeTrapFailed => @panic("Internal termbox error"),
    }

    state.messages = MessageArrayList.init(&state.GPA.allocator);
    state.mobs = MobList.init(&state.GPA.allocator);
    state.machines = MachineList.init(&state.GPA.allocator);
    state.props = PropList.init(&state.GPA.allocator);
    rng.init();

    for (state.dungeon.map) |_, level| {
        // mapgen.fillRandom(level, 40);
        // mapgen.fillBar(level, 1);
        // mapgen.cellularAutomata(level, 5, 2);
        // mapgen.cellularAutomata(level, 5, 2);
        // mapgen.cellularAutomata(level, 5, 2);
        // mapgen.cellularAutomata(level, 6, 1);
        // mapgen.cellularAutomata(level, 6, 1);
        // mapgen.cellularAutomata(level, 6, 1);
        mapgen.placeRandomRooms(level, 1000, &state.GPA.allocator);
        mapgen.placePatrolSquads(level, &state.GPA.allocator);
    }
    for (state.dungeon.map) |_, level|
        mapgen.placeRandomStairs(level);

    display.draw();
}

fn deinitGame() void {
    display.deinit() catch unreachable;
    state.mobs.deinit();
    state.machines.deinit();
    state.props.deinit();
    state.freeall();
    _ = state.GPA.deinit();
}

fn pollNoActionInput() void {
    var ev: termbox.tb_event = undefined;
    const t = termbox.tb_peek_event(&ev, 5);

    if (t == -1) @panic("Fatal termbox error");

    if (t == termbox.TB_EVENT_RESIZE) {
        display.draw();
    } else if (t == termbox.TB_EVENT_KEY) {
        if (ev.key != 0) {
            if (ev.key == termbox.TB_KEY_CTRL_C) {
                deinitGame();
                std.os.exit(0);
            }
        }
    }
}

fn readInput() bool {
    var ev: termbox.tb_event = undefined;
    const t = termbox.tb_poll_event(&ev);

    if (t == -1) @panic("Fatal termbox error");

    if (t == termbox.TB_EVENT_RESIZE) {
        display.draw();
        return false;
    } else if (t == termbox.TB_EVENT_KEY) {
        if (ev.key != 0) {
            if (ev.key == termbox.TB_KEY_CTRL_C) {
                deinitGame();
                std.os.exit(0);
            }
            return false;
        } else if (ev.ch != 0) {
            return switch (ev.ch) {
                '.' => state.player.rest(),
                'h' => state.player.moveInDirection(.West),
                'j' => state.player.moveInDirection(.South),
                'k' => state.player.moveInDirection(.North),
                'l' => state.player.moveInDirection(.East),
                'y' => state.player.moveInDirection(.NorthWest),
                'u' => state.player.moveInDirection(.NorthEast),
                'b' => state.player.moveInDirection(.SouthWest),
                'n' => state.player.moveInDirection(.SouthEast),
                's' => blk: {
                    state.dungeon.atGas(state.player.coord)[gas.SmokeGas.id] += 1.0;
                    break :blk true;
                },
                else => false,
            };
        } else unreachable;
    } else return false;
}

fn tick(present: bool) void {
    state.ticks += 1;

    state.tickAtmosphere(0);
    state.tickSound();

    const cur_level = state.player.coord.z;

    var moblist = state.createMobList(false, false, cur_level, &state.GPA.allocator);
    defer moblist.deinit();

    // Add the player to the beginning, as the moblist doesn't contain it
    moblist.insert(0, state.player) catch unreachable;

    for (moblist.items) |mob| {
        if (mob.coord.z != cur_level) {
            continue;
        }

        if (mob.coord.eq(state.player.coord) and state.player.is_dead) {
            pollNoActionInput();
            std.time.sleep(2 * 100000000); // 0.3 seconds
            if (present) display.draw();
            continue;
        }

        if (mob.is_dead) {
            continue;
        } else if (mob.should_be_dead()) {
            mob.kill();
            continue;
        }

        mob.tick_hp();
        mob.tick_env();

        state._update_fov(mob);

        if (mob.coord.eq(state.player.coord)) {
            display.draw();

            // Read input until something's done
            while (!readInput()) {}
        } else {
            state._mob_occupation_tick(mob, &moblist, &state.GPA.allocator);
        }

        state._update_fov(mob);
    }
}

fn viewerDisplay(level: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            var t = Tile.displayAs(Coord.new2(level, x, y));
            termbox.tb_put_cell(@intCast(isize, x), @intCast(isize, y), &t);
        }
    }
    termbox.tb_present();
}

fn viewerMain() void {
    state.player.kill();

    var level: usize = PLAYER_STARTING_LEVEL;

    while (true) {
        viewerDisplay(level);

        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                if (ev.key == termbox.TB_KEY_CTRL_C) {
                    break;
                }
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    '.' => tick(false),
                    '<' => if (level > 0) {
                        level -= 1;
                    },
                    '>' => if (level < (LEVELS - 1)) {
                        level += 1;
                    },
                    else => {},
                }
            } else unreachable;
        }
    }
}
pub fn main() anyerror!void {
    initGame();
    while (true) tick(true);
    deinitGame();
}
