const build_options = @import("build_options");

const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;

const StackBuffer = @import("buffer.zig").StackBuffer;

const ai = @import("ai.zig");
// const alert = @import("alert.zig");
const rng = @import("rng.zig");
const janet = @import("janet.zig");
const player = @import("player.zig");
const font = @import("font.zig");
const events = @import("events.zig");
const literature = @import("literature.zig");
const explosions = @import("explosions.zig");
const tasks = @import("tasks.zig");
const fire = @import("fire.zig");
const items = @import("items.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const mapgen = @import("mapgen.zig");
const mobs = @import("mobs.zig");
const surfaces = @import("surfaces.zig");
const ui = @import("ui.zig");
const termbox = @import("termbox.zig");
const display = @import("display.zig");
const types = @import("types.zig");
const sentry = @import("sentry.zig");
const state = @import("state.zig");
const err = @import("err.zig");
const scores = @import("scores.zig");

const Direction = types.Direction;
const Coord = types.Coord;
const Rect = types.Rect;
const Tile = types.Tile;

const Squad = types.Squad;
const MobList = types.MobList;
const RingList = types.RingList;
const PotionList = types.PotionList;
const ArmorList = types.ArmorList;
const WeaponList = types.WeaponList;
const MachineList = types.MachineList;
const PropList = types.PropList;
const ContainerList = types.ContainerList;
const Message = types.Message;
const MessageArrayList = types.MessageArrayList;
const MobArrayList = types.MobArrayList;
const StockpileArrayList = types.StockpileArrayList;
const DIRECTIONS = types.DIRECTIONS;

const TaskArrayList = tasks.TaskArrayList;
const PosterArrayList = literature.PosterArrayList;
const EvocableList = items.EvocableList;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// Install a panic handler that tries to shutdown termbox and print the RNG
// seed before calling sentry and then the default panic handler.
var __panic_stage: usize = 0;
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    nosuspend switch (__panic_stage) {
        0 => {
            __panic_stage = 1;
            ui.deinit() catch {};
            std.log.err("Fatal error encountered. (Seed: {})", .{rng.seed});

            if (!state.sentry_disabled) {
                var membuf: [65535]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);
                var alloc = fba.allocator();

                sentry.captureError(
                    build_options.release,
                    build_options.dist,
                    "Panic",
                    msg,
                    &[_]sentry.SentryEvent.TagSet.Tag{.{
                        .name = "seed",
                        .value = std.fmt.allocPrint(alloc, "{}", .{rng.seed}) catch unreachable,
                    }},
                    trace,
                    @returnAddress(),
                    alloc,
                ) catch |e| {
                    std.log.err("zig-sentry: Fail: {s}", .{@errorName(e)});
                };
            }

            std.builtin.default_panic(msg, trace);
        },
        1 => {
            __panic_stage = 2;
            std.builtin.default_panic(msg, trace);
        },
        else => {
            std.os.abort();
        },
    };
}

