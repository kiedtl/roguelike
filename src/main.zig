const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;

const StackBuffer = @import("buffer.zig").StackBuffer;

const rng = @import("rng.zig");
const player = @import("player.zig");
const literature = @import("literature.zig");
const explosions = @import("explosions.zig");
const tasks = @import("tasks.zig");
const fire = @import("fire.zig");
const items = @import("items.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const mapgen = @import("mapgen.zig");
const surfaces = @import("surfaces.zig");
const display = @import("display.zig");
const termbox = @import("termbox.zig");
const types = @import("types.zig");
const state = @import("state.zig");
const err = @import("err.zig");
usingnamespace @import("types.zig");

pub const TaskArrayList = tasks.TaskArrayList;
pub const PosterArrayList = literature.PosterArrayList;
pub const EvocableList = items.EvocableList;

// Install a panic handler that tries to shutdown termbox and print the RNG
// seed before calling the default panic handler.
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace) noreturn {
    display.deinit() catch |e| {};
    std.log.err("Fatal error encountered. (Seed: {})", .{rng.seed});
    std.builtin.default_panic(msg, error_return_trace);
}

fn initGame() bool {
    if (display.init()) {} else |e| switch (e) {
        error.AlreadyInitialized => err.wat(),
        error.TTYOpenFailed => @panic("Could not open TTY"),
        error.UnsupportedTerminal => @panic("Unsupported terminal"),
        error.PipeTrapFailed => @panic("Internal termbox error"),
    }

    if (!display.checkWindowSize(display.MIN_WIN_WIDTH, display.MIN_WIN_HEIGHT)) {
        return false;
    }

    rng.init(&state.GPA.allocator) catch |_| return false;

    player.choosePlayerUpgrades();

    state.chardata.init(&state.GPA.allocator);
    state.memory = state.MemoryTileMap.init(&state.GPA.allocator);

    state.tasks = TaskArrayList.init(&state.GPA.allocator);
    state.mobs = MobList.init(&state.GPA.allocator);
    state.rings = RingList.init(&state.GPA.allocator);
    state.potions = PotionList.init(&state.GPA.allocator);
    state.armors = ArmorList.init(&state.GPA.allocator);
    state.weapons = WeaponList.init(&state.GPA.allocator);
    state.machines = MachineList.init(&state.GPA.allocator);
    state.props = PropList.init(&state.GPA.allocator);
    state.containers = ContainerList.init(&state.GPA.allocator);
    state.evocables = EvocableList.init(&state.GPA.allocator);
    state.messages = MessageArrayList.init(&state.GPA.allocator);

    surfaces.readProps(&state.GPA.allocator);
    literature.readPosters(&state.GPA.allocator);

    for (state.dungeon.map) |*map, level| {
        state.stockpiles[level] = StockpileArrayList.init(&state.GPA.allocator);
        state.inputs[level] = StockpileArrayList.init(&state.GPA.allocator);
        state.outputs[level] = Rect.ArrayList.init(&state.GPA.allocator);
        state.rooms[level] = mapgen.Room.ArrayList.init(&state.GPA.allocator);

        for (map) |*row| for (row) |*tile| {
            tile.rand = rng.int(usize);
        };
    }

    var s_fabs: mapgen.PrefabArrayList = undefined;
    var n_fabs: mapgen.PrefabArrayList = undefined;
    mapgen.readPrefabs(&state.GPA.allocator, &n_fabs, &s_fabs);
    defer s_fabs.deinit();
    defer n_fabs.deinit();

    mapgen.fixConfigs();

    var level: usize = 0;
    var tries: usize = 0;
    while (level < LEVELS) {
        tries += 1;

        mapgen.resetLevel(level, &n_fabs, &s_fabs);
        mapgen.placeBlobs(level);
        (mapgen.Configs[level].mapgen_func)(&n_fabs, &s_fabs, level, &state.GPA.allocator);
        mapgen.placeMoarCorridors(level, &state.GPA.allocator);

        if (!mapgen.validateLevel(level, &state.GPA.allocator, &n_fabs, &s_fabs)) {
            if (tries < 27) {
                std.log.info("Map {} invalid, regenerating...", .{state.levelinfo[level].name});
                continue; // try again
            } else {
                // Give up!
                err.bug(
                    "Couldn't generate a valid map for {}!",
                    .{state.levelinfo[level].name},
                );
            }
        }

        mapgen.setLevelMaterial(level);

        mapgen.placeTraps(level);
        mapgen.placeRoomFeatures(level, &state.GPA.allocator);
        mapgen.placeItems(level);
        mapgen.placeMobs(level, &state.GPA.allocator);
        mapgen.generateLayoutMap(level);

        std.log.info("Generated map {}.", .{state.levelinfo[level].name});

        level += 1;
        tries = 0;
    }

    var f_level: usize = LEVELS - 1;
    while (f_level > 0) : (f_level -= 1) {
        for (mapgen.Configs[f_level].stairs_to) |dst_floor|
            mapgen.placeStair(f_level, dst_floor, &state.GPA.allocator);
    }

    display.draw();

    return true;
}

