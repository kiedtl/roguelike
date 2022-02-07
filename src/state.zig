const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;
const enums = @import("std/enums.zig");

const ai = @import("ai.zig");
const astar = @import("astar.zig");
const display = @import("display.zig");
const dijkstra = @import("dijkstra.zig");
const mapgen = @import("mapgen.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const rng = @import("rng.zig");
const literature = @import("literature.zig");
const fov = @import("fov.zig");
usingnamespace @import("types.zig");

const SoundState = @import("sound.zig").SoundState;
const TaskArrayList = @import("tasks.zig").TaskArrayList;
const EvocableList = @import("items.zig").EvocableList;
const PosterArrayList = literature.PosterArrayList;

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

pub const levelinfo = [LEVELS]struct {
    id: []const u8, name: []const u8
}{
    .{ .id = "PRI", .name = "-1/Prison" },
    .{ .id = "VLT", .name = "-2/Vaults" },
    .{ .id = "PRI", .name = "-3/Prison" },
    .{ .id = "LAB", .name = "-4/Laboratory" },
    .{ .id = "PRI", .name = "-5/Prison" },
    .{ .id = "PRI", .name = "-6/Prison" },
    .{ .id = "SMI", .name = "-7/Smithing" },
};

// Information collected over a run to present in a morgue file.
pub var chardata: struct {
    foes_killed_total: usize = 0,
    foes_stabbed: usize = 0,
    foes_killed: std.AutoHashMap([]const u8, usize) = undefined,
    time_with_statuses: enums.EnumArray(Status, usize) = enums.EnumArray(Status, usize).initFill(0),
    time_on_levels: [LEVELS]usize = [1]usize{0} ** LEVELS,
    potions_quaffed: std.AutoHashMap([]const u8, usize) = undefined,
    evocs_used: std.AutoHashMap([]const u8, usize) = undefined,

    pub fn init(self: *@This(), alloc: *mem.Allocator) void {
        self.foes_killed = std.AutoHashMap([]const u8, usize).init(alloc);
        self.potions_quaffed = std.AutoHashMap([]const u8, usize).init(alloc);
        self.evocs_used = std.AutoHashMap([]const u8, usize).init(alloc);
    }

    pub fn deinit(self: *@This()) void {
        self.foes_killed.clearAndFree();
        self.potions_quaffed.clearAndFree();
        self.evocs_used.clearAndFree();
    }
} = .{};

// TODO: instead of storing the tile's representation in memory, store the
// actual tile -- if a wall is destroyed outside of the player's FOV, the display
// code has no way of knowing what the player remembers the destroyed tile as...
//
// Addendum 21-06-23: Is the above comment even true anymore (was it *ever* true)?
// Need to do some experimenting once explosions are added.
//
pub var memory: CoordCellMap = undefined;

pub var rooms: [LEVELS]mapgen.Room.ArrayList = undefined;
pub var stockpiles: [LEVELS]StockpileArrayList = undefined;
pub var inputs: [LEVELS]StockpileArrayList = undefined;
pub var outputs: [LEVELS]Rect.ArrayList = undefined;

// Data objects
pub var tasks: TaskArrayList = undefined;
pub var mobs: MobList = undefined;
pub var rings: RingList = undefined;
pub var potions: PotionList = undefined;
pub var armors: ArmorList = undefined;
pub var weapons: WeaponList = undefined;
pub var machines: MachineList = undefined;
pub var props: PropList = undefined;
pub var containers: ContainerList = undefined;
pub var evocables: EvocableList = undefined;

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
    switch (dungeon.at(coord).type) {
        .Wall, .Water, .Lava => return false,
        else => {},
    }

    if (dungeon.at(coord).mob) |other|
        if (opts.mob) |mob| {
            if (!mob.canSwapWith(other, null)) return false;
        } else return false;

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
            .Poster => return false,
        }
    }

    return true;
}

// TODO: move this to utils.zig?
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

