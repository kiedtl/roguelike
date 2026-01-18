const state = @import("state.zig");
const types = @import("types.zig");

const Mob = types.Mob;
const Machine = types.Machine;
const Coord = types.Coord;

pub const SoundIntensity = enum(u8) {
    Silent,
    Quiet,
    Medium,
    Loud,
    Louder,
    Loudest,

    pub fn string(self: SoundIntensity) []const u8 {
        return switch (self) {
            .Silent => "silent",
            .Quiet => "quiet",
            .Medium => "medium",
            .Loud => "loud",
            .Louder => "louder",
            .Loudest => "loudest",
        };
    }

    pub fn radiusHeard(self: SoundIntensity) usize {
        return switch (self) {
            .Silent => 0,
            .Quiet => 2,
            .Medium => 4,
            .Loud => 8,
            .Louder => 16,
            .Loudest => 24,
        };
    }
};

pub const SoundType = enum(u8) { None, Movement, Combat, Shout, Alarm, Scream, Explosion, Crash };

// .New: sound has just been made
// .Old: it was made a few turns ago, but mobs will still show up to investigate
// .Dead: the sound is dead
pub const SoundState = enum(u8) {
    New,
    Old,
    Dead,

    pub fn ageToState(age: usize) SoundState {
        return if (age <= 1) @as(SoundState, .New) else if (age <= 3) @as(SoundState, .Old) else @as(SoundState, .Dead);
    }
};

pub const Sound = struct {
    mob_source: ?*Mob = null,
    machine_source: ?*Machine = null,
    intensity: SoundIntensity = .Silent,
    type: SoundType = .None,
    state: SoundState = .Dead,
    when: usize = 0,

    pub fn eq(a: Sound, b: Sound) bool {
        return a.mob_source == b.mob_source and
            a.machine_source == b.machine_source and
            a.intensity == b.intensity and
            a.type == b.type and
            a.state == b.state and
            a.when == b.when;
    }
};

pub fn makeNoise(coord: Coord, s_type: SoundType, intensity: SoundIntensity) void {
    if (state.dungeon.soundAt(coord).intensity.radiusHeard() > intensity.radiusHeard())
        return;

    state.dungeon.soundAt(coord).* = .{
        .intensity = intensity,
        .type = s_type,
        .state = .New,
        .when = state.ticks,
    };

    announceSound(coord);
}

pub fn announceSound(coord: Coord) void {
    const sound = state.dungeon.soundAt(coord);

    if (state.player.canHear(coord) == null)
        return;

    if (sound.mob_source == null or !state.player.cansee(coord)) {
        const text: ?[]const u8 = switch (sound.type) {
            .None => unreachable,
            .Movement => null,
            .Combat => "fighting.",
            .Shout => "a shout!",
            .Alarm => "an alarm!",
            .Scream => "a scream!",
            .Explosion => "an explosion!",
            .Crash => "a crash!",
        };

        if (text) |_text| {
            state.message(.Info, "You hear {s}", .{_text});
            state.markMessageNoisy();
        }
    } else {
        const text: ?[]const u8 = switch (sound.type) {
            .None => unreachable,
            .Explosion, .Crash, .Movement, .Combat, .Alarm => null,
            .Shout => if (sound.mob_source.? == state.player) "shout!" else "shouts!",
            .Scream => if (sound.mob_source.? == state.player) "scream!" else "screams!",
        };

        if (text) |_text| {
            state.message(.Info, "{f} {s}", .{ sound.mob_source.?.fmt().caps(), _text });
            state.markMessageNoisy();
        }
    }
}
