const std = @import("std");
const assert = std.debug.assert;

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
    state.rings = RingList.init(&state.GPA.allocator);
    state.potions = PotionList.init(&state.GPA.allocator);
    state.armors = ArmorList.init(&state.GPA.allocator);
    state.weapons = WeaponList.init(&state.GPA.allocator);
    state.machines = MachineList.init(&state.GPA.allocator);
    state.props = PropList.init(&state.GPA.allocator);
    rng.init();

    var fabs = mapgen.readPrefabs(&state.GPA.allocator);
    for (state.dungeon.map) |_, level| {
        // mapgen.fillRandom(level, 40);
        // mapgen.fillBar(level, 1);
        // mapgen.cellularAutomata(level, 5, 2);
        // mapgen.cellularAutomata(level, 5, 2);
        // mapgen.cellularAutomata(level, 5, 2);
        // mapgen.cellularAutomata(level, 6, 1);
        // mapgen.cellularAutomata(level, 6, 1);
        // mapgen.cellularAutomata(level, 6, 1);
        mapgen.placeRandomRooms(&fabs, level, 2000, &state.GPA.allocator);
        mapgen.placeTraps(level);
        mapgen.placeLights(level);
        mapgen.placeItems(level);
        mapgen.placeGuards(level, &state.GPA.allocator);
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
    state.rings.deinit();
    state.potions.deinit();
    state.machines.deinit();
    state.messages.deinit();
    state.props.deinit();

    _ = state.GPA.deinit();
}

fn readNoActionInput() void {
    var ev: termbox.tb_event = undefined;
    const t = termbox.tb_poll_event(&ev);

    if (t == -1) @panic("Fatal termbox error");

    if (t == termbox.TB_EVENT_RESIZE) {
        display.draw();
    } else if (t == termbox.TB_EVENT_KEY) {
        if (ev.key != 0) {
            if (ev.key == termbox.TB_KEY_CTRL_C) {
                state.state = .Quit;
            }
        }
    }
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn rifleCorpse() bool {
    if (state.dungeon.at(state.player.coord).item) |item| {
        switch (item) {
            .Corpse => |c| {
                c.vomitInventory(&state.GPA.allocator);
                state.player.energy -= state.player.speed() * 2;
                state.message(.Info, "You rifle the {} corpse.", .{c.species});
                return true;
            },
            else => state.message(.MetaError, "You can't rifle that.", .{}),
        }
        return false;
    } else {
        state.message(.MetaError, "The floor is a bit too hard to dig through...", .{});
        return false;
    }
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn throwItem() bool {
    const index = display.chooseInventoryItem("Throw") orelse return false;
    const dest = display.chooseCell() orelse return false;
    const item = &state.player.inventory.pack.slice()[index];

    if (state.player.throwItem(item, dest)) {
        _ = state.player.inventory.pack.orderedRemove(index) catch unreachable;
        state.player.activities.append(.Throw);
        state.player.energy -= state.player.speed();
        return true;
    } else {
        state.message(.MetaError, "You can't throw that.", .{});
        return false;
    }
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn useItem() bool {
    const index = display.chooseInventoryItem("Use") orelse return false;

    switch (state.player.inventory.pack.slice()[index]) {
        .Corpse => |_| {
            state.message(.MetaError, "That doesn't look appetizing.", .{});
            return false;
        },
        .Ring => |_| {
            // So this message was in response to player going "I want to eat it"
            // But of course they might have just been intending to "invoke" the
            // ring, not knowing that there's no such thing.
            // FIXME: so this message can definitely be improved...
            state.message(.MetaError, "Are you three?", .{});
            return false;
        },
        .Weapon, .Armor => @panic("W/A TODO"),
        .Potion => |p| state.player.quaffPotion(p),
    }

    _ = state.player.inventory.pack.orderedRemove(index) catch unreachable;

    state.player.activities.append(.Use);
    state.player.energy -= state.player.speed();

    return true;
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn dropItem() bool {
    if (state.dungeon.at(state.player.coord).item) |item| {
        // TODO: scoot item automatically to next available tile?
        state.message(.MetaError, "There's already an item here.", .{});
        return false;
    } else {
        const index = display.chooseInventoryItem("Drop") orelse return false;
        const item = state.player.inventory.pack.orderedRemove(index) catch unreachable;
        state.dungeon.at(state.player.coord).item = item;

        // TODO: show message

        state.player.activities.append(.Drop);
        state.player.energy -= state.player.speed();
        return true;
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
                state.state = .Quit;
            }
            return true;
        } else if (ev.ch != 0) {
            return switch (ev.ch) {
                'r' => rifleCorpse(),
                't' => throwItem(),
                'a' => useItem(),
                'd' => dropItem(),
                ',' => state.player.grabItem(),
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
                    _ = state.player.rest();
                    state.dungeon.atGas(state.player.coord)[gas.SmokeGas.id] += 1.0;
                    break :blk true;
                },
                else => false,
            };
        } else unreachable;
    } else return false;
}

fn gameOverScreen() void {
    display.drawGameOver();
    readNoActionInput();
}

fn tickGame() void {
    if (state.player.is_dead) {
        state.state = .Lose;
        return;
    }

    const cur_level = state.player.coord.z;

    state.ticks += 1;
    state.tickMachines(cur_level);
    state.tickLight();
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

        while (mob.energy >= 0) {
            if (mob.is_dead or mob.should_be_dead()) break;

            const prev_energy = mob.energy;

            mob.tick_hp();
            mob.tick_env();
            mob.tickRings();
            mob.tickStatuses();

            state._update_fov(mob);

            if (mob.isUnderStatus(.Paralysis)) |_| {
                if (mob.coord.eq(state.player.coord)) {
                    readNoActionInput();
                    display.draw();
                    if (state.state == .Quit) break;
                }

                _ = mob.rest();
                continue;
            } else {
                if (mob.coord.eq(state.player.coord)) {
                    display.draw();
                    while (!readInput()) {}
                    if (state.state == .Quit) break;
                } else {
                    state._mob_occupation_tick(mob, &state.GPA.allocator);
                }
            }

            state._update_fov(mob);

            assert(prev_energy > mob.energy);
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
    state.tickLight();

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

    //viewerMain();

    while (state.state != .Quit) switch (state.state) {
        .Game => tickGame(),
        .Lose, .Win => gameOverScreen(),
        .Quit => break,
    };

    deinitGame();
}
