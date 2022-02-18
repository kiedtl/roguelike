// TODO: rename this module to 'ui'

const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const termbox = @import("termbox.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const MIN_WIN_WIDTH: isize = 100;
pub const MIN_WIN_HEIGHT: isize = 30;

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

// Check that the window is the minimum size.
//
// Return true if the user resized the window, false if the user press Ctrl+C.
pub fn checkWindowSize(min_width: isize, min_height: isize) bool {
    while (true) {
        const cur_w = termbox.tb_width();
        const cur_h = termbox.tb_height();

        if (cur_w >= min_width and cur_h >= min_height) {
            // All's well
            termbox.tb_clear();
            return true;
        }

        _ = _draw_string(1, 1, cur_w, 0xffffff, 0, false, "Your terminal is too small.", .{}) catch unreachable;
        _ = _draw_string(1, 3, cur_w, 0xffffff, 0, false, "Minimum: {}x{}.", .{ min_width, min_height }) catch unreachable;
        _ = _draw_string(1, 4, cur_w, 0xffffff, 0, false, "Current size: {}x{}.", .{ cur_w, cur_h }) catch unreachable;

        termbox.tb_present();

        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                switch (ev.key) {
                    termbox.TB_KEY_CTRL_C, termbox.TB_KEY_ESC => return false,
                    else => {},
                }
                continue;
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    'q' => return false,
                    else => {},
                }
            } else unreachable;
        }
    }
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

fn _clearLineWith(from: isize, to: isize, y: isize, ch: u32, fg: u32, bg: u32) void {
    var x = from;
    while (x < to) : (x += 1)
        termbox.tb_change_cell(x, y, ch, fg, bg);
}

fn _clear_line(from: isize, to: isize, y: isize) void {
    _clearLineWith(from, to, y, ' ', 0xffffff, 0x000000);
}

fn _draw_string(
    _x: isize,
    _y: isize,
    endx: isize,
    bg: u32,
    fg: u32,
    fold: bool,
    comptime format: []const u8,
    args: anytype,
) !isize {
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

        if (x == endx) {
            if (fold) {
                x = _x + 2;
                y += 1;
            } else {
                break;
            }
        }
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
    _ = _draw_string(labelx, y, endx, fg, bg, false, "{s}", .{description}) catch unreachable;
    _ = _draw_string(labelx + bar_len, y, endx, fg, bg2, false, "{s}", .{description2}) catch unreachable;
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

        var mobcell = Tile.displayAs(mob.coord, false);
        termbox.tb_put_cell(startx, y, &mobcell);

        const mobname = mob.ai.profession_name orelse mob.species;

        y = _draw_string(startx + 1, y, endx, 0xffffff, 0, false, ": {}", .{mobname}) catch unreachable;

        _draw_bar(
            y,
            startx,
            endx,
            @floatToInt(usize, mob.HP),
            @floatToInt(usize, mob.max_HP),
            "health",
            0x232faa,
            0xffffff,
        );
        y += 1;

        var statuses = mob.statuses.iterator();
        while (statuses.next()) |entry| {
            const status = entry.key;
            const se = entry.value.*;

            var duration = se.duration;
            if (se.permanent) duration = Status.MAX_DURATION;

            if (duration == 0) continue;

            _draw_bar(y, startx, endx, duration, Status.MAX_DURATION, status.string(), 0x77452e, 0xffffff);
            y += 1;
        }

        const activity = mob.activity_description();
        y = _draw_string(
            endx - @divTrunc(endx - startx, 2) - @intCast(isize, activity.len / 2),
            y,
            endx,
            0x9a9a9a,
            0,
            false,
            "{}",
            .{activity},
        ) catch unreachable;

        y += 2;
    }
}

