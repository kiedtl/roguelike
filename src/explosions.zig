usingnamespace @import("types.zig");
const fov = @import("fov.zig");
const state = @import("state.zig");
const rng = @import("rng.zig");

pub const ExplosionOpts = struct {
    // The "strength" of the explosion determines the radius of the expl.
    // Generally, ((strength / 100) * 2) will be the maximum radius, attainable
    // if the explosion is unimpeded by walls, and (strength / 100) will be the
    // minimum radius, if only walls were mulched by the explosion.
    strength: usize,

    // Whether to pulverise the player if the blast hits them. The only time
    // this should be true is when the explosion was created with a wizkey.
    spare_player: bool = false,
};

// Sets off an explosion.
//
// TODO: set kaboom'd area on fire
// TODO: throw mobs backward
// TODO: take armour into account when giving damage
//
pub fn kaboom(ground0: Coord, opts: ExplosionOpts) void {
    const S = struct {
        pub fn _opacityFunc(coord: Coord) usize {
            return switch (state.dungeon.at(coord).type) {
                .Wall => rng.range(usize, 60, 140),
                .Lava, .Water, .Floor => b: {
                    var hind: usize = 5;
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
                        .Poster => {},
                    };
                    break :b hind;
                },
                else => return 0,
            };
        }
    };

    var result: [HEIGHT][WIDTH]usize = undefined;
    for (result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    var deg: usize = 0;
    while (deg < 360) : (deg += 30) {
        const s = rng.range(usize, opts.strength / 2, opts.strength);
        fov.rayCastOctants(ground0, (s / 100) * 2, s, S._opacityFunc, &result, deg, deg + 31);
    }

    for (result) |row, y| for (row) |cell, x| {
        // Leave edge of map alone.
        if (y == 0 or x == 0 or y == (HEIGHT - 1) or x == (WIDTH - 1)) {
            continue;
        }

        if (cell > 0) {
            const coord = Coord.new2(ground0.z, x, y);
            const newtype: TileType = switch (state.dungeon.at(coord).type) {
                .Wall => .BrokenWall,
                else => .BrokenFloor,
            };
            state.dungeon.at(coord).type = newtype;
            if (state.dungeon.at(coord).surface) |surf| switch (surf) {
                .Machine => |m| m.disabled = true,
                else => {},
            };
            state.dungeon.at(coord).surface = null;
            if (state.dungeon.at(coord).mob) |unfortunate| {
                if (unfortunate == state.player) {
                    if (!opts.spare_player) {
                        state.player.takeDamage(.{
                            .amount = state.player.HP * 0.75,
                            .source = .Explosion,
                        });
                        state.message(.Info, "The blast hits you!!", .{});
                    }
                } else {
                    unfortunate.takeDamage(.{
                        .amount = 100 * @intToFloat(f64, cell) / 100.0,
                        .source = .Explosion,
                    });
                    if (state.player.cansee(unfortunate.coord)) {
                        const ldp = unfortunate.lastDamagePercentage();
                        if (ldp > 200) {
                            state.message(.Info, "The blast grinds the {} to powder!!! ({}% dmg)", .{ unfortunate.displayName(), ldp });
                        } else if (ldp > 100) {
                            state.message(.Info, "The blast pulverises the {}!! ({}% dmg)", .{ unfortunate.displayName(), ldp });
                        } else {
                            state.message(.Info, "The blast hits the {}! ({}% dmg)", .{ unfortunate.displayName(), ldp });
                        }
                    }
                }
            }
        }
    };

    state.dungeon.soundAt(ground0).* = .{
        .intensity = .Deafening,
        .type = .Explosion,
        .state = .New,
        .when = state.ticks,
    };
}
