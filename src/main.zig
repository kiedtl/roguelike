const builtin = @import("builtin");
const build_options = @import("build_options");

const std = @import("std");
const math = std.math;
const sort = std.sort;
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;

// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const StackBuffer = @import("buffer.zig").StackBuffer;

const ai = @import("ai.zig");
const alert = @import("alert.zig");
const display = @import("display.zig");
const err = @import("err.zig");
const events = @import("events.zig");
const explosions = @import("explosions.zig");
const fire = @import("fire.zig");
const font = @import("font.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const janet = @import("janet.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const mobs = @import("mobs.zig");
const player = @import("player.zig");
const rng = @import("rng.zig");
const scores = @import("scores.zig");
const sentry = @import("sentry.zig");
const serializer = @import("serializer.zig");
const spells = @import("spells.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const tasks = @import("tasks.zig");
const termbox = @import("termbox.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");
const Direction = types.Direction;
const Coord = types.Coord;
const Rect = types.Rect;
const Tile = types.Tile;
const Mob = types.Mob;

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
const PosterList = literature.PosterList;
const EvocableList = items.EvocableList;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub fn log(
    comptime message_level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (message_level == .info and state.log_disabled) return;
    std.log.defaultLog(message_level, scope, format, args);
}

// Install a panic handler that tries to shutdown termbox and print the RNG
// seed before calling sentry and then the default panic handler.
var __panic_stage: usize = 0;
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, x: ?usize) noreturn {
    nosuspend switch (__panic_stage) {
        0 => {
            __panic_stage = 1;
            ui.deinit() catch {};
            std.log.err("Fatal error encountered. (Seed: {})", .{state.seed});

            if (!state.sentry_disabled) {
                var membuf: [65535]u8 = undefined;
                var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);
                const alloc = fba.allocator();

                sentry.captureError(
                    build_options.release,
                    build_options.dist,
                    "Panic",
                    msg,
                    &[_]sentry.SentryEvent.TagSet.Tag{.{
                        .name = "seed",
                        .value = std.fmt.allocPrint(alloc, "{}", .{state.seed}) catch unreachable,
                    }},
                    trace,
                    @returnAddress(),
                    alloc,
                ) catch |e| {
                    std.log.err("zig-sentry: Fail: {s}", .{@errorName(e)});
                };
            }

            std.debug.defaultPanic(msg, x);
        },
        1 => {
            __panic_stage = 2;
            std.debug.defaultPanic(msg, x);
        },
        else => {
            std.posix.abort();
        },
    };
}

