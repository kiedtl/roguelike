const std = @import("std");
const math = std.math;

const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const DEFAULT_HEAT: usize = 18; // 18 °C, 65 °F
pub const DISSIPATION: usize = 5;

pub fn lightEmittedByHeat(temperature: usize) usize {
    if (temperature > 700) {
        return math.clamp((temperature - 700) * 100 / 700, 0, 100);
    } else return 0;
}

pub fn heatEmittedByTile(tile: *Tile) usize {
    var heat: usize = 0;
    if (tile.type == .Lava)
        heat += tile.material.melting_point;
    return heat;
}

pub fn tickHeat(level: usize) void {
    var new: [HEIGHT][WIDTH]usize = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(level, x, y);

                var avg: usize = state.dungeon.heat[level][coord.y][coord.x];

                var neighbors: usize = 1;
                for (&DIRECTIONS) |d, i| {
                    if (coord.move(d, state.mapgeometry)) |n| {
                        const current = state.dungeon.heat[level][n.y][n.x];

                        if (current > DEFAULT_HEAT) {
                            avg += state.dungeon.heat[level][n.y][n.x] - DISSIPATION;
                        } else if (current < DEFAULT_HEAT) {
                            avg += state.dungeon.heat[level][n.y][n.x] + DISSIPATION;
                        } else {
                            avg += state.dungeon.heat[level][n.y][n.x];
                        }
                        neighbors += 1;
                    }
                }

                avg /= neighbors;
                avg = math.max(avg, 0);

                new[y][x] = avg;
            }
        }
    }

    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(level, x, y);
                const new_heat = heatEmittedByTile(state.dungeon.at(coord));
                state.dungeon.heat[level][y][x] = new[y][x] + new_heat;
            }
        }
    }
}