fn initGame() bool {
    // Initialize this *first* because we might have to deinitGame() at
    // checkWindowSize, and we have no way to tell if state.dungeon was
    // allocated or not.
    state.dungeon = state.GPA.allocator().create(types.Dungeon) catch err.oom();
    state.dungeon.* = types.Dungeon{};

    if (ui.init()) {} else |e| switch (e) {
        error.AlreadyInitialized => err.wat(),
        error.TTYOpenFailed => err.fatal("Could not open TTY", .{}),
        error.UnsupportedTerminal => err.fatal("Unsupported terminal", .{}),
        error.PipeTrapFailed => err.fatal("Internal termbox error", .{}),
        error.SDL2InitError => if (build_options.use_sdl) {
            err.fatal("SDL2 Error: {s}", .{display.driver_m.SDL_GetError()});
        } else unreachable,
        else => err.fatal("Error when initializing display", .{}),
    }

    if (!ui.checkWindowSize()) {
        return false;
    }

    rng.init(state.GPA.allocator()) catch return false;

    for (state.default_patterns) |*r| r.pattern_checker.reset();

    state.memory = state.MemoryTileMap.init(state.GPA.allocator());

    state.tasks = TaskArrayList.init(state.GPA.allocator());
    state.squads = Squad.List.init(state.GPA.allocator());
    state.mobs = MobList.init(state.GPA.allocator());
    state.rings = RingList.init(state.GPA.allocator());
    state.machines = MachineList.init(state.GPA.allocator());
    state.props = PropList.init(state.GPA.allocator());
    state.containers = ContainerList.init(state.GPA.allocator());
    state.evocables = EvocableList.init(state.GPA.allocator());
    state.messages = MessageArrayList.init(state.GPA.allocator());
    // state.alerts = alert.Alert.List.init(state.GPA.allocator());

    janet.init() catch return false;
    _ = janet.loadFile("scripts/particles.janet", state.GPA.allocator()) catch return false;

    events.init();
    font.loadFontsData();
    state.loadLevelInfo();
    surfaces.readProps(state.GPA.allocator());
    literature.readPosters(state.GPA.allocator());
    mapgen.readSpawnTables(state.GPA.allocator());
    mapgen.readPrefabs(state.GPA.allocator());
    readDescriptions(state.GPA.allocator());
    player.choosePlayerUpgrades();
    events.executeGlobalEvents();

    for (state.dungeon.map) |*map, level| {
        state.stockpiles[level] = StockpileArrayList.init(state.GPA.allocator());
        state.inputs[level] = StockpileArrayList.init(state.GPA.allocator());
        state.outputs[level] = Rect.ArrayList.init(state.GPA.allocator());
        state.rooms[level] = mapgen.Room.ArrayList.init(state.GPA.allocator());

        for (map) |*row| for (row) |*tile| {
            tile.rand = rng.int(usize);
        };
    }

    for (mapgen.floor_seeds) |*seed|
        seed.* = rng.int(u64);

    return true;
}

fn initLevels() bool {
    var loading_screen = ui.initLoadingScreen();
    defer loading_screen.deinit();

    ui.drawLoadingScreen(&loading_screen, "", "Generating level...", 0) catch return false;
    mapgen.initLevel(state.PLAYER_STARTING_LEVEL);

    return ui.drawLoadingScreenFinish(&loading_screen);
}

fn deinitGame() void {
    ui.deinit() catch err.wat();

    mapgen.s_fabs.deinit();
    mapgen.n_fabs.deinit();
    mapgen.fab_records.deinit();

    state.memory.clearAndFree();

    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
        if (mob.is_dead) continue;
        mob.deinit();
    }
    var s_iter = state.squads.iterator();
    while (s_iter.next()) |squad|
        squad.deinit();
    for (state.dungeon.map) |_, level| {
        state.stockpiles[level].deinit();
        state.inputs[level].deinit();
        state.outputs[level].deinit();
        state.rooms[level].deinit();
    }

    state.tasks.deinit();
    state.squads.deinit();
    state.mobs.deinit();
    state.rings.deinit();
    state.machines.deinit();
    state.messages.deinit();
    state.props.deinit();
    state.containers.deinit();
    state.evocables.deinit();
    // state.alerts.deinit();

    for (literature.posters.items) |poster|
        poster.deinit(state.GPA.allocator());
    literature.posters.deinit();

    events.deinit();
    janet.deinit();
    font.freeFontData();
    state.freeLevelInfo();
    surfaces.freeProps(state.GPA.allocator());
    mapgen.freeSpawnTables(state.GPA.allocator());
    freeDescriptions(state.GPA.allocator());

    // Do this last so that mob corpses can be placed (A better fix would be to
    // just not place corpses at all when deinit'ing the game)
    state.GPA.allocator().destroy(state.dungeon);

    _ = state.GPA.deinit();
}

