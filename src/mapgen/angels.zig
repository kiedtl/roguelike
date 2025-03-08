const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const colors = @import("../colors.zig");
const err = @import("../err.zig");
const gas = @import("../gas.zig");
const mobs = @import("../mobs.zig");
const rng = @import("../rng.zig");
const spells = @import("../spells.zig");
const state = @import("../state.zig");
const surfaces = @import("../surfaces.zig");
const types = @import("../types.zig");

const Machine = types.Machine;
const MobTemplate = mobs.MobTemplate;
const Mob = types.Mob;
const Resistance = types.Resistance;
const StackBuffer = @import("../buffer.zig").StackBuffer;
const Stat = types.Stat;
const Terrain = surfaces.Terrain;

const Filter = enum { Mob, Machine, Terrain };

const Char = struct {
    ch: u21,
    original_weight: usize,
    weight: usize = 0,
};

const Name = struct {
    kind: Kind,
    str: []const u8,
    syl: usize,
    prefer_color: ?[]const u8 = null,
    forbid: ?[]const u8 = null,
    original_weight: usize = 10,
    require: ?AngelKind = null,

    // Reset after generation process
    weight: usize = 0,

    pub const Kind = enum { Adj, Noun };
};

const Trait = struct {
    power: isize,
    name: []const u8,
    kind: Kind,
    prefer_names: ?[]const Preference = null,
    prefer_tile: ?u21 = null,
    attached: ?*const Trait = null,
    require_kind: ?[]const AngelKind = null,
    max_used: usize = 1,
    original_weight: usize = 1,

    weight: usize = 0,
    used_ctr: usize = 0,

    pub const Preference = struct {
        n: []const u8,
        w: isize,
    };

    pub const Kind = union(enum) {
        Foo,
        Stat: std.enums.EnumFieldStruct(Stat, isize, 0),
        Resist: std.enums.EnumFieldStruct(Resistance, isize, 0),
        Status: []const types.StatusDataInfo,
        Spell: spells.SpellOptions,

        // Mostly for debugging, so it's ok if this is incomplete
        //
        pub fn format(self: @This(), comptime f: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            if (comptime !mem.eql(u8, f, "")) {
                @compileError("Unknown format string: '" ++ f ++ "'");
            }

            try writer.writeAll(@tagName(self));
            try writer.writeAll(": ");

            try switch (self) {
                else => writer.writeAll(""),
            };
        }

        pub fn apply(self: @This(), _: *MobTemplate) void {
            switch (self) {
                .Foo => {},
            }
        }
    };
};

pub fn s(st: types.Status, d: types.StatusDataInfo.Duration) types.StatusDataInfo {
    return .{ .status = st, .power = 0, .duration = d, .add_duration = false };
}

const CHARS = [_]Char{
    .{ .ch = 'א', .original_weight = 10 },
    .{ .ch = 'ד', .original_weight = 10 },
    .{ .ch = 'ה', .original_weight = 10 },
    .{ .ch = 'ט', .original_weight = 10 },
    .{ .ch = 'ל', .original_weight = 10 },
    .{ .ch = 'ם', .original_weight = 10 },
    .{ .ch = 'מ', .original_weight = 10 },
    .{ .ch = 'ס', .original_weight = 10 },
    .{ .ch = 'ע', .original_weight = 10 },
    .{ .ch = 'ף', .original_weight = 10 },
    .{ .ch = 'פ', .original_weight = 10 },
    .{ .ch = 'ץ', .original_weight = 10 },
    .{ .ch = 'צ', .original_weight = 10 },
    .{ .ch = 'ק', .original_weight = 10 },
    .{ .ch = 'ש', .original_weight = 10 },
    .{ .ch = 'ת', .original_weight = 10 },
};

