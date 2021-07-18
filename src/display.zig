// TODO: rename this module to 'ui'

const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const termbox = @import("termbox.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

// tb_shutdown() calls abort() if tb_init() wasn't called, or if tb_shutdown()
// was called twice. Keep track of termbox's state to prevent this.
var is_tb_inited = false;

pub fn init() !void {
    if (is_tb_inited)
        return error.AlreadyInitialized;

    switch (termbox.tb_init()) {
        0 => is_tb_inited = true,
        termbox.TB_EFAILED_TO_OPEN_TTY => return error.TTYOpenFailed,
        termbox.TB_EUNSUPPORTED_TERMINAL => return error.UnsupportedTerminal,
        termbox.TB_EPIPE_TRAP_ERROR => return error.PipeTrapFailed,
        else => unreachable,
    }

    _ = termbox.tb_select_output_mode(termbox.TB_OUTPUT_TRUECOLOR);
    _ = termbox.tb_set_clear_attributes(termbox.TB_WHITE, termbox.TB_BLACK);
    _ = termbox.tb_clear();
}

pub fn deinit() !void {
    if (!is_tb_inited)
        return error.AlreadyDeinitialized;
    termbox.tb_shutdown();
    is_tb_inited = false;
}

pub const DisplayWindow = enum { PlayerInfo, Main, EnemyInfo, Log };
pub const Dimension = struct { from: Coord, to: Coord, width: usize, height: usize };

pub fn dimensions(w: DisplayWindow) Dimension {
    const height = @intCast(usize, termbox.tb_height());
    const width = @intCast(usize, termbox.tb_width());

    const log_height = 6;
    const playerinfo_width = 25;
    const enemyinfo_width = 25;
    const playerinfo_start = 1;
    const main_start = playerinfo_start + playerinfo_width + 1;
    const main_width = width - 1 - playerinfo_width - enemyinfo_width;
    const log_start = main_start;
    const enemyinfo_start = main_start + main_width + 1;

    return switch (w) {
        .PlayerInfo => .{
            .from = Coord.new(playerinfo_start, 0),
            .to = Coord.new(playerinfo_start + playerinfo_width, height - 1),
            .width = playerinfo_width,
            .height = height - 1,
        },
        .Main => .{
            .from = Coord.new(main_start, 0),
            .to = Coord.new(main_start + main_width, height - 1 - log_height),
            .width = main_width,
            .height = height - 1 - log_height,
        },
        .EnemyInfo => .{
            .from = Coord.new(enemyinfo_start, 0),
            .to = Coord.new(width - 1, height - 1),
            .width = enemyinfo_width,
            .height = height - 1,
        },
        .Log => .{
            .from = Coord.new(log_start, height - 1 - log_height),
            .to = Coord.new(log_start + main_width, height - 1),
            .width = main_width,
            .height = log_height,
        },
    };
}

fn _clear_line(from: isize, to: isize, y: isize) void {
    var x = from;
    while (x < to) : (x += 1)
        termbox.tb_change_cell(x, y, ' ', 0xffffff, 0);
}

fn _draw_string(_x: isize, _y: isize, endx: isize, bg: u32, fg: u32, comptime format: []const u8, args: anytype) !isize {
    var buf: [256]u8 = [_]u8{0} ** 256;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.fmt.format(fbs.writer(), format, args);
    const str = fbs.getWritten();

    var x = _x;
    var y = _y;

    var utf8 = (try std.unicode.Utf8View.init(str)).iterator();
    while (utf8.nextCodepointSlice()) |encoded_codepoint| {
        const codepoint = try std.unicode.utf8Decode(encoded_codepoint);

        if (codepoint == '\n') {
            x = _x;
            y += 1;
            continue;
        }

        termbox.tb_change_cell(x, y, codepoint, bg, fg);
        x += 1;

        if (x == endx) break;
    }

    return y + 1;
}

fn _draw_bar(y: isize, startx: isize, endx: isize, current: usize, max: usize, description: []const u8, bg: u32, fg: u32) void {
    const bar_max = endx;
    const bg2 = utils.darkenColor(bg, 3); // Color used to display depleted bar
    const labelx = startx + 1; // Start of label

    var barx = startx;
    const percent = (current * 100) / max;

    const bar = @divTrunc((bar_max - barx - 1) * @intCast(isize, percent), 100);
    const bar_end = barx + bar;
    while (barx < bar_end) : (barx += 1) termbox.tb_change_cell(barx, y, ' ', fg, bg);
    while (barx < (bar_max - 1)) : (barx += 1) termbox.tb_change_cell(barx, y, ' ', fg, bg2);

    const bar_len = bar_end - startx;
    const description2 = description[math.min(@intCast(usize, bar_len), description.len)..];
    _ = _draw_string(labelx, y, endx, 0xffffff, bg, "{s}", .{description}) catch unreachable;
    _ = _draw_string(labelx + bar_len, y, endx, 0xffffff, bg2, "{s}", .{description2}) catch unreachable;
}

fn drawEnemyInfo(
    moblist: []const *Mob,
    startx: isize,
    starty: isize,
    endx: isize,
    endy: isize,
) void {
    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty;

    for (moblist) |mob| {
        if (mob.is_dead) continue;

        _clear_line(startx, endx, y);
        _clear_line(startx, endx, y + 1);

        var mobcell = Tile.displayAs(mob.coord);
        termbox.tb_put_cell(startx, y, &mobcell);

        const mobname = mob.occupation.profession_name orelse mob.species;

        y = _draw_string(startx + 1, y, endx, 0xffffff, 0, ": {}", .{mobname}) catch unreachable;

        _draw_bar(
            y,
            startx,
            endx,
            @floatToInt(usize, mob.HP),
            @floatToInt(usize, mob.max_HP),
            "health",
            0x232faa,
            0,
        );
        y += 1;

        var statuses = mob.statuses.iterator();
        while (statuses.next()) |entry| {
            const status = entry.key;
            const se = entry.value.*;

            const left = utils.saturating_sub(se.started + se.duration, state.ticks);

            if (left == 0) continue;

            _draw_bar(y, startx, endx, left, Status.MAX_DURATION, status.string(), 0x77452e, 0);
            y += 1;
        }

        const activity = mob.activity_description();
        y = _draw_string(
            endx - @divTrunc(endx - startx, 2) - @intCast(isize, activity.len / 2),
            y,
            endx,
            0x9a9a9a,
            0,
            "{}",
            .{activity},
        ) catch unreachable;

        y += 2;
    }
}

fn drawPlayerInfo(startx: isize, starty: isize, endx: isize, endy: isize) void {
    const is_running = state.player.turnsSinceRest() == state.player.activities.len;
    const strength = state.player.strength();
    const dexterity = state.player.dexterity();
    const speed = state.player.speed();

    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty;

    y = _draw_string(startx, y, endx, 0xffffff, 0, "score: {:<5} depth: {}", .{ state.score, state.player.coord.z }) catch unreachable;
    y = _draw_string(startx, y, endx, 0xffffff, 0, "turns: {}", .{state.ticks}) catch unreachable;
    y += 1;

    if (strength != state.player.base_strength) {
        const diff = @intCast(isize, strength) - @intCast(isize, state.player.base_strength);
        const adiff = math.absInt(diff) catch unreachable;
        const sign = if (diff > 0) "+" else "-";
        y = _draw_string(startx, y, endx, 0xffffff, 0, "strength:  {} ({}{})", .{ strength, sign, adiff }) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, "strength:  {}", .{strength}) catch unreachable;
    }

    if (dexterity != state.player.base_dexterity) {
        const diff = @intCast(isize, dexterity) - @intCast(isize, state.player.base_dexterity);
        const adiff = math.absInt(diff) catch unreachable;
        const sign = if (diff > 0) "+" else "-";
        y = _draw_string(startx, y, endx, 0xffffff, 0, "dexterity: {} ({}{})", .{ dexterity, sign, adiff }) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, "dexterity: {}", .{dexterity}) catch unreachable;
    }

    if (speed != state.player.base_speed) {
        const diff = @intCast(isize, speed) - @intCast(isize, state.player.base_speed);
        const adiff = math.absInt(diff) catch unreachable;
        const sign = if (diff > 0) "+" else "-";
        y = _draw_string(startx, y, endx, 0xffffff, 0, "speed: {} ({}{})", .{ speed, sign, adiff }) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, "speed: {}", .{speed}) catch unreachable;
    }

    y += 1;

    _draw_bar(
        y,
        startx,
        endx,
        @floatToInt(usize, state.player.HP),
        @floatToInt(usize, state.player.max_HP),
        "health",
        0x232faa,
        0,
    );
    y += 1;
    _draw_bar(
        y,
        startx,
        endx,
        state.player.turnsSinceRest(),
        state.player.activities.len,
        if (is_running) "running" else "walking",
        if (is_running) 0x45772e else 0x25570e,
        0,
    );
    y += 1;

    var statuses = state.player.statuses.iterator();
    while (statuses.next()) |entry| {
        const status = entry.key;
        const se = entry.value.*;

        const left = utils.saturating_sub(se.started + se.duration, state.ticks);

        if (left == 0) continue;

        _draw_bar(y, startx, endx, left, Status.MAX_DURATION, status.string(), 0x77452e, 0);
        y += 1;
    }
    y += 1;

    if (state.player.inventory.wielded) |weapon| {
        const item = Item{ .Weapon = weapon };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, endx, 0xffffff, 0, "-) {}", .{dest}) catch unreachable;
    }
    if (state.player.inventory.backup) |backup| {
        const item = Item{ .Weapon = backup };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, endx, 0xffffff, 0, "2) {}", .{dest}) catch unreachable;
    }
    if (state.player.inventory.armor) |armor| {
        const item = Item{ .Armor = armor };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, endx, 0xffffff, 0, "&) {}", .{dest}) catch unreachable;
    }
    y += 1;

    const inventory = state.player.inventory.pack.slice();
    if (inventory.len == 0) {
        y = _draw_string(startx, y, endx, 0xffffff, 0, "Your pack is empty.", .{}) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, "Inventory:", .{}) catch unreachable;
        for (inventory) |item, i| {
            const dest = (item.shortName() catch unreachable).constSlice();
            y = _draw_string(startx, y, endx, 0xffffff, 0, "  {}) {}", .{ i, dest }) catch unreachable;
        }
    }
}

