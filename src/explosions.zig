const std = @import("std");
const meta = std.meta;
const sort = std.sort;
const math = std.math;

const colors = @import("colors.zig");
const err = @import("err.zig");
const fire = @import("fire.zig");
const fov = @import("fov.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const rng = @import("rng.zig");
const sound = @import("sound.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");
const StackBuffer = @import("buffer.zig").StackBuffer;

const Mob = types.Mob;
const DamageStr = types.DamageStr;
const Coord = types.Coord;
const CoordArrayList = types.CoordArrayList;
const Direction = types.Direction;
const Tile = types.Tile;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub const FireBurstOpts = struct {
    initial_damage: usize = 1,

    min_fire: usize = 20,

    // Who created the explosion, and is thus responsible for the damage to mobs?
    culprit: ?*Mob = null,

    // Used to prevent mobs from taking damage multiple times when recursive
    // explosions take place.
    mob_cache: ?*std.AutoHashMap(*Mob, void) = null,
};

pub fn fireBurst(ground0: Coord, max_radius: usize, opts: FireBurstOpts) void {
    const S = struct {
        pub fn _opacityFunc(c: Coord, _: void) usize {
            return switch (state.dungeon.at(c).type) {
                .Lava, .Water, .Wall => 100,
                .Floor => if (state.dungeon.at(c).surface) |surf| switch (surf) {
                    .Machine => |m| if (m.isWalkable()) @as(usize, 0) else 50,
                    .Prop => |p| if (p.walkable) @as(usize, 0) else 50,
                    .Container => 100,
                    else => 0,
                } else 0,
            };
        }
    };

    var result: [HEIGHT][WIDTH]usize = undefined;
    for (&result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    sound.makeNoise(ground0, .Explosion, switch (max_radius) {
        // These are *fire* explosions, after all, so not quite as loud as regular ones
        0...1 => .Medium,
        2...4 => .Loud,
        else => .Louder,
    });

    var deg: usize = 0;
    while (deg < 360) : (deg += 30) {
        const radius = rng.range(usize, max_radius / 2, max_radius);
        fov.rayCastOctants(ground0, radius, radius * 10, {}, S._opacityFunc, &result, deg, deg + 31);
    }
    result[ground0.y][ground0.x] = 100; // Ground zero is always incinerated

    var mob_cache_backing = if (opts.mob_cache == null) std.AutoHashMap(*Mob, void).init(state.alloc) else undefined;
    const mob_cache = opts.mob_cache orelse &mob_cache_backing;
    defer if (opts.mob_cache == null) mob_cache_backing.deinit();

    for (&result, 0..) |row, y| for (row, 0..) |cell, x| {
        if (cell > 0) {
            const cellc = Coord.new2(ground0.z, x, y);
            if (state.dungeon.at(cellc).mob) |mob| {
                if (opts.initial_damage > 0 and !mob.isFullyResistant(.rFire) and
                    mob_cache.get(mob) == null)
                {
                    mob_cache.put(mob, {}) catch err.wat();
                    mob.takeDamage(.{
                        .amount = opts.initial_damage,
                        .by_mob = opts.culprit,
                        .source = .Explosion,
                        .kind = .Fire,
                        .indirect = true,
                    }, .{
                        .noun = "The fiery blast",
                        .strs = &[_]DamageStr{
                            items._dmgstr(0, "scorches", "scorches", ""),
                            items._dmgstr(100, "burns", "burns", ""),
                            items._dmgstr(300, "incinerates", "incinerates", ""),
                        },
                    });
                }
            }
            fire.setTileOnFire(cellc, @max(opts.min_fire, fire.tileFlammability(cellc)));

            if (state.dungeon.gasAt(cellc, gas.Fire.id).* > 0) {
                state.dungeon.gasAt(cellc, gas.Fire.id).* = 0;
                var copts = opts;
                copts.mob_cache = mob_cache;
                fireBurst(cellc, 1, copts);
            }
        }
    };
}

pub fn elecBurst(ground0: Coord, max_damage: usize, by: ?*Mob) void {
    const S = struct {
        pub fn _opacityFunc(coord: Coord, _: void) usize {
            return switch (state.dungeon.at(coord).type) {
                .Wall => 100,
                .Lava, .Water, .Floor => b: {
                    var hind: usize = 0;
                    if (state.dungeon.at(coord).mob != null) {
                        hind += 50;
                    }
                    if (state.dungeon.at(coord).surface) |surf| switch (surf) {
                        .Machine => |m| if (m.isWalkable()) {
                            hind += 50;
                        } else {
                            hind += 100;
                        },
                        .Prop => |p| if (p.walkable) {
                            hind += 50;
                        } else {
                            hind += 100;
                        },
                        .Container => hind += 100,
                        else => {},
                    };
                    break :b hind;
                },
            };
        }
    };

    sound.makeNoise(ground0, .Explosion, .Loudest);
    state.message(.Info, "KABOOM!", .{});

    var result: [HEIGHT][WIDTH]usize = undefined;
    for (&result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    var deg: usize = 0;
    while (deg < 360) : (deg += 30) {
        const s = rng.range(usize, 1, 2);
        fov.rayCastOctants(ground0, s, 100, {}, S._opacityFunc, &result, deg, deg + 31);
    }

    result[ground0.y][ground0.x] = 100; // Ground zero is always harmed
    for (result, 0..) |row, y| for (row, 0..) |cell, x| {
        if (cell > 0) {
            const coord = Coord.new2(ground0.z, x, y);
            const dmg = max_damage * cell / 100;
            if (state.dungeon.at(coord).mob) |mob|
                if (!mob.isFullyResistant(.rElec)) {
                    mob.takeDamage(.{
                        .amount = rng.range(usize, dmg / 2, dmg),
                        .by_mob = by,
                        .source = .Explosion,
                        .kind = .Electric,
                        .indirect = true,
                    }, .{
                        .noun = "The electric arc",
                        .strs = &[_]DamageStr{items._dmgstr(0, "strikes", "strikes", "")},
                    });
                };
        }
    };
}

pub const ExplosionOpts = struct {
    // The "strength" of the explosion determines the radius of the expl.
    // Generally, (strength / 100) will be the maximum radius.
    strength: usize,

    // Whether to pulverise the player if the blast hits them. The only time
    // this should be true is when the explosion was created with a wizkey.
    //
    // EDIT 2025-03-24: ...and when shrines explode
    //
    spare_player: bool = false,

    // Who created the explosion, and is thus responsible for the damage to mobs?
    culprit: ?*Mob = null,
};

// Sets off an explosion.
//
// TODO: throw mobs backward
// TODO: throw shrapnel at nearby mobs
//
pub fn kaboom(ground0: Coord, opts: ExplosionOpts) void {
    const S = struct {
        pub fn _opacityFunc(coord: Coord, _: void) usize {
            return switch (state.dungeon.at(coord).type) {
                .Wall => rng.range(usize, 60, 140),
                .Lava, .Water, .Floor => b: {
                    var hind: usize = 0;
                    if (state.dungeon.at(coord).mob != null) {
                        hind += 10;
                    }
                    if (state.dungeon.at(coord).surface) |surf| switch (surf) {
                        .Machine => |m| if (m.isWalkable()) {
                            hind += 1;
                        } else {
                            hind += rng.range(usize, 50, 80);
                        },
                        .Prop => |p| if (p.walkable) {
                            hind += 1;
                        } else {
                            hind += rng.range(usize, 50, 80);
                        },
                        .Container => hind += rng.range(usize, 60, 80),
                        else => {},
                    };
                    break :b @max(20, hind);
                },
            };
        }
    };

    sound.makeNoise(ground0, .Explosion, .Loudest);

    var result: [HEIGHT][WIDTH]usize = undefined;
    for (&result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    var deg: usize = 0;
    while (deg < 360) : (deg += 30) {
        const s = rng.range(usize, opts.strength / 2, opts.strength);
        fov.rayCastOctants(ground0, (s / 100), s, {}, S._opacityFunc, &result, deg, deg + 31);
    }

    var coords = CoordArrayList.init(state.alloc);
    defer coords.deinit();

    // Get list of coords affected, so that we can process animations before
    // we apply any effects.
    //
    result[ground0.y][ground0.x] = 100; // Ground zero is always harmed
    for (result, 0..) |row, y| for (row, 0..) |cell, x| {
        // Leave edge of map alone.
        if (y == 0 or x == 0 or y == (HEIGHT - 1) or x == (WIDTH - 1)) {
            continue;
        } else if (cell == 0) {
            continue;
        }

        coords.append(Coord.new2(ground0.z, x, y)) catch err.wat();
    };

    // Do animation before damage, otherwise the damage animations appear
    // before and it just looks weird.
    ui.Animation.blink(coords.items, '#', colors.PALE_VIOLET_RED, .{}).apply();

    // Do fire and object removal next
    //
    // Otherwise fire slowly "spreads" from top to bottom as mobs take damage
    // and again, it just looks weird.
    for (coords.items) |coord| {
        const max_range = @max(1, opts.strength / 100);
        const chance_for_fire = 100 - (coord.distance(ground0) * 100 / max_range);
        if (rng.percent(chance_for_fire)) {
            fire.setTileOnFire(coord, null);
        }

        if (state.dungeon.at(coord).surface) |surface| switch (surface) {
            .Corpse, .Poster, .Prop, .Machine => surface.destroy(coord),
            else => {},
        };

        if (state.dungeon.at(coord).type == .Wall)
            state.dungeon.at(coord).type = .Floor;
    }

    // Finally, the damage
    for (coords.items) |coord| {
        if (state.dungeon.at(coord).mob) |unfortunate|
            if (unfortunate != state.player or !opts.spare_player)
                unfortunate.takeDamage(.{
                    .amount = 3,
                    .by_mob = opts.culprit,
                    .source = .Explosion,
                    .indirect = true,
                }, .{
                    .noun = "The explosion",
                    .strs = &[_]DamageStr{
                        items._dmgstr(0, "hits", "hits", ""),
                        items._dmgstr(100, "pulverises", "pulverises", ""),
                        items._dmgstr(300, "grinds", "grinds", " to powder"),
                    },
                });
    }
}
