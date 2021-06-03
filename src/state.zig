const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const ai = @import("ai.zig");
const astar = @import("astar.zig");
const dijkstra = @import("dijkstra.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const rng = @import("rng.zig");
const fov = @import("fov.zig");
usingnamespace @import("types.zig");

// Should only be used directly by functions in main.zig. For other applications,
// should be passed as a parameter by caller.
pub var GPA = std.heap.GeneralPurposeAllocator(.{
    // Probably should enable this later on to track memory usage, if
    // allocations become too much
    .enable_memory_limit = false,

    .safety = true,

    // Probably would enable this later, as we might want to run the ticks()
    // on other dungeon levels in another thread
    .thread_safe = true,

    .never_unmap = true,
}){};

pub const mapgeometry = Coord.new2(LEVELS, WIDTH, HEIGHT);
pub var dungeon: Dungeon = .{};
pub var player: *Mob = undefined;

pub var mobs: MobList = undefined;
pub var machines: MachineList = undefined;
pub var props: PropList = undefined;

pub var ticks: usize = 0;
pub var messages: MessageArrayList = undefined;
pub var score: usize = 0;

// STYLE: change to Tile.lightOpacity
pub fn light_tile_opacity(coord: Coord) usize {
    const tile = dungeon.at(coord);
    var o: usize = 5;

    if (tile.type == .Wall)
        return @floatToInt(usize, tile.material.opacity * 100);

    if (tile.surface) |surface| {
        switch (surface) {
            .Machine => |m| o += @floatToInt(usize, m.opacity * 100),
            else => {},
        }
    }

    const gases = dungeon.atGas(coord);
    for (gases) |q, g| {
        if (q > 0) o += @floatToInt(usize, gas.Gases[g].opacity * 100);
    }

    return o;
}

// STYLE: change to Tile.opacity
fn tile_opacity(coord: Coord) f64 {
    const tile = dungeon.at(coord);
    var o: f64 = 0.0;

    if (tile.type == .Wall)
        return tile.material.opacity;

    if (tile.surface) |surface| {
        switch (surface) {
            .Machine => |m| o += m.opacity,
            else => {},
        }
    }

    const gases = dungeon.atGas(coord);
    for (gases) |q, g| {
        if (q > 0) o += gas.Gases[g].opacity;
    }

    return o;
}

// STYLE: change to Tile.isWalkable
pub fn is_walkable(coord: Coord) bool {
    if (dungeon.at(coord).type == .Wall)
        return false;
    if (dungeon.at(coord).mob != null)
        return false;
    if (dungeon.at(coord).surface) |surface| {
        switch (surface) {
            .Machine => |m| if (m.should_be_avoided or !m.walkable) return false,
            else => {},
        }
    }
    return true;
}

// TODO: get rid of this
pub fn createMobList(include_player: bool, only_if_infov: bool, level: usize, alloc: *mem.Allocator) MobArrayList {
    var moblist = std.ArrayList(*Mob).init(alloc);
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new(x, y);

            if (!include_player and coord.eq(player.coord))
                continue;

            if (dungeon.at(Coord.new2(level, x, y)).mob) |mob| {
                if (only_if_infov and !player.cansee(coord))
                    continue;

                moblist.append(mob) catch unreachable;
            }
        }
    }
    return moblist;
}

// STYLE: rename to Mob.updateFOV
pub fn _update_fov(mob: *Mob) void {
    const all_octants = [_]?usize{ 0, 1, 2, 3, 4, 5, 6, 7 };

    mob.fov.shrinkRetainingCapacity(0);
    const apparent_vision = if (mob.facing_wide) mob.vision / 2 else mob.vision;

    if (mob.coord.eq(player.coord)) {
        fov.shadowcast(player.coord, all_octants, mob.vision, mapgeometry, tile_opacity, &mob.fov);
    } else {
        const octants = fov.octants(mob.facing, mob.facing_wide);
        fov.shadowcast(mob.coord, octants, apparent_vision, mapgeometry, tile_opacity, &mob.fov);
    }

    for (mob.fov.items) |fc| {
        mob.memory.put(fc, Tile.displayAs(fc)) catch unreachable;
    }
}

fn _can_hear_hostile(mob: *Mob) ?Coord {
    var iter = mobs.iterator();
    while (iter.nextPtr()) |othermob| {
        if (mob.canHear(othermob.coord)) |sound| {
            if (mob.isHostileTo(othermob)) {
                return othermob.coord;
            } else if (sound > 20) {
                // Sounds like one of our friends [or a neutral mob] is having
                // quite a party, let's go join the fun~
                return othermob.coord;
            }
        }
    }

    return null;
}