fn drawLog(startx: isize, endx: isize, starty: isize, endy: isize) void {
    if (state.messages.items.len == 0)
        return;

    const first = state.messages.items.len - 1;
    var i: usize = first;
    var y: isize = starty;
    while (i > 0 and y < endy) : (i -= 1) {
        const msg = state.messages.items[i];
        const col = if (msg.turn == state.ticks or i == first) msg.type.color() else 0xa0a0a0;
        if (msg.type == .MetaError) {
            y = _draw_string(startx, y, endx, col, 0, "ERROR: {}", .{msg.msg}) catch unreachable;
        } else {
            y = _draw_string(startx, y, endx, col, 0, "{}", .{msg.msg}) catch unreachable;
        }
    }
}

fn _mobs_can_see(moblist: []const *Mob, coord: Coord) bool {
    for (moblist) |mob| {
        if (mob.is_dead) continue;
        if (mob.no_show_fov or !mob.occupation.is_combative) continue;
        if (mob.cansee(coord)) return true;
    }
    return false;
}

pub fn drawMap(moblist: []const *Mob, startx: isize, endx: isize, starty: isize, endy: isize) void {
    const playery = @intCast(isize, state.player.coord.y);
    const playerx = @intCast(isize, state.player.coord.x);
    const level = state.player.coord.z;
    var is_player_watched = false;

    const main_window = dimensions(.Main);
    var cursory: isize = starty;
    var cursorx: isize = 0;

    const height = @intCast(usize, endy - starty);
    const width = @intCast(usize, endx - startx);
    const map_starty = playery - @intCast(isize, height / 2);
    const map_endy = playery + @intCast(isize, height / 2);
    const map_startx = playerx - @intCast(isize, width / 2);
    const map_endx = playerx + @intCast(isize, width / 2);

    var y = map_starty;
    while (y < map_endy and cursory < endy) : ({
        y += 1;
        cursory += 1;
        cursorx = startx;
    }) {
        var x: isize = map_startx;
        while (x < map_endx and cursorx < endx) : ({
            x += 1;
            cursorx += 1;
        }) {
            // if out of bounds on the map, draw a black tile
            if (y < 0 or x < 0 or y >= state.HEIGHT or x >= state.WIDTH) {
                termbox.tb_change_cell(cursorx, cursory, ' ', 0xffffff, 0);
                continue;
            }

            const u_x: usize = @intCast(usize, x);
            const u_y: usize = @intCast(usize, y);
            const coord = Coord.new2(level, u_x, u_y);

            const material = state.dungeon.at(coord).material;
            var tile = Tile.displayAs(coord);

            // if player can't see area, draw a blank/grey tile, depending on
            // what they saw last there
            if (!state.player.cansee(coord)) {
                tile = .{ .fg = 0xffffff, .bg = 0, .ch = ' ' };

                if (state.player.memory.contains(coord)) {
                    tile = state.player.memory.get(coord) orelse unreachable;

                    tile.fg = utils.filterColorGrayscale(utils.darkenColor(tile.fg, 3));
                    tile.bg = utils.filterColorGrayscale(utils.darkenColor(tile.bg, 3));
                }

                if (state.player.canHear(coord)) |noise| {
                    // Adjust noise to between 0 and 122, add 0x95, then display
                    const adj_n = math.min(noise, 100) * 100 / 122;
                    const green = @intCast(u32, (255 * adj_n) / 100);
                    tile.fg = (green + 0x85) << 8;
                    tile.ch = '!';
                }

                termbox.tb_put_cell(cursorx, cursory, &tile);

                continue;
            }

            // Draw noise and indicate if that tile is visible by another mob
            switch (state.dungeon.at(coord).type) {
                .Floor => {
                    if (state.dungeon.at(coord).mob) |mob| {
                        // Treat this cell specially if it's the player and the player is
                        // being watched.
                        if (state.player.coord.eq(coord) and _mobs_can_see(moblist, coord)) {
                            termbox.tb_change_cell(cursorx, cursory, '@', 0, 0xffffff);
                            continue;
                        }
                    } else if (state.dungeon.at(coord).surface != null or
                        state.dungeon.itemsAt(coord).len > 0)
                    {
                        // Do nothing
                    } else {
                        if (state.player.canHear(coord)) |noise| {
                            // Adjust noise to between 0 and 122, add 0x95, then display
                            const adj_n = math.min(noise, 100) * 100 / 122;
                            const green = @intCast(u32, (255 * adj_n) / 100);
                            tile.fg = (green + 0x85) << 8;
                            tile.ch = '!';
                        } else if (_mobs_can_see(moblist, coord)) {
                            var can_mob_see = true;
                            if (state.player.coord.eq(coord))
                                is_player_watched = can_mob_see;
                            tile.ch = '·';
                        }
                    }
                },
                else => {},
            }

            // Adjust depending on FOV/light
            const light = math.max(
                state.dungeon.lightIntensityAt(coord).*,
                state.player.fov[coord.y][coord.x],
            );
            const light_adj = @floatToInt(usize, math.round(@intToFloat(f64, light) / 10) * 10);
            tile.bg = math.max(utils.percentageOfColor(tile.bg, light), utils.darkenColor(tile.bg, 4));
            tile.fg = math.max(utils.percentageOfColor(tile.fg, light), utils.darkenColor(tile.fg, 4));

            termbox.tb_put_cell(cursorx, cursory, &tile);
        }
    }
}