fn _canHearNoise(mob: *Mob) ?Coord {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(mob.coord.z, x, y);
            if (mob.canHear(coord)) |sound| {
                if (sound.mob_source) |othermob| {
                    // Just because one guard made some noise running over to
                    // the player doesn't mean we want to whole level to
                    // run over and investigate the guard's noise.
                    //
                    if (sound.type == .Movement and !mob.isHostileTo(othermob))
                        continue;

                    if (dungeon.at(coord).prison)
                        continue;
                }

                return coord;
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
        if (_canHearNoise(mob)) |dest| {
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

// Make sound "decay" each tick.
pub fn tickSound(cur_lev: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(cur_lev, x, y);
            const cur_sound = dungeon.soundAt(coord);
            cur_sound.state = SoundState.ageToState(ticks - cur_sound.when);
        }
    }
}

// Create and dissipate gas.
pub fn tickAtmosphere(cur_lev: usize, cur_gas: usize) void {
    // First make hot water emit gas.
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);
                const c_gas = dungeon.atGas(coord);
                switch (dungeon.at(coord).type) {
                    .Water => {
                        var near_lavas: f64 = 0;
                        for (&DIRECTIONS) |d|
                            if (coord.move(d, mapgeometry)) |neighbor| {
                                if (dungeon.at(neighbor).type == .Lava) near_lavas += 1;
                            };
                        c_gas[gas.Steam.id] = near_lavas;
                    },
                    // TODO: smoke for lava?
                    else => {},
                }
            }
        }
    }

    // ...then spread it.
    const std_dissipation = gas.Gases[cur_gas].dissipation_rate;
    const residue = gas.Gases[cur_gas].residue;

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
                        if (dungeon.atGas(n)[cur_gas] < 0.1)
                            continue;

                        avg += dungeon.atGas(n)[cur_gas];
                        neighbors += 1;
                    }
                }

                const max_dissipation = @floatToInt(usize, std_dissipation * 100);
                const dissipation = rng.rangeClumping(usize, 0, max_dissipation * 2, 2);
                const dissipation_f = @intToFloat(f64, dissipation) / 100;

                avg /= neighbors;
                avg -= dissipation_f;
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

pub fn message(mtype: MessageType, comptime fmt: []const u8, args: anytype) void {
    var buf: [128]u8 = undefined;
    for (buf) |*i| i.* = 0;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch |_| @panic("format error");

    var msg: Message = .{
        .msg = undefined,
        .type = mtype,
        .turn = ticks,
    };
    utils.copyZ(&msg.msg, fbs.getWritten());

    // If the message isn't a prompt, check if the message is a duplicate
    if (mtype != .Prompt and messages.items.len > 0 and mem.eql(
        u8,
        utils.used(messages.items[messages.items.len - 1].msg),
        utils.used(msg.msg),
    )) {
        messages.items[messages.items.len - 1].dups += 1;
    } else {
        messages.append(msg) catch @panic("OOM");
    }
}

// Print a prompt, redrawing the screen immediately.
//
// If valid_inputs is empty, any input will be accepted and returned.
// If the key pressed is not in valid_inputs, continue prompting.
// If a 'cancel' key is pressed (see display.waitForInput), the text "Nevermind" is printed.
// If <enter> is pressed, default_input is returned.
// Otherwise, normalized_inputs[<index of key in valid_inputs>] is returned.
//
// Example:
//     messageKeyPrompts("Foo [Y/n]?", .{}, 'Y', "YyNn", "yynn");
//  "Y" => 'y'
//  "N" => 'n'
//  "n' => 'n'
//
pub fn messageKeyPrompt(
    comptime fmt: []const u8,
    args: anytype,
    default_input: ?u8,
    valid_inputs: []const u8,
    normalized_inputs: []const u8,
) ?u8 {
    message(.Prompt, fmt, args);
    display.draw();

    while (true) {
        const res = display.waitForInput(default_input);
        if (res == null) {
            message(.Prompt, "Nevermind.", .{});
            return null;
        }
        if (res.? > 255) continue;

        const key = @intCast(u8, res.?);

        // Should we accept any input?
        if (valid_inputs.len == 0) {
            return key;
        }

        if (mem.indexOfScalar(u8, valid_inputs, key)) |ind| {
            return normalized_inputs[ind];
        }
    }
}

