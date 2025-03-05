const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const sort = std.sort;

const err = @import("err.zig");
const state = @import("state.zig");
const rng = @import("rng.zig");
const types = @import("types.zig");
const player = @import("player.zig");
const surfaces = @import("surfaces.zig");
const utils = @import("utils.zig");

const StackBuffer = @import("buffer.zig").StackBuffer;
const BStr = utils.BStr;

const Mob = types.Mob;
const Coord = types.Coord;
const Status = types.Status;
const Tile = types.Tile;
const WIDTH = state.WIDTH;
const HEIGHT = state.HEIGHT;
const LEVELS = state.LEVELS;

pub const Info = struct {
    seed: u64,
    username: BStr(128),
    end_datetime: utils.DateTime,
    turns: usize,
    result: []const u8, // "Escaped", "died in darkness", etc
    slain_str: []const u8, // Empty if won/quit
    slain_by_id: []const u8, // Empty if won/quit
    slain_by_name: BStr(32), // Empty if won/quit
    slain_by_captain_id: []const u8, // Empty if won/quit
    slain_by_captain_name: BStr(32), // Empty if won/quit
    level: usize,
    statuses: StackBuffer(types.StatusDataInfo, Status.TOTAL),
    stats: Mob.MobStat,
    surroundings: [SURROUND_RADIUS][SURROUND_RADIUS]u21,
    messages: StackBuffer(Message, MESSAGE_COUNT),

    in_view_ids: StackBuffer([]const u8, 32),
    in_view_names: StackBuffer([]const u8, 32),

    inventory_ids: StackBuffer([]const u8, Mob.Inventory.PACK_SIZE),
    inventory_names: StackBuffer(BStr(128), Mob.Inventory.PACK_SIZE),
    equipment: StackBuffer(Equipment, Mob.Inventory.EQU_SLOT_SIZE),
    aptitudes_names: StackBuffer([]const u8, player.PlayerUpgrade.TOTAL),
    aptitudes_descs: StackBuffer([]const u8, player.PlayerUpgrade.TOTAL),
    augments_names: StackBuffer([]const u8, player.ConjAugment.TOTAL),
    augments_descs: StackBuffer([]const u8, player.ConjAugment.TOTAL),

    pub const MESSAGE_COUNT = 30;
    pub const SURROUND_RADIUS = 20;
    pub const Self = @This();
    pub const Message = struct { text: BStr(128), dups: usize };
    pub const Equipment = struct { slot_id: []const u8, slot_name: []const u8, id: []const u8, name: BStr(128) };

    pub fn collect(alloc: std.mem.Allocator) Self {
        // FIXME: should be a cleaner way to do this...
        var s: Self = undefined;

        s.seed = state.seed;

        if (std.process.getEnvVarOwned(state.alloc, "USER")) |env| {
            s.username.reinit(env);
            state.alloc.free(env);
        } else |_| {
            if (std.process.getEnvVarOwned(state.alloc, "USERNAME")) |env| {
                s.username.reinit(env);
                state.alloc.free(env);
            } else |_| {
                s.username.reinit("Obmirnul");
            }
        }

        s.end_datetime = utils.DateTime.collect();
        s.turns = state.player_turns;

        s.result = switch (state.state) {
            .Viewer => "Ate a polar bear's liver",
            .Game => "Began meditating on the mysteries of eggplants",
            .Win => "Escaped the Necromancer's wrath",
            .Quit => "Overcome by the Fear of death",
            .Lose => b: {
                if (state.player.killed_by) |by| {
                    if (by.faction == .Necromancer) {
                        if (by.life_type == .Undead) {
                            break :b "Faced the Necromancer's wrath";
                        } else {
                            break :b "Paid for their treachery";
                        }
                    } else if (by.faction == .Night) {
                        // Don't use terrainAt() because the player's corpse will
                        // be there, and terrainAt() only returns the terrain if there's
                        // no surface item.
                        //
                        if (state.dungeon.at(state.player.coord).terrain == &surfaces.SladeTerrain) {
                            break :b "Died in darkness";
                        } else {
                            break :b "Fell into darkness";
                        }
                        // } else if (by.faction == .Revgenunkim) {
                        //     break :b "Overcome by an ancient Power";
                        // } else if (by.faction == .Holy) {
                        //     break :b "Cast into the Abyss";
                    } else {
                        break :b "Died on the journey";
                    }
                }
                break :b "Died on the journey";
            },
        };

        s.slain_str = "";
        s.slain_by_id = "";
        s.slain_by_captain_id = "";
        s.slain_by_name.reinit(null);
        s.slain_by_captain_name.reinit(null);

        if (state.state == .Lose and state.player.killed_by != null) {
            const ldp = state.player.lastDamagePercentage();
            s.slain_str = "slain";
            if (ldp > 10) s.slain_str = "executed";
            if (ldp > 20) s.slain_str = "demolished";
            if (ldp > 30) s.slain_str = "miserably destroyed";

            const killer = state.player.killed_by.?;
            s.slain_by_id = killer.id;
            s.slain_by_name.reinit(killer.displayName());

            if (!killer.isAloneOrLeader()) {
                if (killer.squad.?.leader) |leader| {
                    s.slain_by_captain_id = leader.id;
                    s.slain_by_captain_name.reinit(leader.displayName());
                }
            }
        }

        s.level = state.player.coord.z;

        s.statuses.reinit(null);
        var statuses = state.player.statuses.iterator();
        while (statuses.next()) |entry| {
            if (!state.player.hasStatus(entry.key)) continue;
            s.statuses.append(entry.value.*) catch err.wat();
        }

        s.stats = state.player.stats;

        {
            var dy: usize = 0;
            var my: usize = state.player.coord.y -| Info.SURROUND_RADIUS / 2;
            while (dy < Info.SURROUND_RADIUS) : ({
                dy += 1;
                my += 1;
            }) {
                var dx: usize = 0;
                var mx: usize = state.player.coord.x -| Info.SURROUND_RADIUS / 2;
                while (dx < Info.SURROUND_RADIUS) : ({
                    dx += 1;
                    mx += 1;
                }) {
                    if (mx >= WIDTH or my >= HEIGHT) {
                        s.surroundings[dy][dx] = ' ';
                        continue;
                    }

                    const coord = Coord.new2(state.player.coord.z, mx, my);

                    if (state.dungeon.neighboringWalls(coord, true) == 9) {
                        s.surroundings[dy][dx] = ' ';
                    } else if (state.player.coord.eq(coord)) {
                        s.surroundings[dy][dx] = '@';
                    } else {
                        s.surroundings[dy][dx] = @intCast(Tile.displayAs(coord, false, false).ch);
                    }
                }
            }
        }

        s.messages.reinit(null);
        if (state.messages.items.len > 0) {
            const msgcount = state.messages.items.len - 1;
            var i: usize = msgcount - @min(msgcount, MESSAGE_COUNT - 1);
            while (i <= msgcount) : (i += 1) {
                const msg = state.messages.items[i];
                s.messages.append(.{
                    .text = BStr(128).init(msg.msg.constSlice()),
                    .dups = msg.dups,
                }) catch err.wat();
            }
        }

        s.in_view_ids.reinit(null);
        s.in_view_names.reinit(null);
        {
            const can_see = state.createMobList(false, true, state.player.coord.z, state.alloc);
            defer can_see.deinit();
            for (can_see.items) |mob| {
                s.in_view_ids.append(mob.id) catch break;
                s.in_view_names.append(
                    std.fmt.allocPrint(alloc, "{cAf}", .{mob}) catch err.wat(),
                ) catch err.wat();
            }
        }

        s.inventory_ids.reinit(null);
        s.inventory_names.reinit(null);
        for (state.player.inventory.pack.constSlice()) |item| {
            s.inventory_ids.append(item.id().?) catch err.wat();
            s.inventory_names.append(BStr(128).init((item.longName() catch err.wat()).constSlice())) catch err.wat();
        }

        s.equipment.reinit(null);
        inline for (@typeInfo(Mob.Inventory.EquSlot).@"enum".fields) |slots_f| {
            const slot: Mob.Inventory.EquSlot = @enumFromInt(slots_f.value);
            const item = state.player.inventory.equipment(slot).*;
            s.equipment.append(.{
                .slot_id = @tagName(slot),
                .slot_name = slot.name(),
                .id = if (item) |i| i.id().? else "",
                .name = BStr(128).init(if (item) |i| (i.longName() catch err.wat()).constSlice() else ""),
            }) catch err.wat();
        }

        s.aptitudes_names.reinit(null);
        s.aptitudes_descs.reinit(null);
        for (state.player_upgrades) |upgr| if (upgr.recieved) {
            s.aptitudes_names.append(upgr.upgrade.name()) catch err.wat();
            s.aptitudes_descs.append(upgr.upgrade.description()) catch err.wat();
        };

        s.augments_names.reinit(null);
        s.augments_descs.reinit(null);
        for (state.player_conj_augments) |aug| if (aug.received) {
            s.augments_names.append(aug.a.name()) catch err.wat();
            s.augments_descs.append(aug.a.description()) catch err.wat();
        };

        return s;
    }
};

