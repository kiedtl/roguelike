// Spells are, basically, and ranged attack that doesn't come from a launcher.
//
// They can be fired by machines as well as monsters; when fired by monsters,
// they could be "natural" abilities (e.g., a drake's breath).
//
usingnamespace @import("types.zig");
const err = @import("err.zig");
const sound = @import("sound.zig");
const state = @import("state.zig");
const rng = @import("rng.zig");

pub const BOLT_LIGHTNING = Spell{ .name = "bolt of electricity", .cast_type = .Bolt, .noise = .Medium, .effect_type = .{ .Custom = _effectBoltLightning } };
fn _effectBoltLightning(spell: Spell, opts: SpellOptions, coord: Coord) void {
    if (state.dungeon.at(coord).mob) |victim| {
        const avg_dmg = opts.bolt_power;
        const dmg = rng.rangeClumping(usize, avg_dmg / 2, avg_dmg * 2, 2);
        victim.takeDamage(.{
            .amount = @intToFloat(f64, dmg),
            .source = .RangedAttack,
            .kind = .Electric,
            .blood = false,
        });
    }
}

pub const CAST_FREEZE = Spell{ .name = "freeze", .cast_type = .Cast, .effect_type = .{ .Status = .Paralysis } };
pub const CAST_FAMOUS = Spell{ .name = "famous", .cast_type = .Cast, .effect_type = .{ .Status = .Corona } };
pub const CAST_FERMENT = Spell{ .name = "ferment", .cast_type = .Cast, .effect_type = .{ .Status = .Confusion } };
pub const CAST_FEAR = Spell{ .name = "fear", .cast_type = .Cast, .effect_type = .{ .Status = .Fear } };
pub const CAST_PAIN = Spell{ .name = "pain", .cast_type = .Cast, .effect_type = .{ .Status = .Pain } };

fn willSucceedAgainstMob(caster: *const Mob, target: *const Mob) bool {
    if (rng.onein(10)) return false;
    return (rng.rangeClumping(usize, 1, 100, 2) * caster.willpower) >
        (rng.rangeClumping(usize, 1, 100, 2) * target.willpower);
}

pub const SpellOptions = struct {
    caster_name: ?[]const u8 = null,
    bolt_power: usize = 0,
    status_duration: usize = Status.MAX_DURATION,
    status_power: usize = 0,
};

pub const SpellInfo = struct {
    spell: *const Spell,
    duration: usize = Status.MAX_DURATION,
    power: usize = 0,
};

pub const Spell = struct {
    name: []const u8,

    cast_type: union(enum) {
        Ray,

        // Single-target, requires line-of-fire. Cannot be dodged.
        Bolt,

        // Doesn't require line-of-fire. Checks willpower.
        Cast,
    },

    noise: sound.SoundIntensity = .Silent,

    effect_type: union(enum) {
        Status: Status,
        Custom: fn (spell: Spell, opts: SpellOptions, coord: Coord) void,
    },

    pub fn use(
        self: Spell,
        caster: ?*Mob,
        caster_coord: Coord,
        target: Coord,
        opts: SpellOptions,
        comptime message: ?[]const u8,
    ) void {
        if (state.player.cansee(caster_coord)) {
            const name = opts.caster_name orelse
                if (caster) |c| c.displayName() else "giant tomato";
            state.message(
                .SpellCast,
                message orelse "The {0} gestures ominously!",
                .{name},
            );
        }

        if (caster) |_| {
            caster.?.declareAction(.Cast);
            caster.?.makeNoise(.Combat, self.noise);
        } else {
            state.dungeon.soundAt(caster_coord).* = .{
                .intensity = self.noise,
                .type = .Combat,
                .state = .New,
                .when = state.ticks,
            };
        }

        switch (self.cast_type) {
            .Ray => err.todo(),
            .Bolt => {
                // Fling a bolt and let it hit whatever
                const line = caster_coord.drawLine(target, state.mapgeometry);
                const bolt_dest = for (line.constSlice()) |c| {
                    if (!c.eq(caster_coord) and !state.is_walkable(c, .{ .right_now = true }))
                        break c;
                } else target;

                const hit_mob = state.dungeon.at(bolt_dest).mob;

                if (hit_mob) |victim| {
                    if (victim == state.player) {
                        state.message(.Info, "The {} hits you!", .{self.name});
                    } else if (state.player.cansee(victim.coord)) {
                        state.message(.Info, "The {} hits the {}!", .{
                            self.name, victim.displayName(),
                        });
                    } else if (state.player.cansee(caster_coord)) {
                        state.message(.Info, "The {} hits something!", .{self.name});
                    }
                }

                switch (self.effect_type) {
                    .Status => |s| if (hit_mob) |victim| {
                        victim.addStatus(s, opts.status_power, opts.status_duration, false);
                    },
                    .Custom => |c| c(self, opts, bolt_dest),
                }
            },
            .Cast => {
                if (caster == null) {
                    err.bug("Non-mob entity attempting to cast will-checked spell!", .{});
                }

                if (state.dungeon.at(target).mob == null) {
                    err.bug("Spellcaster using .Cast spell on empty target!", .{});
                }

                const mob = state.dungeon.at(target).mob.?;

                if (!willSucceedAgainstMob(caster.?, mob))
                    return;

                switch (self.effect_type) {
                    .Status => |s| mob.addStatus(s, opts.status_power, opts.status_duration, false),
                    .Custom => |c| c(self, opts, target),
                }
            },
        }
    }
};
