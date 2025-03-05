const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const colors = @import("../colors.zig");
const err = @import("../err.zig");
const gas = @import("../gas.zig");
const rng = @import("../rng.zig");
const state = @import("../state.zig");
const surfaces = @import("../surfaces.zig");
const types = @import("../types.zig");

const Machine = types.Machine;
const Mob = types.Mob;
const Terrain = surfaces.Terrain;
const StackBuffer = @import("../buffer.zig").StackBuffer;

const Filter = enum { Mob, Machine, Terrain };

const Char = struct {
    ch: u21,
    original_weight: usize,
    weight: usize = 0,
};

const PresetColor = struct {
    name: []const u8,
    base: enum(u24) {
        Crimson = 0xcb042c, // Darker version of crimson
        Red = 0xcc0314,
        BrownRed = 0x951a1a,
        Green = 0x556855,
        Purple = 0x451a89,
        Grey = 0xcacbca,
        Brown = 0x955a3a,
        Gold = 0xaa8700,
    },
    variation: colors.ColorDance,

    original_weight: usize = 1,
    weight: usize = 0,
};

const Name = struct {
    kind: Kind,
    string: []const u8,
    prefer_color: ?[]const u8 = null,
    forbid: ?[]const u8 = null,
    original_weight: usize = 10,

    // Reset after generation process
    weight: usize = 0,

    pub const Kind = enum { Adj, Noun };
};

const Trait = struct {
    kind: Kind,
    prefer_names: ?[]const Preference = null,
    prefer_tile: ?u21 = null,
    attached: ?*const Trait = null,

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
        Opacity: usize,

        // Mob only
        //BloodCloud: usize, // gas id
        //DeathProp: []const u8, // prop id
        //Spikes: usize,

        // Both
        //Scatter: struct {
        //  names: []const []const u8,
        //  chance: usize, // one in X
        //},

        pub fn format(self: @This(), comptime f: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            if (comptime !mem.eql(u8, f, "")) {
                @compileError("Unknown format string: '" ++ f ++ "'");
            }

            try writer.writeAll(@tagName(self));
            try writer.writeAll(": ");

            try switch (self) {
                .Status => |st| writer.print("{s} {}", .{ @tagName(st.status), st.duration }),
                .TrampleCloud => |g| writer.print("{s} 1/{}, {}u", .{ gas.Gases[g.id].name, g.chance, g.amount }),
                .TrampleInto => |t| writer.print("{s}", .{t.name}),
                .Luminescent => writer.writeAll(""),
                .Opacity => |o| writer.print("{}", .{o}),
            };
        }

        pub fn apply(self: @This(), onto: *surfaces.Terrain) void {
            switch (self) {
                .Status => |st| {
                    const effects = if (onto.effects.len == 0)
                        state.alloc.alloc(types.StatusDataInfo, 1) catch err.oom()
                    else
                        state.alloc.realloc(@constCast(onto.effects), onto.effects.len + 1) catch err.oom();
                    effects[effects.len - 1] = st;
                    // Can't assign directly because onto.effects is const
                    onto.effects = effects;
                },
                .TrampleCloud => |g| onto.trample_cloud = g,
                .TrampleInto => |t| onto.trample_into = t,
                .Luminescent => |_| onto.luminescence = 50,
                .Opacity => |o| onto.opacity = o,
            }
        }
    };
};

pub fn s(st: types.Status, d: types.StatusDataInfo.Duration) types.StatusDataInfo {
    return .{ .status = st, .power = 0, .duration = d, .add_duration = false };
}

const COLORS = [_]PresetColor{
    .{ .name = "blood red", .base = .Crimson, .variation = .{ .each = 0x222222, .all = 20 } },
    .{ .name = "red", .base = .Red, .variation = .{ .each = 0x2f1212, .all = 20 } },
    .{ .name = "reddish brown", .base = .BrownRed, .variation = .{ .each = 0x131308, .all = 18 } },
    .{ .name = "green", .base = .Green, .variation = .{ .each = 0x101510, .all = 18 } },
    .{ .name = "purple", .base = .Purple, .variation = .{ .each = 0x23132f, .all = 24 } },
    .{ .name = "brown", .base = .Brown, .variation = .{ .each = 0x151515, .all = 20 } },
    .{ .name = "gold", .base = .Gold, .variation = .{ .each = 0x25251a, .all = 20 } },
};

