// NOTE: this doesn't store threat data per floor; it just resets threat data
// everytime the player ascends.
//
const std = @import("std");
const assert = std.debug.assert;

const ai = @import("ai.zig");
const player = @import("player.zig");
const err = @import("err.zig");
const mapgen = @import("mapgen.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const tasks = @import("tasks.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");
const rng = @import("rng.zig");

const Mob = types.Mob;
const Room = mapgen.Room;
const Coord = types.Coord;
const Direction = types.Direction;
const DIRECTIONS = types.DIRECTIONS;

const StackBuffer = @import("buffer.zig").StackBuffer;
const StringBuf64 = @import("buffer.zig").StringBuf64;

pub const GENERAL_THREAT_DEPLOY_CORRIDOR_PATROLS_1 = 10;
pub const GENERAL_THREAT_CLOSE_SHRINES = 80;
pub const GENERAL_THREAT_DEPLOY_PATROLS = 80;
pub const GENERAL_THREAT_LOOK_CAREFULLY = 100;
pub const GENERAL_THREAT_DEPLOY_CORRIDOR_PATROLS_2 = 40;
pub const GENERAL_THREAT_LOOK_CAREFULLY2 = 160;
pub const UNKNOWN_THREAT_DEPLOY_WATCHERS_1 = 100;
pub const UNKNOWN_THREAT_DEPLOY_SPIRES = 100;
pub const UNKNOWN_THREAT_IS_PERSISTENT = 200;
pub const UNKNOWN_THREAT_DEPLOY_WATCHERS_2 = 300;
pub const UNKNOWN_THREAT_DEPLOY_WATCHERS_3 = 500;
pub const UNKNOWN_THREAT_DEPLOY_WATCHERS_4 = 700;

pub const TURNS_BETWEEN_ASSAULT = 40;

pub const Threat = union(enum) { General, Unknown, Specific: *Mob };

pub const ThreatData = struct {
    level: usize = 0, // See comment for ThreatIncrease
    deadly: bool = false,

    // Only used for .Unknown threat.
    is_active: bool = true,

    // Only used for .Unknown and .Specific.
    last_incident: usize = 0,

    // Only used for .Specific.
    last_known_coord: ?Coord = null,
};

// Note, the numbers do NOT indicate the deadliness of the threat -- if it did,
// the numbers would be more like Noise=1, Confrontation=5,
// ArmedConfrontation=10, Dead=10.
//
// Instead, the numbers indicate the likelihood (in the eyes of the Dungeon)
// that the threat is real and persistent. Thus, death is less than
// confrontation because death could have been anything, confrontation is
// visual confirmation of the existence of the threat.
//
pub const ThreatIncrease = enum(usize) {
    Noise = 10,
    Death = 12,
    Confrontation = 15,
    Alarm = 16,
    ArmedConfrontation = 20,

    pub fn isDeadly(self: @This()) bool {
        return switch (self) {
            .Noise, .Confrontation, .Alarm => false,
            .Death, .ArmedConfrontation => true,
        };
    }
};

pub const ThreatResponseType = union(enum) {
    ReinforceAgainstEnemy: struct {
        reinforcement: union(enum) {
            Class: []const u8,
            Specific: *const mobs.MobTemplate,
        },
        threat: Threat,
    },
    ReinforceRoom: struct {
        reinforcement: union(enum) {
            Class: []const u8,
            Specific: *const mobs.MobTemplate,
        },
        room: usize,
        coord: ?Coord = null,
        coord2: ?Coord = null,
    },
    Assault: struct {
        waves: usize,
        _ctr: usize = 0,
        _last_time: usize = 0,
        target: *Mob,
    },
};

pub const ThreatResponse = struct {
    type: ThreatResponseType,

    pub const AList = std.ArrayList(@This());
};

pub fn init() void {
    state.threats = @TypeOf(state.threats).init(state.alloc);
    state.responses = @TypeOf(state.responses).init(state.alloc);
}

pub fn deinit() void {
    state.threats.clearAndFree();
    state.responses.deinit();
}

pub fn getThreat(threat: Threat) *ThreatData {
    return (state.threats.getOrPutValue(threat, .{}) catch err.wat()).value_ptr;
}

pub fn reportThreat(by: ?*Mob, threat: Threat, threattype: ThreatIncrease) void {
    const z = if (by) |b| b.coord.z else state.player.coord.z;

    if (z != state.current_level or (by != null and by.?.faction != .Necromancer) or
        (threat == .Specific and threat.Specific.faction == .Necromancer)) // Insanity
    {
        return;
    }

    // if (by) |_by|
    //     std.log.info("{}: threat: <- {cf} ({}, t: {})", .{ z, _by, threat, threattype })
    // else
    //     std.log.info("{}: threat: <- anon ({}, t: {})", .{ z, threat, threattype });

    // If a new specific threat is encountered and an unknown threat existed,
    // deactivate the unknown threat (assume the specific threat to be the unknown
    // one)
    if (threat == .Specific and getThreat(threat).level == 0 and
        getThreat(.Unknown).is_active)
    {
        getThreat(.Unknown).is_active = false;
    } else if (threat == .Unknown) {
        getThreat(.Unknown).is_active = true;
    }

    // If threat is dead and threat's corpse has been noticed, dismiss the threat.
    if (threat == .Specific and
        threat.Specific.is_dead and threat.Specific.corpse_info.is_noticed)
    {
        dismissThreat(by, threat);
        return;
    }

    // state.message(.Info, "Report by {f} on threat {}: {}", .{ by, threat, threattype });

    const info = getThreat(threat);

    onThreatIncrease(z, threat, info.level, info.level + @intFromEnum(threattype));

    // std.log.info("*** Increasing level for {} by {}", .{ threat, @intFromEnum(threattype) });

    info.deadly = info.deadly or threattype.isDeadly();
    info.level += @intFromEnum(threattype);
    info.last_incident = state.ticks;
    info.last_known_coord = if (threat == .Specific) threat.Specific.coord else null;

    if (threat != .General)
        reportThreat(by, .General, threattype);
}

// Threat neutralized
pub fn dismissThreat(by: ?*Mob, threat: Threat) void {
    // Would be interesting mechanic to lower general alert level when threat
    // dies, but would require more bookkeeping since individual threat levels
    // rise each turn
    //
    // Also there would need to be checks in place for when threats are
    // dismissed redundantly
    //
    //state.threats.put(threat, getThreat(.General).level - getThreat(threat).level);

    assert(threat != .General);
    assert(by == null or by.?.faction == .Necromancer);

    _ = state.threats.remove(threat);
}

pub fn queueThreatResponse(response: ThreatResponseType) void {
    state.responses.append(.{ .type = response }) catch err.wat();
}

// Also used by events, esp the one which sends hunters
pub fn spawnAssault(level: usize, target: *Mob, spawn_class: []const u8) !void {
    const squad_template = mobs.spawns.chooseMob(.Special, level, spawn_class) catch err.wat();
    const hunter = try mobs.placeMobNearStairs(&mobs.HunterTemplate, level, .{});
    const squad_coord = state.nextSpotForMob(hunter.coord, null) orelse {
        hunter.deinitEntirelyNoCorpse();
        return error.NoSpace;
    };
    const squadl = mobs.placeMob(state.alloc, squad_template, squad_coord, .{});
    if (squadl.squad) |squad| {
        squad.mergeInto(hunter.squad.?);
    } else {
        hunter.addUnderling(squadl);
    }
    ai.updateEnemyKnowledge(hunter, target, null);
    for (hunter.squad.?.members.constSlice()) |dude|
        dude.newJob(.WRK_LeaveFloor);
}

fn executeResponse(response: ThreatResponse, level: usize) !void {
    switch (response.type) {
        .ReinforceAgainstEnemy => |r| {
            const mob_template = switch (r.reinforcement) {
                .Specific => |m| m,
                .Class => |c| mobs.spawns.chooseMob(.Special, level, c) catch err.wat(),
            };

            const coord = getThreat(r.threat).last_known_coord orelse
                // A bit unrealistic that enemies could possibly home in
                // on exact player's position, but whatever
                r.threat.Specific.coord;

            const opts: mobs.PlaceMobOptions = .{
                .phase = .Investigate,
                .work_area = coord,
            };

            if (opts.work_area == null)
                return; // uhg

            // Sending an engineer into a firefight to help against enemies
            // is stupid
            assert(!mob_template.mob.immobile);

            const mob = try mobs.placeMobNearStairs(mob_template, level, opts);
            mob.sustiles.append(.{
                .coord = coord,
                .unforgettable = true,
            }) catch err.wat();
        },
        .ReinforceRoom => |r| {
            const mob_template = switch (r.reinforcement) {
                .Specific => |m| m,
                .Class => |c| mobs.spawns.chooseMob(.Special, level, c) catch err.wat(),
            };

            var opts: mobs.PlaceMobOptions = .{};
            if (r.coord) |coord| {
                opts.work_area = coord;
            } else {
                const room = state.rooms[level].items[r.room];
                var tries: usize = 100;
                while (tries > 0) : (tries -= 1) {
                    const post_coord = room.rect.randomCoord();
                    if (state.is_walkable(post_coord, .{})) {
                        opts.work_area = post_coord;
                        break;
                    }
                }
            }

            if (opts.work_area == null)
                return; // uhg

            if (mob_template.mob.immobile) {
                tasks.reportTask(level, .{ .BuildMob = .{ .mob = mob_template, .coord = opts.work_area.?, .opts = opts } });
            } else {
                _ = try mobs.placeMobNearStairs(mob_template, level, opts);
            }
        },
        .Assault => |a| {
            const send_wave = state.ticks > a._last_time + TURNS_BETWEEN_ASSAULT;
            if (send_wave) {
                try spawnAssault(level, a.target, "a");
            }
            if (a._ctr < a.waves) {
                var new = response;
                if (send_wave) {
                    new.type.Assault._ctr += 1;
                    new.type.Assault._last_time = state.ticks;
                }
                state.responses.append(new) catch err.wat();
            }
        },
    }
}

pub fn tickThreats(level: usize) void {
    // Unsure if modifying container while iterator() is active is safe to do
    var dismiss_threats = StackBuffer(Threat, 64).init(null);

    var iter = state.threats.iterator();
    while (iter.next()) |entry| {
        if (entry.key_ptr.* == .General)
            continue;
        if (entry.key_ptr.* == .Unknown and !entry.value_ptr.is_active)
            continue;

        if (entry.key_ptr.* == .Unknown and
            (state.ticks - entry.value_ptr.last_incident) > 30 and
            entry.value_ptr.level < UNKNOWN_THREAT_IS_PERSISTENT)
        {
            entry.value_ptr.is_active = false;
            continue;
        }

        if (entry.key_ptr.* == .Specific and
            entry.key_ptr.*.Specific.is_dead and
            entry.key_ptr.*.Specific.corpse_info.is_noticed)
        {
            dismiss_threats.append(entry.key_ptr.*) catch {};
            continue;
        }

        // std.log.info("{}: {}: Increasing threat level for {} ({}).", .{
        //     state.ticks, state.player_turns, entry.key_ptr.*, entry.value_ptr.*,
        // });

        onThreatIncrease(level, entry.key_ptr.*, entry.value_ptr.level, entry.value_ptr.level + 1);
        entry.value_ptr.level += 1;
    }

    for (dismiss_threats.constSlice()) |threat|
        dismissThreat(null, threat);

    if (state.responses.items.len > 0) {
        const index = state.responses.items.len - 1;
        const response = state.responses.items[index];
        if (executeResponse(response, level)) |_| {
            // Use index instead of pop(), as sometimes executeResponse will add
            // a new (modified) response to the queue (e.g. Assault)
            _ = state.responses.orderedRemove(index);
        } else |_| {
            // No space near stairs. Add the response back, wait until next
            // time, hopefully the traffic dissipates.
            //
            // FIXME: why are we adding it back, when we never removed it
            // in the first place??
            state.responses.append(response) catch err.wat();
        }
    }
}

fn onThreatIncrease(level: usize, threat: Threat, old: usize, new: usize) void {
    assert(old != new);

    switch (threat) {
        .General => {
            if (_didIncreasePast(GENERAL_THREAT_CLOSE_SHRINES, old, new)) {
                if (state.shrine_locations[level]) |shrine_coord| {
                    const shrine = state.dungeon.machineAt(shrine_coord).?;
                    if (shrine.canBeInteracted(state.player, &shrine.player_interact.?)) {
                        state.message(.Drain, "You sense the Power here removing its link to the floor.", .{});
                        state.shrines_in_lockdown[level] = true;
                    }
                }
            }

            if (_didIncreasePast(GENERAL_THREAT_DEPLOY_PATROLS, old, new)) {
                _reinforceRooms(level, &mobs.PatrolTemplate, 1);
            }

            if (_didIncreasePast(GENERAL_THREAT_DEPLOY_CORRIDOR_PATROLS_1, old, new) or
                _didIncreasePast(GENERAL_THREAT_DEPLOY_CORRIDOR_PATROLS_2, old, new))
            {
                // Duplicated code here and in _reinforceRooms()
                var tries: usize = 1000;
                while (tries > 0) : (tries -= 1) {
                    const room = rng.choose2(Room, state.rooms[level].items, "importance") catch err.wat();
                    const rect = room.rect;
                    if (room.type != .Corridor or rect.width == 1 or rect.height == 1)
                        continue;
                    const room_id = utils.getRoomFromCoord(level, rect.start).?;
                    queueThreatResponse(.{
                        .ReinforceRoom = .{
                            .reinforcement = .{ .Class = "p" },
                            .room = room_id,
                            .coord = rect.start,
                            .coord2 = rect.end(),
                        },
                    });
                    break;
                }
            }
        },
        .Unknown => {
            if (!getThreat(.Unknown).deadly and
                (_didIncreasePast(UNKNOWN_THREAT_DEPLOY_WATCHERS_1, old, new) or
                    _didIncreasePast(UNKNOWN_THREAT_DEPLOY_WATCHERS_2, old, new) or
                    _didIncreasePast(UNKNOWN_THREAT_DEPLOY_WATCHERS_3, old, new) or
                    _didIncreasePast(UNKNOWN_THREAT_DEPLOY_WATCHERS_4, old, new)))
            {
                _reinforceRooms(level, &mobs.WatcherTemplate, 2);
            }

            if (getThreat(.Unknown).deadly and
                _didIncreasePast(UNKNOWN_THREAT_DEPLOY_SPIRES, old, new))
            {
                const reinforcement = rng.chooseUnweighted(*const mobs.MobTemplate, &[_]*const mobs.MobTemplate{
                    &mobs.IronSpireTemplate, &mobs.LightningSpireTemplate,
                });
                _reinforceRooms(level, reinforcement, rng.range(usize, 3, 5));
            }
        },
        .Specific => |_| {},
    }
}

inline fn _didIncreasePast(num: usize, old: usize, new: usize) bool {
    return old <= num and new > num;
}

fn _reinforceRooms(level: usize, reinforcement: *const mobs.MobTemplate, times: usize) void {
    // TODO: check that we don't deploy to the same room twice
    var count: usize = times;
    while (count > 0) : (count -= 1) {
        const room = rng.choose2(Room, state.rooms[level].items, "importance") catch err.wat();
        const room_id = utils.getRoomFromCoord(level, room.rect.start).?;
        queueThreatResponse(.{
            .ReinforceRoom = .{ .reinforcement = .{ .Specific = reinforcement }, .room = room_id },
        });
    }
}
