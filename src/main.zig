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

var quit: bool = undefined;

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
        mapgen.placeRandomRooms(level, 2000, &state.GPA.allocator);
        mapgen.placePatrolSquads(level, &state.GPA.allocator);
    }

    for (state.dungeon.map) |_, level|
        mapgen.placeRandomStairs(level);

    display.draw();
}

fn deinitGame() void {
    display.deinit() catch unreachable;

    var iter = state.mobs.iterator();
    while (iter.nextPtr()) |mob| {
        if (mob.is_dead) continue;
        mob.kill();
    }
    for (state.dungeon.rooms) |r|
        r.deinit();

    state.mobs.deinit();
    state.machines.deinit();
    state.messages.deinit();
    state.props.deinit();

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
                quit = true;
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
                quit = true;
            }
            return true;
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

fn tickGame() void {
    quit = false;
    while (!quit) {
        const cur_level = state.player.coord.z;

        state.ticks += 1;
        state.tickAtmosphere(0);
        state.tickSound();

        var iter = state.mobs.iterator();
        while (iter.nextPtr()) |mob| {
            if (mob.coord.z != cur_level) continue;

            if (mob.is_dead) {
                continue;
            } else if (mob.should_be_dead()) {
                mob.kill();
                continue;
            }

            mob.energy += 100;
            if (mob.energy < 0) continue;

            mob.tick_hp();
            mob.tick_env();

            state._update_fov(mob);

            if (mob.coord.eq(state.player.coord)) {
                if (state.player.is_dead) {
                    pollNoActionInput();
                    std.time.sleep(2 * 100000000); // 0.3 seconds
                    display.draw();
                } else {
                    display.draw();

                    // Read input until something's done
                    while (!readInput()) {}
                }
            } else {
                state._mob_occupation_tick(mob, &state.GPA.allocator);
            }

            state._update_fov(mob);
        }
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
    tickGame();
    deinitGame();
}