const CHARS = [_]Char{
    .{ .ch = '"', .original_weight = 10 },
    .{ .ch = '&', .original_weight = 0 },
    .{ .ch = '%', .original_weight = 0 },
    .{ .ch = '$', .original_weight = 5 },
    .{ .ch = '*', .original_weight = 0 },
};

const NAMES = [_]Name{
    .{ .kind = .Adj, .string = "blood", .prefer_color = "blood red", .original_weight = 0 },
    .{ .kind = .Adj, .string = "red", .prefer_color = "red" },
    .{ .kind = .Adj, .string = "ember", .prefer_color = "red" },
    .{ .kind = .Adj, .string = "cinder", .prefer_color = "red" },
    .{ .kind = .Adj, .string = "crimson", .prefer_color = "blood red" },
    .{ .kind = .Adj, .string = "rusty", .forbid = "rust", .prefer_color = "reddish brown" },
    .{ .kind = .Adj, .string = "green", .prefer_color = "green" },
    .{ .kind = .Adj, .string = "slimy", .original_weight = 0 },
    .{ .kind = .Adj, .string = "honey", .prefer_color = "gold" },
    .{ .kind = .Adj, .string = "golden" },
    .{ .kind = .Adj, .string = "oily" },
    .{ .kind = .Adj, .string = "waxy" },
    .{ .kind = .Adj, .string = "blue", .prefer_color = "purple" }, // lol
    .{ .kind = .Adj, .string = "inky" },
    .{ .kind = .Adj, .string = "brooding" },
    .{ .kind = .Adj, .string = "dimpled" },
    .{ .kind = .Adj, .string = "pitted" },
    .{ .kind = .Adj, .string = "patchy" },
    .{ .kind = .Adj, .string = "weeping", .forbid = "weep", .original_weight = 0 },
    .{ .kind = .Adj, .string = "clinging", .forbid = "clinger", .original_weight = 0 },
    .{ .kind = .Adj, .string = "sticky", .original_weight = 0 },

    .{ .kind = .Noun, .string = "clinger", .forbid = "clinging", .original_weight = 0 },
    .{ .kind = .Noun, .string = "cap" },
    .{ .kind = .Noun, .string = "thorn", .original_weight = 0 },
    .{ .kind = .Noun, .string = "plate" },
    .{ .kind = .Noun, .string = "bulb" },
    .{ .kind = .Noun, .string = "bowl" },
    .{ .kind = .Noun, .string = "cup" },
    .{ .kind = .Noun, .string = "weep", .forbid = "weeping", .original_weight = 0 },
    .{ .kind = .Noun, .string = "puff", .original_weight = 0 },
    .{ .kind = .Noun, .string = "cherub" },
    .{ .kind = .Noun, .string = "tower", .original_weight = 0 },
    .{ .kind = .Noun, .string = "lichen" },
    .{ .kind = .Noun, .string = "moss" },
    .{ .kind = .Noun, .string = "stoneberry" },
    .{ .kind = .Noun, .string = "gemfruit" },
    .{ .kind = .Noun, .string = "gemcap" },
    .{ .kind = .Noun, .string = "gemthorn", .original_weight = 0 },
    .{ .kind = .Noun, .string = "stonecap" },
    .{ .kind = .Noun, .string = "pipe" },
    .{ .kind = .Noun, .string = "tube" },
    .{ .kind = .Noun, .string = "trumpet" },
    .{ .kind = .Noun, .string = "tuber" },
    .{ .kind = .Noun, .string = "mushroom" },
    .{ .kind = .Noun, .string = "fungi" },
    .{ .kind = .Noun, .string = "toadstool", .original_weight = 0 },
    .{ .kind = .Noun, .string = "rust", .forbid = "rusty" },
    .{ .kind = .Noun, .string = "mycelium" },
    .{ .kind = .Noun, .string = "rot", .original_weight = 0 },
};