fn initGame(no_display: bool, display_scale: f32) bool {
    janet.init() catch return false;
    _ = janet.loadFile("scripts/particles.janet", state.alloc) catch return false;

    font.loadFontsData();
    state.loadStatusStringInfo();
    state.loadLevelInfo();
    surfaces.readProps(state.alloc);
    literature.readPosters(state.alloc);
    literature.readNames(state.alloc);
    mobs.spawns.readSpawnTables(state.alloc);
    mapgen.readPrefabs(state.alloc);
    readDescriptions(state.alloc);

    initGameState();

    if (!no_display) {
        if (ui.init(display_scale)) {} else |e| switch (e) {
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
    }

    return true;
}

fn initGameState() void {
    state.dungeon = state.alloc.create(types.Dungeon) catch err.oom();
    state.dungeon.* = types.Dungeon{};

    rng.init();
    for (&state.floor_seeds) |*seed|
        seed.* = rng.int(u64);

    for (&state.default_patterns) |*r| r.pattern_checker.reset();

    state.memory = state.MemoryTileMap.init(state.alloc);

    state.tasks = TaskArrayList.init(state.alloc);
    state.squads = Squad.List.init(state.alloc);
    state.mobs = MobList.init(state.alloc);
    state.rings = RingList.init(state.alloc);
    state.armors = ArmorList.init(state.alloc);
    state.machines = MachineList.init(state.alloc);
    state.props = PropList.init(state.alloc);
    state.containers = ContainerList.init(state.alloc);
    state.evocables = EvocableList.init(state.alloc);
    state.messages = MessageArrayList.init(state.alloc);

    mapgen.fungi.init();
    mapgen.angels.init();
    alert.init();
    events.init();
    player.choosePlayerUpgrades();
    events.check(0, .InitGameState);
    spells.initAvgWillChances();

    for (&state.dungeon.map, 0..) |*map, level| {
        state.stockpiles[level] = StockpileArrayList.init(state.alloc);
        state.inputs[level] = StockpileArrayList.init(state.alloc);
        state.outputs[level] = Rect.ArrayList.init(state.alloc);
        state.rooms[level] = mapgen.Room.ArrayList.init(state.alloc);

        for (map) |*row| for (row) |*tile| {
            tile.rand = rng.int(usize);
        };
    }
}

fn initLevels() bool {
    var loading_screen = ui.initLoadingScreen();
    defer loading_screen.deinit();

    ui.drawLoadingScreen(&loading_screen, "", "Generating level...", 0) catch return false;
    mapgen.initLevel(state.PLAYER_STARTING_LEVEL);

    return ui.drawLoadingScreenFinish(&loading_screen);
}

fn deinitGame() void {
    ui.deinit() catch {};

    mapgen.s_fabs.deinit();
    mapgen.n_fabs.deinit();
    state.fab_records.deinit();

    deinitGameState();

    {
        var iter = literature.posters.iterator();
        while (iter.next()) |poster|
            poster.deinit(state.alloc);
    }
    literature.posters.deinit();

    janet.deinit();
    font.freeFontData();
    state.freeStatusStringInfo();
    state.freeLevelInfo();
    surfaces.freeProps(state.alloc);
    mobs.spawns.freeSpawnTables(state.alloc);
    freeDescriptions(state.alloc);
    literature.freeNames(state.alloc);

    _ = state.gpa.deinit();
}

fn deinitGameState() void {
    state.memory.clearAndFree();

    {
        var iter = state.mobs.iterator();
        while (iter.next()) |mob| {
            if (mob.is_dead) continue;
            mob.deinitNoCorpse();
        }
    }
    {
        var s_iter = state.squads.iterator();
        while (s_iter.next()) |squad|
            squad.deinit();
    }

    for (state.dungeon.map, 0..) |_, level| {
        state.stockpiles[level].deinit();
        state.inputs[level].deinit();
        state.outputs[level].deinit();
        state.rooms[level].deinit();
    }

    state.tasks.deinit();
    state.squads.deinit();
    state.mobs.deinit();
    state.rings.deinit();
    state.armors.deinit();
    state.machines.deinit();
    state.messages.deinit();
    state.props.deinit();
    state.containers.deinit();
    state.evocables.deinit();

    mapgen.fungi.deinit();
    mapgen.angels.deinit();
    alert.deinit();
    events.deinit();

    state.player_inited = false;
    state.alloc.destroy(state.dungeon);
}

fn readDescriptions(alloc: mem.Allocator) void {
    state.descriptions = @TypeOf(state.descriptions).init(alloc);

    const data_dir = std.fs.cwd().openDir("data/des", .{ .iterate = true }) catch err.wat();
    var data_dir_iterator = data_dir.iterate();
    while (data_dir_iterator.next() catch err.wat()) |data_f| {
        if (data_f.kind != .file) continue;
        var data_file = data_dir.openFile(data_f.name, .{}) catch err.wat();
        defer data_file.close();

        const filesize = data_file.getEndPos() catch err.wat();
        const filebuf = alloc.alloc(u8, @intCast(filesize)) catch err.wat();
        defer alloc.free(filebuf);
        const read = data_file.readAll(filebuf[0..]) catch err.wat();

        var lines = mem.splitScalar(u8, filebuf[0..read], '\n');
        var current_desc_id: ?[]const u8 = null;
        var current_desc = StackBuffer(u8, 4096).init(null);

        const S = struct {
            pub fn _finishDescEntry(fname: []const u8, id: []const u8, desc: []const u8, a: mem.Allocator) void {
                const key = a.alloc(u8, id.len) catch err.wat();
                mem.copyForwards(u8, key, id);

                const val = a.alloc(u8, desc.len) catch err.wat();
                mem.copyForwards(u8, val, desc);

                state.descriptions.putNoClobber(key, val) catch err.bug(
                    "{s}: Duplicate description {s} found",
                    .{ fname, key },
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
                        S._finishDescEntry(data_f.name, id, current_desc.constSlice(), alloc);

                        current_desc.clear();
                        current_desc_id = null;
                    }

                    if (line.len <= 2) err.bug("{s}: Missing desc ID", .{data_f.name});
                    current_desc_id = line[2..];
                } else {
                    if (current_desc_id == null) {
                        err.bug("{s}: Description without ID", .{data_f.name});
                    }

                    current_desc.appendSlice(line) catch err.wat();
                    prev_was_nl = true;
                }
            }
        }

        S._finishDescEntry(data_f.name, current_desc_id.?, current_desc.constSlice(), alloc);
        std.log.info("Loaded description data (data/des/{s}).", .{data_f.name});
    }
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

    var evgen = display.getEvents(timeout);
    while (evgen.next()) |e| switch (e) {
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
    };

    if (state.state == .Quit) return error.Quit;
    ui.draw();
}

fn readInput() !bool {
    if (state.state == .Quit) return error.Quit;
    var action_taken = false;

    var evgen = display.getEvents(ui.FRAMERATE);
    while (evgen.next()) |ev| {
        switch (ev) {
            .Quit => state.state = .Quit,
            .Resize => ui.draw(),
            .Wheel, .Hover, .Click => if (ui.handleMouseEvent(ev)) {
                ui.draw();
            },
            .Key => |k| {
                switch (k) {
                    .Esc => ui.drawEscapeMenu(),
                    .CtrlC => state.state = .Quit,
                    .F1 => ui.drawWizScreen(),
                    else => {},
                }
                ui.draw();
            },
            .Char => |c| {
                switch (c) {
                    ' ' => _ = ui.drawZapScreen(),
                    '\'' => {
                        state.player.swapWeapons();
                        if (state.player.inventory.equipment(.Weapon).*) |weapon| {
                            state.message(.Inventory, "Now wielding a {s}.", .{
                                (weapon.longName() catch err.wat()).constSlice(),
                            });
                        } else {
                            state.message(.Inventory, "You aren't wielding anything now.", .{});
                        }
                    },
                    'A' => action_taken = player.activateSurfaceItem(state.player.coord),
                    'i' => action_taken = ui.drawInventoryScreen(),
                    'v' => action_taken = ui.drawExamineScreen(null, null),
                    '@' => ui.drawPlayerInfoScreen(),
                    'M' => ui.drawMessagesScreen(),
                    ',' => action_taken = player.grabItem(),
                    's', '.' => action_taken = player.tryRest(),
                    'q', 'y' => action_taken = player.moveOrFight(.NorthWest),
                    'w', 'k' => action_taken = player.moveOrFight(.North),
                    'e', 'u' => action_taken = player.moveOrFight(.NorthEast),
                    'd', 'l' => action_taken = player.moveOrFight(.East),
                    'c', 'n' => action_taken = player.moveOrFight(.SouthEast),
                    'x', 'j' => action_taken = player.moveOrFight(.South),
                    'z', 'b' => action_taken = player.moveOrFight(.SouthWest),
                    'a', 'h' => action_taken = player.moveOrFight(.West),
                    else => {},
                }
                ui.draw();
            },
        }
        if (action_taken) break;
    }

    if (state.state == .Quit) return error.Quit;
    return action_taken;
}

