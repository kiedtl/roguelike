const std = @import("std");
const mem = std.mem;

const err = @import("err.zig");
const mapgen = @import("mapgen.zig");
const mobs = @import("mobs.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const types = @import("types.zig");

const MobTemplate = mobs.MobTemplate;
const AIJob = types.AIJob;

// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;

const GimmePrefabIter = struct {
    name: []const u8,
    i: usize = 0,
    s_fabs: bool = true,

    pub fn next(self: *@This()) ?*mapgen.Prefab {
        if (self.s_fabs) {
            while (self.i < mapgen.s_fabs.items.len) {
                const i = self.i;
                self.i += 1;
                if (mem.eql(u8, self.name, mapgen.s_fabs.items[i].name.constSlice()))
                    return &mapgen.s_fabs.items[i];
            }
            self.i = 0;
            self.s_fabs = false;
            return self.next();
        } else {
            while (self.i < mapgen.n_fabs.items.len) {
                const i = self.i;
                self.i += 1;
                if (mem.eql(u8, self.name, mapgen.n_fabs.items[i].name.constSlice()))
                    return &mapgen.n_fabs.items[i];
            }
            return null;
        }
    }
};

fn gimmePrefabs(name: []const u8) GimmePrefabIter {
    return .{ .name = name };
}

// fn gimmePrefabs(ctx: *GeneratorCtx(*mapgen.Prefab), name: []const u8) void {
//     for (mapgen.n_fabs.items) |*f| if (mem.eql(u8, name, f.name.constSlice())) ctx.yield(f);
//     for (mapgen.s_fabs.items) |*f| if (mem.eql(u8, name, f.name.constSlice())) ctx.yield(f);
//     ctx.finish();
// }

pub const Trigger = enum {
    InitGameState, // main.zig, initGameState()
    EnteringNewLevel, // Player has just entered a new level. player.zig, triggerStair()
};

pub const Effect = union(enum) {
    SetPrefabGlobalRestriction: struct { prefab: []const u8, val: usize },
    AppendPrefabWhitelist: struct { prefab: []const u8, val: []const u8 },
    Custom: *const fn (*const Event) void,

    pub fn apply(self: @This(), ev: *const Event) !void {
        switch (self) {
            .SetPrefabGlobalRestriction => |ctx| {
                var gen = gimmePrefabs(ctx.prefab);
                while (gen.next()) |fab| {
                    fab.global_restriction = ctx.val;
                }
            },
            .AppendPrefabWhitelist => |ctx| {
                var gen = gimmePrefabs(ctx.prefab);
                while (gen.next()) |prefab| {
                    const z = if (mem.eql(u8, ctx.val, "$SPAWN_LEVEL"))
                        state.PLAYER_STARTING_LEVEL
                    else
                        state.findLevelByName(ctx.val).?;

                    if (prefab.whitelist.linearSearch(z) == null)
                        prefab.whitelist.append(z) catch err.wat();
                }
            },
            .Custom => |func| (func)(ev),
        }
    }
};

pub const Event = struct {
    id: []const u8,
    triggers: []const Trigger,
    conditions: []const *const fn (level: usize) bool = &[0]*const fn (usize) bool{},
    global_maximum: usize = 1,
    global_incompats: []const []const u8 = &[_][]const u8{},
    effect: []const Effect,

    pub const AList = std.ArrayList(@This());
};

pub const EV_SYMBOL_DISALLOW = Event{
    .id = "ev_symbol_disallow",
    .triggers = &.{.InitGameState},
    .global_incompats = &[_][]const u8{"ev_symbol_restrict_to_upper_shrine"},
    .effect = &[_]Effect{.{ .SetPrefabGlobalRestriction = .{ .prefab = "SIN_symbol", .val = 0 } }},
};

pub const EV_SYMBOL_RESTRICT_TO_UPPER_SHRINE = Event{
    .id = "ev_symbol_restrict_to_upper_shrine",
    .triggers = &.{.InitGameState},
    .global_incompats = &[_][]const u8{"ev_symbol_disallow"},
    .effect = &[_]Effect{.{ .AppendPrefabWhitelist = .{ .prefab = "SIN_symbol", .val = "6/Shrine" } }},
};

pub const EV_DISINT_DISALLOW = Event{
    .id = "ev_disint_disallow",
    .triggers = &.{.InitGameState},
    .effect = &[_]Effect{.{ .SetPrefabGlobalRestriction = .{ .prefab = "WRK_disintegration", .val = 0 } }},
};

pub const EV_SHIELD_DISALLOW = Event{
    .id = "ev_shield_disallow",
    .triggers = &.{.InitGameState},
    .effect = &[_]Effect{.{ .SetPrefabGlobalRestriction = .{ .prefab = "LAB_shield", .val = 0 } }},
};

pub const EV_PUNISH_EVIL_PLAYER = Event{
    .id = "ev_punish_evil_player",
    .triggers = &.{.EnteringNewLevel},
    .global_maximum = 3,
    .conditions = &.{
        struct {
            pub fn f(_: usize) bool {
                return state.player.hasStatus(.Sceptre);
            }
        }.f,
    },
    .effect = &[_]Effect{.{ .Custom = struct {
        pub fn f(_: *const Event) void {
            const dialog = "Good morning.";

            const spot = state.nextSpotForMob(state.player.coord, null) orelse return;
            const angel_template = rng.chooseUnweighted(*const MobTemplate, &mobs.ANGELS);
            const angel = mobs.placeMob(state.alloc, angel_template, spot, .{ .job = .SPC_TellPlayer });
            angel.newestJob().?.ctx.set(void, AIJob.CTX_OVERRIDE_FIGHT, {});
            angel.newestJob().?.ctx.set([]const u8, AIJob.CTX_DIALOG, dialog);
        }
    }.f }},
};

pub const EVENTS = [_]struct { p: usize, v: *const Event }{
    .{ .p = 30, .v = &EV_SYMBOL_DISALLOW },
    .{ .p = 30, .v = &EV_SYMBOL_RESTRICT_TO_UPPER_SHRINE },
    .{ .p = 45, .v = &EV_DISINT_DISALLOW },
    .{ .p = 45, .v = &EV_SHIELD_DISALLOW },
    .{ .p = 5, .v = &EV_PUNISH_EVIL_PLAYER },
};

pub fn init() void {
    // Nothing
}

pub fn deinit() void {
    // Nothing
}

pub fn eventUsedCount(id: []const u8) usize {
    const ind = for (EVENTS, 0..) |ev, i| {
        if (mem.eql(u8, ev.v.id, id)) break i;
    } else err.wat();
    return state.completed_events[ind];
}

// NOTE: level = 0 for, say, .InitGameState triggers.
//
pub fn eventCanBeUsed(event: *const Event, level: usize, trigger: Trigger) bool {
    // Check trigger
    for (event.triggers) |t| {
        if (t == trigger) break;
    } else return false;

    for (event.conditions) |func| {
        if (!(func)(level))
            return false;
    }

    // Check use restriction count
    if (eventUsedCount(event.id) >= event.global_maximum)
        return false;

    // Check incompatibilities
    for (event.global_incompats) |incompat|
        if (eventUsedCount(incompat) > 0)
            return false;
    return true;
}

pub fn check(level: usize, trigger: Trigger) void {
    for (&EVENTS, 0..) |event, i| {
        if (eventCanBeUsed(event.v, level, trigger) and rng.percent(event.p)) {
            const new_event = event.v.*;
            for (new_event.effect) |effect|
                effect.apply(&new_event) catch unreachable;
            state.completed_events[i] += 1;
        }
    }
}