const TRAITS = [_]Trait{
    .{
        .kind = .{ .Status = s(.Noisy, .{ .Ctx = null }) },
        .prefer_names = &[1]Trait.Preference{.{ .n = "trumpet", .w = 30 }},
    },
    .{
        .kind = .{ .Status = s(.Held, .{ .Tmp = 3 }) },
        .prefer_names = &[3]Trait.Preference{
            .{ .n = "clinger", .w = 20 },
            .{ .n = "clinging", .w = 20 },
            .{ .n = "sticky", .w = 20 },
        },
    },
    .{
        .kind = .{ .Status = s(.Recuperate, .{ .Tmp = 3 }) },
        // Fragility concept doesn't work
        //
        // - Moving onto: terrain breaks as soon as it's stepped on, so no time
        //   for effect to happen
        // - Moving off: no point, player can stay as long as they want on
        //   terrain to recuperate
        //.attached = &Trait{ .kind = .Fragile },
    },
    .{
        .kind = .{ .Status = s(.Nausea, .{ .Ctx = null }) },
        .prefer_names = &[1]Trait.Preference{.{ .n = "rot", .w = 20 }},
    },
    .{
        .kind = .{ .Status = s(.Pain, .{ .Ctx = null }) },
        .prefer_names = &[4]Trait.Preference{
            .{ .n = "thorn", .w = 30 },
            .{ .n = "blood", .w = 30 },
            .{ .n = "gemthorn", .w = 10 },
            .{ .n = "toadstool", .w = 20 },
        },
    },
    .{
        .kind = .{ .TrampleInto = &surfaces.ShallowWaterTerrain },
        .prefer_names = &[2]Trait.Preference{
            .{ .n = "weep", .w = 40 },
            .{ .n = "weeping", .w = 40 },
        },
        .prefer_tile = '%',
    },
    .{
        .kind = .{ .TrampleCloud = .{ .id = gas.Dust.id, .chance = 1, .amount = 30 } },
        .prefer_names = &[1]Trait.Preference{.{ .n = "puff", .w = 20 }},
        .prefer_tile = '*',
    },
    .{
        .kind = .{ .TrampleCloud = .{ .id = gas.Paralysis.id, .chance = 20, .amount = 20 } },
        .prefer_names = &[1]Trait.Preference{.{ .n = "puff", .w = 30 }},
        .prefer_tile = '*',
    },
    .{
        .kind = .{ .TrampleCloud = .{ .id = gas.Blinding.id, .chance = 10, .amount = 30 } },
        .prefer_names = &[1]Trait.Preference{.{ .n = "puff", .w = 30 }},
        .prefer_tile = '*',
    },
    // .{
    //     .kind = .{ .Scatter = &[_][]const u8{ "fungal piece"} },
    //     .prefer_names = &[_].{ .{ .n = "puff", .w = 10 } },
    // },
    .{
        .kind = .{ .Luminescent = .{} },
    },
    // .{
    //     .kind = .{ .Opacity = 100 },
    //     .prefer_names = &[5]Trait.Preference{
    //         .{ .n = "tube", .w = 30 },
    //         .{ .n = "pipe", .w = 30 },
    //         .{ .n = "tower", .w = 20 },
    //         .{ .n = "moss", .w = -999 },
    //         .{ .n = "lichen", .w = -999 },
    //     },
    //     .prefer_tile = '&',
    // },
};