pub fn _mob_occupation_tick(mob: *Mob, alloc: *mem.Allocator) void {
    ai.checkForHostiles(mob);

    if (mob.occupation.phase != .SawHostile) {
        if (_can_hear_hostile(mob)) |dest| {
            // Let's investigate
            mob.occupation.phase = .GoTo;
            mob.occupation.target = dest;
        }
    }

    if (mob.occupation.phase == .Work) {
        mob.occupation.work_fn(mob, alloc);
        return;
    }

    if (mob.occupation.phase == .GoTo) {
        const target_coord = mob.occupation.target.?;

        if (mob.coord.eq(target_coord)) {
            // We're here, let's just look around a bit before leaving
            //
            // 1 in 8 chance of leaving every turn
            if (rng.int(u3) == 0) {
                mob.facing_wide = false;
                mob.occupation.target = null;
                mob.occupation.phase = .Work;
            } else {
                mob.facing_wide = true;
                mob.facing = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);
            }
        } else {
            if (mob.nextDirectionTo(target_coord, is_walkable)) |d| {
                _ = mob.moveInDirection(d);
            }
        }
    }

    if (mob.occupation.phase == .SawHostile) {
        assert(mob.occupation.is_combative);
        assert(mob.enemies.items.len > 0);

        const target = mob.enemies.items[0].mob;

        if (dungeon.at(target.coord).mob == null) {
            mob.occupation.phase = .GoTo;
            mob.occupation.target = target.coord;
            return;
        }

        if (mob.coord.eq(target.coord)) {
            mob.occupation.target = null;
            mob.occupation.phase = .Work;
            return;
        }

        if (mob.coord.distance(target.coord) > mob.prefers_distance) {
            if (mob.nextDirectionTo(target.coord, is_walkable)) |d| {
                _ = mob.moveInDirection(d);
            }
        } else if (mob.coord.distance(target.coord) < mob.prefers_distance) {
            // Find next space to flee to.
            const current_distance = mob.coord.distance(target.coord);

            var dijk = dijkstra.Dijkstra.init(mob.coord, mapgeometry, 3, is_walkable, alloc);
            defer dijk.deinit();

            while (dijk.next()) |coord| {
                if (coord.distance(target.coord) > current_distance) {
                    if (mob.nextDirectionTo(coord, is_walkable)) |d| {
                        const oldd = mob.facing;
                        _ = mob.moveInDirection(d);
                        mob.facing = oldd;
                        break;
                    }
                }
            }
        }
    }

    for (mob.squad_members.items) |lmob| {
        lmob.occupation.target = mob.occupation.target;
        lmob.occupation.phase = mob.occupation.phase;
        lmob.occupation.work_area.items[0] = mob.occupation.work_area.items[0];
    }
}

pub fn tickLight() void {
    const cur_lev = player.coord.z;

    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);
                dungeon.lightIntensityAt(coord).* = 0;
            }
        }
    }

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(cur_lev, x, y);
            const light = dungeon.at(coord).emittedLightIntensity();

            // A memorial to my stupidity:
            //
            // When I first created the lighting system, I omitted the below
            // check (light > 0) and did raycasting *on every tile on the map*.
            // I chalked the resulting lag (2 seconds for every turn!) to
            // the lack of optimizations in the raycasting routing, and spent
            // hours trying to write and rewrite a better raycasting function.
            //
            // Thankfully, I only wasted about two days of tearing out my hair
            // before noticing the issue.
            if (light > 0) fov.lightingRaycast(coord, 20, light);
        }
    }
}

// Each tick, make sound decay by 0.80 for each tile. This constant is chosen
// to ensure that sound that results from an untimely move persists for at least
// 4 turns.
pub fn tickSound() void {
    const cur_lev = player.coord.z;
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(cur_lev, x, y);
            const cur_sound = dungeon.soundAt(coord).*;
            const new_sound = @intToFloat(f64, cur_sound) * 0.80;
            dungeon.soundAt(coord).* = @floatToInt(usize, new_sound);
        }
    }
}

pub fn tickAtmosphere(cur_gas: usize) void {
    const dissipation = gas.Gases[cur_gas].dissipation_rate;
    const cur_lev = player.coord.z;
    var new: [HEIGHT][WIDTH]f64 = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);

                if (dungeon.at(coord).type == .Wall)
                    continue;

                var avg: f64 = dungeon.atGas(coord)[cur_gas];
                var neighbors: f64 = 1;
                for (&DIRECTIONS) |d, i| {
                    var n = coord;
                    if (!n.move(d, mapgeometry)) continue;

                    if (dungeon.at(n).type == .Wall)
                        continue;

                    if (dungeon.atGas(n)[cur_gas] == 0)
                        continue;

                    avg += dungeon.atGas(n)[cur_gas] - dissipation;
                    neighbors += 1;
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
            while (x < WIDTH) : (x += 1)
                dungeon.atGas(Coord.new2(cur_lev, x, y))[cur_gas] = new[y][x];
        }
    }

    if (cur_gas < (gas.GAS_NUM - 1))
        tickAtmosphere(cur_gas + 1);
}

pub fn reset_marks() void {
    var z: usize = 0;
    while (z < LEVELS) : (z += 1) {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                dungeon.at(Coord.new2(z, x, y)).marked = false;
            }
        }
    }
}

pub fn message(mtype: MessageType, comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    for (buf) |*i| i.* = 0;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch |_| @panic("format error");
    const str = fbs.getWritten();
    messages.append(.{ .msg = buf, .type = mtype, .turn = ticks }) catch @panic("OOM");
}
