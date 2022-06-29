const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const enums = std.enums;

const ai = @import("ai.zig");
const astar = @import("astar.zig");
const err = @import("err.zig");
const player_m = @import("player.zig");
const display = @import("display.zig");
const dijkstra = @import("dijkstra.zig");
const mapgen = @import("mapgen.zig");
const fire = @import("fire.zig");
const items = @import("items.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const rng = @import("rng.zig");
const literature = @import("literature.zig");
const fov = @import("fov.zig");
const types = @import("types.zig");

const Rune = items.Rune;
const Squad = types.Squad;
const Mob = types.Mob;
const MessageType = types.MessageType;
const Item = types.Item;
const Coord = types.Coord;
const Dungeon = types.Dungeon;
const Tile = types.Tile;
const Status = types.Status;
const Stockpile = types.Stockpile;
const StockpileArrayList = types.StockpileArrayList;
const Rect = types.Rect;
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
const Direction = types.Direction;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;

const SoundState = @import("sound.zig").SoundState;
const TaskArrayList = @import("tasks.zig").TaskArrayList;
const EvocableList = @import("items.zig").EvocableList;
const PosterArrayList = literature.PosterArrayList;

pub const GameState = union(enum) { Game, Win, Lose, Quit };
pub const Layout = union(enum) { Unknown, Room: usize };

pub const HEIGHT = 35;
pub const WIDTH = 70;
pub const LEVELS = 14;
pub const PLAYER_STARTING_LEVEL = 13; // TODO: define in data file

// Should only be used directly by functions in main.zig. For other applications,
// should be passed as a parameter by caller.
pub var GPA = std.heap.GeneralPurposeAllocator(.{
    // Probably should enable this later on to track memory usage, if
    // allocations become too much
    .enable_memory_limit = false,

    .safety = true,

    // Probably would enable this later?
    .thread_safe = false,

    .never_unmap = true,

    .stack_trace_frames = 6,
}){};

pub const mapgeometry = Coord.new2(LEVELS, WIDTH, HEIGHT);
pub var dungeon: Dungeon = .{};
pub var layout: [LEVELS][HEIGHT][WIDTH]Layout = undefined;
pub var player: *Mob = undefined;
pub var state: GameState = .Game;

// zig fmt: off
// field upgr: whether to grant an upgrade on this floor.
pub const levelinfo = [LEVELS]struct {
    id: []const u8, upgr: bool, optional: bool, name: []const u8
}{
    .{ .id = "PRI", .upgr = false, .optional = false, .name = "-1/Prison"       },
    .{ .id = "PRI", .upgr = false, .optional = false, .name = "-2/Prison"       },
    .{ .id = "QRT", .upgr = false, .optional = true,  .name = "-3/Quarters/3"   },
    .{ .id = "QRT", .upgr = false, .optional = true,  .name = "-3/Quarters/2"   },
    .{ .id = "QRT", .upgr = true,  .optional = false, .name = "-3/Quarters"     },
    .{ .id = "PRI", .upgr = false, .optional = false, .name = "-4/Prison"       },
    .{ .id = "CAV", .upgr = false, .optional = true,  .name = "-5/Caverns/3"    },
    .{ .id = "CAV", .upgr = false, .optional = true,  .name = "-5/Caverns/2"    },
    .{ .id = "CAV", .upgr = true,  .optional = false, .name = "-5/Caverns"      },
    .{ .id = "LAB", .upgr = false, .optional = true,  .name = "-6/Laboratory/3" },
    .{ .id = "LAB", .upgr = false, .optional = true,  .name = "-6/Laboratory/2" },
    .{ .id = "LAB", .upgr = true,  .optional = false, .name = "-6/Laboratory"   },
    .{ .id = "PRI", .upgr = false, .optional = false, .name = "-7/Prison"       },
    .{ .id = "PRI", .upgr = false, .optional = false, .name = "-8/Prison"       },
};

pub const RUNE_PLACEMENT = [Rune.COUNT]struct {
    floorstr: []const u8, rune: Rune
}{
    .{ .floorstr = "-3/Quarters/3",   .rune = .Golden  },
    .{ .floorstr = "-5/Caverns/3",    .rune = .Basalt  },
    .{ .floorstr = "-6/Laboratory/3", .rune = .Twisted },
};
// zig fmt: on

// Information collected over a run to present in a morgue file.
pub var chardata: struct {
    foes_killed_total: usize = 0,
    foes_stabbed: usize = 0,
    foes_killed: std.StringHashMap(usize) = undefined,
    time_with_statuses: enums.EnumArray(Status, usize) = enums.EnumArray(Status, usize).initFill(0),
    time_on_levels: [LEVELS]usize = [1]usize{0} ** LEVELS,
    items_used: std.StringHashMap(usize) = undefined,
    evocs_used: std.StringHashMap(usize) = undefined,

    pub fn init(self: *@This(), alloc: mem.Allocator) void {
        self.foes_killed = std.StringHashMap(usize).init(alloc);
        self.items_used = std.StringHashMap(usize).init(alloc);
        self.evocs_used = std.StringHashMap(usize).init(alloc);
    }

    pub fn deinit(self: *@This()) void {
        self.foes_killed.clearAndFree();
        self.items_used.clearAndFree();
        self.evocs_used.clearAndFree();
    }
} = .{};

pub var collected_runes = enums.EnumArray(Rune, bool).initFill(false);

pub var player_upgrades: [3]player_m.PlayerUpgradeInfo = undefined;

pub var default_patterns = [_]types.Ring{
    items.DefaultPinRing,
};

pub const MemoryTile = struct {
    fg: u32 = 0x000000,
    bg: u32 = 0x000000,
    ch: u32 = ' ',
    type: Type = .Immediate,

    pub const Type = enum { Immediate, Echolocated, DetectUndead };
};
pub const MemoryTileMap = std.AutoHashMap(Coord, MemoryTile);

pub var memory: MemoryTileMap = undefined;

pub var descriptions: std.StringHashMap([]const u8) = undefined;

pub var rooms: [LEVELS]mapgen.Room.ArrayList = undefined;
pub var stockpiles: [LEVELS]StockpileArrayList = undefined;
pub var inputs: [LEVELS]StockpileArrayList = undefined;
pub var outputs: [LEVELS]Rect.ArrayList = undefined;

// Data objects
pub var tasks: TaskArrayList = undefined;
pub var squads: Squad.List = undefined;
pub var mobs: MobList = undefined;
pub var rings: RingList = undefined;
pub var armors: ArmorList = undefined;
pub var weapons: WeaponList = undefined;
pub var machines: MachineList = undefined;
pub var props: PropList = undefined;
pub var containers: ContainerList = undefined;
pub var evocables: EvocableList = undefined;

pub var ticks: usize = 0;
pub var messages: MessageArrayList = undefined;
pub var score: usize = 0;

// Find the nearest space in which an item can be dropped.
//
// First attempt to find a tile without any items on it; if there are no such
// spaces within two spaces, grab the nearest place where an item can be
// dropped.
//
// Note, non-full containers are considered a "valid" space for dropping an
// item here.
//
pub fn nextAvailableSpaceForItem(c: Coord, a: mem.Allocator) ?Coord {
    const S = struct {
        pub fn _helper(strict: bool, crd: Coord, alloc: mem.Allocator) ?Coord {
            const S = struct {
                pub fn _isFull(strict_: bool, coord: Coord) bool {
                    if (dungeon.at(coord).surface) |surface| {
                        switch (surface) {
                            .Container => |container| return container.items.isFull(),
                            else => if (strict_) return true,
                        }
                    }

                    return if (strict_)
                        dungeon.itemsAt(coord).len > 0
                    else
                        dungeon.itemsAt(coord).isFull();
                }
            };

            if (is_walkable(crd, .{ .right_now = true }) and !S._isFull(strict, crd))
                return crd;

            var dijk = dijkstra.Dijkstra.init(crd, mapgeometry, 2, is_walkable, .{ .right_now = true }, alloc);
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
};

// STYLE: change to Tile.isWalkable
pub fn is_walkable(coord: Coord, opts: IsWalkableOptions) bool {
    const tile_broken = dungeon.at(coord).broken;

    if (!tile_broken) {
        switch (dungeon.at(coord).type) {
            .Wall => return false,
            .Water, .Lava => if (!opts.only_if_breaks_lof) return false,
            else => {},
        }
    }

    if (!opts.ignore_mobs) {
        if (dungeon.at(coord).mob) |other| {
            if (opts.mob) |mob| {
                if (mob != other and !mob.canSwapWith(other, null)) return false;
            } else return false;
        }
    }

    if (!tile_broken) {
        if (dungeon.at(coord).surface) |surface| {
            switch (surface) {
                .Corpse => |_| return true,
                .Container => |_| return true,
                .Machine => |m| {
                    if (opts.right_now) {
                        if (!m.isWalkable())
                            return false;
                    } else {
                        if (!m.powered_walkable and !m.unpowered_walkable)
                            return false;

                        // oh boy
                        if (opts.mob) |mob|
                            if (m.restricted_to) |restriction|
                                if (!m.isWalkable() and m.powered_walkable and !m.unpowered_walkable)
                                    if (restriction != mob.allegiance)
                                        return false;
                    }
                },
                .Prop => |p| if (!p.walkable) return false,
                .Poster => return true,
                .Stair => return false,
            }
        }
    }

    return true;
}

// TODO: move this to utils.zig?
pub fn createMobList(include_player: bool, only_if_infov: bool, level: usize, alloc: mem.Allocator) MobArrayList {
    var moblist = std.ArrayList(*Mob).init(alloc);
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
    std.sort.insertionSort(*Mob, moblist.items, {}, S._sortFunc);

    return moblist;
}

pub fn tickLight(level: usize) void {
    const light_buffer = &dungeon.light[level];

    // Clear out previous light levels.
    for (light_buffer) |*row| for (row) |*cell| {
        cell.* = false;
    };

    // Now for the actual party...

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
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
                //fov.rayCast(coord, 20, light, Dungeon.tileOpacity, light_buffer, null);
                const r = light / Dungeon.FLOOR_OPACITY;
                fov.shadowCast(coord, r, mapgeometry, light_buffer, Dungeon.isTileOpaque);
            }
        }
    }
}

