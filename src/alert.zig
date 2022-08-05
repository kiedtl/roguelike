const std = @import("std");
const assert = std.debug.assert;

const ai = @import("ai.zig");
const player = @import("player.zig");
const err = @import("err.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");
const rng = @import("rng.zig");

const Mob = types.Mob;
const Room = types.Room;
const Coord = types.Coord;
const Direction = types.Direction;
const DIRECTIONS = types.DIRECTIONS;

const StackBuffer = @import("buffer.zig").StackBuffer;
const StringBuf64 = @import("buffer.zig").StringBuf64;

pub const GUARD_SQUADS = [_][][]const u8{
    &.{ "guard", "watcher", "watcher" },
    &.{ "guard", "shrieker", "watcher" },
    &.{ "guard", "guard", "guard" },
    &.{ "sentinel", "guard", "guard" },
    &.{ "sentinel", "defender", "defender" },
};

pub const DEATH_SQUADS = [_][][]const u8{
    &.{ "sentinel", "executioner" },
    &.{ "sentinel", "destroyer" },
    &.{ "destroyer", "executioner", "executioner" },
    &.{"death_knight"},
    &.{"brimstone_mage"},
    &.{"lightning_mage"},
    &.{ "death_knight", "skeletal_blademaster" },
    &.{"death_mage"},
    &.{"burning_brute"},
    &.{"basalt_fiend"},
    &.{"ancient_mage"},
};

pub const Alert = struct {
    alert: Type,
    filed: usize, // state.ticks
    by: ?*Mob,
    floor: usize,
    resolved: bool,

    pub const List = std.ArrayList(@This());

    pub const Type = union(enum) {
        EnemyAlert: EnemyAlert,
        CheckDeaths: CheckDeathsAlert,
    };

    pub const CheckDeathsAlert = struct {
        locations: StackBuffer(Coord, 64),
    };

    pub const EnemyAlert = struct {
        enemy: *Mob,
    };
};

fn isMobInVault(mob: *Mob) bool {
    return switch (state.layout[mob.coord.z][mob.coord.y][mob.coord.x]) {
        .Unknown => false,
        .Room => |r| state.rooms[mob.coord.z].items[r].is_vault != null,
    };
}

fn isMobNotable(mob: *Mob) bool {
    return !isMobInVault(mob) and
        mob.allegiance == .Necromancer and mob.life_type == .Living;
}

pub fn tickCheckLevelHealth(level: usize) void {
    var mobs_total: usize = 0;
    var mobs_dead: usize = 0;

    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
        if (mob.coord.z == level and isMobNotable(mob)) {
            mobs_total += 1;
            if (mob.is_dead and !mob.is_death_reported) {
                mobs_dead += 1;
            }
        }
    }

    if (mobs_dead >= ((mobs_total / 4) * 3)) {
        var locations = StackBuffer(Coord, 64).init(null);

        iter = state.mobs.iterator();
        while (iter.next()) |mob| {
            if (mob.coord.z == level and isMobNotable(mob)) {
                if (mob.is_dead and !mob.is_death_reported) {
                    mob.is_death_reported = true;
                    locations.append(mob.coord) catch err.wat();
                }
            }
        }

        //_ = @import("display.zig").drawContinuePrompt("ALERT: checking deaths", .{});

        const newalert = Alert{
            .alert = .{ .CheckDeaths = .{ .locations = locations } },
            .filed = state.ticks,
            .by = null,
            .floor = level,
            .resolved = false,
        };
        state.alerts.append(newalert) catch err.wat();
    }
}

pub fn tickActOnAlert(level: usize) void {
    for (state.alerts.items) |*alert| if (alert.floor == level and !alert.resolved) {
        switch (alert.alert) {
            .CheckDeaths => |deaths_alert| {
                const coord = for (state.dungeon.stairs[level].constSlice()) |stair| {
                    if (state.nextSpotForMob(stair, null)) |coord| {
                        break coord;
                    }
                } else null;
                if (coord) |spawn_coord| {
                    const coroner = mobs.placeMob(state.GPA.allocator(), &mobs.CoronerTemplate, spawn_coord, .{});
                    for (deaths_alert.locations.constSlice()) |location| {
                        coroner.ai.work_area.append(location) catch err.wat();
                    }
                    alert.resolved = true;
                }
            },
            .EnemyAlert => |enemy_alert| {
                const coord = for (state.dungeon.stairs[level].constSlice()) |stair| {
                    if (state.nextSpotForMob(stair, null)) |coord| {
                        break coord;
                    }
                } else null;
                if (coord) |spawn_coord| {
                    const knight = mobs.placeMob(state.GPA.allocator(), &mobs.DeathKnightTemplate, spawn_coord, .{});
                    ai.updateEnemyKnowledge(knight, enemy_alert.enemy, null);
                    if (enemy_alert.enemy.squad) |enemy_squad| for (enemy_squad.members.constSlice()) |member| {
                        ai.updateEnemyKnowledge(knight, member, null);
                    };
                    alert.resolved = true;
                }
            },
        }
    };
}

pub fn announceEnemyAlert(enemy: *Mob) void {
    if (!enemy.isAloneOrLeader()) {
        announceEnemyAlert(enemy.squad.?.leader.?);
        return;
    }

    if (enemy.is_dead) {
        return;
    }

    const existing_alert = for (state.alerts.items) |*alert| {
        if (alert.floor == state.player.coord.z and !alert.resolved) {
            if (alert.alert == .EnemyAlert and
                alert.alert.EnemyAlert.enemy == enemy)
            {
                break alert;
            }
        }
    } else null;

    if (existing_alert == null) {
        const newalert = Alert{
            .alert = .{ .EnemyAlert = .{ .enemy = enemy } },
            .filed = state.ticks,
            .by = null,
            .floor = state.player.coord.z,
            .resolved = false,
        };
        state.alerts.append(newalert) catch err.wat();
    }
}