fn tickGame(p_cur_level: ?usize) !void {
    if (state.state != .Viewer and state.player.is_dead) {
        state.state = .Lose;
        return;
    }

    const cur_level = p_cur_level orelse state.current_level;

    assert(state.state == .Viewer or state.player.coord.z == state.current_level);

    state.ticks += 1;
    surfaces.tickMachines(cur_level);
    fire.tickFire(cur_level);
    gas.tickGasEmitters(cur_level);
    gas.tickGases(cur_level);
    state.tickSound(cur_level);
    state.tickLight(cur_level);
    alert.tickThreats(cur_level);

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
                assert(state.state != .Viewer);
                ui.draw();
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
            mob.tickMorale();
            mob.tickFOV();
            mob.tickDisruption();
            mob.tickStatuses();

            if (mob == state.player) {
                assert(state.state != .Viewer);
                state.player_turns += 1;
                scores.recordUsize(.TurnsSpent, 1);
                player.bookkeepingFOV();
                player.checkForGarbage();
            }

            mob.assertIsAtLocation();

            if (mob.isUnderStatus(.Paralysis)) |_| {
                if (mob == state.player) {
                    var frames: usize = 5;
                    while (frames > 0) : (frames -= 1)
                        try readNoActionInput(ui.FRAMERATE);
                }

                mob.rest();
                continue;
            } else {
                if (mob == state.player) {
                    ui.draw();
                    if (state.state == .Quit) break;
                    while (!try readInput())
                        ui.drawAnimations();
                    ui.draw();
                    if (state.state == .Quit) break;
                } else {
                    ai.main(mob);
                }
            }

            if (mob.is_dead) break;

            // Dupe of code at start of function
            if (state.player.should_be_dead()) {
                state.player.kill();
            }
            if (state.state != .Viewer and state.player.is_dead) {
                state.state = .Lose;
                return;
            }

            mob.assertIsAtLocation();
            if (mob == state.player or state.player.canSeeMob(mob))
                mob.tickFOV();

            if (mob == state.player) {
                assert(state.state != .Viewer);
                player.bookkeepingFOV();
            }

            const _j = if (mob.newestJob()) |j| j.job else .Dummy;
            err.ensure(prev_energy > mob.energy, "{cf} (phase: {}; job: {}) did nothing during turn!", .{ mob, mob.ai.phase, _j }) catch {
                ai.tryRest(mob);
            };

            if (state.state != .Viewer and
                actions_taken > 1 and state.player.cansee(mob.coord))
            {
                ui.draw();
                try readNoActionInput(130);
            }
        }

        if (!mob.is_dead and mob.should_be_dead()) {
            mob.kill();
            continue;
        }
    }
}

fn viewerDisplay(tty_height: usize, sy: usize) void {
    var dy: usize = sy;
    var y: usize = 0;
    while (y < tty_height and dy < HEIGHT) : ({
        y += 1;
        dy += 1;
    }) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const t = Tile.displayAs(Coord.new2(state.current_level, x, dy), false, false);
            display.setCell(x, y, t);
        }
    }
    while (y < tty_height) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            termbox.tb_change_cell(@intCast(x), @intCast(y), ' ', 0, 0);
        }
    }
    termbox.tb_present();
}

