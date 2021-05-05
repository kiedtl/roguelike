const std = @import("std");
const assert = std.debug.assert;

usingnamespace @import("types.zig");

pub const HEIGHT = 40;
pub const WIDTH = 100;
pub var dungeon = [_][WIDTH]Tile{[_]Tile{Tile{
    .type = .Wall,
    .mob = null,
}} ** WIDTH} ** HEIGHT;
pub var player = Coord.new(0, 0);

pub fn tick() void {}

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