fn deinitGame() void {
    display.deinit() catch err.wat();

    state.chardata.deinit();
    state.memory.clearAndFree();

    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
        if (mob.is_dead) continue;
        mob.kill();
    }
    for (state.dungeon.map) |_, level| {
        state.stockpiles[level].deinit();
        state.inputs[level].deinit();
        state.outputs[level].deinit();
        state.rooms[level].deinit();
    }

    state.tasks.deinit();
    state.mobs.deinit();
    state.rings.deinit();
    state.potions.deinit();
    state.armors.deinit();
    state.weapons.deinit();
    state.machines.deinit();
    state.messages.deinit();
    state.props.deinit();
    state.containers.deinit();
    state.evocables.deinit();

    for (literature.posters.items) |poster|
        poster.deinit(&state.GPA.allocator);
    literature.posters.deinit();

    surfaces.freeProps(&state.GPA.allocator);

    _ = state.GPA.deinit();
}

fn readNoActionInput(timeout: ?isize) void {
    var ev: termbox.tb_event = undefined;
    const t = if (timeout) |t| termbox.tb_peek_event(&ev, t) else termbox.tb_poll_event(&ev);

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

fn readInput() bool {
    var ev: termbox.tb_event = undefined;
    const t = termbox.tb_poll_event(&ev);

    if (t == -1) @panic("Fatal termbox error");

    if (t == termbox.TB_EVENT_RESIZE) {
        display.draw();
        return false;
    } else if (t == termbox.TB_EVENT_KEY) {
        if (ev.key != 0) {
            return switch (ev.key) {
                termbox.TB_KEY_CTRL_C => b: {
                    state.state = .Quit;
                    break :b true;
                },

                // Wizard keys
                termbox.TB_KEY_F1 => blk: {
                    if (state.player.coord.z != 0) {
                        const l = state.player.coord.z - 1;
                        const r = rng.chooseUnweighted(mapgen.Room, state.rooms[l].items);
                        const c = r.rect.randomCoord();
                        break :blk state.player.teleportTo(c, null);
                    } else {
                        break :blk false;
                    }
                },
                termbox.TB_KEY_F2 => blk: {
                    if (state.player.coord.z < (LEVELS - 1)) {
                        const l = state.player.coord.z + 1;
                        const r = rng.chooseUnweighted(mapgen.Room, state.rooms[l].items);
                        const c = r.rect.randomCoord();
                        break :blk state.player.teleportTo(c, null);
                    } else {
                        break :blk false;
                    }
                },
                termbox.TB_KEY_F3 => blk: {
                    state.player.allegiance = switch (state.player.allegiance) {
                        .OtherGood => .Necromancer,
                        .Necromancer => .OtherEvil,
                        .OtherEvil => .OtherGood,
                    };
                    break :blk false;
                },
                termbox.TB_KEY_F4 => blk: {
                    explosions.kaboom(state.player.coord, .{
                        .strength = 10 * 100,
                        .spare_player = true,
                    });
                    _ = state.player.rest();
                    break :blk true;
                },
                termbox.TB_KEY_F5 => blk: {
                    state.player.HP = state.player.max_HP;
                    state.player.MP = state.player.max_MP;
                    break :blk false;
                },
                termbox.TB_KEY_F6 => blk: {
                    const stairlocs = state.dungeon.stairs[state.player.coord.z];
                    const stairloc = rng.chooseUnweighted(Coord, stairlocs.constSlice());
                    break :blk state.player.teleportTo(stairloc, null);
                },
                else => false,
            };
        } else if (ev.ch != 0) {
            return switch (ev.ch) {
                'x' => state.player.swapWeapons(),
                'r' => player.invokeRecharger(),
                't' => player.throwItem(),
                'a' => player.useSomething(),
                'd' => player.dropItem(),
                ',' => player.grabItem(),
                '.' => state.player.rest(),
                'h' => player.moveOrFight(.West),
                'j' => player.moveOrFight(.South),
                'k' => player.moveOrFight(.North),
                'l' => player.moveOrFight(.East),
                'y' => player.moveOrFight(.NorthWest),
                'u' => player.moveOrFight(.NorthEast),
                'b' => player.moveOrFight(.SouthWest),
                'n' => player.moveOrFight(.SouthEast),
                else => false,
            };
        } else err.wat();
    } else return false;
}

fn tickGame() void {
    if (state.player.is_dead) {
        state.state = .Lose;
        return;
    }

    const cur_level = state.player.coord.z;

    state.ticks += 1;
    surfaces.tickMachines(cur_level);
    tasks.tickTasks(cur_level);
    fire.tickFire(cur_level);
    gas.tickGases(cur_level, 0);
    state.tickSound(cur_level);
    state.tickLight(cur_level);

    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
        if (mob.coord.z != cur_level) continue;

        if (mob.is_dead) {
            continue;
        } else if (mob.should_be_dead()) {
            mob.kill();
            continue;
        }

        mob.energy += 100;

        if (mob.energy < 0) {
            if (mob.coord.eq(state.player.coord)) {
                display.draw();
                readNoActionInput(130);
                display.draw();
                if (state.state == .Quit) break;
            }

            continue;
        }

        while (mob.energy >= 0) {
            if (mob.is_dead) {
                break;
            } else if (mob.should_be_dead()) {
                mob.kill();
                break;
            }

            const prev_energy = mob.energy;

            mob.tick_env();
            mob.tickFOV();
            mob.tickRings();
            mob.tickStatuses();

            if (mob == state.player) {
                state.chardata.time_on_levels[mob.coord.z] += 1;
                player.bookkeepingFOV();
            }

            if (mob.isUnderStatus(.Paralysis)) |_| {
                if (mob.coord.eq(state.player.coord)) {
                    display.draw();
                    readNoActionInput(130);
                    display.draw();
                    if (state.state == .Quit) break;
                }

                _ = mob.rest();
                continue;
            } else {
                if (mob.coord.eq(state.player.coord)) {
                    display.draw();
                    while (!readInput()) display.draw();
                    if (state.state == .Quit) break;
                } else {
                    state._mob_occupation_tick(mob, &state.GPA.allocator);
                }
            }

            if (state.dungeon.at(mob.coord).mob == null) {
                err.bug("Mob {} is dancing around the chessboard!", .{mob.displayName()});
            }

            mob.tickFOV();

            if (mob == state.player) {
                player.bookkeepingFOV();
            }

            if (prev_energy <= mob.energy) {
                err.bug("Mob {} did nothing during its turn!", .{mob.displayName()});
            }
        }
    }
}

