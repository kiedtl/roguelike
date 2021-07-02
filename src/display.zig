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

fn _clear_line(from: isize, to: isize, y: isize) void {
    var x = from;
    while (x < to) : (x += 1)
        termbox.tb_change_cell(x, y, ' ', 0xffffff, 0);
}

fn _draw_string(_x: isize, _y: isize, bg: u32, fg: u32, comptime format: []const u8, args: anytype) !isize {
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
    }

    return y + 1;
}

fn _draw_bar(y: isize, startx: isize, endx: isize, current: usize, max: usize, description: []const u8, loss_percent: usize, bg: u32, fg: u32) void {
    const bar_max = endx - 5; // Minus max width needed to display loss percentage
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
    _ = _draw_string(labelx, y, 0xffffff, bg, "{s}", .{description}) catch unreachable;
    _ = _draw_string(labelx + bar_len, y, 0xffffff, bg2, "{s}", .{description2}) catch unreachable;
    if (loss_percent != 0) {
        _ = _draw_string(bar_max, y, 0xffffff, 0, "-{}%", .{loss_percent}) catch unreachable;
    }
}

fn _draw_infopanel(
    player: *Mob,
    moblist: *const std.ArrayList(*Mob),
    startx: isize,
    starty: isize,
    endx: isize,
    endy: isize,
) void {
    const is_running = player.turnsSinceRest() == player.activities.len;
    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty;

    _draw_bar(
        y,
        startx,
        endx,
        @floatToInt(usize, player.HP),
        @floatToInt(usize, player.max_HP),
        "health",
        player.lastDamagePercentage(),
        0x232faa,
        0,
    );
    y += 1;
    _draw_bar(
        y,
        startx,
        endx,
        player.turnsSinceRest(),
        player.activities.len,
        if (is_running) "running" else "walking",
        0,
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

        _draw_bar(y, startx, endx, left, Status.MAX_DURATION, status.string(), 0, 0x77452e, 0);
        y += 1;
    }

    y = _draw_string(startx, y, 0xffffff, 0, "score: {:<5} level: {}", .{ state.score, state.player.coord.z }) catch unreachable;
    y = _draw_string(startx, y, 0xffffff, 0, "turns: {}", .{state.ticks}) catch unreachable;
    y += 2;

    if (state.player.inventory.wielded) |weapon| {
        const item = Item{ .Weapon = weapon };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, 0xffffff, 0, "-) {}", .{dest}) catch unreachable;
    }
    if (state.player.inventory.backup) |backup| {
        const item = Item{ .Weapon = backup };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, 0xffffff, 0, "2) {}", .{dest}) catch unreachable;
    }
    if (state.player.inventory.armor) |armor| {
        const item = Item{ .Armor = armor };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, 0xffffff, 0, "&) {}", .{dest}) catch unreachable;
    }
    y += 1;

    const inventory = state.player.inventory.pack.slice();
    if (inventory.len == 0) {
        y = _draw_string(startx, y, 0xffffff, 0, "Your pack is empty.", .{}) catch unreachable;
    } else {
        y = _draw_string(startx, y, 0xffffff, 0, "Inventory:", .{}) catch unreachable;
        for (inventory) |item, i| {
            const dest = (item.shortName() catch unreachable).constSlice();
            y = _draw_string(startx, y, 0xffffff, 0, "  {}) {}", .{ i, dest }) catch unreachable;
        }
    }
    y += 2;

    for (moblist.items) |mob| {
        if (mob.is_dead) continue;

        _clear_line(startx, endx, y);
        _clear_line(startx, endx, y + 1);

        var mobcell = Tile.displayAs(mob.coord);
        termbox.tb_put_cell(startx, y, &mobcell);

        y = _draw_string(startx + 1, y, 0xffffff, 0, ": {} ({})", .{ mob.species, mob.activity_description() }) catch unreachable;

        _draw_bar(y, startx, endx, @floatToInt(usize, mob.HP), @floatToInt(usize, mob.max_HP), "Health", mob.lastDamagePercentage(), 0x232faa, 0);
        y += 2;
    }
}

fn _draw_messages(startx: isize, endx: isize, starty: isize, endy: isize) void {
    if (state.messages.items.len == 0)
        return;

    const first = state.messages.items.len - 1;
    var i: usize = first;
    var y: isize = starty;
    while (i > 0 and y < endy) : (i -= 1) {
        const msg = state.messages.items[i];
        const col = if (msg.turn == state.ticks or i == first) msg.type.color() else 0xa0a0a0;
        if (msg.type == .MetaError) {
            y = _draw_string(startx, y, col, 0, "ERROR: {}", .{msg.msg}) catch unreachable;
        } else {
            y = _draw_string(startx, y, col, 0, "{}", .{msg.msg}) catch unreachable;
        }
    }
}

