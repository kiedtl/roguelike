const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const err = @import("err.zig");
const state = @import("state.zig");
const rng = @import("rng.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const StackBuffer = @import("buffer.zig").StackBuffer;

const Mob = types.Mob;
const Coord = types.Coord;
const Status = types.Status;
const Tile = types.Tile;
const WIDTH = state.WIDTH;
const HEIGHT = state.HEIGHT;
const LEVELS = state.LEVELS;

pub const Chunk = union(enum) {
    Header: struct { n: []const u8 },
    Stat: struct { s: Stat, n: []const u8, ign0: bool = true },
};

pub const CHUNKS = [_]Chunk{
    .{ .Header = .{ .n = "General stats" } },
    .{ .Stat = .{ .s = .TurnsSpent, .n = "turns spent" } },
    .{ .Stat = .{ .s = .KillRecord, .n = "vanquished foes" } },
    .{ .Stat = .{ .s = .StabRecord, .n = "stabbed foes" } },
};

pub const Stat = enum(usize) {
    TurnsSpent = 0,
    KillRecord = 1,
    StabRecord = 2,

    pub fn stattype(self: Stat) std.meta.FieldEnum(StatValue) {
        return switch (self) {
            .TurnsSpent => .SingleUsize,
            .KillRecord => .BatchUsize,
            .StabRecord => .BatchUsize,
        };
    }
};

pub const StatValue = struct {
    SingleUsize: SingleUsize = .{},
    BatchUsize: struct {
        total: usize = 0,
        singles: StackBuffer(BatchEntry, 256) = StackBuffer(BatchEntry, 256).init(null),
    },

    pub const BatchEntry = struct {
        id: []const u8 = "",
        val: SingleUsize = .{},
    };

    pub const SingleUsize = struct {
        total: usize = 0,
        each: [LEVELS]usize = [1]usize{0} ** LEVELS,
    };
};

pub var data = std.enums.directEnumArray(Stat, StatValue, 0, undefined);

pub fn init() void {
    for (data) |*entry, i|
        if (std.meta.intToEnum(Stat, i)) |_| {
            entry.* = .{};
        } else |_| {};
}

// XXX: this hidden reliance on state.player.z could cause bugs
// e.g. when recording stats of a level the player just left
pub fn recordUsize(stat: Stat, value: usize) void {
    switch (stat.stattype()) {
        .SingleUsize => {
            data[@enumToInt(stat)].SingleUsize.total += value;
            data[@enumToInt(stat)].SingleUsize.each[state.player.coord.z] += value;
        },
        else => unreachable,
    }
}

// XXX: this hidden reliance on state.player.z could cause bugs
// e.g. when recording stats of a level the player just left
pub fn recordTaggedUsize(stat: Stat, key: []const u8, value: usize) void {
    switch (stat.stattype()) {
        .BatchUsize => {
            data[@enumToInt(stat)].BatchUsize.total += value;
            const index: ?usize = for (data[@enumToInt(stat)].BatchUsize.singles.constSlice()) |single, i| {
                if (mem.eql(u8, single.id, key)) break i;
            } else null;
            if (index) |i| {
                data[@enumToInt(stat)].BatchUsize.singles.slice()[i].val.total += value;
                data[@enumToInt(stat)].BatchUsize.singles.slice()[i].val.each[state.player.coord.z] += value;
            } else {
                data[@enumToInt(stat)].BatchUsize.singles.append(.{}) catch err.wat();
                data[@enumToInt(stat)].BatchUsize.singles.lastPtr().?.id = key;
                data[@enumToInt(stat)].BatchUsize.singles.lastPtr().?.val.total += value;
                data[@enumToInt(stat)].BatchUsize.singles.lastPtr().?.val.each[state.player.coord.z] += value;
            }
        },
        else => unreachable,
    }
}

fn _isLevelSignificant(level: usize) bool {
    return data[@enumToInt(@as(Stat, .TurnsSpent))].SingleUsize.each[level] > 0;
}

fn formatMorgue(alloc: mem.Allocator) !std.ArrayList(u8) {
    const S = struct {
        fn _damageString() []const u8 {
            const ldp = state.player.lastDamagePercentage();
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

    var username: []const u8 = undefined;
    // FIXME: should be a cleaner way to do this...
    if (std.process.getEnvVarOwned(alloc, "USER")) |s| {
        username = s;
    } else |_| {
        if (std.process.getEnvVarOwned(alloc, "USERNAME")) |s| {
            username = s;
        } else |_| {
            username = alloc.dupe(u8, "Obmirnul") catch unreachable;
        }
    }
    defer alloc.free(username);

    const gamestate = switch (state.state) {
        .Win => "escaped",
        .Lose => "died",
        else => "quit",
    };
    try w.print("{s} {s} after {} turns\n", .{ username, gamestate, state.ticks });
    if (state.state == .Lose) {
        if (state.player.killed_by) |by| {
            try w.print("        ...{s} by a {s} ({}% dmg)\n", .{
                S._damageString(),
                by.displayName(),
                state.player.lastDamagePercentage(),
            });
        }
        try w.print("        ...on level {s} of the Dungeon\n", .{state.levelinfo[state.player.coord.z].name});
    }
    try w.print("\n", .{});
    inline for (@typeInfo(Mob.Inventory.EquSlot).Enum.fields) |slots_f| {
        const slot = @intToEnum(Mob.Inventory.EquSlot, slots_f.value);
        try w.print("{s: <7} {s}\n", .{
            slot.name(),
            if (state.player.inventory.equipment(slot).*) |i|
                (i.longName() catch unreachable).constSlice()
            else
                "<none>",
        });
    }
    try w.print("\n", .{});

    try w.print("Aptitudes:\n", .{});
    for (state.player_upgrades) |upgr| if (upgr.recieved) {
        try w.print("- {s}\n", .{upgr.upgrade.description()});
    };
    try w.print("\n", .{});

    try w.print("Inventory:\n", .{});
    for (state.player.inventory.pack.constSlice()) |item| {
        const itemname = (item.longName() catch unreachable).constSlice();
        try w.print("- {s}\n", .{itemname});
    }
    try w.print("\n", .{});

    try w.print("Statuses:\n", .{});
    {
        inline for (@typeInfo(Status).Enum.fields) |status| {
            const status_e = @field(Status, status.name);
            if (state.player.isUnderStatus(status_e)) |_| {
                try w.print("- {s}\n", .{status_e.string(state.player)});
            }
        }
    }
    try w.print("\n", .{});

    try w.print("You killed {} foe{s}, stabbing {} of them.\n", .{
        state.chardata.foes_killed_total,
        if (state.chardata.foes_killed_total > 0) @as([]const u8, "s") else "",
        state.chardata.foes_stabbed,
    });
    try w.print("\n", .{});

    try w.print("Last messages:\n", .{});
    if (state.messages.items.len > 0) {
        const msgcount = state.messages.items.len - 1;
        var i: usize = msgcount - math.min(msgcount, 45);
        while (i <= msgcount) : (i += 1) {
            const msg = state.messages.items[i];
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
        var y: usize = state.player.coord.y -| radius;
        while (y < math.min(state.player.coord.y + radius, HEIGHT)) : (y += 1) {
            try w.print("        ", .{});
            var x: usize = state.player.coord.x -| radius;
            while (x < math.min(state.player.coord.x + radius, WIDTH)) : (x += 1) {
                const coord = Coord.new2(state.player.coord.z, x, y);

                if (state.dungeon.neighboringWalls(coord, true) == 9) {
                    try w.print(" ", .{});
                    continue;
                }

                if (state.player.coord.eq(coord)) {
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
        // Memory buffer to hold mob displayName()'s, because StringHashMap
        // doesn't clone the strings...
        //
        // (We're using this so we don't have to try to deallocate stuff.)
        var membuf: [65535]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

        var can_see_counted = std.StringHashMap(usize).init(alloc);
        defer can_see_counted.deinit();

        const can_see = state.createMobList(false, true, state.player.coord.z, alloc);
        defer can_see.deinit();
        for (can_see.items) |mob| {
            const name = try utils.cloneStr(mob.displayName(), fba.allocator());
            const prevtotal = (can_see_counted.getOrPutValue(name, 0) catch err.wat()).value_ptr.*;
            can_see_counted.put(name, prevtotal + 1) catch unreachable;
        }

        var iter = can_see_counted.iterator();
        while (iter.next()) |mobcount| {
            try w.print("- {: >2} {s}\n", .{ mobcount.value_ptr.*, mobcount.key_ptr.* });
        }
    }
    try w.print("\n", .{});

    try w.print("\n", .{});
    try w.print("Time spent with statuses:\n", .{});
    inline for (@typeInfo(Status).Enum.fields) |status| {
        const status_e = @field(Status, status.name);
        const turns = state.chardata.time_with_statuses.get(status_e);
        if (turns > 0) {
            try w.print("- {s: <20} {: >5} turns\n", .{ status_e.string(state.player), turns });
        }
    }
    try w.print("\n", .{});
    try w.print("Items used:\n", .{});
    {
        var iter = state.chardata.items_used.iterator();
        while (iter.next()) |item| {
            try w.print("- {: <20} {s: >5}\n", .{ item.value_ptr.*, item.key_ptr.* });
        }
    }
    {
        var iter = state.chardata.evocs_used.iterator();
        while (iter.next()) |item| {
            try w.print("- {: <20} {s: >5}\n", .{ item.value_ptr.*, item.key_ptr.* });
        }
    }

    // Newlines will be auto-added by header, see below
    // try w.print("\n\n", .{});

    for (&CHUNKS) |chunk| {
        switch (chunk) {
            .Header => |header| {
                try w.print("\n\n", .{});
                try w.print(" {s: <26}", .{header.n});
                try w.print("| ", .{});
                {
                    var c: usize = state.levelinfo.len - 1;
                    while (c > 0) : (c -= 1) if (_isLevelSignificant(c)) {
                        try w.print("{: <4} ", .{state.levelinfo[c].depth});
                    };
                }
                try w.print("\n-", .{});
                for (header.n) |_|
                    try w.print("-", .{});
                try w.print("-", .{});
                var si: usize = 26 - (header.n.len + 2) + 1;
                while (si > 0) : (si -= 1)
                    try w.print(" ", .{});
                try w.print("| ", .{});
                {
                    var c: usize = state.levelinfo.len - 1;
                    while (c > 0) : (c -= 1) if (_isLevelSignificant(c)) {
                        try w.print("{s: <4} ", .{state.levelinfo[c].shortname});
                    };
                }
                try w.print("\n", .{});
            },
            .Stat => |stat| {
                const entry = &data[@enumToInt(stat.s)];
                switch (stat.s.stattype()) {
                    .SingleUsize => {
                        try w.print("{s: <20} {: >5} | ", .{ stat.n, entry.SingleUsize.total });
                        {
                            var c: usize = state.levelinfo.len - 1;
                            while (c > 0) : (c -= 1) if (_isLevelSignificant(c)) {
                                if (stat.ign0 and entry.SingleUsize.each[c] == 0) {
                                    try w.print("-    ", .{});
                                } else {
                                    try w.print("{: <4} ", .{entry.SingleUsize.each[c]});
                                }
                            };
                        }
                        try w.print("\n", .{});
                    },
                    .BatchUsize => {
                        try w.print("{s: <20} {: >5} |\n", .{ stat.n, entry.BatchUsize.total });
                        for (entry.BatchUsize.singles.slice()) |batch_entry| {
                            try w.print("  {s: <18} {: >5} | ", .{ batch_entry.id, batch_entry.val.total });
                            var c: usize = state.levelinfo.len - 1;
                            while (c > 0) : (c -= 1) if (_isLevelSignificant(c)) {
                                if (stat.ign0 and batch_entry.val.each[c] == 0) {
                                    try w.print("-    ", .{});
                                } else {
                                    try w.print("{: <4} ", .{batch_entry.val.each[c]});
                                }
                            };
                            try w.print("\n", .{});
                        }
                    },
                }
            },
        }
    }

    try w.print("\n", .{});

    return buf;
}

pub fn exportMorgueTXT() void {
    const morgue = formatMorgue(state.GPA.allocator()) catch err.wat();
    defer morgue.deinit();

    var username: []const u8 = undefined;
    // FIXME: should be a cleaner way to do this...
    if (std.process.getEnvVarOwned(state.GPA.allocator(), "USER")) |s| {
        username = s;
    } else |_| {
        if (std.process.getEnvVarOwned(state.GPA.allocator(), "USERNAME")) |s| {
            username = s;
        } else |_| {
            username = state.GPA.allocator().dupe(u8, "Obmirnul") catch unreachable;
        }
    }
    defer state.GPA.allocator().free(username);

    const ep_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(u64, std.time.timestamp()) };
    const ep_day = ep_secs.getEpochDay();
    const year_day = ep_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();

    const filename = std.fmt.allocPrintZ(state.GPA.allocator(), "morgue-{s}-{}-{}-{:0>2}-{:0>2}.txt", .{ username, rng.seed, year_day.year, month_day.month.numeric(), month_day.day_index }) catch err.oom();
    defer state.GPA.allocator().free(filename);

    std.os.mkdir("morgue", 0o776) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("Could not create morgue directory: {}", .{e});
            std.log.err("Refusing to write morgue entries.", .{});
            return;
        },
    };

    (std.fs.cwd().openDir("morgue", .{}) catch err.wat()).writeFile(filename, morgue.items[0..]) catch |e| {
        std.log.err("Could not write to morgue file '{s}': {}", .{ filename, e });
        std.log.err("Refusing to write morgue entries.", .{});
        return;
    };
    std.log.info("Morgue file written to {s}.", .{filename});
}
