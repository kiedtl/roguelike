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
const literature = @import("literature.zig");
const fov = @import("fov.zig");
const tasks_m = @import("tasks.zig");
usingnamespace @import("types.zig");

pub const TaskArrayList = tasks_m.TaskArrayList;
pub const PosterArrayList = literature.PosterArrayList;

pub const GameState = union(enum) { Game, Win, Lose, Quit };
pub const Layout = union(enum) { Unknown, Room: usize };

// Should only be used directly by functions in main.zig. For other applications,
// should be passed as a parameter by caller.
pub var GPA = std.heap.GeneralPurposeAllocator(.{
    // Probably should enable this later on to track memory usage, if
    // allocations become too much
    .enable_memory_limit = false,

    .safety = true,

    // Probably would enable this later?
    .thread_safe = false,

    .never_unmap = false,
}){};

pub const mapgeometry = Coord.new2(LEVELS, WIDTH, HEIGHT);
pub var dungeon: Dungeon = .{};
pub var layout: [LEVELS][HEIGHT][WIDTH]Layout = undefined;
pub var player: *Mob = undefined;
pub var state: GameState = .Game;

// TODO: instead of storing the tile's representation in memory, store the
// actual tile -- if a wall is destroyed outside of the player's FOV, the display
// code has no way of knowing what the player remembers the destroyed tile as...
//
// Addendum 21-06-23: Is the above comment even true anymore (was it *ever* true)?
// Need to do some experimenting once explosions are added.
//
pub var memory: CoordCellMap = undefined;

pub var stockpiles: [LEVELS]StockpileArrayList = undefined;
pub var inputs: [LEVELS]StockpileArrayList = undefined;
pub var outputs: [LEVELS]RoomArrayList = undefined;

// Data objects
pub var tasks: TaskArrayList = undefined;
pub var mobs: MobList = undefined;
pub var sobs: SobList = undefined;
pub var rings: RingList = undefined;
pub var potions: PotionList = undefined;
pub var armors: ArmorList = undefined;
pub var weapons: WeaponList = undefined;
pub var machines: MachineList = undefined;
pub var props: PropList = undefined;
pub var containers: ContainerList = undefined;

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

pub const FLOOR_OPACITY: usize = 4;
pub const MOB_OPACITY: usize = 20;

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
            .Container => |_| return true,
            .Machine => |m| {
                if (opts.right_now) {
                    if (!m.isWalkable())
                        return false;
                } else {
                    if (!m.powered_walkable and !m.unpowered_walkable)
                        return false;

                    // oh boy
                    if (opts.mob) |mob|
                        if (m.restricted_to) |restriction|
                            if (!m.isWalkable() and m.powered_walkable and !m.unpowered_walkable)
                                if (restriction != mob.allegiance)
                                    return false;
                }
            },
            .Prop => |p| if (!p.walkable) return false,
            .Sob => |s| if (!s.walkable) return false,
            .Poster => return false,
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

fn _can_hear_hostile(mob: *Mob) ?Coord {
    var iter = mobs.iterator();
    while (iter.nextPtr()) |othermob| {
        if (mob.canHear(othermob.coord)) |sound| {
            if (mob.isHostileTo(othermob)) {
                return othermob.coord;
            } else if (sound > 20 and
                (othermob.ai.phase == .Hunt or
                othermob.ai.phase == .Flee))
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
        lmob.ai.target = mob.ai.target;
        lmob.ai.phase = mob.ai.phase;
        lmob.ai.work_area.items[0] = mob.ai.work_area.items[0];
    }

    ai.checkForHostiles(mob);

    // Check for sounds
    if (mob.ai.phase == .Work and mob.ai.is_curious) {
        if (_can_hear_hostile(mob)) |dest| {
            // Let's investigate
            mob.ai.phase = .Investigate;
            mob.ai.target = dest;
        }
    }

    if (mob.ai.phase == .Hunt and ai.shouldFlee(mob)) {
        mob.ai.phase = .Flee;
    } else if (mob.ai.phase == .Flee and !ai.shouldFlee(mob)) {
        mob.ai.phase = .Hunt;
    }

    if (mob.ai.phase == .Work) {
        (mob.ai.work_fn)(mob, alloc);
        return;
    }

    if (mob.ai.phase == .Investigate) {
        const target_coord = mob.ai.target.?;

        if (mob.coord.eq(target_coord) or mob.cansee(target_coord)) {
            // We're here, let's just look around a bit before leaving
            //
            // 1 in 8 chance of leaving every turn
            if (rng.onein(8)) {
                mob.ai.target = null;
                mob.ai.phase = .Work;
            } else {
                mob.facing = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);
            }

            _ = mob.rest();
        } else {
            mob.tryMoveTo(target_coord);
            mob.facing = mob.coord.closestDirectionTo(target_coord, mapgeometry);
        }
    }

    if (mob.ai.phase == .Hunt) {
        assert(mob.ai.is_combative);
        assert(mob.enemies.items.len > 0);

        (mob.ai.fight_fn.?)(mob, alloc);

        const target = mob.enemies.items[0].mob;
        mob.facing = mob.coord.closestDirectionTo(target.coord, mapgeometry);
    }

    if (mob.ai.phase == .Flee) {
        ai.flee(mob, alloc);
    }
}

