const std = @import("std");
const assert = std.debug.assert;

const fov = @import("fov.zig");
usingnamespace @import("types.zig");

pub const HEIGHT = 40;
pub const WIDTH = 100;
pub const mapgeometry = Coord.new(WIDTH, HEIGHT);
pub var dungeon = [_][WIDTH]Tile{[_]Tile{Tile{
    .type = .Wall,
    .mob = null,
    .marked = false,
}} ** WIDTH} ** HEIGHT;
pub var player = Coord.new(0, 0);
pub var ticks: usize = 0;

pub fn tick() void {
    ticks += 1;

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            if (dungeon[y][x].mob) |*mob| {
                if (mob.is_dead) {
                    continue;
                } else if (mob.should_be_dead()) {
                    mob.kill();
                    continue;
                }

                mob.tick_pain();

                const apparent_vision = if (mob.facing_wide) mob.vision / 2 else mob.vision;
                const octants = fov.octants(mob.facing, mob.facing_wide);
                mob.fov.shrinkRetainingCapacity(0);
                fov.shadowcast(mob.coord, octants, mob.vision, mapgeometry, &mob.fov);

                for (mob.fov.items) |fc| {
                    var tile: u21 = if (dungeon[fc.y][fc.x].type == .Wall) '▓' else ' ';
                    if (dungeon[fc.y][fc.x].mob) |tilemob| {
                        if (!tilemob.is_dead) {
                            tile = tilemob.tile;
                        }
                    }

                    mob.memory.put(fc, tile) catch unreachable;
                }
            }
        }
    }
}

pub fn freeall() void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            if (dungeon[y][x].mob) |*mob| {
                if (mob.is_dead)
                    continue;
                mob.kill();
            }
        }
    }
}

pub fn reset_marks() void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            dungeon[y][x].marked = false;
        }
    }
}

/// Try to move a mob.
///
/// Is the destination tile a wall?
/// | true:  return false
/// | false: Does the destination tile have a mob on it already?
///     | true:  Is the other mob hostile?
///         | true:  Fight!
///         | false: return false.
///     | false: Move onto the tile and return true.
///
pub fn mob_move(coord: Coord, direction: Direction) bool {
    const mob = &dungeon[coord.y][coord.x].mob.?;

    // Face in that direction no matter whether we end up moving or no
    mob.facing = direction;

    var dest = coord;
    if (!dest.move(direction, Coord.new(WIDTH, HEIGHT))) {
        return false;
    }

    if (dungeon[dest.y][dest.x].type == .Wall) {
        return false;
    }

    if (dungeon[dest.y][dest.x].mob) |*othermob| {
        // XXX: add is_mob_hostile method that deals with all the nuances (eg
        // .NoneGood should not be hostile to .Illuvatar, but .NoneEvil should
        // be hostile to .Sauron)
        if (othermob.allegiance != mob.allegiance and !othermob.is_dead) {
            mob.fight(othermob);
        } else {
            // TODO: implement swapping when !othermob.is_dead
            return false;
        }
    } else {
        dungeon[dest.y][dest.x].mob = dungeon[coord.y][coord.x].mob;
        dungeon[coord.y][coord.x].mob = null;

        if (coord.eq(player))
            player = dest;
    }

    dungeon[dest.y][dest.x].mob.?.coord = dest;
    return true;
}

pub fn mob_gaze(coord: Coord, direction: Direction) bool {
    const mob = &dungeon[coord.y][coord.x].mob.?;

    if (mob.facing == direction) {
        mob.facing_wide = !mob.facing_wide;
    } else {
        mob.facing = direction;
    }

    // Looking around is not instantaneous and should take up a turn...
    // Probably might change this later, though, as making it not take up a turn
    // might possibly keep things easy (a mob shouldn't creep up on a player while
    // the player's scanning the opposite direction).
    return true;
}