// Make sound "decay" each tick.
pub fn tickSound(cur_lev: usize) void {
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
    var buf: [128]u8 = undefined;
    for (buf) |*i| i.* = 0;
    var fbs = std.io.fixedBufferStream(&buf);

    if (mob == player) {
        std.fmt.format(fbs.writer(), mob_is_me_fmt, mob_is_me_args) catch err.wat();
        message(mtype, "You {s}", .{fbs.getWritten()});
    } else if (player.cansee(mob.coord)) {
        std.fmt.format(fbs.writer(), mob_is_else_fmt, mob_is_else_args) catch err.wat();
        message(mtype, "The {s} {s}", .{ mob.displayName(), fbs.getWritten() });
    } else if (ref_coord != null and player.cansee(ref_coord.?)) {
        std.fmt.format(fbs.writer(), mob_is_else_fmt, mob_is_else_args) catch err.wat();
        message(mtype, "Something {s}", .{fbs.getWritten()});
    }
}

pub fn message(mtype: MessageType, comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    for (buf) |*i| i.* = 0;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch err.bug("format error", .{});

    var msg: Message = .{
        .msg = undefined,
        .type = mtype,
        .turn = ticks,
    };
    utils.copyZ(&msg.msg, fbs.getWritten());

    // If the message isn't a prompt, check if the message is a duplicate
    if (mtype != .Prompt and messages.items.len > 0 and mem.eql(
        u8,
        utils.used(messages.items[messages.items.len - 1].msg),
        utils.used(msg.msg),
    )) {
        messages.items[messages.items.len - 1].dups += 1;
    } else {
        messages.append(msg) catch err.oom();
    }
}

