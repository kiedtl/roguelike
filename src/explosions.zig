const std = @import("std");
const meta = std.meta;
const math = std.math;

const types = @import("types.zig");
const fov = @import("fov.zig");
const state = @import("state.zig");
const fire = @import("fire.zig");
const items = @import("items.zig");
const sound = @import("sound.zig");
const rng = @import("rng.zig");

const Mob = types.Mob;
const DamageStr = types.DamageStr;
const Coord = types.Coord;
const Direction = types.Direction;
const Tile = types.Tile;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub fn fireBurst(ground0: Coord, max_radius: usize) void {
    const S = struct {
        pub fn _opacityFunc(c: Coord) usize {
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
    for (result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    var deg: usize = 0;
    while (deg < 360) : (deg += 30) {
        const radius = rng.range(usize, max_radius / 2, max_radius);
        fov.rayCastOctants(ground0, radius, radius * 10, S._opacityFunc, &result, deg, deg + 31);
    }
    result[ground0.y][ground0.x] = 100; // Ground zero is always incinerated

    for (result) |row, y| for (row) |cell, x| {
        if (cell > 0) {
            const cellc = Coord.new2(ground0.z, x, y);
            fire.setTileOnFire(cellc, math.max(20, fire.tileFlammability(cellc)));
        }
    };
}

pub fn elecBurst(ground0: Coord, max_damage: usize, by: ?*Mob) void {
    const S = struct {
        pub fn _opacityFunc(coord: Coord) usize {
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
    for (result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    var deg: usize = 0;
    while (deg < 360) : (deg += 30) {
        const s = rng.range(usize, 1, 2);
        fov.rayCastOctants(ground0, s, 100, S._opacityFunc, &result, deg, deg + 31);
    }

    result[ground0.y][ground0.x] = 100; // Ground zero is always harmed
    for (result) |row, y| for (row) |cell, x| {
        if (cell > 0) {
            const coord = Coord.new2(ground0.z, x, y);
            const dmg = @intToFloat(f64, max_damage * cell / 100);
            if (state.dungeon.at(coord).mob) |mob|
                if (!mob.isFullyResistant(.rElec)) {
                    mob.takeDamage(.{
                        .amount = rng.range(f64, dmg / 2, dmg),
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
    spare_player: bool = false,

    // Who created the explosion, and is thus responsible for the damage to mobs?
    culprit: ?*Mob = null,
};

// Sets off an explosion.
//
// TODO: throw mobs backward
// TODO: throw shrapnel at nearby mobs
// TODO: take armour into account when giving damage
//
pub fn kaboom(ground0: Coord, opts: ExplosionOpts) void {
    const S = struct {
        pub fn _opacityFunc(coord: Coord) usize {
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
                    break :b math.max(20, hind);
                },
            };
        }
    };

    sound.makeNoise(ground0, .Explosion, .Loudest);
    state.message(.Info, "KABOOM!", .{});

    var result: [HEIGHT][WIDTH]usize = undefined;
    for (result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    var deg: usize = 0;
    while (deg < 360) : (deg += 30) {
        const s = rng.range(usize, opts.strength / 2, opts.strength);
        fov.rayCastOctants(ground0, (s / 100), s, S._opacityFunc, &result, deg, deg + 31);
    }

    result[ground0.y][ground0.x] = 100; // Ground zero is always harmed
    for (result) |row, y| for (row) |cell, x| {
        // Leave edge of map alone.
        if (y == 0 or x == 0 or y == (HEIGHT - 1) or x == (WIDTH - 1)) {
            continue;
        }

        if (cell > 0) {
            const coord = Coord.new2(ground0.z, x, y);

            const max_range = math.max(1, opts.strength / 100);
            const chance_for_fire = 100 - (coord.distance(ground0) * 100 / max_range);
            if (rng.percent(chance_for_fire)) {
                fire.setTileOnFire(coord, null);
            }

            if (state.dungeon.at(coord).surface) |surface| switch (surface) {
                .Poster, .Prop, .Machine => state.dungeon.at(coord).surface = null,
                .Corpse => |_| state.dungeon.at(coord).surface = null, // Nuke corpses
                else => {},
            };

            if (state.dungeon.at(coord).type == .Wall)
                state.dungeon.at(coord).type = .Floor;

            if (state.dungeon.at(coord).mob) |unfortunate| {
                const total_dmg = @intToFloat(f64, opts.strength * cell / 100 / 5);

                if (unfortunate == state.player) {
                    if (!opts.spare_player) {
                        state.player.takeDamage(.{
                            .amount = math.min(total_dmg, state.player.HP * 0.50),
                            .source = .Explosion,
                            .kind = .Fire,
                        }, .{
                            .noun = "The explosion",
                        });
                    }
                } else {
                    unfortunate.takeDamage(.{
                        .amount = total_dmg,
                        .by_mob = opts.culprit,
                        .source = .Explosion,
                        .kind = .Fire,
                        .indirect = true,
                    }, .{
                        .noun = "The explosion",
                        .strs = &[_]DamageStr{
                            items._dmgstr(000, "hits", "BUG", ""),
                            items._dmgstr(100, "pulverises", "BUG", ""),
                            items._dmgstr(300, "grinds", "BUG", " to powder"),
                        },
                    });
                }
            }
        }
    };
}
