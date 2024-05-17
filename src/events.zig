const std = @import("std");
const mem = std.mem;

const err = @import("err.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const mapgen = @import("mapgen.zig");

const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;

fn gimmePrefabs(ctx: *GeneratorCtx(*mapgen.Prefab), name: []const u8) void {
    for (mapgen.n_fabs.items) |*f| if (mem.eql(u8, name, f.name.constSlice())) ctx.yield(f);
    for (mapgen.s_fabs.items) |*f| if (mem.eql(u8, name, f.name.constSlice())) ctx.yield(f);
    ctx.finish();
}

pub const Effect = union(enum) {
    SetPrefabGlobalRestriction: struct { prefab: []const u8, val: usize },
    AppendPrefabWhitelist: struct { prefab: []const u8, val: []const u8 },

    pub fn apply(self: @This()) !void {
        switch (self) {
            .SetPrefabGlobalRestriction => |ctx| {
                var gen = Generator(gimmePrefabs).init(ctx.prefab);
                while (gen.next()) |fab| {
                    fab.global_restriction = ctx.val;
                }
            },
            .AppendPrefabWhitelist => |ctx| {
                var gen = Generator(gimmePrefabs).init(ctx.prefab);
                while (gen.next()) |prefab| {
                    const z = if (mem.eql(u8, ctx.val, "$SPAWN_LEVEL"))
                        state.PLAYER_STARTING_LEVEL
                    else
                        state.findLevelByName(ctx.val).?;

                    if (prefab.whitelist.linearSearch(z) == null)
                        prefab.whitelist.append(z) catch err.wat();
                }
            },
        }
    }
};

pub const Event = struct {
    id: []const u8,
    checked_when: enum { MapgenBeginning },
    global_maximum: usize = 1,
    global_incompats: []const []const u8 = &[_][]const u8{},
    effect: []const Effect,

    pub const AList = std.ArrayList(@This());
};

pub const EV_SYMBOL_DISALLOW = Event{
    .id = "ev_symbol_disallow",
    .checked_when = .MapgenBeginning,
    .global_incompats = &[_][]const u8{"ev_symbol_restrict_to_upper_shrine"},
    .effect = &[_]Effect{.{ .SetPrefabGlobalRestriction = .{ .prefab = "SIN_symbol", .val = 0 } }},
};

pub const EV_SYMBOL_RESTRICT_TO_UPPER_SHRINE = Event{
    .id = "ev_symbol_restrict_to_upper_shrine",
    .checked_when = .MapgenBeginning,
    .global_incompats = &[_][]const u8{"ev_symbol_disallow"},
    .effect = &[_]Effect{.{ .AppendPrefabWhitelist = .{ .prefab = "SIN_symbol", .val = "6/Shrine" } }},
};

pub const EV_DISINT_DISALLOW = Event{
    .id = "ev_disint_disallow",
    .checked_when = .MapgenBeginning,
    .effect = &[_]Effect{.{ .SetPrefabGlobalRestriction = .{ .prefab = "WRK_disintegration", .val = 0 } }},
};

pub const EV_SHIELD_DISALLOW = Event{
    .id = "ev_shield_disallow",
    .checked_when = .MapgenBeginning,
    .effect = &[_]Effect{.{ .SetPrefabGlobalRestriction = .{ .prefab = "LAB_shield", .val = 0 } }},
};

pub const EVENTS = [_]struct { p: usize, v: *const Event }{
    .{ .p = 30, .v = &EV_SYMBOL_DISALLOW },
    .{ .p = 30, .v = &EV_SYMBOL_RESTRICT_TO_UPPER_SHRINE },
    .{ .p = 45, .v = &EV_DISINT_DISALLOW },
    .{ .p = 45, .v = &EV_SHIELD_DISALLOW },
};

pub fn init() void {
    // Nothing
}

pub fn deinit() void {
    // Nothing
}

pub fn eventUsedCount(id: []const u8) usize {
    const ind = for (EVENTS) |ev, i| {
        if (mem.eql(u8, ev.v.id, id)) break i;
    } else err.wat();
    return state.completed_events[ind];
}

pub fn eventCanBeUsed(event: *const Event) bool {
    for (event.global_incompats) |incompat|
        if (eventUsedCount(incompat) > 0)
            return false;
    if (eventUsedCount(event.id) >= event.global_maximum)
        return false;
    return true;
}

// Choose and execute events right before map generation. Usually involves
// modifying prefab metadata and such.
//
// XXX: Need to add checks for restrictions etc when that's added
//
pub fn executeGlobalEvents() void {
    for (&EVENTS) |event, i| {
        if (rng.percent(event.p) and eventCanBeUsed(event.v)) {
            var new_event = event.v.*;
            for (new_event.effect) |effect|
                effect.apply() catch unreachable;
            state.completed_events[i] += 1;
        }
    }
}