pub const Chunk = union(enum) {
    Header: struct { n: []const u8 },
    Stat: struct { s: Stat, n: []const u8, ign0: bool = true },
};

pub const CHUNKS = [_]Chunk{
    .{ .Header = .{ .n = "General stats" } },
    .{ .Stat = .{ .s = .TurnsSpent, .n = "turns spent" } },
    .{ .Stat = .{ .s = .StatusRecord, .n = "turns w/ statuses" } },
    .{ .Header = .{ .n = "Combat" } },
    .{ .Stat = .{ .s = .KillRecord, .n = "vanquished foes" } },
    .{ .Stat = .{ .s = .StabRecord, .n = "stabbed foes" } },
    .{ .Stat = .{ .s = .DamageInflicted, .n = "inflicted damage" } },
    .{ .Stat = .{ .s = .DamageEndured, .n = "endured damage" } },
    .{ .Header = .{ .n = "Items/rings" } },
    .{ .Stat = .{ .s = .ItemsUsed, .n = "items used" } },
    .{ .Stat = .{ .s = .ItemsThrown, .n = "items thrown" } },
    .{ .Stat = .{ .s = .RingsUsed, .n = "rings used" } },
    .{ .Header = .{ .n = "Misc" } },
    .{ .Stat = .{ .s = .RaidedLairs, .n = "lairs trespassed" } },
    .{ .Stat = .{ .s = .CandlesDestroyed, .n = "candles destroyed" } },
    .{ .Stat = .{ .s = .ShrinesDrained, .n = "shrines drained" } },
    .{ .Stat = .{ .s = .TimesCorrupted, .n = "times corrupted" } },
    .{ .Stat = .{ .s = .WizardUsed, .n = "wizard keys used" } },
};