pub fn tickLight(level: usize) void {
    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const light_buffer = &dungeon.light_intensity[level];

    // Clear out previous light levels.
    for (light_buffer) |*row| for (row) |*cell| {
        cell.* = 500;
    };

    var light_distances: [HEIGHT][WIDTH]usize = undefined;
    var light_intensities: [HEIGHT][WIDTH]usize = undefined;
    var lights_list = CoordArrayList.init(&fba.allocator);
    defer lights_list.deinit();

    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(level, x, y);
                const light = dungeon.emittedLightIntensity(coord);

                light_buffer[y][x] = light;
                light_distances[y][x] = 500;
                light_intensities[y][x] = light;

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
                    lights_list.append(coord) catch unreachable;
                    light_distances[y][x] = 0;
                }
            }
        }
    }

    var opacity: [HEIGHT][WIDTH]usize = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                opacity[y][x] = tileOpacity(Coord.new2(level, x, y));
            }
        }
    }

    var no_changes = false;
    while (!no_changes) {
        no_changes = true;

        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(level, x, y);

                const i_current_score = light_buffer[coord.y][coord.x];
                var i_best_score: usize = 0;
                const d_current_score = light_distances[coord.y][coord.x];
                var d_best_score: usize = 0;

                for (&DIRECTIONS) |direction| if (coord.move(direction, mapgeometry)) |neighbor| {
                    // Skip lit walls
                    if (opacity[neighbor.y][neighbor.x] >= 100 and
                        light_intensities[neighbor.y][neighbor.x] == 0)
                    {
                        continue;
                    }

                    const d_neighbor_score = light_distances[neighbor.y][neighbor.x];
                    if (d_neighbor_score < d_best_score) {
                        d_best_score = d_neighbor_score;
                    }

                    const i_neighbor_score = light_buffer[neighbor.y][neighbor.x];
                    if (i_neighbor_score > i_best_score) {
                        i_best_score = i_neighbor_score;
                    }
                };

                if ((d_best_score + 1) < d_current_score) {
                    light_distances[y][x] = d_best_score + 1;
                    no_changes = false;
                }

                const i_best_score_adj = utils.saturating_sub(i_best_score, FLOOR_OPACITY);
                if (i_current_score < i_best_score_adj) {
                    light_buffer[y][x] = i_best_score_adj;
                    no_changes = false;
                }
            }
        }
    }

    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(level, x, y);

                // Find distance of closest light
                var closest_light: usize = 999;
                for (lights_list.items) |light| {
                    //if (light_intensities[light.y][light.x] >= light_buffer[y][x]) {
                    const dist = coord.distance(light);
                    if (dist < closest_light) {
                        closest_light = dist;
                    }
                    //}
                }

                // If the distance to the closest light is less than the current
                // value of this cell in the "dijkstra map", the light went around
                // a corner; therefore, this cell should be in shadow.
                if (light_distances[y][x] > closest_light) {
                    light_buffer[y][x] /= 2;
                    light_buffer[y][x] = math.max(light_buffer[y][x], light_intensities[y][x]);
                }
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
    const residue = gas.Gases[cur_gas].residue;

    var new: [HEIGHT][WIDTH]f64 = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);

                if (!is_walkable(coord, .{}))
                    continue;

                var avg: f64 = dungeon.atGas(coord)[cur_gas];
                var neighbors: f64 = 1;
                for (&DIRECTIONS) |d, i| {
                    if (coord.move(d, mapgeometry)) |n| {
                        if (dungeon.atGas(n)[cur_gas] < 0.1)
                            continue;

                        avg += dungeon.atGas(n)[cur_gas];
                        neighbors += 1;
                    }
                }

                avg /= neighbors;
                avg -= dissipation;
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
                const coord = Coord.new2(cur_lev, x, y);
                dungeon.atGas(coord)[cur_gas] = new[y][x];
                if (residue != null and new[y][x] > 0.3)
                    dungeon.spatter(coord, residue.?);
            }
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

pub fn message(mtype: MessageType, comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    for (buf) |*i| i.* = 0;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch |_| @panic("format error");
    const str = fbs.getWritten();
    messages.append(.{ .msg = buf, .type = mtype, .turn = ticks }) catch @panic("OOM");
}
