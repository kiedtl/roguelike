const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const rng = @import("../rng.zig");
const surfaces = @import("../surfaces.zig");
const err = @import("../err.zig");
const types = @import("../types.zig");
const gas = @import("../gas.zig");
const colors = @import("../colors.zig");

const Machine = types.Machine;
const Mob = types.Mob;
const Terrain = surfaces.Terrain;
const StackBuffer = @import("../buffer.zig").StackBuffer;

const Filter = enum { Mob, Machine, Terrain };

const PresetColor = struct {
    name: "red",

    base: enum(u24) {
        Red = 0xcc1354,
    },

    variation: colors.ColorDance,
};

const Name = struct {
    kind: Kind,
    string: []const u8,
    prefer_color: ?[]const u8 = null,
    forbid: ?[]const u8 = null,
    special: bool = false,
    weight: usize = 10,

    pub const Kind = enum { Adj, Noun };
};

const Trait = struct {
    kind: Kind,
    prefer: ?[]const Preference = null,

    pub const Preference = struct {
        n: []const u8,
        w: isize,
    };

    pub const Kind = union(enum) {
        // Terrain only
        Status: types.StatusDataInfo,
        TrampleCloud: gas.GasCreationOpts,
        TrampleInto: *const Terrain,
        Luminescent: struct {},

        // Mob only
        BloodCloud: usize, // gas id
        DeathProp: []const u8, // prop id
        Spikes: usize,

        // Both
        //Scatter: struct {
        //  names: []const []const u8,
        //  chance: usize, // one in X
        //},
    };
};

pub fn s(st: types.Status, d: types.StatusDataInfo.Duration) types.StatusDataInfo {
    return .{ .status = st, .power = 0, .duration = d };
}

const COLORS = [_]PresetColor{
    .{ .name = "blood red", .base = .Red, .variation = .{ .each = 0x121212, .all = 5 } },
};

const NAMES = [_]Name{
    .{ .kind = .Adj, .string = "blood", .prefer_color = "blood red", .special = true },
    .{ .kind = .Adj, .string = "red", .prefer_color = "blood red" },
    .{ .kind = .Adj, .string = "ember", .prefer_color = "blood red" },
    .{ .kind = .Adj, .string = "cinder", .prefer_color = "blood red" },
    .{ .kind = .Adj, .string = "crimson", .prefer_color = "blood red" },
    .{ .kind = .Adj, .string = "rusty", .forbid = "rust" },
    .{ .kind = .Adj, .string = "green" },
    .{ .kind = .Adj, .string = "slimy", .special = true },
    .{ .kind = .Adj, .string = "honey" },
    .{ .kind = .Adj, .string = "golden" },
    .{ .kind = .Adj, .string = "oily" },
    .{ .kind = .Adj, .string = "waxy" },
    .{ .kind = .Adj, .string = "blue" },
    .{ .kind = .Adj, .string = "inky" },
    .{ .kind = .Adj, .string = "brooding" },
    .{ .kind = .Adj, .string = "dimpled" },
    .{ .kind = .Adj, .string = "pitted" },
    .{ .kind = .Adj, .string = "patchy" },
    .{ .kind = .Adj, .string = "weeping", .forbid = "weep", .special = true },

    .{ .kind = .Noun, .string = "cap" },
    .{ .kind = .Noun, .string = "thorn", .special = true },
    .{ .kind = .Noun, .string = "plate" },
    .{ .kind = .Noun, .string = "bulb" },
    .{ .kind = .Noun, .string = "bowl" },
    .{ .kind = .Noun, .string = "cup" },
    .{ .kind = .Noun, .string = "weep", .forbid = "weeping", .special = true },
    .{ .kind = .Noun, .string = "puff" },
    .{ .kind = .Noun, .string = "cherub" },
    .{ .kind = .Noun, .string = "tower" },
    .{ .kind = .Noun, .string = "lichen" },
    .{ .kind = .Noun, .string = "moss" },
    .{ .kind = .Noun, .string = "stoneberry" },
    .{ .kind = .Noun, .string = "gemfruit" },
    .{ .kind = .Noun, .string = "gemcap" },
    .{ .kind = .Noun, .string = "gemthorn", .special = true },
    .{ .kind = .Noun, .string = "stonecap" },
    .{ .kind = .Noun, .string = "pipe" },
    .{ .kind = .Noun, .string = "tube" },
    .{ .kind = .Noun, .string = "trumpet" },
    .{ .kind = .Noun, .string = "tuber" },
    .{ .kind = .Noun, .string = "mushroom" },
    .{ .kind = .Noun, .string = "fungi" },
    .{ .kind = .Noun, .string = "toadstool", .special = true },
    .{ .kind = .Noun, .string = "rust", .forbid = "rusty" },
    .{ .kind = .Noun, .string = "mycelium" },
    .{ .kind = .Noun, .string = "rot", .special = true },
};