pub const Stat = enum(usize) {
    TurnsSpent = 0,
    KillRecord = 1,
    StabRecord = 2,
    DamageInflicted = 3,
    DamageEndured = 4,
    StatusRecord = 5,
    ItemsUsed = 6,
    ItemsThrown = 7,
    RingsUsed = 8,
    RaidedLairs = 9,
    CandlesDestroyed = 10,
    ShrinesDrained = 11,
    TimesCorrupted = 12,
    WizardUsed = 13,

    pub fn stattype(self: Stat) std.meta.FieldEnum(StatValue) {
        return switch (self) {
            .TurnsSpent => .SingleUsize,
            .KillRecord => .BatchUsize,
            .StabRecord => .BatchUsize,
            .DamageInflicted => .BatchUsize,
            .DamageEndured => .BatchUsize,
            .StatusRecord => .BatchUsize,
            .ItemsUsed => .BatchUsize,
            .ItemsThrown => .BatchUsize,
            .RingsUsed => .BatchUsize,
            .RaidedLairs => .SingleUsize,
            .CandlesDestroyed => .SingleUsize,
            .ShrinesDrained => .SingleUsize,
            .TimesCorrupted => .BatchUsize,
            .WizardUsed => .BatchUsize,
        };
    }
};

pub const StatValue = struct {
    SingleUsize: Single = .{},
    BatchUsize: struct {
        total: usize = 0,
        singles: StackBuffer(BatchEntry, 256) = StackBuffer(BatchEntry, 256).init(null),
    },

    pub const BatchEntry = struct {
        id: StackBuffer(u8, 64) = StackBuffer(u8, 64).init(null),
        val: Single = .{},
    };

    pub const Single = struct {
        total: usize = 0,
        each: [LEVELS]usize = [1]usize{0} ** LEVELS,

        pub fn jsonStringify(val: Single, stream: anytype) !void {
            const JsonValue = struct { floor_type: []const u8, floor_name: []const u8, value: usize };
            var object: struct { total: usize, values: StackBuffer(JsonValue, LEVELS) } = .{
                .total = val.total,
                .values = StackBuffer(JsonValue, LEVELS).init(null),
            };

            var c: usize = state.levelinfo.len - 1;
            while (c > 0) : (c -= 1) if (_isLevelSignificant(c)) {
                const v = JsonValue{
                    .floor_type = state.levelinfo[c].id,
                    .floor_name = state.levelinfo[c].name,
                    .value = val.each[c],
                };
                object.values.append(v) catch err.wat();
            };

            //try std.json.stringify(object, opts, stream);
            try stream.write(object);
        }
    };
};