fn viewerMain() void {
    // const RUNS = 60;

    // var open_space_min: usize = 100;
    // var open_space_max: usize = 0;
    // var open_space_total_percent: usize = 0;

    // var j: usize = RUNS;
    // while (j > 0) : (j -= 1) {
    //     state.floor_seeds[0] = @intCast(u64, std.time.milliTimestamp());
    //     mapgen.resetLevel(0);
    //     mapgen.initLevel(0);

    //     var open_space_rtotal_: usize = 0;
    //     var open_space_ctotal_: usize = 0;
    //     var open_space_total_: usize = 0;
    //     for (state.rooms[0].items) |room| {
    //         open_space_total_ += room.rect.height * room.rect.width;
    //         if (room.type == .Corridor)
    //             open_space_ctotal_ += room.rect.height * room.rect.width
    //         else
    //             open_space_rtotal_ += room.rect.height * room.rect.width;
    //     }

    //     const open_space_percent_ = open_space_total_ * 100 / (WIDTH * HEIGHT);
    //     // const open_space_rpercent_ = open_space_rtotal_ / (WIDTH * HEIGHT);
    //     // const open_space_cpercent_ = open_space_ctotal_ / (WIDTH * HEIGHT);

    //     if (open_space_min > open_space_percent_)
    //         open_space_min = open_space_percent_;
    //     if (open_space_max < open_space_percent_)
    //         open_space_max = open_space_percent_;
    //     open_space_total_percent += open_space_percent_;

    //     std.log.info("try {} ({}%)", .{ j, open_space_percent_ });
    // }

    // const avg = open_space_total_percent / RUNS;
    // std.log.info("Average% open space: {}", .{avg});
    // std.log.info("Min open space: {}", .{open_space_min});
    // std.log.info("Max open space: {}", .{open_space_max});
    // std.log.info("Deviation: ±{}", .{dev});

    // if (true) return;
    //
    // if (true) {
    //     var i: usize = 100000;
    //     while (i > 0) : (i -= 1) {
    //         const ring = items.createItemFromTemplate(mapgen.chooseRing(true));
    //         std.log.info("Chose ring {s}", .{ring.Ring.name});
    //     }
    //     return;
    // }

    // Wrap whole thing in comptime if condition to ensure no linker errors
    if (build_options.use_sdl) {
        err.fatal("Viewer not available when compiled in SDL2 mode", .{});
    } else {
        // mapgen.initLevel(11);
        // state.current_level = 11;
        for (&state.rooms, 0..) |*smh, i| {
            if (smh.items.len == 0) {
                mapgen.initLevel(i);
            }
        }

        state.player.kill();

        var y: usize = 0;
        var running: bool = false;

        const tty_height: usize = @intCast(termbox.tb_height());

        while (true) {
            viewerDisplay(tty_height, y);

            var ev: termbox.tb_event = undefined;
            var t: isize = 0;

            if (running) {
                t = termbox.tb_peek_event(&ev, 150);
                if (t == 0) {
                    tickGame(state.current_level) catch {};
                    continue;
                }
            } else {
                t = termbox.tb_poll_event(&ev);
            }

            if (t == -1) @panic("Fatal termbox error");

            if (t == termbox.TB_EVENT_KEY) {
                if (ev.key != 0) {
                    switch (ev.key) {
                        termbox.TB_KEY_CTRL_C => break,
                        // termbox.TB_KEY_F7 => {
                        //     serializer.serializeWorld() catch err.wat();
                        //     serializer.deserializeWorld() catch err.wat();
                        // },
                        else => {},
                    }
                } else if (ev.ch != 0) {
                    switch (ev.ch) {
                        '.' => tickGame(state.current_level) catch {},
                        'r' => {
                            state.floor_seeds[state.current_level] = rng.int(u64);
                            mapgen.initLevel(state.current_level);
                        },
                        'a' => running = !running,
                        'j' => if (y < HEIGHT) {
                            y = @min(y + (tty_height / 2), HEIGHT - 1);
                        },
                        'k' => y -|= tty_height / 2,
                        'e' => explosions.kaboom(
                            Coord.new2(
                                state.current_level,
                                rng.range(usize, 20, WIDTH - 20),
                                rng.range(usize, 20, HEIGHT - 20),
                            ),
                            .{ .strength = rng.range(usize, 400, 1500) },
                        ),
                        '<' => if (state.current_level > 0) {
                            state.current_level -= 1;
                        },
                        '>' => if (state.current_level < (LEVELS - 1)) {
                            state.current_level += 1;
                        },
                        else => {},
                    }
                } else err.wat();
            }
        }
    }
}

