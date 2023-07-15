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

pub const GENERAL_THREAT_LOOK_CAREFULLY = 80;
pub const GENERAL_THREAT_LOOK_CAREFULLY2 = 160;

pub const Threat = union(enum) { General, Unknown, Specific: *Mob };

pub const ThreatData = struct {
    level: usize = 0, // See comment for ThreatIncrease
    deadly: bool = false,

    // Only used for .Unknown threat.
    is_active: bool = true,
};

// Note, the numbers do NOT indicate the deadliness of the threat -- if it did,
// the numbers would be more like Noise=1, Confrontation=5,
// ArmedConfrontation=10, Dead=10.
//
// Instead, the numbers indicate the likelihood (in the eyes of the Complex)
// that the threat is real and persistent. Thus, death is less than
// confrontation because death could have been anything, confrontation is
// visual confirmation of the existence of the threat.
//
pub const ThreatIncrease = enum(usize) {
    Noise = 10,
    Death = 20,
    Confrontation = 30,
    ArmedConfrontation = 40,

    pub fn isDeadly(self: @This()) bool {
        return switch (self) {
            .Noise, .Confrontation => false,
            else => true,
        };
    }
};

pub var threats: std.AutoHashMap(Threat, ThreatData) = undefined;

pub fn init() void {
    threats = @TypeOf(threats).init(state.GPA.allocator());
}

pub fn deinit() void {
    threats.clearAndFree();
}

pub fn getThreat(threat: Threat) *ThreatData {
    return (threats.getOrPutValue(threat, .{}) catch err.wat()).value_ptr;
}

pub fn reportThreat(by: *Mob, threat: Threat, threattype: ThreatIncrease) void {
    if (by.faction != .Necromancer or
        (threat == .Specific and threat.Specific.faction == .Necromancer)) // Insanity
    {
        return;
    }

    // If a new specific threat is encountered, put the unknown threat to sleep.
    if (threat == .Specific and getThreat(threat).level == 0 and
        getThreat(.Unknown).is_active)
    {
        getThreat(.Unknown).is_active = false;
    } else if (threat == .Unknown) {
        getThreat(.Unknown).is_active = true;
    }

    // Don't report threats if the guy is dead
    if (threat == .Specific and
        threat.Specific.is_dead and threat.Specific.corpse_info.is_noticed)
    {
        dismissThreat(by, threat);
    }

    const info = getThreat(threat);
    info.deadly = info.deadly or threattype.isDeadly();
    info.level += @enumToInt(threattype);

    if (threat != .General)
        reportThreat(by, .General, threattype);
}

// Threat neutralized
pub fn dismissThreat(by: *Mob, threat: Threat) void {
    // Would be interesting mechanic to lower general alert level when threat
    // dies, but would require more bookkeeping since individual threat levels
    // rise each turn
    //
    // Also there would need to be checks in place for when threats are
    // dismissed redundantly
    //
    //threats.put(threat, getThreat(.General).level - getThreat(threat).level);

    assert(threat != .General);
    assert(by.faction == .Necromancer);

    _ = by;
    _ = threats.remove(threat);
}

pub fn tickThreats() void {
    var iter = threats.iterator();
    while (iter.next()) |entry| {
        if (entry.key_ptr.* == .General)
            continue;
        if (entry.key_ptr.* == .Unknown and !entry.value_ptr.is_active)
            continue;

        entry.value_ptr.level += 1;
    }
}