fn readDescriptions(alloc: mem.Allocator) void {
    state.descriptions = @TypeOf(state.descriptions).init(alloc);

    const data_dir = std.fs.cwd().openDir("data", .{}) catch err.wat();
    const data_file = data_dir.openFile("des.txt", .{
        .read = true,
        .lock = .None,
    }) catch err.wat();

    const filesize = data_file.getEndPos() catch err.wat();
    const filebuf = alloc.alloc(u8, @intCast(usize, filesize)) catch err.wat();
    defer alloc.free(filebuf);
    const read = data_file.readAll(filebuf[0..]) catch err.wat();

    var lines = mem.split(u8, filebuf[0..read], "\n");
    var current_desc_id: ?[]const u8 = null;
    var current_desc = StackBuffer(u8, 4096).init(null);

    const S = struct {
        pub fn _finishDescEntry(id: []const u8, desc: []const u8, a: mem.Allocator) void {
            const key = a.alloc(u8, id.len) catch err.wat();
            mem.copy(u8, key, id);

            const val = a.alloc(u8, desc.len) catch err.wat();
            mem.copy(u8, val, desc);

            state.descriptions.putNoClobber(key, val) catch err.bug(
                "Duplicate description {s} found",
                .{key},
            );
        }
    };

    var prev_was_nl = false;
    while (lines.next()) |line| {
        if (line.len == 0) {
            if (prev_was_nl) {
                current_desc.appendSlice("\n") catch err.wat();
            }
            prev_was_nl = true;
        } else {
            if (prev_was_nl) {
                current_desc.appendSlice(" ") catch err.wat();
            }
            prev_was_nl = false;

            if (line[0] == '%') {
                if (current_desc_id) |id| {
                    S._finishDescEntry(id, current_desc.constSlice(), alloc);

                    current_desc.clear();
                    current_desc_id = null;
                }

                if (line.len <= 2) err.bug("Missing desc ID", .{});
                current_desc_id = line[2..];
            } else {
                if (current_desc_id == null) {
                    err.bug("Description without ID", .{});
                }

                current_desc.appendSlice(line) catch err.wat();
                prev_was_nl = true;
            }
        }
    }

    S._finishDescEntry(current_desc_id.?, current_desc.constSlice(), alloc);
}

fn freeDescriptions(alloc: mem.Allocator) void {
    var iter = state.descriptions.iterator();
    while (iter.next()) |entry| {
        alloc.free(entry.key_ptr.*);
        alloc.free(entry.value_ptr.*);
    }
    state.descriptions.clearAndFree();
}

fn readNoActionInput(timeout: ?usize) !void {
    ui.draw();
    if (state.state == .Quit) return error.Quit;

    switch (display.waitForEvent(timeout) catch |e| switch (e) {
        error.NoInput => {
            assert(timeout != null);
            return;
        },
        else => err.fatal("{s}", .{@errorName(e)}),
    }) {
        .Quit => {
            state.state = .Quit;
            return error.Quit;
        },
        .Resize => ui.draw(),
        .Key => |k| switch (k) {
            .CtrlC => {
                state.state = .Quit;
                return error.Quit;
            },
            else => {},
        },
        else => {},
    }

    if (state.state == .Quit) return error.Quit;
    ui.draw();
}