fn testerMain() void {
    state.sentry_disabled = true;
    state.log_disabled = true;

    assert(initGame(true, 0));

    const Error = error{ Failed, BasicFailed };

    const TestContext = struct {
        alloc: mem.Allocator,

        current_suite: []const u8 = undefined,
        current_test: []const u8 = undefined,

        total_asserts: usize = 0,
        failed: usize = 0,
        succeeded: usize = 0,
        total: usize = 0,

        errors: std.ArrayList([]const u8),

        pub fn record(x: *@This(), comptime fmt: []const u8, args: anytype) void {
            if (builtin.strip_debug_info) return;
            const debug_info = std.debug.getSelfDebugInfo() catch err.wat();
            const startaddr = @returnAddress();
            if (builtin.os.tag == .windows) {
                @panic("Unimplemented backtrace for windows, blurrg.");
            } else {
                var it = std.debug.StackIterator.init(startaddr, null);
                _ = it.next().?;
                const retaddr = it.next().?;

                const module = debug_info.getModuleForAddress(retaddr) catch err.wat();
                const symb_info = module.getSymbolAtAddress(state.alloc, retaddr) catch err.wat();
                // MIGRATION defer symb_info.deinit(state.alloc);
                const str = std.fmt.allocPrint(x.alloc, "{s}:{s} ({})\t" ++ fmt ++ "\n", .{
                    x.current_suite, x.current_test, symb_info.source_location.?.line,
                } ++ args) catch err.wat();
                x.errors.append(str) catch err.wat();
            }
        }

        pub fn assertT(x: *@This(), b: bool, comptime c_fmt: []const u8, c_args: anytype) Error!void {
            x.total_asserts += 1;
            if (!b) {
                x.record("Expected true (" ++ c_fmt ++ ")", c_args);
                return error.Failed;
            }
        }

        pub fn assertF(x: *@This(), b: bool, comptime c_fmt: []const u8, c_args: anytype) Error!void {
            x.total_asserts += 1;
            if (b) {
                x.record("Expected false (" ++ c_fmt ++ ")", c_args);
                return error.Failed;
            }
        }

        pub fn assertEq(x: *@This(), a: anytype, b: @TypeOf(a), comptime c_fmt: []const u8, c_args: anytype) Error!void {
            x.total_asserts += 1;
            if (a != b) {
                x.record("Expected equality ({} != {}) (" ++ c_fmt ++ ")", .{ a, b } ++ c_args);
                return error.Failed;
            }
        }

        pub fn assertNotNull(x: *@This(), a: anytype, comptime c_fmt: []const u8, c_args: anytype) Error!void {
            x.total_asserts += 1;
            if (a == null) {
                x.record("Got null (" ++ c_fmt ++ ")", c_args);
                return error.Failed;
            }
        }

        pub fn getMob(x: *@This(), tag: u8) Error!*Mob {
            var i = state.mobs.iteratorReverse();
            return while (i.next()) |mob| {
                if (mob.tag == tag) break mob;
            } else {
                x.record("No such mob tagged '{u}'", .{tag});
                return error.BasicFailed;
            };
        }

        // For some reason this isn't getting called w/ defer in Zig 0.9.1...
        // So I manually free it in the main loop.
        pub fn deinit(x: *@This()) void {
            // do nothing, test in zig v12
            _ = x;
        }
    };

    const Test = struct {
        name: []const u8,
        prefab: []const u8,
        initial_setup: ?*const fn (*TestContext) Error!void,
        initial_ticks: usize,
        fun: *const fn (*TestContext) Error!void,
        entry: bool,

        pub fn n(name: []const u8, fab: []const u8, ticks: usize, f1: ?*const fn (*TestContext) Error!void, f2: *const fn (*TestContext) Error!void, entry: bool) @This() {
            return .{ .name = name, .prefab = fab, .initial_setup = f1, .initial_ticks = ticks, .fun = f2, .entry = entry };
        }
    };

    const TestGroup = struct {
        name: []const u8,
        tests: []const Test,
    };

    const TESTS = [_]TestGroup{
        .{
            .name = "data_files",
            .tests = &[_]Test{
                Test.n("mob_spawns", "TEST_dummy", 0, null, struct {
                    pub fn f(x: *TestContext) !void {
                        for (mobs.spawns.TABLES, 0..) |spawn_table, i|
                            for (spawn_table) |table|
                                for (table.items) |spawn_info| {
                                    try x.assertNotNull(
                                        mobs.findMobById(spawn_info.id),
                                        "table: {}, id: {s}",
                                        .{ i, spawn_info.id },
                                    );
                                };
                    }
                }.f, false),
            },
        },
        .{
            .name = "basic_systems",
            .tests = &[_]Test{
                Test.n("gas_no_effect_on_unbreathing", "TEST_gas_rFume", 5, struct {
                    pub fn f(x: *TestContext) !void {
                        state.dungeon.atGas((try x.getMob('2')).coord)[gas.Paralysis.id] = 100;
                    }
                }.f, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertT((try x.getMob('0')).hasStatus(.Paralysis), "", .{});
                        try x.assertF((try x.getMob('1')).hasStatus(.Paralysis), "", .{});
                        try x.assertF((try x.getMob('2')).hasStatus(.Paralysis), "", .{});
                        try x.assertF((try x.getMob('3')).hasStatus(.Paralysis), "", .{});
                        try x.assertF((try x.getMob('4')).hasStatus(.Paralysis), "", .{});
                    }
                }.f, false),
                // ---
                Test.n("gas_no_pass_through_walls", "TEST_gas_no_pass_through_walls", 6, struct {
                    pub fn f(x: *TestContext) !void {
                        state.dungeon.atGas((try x.getMob('A')).coord)[gas.Paralysis.id] = 100;
                    }
                }.f, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertT((try x.getMob('A')).hasStatus(.Paralysis), "", .{});
                        try x.assertF((try x.getMob('B')).hasStatus(.Paralysis), "", .{});
                    }
                }.f, false),
                // ---
                Test.n("gas_effect_on_unbreathing_if_not_breathed", "TEST_gas_rFume2", 10, struct {
                    pub fn f(x: *TestContext) !void {
                        state.dungeon.atGas((try x.getMob('0')).coord)[gas.Corrosive.id] = 100;
                        state.dungeon.atGas((try x.getMob('1')).coord)[gas.Corrosive.id] = 100;
                    }
                }.f, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertT((try x.getMob('0')).is_dead, "", .{});
                        try x.assertT((try x.getMob('1')).is_dead, "", .{});
                    }
                }.f, false),
                // ---
                Test.n("gas_works_in_tandem", "TEST_gas_works_in_tandem", 10, struct {
                    pub fn f(x: *TestContext) !void {
                        state.dungeon.atGas((try x.getMob('B')).coord)[gas.Paralysis.id] = 100;
                        state.dungeon.atGas((try x.getMob('B')).coord)[gas.Seizure.id] = 100;
                        state.dungeon.atGas((try x.getMob('B')).coord)[gas.Miasma.id] = 100;
                        state.dungeon.atGas((try x.getMob('B')).coord)[gas.Blinding.id] = 100;
                    }
                }.f, struct {
                    pub fn f(x: *TestContext) !void {
                        for (@as([]const u8, "ABCD")) |subject|
                            for (&[_]types.Status{ .Paralysis, .Debil, .Nausea, .Blind }) |status|
                                try x.assertT(
                                    (try x.getMob(subject)).hasStatus(status),
                                    "subject: {u}; status: {}",
                                    .{ subject, status },
                                );
                    }
                }.f, false),
                // ---
                Test.n("gas_pass_through_if_porous", "TEST_gas_pass_through_if_porous", 3, struct {
                    pub fn f(x: *TestContext) !void {
                        state.dungeon.atGas((try x.getMob('A')).coord)[gas.Paralysis.id] = 100;
                    }
                }.f, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertT((try x.getMob('B')).hasStatus(.Paralysis), "", .{});
                        try x.assertT((try x.getMob('C')).hasStatus(.Paralysis), "", .{});
                        try x.assertF((try x.getMob('D')).hasStatus(.Paralysis), "", .{});
                        try x.assertF((try x.getMob('E')).hasStatus(.Paralysis), "", .{});
                    }
                }.f, false),
                // ---
                Test.n("gas_eventually_dissipates", "TEST_gas_eventually_dissipates", 15, struct {
                    pub fn f(x: *TestContext) !void {
                        // Choose one w/ high dissipation rate so we don't have to do 40 ticks
                        state.dungeon.atGas((try x.getMob('A')).coord)[gas.Dust.id] = 100;
                    }
                }.f, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertEq(state.dungeon.atGas((try x.getMob('A')).coord)[gas.Paralysis.id], 0, "", .{});
                    }
                }.f, false),
                // ---
                Test.n("light_opacity_checks", "TEST_light_opacity_checks", 1, struct {
                    pub fn f(x: *TestContext) !void {
                        state.dungeon.atGas((try x.getMob('X')).coord)[gas.Darkness.id] = 100;
                    }
                }.f, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertF((try x.getMob('A')).isLit(), "", .{});
                        try x.assertT((try x.getMob('B')).isLit(), "", .{});
                        try x.assertT((try x.getMob('C')).isLit(), "", .{});
                        try x.assertF((try x.getMob('D')).isLit(), "", .{});
                    }
                }.f, false),
                // ---
            },
        },
        .{
            .name = "combat_ai",
            .tests = &[_]Test{
                Test.n("enters_combat_mode", "TEST_combat_ai_enters_combat", 2, null, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertT((try x.getMob('A')).isHostileTo(try x.getMob('B')), "", .{});
                        try x.assertEq((try x.getMob('A')).ai.phase, .Hunt, "", .{});
                    }
                }.f, true),
                // ---
                Test.n("melee_fight", "TEST_combat_ai_melee_fight", 8, null, struct {
                    pub fn f(x: *TestContext) !void {
                        const A = try x.getMob('A');
                        const C = try x.getMob('C');
                        // A gotta be right next to B, since it should be fighting it
                        try x.assertEq(A.distance2(C.coord), 1, "", .{});
                        try x.assertF((try x.getMob('B')).is_dead, "", .{}); // should be ignored
                        try x.assertT(C.is_dead, "", .{});
                        try x.assertF((try x.getMob('D')).is_dead, "", .{}); // too far away
                        // Still got that D mob to kill
                        try x.assertEq(A.ai.phase, .Hunt, "", .{});
                    }
                }.f, true),
                // ---
                Test.n("slaughter", "TEST_combat_ai_slaughter", 50, null, struct {
                    pub fn f(x: *TestContext) !void {
                        const A = try x.getMob('A');
                        try x.assertEq(A.distance2((try x.getMob('B')).coord), 1, "", .{});
                        for ("LKJIHGFEDCB") |enemy|
                            try x.assertT((try x.getMob(enemy)).is_dead, "mob: {u}", .{enemy});
                    }
                }.f, true),
                // ---
                Test.n("simple_spell_use", "TEST_combat_ai_simple_spell_use", 1, null, struct {
                    pub fn f(x: *TestContext) !void {
                        try x.assertEq((try x.getMob('J')).ai.phase, .Hunt, "", .{});
                        try x.assertT((try x.getMob('T')).is_dead, "", .{});
                    }
                }.f, true),
                // ---
                Test.n("checkForAllies", "TEST_combat_ai_checkForAllies", 2, null, struct {
                    pub fn f(x: *TestContext) !void {
                        const a = try x.getMob('A');
                        // NOTE: it doesn't have to be in this order, b could
                        // come before c, but due to checkForAllies'
                        // implementation (iterating over each x and y) it will
                        // always be in this order. Kinda fragile testing like
                        // this though.
                        try x.assertEq(a.allies.items[0], try x.getMob('C'), "", .{});
                        try x.assertEq(a.allies.items[1], try x.getMob('B'), "", .{});
                        try x.assertEq(a.allies.items.len, 2, "", .{});
                    }
                }.f, true),
                // ---
                Test.n("social_fighter", "TEST_combat_ai_social_fighter", 2, null, struct {
                    pub fn f(x: *TestContext) !void {
                        for ("ADE") |m|
                            try x.assertF((try x.getMob(m)).is_dead, "mob: {u}", .{m});
                        for ("BCF") |m|
                            try x.assertT((try x.getMob(m)).is_dead, "mob: {u}", .{m});
                    }
                }.f, true),
                // ---
            },
        },
    };

    const stdout = std.io.getStdOut().writer();
    var ctx = TestContext{
        .alloc = state.alloc,
        .errors = std.ArrayList([]const u8).init(state.alloc),
    };
    defer ctx.deinit();

    stdout.print("*** Starting test suites\n", .{}) catch {};

    for (&TESTS, 0..) |test_group, j| {
        ctx.current_suite = test_group.name;
        if (j != 0) stdout.print("\n", .{}) catch {};
        stdout.print("--- Beginning test suite '{s}'; {} test(s)", .{ // deliberately omit newline
            test_group.name, test_group.tests.len,
        }) catch {};
        for (test_group.tests, 0..) |testg, i| {
            ctx.current_test = testg.name;
            ctx.total += 1;

            if (i % 60 == 0) stdout.print("\n    ", .{}) catch {};

            if (!(j == 0 and i == 0))
                initGameState();
            defer deinitGameState();

            mapgen.initLevelTest(testg.prefab, testg.entry) catch |e| switch (e) {
                error.NoSuchPrefab => {
                    ctx.failed += 1;
                    ctx.record("No such prefab '{s}'", .{testg.prefab});
                    stdout.print("P", .{}) catch {};
                    continue;
                },
            };

            if (testg.initial_setup) |fun| {
                fun(&ctx) catch |e| {
                    ctx.failed += 1;
                    stdout.print("I", .{}) catch {};
                    ctx.record("Initial setup error: {}", .{e});
                    continue;
                };
            }

            var t = testg.initial_ticks;
            while (t > 0) : (t -= 1)
                tickGame(0) catch |e| {
                    ctx.failed += 1;
                    ctx.record("Tick error: {}", .{e});
                    stdout.print("T", .{}) catch {};
                    continue;
                };

            if (testg.fun(&ctx)) |_| {
                ctx.succeeded += 1;
                stdout.print(".", .{}) catch {};
            } else |e| switch (e) {
                error.BasicFailed => {
                    ctx.failed += 1;
                    stdout.print("B", .{}) catch {};
                },
                error.Failed => {
                    ctx.failed += 1;
                    stdout.print("F", .{}) catch {};
                },
            }
        }
    }

    stdout.print("\n---\n", .{}) catch {};
    stdout.print("*** Completed {} suites with {} tests and {} asserts.\n", .{
        TESTS.len, ctx.total, ctx.total_asserts,
    }) catch {};
    stdout.print("    {} succeeded, {} failed, 0 skipped.\n", .{
        ctx.succeeded, ctx.failed,
    }) catch {};
    for (ctx.errors.items) |str| {
        stdout.print("FAIL: {s}", .{str}) catch {};
        ctx.alloc.free(str);
    }
    ctx.errors.deinit();

    // XXX: stupid hack: init game state again to prevent crash when deinitGame()
    // is called :))
    initGameState();

    deinitGame();

    std.posix.exit(if (ctx.failed > 0) 1 else 0);
}