fn drawPlayerInfo(moblist: []const *Mob, startx: isize, starty: isize, endx: isize, endy: isize) void {
    const is_running = state.player.turnsSpentMoving() == state.player.activities.len;
    const last_action_cost = if (state.player.activities.current()) |lastaction| b: {
        const spd = @intToFloat(f64, state.player.speed());
        break :b (spd * @intToFloat(f64, lastaction.cost())) / 100.0 / 10.0;
    } else 0.0;
    const strength = state.player.strength();
    const dexterity = state.player.dexterity();
    const speed = state.player.speed();
    const pursued = b: for (moblist) |mob| {
        if (!mob.no_show_fov and mob.isHostileTo(state.player)) {
            for (mob.enemies.items) |enemyrecord| {
                if (enemyrecord.mob == state.player) {
                    break :b true;
                }
            }
        }
    } else false;
    const light = state.dungeon.lightIntensityAt(state.player.coord).*;

    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty;

    y = _draw_string(startx, y, endx, 0xffffff, 0, false, "score: {:<5} depth: {}", .{
        state.score, state.player.coord.z,
    }) catch unreachable;
    y = _draw_string(startx, y, endx, 0xffffff, 0, false, "turns: {} ({e:.1})", .{
        state.ticks, last_action_cost,
    }) catch unreachable;
    y += 1;

    if (strength != state.player.base_strength) {
        const diff = @intCast(isize, strength) - @intCast(isize, state.player.base_strength);
        const adiff = math.absInt(diff) catch unreachable;
        const sign = if (diff > 0) "+" else "-";
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "STR  {} ({}{})", .{ strength, sign, adiff }) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "STR  {}", .{strength}) catch unreachable;
    }

    if (dexterity != state.player.base_dexterity) {
        const diff = @intCast(isize, dexterity) - @intCast(isize, state.player.base_dexterity);
        const adiff = math.absInt(diff) catch unreachable;
        const sign = if (diff > 0) "+" else "-";
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "DEX  {} ({}{})", .{ dexterity, sign, adiff }) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "DEX  {}", .{dexterity}) catch unreachable;
    }

    if (speed != state.player.base_speed) {
        const diff = @intCast(isize, speed) - @intCast(isize, state.player.base_speed);
        const adiff = math.absInt(diff) catch unreachable;
        const sign = if (diff > 0) "+" else "-";
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "SPD  {}% ({}{}%)", .{ speed, sign, adiff }) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "SPD  {}%", .{speed}) catch unreachable;
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
        0xffffff,
    );
    y += 1;

    var statuses = state.player.statuses.iterator();
    while (statuses.next()) |entry| {
        const status = entry.key;
        const se = entry.value.*;

        var duration = se.duration;
        if (se.permanent) duration = Status.MAX_DURATION;

        if (duration == 0) continue;

        _draw_bar(y, startx, endx, duration, Status.MAX_DURATION, status.string(), 0x77452e, 0xffffff);
        y += 1;
    }
    y += 1;

    _draw_bar(
        y,
        startx,
        endx,
        state.player.turnsSpentMoving(),
        state.player.activities.len,
        if (is_running) "running" else "walking",
        if (is_running) 0x45772e else 0x25570e,
        0xffffff,
    );
    y += 1;
    _draw_bar(
        y,
        startx,
        endx,
        light / 10,
        10,
        if (light > 20) "lit" else "shadowed",
        0x776644,
        0xffffff,
    );
    y += 1;
    _draw_bar(
        y,
        startx,
        endx,
        1,
        1,
        if (pursued) "pursued" else "unseen",
        if (pursued) 0x99bbcc else 0x222222,
        if (pursued) 0x222222 else 0xcccccc,
    );
    y += 2;

    if (state.player.inventory.wielded) |weapon| {
        const item = Item{ .Weapon = weapon };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "-) {}", .{dest}) catch unreachable;
    }
    if (state.player.inventory.backup) |backup| {
        const item = Item{ .Weapon = backup };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "2) {}", .{dest}) catch unreachable;
    }
    if (state.player.inventory.armor) |armor| {
        const item = Item{ .Armor = armor };
        const dest = (item.shortName() catch unreachable).constSlice();
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "&) {}", .{dest}) catch unreachable;
    }
    y += 1;

    const inventory = state.player.inventory.pack.slice();
    if (inventory.len == 0) {
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "Your pack is empty.", .{}) catch unreachable;
    } else {
        y = _draw_string(startx, y, endx, 0xffffff, 0, false, "Inventory:", .{}) catch unreachable;
        for (inventory) |item, i| {
            const dest = (item.shortName() catch unreachable).constSlice();
            y = _draw_string(startx, y, endx, 0xffffff, 0, false, "  {}) {}", .{ i, dest }) catch unreachable;
        }
    }
}

fn drawLog(startx: isize, endx: isize, starty: isize, endy: isize) void {
    if (state.messages.items.len == 0)
        return;

    const msgcount = state.messages.items.len - 1;
    const first = msgcount - math.min(msgcount, @intCast(usize, endy - 1 - starty));
    var i: usize = first;
    var y: isize = starty;
    while (i <= msgcount and y < endy) : (i += 1) {
        const msg = state.messages.items[i];
        const msgtext = utils.used(msg.msg);

        const col = if (msg.turn >= utils.saturating_sub(state.ticks, 3) or i == msgcount)
            msg.type.color()
        else
            utils.darkenColor(msg.type.color(), 2);

        const prefix: []const u8 = switch (msg.type) {
            .MetaError => "ERROR: ",
            else => "",
        };

        _clear_line(startx, endx, y);

        if (msg.dups == 0) {
            y = _draw_string(startx, y, endx, col, 0, true, "{}{}", .{
                prefix, msgtext,
            }) catch unreachable;
        } else {
            y = _draw_string(startx, y, endx, col, 0, true, "{}{} (×{})", .{
                prefix, msgtext, msg.dups + 1,
            }) catch unreachable;
        }
    }
}