const TRAITS = [_]Trait{
    .{
        .kind = .{ .Status = s(.Noisy, .{ .Ctx = null }) },
        .prefer = &[1]Trait.Preference{.{ .n = "trumpet", .w = 10 }},
    },
    .{
        .kind = .{ .TrampleInto = &surfaces.ShallowWaterTerrain },
        .prefer = &[1]Trait.Preference{.{ .n = "weep", .w = 10 }},
    },
    .{
        .kind = .{ .TrampleCloud = .{ .id = gas.Dust.id, .chance = 1, .amount = 20 } },
        .prefer = &[1]Trait.Preference{.{ .n = "puff", .w = 10 }},
    },
    // .{
    //     .kind = .{ .Scatter = &[_][]const u8{ "fungal piece"} },
    //     .prefer = &[_].{ .{ .n = "puff", .w = 10 } },
    // },
    .{
        .kind = .{ .Luminescent = .{} },
    },
    .{
        .kind = .{ .Status = s(.Nausea, .{ .Ctx = null }) },
        .prefer = &[1]Trait.Preference{.{ .n = "rot", .w = 10 }},
    },
    .{
        .kind = .{ .Status = s(.Pain, .{ .Ctx = null }) },
        .prefer = &[4]Trait.Preference{
            .{ .n = "thorn", .w = 10 },
            .{ .n = "blood", .w = 10 },
            .{ .n = "gemthorn", .w = 1 },
            .{ .n = "toadstool", .w = 5 },
        },
    },
};

pub fn generateSingle() void {
    var traits = StackBuffer(Trait, TRAITS.len).init(&TRAITS);
    var names = StackBuffer(Name, NAMES.len).init(null);
    for (&NAMES) |name|
        if (!name.special)
            names.append(name) catch err.wat();

    var chosen_traits = StackBuffer(Trait, 2).init(null);

    for (0..rng.range(usize, 1, 2)) |_| {
        const chosen_ind = rng.range(usize, 0, TRAITS.len);
        const chosen = traits.orderedRemove(chosen_ind) catch err.wat();
        chosen_traits.append(chosen) catch err.wat();

        if (chosen.prefer) |preferred_names| {
            for (preferred_names) |preference| {
                const name_ind = for (names.constSlice(), 0..) |n, i| {
                    if (mem.eql(u8, n.string, preference.n)) break i;
                } else for (&NAMES) |n| {
                    if (mem.eql(u8, n.string, preference.n)) {
                        assert(n.special);
                        names.append(n) catch err.wat();
                        break names.len - 1;
                    }
                } else b: {
                    err.ensure(false, "Fungi name {s} doesn't exist.", .{preference.n}) catch {};
                    break :b 0;
                };
                names.slice()[name_ind].weight = @intCast(@as(isize, @intCast(names.slice()[name_ind].weight)) + preference.w);
            }
        }
    }

    var adj: ?Name = null;
    var noun: ?Name = null;

    while (adj == null or noun == null) {
        const chosen = rng.choose2(Name, names.constSlice(), "weight") catch err.wat();
        switch (chosen.kind) {
            .Noun => {
                if (adj != null and adj.?.forbid != null and mem.eql(u8, adj.?.forbid.?, chosen.string))
                    continue;
                noun = chosen;
            },
            .Adj => {
                if (noun != null and noun.?.forbid != null and mem.eql(u8, noun.?.forbid.?, chosen.string))
                    continue;
                adj = chosen;
            },
        }
    }

    std.log.info("Generated:", .{});
    std.log.info("  - {s} {s}", .{ adj.?.string, noun.?.string });
    std.log.info("  - Trait: {any}", .{traits.constSlice()[0]});
    if (traits.len > 1)
        std.log.info("  - Trait: {any}", .{traits.constSlice()[1]});
}