fn profilerMain() void {
    // const LEVEL = 0;

    std.log.info("[ Seed: {} ]", .{state.seed});

    state.sentry_disabled = true;
    assert(initGame(true, 0));
    defer deinitGame();

    mapgen.initLevelTest("PRF1_combat", true) catch err.wat();

    var i: usize = 200;
    while (i > 0) : (i -= 1) {
        var alive_nec: [2]usize = [2]usize{ 0, 0 };
        var alive_rev: [2]usize = [2]usize{ 0, 0 };
        var alive_cav: [2]usize = [2]usize{ 0, 0 };
        var alive_drk: [2]usize = [2]usize{ 0, 0 };
        var alive_hly: [2]usize = [2]usize{ 0, 0 };

        var iter = state.mobs.iterator();
        while (iter.next()) |mob| if (!mob.is_dead) {
            switch (mob.faction) {
                .Necromancer => {
                    if (mob.ai.phase == .Flee) alive_nec[0] += 1;
                    alive_nec[1] += 1;
                },
                .Revgenunkim => {
                    if (mob.ai.phase == .Flee) alive_rev[0] += 1;
                    alive_rev[1] += 1;
                },
                .CaveGoblins => {
                    if (mob.ai.phase == .Flee) alive_cav[0] += 1;
                    alive_cav[1] += 1;
                },
                .Night => {
                    if (mob.ai.phase == .Flee) alive_drk[0] += 1;
                    alive_drk[1] += 1;
                },
                .Holy => {
                    if (mob.ai.phase == .Flee) assert(false); //alive_hly[0] += 1;
                    alive_hly[1] += 1;
                },
                .Player => err.wat(),
                .Vermin => {},
            }
        };

        std.log.info("{}\tnec: {} ({})\tcav: {} ({})\trev: {} ({})\tnight: {} ({})\tholy: {} ({})", .{
            i,            alive_nec[0], alive_nec[1], alive_cav[0], alive_cav[1],
            alive_rev[0], alive_rev[1], alive_drk[0], alive_drk[1], alive_hly[0],
            alive_hly[1],
        });

        tickGame(0) catch err.wat();

        // mapgen.initLevel(LEVEL);
        // mapgen.resetLevel(LEVEL);
    }
}