fn viewerTickGame(cur_level: usize) void {
    state.ticks += 1;
    surfaces.tickMachines(cur_level);
    tasks.tickTasks(cur_level);
    fire.tickFire(cur_level);
    gas.tickGases(cur_level, 0);
    state.tickSound(cur_level);
    state.tickLight(cur_level);

    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
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

            mob.tick_env();
            mob.tickFOV();
            mob.tickRings();
            mob.tickStatuses();

            if (state.dungeon.at(mob.coord).mob == null) {
                err.bug("Mob {} isn't where it is! (mob.coord: {}, last activity: {})", .{
                    mob.displayName(), mob.coord, mob.activities.current(),
                });
            }

            if (mob.isUnderStatus(.Paralysis)) |_| {
                _ = mob.rest();
                continue;
            } else {
                state._mob_occupation_tick(mob, &state.GPA.allocator);
            }

            mob.tickFOV();

            if (state.dungeon.at(mob.coord).mob == null) {
                err.bug("Mob {} isn't where it is! (mob.coord: {}, last activity: {})", .{
                    mob.displayName(), mob.coord, mob.activities.current(),
                });
            }

            assert(prev_energy > mob.energy);
        }
    }
}

fn viewerDisplay(tty_height: usize, level: usize, sy: usize) void {
    var dy: usize = sy;
    var y: usize = 0;
    while (y < tty_height and dy < HEIGHT) : ({
        y += 1;
        dy += 1;
    }) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            var t = Tile.displayAs(Coord.new2(level, x, dy), false);
            termbox.tb_put_cell(@intCast(isize, x), @intCast(isize, y), &t);
        }
    }
    while (y < tty_height) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            termbox.tb_change_cell(@intCast(isize, x), @intCast(isize, y), ' ', 0, 0);
        }
    }
    termbox.tb_present();
}

