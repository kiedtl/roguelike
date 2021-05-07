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

fn _foreach_mob(func: fn (Coord, *Mob) void) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            if (dungeon[y][x].mob) |*mob| {
                func(Coord.new(x, y), mob);
            }
        }
    }
}

fn __mob_fov(coord: Coord, mob: *Mob) void {
    mob.fov.shrinkRetainingCapacity(0);
    fov.shadowcast(coord, mob.vision, mapgeometry, &mob.fov);

    for (mob.fov.items) |fc| {
        var tile: u21 = if (dungeon[fc.y][fc.x].type == .Wall) '▓' else ' ';
        if (dungeon[fc.y][fc.x].mob) |tilemob| tile = tilemob.tile;
        mob.memory.put(fc, tile) catch unreachable;
    }
}

pub fn tick() void {
    ticks += 1;
    _foreach_mob(__mob_fov);
}

pub fn freeall() void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            if (dungeon[y][x].mob) |*mob| {
                mob.fov.deinit();
                mob.memory.clearAndFree();
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
    const mob = dungeon[coord.y][coord.x].mob orelse unreachable;

    var dest = coord;
    if (!dest.move(direction, Coord.new(WIDTH, HEIGHT))) {
        return false;
    }

    if (dungeon[dest.y][dest.x].type == .Wall) {
        return false;
    }

    if (dungeon[dest.y][dest.x].mob) |othermob| {
        // XXX: add is_mob_hostile method that deals with all the nuances (eg
        // .NoneGood should not be hostile to .Illuvatar, but .NoneEvil should
        // be hostile to .Sauron)
        if (othermob.allegiance != mob.allegiance) {
            mob_fight(coord, dest);
        } else {
            // TODO: implement swapping
            return false;
        }
    } else {
        dungeon[dest.y][dest.x].mob = mob;
        dungeon[coord.y][coord.x].mob = null;

        if (coord.eq(player))
            player = dest;
    }

    return true;
}

// TODO
pub fn mob_fight(attacker: Coord, recipient: Coord) void {
    // WHAM
}
