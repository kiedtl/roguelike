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

pub const GameState = union(enum) { Game, Win, Lose, Quit };
pub const Layout = union(enum) { Unknown, Room: usize };

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
pub var layout: [LEVELS][HEIGHT][WIDTH]Layout = undefined;
pub var player: *Mob = undefined;
pub var state: GameState = .Game;

pub var mobs: MobList = undefined;
pub var sobs: SobList = undefined;
pub var rings: RingList = undefined;
pub var potions: PotionList = undefined;
pub var armors: ArmorList = undefined;
pub var weapons: WeaponList = undefined;
pub var projectiles: ProjectileList = undefined;
pub var machines: MachineList = undefined;
pub var props: PropList = undefined;

pub var ticks: usize = 0;
pub var messages: MessageArrayList = undefined;
pub var score: usize = 0;

pub fn nextAvailableSpaceForItem(c: Coord, alloc: *mem.Allocator) ?Coord {
    if (is_walkable(c, .{}) and !dungeon.itemsAt(c).isFull())
        return c;

    var dijk = dijkstra.Dijkstra.init(
        c,
        mapgeometry,
        8,
        is_walkable,
        .{ .right_now = true },
        alloc,
    );
    defer dijk.deinit();

    while (dijk.next()) |coord| {
        if (!is_walkable(c, .{}) or dungeon.itemsAt(c).isFull())
            continue;

        return coord;
    }

    return null;
}

const FLOOR_OPACITY: usize = 5;
const MOB_OPACITY: usize = 10;

// STYLE: change to Tile.lightOpacity
pub fn tileOpacity(coord: Coord) usize {
    const tile = dungeon.at(coord);
    var o: usize = FLOOR_OPACITY;

    if (tile.type == .Wall)
        return @floatToInt(usize, tile.material.opacity * 100);

    if (tile.mob) |_|
        o += MOB_OPACITY;

    if (tile.surface) |surface| {
        switch (surface) {
            .Machine => |m| o += @floatToInt(usize, m.opacity() * 100),
            .Prop => |p| o += @floatToInt(usize, p.opacity * 100),
            else => {},
        }
    }

    const gases = dungeon.atGas(coord);
    for (gases) |q, g| {
        if (q > 0) o += @floatToInt(usize, gas.Gases[g].opacity * 100);
    }

    return o;
}

pub const IsWalkableOptions = struct {
    // Return true only if the tile is walkable *right now*. Otherwise, tiles
    // that *could* be walkable in the future are merely assigned a penalty but
    // are treated as if they are walkable (e.g., tiles with mobs, or tiles with
    // machines that are walkable when powered but not walkable otherwise, like
    // doors).
    //
    right_now: bool = false,
    mob: ?*const Mob = null,
};