pub fn init() void {
    for (state.scoredata, 0..) |*entry, i|
        if (std.meta.enumFromInt(Stat, i)) |_| {
            entry.* = .{};
        } else |_| {};
}

pub fn get(s: Stat) *StatValue {
    return &state.scoredata[@intFromEnum(s)];
}

// XXX: this hidden reliance on state.player.z could cause bugs
// e.g. when recording stats of a level the player just left
pub fn recordUsize(stat: Stat, value: usize) void {
    switch (stat.stattype()) {
        .SingleUsize => {
            state.scoredata[@intFromEnum(stat)].SingleUsize.total += value;
            state.scoredata[@intFromEnum(stat)].SingleUsize.each[state.player.coord.z] += value;
        },
        else => unreachable,
    }
}

pub const Tag = union(enum) {
    M: *Mob,
    I: types.Item,
    W: player.WizardFun,
    s: []const u8,

    pub fn intoString(self: Tag) StackBuffer(u8, 64) {
        return switch (self) {
            .M => |mob| StackBuffer(u8, 64).initFmt("{s}", .{mob.displayName()}),
            .I => |item| StackBuffer(u8, 64).init((item.shortName() catch err.wat()).constSlice()),
            .W => |wiz| StackBuffer(u8, 64).init(@tagName(wiz)),
            .s => |str| StackBuffer(u8, 64).init(str),
        };
    }
};

// XXX: this hidden reliance on state.player.z could cause bugs
// e.g. when recording stats of a level the player just left
pub fn recordTaggedUsize(stat: Stat, tag: Tag, value: usize) void {
    const key = tag.intoString();
    switch (stat.stattype()) {
        .BatchUsize => {
            state.scoredata[@intFromEnum(stat)].BatchUsize.total += value;
            const index: ?usize = for (state.scoredata[@intFromEnum(stat)].BatchUsize.singles.constSlice(), 0..) |single, i| {
                if (mem.eql(u8, single.id.constSlice(), key.constSlice())) break i;
            } else null;
            if (index) |i| {
                state.scoredata[@intFromEnum(stat)].BatchUsize.singles.slice()[i].val.total += value;
                state.scoredata[@intFromEnum(stat)].BatchUsize.singles.slice()[i].val.each[state.player.coord.z] += value;
            } else {
                state.scoredata[@intFromEnum(stat)].BatchUsize.singles.append(.{}) catch err.wat();
                state.scoredata[@intFromEnum(stat)].BatchUsize.singles.lastPtr().?.id = key;
                state.scoredata[@intFromEnum(stat)].BatchUsize.singles.lastPtr().?.val.total += value;
                state.scoredata[@intFromEnum(stat)].BatchUsize.singles.lastPtr().?.val.each[state.player.coord.z] += value;
            }
        },
        else => unreachable,
    }
}

fn _isLevelSignificant(level: usize) bool {
    return state.scoredata[@intFromEnum(@as(Stat, .TurnsSpent))].SingleUsize.each[level] > 0;
}