pub fn formatMorgue(alloc: *mem.Allocator) !std.ArrayList(u8) {
    const S = struct {
        fn _damageString() []const u8 {
            const ldp = player.lastDamagePercentage();
            var str: []const u8 = "killed";
            if (ldp > 30) str = "demolished";
            if (ldp > 50) str = "miserably destroyed";
            if (ldp > 80) str = "utterly destroyed";
            return str;
        }
    };

    var buf = std.ArrayList(u8).init(alloc);
    var w = buf.writer();

    try w.print("Oathbreaker morgue entry\n", .{});
    try w.print("\n", .{});
    try w.print("Seed: {}\n", .{rng.seed});
    try w.print("\n", .{});
    try w.print("{} {} after {} turns\n", .{
        std.os.getenv("USER").?, // FIXME: should have backup option if null
        if (state == .Win) @as([]const u8, "escaped") else "died",
        ticks,
    });
    if (state == .Lose) {
        if (player.killed_by) |by| {
            try w.print("        ...{} by a {} ({}% dmg)\n", .{
                S._damageString(),
                by.displayName(),
                player.lastDamagePercentage(),
            });
        }
        try w.print("        ...on level {} of the Dungeon\n", .{levelinfo[player.coord.z].name});
    }
    try w.print("\n", .{});
    try w.print("-) {: <40} &) {}\n", .{
        if (player.inventory.wielded) |i|
            ((Item{ .Weapon = i }).shortName() catch unreachable).constSlice()
        else
            "<none>",
        if (player.inventory.armor) |a|
            ((Item{ .Armor = a }).shortName() catch unreachable).constSlice()
        else
            "<none>",
    });
    try w.print("2) {}\n", .{
        if (player.inventory.backup) |b|
            ((Item{ .Weapon = b }).shortName() catch unreachable).constSlice()
        else
            "<none>",
    });
    try w.print("\n", .{});
    try w.print("Rings:\n", .{});
    try w.print("1) {: <40} 2) {}\n", .{
        if (player.inventory.rings[0]) |b|
            ((Item{ .Ring = b }).shortName() catch unreachable).constSlice()
        else
            "<none>",
        if (player.inventory.rings[1]) |b|
            ((Item{ .Ring = b }).shortName() catch unreachable).constSlice()
        else
            "<none>",
    });
    try w.print("3) {: <40} 4) {}\n", .{
        if (player.inventory.rings[2]) |b|
            ((Item{ .Ring = b }).shortName() catch unreachable).constSlice()
        else
            "<none>",
        if (player.inventory.rings[3]) |b|
            ((Item{ .Ring = b }).shortName() catch unreachable).constSlice()
        else
            "<none>",
    });
    try w.print("\n", .{});
    try w.print("Inventory:\n", .{});
    for (player.inventory.pack.constSlice()) |item| {
        const itemname = (item.shortName() catch unreachable).constSlice();
        try w.print("- {}\n", .{itemname});
    }
    try w.print("\n", .{});
    try w.print("You were: ", .{});
    {
        var comma = false;
        inline for (@typeInfo(Status).Enum.fields) |status| {
            const status_e = @field(Status, status.name);
            if (player.isUnderStatus(status_e)) |_| {
                if (comma)
                    try w.print(", {}", .{status_e.string()})
                else
                    try w.print("{}", .{status_e.string()});
                comma = true;
            }
        }
    }
    try w.print(".\n", .{});
    try w.print("You killed {} foe{}, stabbing {} of them.\n", .{
        chardata.foes_killed_total,
        if (chardata.foes_killed_total > 0) @as([]const u8, "s") else "",
        chardata.foes_stabbed,
    });
    try w.print("\n", .{});
    try w.print("Last messages:\n", .{});
    if (messages.items.len > 0) {
        const msgcount = messages.items.len - 1;
        var i: usize = msgcount - math.min(msgcount, 45);
        while (i <= msgcount) : (i += 1) {
            const msg = messages.items[i];
            const msgtext = utils.used(msg.msg);

            const prefix: []const u8 = switch (msg.type) {
                .MetaError => "ERROR: ",
                else => "",
            };

            if (msg.dups == 0) {
                try w.print("- {}{}\n", .{ prefix, msgtext });
            } else {
                try w.print("- {}{} (×{})\n", .{ prefix, msgtext, msg.dups + 1 });
            }
        }
    }
    try w.print("\n", .{});
    try w.print("Surroundings:\n", .{});
    {
        const radius: usize = 14;
        var y: usize = utils.saturating_sub(player.coord.y, radius);
        while (y < math.min(player.coord.y + radius, HEIGHT)) : (y += 1) {
            try w.print("        ", .{});
            var x: usize = utils.saturating_sub(player.coord.x, radius);
            while (x < math.min(player.coord.x + radius, WIDTH)) : (x += 1) {
                const coord = Coord.new2(player.coord.z, x, y);

                if (dungeon.neighboringWalls(coord, true) == 9) {
                    try w.print(" ", .{});
                    continue;
                }

                if (player.coord.eq(coord)) {
                    try w.print("@", .{});
                    continue;
                }

                var ch = @intCast(u21, Tile.displayAs(coord, false).ch);
                if (ch == ' ') ch = '.';

                // TODO: after zig v9 upgrade, change this to use {u} format specifier
                var utf8buf: [4]u8 = undefined;
                const sz = std.unicode.utf8Encode(ch, &utf8buf) catch unreachable;
                try w.print("{}", .{utf8buf[0..sz]});
            }
            try w.print("\n", .{});
        }
    }
    try w.print("\n", .{});
    try w.print("You could see:\n", .{});
    {
        const can_see = createMobList(false, true, player.coord.z, alloc);
        defer can_see.deinit();
        var can_see_counted = std.AutoHashMap([]const u8, usize).init(alloc);
        defer can_see_counted.deinit();
        for (can_see.items) |mob| {
            const prevtotal = (can_see_counted.getOrPutValue(mob.displayName(), 0) catch unreachable).value;
            can_see_counted.put(mob.displayName(), prevtotal + 1) catch unreachable;
        }

        var iter = can_see_counted.iterator();
        while (iter.next()) |mobcount| {
            try w.print("- {: >2} {}\n", .{ mobcount.value, mobcount.key });
        }
    }
    try w.print("\n", .{});
    try w.print("Vanquished foes:\n", .{});
    {
        var iter = chardata.foes_killed.iterator();
        while (iter.next()) |mobcount| {
            try w.print("- {: >2} {}\n", .{ mobcount.value, mobcount.key });
        }
    }
    try w.print("\n", .{});
    try w.print("Time spent with statuses:\n", .{});
    inline for (@typeInfo(Status).Enum.fields) |status| {
        const status_e = @field(Status, status.name);
        const turns = chardata.time_with_statuses.get(status_e);
        if (turns > 0) {
            try w.print("- {: <20} {: >5} turns\n", .{ status_e.string(), turns });
        }
    }
    try w.print("\n", .{});
    try w.print("Items used:\n", .{});
    {
        var iter = chardata.potions_quaffed.iterator();
        while (iter.next()) |item| {
            try w.print("- {: <20} {: >5}\n", .{ item.value, item.key });
        }
    }
    {
        var iter = chardata.evocs_used.iterator();
        while (iter.next()) |item| {
            try w.print("- {: <20} {: >5}\n", .{ item.value, item.key });
        }
    }
    try w.print("\n", .{});
    try w.print("Time spent on levels:\n", .{});
    for (chardata.time_on_levels[0..]) |turns, level| {
        try w.print("- {: <20} {: >5}\n", .{ levelinfo[level].name, turns });
    }

    return buf;
}
