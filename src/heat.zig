const std = @import("std");
const math = std.math;

const state = @import("state.zig");
const materials = @import("materials.zig");
usingnamespace @import("types.zig");

pub const DEFAULT_HEAT: usize = 18; // 18 °C, 65 °F
pub const DISSIPATION: usize = 5;

// Calculations are most likely completely wrong. I am not a physicist.
fn newTemperatures(
    a_tile: *const Tile,
    a_temp: usize,
    b_tile: *const Tile,
    b_temp: usize,
) struct { a: usize, b: usize } {
    const a_specific_heat = if (a_tile.type == .Wall) a_tile.material.specific_heat else Material.AIR_SPECIFIC_HEAT;
    const b_specific_heat = if (b_tile.type == .Wall) b_tile.material.specific_heat else Material.AIR_SPECIFIC_HEAT;
    const a_density = if (a_tile.type == .Wall) a_tile.material.density else Material.AIR_DENSITY;
    const b_density = if (b_tile.type == .Wall) b_tile.material.density else Material.AIR_DENSITY;
    const a_k: f64 = if (a_tile.type == .Wall) 3.00 else 15.00; // Thermal conductivity. Just using a random value, TODO: fix

    const time = 1.0; // 1 second
    const A = 1.0; // Surface area of <b> in contact with <a> (1 m²)
    const deltaT = @intToFloat(f64, @intCast(isize, a_temp) - @intCast(isize, b_temp));
    const d = 1.0; // Thickness of <b> (1 m)
    const Qt = math.ceil(math.fabs(((a_k * A * deltaT) / d) * time));

    const a_temp_diff = Qt / (a_specific_heat * (a_density * 1000));
    const b_temp_diff = Qt / (b_specific_heat * (b_density * 1000));

    const fa_temp = @intToFloat(f64, a_temp);
    const fb_temp = @intToFloat(f64, b_temp);
    var a_n_temp = if (a_temp > b_temp) fa_temp - a_temp_diff else fa_temp + a_temp_diff;
    var b_n_temp = if (b_temp > a_temp) fb_temp - b_temp_diff else fb_temp + b_temp_diff;
    a_n_temp = math.clamp(a_n_temp, 0, 65535);
    b_n_temp = math.clamp(b_n_temp, 0, 65535);

    return .{ .a = @floatToInt(usize, a_n_temp), .b = @floatToInt(usize, b_n_temp) };
}

pub fn lightEmittedByHeat(temperature: usize) usize {
    if (temperature > 600 and false) { // disabled for now
        return math.clamp((temperature - 600) * 100 / 1000, 0, 75);
    } else return 0;
}

pub fn heatEmittedByTile(tile: *Tile) usize {
    var heat: usize = 0;
    if (tile.type == .Lava)
        heat += tile.material.melting_point;
    return heat;
}

pub fn tickHeat(level: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);

            const my_tile = state.dungeon.at(coord);
            const emitted = heatEmittedByTile(state.dungeon.at(coord));
            var my_temp = state.dungeon.heat[level][coord.y][coord.x];

            for (&CARDINAL_DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |n| {
                const neighbor_tile = state.dungeon.at(n);
                var neighbor_temp = state.dungeon.heat[level][n.y][n.x];

                const new_temps = newTemperatures(neighbor_tile, neighbor_temp, my_tile, my_temp);
                neighbor_temp = new_temps.a;
                my_temp = new_temps.b;

                if (neighbor_temp > DEFAULT_HEAT) {
                    neighbor_temp -= DISSIPATION;
                } else if (neighbor_temp < DEFAULT_HEAT) {
                    neighbor_temp += DISSIPATION;
                }

                state.dungeon.heat[level][n.y][n.x] = neighbor_temp;
            };

            my_temp += emitted;
            state.dungeon.heat[level][coord.y][coord.x] = my_temp;
        }
    }
}
