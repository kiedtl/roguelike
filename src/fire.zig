const std = @import("std");
const math = std.math;
const sort = std.sort;
const mem = std.mem;

const state = @import("state.zig");
const gas = @import("gas.zig");
const explosions = @import("explosions.zig");
const utils = @import("utils.zig");
const sound = @import("sound.zig");
const rng = @import("rng.zig");
const types = @import("types.zig");
const surfaces = @import("surfaces.zig");

const Mob = types.Mob;
const Coord = types.Coord;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub const MOB_BURN_DURATION = 7;

pub fn tileFlammability(c: Coord) usize {
    var f: usize = 0;

    f += state.dungeon.terrainAt(c).flammability;

    if (state.dungeon.at(c).mob) |mob| {
        if (mob.isVulnerable(.rFire)) {
            f += if (mob.hasStatus(.Fire)) @as(usize, 5) else 8;
        }
    }

    if (state.dungeon.at(c).surface) |s| switch (s) {
        .Prop => |p| f += p.flammability,
        .Machine => |m| f += m.flammability,
        .Corpse => |_| f += 10,
        else => f += 5,
    };

    return f;
}

pub fn setTileOnFire(c: Coord, amount: ?usize) void {
    if (state.dungeon.at(c).type != .Floor)
        return;
    if (state.dungeon.terrainAt(c).fire_retardant)
        return;

    const flammability = tileFlammability(c);
    const newfire = amount orelse @max(flammability, 5);
    state.dungeon.fireAt(c).* = newfire;
}

// Fire is safe if:
// - Fire is <= 3
// - Mob is already on fire (can't be much worse...)
// - Mob is immune to fire
pub inline fn fireIsSafeFor(mob: *const Mob, amount: usize) bool {
    if (amount <= 3) return true;
    if (mob.isUnderStatus(.Fire) != null) return true;
    if (mob.isFullyResistant(.rFire)) return true;
    return false;
}

pub inline fn fireLight(amount: usize) usize {
    return math.clamp(amount * 10, 0, 50);
}

pub inline fn fireColor(amount: usize) u32 {
    if (amount <= 3) return 0xff3030;
    if (amount <= 7) return 0xff4040;
    return 0xff5040;
}

pub inline fn fireGlyph(amount: usize) u21 {
    if (amount <= 3) return ',';
    if (amount <= 7) return '^';
    return '§';
}

pub inline fn fireOpacity(amount: usize) usize {
    if (amount <= 3) return 0;
    if (amount <= 7) return 5;
    return 10;
}

// Executes a bunch of triggers and sets the fire amount to 0
pub fn putFireOut(coord: Coord) void {
    // Spatter ash
    //
    state.dungeon.spatter(coord, .Ash);

    // Remove flammable terrain
    //
    // (Do this now instead of in tickFire() to ensure that things like wood
    //  don't get destroyed immediately and stop giving their rF--)
    //
    if (state.dungeon.terrainAt(coord).flammability > 0) {
        state.dungeon.at(coord).terrain = &surfaces.DefaultTerrain;
    }

    state.dungeon.fireAt(coord).* = 0;
}

pub fn tickFire(level: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            if (state.dungeon.at(coord).type != .Floor)
                continue;
            const oldfire = state.dungeon.fireAt(coord).*;
            if (oldfire == 0) continue;
            var newfire = oldfire;

            // Set mob on fire
            if (oldfire > 3) {
                if (state.dungeon.at(coord).mob) |mob| {
                    if (!mob.hasStatus(.Fire))
                        mob.addStatus(.Fire, 0, .{ .Tmp = MOB_BURN_DURATION });
                }
            }

            // Set floor neighbors on fire, if they're not already on fire.
            // Make water neighbors release steam if oldfire >= 7.
            if (oldfire > 7) {
                for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
                    switch (state.dungeon.at(neighbor).type) {
                        .Floor => {
                            const neighborfire = state.dungeon.fireAt(neighbor).*;
                            if (neighborfire == 0 and rng.percent(oldfire * 10))
                                setTileOnFire(neighbor, null);
                        },
                        .Water => {
                            if (rng.onein(3))
                                state.dungeon.atGas(neighbor)[gas.Steam.id] += 20;
                        },
                        else => {},
                    }
                };
            }

            // Destroy surface items
            if (state.dungeon.at(coord).surface) |s| {
                switch (s) {
                    .Poster, .Machine, .Corpse => state.dungeon.at(coord).surface = null,
                    else => {},
                }
            }

            newfire -|= rng.range(usize, 1, 2);

            // Release ash if going out
            // Run triggers if fire went out
            if (newfire == 0) {
                putFireOut(coord);
            }

            state.dungeon.fireAt(coord).* = newfire;
        }
    }
}