fn exportTextMorgue(info: Info, alloc: mem.Allocator) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8).init(alloc);
    var w = buf.writer();

    try w.print("// Oathbreaker morgue entry @@ {}-{}-{} {}:{}\n", .{ info.end_datetime.Y, info.end_datetime.M, info.end_datetime.D, info.end_datetime.h, info.end_datetime.m });
    try w.print("// Seed: {}\n", .{info.seed});
    try w.print("\n", .{});

    try w.print("{s} the Oathbreaker\n", .{info.username.constSlice()});
    try w.print("\n", .{});
    try w.print("*** {s} ***\n", .{info.result});
    try w.print("\n", .{});

    if (state.state == .Lose or state.state == .Quit) {
        if (info.slain_str.len > 0) {
            try w.print("... {s} by a {s}\n", .{ info.slain_str, info.slain_by_name.constSlice() });
            if (info.slain_by_captain_name.len > 0)
                try w.print("... in service of a {s}\n", .{info.slain_by_captain_name.constSlice()});
        }
    }

    try w.print("... at {s} after {} turns\n", .{ state.levelinfo[info.level].name, info.turns });
    try w.print("\n", .{});

    try w.print(" State \n", .{});
    try w.print("=======\n", .{});
    try w.print("\n", .{});

    for (info.equipment.constSlice()) |equ| {
        try w.print("{s: <7} {s}\n", .{ equ.slot_name, equ.name.constSlice() });
    }
    try w.print("\n", .{});

    if (info.inventory_ids.len > 0) {
        try w.print("Inventory:\n", .{});
        for (info.inventory_names.constSlice()) |item|
            try w.print("- {s}\n", .{item.constSlice()});
    } else {
        try w.print("Your inventory was empty.\n", .{});
    }
    try w.print("\n", .{});

    if (info.aptitudes_names.len > 0) {
        try w.print("Aptitudes:\n", .{});
        for (info.aptitudes_names.constSlice(), 0..) |apt, i|
            try w.print("- [{s}] {s}\n", .{ apt, info.aptitudes_descs.data[i] });
    } else {
        try w.print("Your memory was still clouded.\n", .{});
    }
    try w.print("\n", .{});

    if (info.augments_names.len > 0) {
        try w.print("Conjuration Augments:\n", .{});
        for (info.augments_names.constSlice(), 0..) |apt, i|
            try w.print("- [{s}] {s}\n", .{ apt, info.augments_descs.data[i] });
        try w.print("\n", .{});
    }

    const killed = state.scoredata[@intFromEnum(@as(Stat, .KillRecord))].BatchUsize.total;
    const stabbed = state.scoredata[@intFromEnum(@as(Stat, .StabRecord))].BatchUsize.total;
    try w.print("You killed {} foe(s), stabbing {} of them.\n", .{ killed, stabbed });
    try w.print("\n", .{});

    try w.print(" Circumstances \n", .{});
    try w.print("===============\n", .{});
    try w.print("\n", .{});

    if (info.statuses.len > 0) {
        try w.print("Statuses:\n", .{});
        for (info.statuses.constSlice()) |statusinfo| {
            const sname = statusinfo.status.string(state.player);
            switch (statusinfo.duration) {
                .Prm => try w.print("<Prm> {s}", .{sname}),
                .Equ => try w.print("<Equ> {s}", .{sname}),
                .Tmp => try w.print("<Tmp> {s} ({})", .{ sname, statusinfo.duration.Tmp }),
                .Ctx => try w.print("<Ctx> {s}", .{sname}),
            }
            try w.print("\n", .{});
        }
    } else {
        try w.print("You had no status effects.\n", .{});
    }
    try w.print("\n", .{});

    try w.print("Last messages:\n", .{});
    for (info.messages.constSlice()) |message| {
        try w.print("- ", .{});
        {
            var f = false;
            for (message.text.constSlice()) |ch| {
                if (f) {
                    f = false;
                    continue;
                } else if (ch == '$') {
                    f = true;
                    continue;
                }
                try w.print("{u}", .{ch});
            }
        }
        if (message.dups > 0) {
            try w.print(" (×{})", .{message.dups + 1});
        }
        try w.print("\n", .{});
    }
    try w.print("\n", .{});

    try w.print("Surroundings:\n", .{});
    for (info.surroundings) |row| {
        for (row) |ch| {
            try w.print("{u}", .{ch});
        }
        try w.print("\n", .{});
    }
    try w.print("\n", .{});

    if (info.in_view_ids.len > 0) {
        try w.print("You could see:\n", .{});

        var can_see_counted = std.StringHashMap(usize).init(state.alloc);
        defer can_see_counted.deinit();

        for (info.in_view_names.constSlice()) |name| {
            const prevtotal = (can_see_counted.getOrPutValue(name, 0) catch err.wat()).value_ptr.*;
            can_see_counted.put(name, prevtotal + 1) catch unreachable;
        }

        var iter = can_see_counted.iterator();
        while (iter.next()) |mobcount| {
            try w.print("- {: >2} {s}\n", .{ mobcount.value_ptr.*, mobcount.key_ptr.* });
        }
    } else {
        try w.print("There was nothing in sight.\n", .{});
    }

    // Newlines will be auto-added by header, see below
    // try w.print("\n\n", .{});

    for (&CHUNKS) |chunk| {
        switch (chunk) {
            .Header => |header| {
                try w.print("\n\n", .{});
                try w.print(" {s: <30}", .{header.n});
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
                var si: usize = 30 - (header.n.len + 2) + 1;
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
                const entry = &state.scoredata[@intFromEnum(stat.s)];
                switch (stat.s.stattype()) {
                    .SingleUsize => {
                        try w.print("{s: <24} {: >5} | ", .{ stat.n, entry.SingleUsize.total });
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
                        try w.print("{s: <24} {: >5} |\n", .{ stat.n, entry.BatchUsize.total });
                        for (entry.BatchUsize.singles.slice()) |batch_entry| {
                            try w.print("  {s: <22} {: >5} | ", .{ batch_entry.id.constSlice(), batch_entry.val.total });
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

fn exportJsonMorgue(info: Info) !std.ArrayList(u8) {
    var buf = std.ArrayList(u8).init(state.alloc);
    var w = buf.writer();

    try w.writeAll("{");

    try w.writeAll("\"info\":");
    try std.json.stringify(info, .{}, w);

    try w.writeAll(",\"stats\":{");
    for (&CHUNKS, 0..) |chunk, chunk_i| switch (chunk) {
        .Header => {},
        .Stat => |stat| {
            const entry = &state.scoredata[@intFromEnum(stat.s)];
            try w.print("\"{s}\": {{", .{stat.n});
            try w.print("\"type\": \"{s}\",", .{@tagName(stat.s.stattype())});
            switch (stat.s.stattype()) {
                .SingleUsize => {
                    try w.writeAll("\"value\":");
                    try std.json.stringify(entry.SingleUsize, .{}, w);
                },
                .BatchUsize => {
                    try w.writeAll("\"values\": [");
                    for (entry.BatchUsize.singles.slice(), 0..) |batch_entry, i| {
                        try w.print("{{ \"name\": \"{s}\", \"value\":", .{batch_entry.id.constSlice()});
                        try std.json.stringify(batch_entry.val, .{}, w);
                        try w.writeAll("}");
                        if (i != entry.BatchUsize.singles.slice().len - 1)
                            try w.writeAll(",");
                    }
                    try w.writeAll("]");
                },
            }
            try w.writeAll("}");

            if (chunk_i != CHUNKS.len - 1)
                try w.writeAll(",");
        },
    };
    try w.writeByte('}');

    try w.writeByte('}');

    return buf;
}

pub fn createMorgue() Info {
    var arena = std.heap.ArenaAllocator.init(state.alloc);
    defer arena.deinit();

    const info = Info.collect(arena.allocator());

    std.posix.mkdir("morgue", 0o776) catch |e| switch (e) {
        error.PathAlreadyExists => {},
        else => {
            std.log.err("Could not create morgue directory: {}", .{e});
            std.log.err("Refusing to write morgue entries.", .{});
            return info;
        },
    };
    const morgue_dir = std.fs.cwd().openDir("morgue", .{}) catch err.wat();

    {
        const morgue = exportJsonMorgue(info) catch err.wat();
        defer morgue.deinit();

        const filename = std.fmt.allocPrintZ(state.alloc, "morgue-{s}-{}-{}-{:0>2}-{:0>2}-{}:{}.json", .{ info.username.constSlice(), state.seed, info.end_datetime.Y, info.end_datetime.M, info.end_datetime.D, info.end_datetime.h, info.end_datetime.m }) catch err.oom();
        defer state.alloc.free(filename);

        morgue_dir.writeFile(.{ .sub_path = filename, .data = morgue.items[0..] }) catch |e| {
            std.log.err("Could not write to morgue file '{s}': {}", .{ filename, e });
            std.log.err("Refusing to write morgue entries.", .{});
            return info;
        };
        std.log.info("Morgue file written to {s}.", .{filename});
    }
    {
        const morgue = exportTextMorgue(info, state.alloc) catch err.wat();
        defer morgue.deinit();

        const filename = std.fmt.allocPrintZ(state.alloc, "morgue-{s}-{}-{}-{:0>2}-{:0>2}-{}:{}.txt", .{ info.username.constSlice(), state.seed, info.end_datetime.Y, info.end_datetime.M, info.end_datetime.D, info.end_datetime.h, info.end_datetime.m }) catch err.oom();
        defer state.alloc.free(filename);

        morgue_dir.writeFile(.{ .sub_path = filename, .data = morgue.items[0..] }) catch |e| {
            std.log.err("Could not write to morgue file '{s}': {}", .{ filename, e });
            std.log.err("Refusing to write morgue entries.", .{});
            return info;
        };
        std.log.info("Morgue file written to {s}.", .{filename});
    }

    return info;
}
