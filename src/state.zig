const std = @import("std");
const mem = std.mem;
const math = std.math;
const sort = std.sort;
const assert = std.debug.assert;
const enums = std.enums;

const strig = @import("strig");

const ai = @import("ai.zig");
const alert = @import("alert.zig");
const astar = @import("astar.zig");
const dijkstra = @import("dijkstra.zig");
const display = @import("display.zig");
const err = @import("err.zig");
const events = @import("events.zig");
const fire = @import("fire.zig");
const fov = @import("fov.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const mobs_m = @import("mobs.zig");
const player_m = @import("player.zig");
const rng = @import("rng.zig");
const scores = @import("scores.zig");
const tsv = @import("tsv.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

const ArmorList = types.ArmorList;
const ContainerList = types.ContainerList;
const Coord = types.Coord;
const Direction = types.Direction;
const Dungeon = types.Dungeon;
const Fuse = @import("fuses.zig").Fuse;
const Item = types.Item;
const MachineList = types.MachineList;
const MessageArrayList = types.MessageArrayList;
const Message = types.Message;
const MessageType = types.MessageType;
const MobArrayList = types.MobArrayList;
const MobList = types.MobList;
const Mob = types.Mob;
const PropList = types.PropList;
const Rect = types.Rect;
const RingList = types.RingList;
const Squad = types.Squad;
const Status = types.Status;
const StockpileArrayList = types.StockpileArrayList;
const Stockpile = types.Stockpile;
const Tile = types.Tile;
const WeaponList = types.WeaponList;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;

const SoundState = @import("sound.zig").SoundState;
const TaskArrayList = @import("tasks.zig").TaskArrayList;
const EvocableList = @import("items.zig").EvocableList;
// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const StackBuffer = @import("buffer.zig").StackBuffer;
const BStr = utils.BStr;

pub const GameState = union(enum) { Game, Win, Lose, Quit, Viewer };
pub const Layout = union(enum) { Unknown, Room: usize };

pub const HEIGHT = 100;
pub const WIDTH = 60;
pub const LEVELS = 23; //21;
pub const PLAYER_STARTING_LEVEL = 22; // TODO: define in data file

pub var gpa = std.heap.DebugAllocator(.{
    // Probably should enable this later on to track memory usage, if
    // allocations become too much
    .enable_memory_limit = false,

    .safety = true,
    .thread_safe = true,
    .never_unmap = false,
    .stack_trace_frames = 10,
}){};

pub var alloc = if (@import("builtin").mode == .Debug)
    gpa.allocator()
else
    std.heap.smp_allocator;

pub var sentry_disabled = false;
pub var log_disabled = false;

pub const mapgeometry = Coord.new2(LEVELS, WIDTH, HEIGHT);
pub fn mapRect(level: usize) Rect {
    return Rect{ .start = Coord.new2(level, 0, 0), .width = WIDTH, .height = HEIGHT };
}

pub const MemoryTile = struct {
    tile: display.Cell,
    type: Type = .Immediate,

    pub const Type = enum { Immediate, Echolocated, DetectUndead };
};
pub const MemoryTileMap = std.AutoHashMap(Coord, MemoryTile);

// Unused now
pub var default_patterns = [_]types.Ring{};

pub var benchmarker: utils.Benchmarker = undefined;

pub const __SER_BEGIN = {};

// Cached return value of player.isPlayerSpotted()
pub var player_is_spotted: struct {
    is_spotted: bool,
    turn_cached: usize,
} = .{ .is_spotted = false, .turn_cached = 0 };

// Data objects
pub var memory: MemoryTileMap = undefined;

pub var rooms: [LEVELS]mapgen.Room.ArrayList = undefined;
pub var stockpiles: [LEVELS]StockpileArrayList = undefined;
pub var inputs: [LEVELS]StockpileArrayList = undefined;
pub var outputs: [LEVELS]Rect.ArrayList = undefined;

pub var squads: Squad.List = undefined;
pub var tasks: TaskArrayList = undefined;
pub var mobs: MobList = undefined;
pub var armors: ArmorList = undefined;
pub var rings: RingList = undefined;
pub var machines: MachineList = undefined;
pub var fuses: Fuse.List = undefined;
pub var props: PropList = undefined;
pub var containers: ContainerList = undefined;
pub var evocables: EvocableList = undefined;
pub var messages: MessageArrayList = undefined;

pub var fab_records: mapgen.FabRecords = undefined;
pub var seed: u64 = undefined;
pub var floor_seeds: [LEVELS]u64 = undefined;

// Global variables
pub var ticks: usize = 0;
pub var player_turns: usize = 0;
pub var score: usize = 0;

// Global mechanic-specific variables
pub var defiled_temple: bool = false;
pub var destroyed_candles: usize = 0;
pub var shrines_in_lockdown: [LEVELS]bool = [1]bool{false} ** LEVELS;
pub var shrine_locations: [LEVELS]?Coord = [1]?Coord{null} ** LEVELS;
pub var alarm_locations: [LEVELS]StackBuffer(Coord, 4) = [1]StackBuffer(Coord, 4){StackBuffer(Coord, 4).init(null)} ** LEVELS;

pub var dungeon: *Dungeon = undefined;
pub var layout: [LEVELS][HEIGHT][WIDTH]Layout = [1][HEIGHT][WIDTH]Layout{[1][WIDTH]Layout{[1]Layout{.Unknown} ** WIDTH} ** HEIGHT} ** LEVELS;
pub var state: GameState = .Game;
pub var current_level: usize = PLAYER_STARTING_LEVEL;
pub var player: *Mob = undefined;
pub var player_inited = false;

pub var scoredata = std.enums.directEnumArray(scores.Stat, scores.StatValue, 0, undefined);
pub var threats: std.AutoHashMap(alert.Threat, alert.ThreatData) = undefined;
pub var responses: alert.ThreatResponse.AList = undefined;
pub var completed_events: [events.EVENTS.len]usize = [_]usize{0} ** events.EVENTS.len;

// zig fmt: off
pub var night_rep = [types.Faction.TOTAL]isize{
    // NEC    @   CG   REV   NC   HOLY   VERM
         0,   0,   0,  -10,  10,     9,     5
};
// zig fmt: on

pub var player_upgrades: [3]player_m.PlayerUpgradeInfo = undefined;
pub var player_conj_augments: [player_m.ConjAugment.TOTAL]player_m.ConjAugmentInfo = undefined;

pub const __SER_STOP = {};

// Numbers don't mean that much right now (unlike with night_rep). Only whether
// it's negative/zero/positive is significant.
//
// Row is indexed by mob checking hostility, column indexed by mob being checked.
//
// zig fmt: off
pub const REP_TABLE = [types.Faction.TOTAL][types.Faction.TOTAL]isize{
    // NEC     @    CG   REV    NC   HOLY   VERM
    .{  10,   -5,   -5,  -10,   -5,    -5,     5  },  // NEC
    .{ -10,   10,    5,  -10,    0,     0,     5  },  // @
    .{ -10,    5,   10,  -10,    1,     1,     5  },  // CG
    .{ -10,  -10,  -10,   10,  -10,   -10,     5  },  // REV
    .{   0,    0,    0,  -10,   10,     9,     5  },  // NC      // NOTE: use night_rep table
    .{  -1,    0,    5,  -10,    9,    10,     5  },  // HOLY
    .{  10,   10,   10,   10,   10,    10,    10  },  // VERM

    //
    // NOTE: player holy_rep really isn't used, what matters most is the rHoly
    // stat. This table just ensures that Necromancer-aligned mobs will be
    // hostile even if their rHoly isn't negative.
};
// zig fmt: on

// Assert that factions are allied with themselves
// TODO: add more checks
comptime {
    for (@typeInfo(types.Faction).@"enum".fields) |field_entry| {
        const field = field_entry.value;
        if (REP_TABLE[field][field] != 10) {
            @compileError("Faction check: a faction isn't fully allied with itself.");
        }
    }
}

// Data files
pub const MapgenInfos = struct {
    has_vault: bool = false,
};
pub var mapgen_infos = [1]MapgenInfos{.{}} ** LEVELS;
pub var descriptions: std.StringHashMap([]const u8) = undefined;
// XXX: []u8 instead of '[]const u8` because of tsv parsing limits
pub const LevelInfo = struct {
    id: []u8,
    depth: usize,
    shortname: []u8,
    name: []u8,
    upgr: bool,
    optional: bool,
    ecosystem: bool,
    stairs: [Dungeon.MAX_STAIRS]?[]u8,
};
pub var levelinfo: [LEVELS]LevelInfo = undefined; // data/levelinfo.tsv

pub const StatusStringInfo = struct {
    name: []const u8,
    unliving_name: ?[]const u8,
    mini_name: ?[]const u8,
};
pub var status_str_infos: std.enums.EnumArray(Status, ?StatusStringInfo) =
    std.enums.EnumArray(Status, ?StatusStringInfo).initFill(null);

// Find the nearest space near a coord in which a monster can be placed.
//
// Will *not* return crd.
//
// Uses state.alloc
//
pub fn nextSpotForMob(crd: Coord, mob: ?*Mob) ?Coord {
    var dijk: dijkstra.Dijkstra = undefined;
    dijk.init(crd, mapgeometry, 3, is_walkable, .{
        .mob = mob,
        .ignore_mobs = true,
        .right_now = true,
    }, gpa.allocator());
    defer dijk.deinit();

    return while (dijk.next()) |child| {
        if (!child.eq(crd) and !dungeon.at(child).prison and
            dungeon.at(child).mob == null)
        {
            break child;
        }
    } else null;
}

// Find the nearest space in which an item can be dropped.
//
// First attempt to find a tile without any items on it; if there are no such
// spaces within 3 spaces, grab the nearest place where an item can be dropped.
//
pub fn nextAvailableSpaceForItem(c: Coord, a: mem.Allocator) ?Coord {
    const S = struct {
        pub fn _helper(strict: bool, crd: Coord, myalloc: mem.Allocator) ?Coord {
            const S = struct {
                pub fn _isFull(strict_: bool, coord: Coord) bool {
                    if (dungeon.at(coord).surface) |_| {
                        if (strict_) return true;
                        // switch (surface) {
                        //     .Container => |container| return container.items.isFull(),
                        //     else => if (!strict_) return true,
                        // }
                    }

                    return if (strict_)
                        dungeon.itemsAt(coord).len > 0
                    else
                        dungeon.itemsAt(coord).isFull();
                }
            };

            if (is_walkable(crd, .{ .right_now = true }) and !S._isFull(strict, crd))
                return crd;

            var dijk: dijkstra.Dijkstra = undefined;
            dijk.init(crd, mapgeometry, 3, is_walkable, .{ .right_now = true }, myalloc);
            defer dijk.deinit();

            return while (dijk.next()) |child| {
                if (!S._isFull(strict, child))
                    break child;
            } else null;
        }
    };

    return S._helper(true, c, a) orelse S._helper(false, c, a);
}

pub const IsWalkableOptions = struct {
    // Return true only if the tile is walkable *right now*. Otherwise, tiles
    // that *could* be walkable in the future are merely assigned a penalty but
    // are treated as if they are walkable (e.g., tiles with mobs, or tiles with
    // machines that are walkable when powered but not walkable otherwise, like
    // doors).
    //
    right_now: bool = false,

    // Only treat a tile as unwalkable if it breaks line-of-fire.
    //
    // Water and lava tiles will not be considered unwalkable if this is true.
    only_if_breaks_lof: bool = false,

    // Consider a tile with a mob on it walkable.
    ignore_mobs: bool = false,

    mob: ?*const Mob = null,

    _no_multitile_recurse: bool = false,

    // This is a hack to confine astar within a rectangle, not relevant to
    // is_walkable.
    confines: Rect = Rect.new(Coord.new2(0, 0, 0), WIDTH, HEIGHT),
};

// STYLE: change to Tile.isWalkable
pub fn is_walkable(coord: Coord, opts: IsWalkableOptions) bool {
    const flying = opts.mob != null and opts.mob.?.hasStatus(.Fly);

    if (opts.mob != null and opts.mob.?.multitile != null and !opts._no_multitile_recurse) {
        var newopts = opts;
        newopts._no_multitile_recurse = true;
        const l = opts.mob.?.multitile.?;

        var gen = Rect.new(coord, l, l).iter();
        while (gen.next()) |mobcoord|
            if (!is_walkable(mobcoord, newopts))
                return false;

        return true;
    }

    switch (dungeon.at(coord).type) {
        .Wall => return false,
        .Water, .Lava => if (!opts.only_if_breaks_lof and !flying) return false,
        else => {},
    }

    // Mob is walkable if:
    // - It's hostile (it's walkable if it's dead!)
    // - It *is* the mob
    // - Mob can swap with it
    //
    if (!opts.ignore_mobs) {
        if (dungeon.at(coord).mob) |other| {
            if (opts.mob) |mob| {
                if (mob != other and !mob.canSwapWith(other, .{})) {
                    return false;
                }
            } else return false;
        }
    }

    if (dungeon.at(coord).surface) |surface| {
        switch (surface) {
            .Machine => |m| {
                if (opts.right_now) {
                    if (!m.isWalkable())
                        return false;
                } else {
                    if (!m.powered_walkable and !m.unpowered_walkable)
                        return false;

                    if (opts.mob) |mob|
                        if (!m.canBePoweredBy(mob) and
                            !m.isWalkable() and m.powered_walkable and !m.unpowered_walkable)
                            return false;
                }
            },
            .Prop => |p| if (!p.walkable) return false,
            .Poster => return false,
            .Stair => return false,
            .Container, .Corpse => {},
        }
    }

    return true;
}

// TODO: move this to utils.zig?
// TODO: actually no, move this to player.zig
pub fn createMobList(include_player: bool, only_if_infov: bool, level: usize, myalloc: mem.Allocator) MobArrayList {
    var moblist = std.ArrayList(*Mob).init(myalloc);
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new(x, y);

            if (!include_player and coord.eq(player.coord))
                continue;

            if (dungeon.at(Coord.new2(level, x, y)).mob) |mob| {
                if (only_if_infov and !player.cansee(coord))
                    continue;

                // Skip extra areas of multitile creatures to avoid duplicates
                if (mob.multitile != null and !mob.coord.eq(coord))
                    continue;

                moblist.append(mob) catch unreachable;
            }
        }
    }

    const S = struct {
        pub fn _sortFunc(_: void, a: *Mob, b: *Mob) bool {
            if (player.isHostileTo(a) and !player.isHostileTo(b)) return true;
            if (!player.isHostileTo(a) and player.isHostileTo(b)) return false;
            return player.coord.distance(a.coord) < player.coord.distance(b.coord);
        }
    };
    std.sort.insertion(*Mob, moblist.items, {}, S._sortFunc);

    return moblist;
}