fn readInput() !bool {
    ui.draw();
    if (state.state == .Quit) return error.Quit;

    const action_taken = switch (display.waitForEvent(ui.FRAMERATE) catch return false) {
        .Quit => {
            state.state = .Quit;
            return false;
        },
        .Resize => {
            ui.draw();
            return false;
        },
        .Key => |k| switch (k) {
            .Esc => b: {
                ui.drawEscapeMenu();
                break :b false;
            },
            .CtrlC => b: {
                state.state = .Quit;
                break :b true;
            },

            // Wizard keys
            .F1 => blk: {
                if (state.player.coord.z != 0) {
                    const l = state.player.coord.z - 1;
                    const r = rng.chooseUnweighted(mapgen.Room, state.rooms[l].items);
                    const c = r.rect.randomCoord();
                    break :blk state.player.teleportTo(c, null, false, false);
                } else {
                    break :blk false;
                }
            },
            .F2 => blk: {
                if (state.player.coord.z < (LEVELS - 1)) {
                    const l = state.player.coord.z + 1;
                    const r = rng.chooseUnweighted(mapgen.Room, state.rooms[l].items);
                    const c = r.rect.randomCoord();
                    break :blk state.player.teleportTo(c, null, false, false);
                } else {
                    break :blk false;
                }
            },
            .F3 => blk: {
                state.player.faction = switch (state.player.faction) {
                    .Player => .Necromancer,
                    .Necromancer => .CaveGoblins,
                    .CaveGoblins => .Night,
                    .Night => .Player,
                    .Revgenunkim => unreachable,
                };
                state.message(.Info, "[wizard] new faction: {}", .{state.player.faction});
                break :blk false;
            },
            .F4 => blk: {
                player.wiz_lidless_eye = !player.wiz_lidless_eye;
                state.player.rest(); // Update LOS
                break :blk true;
            },
            .F5 => blk: {
                state.player.HP = state.player.max_HP;
                state.player.MP = state.player.max_MP;
                break :blk false;
            },
            .F6 => blk: {
                const stairlocs = state.dungeon.stairs[state.player.coord.z];
                const stairloc = rng.chooseUnweighted(Coord, stairlocs.constSlice());
                break :blk state.player.teleportTo(stairloc, null, false, false);
            },
            .F7 => blk: {
                //state.player.innate_resists.rElec += 25;
                //state.player.addStatus(.Drunk, 0, .{ .Tmp = 20 });
                //state.message(.Info, "Lorem ipsum, dolor sit amet. Lorem ipsum, dolor sit amet.. Lorem ipsum, dolor sit amet. {}", .{rng.int(usize)});
                // _ = ui.drawYesNoPrompt("foo, bar, baz. Lorem ipsum, dolor sit amet. Dolem Lipsum, solor ait smet. Iorem Aipsum, lolor dit asset.", .{});
                //ui.labels.addFor(state.player, "foo bar baz", .{});
                // state.player.addStatus(.Corruption, 0, .{ .Tmp = 5 });
                // state.player.addStatus(.RingTeleportation, 0, .{ .Tmp = 5 });
                // state.player.addStatus(.RingElectrocution, 0, .{ .Tmp = 5 });
                // state.player.addStatus(.RingConjuration, 0, .{ .Tmp = 2 });
                // state.night_rep[@enumToInt(state.player.faction)] += 10;
                state.player.HP = 0;
                break :blk true;
            },
            .F8 => b: {
                _ = janet.loadFile("scripts/particles.janet", state.GPA.allocator()) catch break :b false;

                const target = ui.chooseCell(.{}) orelse break :b false;
                ui.Animation.apply(.{ .Particle = .{ .name = "test", .coord = state.player.coord, .target = .{ .C = target } } });
                break :b true;
            },
            .F9 => b: {
                const chosen = ui.chooseCell(.{}) orelse break :b false;
                break :b state.player.teleportTo(chosen, null, false, false);
            },
            else => false,
        },
        .Char => |c| switch (c) {
            ' ' => b: {
                _ = ui.drawZapScreen();
                break :b false;
            },
            't' => b: {
                player.auto_wait_enabled = !player.auto_wait_enabled;
                const str = if (player.auto_wait_enabled)
                    @as([]const u8, "enabled")
                else
                    "disabled";
                state.message(.Info, "Auto-waiting: {s}", .{str});
                break :b false;
            },
            '\'' => b: {
                state.player.swapWeapons();
                if (state.player.inventory.equipment(.Weapon).*) |weapon| {
                    state.message(.Inventory, "Now wielding a {s}.", .{
                        (weapon.longName() catch err.wat()).constSlice(),
                    });
                } else {
                    state.message(.Inventory, "You aren't wielding anything now.", .{});
                }
                break :b false;
            },
            'A' => player.activateSurfaceItem(state.player.coord),
            'i' => ui.drawInventoryScreen(),
            'v' => ui.drawExamineScreen(null),
            '@' => ui.drawExamineScreen(.Mob),
            'M' => b: {
                ui.drawMessagesScreen();
                break :b false;
            },
            ',' => player.grabItem(),
            's', '.' => player.tryRest(),
            'q', 'y' => player.moveOrFight(.NorthWest),
            'w', 'k' => player.moveOrFight(.North),
            'e', 'u' => player.moveOrFight(.NorthEast),
            'd', 'l' => player.moveOrFight(.East),
            'c', 'n' => player.moveOrFight(.SouthEast),
            'x', 'j' => player.moveOrFight(.South),
            'z', 'b' => player.moveOrFight(.SouthWest),
            'a', 'h' => player.moveOrFight(.West),
            else => false,
        },
        //else => false,
    };

    ui.draw();
    if (state.state == .Quit) return error.Quit;
    return action_taken;
}