pub fn draw() void {
    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    // Create a list of all mobs on the map so that we can calculate what tiles
    // are in the FOV of any mob. Use only mobs that the player can see, the player
    // shouldn't know what's in the FOV of an invisible mob!
    const moblist = state.createMobList(false, true, state.player.coord.z, &fba.allocator);

    const playerinfo_window = dimensions(.PlayerInfo);
    const main_window = dimensions(.Main);
    const enemyinfo_window = dimensions(.EnemyInfo);
    const log_window = dimensions(.Log);

    drawPlayerInfo(
        @intCast(isize, playerinfo_window.from.x),
        @intCast(isize, playerinfo_window.from.y),
        @intCast(isize, playerinfo_window.to.x),
        @intCast(isize, playerinfo_window.to.y),
    );
    drawMap(
        moblist.items,
        @intCast(isize, main_window.from.x),
        @intCast(isize, main_window.to.x),
        @intCast(isize, main_window.from.y),
        @intCast(isize, main_window.to.y),
    );
    drawEnemyInfo(
        moblist.items,
        @intCast(isize, enemyinfo_window.from.x),
        @intCast(isize, enemyinfo_window.from.y),
        @intCast(isize, enemyinfo_window.to.x),
        @intCast(isize, enemyinfo_window.to.y),
    );
    drawLog(
        @intCast(isize, log_window.from.x),
        @intCast(isize, log_window.to.x),
        @intCast(isize, log_window.from.y),
        @intCast(isize, log_window.to.y),
    );

    termbox.tb_present();
}