pub fn tickLight(level: usize) void {
    var timer = benchmarker.timer("tickLight");
    defer timer.end();

    const light_buffer = &dungeon.light[level];

    // Clear out previous light levels.
    for (light_buffer) |*row| @memset(row, false);

    // Now for the actual party...

    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            const coord = Coord.new2(level, x, y);
            const light = dungeon.emittedLight(coord);

            // A memorial to my stupidity:
            //
            // When I first created the lighting system, I omitted the below
            // check (light > 0) and did raycasting *on every tile on the map*.
            // I chalked the resulting lag (2 seconds for every turn!) to
            // the lack of optimizations in the raycasting routine, and spent
            // hours trying to write and rewrite a better raycasting function.
            //
            // Thankfully, I only wasted about two days of tearing out my hair
            // before noticing the issue.
            //
            if (light > 0) {
                const r = light / Dungeon.FLOOR_OPACITY;
                fov.shadowCast(coord, r, mapgeometry, light_buffer, Dungeon.isTileOpaque, true);
            }
        }
    }

    // Anti-light

    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            const coord = Coord.new2(level, x, y);
            const antilight = dungeon.emittedAntiLight(coord);

            if (antilight > 0) {
                const r = antilight / Dungeon.FLOOR_OPACITY;
                fov.shadowCast(coord, r, mapgeometry, light_buffer, Dungeon.isTileOpaque, false);
            }
        }
    }
}