fn analyzerMain() void {
    state.sentry_disabled = true;
    assert(initGame(true, 0));
    defer deinitGame();
    deinitGameState();

    var arena = std.heap.ArenaAllocator.init(state.alloc);
    defer arena.deinit();

    var ITERS: usize = 20;
    if (std.process.getEnvVarOwned(state.alloc, "RL_AN_ITERS")) |v| {
        defer state.alloc.free(v);
        ITERS = std.fmt.parseInt(u64, v, 0) catch |e| b: {
            std.log.err("Could not parse RL_AN_ITERS (reason: {}); using default.", .{e});
            break :b 20;
        };
    } else |_| {}

    var results: [999][LEVELS]mapgen.LevelAnalysis = undefined;

    var i: usize = 0;
    while (i < ITERS) : (i += 1) {
        state.seed = @intCast(std.time.milliTimestamp());
        std.log.info("*** \x1b[94;1m ITERATION \x1b[m {} (seed: {})", .{ i, state.seed });
        initGameState();

        const S = state.PLAYER_STARTING_LEVEL;

        // Gotta place the player first or everything crumbles...
        mapgen.initLevel(S);
        results[i][S] = mapgen.analyzeLevel(S, arena.allocator()) catch err.wat();

        for (state.levelinfo, 0..) |_, z| if (z != S)
            mapgen.initLevel(z);
        for (state.levelinfo, 0..) |_, z| if (z != S) {
            results[i][z] = mapgen.analyzeLevel(z, arena.allocator()) catch err.wat();
        };

        for (state.levelinfo, 0..) |_, z|
            mapgen.resetLevel(z);

        deinitGameState();

        // Re-init prefabs.
        //
        // We shouldn't have to do this, but events.executeGlobalEvents() modifies
        // this stuff...
        //
        // FIXME
        mapgen.s_fabs.deinit();
        mapgen.n_fabs.deinit();
        mapgen.readPrefabs(state.alloc);
    }

    std.json.stringify(results[0..ITERS], .{}, std.io.getStdOut().writer()) catch err.wat();

    // Another hack for babysitting deinitGame()...
    initGameState();
}

