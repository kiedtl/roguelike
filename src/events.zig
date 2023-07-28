const std = @import("std");
const mem = std.mem;

const err = @import("err.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const mapgen = @import("mapgen.zig");

fn _gimmePrefab(name: []const u8) ?*mapgen.Prefab {
    return mapgen.Prefab.findPrefabByName(name, &mapgen.n_fabs) orelse
        mapgen.Prefab.findPrefabByName(name, &mapgen.s_fabs);
}

pub const Effect = union(enum) {
    SetPrefabGlobalRestriction: struct { prefab: []const u8, val: usize },
    AppendPrefabWhitelist: struct { prefab: []const u8, val: []const u8 },

    pub fn apply(self: @This()) !void {
        switch (self) {
            .SetPrefabGlobalRestriction => |ctx| {
                _gimmePrefab(ctx.prefab).?.global_restriction = ctx.val;
            },
            .AppendPrefabWhitelist => |ctx| {
                const prefab = _gimmePrefab(ctx.prefab).?;

                if (mem.eql(u8, ctx.val, "$SPAWN_LEVEL")) {
                    prefab.whitelist.append(state.PLAYER_STARTING_LEVEL) catch err.wat();
                } else {
                    prefab.whitelist.append(state.findLevelByName(ctx.val).?) catch err.wat();
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
    .{ .p = 75, .v = &EV_DISINT_DISALLOW },
    .{ .p = 75, .v = &EV_SHIELD_DISALLOW },
};

pub var completed_events: Event.AList = undefined;

pub fn init() void {
    completed_events = @TypeOf(completed_events).init(state.GPA.allocator());
}

pub fn deinit() void {
    completed_events.deinit();
}

pub fn eventUsedCount(id: []const u8) usize {
    var i: usize = 0;
    for (completed_events.items) |completed| {
        if (mem.eql(u8, id, completed.id))
            i += 1;
    }
    return i;
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
    for (&EVENTS) |event| {
        if (rng.percent(event.p) and eventCanBeUsed(event.v)) {
            var new_event = event.v.*;
            for (new_event.effect) |effect|
                effect.apply() catch unreachable;
            completed_events.append(new_event) catch err.wat();
        }
    }
}