pub fn chooseCell() ?Coord {
    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    // Create a list of all mobs on the map so that we can calculate what tiles
    // are in the FOV of any mob. Use only mobs that the player can see, the player
    // shouldn't know what's in the FOV of an invisible mob!
    const moblist = state.createMobList(false, true, state.player.coord.z, &fba.allocator);

    var coord: Coord = state.player.coord;

    const playery = @intCast(isize, state.player.coord.y);
    const playerx = @intCast(isize, state.player.coord.x);

    const height = termbox.tb_height() - 1;
    const width = termbox.tb_width() - 1;

    const starty = playery - @divFloor(height, 2);
    const startx = playerx - @divFloor(width, 2);

    drawMap(moblist.items, 0, width, 0, height);
    termbox.tb_present();

    while (true) {
        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                switch (ev.key) {
                    termbox.TB_KEY_CTRL_C,
                    termbox.TB_KEY_CTRL_G,
                    => return null,
                    termbox.TB_KEY_ENTER => return coord,
                    else => continue,
                }
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    'h' => coord = coord.move(.West, state.mapgeometry) orelse coord,
                    'j' => coord = coord.move(.South, state.mapgeometry) orelse coord,
                    'k' => coord = coord.move(.North, state.mapgeometry) orelse coord,
                    'l' => coord = coord.move(.East, state.mapgeometry) orelse coord,
                    'y' => coord = coord.move(.NorthWest, state.mapgeometry) orelse coord,
                    'u' => coord = coord.move(.NorthEast, state.mapgeometry) orelse coord,
                    'b' => coord = coord.move(.SouthWest, state.mapgeometry) orelse coord,
                    'n' => coord = coord.move(.SouthEast, state.mapgeometry) orelse coord,
                    else => {},
                }
            } else unreachable;
        }

        drawMap(moblist.items, 0, width, 0, height);

        const relcoordx = @intCast(usize, @intCast(isize, coord.x) - startx);
        const relcoordy = @intCast(usize, @intCast(isize, coord.y) - starty);
        const adjcoord = (relcoordy * @intCast(usize, termbox.tb_width())) + relcoordx;
        const coordtile = &termbox.tb_cell_buffer()[adjcoord];

        const tmp = coordtile.bg;
        coordtile.bg = coordtile.fg;
        coordtile.fg = tmp;

        termbox.tb_present();
    }
}

