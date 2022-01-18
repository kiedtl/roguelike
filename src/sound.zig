usingnamespace @import("types.zig");

pub const SoundIntensity = enum {
    Silent,
    Quiet,
    Medium,
    Loud,
    Louder,
    Loudest,
    Deafening,

    pub fn radiusHeard(self: SoundIntensity) usize {
        return switch (self) {
            .Silent => 0,
            .Quiet => 5,
            .Medium => 10,
            .Loud => 15,
            .Louder => 20,
            .Loudest => 25,
            .Deafening => 35,
        };
    }
};

pub const SoundType = enum {
    None, Movement, Combat, Shout, Alarm, Scream, Explosion
};

// .New: sound has just been made
// .Old: it was made a few turns ago, but mobs will still show up to investigate
// .Dead: the sound is dead
pub const SoundState = enum {
    New,
    Old,
    Dead,

    pub fn ageToState(age: usize) SoundState {
        return if (age <= 2) @as(SoundState, .New) else if (age <= 4) @as(SoundState, .Old) else @as(SoundState, .Dead);
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
