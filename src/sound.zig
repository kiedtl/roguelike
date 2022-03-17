const state = @import("state.zig");
const types = @import("types.zig");

const Mob = types.Mob;
const Machine = types.Machine;
const Coord = types.Coord;

pub const SoundIntensity = enum {
    Silent,
    Quiet,
    Medium,
    Loud,
    Louder,
    Loudest,

    pub fn radiusHeard(self: SoundIntensity) usize {
        return switch (self) {
            .Silent => 0,
            .Quiet => 5,
            .Medium => 10,
            .Loud => 14,
            .Louder => 18,
            .Loudest => 20,
        };
    }
};

pub const SoundType = enum { None, Movement, Combat, Shout, Alarm, Scream, Explosion, Crash };

// .New: sound has just been made
// .Old: it was made a few turns ago, but mobs will still show up to investigate
// .Dead: the sound is dead
pub const SoundState = enum {
    New,
    Old,
    Dead,

    pub fn ageToState(age: usize) SoundState {
        return if (age <= 3) @as(SoundState, .New) else if (age <= 6) @as(SoundState, .Old) else @as(SoundState, .Dead);
    }
};

pub const Sound = struct {
    mob_source: ?*Mob = null,
    machine_source: ?*Machine = null,
    intensity: SoundIntensity = .Silent,
    type: SoundType = .None,
    state: SoundState = .Dead,
    when: usize = 0,
};

pub fn makeNoise(coord: Coord, s_type: SoundType, intensity: SoundIntensity) void {
    state.dungeon.soundAt(coord).* = .{
        .intensity = intensity,
        .type = s_type,
        .state = .New,
        .when = state.ticks,
    };
}