pub fn chooseInventoryItem(msg: []const u8, items: []const Item) ?usize {
    termbox.tb_clear();

    const suffix = " which item?";

    const msglen = msg.len + suffix.len;
    var y = @divFloor(termbox.tb_height(), 2) - @intCast(isize, items.len + 2);
    const x = @divFloor(termbox.tb_width(), 2) - @intCast(isize, msglen / 2);
    const endx = termbox.tb_width() - 1;

    _ = _draw_string(x, y, endx, 0xffffff, 0, "{s}{s}", .{ msg, suffix }) catch unreachable;
    y += 1;

    if (items.len == 0) {
        y = _draw_string(x, y, endx, 0xffffff, 0, "(Nothing to choose.)", .{}) catch unreachable;
    } else {
        for (items) |item, i| {
            const dest = (item.shortName() catch unreachable).constSlice();
            y = _draw_string(x, y, endx, 0xffffff, 0, "  {}) {}", .{ i, dest }) catch unreachable;
        }
    }

    termbox.tb_present();

    while (true) {
        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                if (ev.key == termbox.TB_KEY_CTRL_C or ev.key == termbox.TB_KEY_CTRL_G) {
                    return null;
                }
                continue;
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    ' ' => return null,
                    '0'...'9' => {
                        const c: usize = ev.ch - '0';
                        if (c < items.len) {
                            return c;
                        }
                    },
                    else => {},
                }
            } else unreachable;
        } else return null;
    }
}

pub fn drawGameOver() void {
    assert(state.state == .Win or state.state == .Lose);

    termbox.tb_clear();

    const msg = if (state.state == .Win) "You escaped!" else "You died!";
    const y = @divFloor(termbox.tb_height(), 2);
    const x = @divFloor(termbox.tb_width(), 2) - @intCast(isize, msg.len / 2);

    _ = _draw_string(x, y, termbox.tb_width(), 0xffffff, 0, "{s}", .{msg}) catch unreachable;

    termbox.tb_present();
}