// Generates a single fungi into a given terrain, and removes its name and
// traits so it can't be used in future generation cycles. Tiles are not unique
// and can be reused.
fn generateSingle(
    onto: *Terrain,
    traits: *StackBuffer(Trait, TRAITS.len),
    names: *StackBuffer(Name, NAMES.len),
    clrs: *StackBuffer(PresetColor, COLORS.len),
) void {
    for (names.slice()) |*i| i.weight = i.original_weight;
    for (clrs.slice()) |*i| i.weight = i.original_weight;

    var tiles = StackBuffer(Char, CHARS.len).init(&CHARS);

    var chosen_traits = StackBuffer(Trait, 2).init(null);

    for (0..rng.range(usize, 1, 2)) |_| {
        const chosen_ind = rng.range(usize, 0, traits.len - 1);
        const chosen = traits.orderedRemove(chosen_ind) catch err.wat();
        chosen_traits.append(chosen) catch err.wat();

        if (chosen.prefer_names) |preferred_names| {
            for (preferred_names) |preference| {
                const name_ind = for (names.constSlice(), 0..) |n, i| {
                    if (mem.eql(u8, n.string, preference.n)) break i;
                } else {
                    // Already used and removed from list.
                    continue;
                };
                names.slice()[name_ind].weight = @intCast(@max(0, @as(isize, @intCast(names.slice()[name_ind].weight)) + preference.w));
            }
        }

        if (chosen.prefer_tile) |preferred_tile| {
            for (tiles.slice()) |*n| {
                if (n.ch == preferred_tile)
                    n.weight += 30;
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

        if (chosen.prefer_color) |color_name|
            for (clrs.slice()) |*color|
                if (mem.eql(u8, color.name, color_name)) {
                    color.weight += 5;
                    break;
                };
    }

    const chosen_clr_ind = rng.chooseInd2(PresetColor, clrs.constSlice(), "weight");
    const chosen_clr = clrs.orderedRemove(chosen_clr_ind) catch err.wat();

    // std.log.info("*** {s} {s}", .{ adj.?.string, noun.?.string });
    // std.log.info("  - Trait: {}", .{chosen_traits.constSlice()[0].kind});
    // if (chosen_traits.len > 1)
    //     std.log.info("  - Trait: {}", .{chosen_traits.constSlice()[1].kind});
    // std.log.info("  - Color: {s}", .{chosen_clr.name});

    const chosen_tile = rng.choose2(Char, tiles.constSlice(), "weight") catch err.wat();

    // Now apply to the terrain

    for (chosen_traits.constSlice()) |trait| {
        trait.kind.apply(onto);
        if (trait.attached) |attached|
            attached.kind.apply(onto);
    }

    onto.name = std.fmt.allocPrint(state.alloc, "{s} {s}", .{ adj.?.string, noun.?.string }) catch err.oom();
    onto.fg = @intFromEnum(chosen_clr.base);
    onto.fg_dance = chosen_clr.variation;
    onto.tile = chosen_tile.ch;
}

pub fn init() void {
    var traits = StackBuffer(Trait, TRAITS.len).init(&TRAITS);
    var names = StackBuffer(Name, NAMES.len).init(&NAMES);
    var clrs = StackBuffer(PresetColor, COLORS.len).init(&COLORS);

    generateSingle(&surfaces.CavernsTerrain1, &traits, &names, &clrs);
    generateSingle(&surfaces.CavernsTerrain2, &traits, &names, &clrs);
    generateSingle(&surfaces.CavernsTerrain3, &traits, &names, &clrs);
    generateSingle(&surfaces.CavernsTerrain4, &traits, &names, &clrs);
}

pub fn deinit() void {
    state.alloc.free(surfaces.CavernsTerrain1.name);
    state.alloc.free(surfaces.CavernsTerrain2.name);
    state.alloc.free(surfaces.CavernsTerrain3.name);
    state.alloc.free(surfaces.CavernsTerrain4.name);

    if (surfaces.CavernsTerrain1.effects.len > 0)
        state.alloc.free(surfaces.CavernsTerrain1.effects);
    if (surfaces.CavernsTerrain2.effects.len > 0)
        state.alloc.free(surfaces.CavernsTerrain2.effects);
    if (surfaces.CavernsTerrain3.effects.len > 0)
        state.alloc.free(surfaces.CavernsTerrain3.effects);
    if (surfaces.CavernsTerrain4.effects.len > 0)
        state.alloc.free(surfaces.CavernsTerrain4.effects);
}