fn _mobs_can_see(moblist: *const std.ArrayList(*Mob), coord: Coord) bool {
    for (moblist.items) |mob| {
        if (mob.is_dead) continue;
        if (mob.cansee(coord)) return true;
    }
    return false;
}

pub fn draw() void {
    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const playery = @intCast(isize, state.player.coord.y);
    const playerx = @intCast(isize, state.player.coord.x);
    const level = state.player.coord.z;
    var is_player_watched = false;

    const maxy: isize = termbox.tb_height() - 6;
    const maxx: isize = termbox.tb_width() - 30;
    const minx: isize = 0;
    const miny: isize = 0;

    const starty = playery - @divFloor(maxy, 2);
    const endy = playery + @divFloor(maxy, 2);
    const startx = playerx - @divFloor(maxx, 2);
    const endx = playerx + @divFloor(maxx, 2);

    var cursory: isize = 0;
    var cursorx: isize = 0;

    // Create a list of all mobs on the map so that we can calculate what tiles
    // are in the FOV of any mob. Use only mobs that the player can see, the player
    // shouldn't know what's in the FOV of an invisible mob!
    var moblist = state.createMobList(false, true, level, &fba.allocator);

    var y = starty;
    while (y < endy and cursory < @intCast(usize, maxy)) : ({
        y += 1;
        cursory += 1;
        cursorx = 0;
    }) {
        var x: isize = startx;
        while (x < endx and cursorx < maxx) : ({
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
                        if (state.player.coord.eq(coord) and _mobs_can_see(&moblist, coord))
                            is_player_watched = true;
                    } else if (state.dungeon.at(coord).surface) |surfaceitem| {} else if (state.dungeon.at(coord).item) |item| {} else {
                        if (state.player.canHear(coord)) |noise| {
                            // Adjust noise to between 0 and 122, add 0x95, then display
                            const adj_n = math.min(noise, 100) * 100 / 122;
                            const green = @intCast(u32, (255 * adj_n) / 100);
                            tile.fg = (green + 0x85) << 8;
                            tile.ch = '!';
                        } else if (_mobs_can_see(&moblist, coord)) {
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

    if (!state.player.is_dead) {
        const normal_bg = Tile.displayAs(state.player.coord).bg;
        if (is_player_watched) {
            termbox.tb_change_cell(playerx - startx, playery - starty, '@', 0, 0xffffff);
        } else {
            termbox.tb_change_cell(playerx - startx, playery - starty, '@', 0xffffff, normal_bg);
        }
    }

    _draw_infopanel(state.player, &moblist, maxx, 1, termbox.tb_width(), termbox.tb_height() - 1);
    _draw_messages(0, maxx, maxy, termbox.tb_height() - 1);

    termbox.tb_present();
}

pub fn chooseCell() ?Coord {
    var coord: Coord = state.player.coord;

    const playery = @intCast(isize, state.player.coord.y);
    const playerx = @intCast(isize, state.player.coord.x);

    const maxy: isize = termbox.tb_height() - 6;
    const maxx: isize = termbox.tb_width() - 30;

    const starty = playery - @divFloor(maxy, 2);
    const startx = playerx - @divFloor(maxx, 2);

    draw();

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
                    'h' => _ = coord.move(.West, state.mapgeometry),
                    'j' => _ = coord.move(.South, state.mapgeometry),
                    'k' => _ = coord.move(.North, state.mapgeometry),
                    'l' => _ = coord.move(.East, state.mapgeometry),
                    'y' => _ = coord.move(.NorthWest, state.mapgeometry),
                    'u' => _ = coord.move(.NorthEast, state.mapgeometry),
                    'b' => _ = coord.move(.SouthWest, state.mapgeometry),
                    'n' => _ = coord.move(.SouthEast, state.mapgeometry),
                    else => {},
                }
            } else unreachable;
        }

        draw();

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

pub fn chooseInventoryItem(msg: []const u8) ?usize {
    termbox.tb_clear();

    const suffix = " which item?";
    const inventory = state.player.inventory.pack.constSlice();

    const msglen = msg.len + suffix.len;
    var y = @divFloor(termbox.tb_height(), 2) - @intCast(isize, inventory.len + 2);
    const x = @divFloor(termbox.tb_width(), 2) - @intCast(isize, msglen / 2);

    _ = _draw_string(x, y, 0xffffff, 0, "{s}{s}", .{ msg, suffix }) catch unreachable;
    y += 1;

    if (inventory.len == 0) {
        y = _draw_string(x, y, 0xffffff, 0, "(Your pack is empty.)", .{}) catch unreachable;
    } else {
        for (inventory) |item, i| {
            const dest = (item.shortName() catch unreachable).constSlice();
            y = _draw_string(x, y, 0xffffff, 0, "  {}) {}", .{ i, dest }) catch unreachable;
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
                        if (c < inventory.len) {
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

    _ = _draw_string(x, y, 0xffffff, 0, "{s}", .{msg}) catch unreachable;

    termbox.tb_present();
}