// Make sound "decay" each tick.
pub fn tickSound(cur_lev: usize) void {
    var timer = benchmarker.timer("tickSound");
    defer timer.end();

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(cur_lev, x, y);
            const cur_sound = dungeon.soundAt(coord);
            cur_sound.state = SoundState.ageToState(ticks - cur_sound.when);
        }
    }
}

pub fn loadStatusStringInfo() void {
    var rbuf: [65535]u8 = undefined;
    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("status_help.tsv", .{}) catch unreachable;

    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(struct { e: Status, n: []u8, un: ?[]u8, mn: ?[]u8 }, &[_]tsv.TSVSchemaItem{
        .{ .field_name = "e", .parse_to = Status, .parse_fn = tsv.parsePrimitive },
        .{ .field_name = "n", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
        .{ .field_name = "un", .parse_to = ?[]u8, .parse_fn = tsv.parseOptionalUtf8String, .optional = true },
        .{ .field_name = "mn", .parse_to = ?[]u8, .parse_fn = tsv.parseOptionalUtf8String, .optional = true },
    }, .{ .e = undefined, .n = undefined, .un = null, .mn = null }, rbuf[0..read], alloc);

    if (!result.is_ok()) {
        err.bug("Can't load data/status_help.tsv: {} (line {}, field {})", .{
            result.Err.type,
            result.Err.context.lineno,
            result.Err.context.field,
        });
    }

    const data = result.unwrap();
    defer data.deinit();

    for (data.items) |row| {
        const s = StatusStringInfo{ .name = row.n, .unliving_name = row.un, .mini_name = row.mn };
        status_str_infos.set(row.e, s);
    }

    var iter = status_str_infos.iterator();
    while (iter.next()) |info|
        if (info.value.* == null)
            err.bug("Can't load data/status_help.tsv: Missing entry for {}.", .{info.key});

    std.log.info("Loaded data/status_help.tsv.", .{});
}

pub fn freeStatusStringInfo() void {
    var iter = status_str_infos.iterator();
    while (iter.next()) |info| {
        alloc.free(info.value.*.?.name);
        if (info.value.*.?.unliving_name) |str|
            alloc.free(str);
        if (info.value.*.?.mini_name) |str|
            alloc.free(str);
    }
}

pub fn loadLevelInfo() void {
    var rbuf: [65535]u8 = undefined;
    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("levelinfo.tsv", .{}) catch unreachable;

    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(LevelInfo, &[_]tsv.TSVSchemaItem{
        .{ .field_name = "id", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
        .{ .field_name = "depth", .parse_to = usize, .parse_fn = tsv.parsePrimitive },
        .{ .field_name = "shortname", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
        .{ .field_name = "name", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
        .{ .field_name = "ecosystem", .parse_to = bool, .parse_fn = tsv.parsePrimitive },
        .{ .field_name = "upgr", .parse_to = bool, .parse_fn = tsv.parsePrimitive },
        .{ .field_name = "optional", .parse_to = bool, .parse_fn = tsv.parsePrimitive },
        .{ .field_name = "stairs", .parse_to = ?[]u8, .is_array = Dungeon.MAX_STAIRS, .parse_fn = tsv.parseOptionalUtf8String, .optional = true },
    }, .{
        .id = undefined,
        .depth = undefined,
        .shortname = undefined,
        .name = undefined,
        .ecosystem = undefined,
        .upgr = undefined,
        .optional = undefined,
        .stairs = [_]?[]u8{null} ** Dungeon.MAX_STAIRS,
    }, rbuf[0..read], alloc);

    if (!result.is_ok()) {
        err.bug("Can't load data/levelinfo.tsv: {} (line {}, field {})", .{
            result.Err.type,
            result.Err.context.lineno,
            result.Err.context.field,
        });
    }

    const data = result.unwrap();
    defer data.deinit();

    if (data.items.len != LEVELS) {
        err.bug("Can't load data/levelinfo.tsv: Incorrect number of entries.", .{});
    }

    for (data.items, 0..) |row, i|
        levelinfo[i] = row;

    std.log.info("Loaded data/levelinfo.tsv.", .{});
}

pub fn findLevelByName(name: []const u8) ?usize {
    return for (levelinfo, 0..) |item, i| {
        if (mem.eql(u8, item.name, name)) break i;
    } else null;
}

pub fn freeLevelInfo() void {
    for (levelinfo) |info| {
        alloc.free(info.id);
        alloc.free(info.shortname);
        alloc.free(info.name);
        for (&info.stairs) |maybe_stair|
            if (maybe_stair) |stair|
                alloc.free(stair);
    }
}

pub fn dialog(by: *const Mob, text: []const u8) void {
    ui.Animation.apply(.{ .PopChar = .{ .coord = by.coord, .char = '!' } });
    message(.Dialog, "{f}: \"{s}\"", .{ by.fmt().caps(), text });
    ui.drawTextModalAtMob(by, "{s}", .{text}) catch
        err.ensure(false, "Couldn't find a space to draw the dialog. Dialog len: {}; mob coord: {}", .{ text.len, by.coord }) catch {};
}

pub fn messageAboutMob2(mob: *const Mob, ref_coord: ?Coord, mtype: MessageType, comptime fmt: []const u8, args: anytype) void {
    messageAboutMob(mob, ref_coord, mtype, fmt, args, fmt, args);
}

pub fn messageAboutMob(
    mob: *const Mob,
    ref_coord: ?Coord,
    mtype: MessageType,
    comptime mob_is_me_fmt: []const u8,
    mob_is_me_args: anytype,
    comptime mob_is_else_fmt: []const u8,
    mob_is_else_args: anytype,
) void {
    if (mob == player) {
        message(mtype, "You " ++ mob_is_me_fmt, mob_is_me_args);
    } else if (player.cansee(mob.coord)) {
        message(mtype, "The {s} " ++ mob_is_else_fmt, .{mob.displayName()} ++ mob_is_else_args);
    } else if (ref_coord != null and player.cansee(ref_coord.?)) {
        message(mtype, "Something " ++ mob_is_else_fmt, mob_is_else_args);
    }
}

pub fn message(mtype: MessageType, comptime fmt: []const u8, args: anytype) void {
    var msg = Message{ .msg = .empty, .type = mtype, .turn = player_turns };
    std.fmt.format(msg.msg.writer(alloc), fmt, args) catch err.oom();

    // If the message isn't a prompt, check if the message is a duplicate
    if (mtype != .Prompt and messages.items.len > 0 and mem.eql(
        u8,
        messages.items[messages.items.len - 1].msg.bytes(),
        msg.msg.bytes(),
    )) {
        messages.items[messages.items.len - 1].dups += 1;
        msg.msg.deinit(alloc);
    } else {
        messages.append(msg) catch err.oom();
    }
}

pub fn markMessageNoisy() void {
    assert(messages.items.len > 0);
    messages.items[messages.items.len - 1].noise = true;
}

pub fn deinitMessages() void {
    for (messages.items) |msg|
        msg.msg.deinit(alloc);
    messages.deinit();
}