fn viewerMain() void {
    state.player.kill();

    var level: usize = PLAYER_STARTING_LEVEL;
    var y: usize = 0;
    var running: bool = false;

    const tty_height = @intCast(usize, termbox.tb_height());

    while (true) {
        viewerDisplay(tty_height, level, y);

        var ev: termbox.tb_event = undefined;
        var t: isize = 0;

        if (running) {
            t = termbox.tb_peek_event(&ev, 150);
            if (t == 0) {
                viewerTickGame(level);
                continue;
            }
        } else {
            t = termbox.tb_poll_event(&ev);
        }

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                if (ev.key == termbox.TB_KEY_CTRL_C) {
                    break;
                }
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    '.' => viewerTickGame(level),
                    'a' => running = !running,
                    'j' => if (y < HEIGHT) {
                        y = math.min(y + (tty_height / 2), HEIGHT - 1);
                    },
                    'k' => y = utils.saturating_sub(y, (tty_height / 2)),
                    'e' => explosions.kaboom(
                        Coord.new2(
                            level,
                            rng.range(usize, 20, WIDTH - 20),
                            rng.range(usize, 20, HEIGHT - 20),
                        ),
                        .{ .strength = rng.range(usize, 400, 1500) },
                    ),
                    '<' => if (level > 0) {
                        level -= 1;
                    },
                    '>' => if (level < (LEVELS - 1)) {
                        level += 1;
                    },
                    else => {},
                }
            } else err.wat();
        }
    }
}

pub fn main() anyerror!void {
    if (!initGame()) {
        deinitGame();
        return;
    }

    var use_viewer: bool = undefined;

    if (std.process.getEnvVarOwned(&state.GPA.allocator, "RL_MODE")) |v| {
        use_viewer = mem.eql(u8, v, "viewer");
        state.GPA.allocator.free(v);
    } else |_| {
        use_viewer = false;
    }

    if (use_viewer) {
        viewerMain();
    } else {
        while (state.state != .Quit) switch (state.state) {
            .Game => tickGame(),
            .Win => {
                _ = state.messageKeyPrompt("You escaped! (more)", .{}, ' ', "", "");
                break;
            },
            .Lose => {
                _ = state.messageKeyPrompt("You die... (more)", .{}, ' ', "", "");
                break;
            },
            .Quit => break,
        };
    }

    const morgue = state.formatMorgue(&state.GPA.allocator) catch err.wat();
    const filename = "dump.txt";
    try std.fs.cwd().writeFile(filename, morgue.items[0..]);
    std.log.info("Morgue file written to {}.", .{filename});
    morgue.deinit(); // We can't defer{} this because we're deinit'ing the allocator

    deinitGame();
}