fn tickGame() !void {
    if (state.player.is_dead) {
        state.state = .Lose;
        return;
    }

    const cur_level = state.player.coord.z;

    state.ticks += 1;
    surfaces.tickMachines(cur_level);
    fire.tickFire(cur_level);
    gas.tickGasEmitters(cur_level);
    gas.tickGases(cur_level);
    state.tickSound(cur_level);
    state.tickLight(cur_level);

    if (state.ticks % 10 == 0) {
        // alert.tickCheckLevelHealth(cur_level);
        // alert.tickActOnAlert(cur_level);
        tasks.tickTasks(cur_level);
    }

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
            if (mob == state.player) {
                try readNoActionInput(130);
            }

            ai.checkForNoises(mob);
            continue;
        }

        var actions_taken: usize = 0;
        while (mob.energy >= 0) : (actions_taken += 0) {
            if (mob.is_dead) {
                break;
            } else if (mob.should_be_dead()) {
                mob.kill();
                break;
            }

            const prev_energy = mob.energy;

            mob.tick_env();
            mob.tickFOV();
            mob.tickDisruption();
            mob.tickStatuses();

            if (mob == state.player) {
                state.player_turns += 1;
                scores.recordUsize(.TurnsSpent, 1);
                player.bookkeepingFOV();
                player.checkForGarbage();
                if (player.getActiveRing()) |r|
                    player.getRingHints(r);
            }

            if (mob.isUnderStatus(.Paralysis)) |_| {
                if (mob.coord.eq(state.player.coord)) {
                    var frames: usize = 5;
                    while (frames > 0) : (frames -= 1) {
                        try readNoActionInput(ui.FRAMERATE);
                    }
                }

                mob.rest();
                continue;
            } else {
                if (mob.coord.eq(state.player.coord)) {
                    ui.draw();
                    if (state.state == .Quit) break;
                    while (!try readInput()) ui.draw();
                    if (state.state == .Quit) break;
                } else {
                    ai.main(mob, state.GPA.allocator());
                }
            }

            mob.checkForPatternUsage();

            if (state.dungeon.at(mob.coord).mob == null) {
                err.bug("Mob {s} is dancing around the chessboard!", .{mob.displayName()});
            }

            mob.tickFOV();

            if (mob == state.player) {
                player.bookkeepingFOV();
            }

            err.ensure(prev_energy > mob.energy, "{c} (phase: {}) did nothing during turn!", .{ mob, mob.ai.phase }) catch {
                ai.tryRest(mob);
            };

            if (actions_taken > 1 and state.player.cansee(mob.coord)) {
                try readNoActionInput(130);
            }
        }

        if (!mob.is_dead and mob.should_be_dead()) {
            mob.kill();
            continue;
        }
    }
}