pub fn actualMain() anyerror!void {
    var use_viewer = false;
    var use_tester = false;
    var use_profiler = false;
    var use_analyzer = false;

    if (std.process.getEnvVarOwned(state.alloc, "RL_MODE")) |v| {
        if (mem.eql(u8, v, "viewer")) {
            state.state = .Viewer;
            use_viewer = true;
        } else if (mem.eql(u8, v, "tester")) {
            state.state = .Viewer;
            use_tester = true;
        } else if (mem.eql(u8, v, "profiler1")) {
            state.state = .Viewer;
            use_profiler = true;
        } else if (mem.eql(u8, v, "analyzer")) {
            state.state = .Viewer;
            use_analyzer = true;
        }
        state.alloc.free(v);
    } else |_| {
        use_viewer = false;
        use_tester = false;
    }

    if (std.process.getEnvVarOwned(state.alloc, "RL_SEED")) |seed_str| {
        defer state.alloc.free(seed_str);
        state.seed = std.fmt.parseInt(u64, seed_str, 0) catch |e| b: {
            std.log.err("Could not parse RL_SEED (reason: {}); using default.", .{e});
            break :b 0;
        };
    } else |_| {
        state.seed = @intCast(std.time.milliTimestamp());
    }
    std.log.info("Seed: {}", .{state.seed});

    if (use_tester) {
        testerMain();
        return;
    } else if (use_profiler) {
        profilerMain();
        return;
    } else if (use_analyzer) {
        analyzerMain();
        return;
    }

    if (std.process.getEnvVarOwned(state.alloc, "RL_NO_SENTRY")) |v| {
        state.sentry_disabled = true;
        state.alloc.free(v);
    } else |_| {
        // state.sentry_disabled = false;
        state.sentry_disabled = true;
    }

    var scale: f32 = 1;
    if (std.process.getEnvVarOwned(state.alloc, "RL_DISPLAY_SCALE")) |v| {
        if (std.fmt.parseFloat(f32, v)) |val| {
            scale = val;
        } else |e| {
            std.log.err("Could not parse RL_DISPLAY_SCALE (reason: {}); using default.", .{e});
        }
        state.alloc.free(v);
    } else |_| {}

    if (!initGame(false, scale)) {
        deinitGame();
        std.log.err("Unknown error occurred while initializing game.", .{});
        return;
    }
    if (!initLevels()) {
        deinitGame();
        std.log.err("Canceled.", .{});
        return;
    }

    ui.draw();

    state.message(.Info, "You've just escaped from prison.", .{});
    state.message(.Info, "Hurry to the stairs before the guards find you!", .{});

    if (use_viewer) {
        viewerMain();
    } else {
        while (state.state != .Quit) switch (state.state) {
            .Game => tickGame(null) catch {},
            .Win => {
                _ = ui.drawContinuePrompt("You escaped!", .{});
                break;
            },
            .Lose => {
                const msg = switch (rng.range(usize, 0, 99)) {
                    0...90 => "You die...",
                    95...99 => "You failed to escape.",
                    else => if (rng.tenin(15)) b: {
                        break :b "You received the penalty for treason: death.";
                    } else b: {
                        break :b switch (rng.range(usize, 0, 13)) {
                            0...1 => "Uh, you just died.",
                            2...3 => "You died. Unsurprising, given your playstyle.",
                            4...5 => "You died. (Skill issue.)",
                            6...7 => "Congrats! You died!",
                            8...9 => "You acquire Negative Health Syndrome!",
                            10...11 => "You acquire Negative Health Syndrome!",
                            else => "You did the thing!! You died!!! Congrats!!!!",
                        };
                    },
                };
                _ = ui.drawContinuePrompt("{s}", .{msg});
                break;
            },
            .Quit => break,
            .Viewer => err.wat(),
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
                const alloc = fba.allocator();

                sentry.captureError(
                    build_options.release,
                    build_options.dist,
                    @errorName(e),
                    "propagated error trace",
                    &[_]sentry.SentryEvent.TagSet.Tag{.{
                        .name = "seed",
                        .value = std.fmt.allocPrint(alloc, "{}", .{state.seed}) catch unreachable,
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
