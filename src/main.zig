const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;

const rng = @import("rng.zig");
const literature = @import("literature.zig");
const heat = @import("heat.zig");
const tasks = @import("tasks.zig");
const items = @import("items.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const mapgen = @import("mapgen.zig");
const surfaces = @import("surfaces.zig");
const display = @import("display.zig");
const termbox = @import("termbox.zig");
const types = @import("types.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const TaskArrayList = tasks.TaskArrayList;
pub const PosterArrayList = literature.PosterArrayList;

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

    state.memory = CoordCellMap.init(&state.GPA.allocator);

    state.tasks = TaskArrayList.init(&state.GPA.allocator);
    state.mobs = MobList.init(&state.GPA.allocator);
    state.sobs = SobList.init(&state.GPA.allocator);
    state.rings = RingList.init(&state.GPA.allocator);
    state.potions = PotionList.init(&state.GPA.allocator);
    state.armors = ArmorList.init(&state.GPA.allocator);
    state.weapons = WeaponList.init(&state.GPA.allocator);
    state.machines = MachineList.init(&state.GPA.allocator);
    state.props = PropList.init(&state.GPA.allocator);
    state.containers = ContainerList.init(&state.GPA.allocator);
    state.messages = MessageArrayList.init(&state.GPA.allocator);

    surfaces.readProps(&state.GPA.allocator);
    literature.readPosters(&state.GPA.allocator);

    for (state.dungeon.map) |_, level| {
        state.stockpiles[level] = StockpileArrayList.init(&state.GPA.allocator);
        state.inputs[level] = StockpileArrayList.init(&state.GPA.allocator);
        state.outputs[level] = RoomArrayList.init(&state.GPA.allocator);
        state.dungeon.rooms[level] = RoomArrayList.init(&state.GPA.allocator);
    }

    rng.init();

    var s_fabs: mapgen.PrefabArrayList = undefined;
    var n_fabs: mapgen.PrefabArrayList = undefined;
    mapgen.readPrefabs(&state.GPA.allocator, &n_fabs, &s_fabs);
    defer s_fabs.deinit();
    defer n_fabs.deinit();

    var level: usize = 0;
    while (level < LEVELS) {
        std.log.warn("Generating map {}.", .{mapgen.Configs[level].identifier});

        mapgen.resetLevel(level);

        if (level == 6) {
            mapgen.fillRandom(&state.layout[level], level, 40, .Floor);
            mapgen.cellularAutomata(&state.layout[level], level, 3, 0, .Wall);
            mapgen.cellularAutomata(&state.layout[level], level, 4, 0, .Wall);
            mapgen.cellularAutomata(&state.layout[level], level, 4, 0, .Wall);
            mapgen.cellularAutomata(&state.layout[level], level, 4, 0, .Wall);
            mapgen.cellularAutomata(&state.layout[level], level, 4, 0, .Wall);
            mapgen.cellularAutomata(&state.layout[level], level, 4, 0, .Wall);
            mapgen.cellularAutomata(&state.layout[level], level, 3, 0, .Wall);
            mapgen.cellularAutomata(&state.layout[level], level, 3, 0, .Wall);
        }

        mapgen.placeRandomRooms(&n_fabs, &s_fabs, level, &state.GPA.allocator);
        mapgen.placeMoarCorridors(level);

        if (!mapgen.validateLevel(level, &state.GPA.allocator)) {
            std.log.warn("Map {} invalid, regenerating.", .{mapgen.Configs[level].identifier});
            continue; // try again
        }

        mapgen.setLevelMaterial(level);

        mapgen.placeTraps(level);
        mapgen.placeRoomFeatures(level, &state.GPA.allocator);
        mapgen.placeItems(level);
        mapgen.placeMobs(level, &state.GPA.allocator);
        mapgen.generateLayoutMap(level);

        if (level == 6) {
            mapgen.fillRandom(&state.layout[level], level, 2, .Lava);
            mapgen.cellularAutomata(&state.layout[level], level, 2, 0, .Lava);
            mapgen.cellularAutomata(&state.layout[level], level, 2, 0, .Lava);
            mapgen.cellularAutomata(&state.layout[level], level, 1, 0, .Lava);
            mapgen.cellularAutomata(&state.layout[level], level, 1, 0, .Lava);
            mapgen.cellularAutomata(&state.layout[level], level, 2, 0, .Lava);
            mapgen.cellularAutomata(&state.layout[level], level, 3, 0, .Lava);
        }

        level += 1;
    }

    for (state.dungeon.map) |_, mlevel|
        mapgen.placeRandomStairs(mlevel);

    display.draw();
}

fn deinitGame() void {
    display.deinit() catch unreachable;

    state.memory.clearAndFree();

    var iter = state.mobs.iterator();
    while (iter.nextPtr()) |mob| {
        if (mob.is_dead) continue;
        mob.kill();
    }
    for (state.dungeon.map) |_, level| {
        state.dungeon.rooms[level].deinit();
        state.stockpiles[level].deinit();
        state.inputs[level].deinit();
        state.outputs[level].deinit();
    }

    state.tasks.deinit();
    state.mobs.deinit();
    state.sobs.deinit();
    state.rings.deinit();
    state.potions.deinit();
    state.armors.deinit();
    state.weapons.deinit();
    state.machines.deinit();
    state.messages.deinit();
    state.props.deinit();
    state.containers.deinit();

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

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn moveOrFight(direction: Direction) bool {
    const current = state.player.coord;

    if (current.move(direction, state.mapgeometry)) |dest| {
        if (state.dungeon.at(dest).mob) |mob| {
            if (state.player.isHostileTo(mob) and !state.player.canSwapWith(mob, direction)) {
                state.player.fight(mob);
                return true;
            }
        }

        return state.player.moveInDirection(direction);
    } else {
        return false;
    }
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn fireLauncher() bool {
    if (state.player.inventory.wielded) |weapon| {
        if (weapon.launcher) |launcher| {
            const dest = display.chooseCell() orelse return false;
            assert(state.player.launchProjectile(&launcher, dest));
            return true;
        } else {
            state.message(.MetaError, "You can't fire anything with that weapon.", .{});
            return false;
        }
    } else {
        state.message(.MetaError, "You aren't wielding anything.", .{});
        return false;
    }
}

pub fn grabItem() bool {
    if (state.player.inventory.pack.isFull()) {
        state.message(.MetaError, "Your pack is full.", .{});
        return false;
    }

    if (state.dungeon.at(state.player.coord).surface) |surface| {
        switch (surface) {
            .Container => |container| {
                if (container.items.len == 0) {
                    state.message(.MetaError, "There's nothing in the {}.", .{container.name});
                    return false;
                } else {
                    const index = display.chooseInventoryItem(
                        "Take",
                        container.items.constSlice(),
                    ) orelse return false;
                    const item = container.items.orderedRemove(index) catch unreachable;
                    state.player.inventory.pack.append(item) catch unreachable;

                    // TODO: show message

                    state.player.declareAction(.Grab);
                    return true;
                }
            },
            else => {},
        }
    }

    if (state.dungeon.itemsAt(state.player.coord).last()) |item| {
        state.player.inventory.pack.append(item) catch unreachable;
        _ = state.dungeon.itemsAt(state.player.coord).pop() catch unreachable;
        state.player.declareAction(.Grab);
        return true;
    } else {
        return false;
    }
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn rifleCorpse() bool {
    if (state.dungeon.itemsAt(state.player.coord).last()) |item| {
        switch (item) {
            .Corpse => |c| {
                c.vomitInventory(&state.GPA.allocator);
                state.player.declareAction(.Rifle);
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
    const index = display.chooseInventoryItem(
        "Throw",
        state.player.inventory.pack.constSlice(),
    ) orelse return false;
    const dest = display.chooseCell() orelse return false;
    const item = &state.player.inventory.pack.slice()[index];

    if (state.player.throwItem(item, dest)) {
        _ = state.player.removeItem(index) catch unreachable;
        state.player.declareAction(.Throw);
        return true;
    } else {
        state.message(.MetaError, "You can't throw that.", .{});
        return false;
    }
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
fn useItem() bool {
    const index = display.chooseInventoryItem(
        "Use",
        state.player.inventory.pack.constSlice(),
    ) orelse return false;

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
        .Weapon => |weapon| {
            if (state.player.inventory.wielded) |w| {
                state.player.inventory.pack.append(Item{ .Weapon = w }) catch |e| switch (e) {
                    error.NoSpaceLeft => {
                        if (state.nextAvailableSpaceForItem(
                            state.player.coord,
                            &state.GPA.allocator,
                        )) |c| {
                            state.message(
                                .Info,
                                "You drop the {} to wield the {}.",
                                .{ w.name, weapon.name },
                            );

                            if (state.dungeon.itemsAt(c).isFull())
                                _ = state.dungeon.itemsAt(c).orderedRemove(0) catch unreachable;
                            state.dungeon.itemsAt(c).append(Item{ .Weapon = w }) catch unreachable;
                        } else {
                            state.message(
                                .Info,
                                "You don't have any space to drop the {} to wield the {}.",
                                .{ w.name, weapon.name },
                            );
                            return false;
                        }
                    },
                    else => unreachable,
                };
                state.message(.Info, "You wield the {}.", .{weapon.name});
            }

            state.player.inventory.wielded = weapon;
        },
        .Armor => |armor| {
            if (state.player.inventory.armor) |a| {
                state.player.inventory.pack.append(Item{ .Armor = a }) catch |e| switch (e) {
                    error.NoSpaceLeft => {
                        if (state.nextAvailableSpaceForItem(
                            state.player.coord,
                            &state.GPA.allocator,
                        )) |c| {
                            state.message(
                                .Info,
                                "You drop the {} to wear the {}.",
                                .{ a.name, armor.name },
                            );

                            if (state.dungeon.itemsAt(c).isFull())
                                _ = state.dungeon.itemsAt(c).orderedRemove(0) catch unreachable;
                            state.dungeon.itemsAt(c).append(Item{ .Armor = a }) catch unreachable;
                        } else {
                            state.message(
                                .Info,
                                "You don't have any space to drop the {} to wear the {}.",
                                .{ a.name, armor.name },
                            );
                            return false;
                        }
                    },
                    else => unreachable,
                };
                state.message(.Info, "You wear the {}.", .{armor.name});
            }

            state.player.inventory.armor = armor;
        },
        .Potion => |p| state.player.quaffPotion(p),
        .Vial => |v| @panic("TODO"),
        .Boulder => |_| {
            state.message(.MetaError, "You want to *eat* that?", .{});
            return false;
        },
        .Prop => |p| {
            state.message(.Info, "You admire the {}.", .{p.name});
            return false;
        },
    }

    _ = state.player.removeItem(index) catch unreachable;

    state.player.declareAction(.Use);

    return true;
}

// TODO: move this to state.zig...? There should probably be a separate file for
// player-specific actions.
//
// TODO: merge with Mob.dropItem()
fn dropItem() bool {
    if (state.dungeon.at(state.player.coord).surface) |surface| {
        switch (surface) {
            .Container => |container| {
                if (container.items.len >= container.capacity) {
                    state.message(.MetaError, "There's no place on the {} for that.", .{container.name});
                    return false;
                } else {
                    const index = display.chooseInventoryItem(
                        "Store",
                        state.player.inventory.pack.constSlice(),
                    ) orelse return false;
                    const item = state.player.removeItem(index) catch unreachable;
                    container.items.append(item) catch unreachable;

                    // TODO: show message

                    state.player.declareAction(.Drop);
                    return true;
                }
            },
            else => {},
        }
    }

    if (state.dungeon.itemsAt(state.player.coord).isFull()) {
        // TODO: scoot item automatically to next available tile?
        state.message(.MetaError, "There's are already some items here.", .{});
        return false;
    } else {
        const index = display.chooseInventoryItem(
            "Drop",
            state.player.inventory.pack.constSlice(),
        ) orelse return false;
        const item = state.player.removeItem(index) catch unreachable;
        state.dungeon.itemsAt(state.player.coord).append(item) catch unreachable;

        // TODO: show message

        state.player.declareAction(.Drop);
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
                'x' => state.player.swapWeapons(),
                'f' => fireLauncher(),
                'r' => rifleCorpse(),
                't' => throwItem(),
                'a' => useItem(),
                'd' => dropItem(),
                ',' => grabItem(),
                '.' => state.player.rest(),
                'h' => moveOrFight(.West),
                'j' => moveOrFight(.South),
                'k' => moveOrFight(.North),
                'l' => moveOrFight(.East),
                'y' => moveOrFight(.NorthWest),
                'u' => moveOrFight(.NorthEast),
                'b' => moveOrFight(.SouthWest),
                'n' => moveOrFight(.SouthEast),

                // wizard keys
                '<' => blk: {
                    if (state.player.coord.z != 0) {
                        const l = state.player.coord.z - 1;
                        const r = rng.chooseUnweighted(Room, state.dungeon.rooms[l].items);
                        const c = r.randomCoord();
                        break :blk state.player.teleportTo(c, null);
                    } else {
                        break :blk false;
                    }
                },
                '>' => blk: {
                    if (state.player.coord.z < (LEVELS - 1)) {
                        const l = state.player.coord.z + 1;
                        const r = rng.chooseUnweighted(Room, state.dungeon.rooms[l].items);
                        const c = r.randomCoord();
                        break :blk state.player.teleportTo(c, null);
                    } else {
                        break :blk false;
                    }
                },
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
    readNoActionInput(null);
}

fn tickGame() void {
    if (state.player.is_dead) {
        state.state = .Lose;
        return;
    }

    const cur_level = state.player.coord.z;

    state.ticks += 1;
    surfaces.tickMachines(cur_level);
    state.tickLight(cur_level);
    heat.tickHeat(cur_level);
    tasks.tickTasks(cur_level);
    state.tickAtmosphere(cur_level, 0);
    state.tickSound(cur_level);

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

        if (mob.energy < 0) {
            if (mob.coord.eq(state.player.coord)) {
                display.draw();
                readNoActionInput(130);
                display.draw();
                if (state.state == .Quit) break;
            }

            continue;
        }

        var is_first = true;

        while (mob.energy >= 0) {
            if (mob.is_dead) {
                break;
            } else if (mob.should_be_dead()) {
                mob.kill();
                break;
            }

            const prev_energy = mob.energy;

            mob.tick_hp();
            mob.tick_env();
            mob.tickFOV();
            mob.tickRings();
            mob.tickStatuses();

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

            mob.tickFOV();

            assert(prev_energy > mob.energy);

            is_first = false;
        }
    }
}

fn viewerTickGame(cur_level: usize) void {
    state.ticks += 1;
    surfaces.tickMachines(cur_level);
    state.tickLight(cur_level);
    heat.tickHeat(cur_level);
    tasks.tickTasks(cur_level);
    state.tickAtmosphere(cur_level, 0);
    state.tickSound(cur_level);

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
            mob.tickFOV();
            mob.tickRings();
            mob.tickStatuses();

            if (mob.isUnderStatus(.Paralysis)) |_| {
                _ = mob.rest();
                continue;
            } else {
                state._mob_occupation_tick(mob, &state.GPA.allocator);
            }

            mob.tickFOV();

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
            .Lose, .Win => gameOverScreen(),
            .Quit => break,
        };
    }

    deinitGame();
}