pub fn markMessageNoisy() void {
    assert(messages.items.len > 0);
    messages.items[messages.items.len - 1].noise = true;
}

pub fn formatMorgue(alloc: mem.Allocator) !std.ArrayList(u8) {
    const S = struct {
        fn _damageString() []const u8 {
            const ldp = player.lastDamagePercentage();
            var str: []const u8 = "killed";
            if (ldp > 20) str = "demolished";
            if (ldp > 40) str = "exterminated";
            if (ldp > 60) str = "utterly destroyed";
            if (ldp > 80) str = "miserably destroyed";
            return str;
        }
    };

    var buf = std.ArrayList(u8).init(alloc);
    var w = buf.writer();

    try w.print("Oathbreaker morgue entry\n", .{});
    try w.print("\n", .{});
    try w.print("Seed: {}\n", .{rng.seed});
    try w.print("\n", .{});

    const username = std.os.getenv("USER").?; // FIXME: should have backup option if null
    const gamestate = switch (state) {
        .Win => "escaped",
        .Lose => "died",
        else => "quit",
    };
    try w.print("{s} {s} after {} turns\n", .{ username, gamestate, ticks });
    if (state == .Lose) {
        if (player.killed_by) |by| {
            try w.print("        ...{s} by a {s} ({}% dmg)\n", .{
                S._damageString(),
                by.displayName(),
                player.lastDamagePercentage(),
            });
        }
        try w.print("        ...on level {s} of the Dungeon\n", .{levelinfo[player.coord.z].name});
    }
    try w.print("\n", .{});
    inline for (@typeInfo(Mob.Inventory.EquSlot).Enum.fields) |slots_f| {
        const slot = @intToEnum(Mob.Inventory.EquSlot, slots_f.value);
        try w.print("{s: <7} {s}\n", .{
            slot.name(),
            if (player.inventory.equipment(slot).*) |i|
                (i.longName() catch unreachable).constSlice()
            else
                "<none>",
        });
    }
    try w.print("\n", .{});

    try w.print("Aptitudes:\n", .{});
    for (player_upgrades) |upgr| if (upgr.recieved) {
        try w.print("- {s}\n", .{upgr.upgrade.description()});
    };
    try w.print("\n", .{});

    try w.print("Runes:\n", .{});
    {
        var runes_iter = collected_runes.iterator();
        while (runes_iter.next()) |rune| if (rune.value.*) {
            try w.print("· {s} Rune\n", .{rune.key.name()});
        };
    }
    try w.print("\n", .{});

    try w.print("Inventory:\n", .{});
    for (player.inventory.pack.constSlice()) |item| {
        const itemname = (item.longName() catch unreachable).constSlice();
        try w.print("- {s}\n", .{itemname});
    }
    try w.print("\n", .{});

    try w.print("Statuses:\n", .{});
    {
        inline for (@typeInfo(Status).Enum.fields) |status| {
            const status_e = @field(Status, status.name);
            if (player.isUnderStatus(status_e)) |_| {
                try w.print("- {s}\n", .{status_e.string(player)});
            }
        }
    }
    try w.print("\n", .{});

    try w.print("You killed {} foe{s}, stabbing {} of them.\n", .{
        chardata.foes_killed_total,
        if (chardata.foes_killed_total > 0) @as([]const u8, "s") else "",
        chardata.foes_stabbed,
    });
    try w.print("\n", .{});

    try w.print("Last messages:\n", .{});
    if (messages.items.len > 0) {
        const msgcount = messages.items.len - 1;
        var i: usize = msgcount - math.min(msgcount, 45);
        while (i <= msgcount) : (i += 1) {
            const msg = messages.items[i];
            const msgtext = utils.used(msg.msg);

            if (msg.dups == 0) {
                try w.print("- {s}\n", .{msgtext});
            } else {
                try w.print("- {s} (×{})\n", .{ msgtext, msg.dups + 1 });
            }
        }
    }
    try w.print("\n", .{});

    try w.print("Surroundings:\n", .{});
    {
        const radius: usize = 14;
        var y: usize = player.coord.y -| radius;
        while (y < math.min(player.coord.y + radius, HEIGHT)) : (y += 1) {
            try w.print("        ", .{});
            var x: usize = player.coord.x -| radius;
            while (x < math.min(player.coord.x + radius, WIDTH)) : (x += 1) {
                const coord = Coord.new2(player.coord.z, x, y);

                if (dungeon.neighboringWalls(coord, true) == 9) {
                    try w.print(" ", .{});
                    continue;
                }

                if (player.coord.eq(coord)) {
                    try w.print("@", .{});
                    continue;
                }

                var ch = @intCast(u21, Tile.displayAs(coord, false, false).ch);
                if (ch == ' ') ch = '.';

                try w.print("{u}", .{ch});
            }
            try w.print("\n", .{});
        }
    }
    try w.print("\n", .{});

    try w.print("You could see:\n", .{});
    {
        const can_see = createMobList(false, true, player.coord.z, alloc);
        defer can_see.deinit();
        var can_see_counted = std.StringHashMap(usize).init(alloc);
        defer can_see_counted.deinit();
        for (can_see.items) |mob| {
            const prevtotal = (can_see_counted.getOrPutValue(mob.displayName(), 0) catch unreachable).value_ptr.*;
            can_see_counted.put(mob.displayName(), prevtotal + 1) catch unreachable;
        }

        var iter = can_see_counted.iterator();
        while (iter.next()) |mobcount| {
            try w.print("- {: >2} {s}\n", .{ mobcount.value_ptr.*, mobcount.key_ptr.* });
        }
    }
    try w.print("\n", .{});

    try w.print("Vanquished foes:\n", .{});
    {
        var iter = chardata.foes_killed.iterator();
        while (iter.next()) |mobcount| {
            try w.print("- {: >2} {s}\n", .{ mobcount.value_ptr.*, mobcount.key_ptr.* });
        }
    }
    try w.print("\n", .{});
    try w.print("Time spent with statuses:\n", .{});
    inline for (@typeInfo(Status).Enum.fields) |status| {
        const status_e = @field(Status, status.name);
        const turns = chardata.time_with_statuses.get(status_e);
        if (turns > 0) {
            try w.print("- {s: <20} {: >5} turns\n", .{ status_e.string(player), turns });
        }
    }
    try w.print("\n", .{});
    try w.print("Items used:\n", .{});
    {
        var iter = chardata.items_used.iterator();
        while (iter.next()) |item| {
            try w.print("- {: <20} {s: >5}\n", .{ item.value_ptr.*, item.key_ptr.* });
        }
    }
    {
        var iter = chardata.evocs_used.iterator();
        while (iter.next()) |item| {
            try w.print("- {: <20} {s: >5}\n", .{ item.value_ptr.*, item.key_ptr.* });
        }
    }
    try w.print("\n", .{});
    try w.print("Time spent on levels:\n", .{});
    for (chardata.time_on_levels[0..]) |turns, level| {
        try w.print("- {s: <20} {: >5}\n", .{ levelinfo[level].name, turns });
    }

    return buf;
}