fn viewerTickGame(cur_level: usize) void {
    state.ticks += 1;
    surfaces.tickMachines(cur_level);
    fire.tickFire(cur_level);
    gas.tickGasEmitters(cur_level);
    gas.tickGases(cur_level);
    state.tickSound(cur_level);
    state.tickLight(cur_level);

    if (state.ticks % 10 == 0) {
        // alert.tickCheckLevelHealth(cur_level);
        // alert.tickActOnAlert(cur_level);
        tasks.tickTasks(cur_level);
    }

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
            mob.tickStatuses();

            if (state.dungeon.at(mob.coord).mob == null) {
                err.bug("Mob {s} isn't where it is! (mob.coord: {}, last activity: {})", .{
                    mob.displayName(), mob.coord, mob.activities.current(),
                });
            }

            if (mob.isUnderStatus(.Paralysis)) |_| {
                mob.rest();
                continue;
            } else {
                ai.main(mob, state.GPA.allocator());
            }

            mob.checkForPatternUsage();
            mob.tickFOV();

            if (state.dungeon.at(mob.coord).mob == null) {
                err.bug("Mob {s} isn't where it is! (mob.coord: {}, last activity: {})", .{
                    mob.displayName(), mob.coord, mob.activities.current(),
                });
            }

            err.ensure(prev_energy > mob.energy, "{c} (phase: {}) did nothing during turn!", .{ mob, mob.ai.phase }) catch {
                ai.tryRest(mob);
            };
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
            const t = Tile.displayAs(Coord.new2(level, x, dy), false, false);
            display.setCell(x, y, t);
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
    if (build_options.use_sdl) {
        assert(false);
    } else {
        for (state.rooms) |*smh, i| {
            if (smh.items.len == 0) {
                mapgen.initLevel(i);
            }
        }

        state.player.kill();

        var level: usize = state.PLAYER_STARTING_LEVEL;
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
                        'k' => y -|= tty_height / 2,
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
}

pub fn actualMain() anyerror!void {
    if (std.process.getEnvVarOwned(state.GPA.allocator(), "RL_NO_SENTRY")) |v| {
        state.sentry_disabled = true;
        state.GPA.allocator().free(v);
    } else |_| {
        state.sentry_disabled = false;
    }

    if (!initGame()) {
        deinitGame();
        std.log.err("Unknown error occurred while initializing game.", .{});
        return;
    }
    if (!initLevels()) {
        deinitGame();
        std.log.err("Unknown error occurred while building levels.", .{});
        return;
    }

    ui.draw();

    state.message(.Info, "You've just escaped from prison.", .{});
    state.message(.Info, "Hurry to the stairs before the guards find you!", .{});

    var use_viewer: bool = undefined;

    if (std.process.getEnvVarOwned(state.GPA.allocator(), "RL_MODE")) |v| {
        use_viewer = mem.eql(u8, v, "viewer");
        state.GPA.allocator().free(v);
    } else |_| {
        use_viewer = false;
    }

    if (use_viewer) {
        viewerMain();
    } else {
        while (state.state != .Quit) switch (state.state) {
            .Game => tickGame() catch {},
            .Win => {
                _ = ui.drawContinuePrompt("You escaped!", .{});
                break;
            },
            .Lose => {
                const msg = switch (rng.range(usize, 0, 99)) {
                    0...60 => "You die...",
                    61...70 => "You died. Not surprising given your playstyle.",
                    71...80 => "Geez, you just died.",
                    81...95 => "Congrats! You died!",
                    96...99 => "You acquire Negative Health Syndrome!",
                    else => err.wat(),
                };
                _ = ui.drawContinuePrompt("{s}", .{msg});
                break;
            },
            .Quit => break,
        };
    }

    if (!use_viewer) {
        const info = scores.createMorgue();
        if (state.state != .Quit)
            ui.drawGameOverScreen(info);
    }

    deinitGame();
}

pub fn main() void {
    actualMain() catch |e| {
        if (!state.sentry_disabled) {
            if (@errorReturnTrace()) |error_trace| {
                var membuf: [65535]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);
                var alloc = fba.allocator();

                sentry.captureError(
                    build_options.release,
                    build_options.dist,
                    @errorName(e),
                    "propagated error trace",
                    &[_]sentry.SentryEvent.TagSet.Tag{.{
                        .name = "seed",
                        .value = std.fmt.allocPrint(alloc, "{}", .{rng.seed}) catch unreachable,
                    }},
                    error_trace,
                    null,
                    alloc,
                ) catch |zs_err| {
                    std.log.err("zig-sentry: Fail: {s}", .{@errorName(zs_err)});
                };
            }
        }
    };
}