fn _mobs_can_see(moblist: []const *Mob, coord: Coord) bool {
    for (moblist) |mob| {
        if (mob.is_dead or mob.no_show_fov or
            !mob.ai.is_combative or !mob.isHostileTo(state.player))
            continue;
        if (mob.cansee(coord)) return true;
    }
    return false;
}

pub fn drawMap(moblist: []const *Mob, startx: isize, endx: isize, starty: isize, endy: isize) void {
    const playery = @intCast(isize, state.player.coord.y);
    const playerx = @intCast(isize, state.player.coord.x);
    const level = state.player.coord.z;

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
            var tile = Tile.displayAs(coord, false);

            // if player can't see area, draw a blank/grey tile, depending on
            // what they saw last there
            if (!state.player.cansee(coord)) {
                tile = .{ .fg = 0xffffff, .bg = 0, .ch = ' ' };

                if (state.memory.contains(coord)) {
                    const memt = state.memory.get(coord) orelse unreachable;
                    tile = .{ .fg = memt.fg, .bg = memt.bg, .ch = memt.ch };
                }

                tile.fg = utils.darkenColor(utils.filterColorGrayscale(tile.fg), 4);
                tile.bg = utils.darkenColor(utils.filterColorGrayscale(tile.bg), 4);

                // Can we hear anything
                if (state.player.canHear(coord)) |noise| {
                    const green: u32 = switch (noise.state) {
                        .New => 0x00D610,
                        .Old => 0x00B310,
                        .Dead => unreachable,
                    };
                    tile.fg = green;
                    tile.ch = '!';
                }

                termbox.tb_put_cell(cursorx, cursory, &tile);

                continue;
            }

            // Draw noise and indicate if that tile is visible by another mob
            switch (state.dungeon.at(coord).type) {
                .Floor => {
                    const has_stuff = state.dungeon.at(coord).surface != null or
                        state.dungeon.at(coord).mob != null or
                        state.dungeon.itemsAt(coord).len > 0;

                    if (state.player.canHear(coord)) |noise| {
                        const green: u32 = switch (noise.state) {
                            .New => 0x00D610,
                            .Old => 0x00B310,
                            .Dead => unreachable,
                        };
                        if (has_stuff) {
                            tile.bg = utils.darkenColor(green, 3);
                        } else {
                            tile.fg = green;
                            tile.ch = '!';
                        }
                    }

                    if (_mobs_can_see(moblist, coord)) {
                        // Treat this cell specially if it's the player and the player is
                        // being watched.
                        if (state.player.coord.eq(coord) and _mobs_can_see(moblist, coord)) {
                            termbox.tb_change_cell(cursorx, cursory, '@', 0, 0xffffff);
                            continue;
                        }

                        if (has_stuff) {
                            if (state.is_walkable(coord, .{ .right_now = true })) {
                                // Swap.
                                tile.fg ^= tile.bg;
                                tile.bg ^= tile.fg;
                                tile.fg ^= tile.bg;
                            }
                        } else {
                            tile.ch = '⬞';
                            //tile.fg = 0xffffff;
                        }
                    }
                },
                else => {},
            }

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
    //
    // Then, sort list to put nonhostiles last, and closer mobs first.
    const moblist = state.createMobList(false, true, state.player.coord.z, &fba.allocator);
    {
        const S = struct {
            pub fn _sortFunc(_: void, a: *Mob, b: *Mob) bool {
                const p = state.player;
                if (p.isHostileTo(a) and !p.isHostileTo(b)) return true;
                if (!p.isHostileTo(a) and p.isHostileTo(b)) return false;
                return p.coord.distance(a.coord) < p.coord.distance(b.coord);
            }
        };
        std.sort.insertionSort(*Mob, moblist.items, {}, S._sortFunc);
    }

    const playerinfo_window = dimensions(.PlayerInfo);
    const main_window = dimensions(.Main);
    const enemyinfo_window = dimensions(.EnemyInfo);
    const log_window = dimensions(.Log);

    drawPlayerInfo(
        moblist.items,
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
    assert(items.len > 0); // This should have been handled previously.

    termbox.tb_clear();

    const GREY: u32 = 0xafafaf;
    const WHITE: u32 = 0xffffff;
    const BG_GREY: u32 = 0x1e1e1e;
    const BLACK: u32 = 0x000000;

    const suffix = " which item?";
    const usage_str = "ESC/q/Ctrl+C to cancel, Enter/Space to select.";

    var longest_width: isize = 0;
    for (items) |item| {
        const name = item.longName() catch unreachable;
        if (name.len > longest_width)
            longest_width = @intCast(isize, name.len);
    }
    // + (gold_indicator + number + dash) + padding
    const line_width = math.max(@intCast(isize, usage_str.len), longest_width + 6 + 10);

    var y = @divFloor(termbox.tb_height(), 2) - @intCast(isize, ((items.len * 3) + 3) / 2);
    const x = @divFloor(termbox.tb_width(), 2) - @divFloor(line_width, 2);
    const endx = termbox.tb_width() - 1;

    y = _draw_string(x, y, endx, WHITE, 0, false, "{s}{s}", .{ msg, suffix }) catch unreachable;
    y = _draw_string(x, y, endx, GREY, 0, false, usage_str, .{}) catch unreachable;
    y += 1;
    const starty = y;

    var chosen: usize = 0;
    var cancelled = false;

    while (true) {
        y = starty;
        for (items) |item, i| {
            const name = (item.longName() catch unreachable).constSlice();

            const dist_from_chosen = @intCast(u32, math.absInt(
                @intCast(isize, i) - @intCast(isize, chosen),
            ) catch unreachable);
            const darkening = math.max(30, 100 - math.min(100, dist_from_chosen * 10));
            const dark_bg_grey = utils.percentageOfColor(BG_GREY, darkening);

            _clearLineWith(x, x + line_width, y + 0, '▂', dark_bg_grey, BLACK);
            _clearLineWith(x, x + line_width, y + 1, ' ', BLACK, dark_bg_grey);
            _clearLineWith(x, x + line_width, y + 2, '▆', BLACK, dark_bg_grey);

            y += 1;

            if (i == chosen) {
                _ = _draw_string(x, y, endx, 0xffd700, BG_GREY, false, "▎", .{}) catch unreachable;
            }

            y = _draw_string(
                x + 1,
                y,
                endx,
                if (i == chosen) WHITE else utils.percentageOfColor(GREY, darkening),
                dark_bg_grey,
                false,
                " {} - {}",
                .{ i, name },
            ) catch unreachable;

            y += 1;
        }

        termbox.tb_present();
        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                switch (ev.key) {
                    termbox.TB_KEY_ARROW_DOWN,
                    termbox.TB_KEY_ARROW_LEFT,
                    => if (chosen < items.len - 1) {
                        chosen += 1;
                    },
                    termbox.TB_KEY_ARROW_UP,
                    termbox.TB_KEY_ARROW_RIGHT,
                    => if (chosen > 0) {
                        chosen -= 1;
                    },
                    termbox.TB_KEY_CTRL_C,
                    termbox.TB_KEY_CTRL_G,
                    termbox.TB_KEY_ESC,
                    => {
                        cancelled = true;
                        break;
                    },
                    termbox.TB_KEY_SPACE, termbox.TB_KEY_ENTER => break,
                    else => {},
                }
                continue;
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    'q' => {
                        cancelled = true;
                        break;
                    },
                    'j', 'h' => if (chosen < items.len - 1) {
                        chosen += 1;
                    },
                    'k', 'l' => if (chosen > 0) {
                        chosen -= 1;
                    },
                    '0'...'9' => {
                        const c: usize = ev.ch - '0';
                        if (c < items.len) {
                            chosen = c;
                        }
                    },
                    else => {},
                }
            } else unreachable;
        }
    }

    termbox.tb_clear();
    return if (cancelled) null else chosen;
}

// Wait for input. Return null if Ctrl+c or escape was pressed, default_input
// if <enter> is pressed ,otherwise the key pressed. Will continue waiting if a
// mouse event or resize event was recieved.
pub fn waitForInput(default_input: ?u8) ?u32 {
    while (true) {
        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_RESIZE) {
            draw();
        } else if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) switch (ev.key) {
                termbox.TB_KEY_ESC, termbox.TB_KEY_CTRL_C => return null,
                termbox.TB_KEY_ENTER => if (default_input) |def| return def else continue,
                termbox.TB_KEY_SPACE => return ' ',
                else => continue,
            };

            if (ev.ch != 0) {
                return ev.ch;
            }
        }
    }
}