const NAMES = [_]Name{
    .{ .kind = .Adj, .str = "Silver", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Adamantine", .syl = 4, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Grim", .syl = 1, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Armored", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Dread", .syl = 1 },
    .{ .kind = .Adj, .str = "Crimson", .syl = 2 },
    .{ .kind = .Adj, .str = "Red", .syl = 1 },
    .{ .kind = .Adj, .str = "Iron", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Bladed", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Horned", .syl = 1 },
    .{ .kind = .Adj, .str = "Pronged", .syl = 1 },
    .{ .kind = .Adj, .str = "Clawed", .syl = 1 },
    .{ .kind = .Adj, .str = "Skewering", .syl = 3, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Spiked", .syl = 1, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Boiling", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Burning", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Blazing", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Molten", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Cinder", .syl = 2, .original_weight = 0 },
    .{ .kind = .Adj, .str = "Shining", .syl = 2 },
    .{ .kind = .Adj, .str = "Towering", .syl = 3 },

    .{ .kind = .Noun, .str = "Crawler", .syl = 2 },
    .{ .kind = .Noun, .str = "Banisher", .syl = 2, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Purger", .syl = 2, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Cleanser", .syl = 2, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Disruptor", .syl = 3, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Tormentor", .syl = 3, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Smiter", .syl = 2, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Destroyer", .syl = 3, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Terminator", .syl = 4, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Dread", .syl = 1 },
    .{ .kind = .Noun, .str = "Slayer", .syl = 2 },
    .{ .kind = .Noun, .str = "Hunter", .syl = 2 },
    .{ .kind = .Noun, .str = "Warrior", .syl = 2 },
    .{ .kind = .Noun, .str = "Fury", .syl = 2 },
    .{ .kind = .Noun, .str = "Executioner", .syl = 5 },
    .{ .kind = .Noun, .str = "Blademaster", .syl = 3, .original_weight = 0 },
    .{ .kind = .Noun, .str = "One", .syl = 1 },
    .{ .kind = .Noun, .str = "Spirit", .syl = 2 },
    .{ .kind = .Noun, .str = "Terror", .syl = 2 },
    .{ .kind = .Noun, .str = "Menace", .syl = 2 },
    .{ .kind = .Noun, .str = "Servitor", .syl = 3 },
    .{ .kind = .Noun, .str = "Arbalist", .syl = 3, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Archer", .syl = 2 },
    .{ .kind = .Noun, .str = "Crusher", .syl = 2 },
    .{ .kind = .Noun, .str = "Star", .syl = 1 },
    .{ .kind = .Noun, .str = "Starspawn", .syl = 2 },
    .{ .kind = .Noun, .str = "Guardian", .syl = 3 },
    .{ .kind = .Noun, .str = "Sentinel", .syl = 3 },
    .{ .kind = .Noun, .str = "Enforcer", .syl = 3 },
    .{ .kind = .Noun, .str = "Lancer", .syl = 2, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Piercer", .syl = 2, .original_weight = 0 },
    .{ .kind = .Noun, .str = "Striker", .syl = 2 },
    .{ .kind = .Noun, .str = "Veteran", .syl = 3 },
    .{ .kind = .Noun, .str = "Trooper", .syl = 2 },
    .{ .kind = .Noun, .str = "Knight", .syl = 1 },
    .{ .kind = .Noun, .str = "Furnace", .syl = 2, .original_weight = 0 },

    // Follower angels
    .{ .kind = .Adj, .str = "Fledgeling", .syl = 2, .require = .Follower },
    .{ .kind = .Noun, .str = "Assistant", .syl = 3, .require = .Follower },
    .{ .kind = .Noun, .str = "Apprentice", .syl = 3, .require = .Follower },
    .{ .kind = .Noun, .str = "Follower", .syl = 3, .require = .Follower },

    // Soldiers
    .{ .kind = .Noun, .str = "Soldier", .syl = 2, .require = .Soldier },

    // Archangels
    .{ .kind = .Noun, .str = "Warlord", .syl = 2, .require = .Arch },
    .{ .kind = .Noun, .str = "Captain", .syl = 2, .require = .Arch },
    .{ .kind = .Noun, .str = "Overlord", .syl = 3, .require = .Arch },
    .{ .kind = .Noun, .str = "Marshal", .syl = 2, .require = .Arch },
};

const NAME_PATTERNS = [_][2]usize{
    // Molten dread; burning one; shining knight
    .{ 2, 1 },

    // Skewering star
    .{ 3, 1 },

    // Cinder slayer, boiling smiter
    .{ 2, 2 },

    // Dread lancer, shining menace
    .{ 1, 2 },

    .{ 1, 3 },
    .{ 1, 4 },
    .{ 1, 5 },

    // Adamantine one
    .{ 4, 1 },
};

const TRAITS = [_]Trait{
    .{
        .power = 3,
        .name = "Armor",
        .kind = .{ .Resist = .{ .Armor = 50 } },
        .prefer_names = &[4]Trait.Preference{
            .{ .n = "Grim", .w = 10 },
            .{ .n = "Adamantine", .w = 10 },
            .{ .n = "Armored", .w = 20 },
            .{ .n = "Iron", .w = 20 },
        },
    },
    .{
        .power = 2,
        .name = "Resistances",
        .kind = .{ .Resist = .{ .rFire = 75, .rElec = 75, .rAcid = 75 } },
        .prefer_names = &[2]Trait.Preference{
            .{ .n = "Grim", .w = 20 },
            .{ .n = "Adamantine", .w = 20 },
        },
    },
    .{
        .power = 5,
        .name = "Martial",
        .kind = .{ .Stat = .{ .Martial = 2 } },
        //.attached = &Trait{ .kind = .Foo },
        .prefer_names = &[1]Trait.Preference{
            .{ .n = "Blademaster", .w = 20 },
        },
        // TODO: Prefer trait: riposte
    },
    .{
        .power = 5,
        .name = "Speed",
        .kind = .{ .Stat = .{ .Speed = 50 } },
        // TODO: Forbid: Slow
    },
    .{
        .power = 5,
        .name = "Spikes",
        .kind = .{ .Stat = .{ .Spikes = 2 } },
        .prefer_names = &[2]Trait.Preference{
            .{ .n = "Spiked", .w = 20 },
            .{ .n = "Piercer", .w = 20 },
        },
    },
    .{
        .power = 5,
        .name = "Riposte",
        .kind = .{ .Status = &[_]types.StatusDataInfo{.{ .status = .Riposte, .duration = .Prm }} },
        .prefer_names = &[1]Trait.Preference{
            .{ .n = "Blademaster", .w = 20 },
        },
        // TODO: Prefer trait: martial
        // TODO: Forbid: loss of melee/martial
    },
    .{ .power = 3, .name = "Spell: Disintegrate", .kind = .{ .Spell = .{ .MP_cost = 8, .spell = &spells.BOLT_DISINTEGRATE } } },
    .{ .power = 2, .name = "Spell: Divine regeneration", .kind = .{ .Spell = .{ .MP_cost = 5, .power = 3, .spell = &spells.CAST_DIVINE_REGEN } } },
    .{
        .power = 4,
        .name = "Spell: Hellfire",
        .kind = .{ .Spell = .{ .MP_cost = 5, .power = 3, .spell = &spells.BOLT_HELLFIRE } },
        .max_used = 4,
        .original_weight = 3,
        .require_kind = &.{ .Arch, .Soldier },
        .prefer_names = &[_]Trait.Preference{
            .{ .n = "Boiling", .w = 10 },
            .{ .n = "Blazing", .w = 10 },
            .{ .n = "Molten", .w = 10 },
            .{ .n = "Cinder", .w = 10 },
            .{ .n = "Furnace", .w = 10 },
        },
    },
    .{
        .power = 3,
        .name = "Spell: Electric Hellfire",
        .kind = .{ .Spell = .{ .MP_cost = 5, .power = 2, .spell = &spells.BOLT_HELLFIRE_ELECTRIC } },
        .max_used = 2,
        .original_weight = 1,
        .require_kind = &.{ .Arch, .Soldier },
    },
    .{ .power = 2, .name = "Spell: Enrage Angel", .kind = .{ .Spell = .{ .MP_cost = 7, .power = 16, .spell = &spells.CAST_ENRAGE_ANGEL } } },
    .{
        .power = 2,
        .name = "Spell: Crossbow",
        .kind = .{ .Spell = .{ .MP_cost = 3, .spell = &spells.BOLT_BOLT, .power = 1 } },
        .prefer_names = &[1]Trait.Preference{.{ .n = "Arbalist", .w = 20 }},
    },
    .{
        .power = 3,
        .name = "Spell: Disrupting Blast",
        .kind = .{ .Spell = .{ .MP_cost = 4, .spell = &spells.BLAST_DISRUPTING, .power = 8 } },
        .prefer_names = &[7]Trait.Preference{
            .{ .n = "Abjuror", .w = 20 },
            .{ .n = "Tormentor", .w = 20 },
            .{ .n = "Disruptor", .w = 20 },
            .{ .n = "Purger", .w = 20 },
            .{ .n = "Cleanser", .w = 20 },
            .{ .n = "Destroyer", .w = 20 },
            .{ .n = "Silver", .w = 20 },
        },
    },
    .{
        .power = 3,
        .name = "Spell: Rebuke Earth Demon",
        .kind = .{ .Spell = .{ .MP_cost = 3, .spell = &spells.CAST_REBUKE_EARTH_DEMON, .power = 1 } },
        .prefer_names = &[6]Trait.Preference{
            .{ .n = "Abjuror", .w = 20 },
            .{ .n = "Tormentor", .w = 20 },
            .{ .n = "Smiter", .w = 20 },
            .{ .n = "Destroyer", .w = 20 },
            .{ .n = "Terminator", .w = 20 },
            .{ .n = "Banisher", .w = 20 },
        },
        .max_used = 3,
        .require_kind = &.{ .Arch, .Soldier },
    },
    .{ .power = 3, .name = "Spell: Rolling Boulder", .kind = .Foo },
    .{
        .power = 3,
        .name = "Spell: Awaken Stone",
        .kind = .{ .Spell = .{ .MP_cost = 5, .spell = &spells.CAST_AWAKEN_STONE, .power = 3 } },
    },
    .{
        .power = -2,
        .name = "Slow",
        .kind = .{ .Status = &[_]types.StatusDataInfo{.{ .status = .Slow, .duration = .Prm }} },
        .max_used = 2,
        .prefer_names = &[_]Trait.Preference{
            .{ .n = "Grim", .w = 10 },
        },
        // TODO: Prefer: extra armor or HP
        .require_kind = &.{ .Arch, .Soldier },
    },
    .{
        .power = -2,
        .name = "Less Melee/Missile",
        .kind = .{ .Stat = .{ .Melee = -20, .Missile = -20 } },
        .max_used = 2,
        .require_kind = &.{ .Arch, .Soldier },
    },
    .{
        .power = -2,
        .name = "Less Evade",
        .kind = .{ .Stat = .{ .Evade = -10 } },
        .max_used = 2,
        .require_kind = &.{ .Arch, .Soldier },
    },

    // Fluff generic spells, taken from other monsters (and increased in power)
    .{
        .power = 2,
        .name = "Spell: Iron Bolt",
        .kind = .{ .Spell = .{ .MP_cost = 4, .spell = &spells.BOLT_IRON, .power = 3 } },
        .prefer_names = &[_]Trait.Preference{
            .{ .n = "Iron", .w = 20 },
            .{ .n = "Archer", .w = 10 },
        },
    },
    .{ .power = 2, .name = "Spell: Spark", .kind = .{ .Spell = .{ .MP_cost = 4, .spell = &spells.BOLT_LIGHTNING, .power = 3 } } },
    .{
        .power = 4,
        .name = "Spell: Crystal bolt",
        .kind = .{ .Spell = .{ .MP_cost = 6, .spell = &spells.BOLT_CRYSTAL, .power = 3 } },
        .prefer_names = &[_]Trait.Preference{.{ .n = "Archer", .w = 15 }},
        .require_kind = &.{.Arch}, // Thematic reasons. Only archangels are worthy of the Ancient Mage's signature spell!!
    },
    .{
        .power = 4,
        .name = "Spell: Speeding bolt",
        .kind = .{ .Spell = .{ .MP_cost = 5, .spell = &spells.BOLT_SPEEDING } },
        .prefer_names = &[_]Trait.Preference{.{ .n = "Archer", .w = 15 }},
        .require_kind = &.{ .Arch, .Soldier },
    },
    .{ .power = 4, .name = "Spell: Para", .kind = .{ .Spell = .{ .MP_cost = 6, .spell = &spells.BOLT_PARALYSE, .power = 3 } } },
    .{
        .power = 2,
        .name = "Spell: Fiery javelin",
        .kind = .{ .Spell = .{ .MP_cost = 4, .spell = &spells.BOLT_FIERY_JAVELIN, .power = 3 } },
        .prefer_names = &[_]Trait.Preference{
            .{ .n = "Boiling", .w = 20 },
            .{ .n = "Blazing", .w = 20 },
            .{ .n = "Molten", .w = 20 },
            .{ .n = "Cinder", .w = 20 },
            .{ .n = "Furnace", .w = 20 },
        },
    },
    // This one might be problematic... need to check if this causes angels to kill each other.
    .{
        .power = 2,
        .name = "Spell: Fireball",
        .kind = .{ .Spell = .{ .MP_cost = 3, .spell = &spells.BOLT_FIREBALL, .power = 2, .duration = 8 } },
        .prefer_names = &[_]Trait.Preference{
            .{ .n = "Boiling", .w = 20 },
            .{ .n = "Blazing", .w = 20 },
            .{ .n = "Molten", .w = 20 },
            .{ .n = "Cinder", .w = 20 },
            .{ .n = "Furnace", .w = 20 },
        },
    },
};

pub const AngelKind = enum {
    Follower,
    Soldier,
    Arch,

    pub fn power(self: @This()) usize {
        return switch (self) {
            .Follower => 4,
            .Soldier => 7,
            .Arch => 11,
        };
    }

    pub fn maxHP(self: @This()) usize {
        const variation: usize = switch (self) {
            .Follower => 2,
            .Soldier => 5,
            .Arch => 10,
        };
        return 7 + rng.range(usize, variation / 2, variation);
    }

    pub fn stats(self: @This()) types.MobStat {
        return switch (self) {
            .Follower => .{ .Melee = 80, .Missile = 70, .Evade = 10, .Willpower = 10 },
            .Soldier => .{ .Melee = 90, .Missile = 70, .Evade = 20, .Willpower = mobs.WILL_IMMUNE },
            .Arch => .{ .Melee = 100, .Missile = 80, .Evade = 25, .Willpower = mobs.WILL_IMMUNE },
        };
    }
};

// Generates a single angel into a given mob template, and removes its name and
// traits so it can't be used in future generation cycles.
//
// Tiles are not unique and can be reused.
//
fn generateSingle(
    _: *MobTemplate,
    kind: AngelKind,
    traits: *StackBuffer(Trait, TRAITS.len),
    names: *StackBuffer(Name, NAMES.len),
    tiles: *StackBuffer(Char, CHARS.len),
) void {
    for (traits.slice()) |*i| i.weight = i.original_weight;
    for (names.slice()) |*i| i.weight = i.original_weight;
    for (tiles.slice()) |*i| i.weight = i.original_weight;

    for (traits.slice()) |*trait|
        if (trait.require_kind) |requires| {
            const meets_requirement = for (requires) |require| {
                if (require == kind) break true;
            } else false;
            trait.weight = if (meets_requirement) trait.weight + 10 else 0;
        };

    var power = kind.power();
    var chosen_traits = StackBuffer(Trait, 16).init(null);
    var tries: usize = 200;

    while (power > 0 and tries > 0) : (tries -= 1) {
        const chosen_ind = rng.chooseInd2(Trait, traits.constSlice(), "weight");
        const chosen_ptr = &traits.slice()[chosen_ind];
        const chosen = traits.slice()[chosen_ind];

        const new_power = @as(isize, @intCast(power)) - chosen.power;
        if (new_power < 0)
            continue;
        power = @intCast(new_power);

        chosen_traits.append(chosen) catch err.wat();

        chosen_ptr.used_ctr += 1;
        if (chosen_ptr.used_ctr >= chosen.max_used)
            _ = traits.orderedRemove(chosen_ind) catch err.wat()
        else
            chosen_ptr.weight = 0;

        if (chosen.prefer_names) |preferred_names| {
            for (preferred_names) |preference| {
                // std.log.info("* {s} preferring {s}...", .{ chosen.name, preference.n });
                const name_ind = for (names.constSlice(), 0..) |n, i| {
                    if (mem.eql(u8, n.str, preference.n)) break i;
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

    for (names.slice()) |*name|
        if (name.require) |require|
            if (require != kind) {
                name.weight = 0;
            } else {
                name.weight += 40;
            };

    while (adj == null or noun == null) {
        const chosen = rng.choose2(Name, names.constSlice(), "weight") catch err.wat();
        // std.log.info("chose {s}, weight was {}, original weight was {}", .{ chosen.str, chosen.weight, chosen.original_weight });
        switch (chosen.kind) {
            .Noun => {
                if (noun != null)
                    continue;
                if (adj != null and adj.?.forbid != null and mem.eql(u8, adj.?.forbid.?, chosen.str))
                    continue;
                noun = chosen;
            },
            .Adj => {
                if (adj != null)
                    continue;
                if (noun != null and noun.?.forbid != null and mem.eql(u8, noun.?.forbid.?, chosen.str))
                    continue;
                adj = chosen;
            },
        }

        if (adj != null and noun != null) {
            const allowed = for (&NAME_PATTERNS) |pattern| {
                if (pattern[0] == adj.?.syl and pattern[1] == noun.?.syl)
                    break true;
            } else false;

            // Start over
            if (!allowed) {
                noun = null;
                adj = null;
            }
        }
    }

    // Remove names from list
    const adj_ind = for (names.constSlice(), 0..) |name, i| {
        if (mem.eql(u8, name.str, adj.?.str)) break i;
    } else err.wat();
    _ = names.orderedRemove(adj_ind) catch err.wat();

    const noun_ind = for (names.constSlice(), 0..) |name, i| {
        if (mem.eql(u8, name.str, noun.?.str)) break i;
    } else err.wat();
    _ = names.orderedRemove(noun_ind) catch err.wat();

    // Choose remaining stuff
    const chosen_tile_ind = rng.chooseInd2(Char, tiles.constSlice(), "weight");
    const chosen_tile = tiles.orderedRemove(chosen_tile_ind) catch err.wat();
    const maxHP = kind.maxHP();

    // Done, print it
    std.log.info("*** {s}: {s} {s} ({u}) ({} HP)", .{ @tagName(kind), adj.?.str, noun.?.str, chosen_tile.ch, maxHP });
    for (chosen_traits.constSlice()) |chosen_trait|
        std.log.info("  - Trait: {s} ({})", .{ chosen_trait.name, chosen_trait.kind });

    // Now apply to the terrain

    // for (chosen_traits.constSlice()) |trait| {
    //     trait.kind.apply(onto);
    //     if (trait.attached) |attached|
    //         attached.kind.apply(onto);
    // }

    // onto.name = std.fmt.allocPrint(state.alloc, "{s} {s}", .{ adj.?.str, noun.?.string }) catch err.oom();
    // onto.tile = chosen_tile.ch;
}

pub fn init() void {
    var traits = StackBuffer(Trait, TRAITS.len).init(&TRAITS);
    var names = StackBuffer(Name, NAMES.len).init(&NAMES);
    var tiles = StackBuffer(Char, CHARS.len).init(&CHARS);

    // Generation order is deliberate. We want Archangels to have first priority
    // for spells, in particular the ones which "return" power.
    //
    // Followers get leftovers.

    generateSingle(undefined, .Arch, &traits, &names, &tiles);
    generateSingle(undefined, .Arch, &traits, &names, &tiles);
    generateSingle(undefined, .Soldier, &traits, &names, &tiles);
    generateSingle(undefined, .Soldier, &traits, &names, &tiles);
    generateSingle(undefined, .Soldier, &traits, &names, &tiles);
    generateSingle(undefined, .Follower, &traits, &names, &tiles);
    generateSingle(undefined, .Follower, &traits, &names, &tiles);
}

pub fn deinit() void {}