// STYLE: change to Tile.isWalkable
pub fn is_walkable(coord: Coord, opts: IsWalkableOptions) bool {
    if (dungeon.at(coord).type != .Floor)
        return false;

    if (dungeon.at(coord).mob) |other|
        if (opts.mob) |mob|
            if (!mob.canSwapWith(other, null)) return false;

    if (dungeon.at(coord).surface) |surface| {
        switch (surface) {
            .Machine => |m| {
                if (m.treat_as_walkable_by) |a|
                    if (opts.mob) |mob|
                        if (a == mob.allegiance)
                            return true; // XXX: overrides below

                if (opts.right_now) {
                    if (!m.isWalkable())
                        return false;
                } else {
                    if (!m.powered_walkable and !m.unpowered_walkable)
                        return false;
                }
            },
            .Prop => |p| if (!p.walkable) return false,
            .Sob => |s| if (!s.walkable) return false,
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

    for (mob.fov) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    const energy = mob.vision * FLOOR_OPACITY;
    const direction = if (mob.deg360_vision) null else mob.facing;

    fov.rayCast(mob.coord, mob.vision, energy, tileOpacity, &mob.fov, direction);

    for (mob.fov) |row, y| for (row) |_, x| {
        if (mob.fov[y][x] > 0) {
            const fc = Coord.new2(mob.coord.z, x, y);

            // If a tile is too dim to be seen by a mob and it's not adjacent to that mob,
            // mark it as unlit.
            if (fc.distance(mob.coord) > 1 and
                dungeon.lightIntensityAt(fc).* < mob.night_vision)
            {
                mob.fov[y][x] = 0;
                continue;
            }

            mob.memory.put(fc, Tile.displayAs(fc)) catch unreachable;
        }
    };
}

fn _can_hear_hostile(mob: *Mob) ?Coord {
    var iter = mobs.iterator();
    while (iter.nextPtr()) |othermob| {
        if (mob.canHear(othermob.coord)) |sound| {
            if (mob.isHostileTo(othermob)) {
                return othermob.coord;
            } else if (sound > 20 and
                (othermob.occupation.phase == .SawHostile or
                othermob.occupation.phase == .Flee))
            {
                // Sounds like one of our friends [or a neutral mob] is having
                // quite a party, let's go join the fun~
                return othermob.coord;
            }
        }
    }

    return null;
}

pub fn _mob_occupation_tick(mob: *Mob, alloc: *mem.Allocator) void {
    for (mob.squad_members.items) |lmob| {
        lmob.occupation.target = mob.occupation.target;
        lmob.occupation.phase = mob.occupation.phase;
        lmob.occupation.work_area.items[0] = mob.occupation.work_area.items[0];
    }

    ai.checkForHostiles(mob);

    // Check for sounds
    if (mob.occupation.phase == .Work and mob.occupation.is_curious) {
        if (_can_hear_hostile(mob)) |dest| {
            // Let's investigate
            mob.occupation.phase = .GoTo;
            mob.occupation.target = dest;
        }
    }

    const flee_threshhold = mob.max_HP * 25 / 100;
    if (mob.occupation.phase == .SawHostile and mob.HP < flee_threshhold) {
        mob.occupation.phase = .Flee;
    } else if (mob.occupation.phase == .Flee and mob.HP >= flee_threshhold) {
        mob.occupation.phase = .SawHostile;
    }

    if (mob.occupation.phase == .Work) {
        (mob.occupation.work_fn)(mob, alloc);
        return;
    }

    if (mob.occupation.phase == .GoTo) {
        const target_coord = mob.occupation.target.?;

        if (mob.coord.eq(target_coord) or mob.cansee(target_coord)) {
            // We're here, let's just look around a bit before leaving
            //
            // 1 in 8 chance of leaving every turn
            if (rng.onein(8)) {
                mob.occupation.target = null;
                mob.occupation.phase = .Work;
            } else {
                mob.facing = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);
            }

            _ = mob.rest();
        } else {
            mob.tryMoveTo(target_coord);
        }
    }

    if (mob.occupation.phase == .SawHostile) {
        assert(mob.occupation.is_combative);
        assert(mob.enemies.items.len > 0);

        (mob.occupation.fight_fn.?)(mob, alloc);
    }

    if (mob.occupation.phase == .Flee) {
        ai.flee(mob, alloc);
    }
}

pub fn tickLight(level: usize) void {
    const light_buffer = &dungeon.light_intensity[level];

    // Clear out previous light levels.
    for (light_buffer) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    // Now for the actual party...

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            const light = dungeon.emittedLightIntensity(coord);

            // A memorial to my stupidity:
            //
            // When I first created the lighting system, I omitted the below
            // check (light > 0) and did raycasting *on every tile on the map*.
            // I chalked the resulting lag (2 seconds for every turn!) to
            // the lack of optimizations in the raycasting routine, and spent
            // hours trying to write and rewrite a better raycasting function.
            //
            // Thankfully, I only wasted about two days of tearing out my hair
            // before noticing the issue.
            //
            if (light > 0) {
                fov.rayCast(coord, 20, light, tileOpacity, light_buffer, null);
            }
        }
    }
}

// Each tick, make sound decay by 0.80 for each tile.
pub fn tickSound(cur_lev: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(cur_lev, x, y);
            const cur_sound = dungeon.soundAt(coord).*;
            const new_sound = @intToFloat(f64, cur_sound) * 0.75;
            dungeon.soundAt(coord).* = @floatToInt(usize, new_sound);
        }
    }
}

pub fn tickAtmosphere(cur_lev: usize, cur_gas: usize) void {
    const dissipation = gas.Gases[cur_gas].dissipation_rate;

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
                    if (coord.move(d, mapgeometry)) |n| {
                        if (dungeon.at(n).type == .Wall)
                            continue;

                        if (dungeon.atGas(n)[cur_gas] == 0)
                            continue;

                        avg += dungeon.atGas(n)[cur_gas] - dissipation;
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
            while (x < WIDTH) : (x += 1)
                dungeon.atGas(Coord.new2(cur_lev, x, y))[cur_gas] = new[y][x];
        }
    }

    if (cur_gas < (gas.GAS_NUM - 1))
        tickAtmosphere(cur_lev, cur_gas + 1);
}

pub fn tickSobs(level: usize) void {
    var iter = sobs.iterator();
    while (iter.nextPtr()) |sob| {
        if (sob.coord.z != level or sob.is_dead)
            continue;

        sob.age += 1;
        sob.ai_func(sob);
    }
}

pub fn tickMachines(level: usize) void {
    var iter = machines.iterator();
    while (iter.nextPtr()) |machine| {
        if (machine.coord.z != level or !machine.isPowered())
            continue;

        machine.on_power(machine);
        machine.power = utils.saturating_sub(machine.power, machine.power_drain);
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
