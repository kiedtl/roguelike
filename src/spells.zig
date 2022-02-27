// Spells are, basically, any ranged attack that doesn't come from a projectile.
//
// They can be fired by machines as well as monsters; when fired by monsters,
// they could be "natural" abilities (e.g., a drake's breath).
//

const std = @import("std");
const meta = std.meta;

usingnamespace @import("types.zig");
const err = @import("err.zig");
const sound = @import("sound.zig");
const state = @import("state.zig");
const rng = @import("rng.zig");

pub const BOLT_LIGHTNING = Spell{ .name = "bolt of electricity", .cast_type = .Bolt, .noise = .Medium, .effect_type = .{ .Custom = _effectBoltLightning } };
fn _effectBoltLightning(spell: Spell, opts: SpellOptions, coord: Coord) void {
    if (state.dungeon.at(coord).mob) |victim| {
        const avg_dmg = opts.power;
        const dmg = rng.rangeClumping(usize, avg_dmg / 2, avg_dmg * 2, 2);
        victim.takeDamage(.{
            .amount = @intToFloat(f64, dmg),
            .source = .RangedAttack,
            .kind = .Electric,
            .blood = false,
        });
    }
}

pub const CAST_RESURRECT_NORMAL = Spell{ .name = "resurrection", .cast_type = .Smite, .smite_target_type = .Corpse, .effect_type = .{ .Custom = _resurrectNormal }, .checks_will = false };
fn _resurrectNormal(spell: Spell, opts: SpellOptions, coord: Coord) void {
    const corpse = state.dungeon.at(coord).surface.?.Corpse;
    if (state.player.cansee(coord)) {
        state.message(.SpellCast, "The {} is imbued with a spirit of malice and rises!", .{
            corpse.displayName(),
        });
    }
    corpse.raiseAsUndead(coord);
}

pub const CAST_FREEZE = Spell{ .name = "freeze", .cast_type = .Smite, .effect_type = .{ .Status = .Paralysis }, .checks_will = true };
pub const CAST_FAMOUS = Spell{ .name = "famous", .cast_type = .Smite, .effect_type = .{ .Status = .Corona }, .checks_will = true };
pub const CAST_FERMENT = Spell{ .name = "ferment", .cast_type = .Smite, .effect_type = .{ .Status = .Confusion }, .checks_will = true };
pub const CAST_FEAR = Spell{ .name = "fear", .cast_type = .Smite, .effect_type = .{ .Status = .Fear }, .checks_will = true };
pub const CAST_PAIN = Spell{ .name = "pain", .cast_type = .Smite, .effect_type = .{ .Status = .Pain }, .checks_will = true };

fn willSucceedAgainstMob(caster: *const Mob, target: *const Mob) bool {
    if (rng.onein(10)) return false;
    return (rng.rangeClumping(usize, 1, 100, 2) * caster.willpower) >
        (rng.rangeClumping(usize, 1, 100, 2) * target.willpower);
}

pub const SpellOptions = struct {
    spell: *const Spell = undefined,
    caster_name: ?[]const u8 = null,
    duration: usize = Status.MAX_DURATION,
    power: usize = 0,
};

pub const Spell = struct {
    name: []const u8,

    cast_type: union(enum) {
        Ray,

        // Single-target, requires line-of-fire.
        Bolt,

        // Doesn't require line-of-fire (aka smite-targeted).
        Smite,
    },

    // Only used if cast_type == .Smite.
    smite_target_type: enum {
        Mob, Corpse
    } = .Mob,

    checks_will: bool = false,

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
        if (self.checks_will and caster == null) {
            err.bug("Non-mob entity attempting to cast will-checked spell!", .{});
        }

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
                for (line.constSlice()) |c| {
                    if (!c.eq(caster_coord) and !state.is_walkable(c, .{ .right_now = true })) {
                        const hit_mob = state.dungeon.at(c).mob;

                        if (hit_mob) |victim| {
                            if (self.checks_will) {
                                if (!willSucceedAgainstMob(caster.?, victim))
                                    continue;
                            }

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
                                victim.addStatus(s, opts.power, opts.duration, false);
                            },
                            .Custom => |cu| cu(self, opts, c),
                        }

                        if (hit_mob == null) break;
                    }
                }
            },
            .Smite => {
                switch (self.smite_target_type) {
                    .Mob => {
                        if (state.dungeon.at(target).mob == null) {
                            err.bug("Mage used smite-targeted spell on empty target!", .{});
                        }

                        const mob = state.dungeon.at(target).mob.?;

                        if (self.checks_will) {
                            if (!willSucceedAgainstMob(caster.?, mob))
                                return;
                        }

                        switch (self.effect_type) {
                            .Status => |s| mob.addStatus(s, opts.power, opts.duration, false),
                            .Custom => |c| c(self, opts, target),
                        }
                    },
                    .Corpse => {
                        if (state.dungeon.at(target).surface == null or
                            meta.activeTag(state.dungeon.at(target).surface.?) != .Corpse)
                        {
                            err.bug("Mage used smite-targeted spell on empty target!", .{});
                        }

                        switch (self.effect_type) {
                            .Status => err.bug("Mage tried to induce a status on a corpse!!", .{}),
                            .Custom => |c| c(self, opts, target),
                        }
                    },
                }
            },
        }
    }
};
