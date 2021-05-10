const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

const astar = @import("astar.zig");
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

pub fn is_walkable(coord: Coord) bool {
    if (dungeon[coord.y][coord.x].type == .Wall)
        return false;
    return true;
}

pub fn createMobList(include_player: bool, only_if_infov: bool, alloc: *mem.Allocator) MobArrayList {
    const playermob = dungeon[player.y][player.x].mob.?;

    var moblist = std.ArrayList(*Mob).init(alloc);
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new(x, y);

            if (!include_player and coord.eq(player))
                continue;

            if (dungeon[y][x].mob) |*mob| {
                if (only_if_infov and !playermob.cansee(coord))
                    continue;

                moblist.append(mob) catch unreachable;
            }
        }
    }
    return moblist;
}

// XXX: duplicate of ai._find_coord (private func)
fn _find_coord(coord: Coord, array: *CoordArrayList) usize {
    for (array.items) |item, index| {
        if (item.eq(coord))
            return index;
    }
    unreachable;
}

fn _update_fov(mob: *Mob) void {
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

fn _can_see_hostile(mob: *Mob) ?Coord {
    for (mob.fov.items) |fitem| {
        if (dungeon[fitem.y][fitem.x].mob) |othermob| {
            if (othermob.allegiance != mob.allegiance and !othermob.is_dead) {
                return fitem;
            }
        }
    }
    return null;
}

fn _mob_occupation_tick(mob: *Mob, alloc: *mem.Allocator) void {
    if (mob.occupation.phase != .SawHostile) {
        if (_can_see_hostile(mob)) |hostile| {
            if (astar.path(mob.coord, hostile, mapgeometry, is_walkable, alloc)) |path| {
                mob.occupation.phase = .SawHostile;
                mob.occupation.target = hostile;
                mob.occupation.target_path = path;
            }
        }
    }

    if (mob.occupation.phase == .Work) {
        mob.occupation.work_fn(mob, alloc);
        return;
    }

    if (mob.occupation.phase == .SawHostile and mob.occupation.is_combative) {
        const target = &dungeon[mob.occupation.target.?.y][mob.occupation.target.?.x];
        if (mob.occupation.target_path.?.items.len == 0 or target.mob == null) {
            mob.occupation.target = null;
            if (mob.occupation.target_path) |list|
                list.deinit();
            mob.occupation.target_path = null;
            mob.occupation.phase = .Work;
            return;
        }

        // TODO: assert that the mob_move() func returns true

        const direction = if (mob.occupation.target_path.?.items.len == 1 and target.mob != null)
            mob.occupation.target_path.?.items[0]
        else
            mob.occupation.target_path.?.pop();
        _ = mob_move(mob.coord, direction);
    }
}

pub fn tick(alloc: *mem.Allocator) void {
    ticks += 1;

    const moblist = createMobList(true, false, alloc);
    defer moblist.deinit();

    for (moblist.items) |mob| {
        if (mob.is_dead) {
            continue;
        } else if (mob.should_be_dead()) {
            mob.kill();
            continue;
        }

        mob.tick_pain();
        _update_fov(mob);

        if (!mob.coord.eq(player)) {
            _mob_occupation_tick(mob, alloc);
        }

        // Be careful here, the mob pointer will be invalid if the mob
        // moves during the call to _mob_occupation_tick.
    }

    const newmoblist = createMobList(true, false, alloc);
    defer newmoblist.deinit();

    for (newmoblist.items) |mob| {
        if (mob.is_dead) {
            continue;
        } else if (mob.should_be_dead()) {
            mob.kill();
            continue;
        }
        _update_fov(mob);
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
pub fn mob_move(coord: Coord, direction: Direction) ?*Mob {
    const mob = &dungeon[coord.y][coord.x].mob.?;

    // Face in that direction no matter whether we end up moving or no
    mob.facing = direction;

    var dest = coord;
    if (!dest.move(direction, Coord.new(WIDTH, HEIGHT))) {
        return null;
    }

    if (dungeon[dest.y][dest.x].type == .Wall) {
        return null;
    }

    if (dungeon[dest.y][dest.x].mob) |*othermob| {
        // TODO: add is_mob_hostile method that deals with all the nuances (eg
        // .NoneGood should not be hostile to .Illuvatar, but .NoneEvil should
        // be hostile to .Sauron)
        if (othermob.allegiance != mob.allegiance and !othermob.is_dead) {
            mob.fight(othermob);
            return mob;
        } else {
            // TODO: implement swapping when !othermob.is_dead
            return null;
        }
    }

    dungeon[dest.y][dest.x].mob = dungeon[coord.y][coord.x].mob.?;
    dungeon[dest.y][dest.x].mob.?.coord = dest;
    dungeon[coord.y][coord.x].mob = null;

    if (coord.eq(player))
        player = dest;

    return &dungeon[dest.y][dest.x].mob.?;
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
