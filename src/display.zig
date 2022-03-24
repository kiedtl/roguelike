// TODO: rename this module to 'ui'

const std = @import("std");
const math = std.math;
const io = std.io;
const assert = std.debug.assert;
const mem = std.mem;

const colors = @import("colors.zig");
const player = @import("player.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const gas = @import("gas.zig");
const state = @import("state.zig");
const termbox = @import("termbox.zig");
const utils = @import("utils.zig");
const types = @import("types.zig");

const StackBuffer = @import("buffer.zig").StackBuffer;

const Mob = types.Mob;
const Stat = types.Stat;
const Resistance = types.Resistance;
const Coord = types.Coord;
const Direction = types.Direction;
const Tile = types.Tile;
const Status = types.Status;
const Item = types.Item;
const CoordArrayList = types.CoordArrayList;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

// -----------------------------------------------------------------------------

pub const LEFT_INFO_WIDTH: usize = 24;
pub const RIGHT_INFO_WIDTH: usize = 24;
pub const LOG_HEIGHT: usize = 8;

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
    clearScreen();
}

// Check that the window is the minimum size.
//
// Return true if the user resized the window, false if the user press Ctrl+C.
pub fn checkWindowSize() bool {
    const min_height = HEIGHT + LOG_HEIGHT + 2;
    const min_width = WIDTH + LEFT_INFO_WIDTH + RIGHT_INFO_WIDTH + 2;

    while (true) {
        const cur_w = termbox.tb_width();
        const cur_h = termbox.tb_height();

        if (cur_w >= min_width and cur_h >= min_height) {
            // All's well
            clearScreen();
            return true;
        }

        _ = _drawStr(1, 1, cur_w, "Your terminal is too small.", .{}, .{});
        _ = _drawStr(1, 3, cur_w, "Minimum: {}x{}.", .{ min_width, min_height }, .{});
        _ = _drawStr(1, 4, cur_w, "Current size: {}x{}.", .{ cur_w, cur_h }, .{});

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
pub const Dimension = struct { startx: isize, endx: isize, starty: isize, endy: isize };

pub fn dimensions(w: DisplayWindow) Dimension {
    const height = termbox.tb_height();
    const width = termbox.tb_width();

    const playerinfo_width = LEFT_INFO_WIDTH;
    //const enemyinfo_width = RIGHT_INFO_WIDTH;

    const playerinfo_start = 1;
    const main_start = playerinfo_start + playerinfo_width + 1;
    const main_width = WIDTH;
    const main_height = HEIGHT;
    const log_start = main_start;
    const enemyinfo_start = main_start + main_width + 1;

    return switch (w) {
        .PlayerInfo => .{
            .startx = playerinfo_start,
            .endx = playerinfo_start + playerinfo_width,
            .starty = 0,
            .endy = height - 1,
            //.width = playerinfo_width,
            //.height = height - 1,
        },
        .Main => .{
            .startx = main_start,
            .endx = main_start + main_width,
            .starty = 1,
            .endy = main_height + 2,
            //.width = main_width,
            //.height = main_height,
        },
        .EnemyInfo => .{
            .startx = enemyinfo_start,
            .endx = width - 1,
            .starty = 1,
            .endy = height - 1,
            //.width = math.max(enemyinfo_width, width - enemyinfo_start),
            //.height = height - 1,
        },
        .Log => .{
            .startx = log_start,
            .endx = log_start + main_width,
            .starty = 2 + main_height,
            .endy = height - 1,
            //.width = main_width,
            //.height = math.max(LOG_HEIGHT, height - (2 + main_height) - 1),
        },
    };
}

fn _clearLineWith(from: isize, to: isize, y: isize, ch: u32, fg: u32, bg: u32) void {
    var x = from;
    while (x < to) : (x += 1)
        termbox.tb_change_cell(x, y, ch, fg, bg);
}

pub fn clearScreen() void {
    const height = termbox.tb_height();
    const width = termbox.tb_width();

    var y: isize = 0;
    while (y < height) : (y += 1)
        _clearLineWith(0, width, y, ' ', 0, colors.BG);
}

fn _clear_line(from: isize, to: isize, y: isize) void {
    _clearLineWith(from, to, y, ' ', 0, colors.BG);
}

const DrawStrOpts = struct {
    bg: ?u32 = colors.BG,
    fg: u32 = 0xe6e6e6,
    fold: bool = false,
};

// Escape characters:
//     $g       fg = GREY
//     $G       fg = DARK_GREY
//     $c       fg = LIGHT_CONCRETE
//     $p       fg = PINK
//     $b       fg = LIGHT_STEEL_BLUE
//     $r       fg = PALE_VIOLET_RED
//     $.       reset fg and bg to defaults
fn _drawStr(_x: isize, _y: isize, endx: isize, comptime format: []const u8, args: anytype, opts: DrawStrOpts) isize {
    const termbox_width = termbox.tb_width();
    const termbox_buffer = termbox.tb_cell_buffer();

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), format, args) catch err.bug("format error!", .{});
    const str = fbs.getWritten();

    var x = _x;
    var y = _y;

    var fg = opts.fg;
    var bg: ?u32 = opts.bg;

    var utf8 = (std.unicode.Utf8View.init(str) catch err.bug("bad utf8", .{})).iterator();
    while (utf8.nextCodepointSlice()) |encoded_codepoint| {
        const codepoint = std.unicode.utf8Decode(encoded_codepoint) catch err.bug("bad utf8", .{});
        const def_bg = termbox_buffer[@intCast(usize, y * termbox_width + x)].bg;

        switch (codepoint) {
            '\n' => {
                y += 1;
                x = _x;
                continue;
            },
            '\r' => err.bug("Bad character found in string.", .{}),
            '$' => {
                const next_encoded_codepoint = utf8.nextCodepointSlice() orelse
                    err.bug("Found incomplete escape sequence", .{});
                const next_codepoint = std.unicode.utf8Decode(next_encoded_codepoint) catch err.bug("bad utf8", .{});
                switch (next_codepoint) {
                    '.' => {
                        fg = opts.fg;
                        bg = opts.bg;
                    },
                    'g' => fg = colors.GREY,
                    'G' => fg = colors.DARK_GREY,
                    'c' => fg = colors.LIGHT_CONCRETE,
                    'p' => fg = colors.PINK,
                    'b' => fg = colors.LIGHT_STEEL_BLUE,
                    'r' => fg = colors.PALE_VIOLET_RED,
                    else => err.bug("Found unknown escape sequence", .{}),
                }
                continue;
            },
            else => {
                termbox.tb_change_cell(x, y, codepoint, fg, bg orelse def_bg);
                x += 1;
            },
        }

        if (x == endx) {
            if (opts.fold) {
                x = _x + 2;
                y += 1;
            } else {
                x -= 1;
            }
        }
    }

    return y + 1;
}

fn _draw_bar(y: isize, startx: isize, endx: isize, current: usize, max: usize, description: []const u8, bg: u32, fg: u32) void {
    const bg2 = colors.darken(bg, 3); // Color used to display depleted bar
    const percent = (current * 100) / max;
    const bar = @divTrunc((endx - startx - 1) * @intCast(isize, percent), 100);
    const bar_end = startx + bar;

    _clearLineWith(startx, bar_end, y, ' ', fg, bg);
    _clearLineWith(bar_end, endx - 1, y, ' ', fg, bg2);

    _ = _drawStr(startx + 1, y, endx, "{s}", .{description}, .{ .fg = fg, .bg = null });
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

        y = _drawStr(startx + 1, y, endx, " {s}", .{mob.displayName()}, .{});

        _draw_bar(y, startx, endx, @floatToInt(usize, mob.HP), @floatToInt(usize, mob.max_HP), "health", 0x232faa, 0xffffff);
        y += 1;

        var statuses = mob.statuses.iterator();
        while (statuses.next()) |entry| {
            const status = entry.key;
            const se = entry.value.*;

            const duration = switch (se.duration) {
                .Prm, .Ctx => Status.MAX_DURATION,
                .Tmp => |t| t,
            };

            if (duration == 0) continue;

            _draw_bar(y, startx, endx, duration, Status.MAX_DURATION, status.string(mob), 0x77452e, 0xffffff);
            y += 1;
        }

        const activity = if (mob.prisoner_status != null) if (mob.prisoner_status.?.held_by != null) "(chained)" else "(prisoner)" else mob.activity_description();
        y = _drawStr(endx - @divTrunc(endx - startx, 2) - @intCast(isize, activity.len / 2), y, endx, "{s}", .{activity}, .{ .fg = 0x9a9a9a });

        y += 2;
    }
}

fn drawPlayerInfo(moblist: []const *Mob, startx: isize, starty: isize, endx: isize, endy: isize) void {
    // const last_action_cost = if (state.player.activities.current()) |lastaction| b: {
    //     const spd = @intToFloat(f64, state.player.speed());
    //     break :b (spd * @intToFloat(f64, lastaction.cost())) / 100.0 / 10.0;
    // } else 0.0;

    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty + 1;

    y = _drawStr(startx, y, endx, "--- {s} ---", .{
        state.levelinfo[state.player.coord.z].name,
    }, .{ .fg = 0xffffff });
    y += 1;

    inline for (@typeInfo(Stat).Enum.fields) |statv| {
        const stat = @intToEnum(Stat, statv.value);
        const base_stat_val = utils.getFieldByEnum(Stat, state.player.stats, stat);

        const cur_stat_val = @intCast(isize, switch (stat) {
            .Missile => combat.chanceOfMissileLanding(state.player),
            .Melee => combat.chanceOfMeleeLanding(state.player, null),
            .Evade => combat.chanceOfAttackEvaded(state.player, null),
            else => state.player.stat(stat),
        });

        if (cur_stat_val > 0 or base_stat_val > 0) {
            if (cur_stat_val != base_stat_val) {
                const diff = cur_stat_val - base_stat_val;
                const abs = math.absInt(diff) catch unreachable;
                const sign = if (diff > 0) "+" else "-";
                y = _drawStr(startx, y, endx, "$c{s: <8}$. {: >4} ({s}{})", .{
                    stat.string(), cur_stat_val, sign, abs,
                }, .{});
            } else {
                y = _drawStr(startx, y, endx, "$c{s: <8}$. {: >4}", .{ stat.string(), cur_stat_val }, .{});
            }
        }
    }

    const armor = 100 - @intCast(isize, state.player.resistance(.Armor));
    y = _drawStr(startx, y, endx, "$carmor%$.   {: >4}%", .{armor}, .{});

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

        if (state.player.isUnderStatus(status) == null)
            continue;

        const duration = switch (se.duration) {
            .Prm, .Ctx => Status.MAX_DURATION,
            .Tmp => |t| t,
        };

        _draw_bar(y, startx, endx, duration, Status.MAX_DURATION, status.string(state.player), 0x77452e, 0xffffff);
        y += 1;
    }
    y += 1;

    const sneak = @intCast(usize, state.player.stat(.Sneak));
    const is_walking = state.player.turnsSpentMoving() >= sneak;
    _draw_bar(y, startx, endx, math.min(sneak, state.player.turnsSpentMoving()), sneak, if (is_walking) "walking" else "sneaking", if (is_walking) 0x45772e else 0x25570e, 0xffffff);
    y += 2;

    const light = state.dungeon.lightAt(state.player.coord).*;
    const flanked = state.player.isFlanked();
    const spotted = b: for (moblist) |mob| {
        if (!mob.no_show_fov and mob.ai.is_combative and mob.isHostileTo(state.player)) {
            for (mob.enemies.items) |enemyrecord|
                if (enemyrecord.mob == state.player) break :b true;
        }
    } else false;

    const lit_str = if (light) "Lit " else "";
    const flanked_str = if (flanked) "Flanked " else "";
    const spotted_str = if (spotted) "Spotted " else "";

    y = _drawStr(startx, y, endx, "$c{s}$.$b{s}$.$r{s}$.", .{
        lit_str, spotted_str, flanked_str,
    }, .{});

    y += 1;

    y = _drawStr(startx, y, endx, "$cturns:$. {}", .{state.ticks}, .{});
    y += 1;

    const terrain = state.dungeon.terrainAt(state.player.coord);
    if (!mem.eql(u8, terrain.id, "t_default")) {
        y = _drawStr(startx, y, endx, "$cterrain$.: {s}", .{terrain.name}, .{});

        inline for (@typeInfo(Stat).Enum.fields) |statv| {
            const stat = @intToEnum(Stat, statv.value);
            const stat_val = utils.getFieldByEnum(Stat, terrain.stats, stat);
            if (stat_val != 0) {
                const abs = math.absInt(stat_val) catch unreachable;
                const sign = if (stat_val > 0) "+" else "-";
                y = _drawStr(startx, y, endx, "· $c{s: <5}$. {s}{}", .{
                    stat.string(), sign, abs,
                }, .{});
            }
        }

        inline for (@typeInfo(Resistance).Enum.fields) |resistv| {
            const resist = @intToEnum(Resistance, resistv.value);
            const resist_val = utils.getFieldByEnum(Resistance, terrain.resists, resist);
            if (resist_val != 0) {
                const abs = math.absInt(resist_val) catch unreachable;
                const sign = if (resist_val > 0) "+" else "-";
                y = _drawStr(startx, y, endx, "· {s: <5} {s}{}", .{
                    resist.string(), sign, abs,
                }, .{});
            }
        }

        for (terrain.effects) |effect| {
            const str = effect.status.string(state.player);
            y = switch (effect.duration) {
                .Prm => _drawStr(startx, y, endx, "$gPrm$. {s}\n", .{str}, .{}),
                .Tmp => _drawStr(startx, y, endx, "$gTmp$. {s} ({})\n", .{ str, effect.duration }, .{}),
                .Ctx => _drawStr(startx, y, endx, "$gCtx$. {s}\n", .{str}, .{}),
            };
        }
    }
}

fn drawLog(startx: isize, endx: isize, starty: isize, endy: isize) void {
    var y = starty;

    while (y < endy) : (y += 1) {
        _clear_line(startx, endx, y);
    }
    y = starty;

    if (state.messages.items.len == 0)
        return;

    const msgcount = state.messages.items.len - 1;
    const first = msgcount - math.min(msgcount, @intCast(usize, endy - 1 - starty));
    var i: usize = first;
    while (i <= msgcount and y < endy) : (i += 1) {
        const msg = state.messages.items[i];
        const msgtext = utils.used(msg.msg);

        const col = if (msg.turn >= state.ticks -| 3 or i == msgcount)
            msg.type.color()
        else
            colors.darken(msg.type.color(), 2);

        _clear_line(startx, endx, y);

        if (msg.dups == 0) {
            y = _drawStr(startx, y, endx, "{s}", .{
                msgtext,
            }, .{ .fg = col, .fold = true });
        } else {
            y = _drawStr(startx, y, endx, "{s} (×{})", .{
                msgtext, msg.dups + 1,
            }, .{ .fg = col, .fold = true });
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
    //const playery = @intCast(isize, state.player.coord.y);
    //const playerx = @intCast(isize, state.player.coord.x);
    const level = state.player.coord.z;

    var cursory: isize = starty;
    var cursorx: isize = startx;

    //const height = @intCast(usize, endy - starty);
    //const width = @intCast(usize, endx - startx);
    //const map_starty = playery - @intCast(isize, height / 2);
    //const map_endy = playery + @intCast(isize, height / 2);
    //const map_startx = playerx - @intCast(isize, width / 2);
    //const map_endx = playerx + @intCast(isize, width / 2);

    const map_starty: isize = 0;
    const map_endy: isize = HEIGHT;
    const map_startx: isize = 0;
    const map_endx: isize = WIDTH;

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
            if (y < 0 or x < 0 or y >= HEIGHT or x >= WIDTH) {
                termbox.tb_change_cell(cursorx, cursory, ' ', 0, colors.BG);
                continue;
            }

            const u_x: usize = @intCast(usize, x);
            const u_y: usize = @intCast(usize, y);
            const coord = Coord.new2(level, u_x, u_y);

            var tile = Tile.displayAs(coord, false);

            // if player can't see area, draw a blank/grey tile, depending on
            // what they saw last there
            if (!state.player.cansee(coord)) {
                tile = .{ .fg = 0, .bg = colors.BG, .ch = ' ' };

                if (state.memory.contains(coord)) {
                    const memt = state.memory.get(coord) orelse unreachable;
                    tile = .{ .fg = memt.fg, .bg = memt.bg, .ch = memt.ch };

                    tile.fg = colors.darken(colors.filterGrayscale(tile.fg), 4);
                    tile.bg = colors.darken(colors.filterGrayscale(tile.bg), 4);
                }

                // Can we hear anything
                if (state.player.canHear(coord)) |noise| if (noise.state == .New) {
                    tile.fg = 0x00d610;
                    tile.ch = if (noise.intensity.radiusHeard() > 6) '♫' else '♩';
                };

                termbox.tb_put_cell(cursorx, cursory, &tile);

                continue;
            }

            // Draw noise and indicate if that tile is visible by another mob
            switch (state.dungeon.at(coord).type) {
                .Floor => {
                    const has_stuff = state.dungeon.at(coord).surface != null or
                        state.dungeon.at(coord).mob != null or
                        state.dungeon.itemsAt(coord).len > 0;

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

    const moblist = state.createMobList(false, true, state.player.coord.z, fba.allocator());

    const pinfo_win = dimensions(.PlayerInfo);
    const main_win = dimensions(.Main);
    const einfo_win = dimensions(.EnemyInfo);
    const log_window = dimensions(.Log);

    drawPlayerInfo(moblist.items, pinfo_win.startx, pinfo_win.starty, pinfo_win.endx, pinfo_win.endy);
    drawMap(moblist.items, main_win.startx, main_win.endx, main_win.starty, main_win.endy);
    drawEnemyInfo(moblist.items, einfo_win.startx, einfo_win.starty, einfo_win.endx, einfo_win.endy);
    drawLog(log_window.startx, log_window.endx, log_window.starty, log_window.endy);

    termbox.tb_present();
}

pub fn chooseCell() ?Coord {
    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const moblist = state.createMobList(false, true, state.player.coord.z, fba.allocator());

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

    // A bit messy.
    var namebuf = std.ArrayList([]const u8).init(state.GPA.allocator());
    defer {
        for (namebuf.items) |str| state.GPA.allocator().free(str);
        namebuf.deinit();
    }

    for (items) |item| {
        const itemname = item.longName() catch err.wat();
        const string = state.GPA.allocator().alloc(u8, itemname.len) catch err.wat();
        std.mem.copy(u8, string, itemname.constSlice());
        namebuf.append(string) catch err.wat();
    }

    return chooseOption(msg, namebuf.items);
}

pub fn chooseOption(msg: []const u8, options: []const []const u8) ?usize {
    assert(options.len > 0); // This should have been handled previously.

    clearScreen();

    const usage_str = "ESC/q/Ctrl+C to cancel, Enter/Space to select.";

    var longest_width: isize = 0;
    for (options) |opt| {
        if (opt.len > longest_width)
            longest_width = @intCast(isize, opt.len);
    }
    // + (gold_indicator + number + dash) + padding
    const line_width = math.max(@intCast(isize, usage_str.len), longest_width + 6 + 10);

    var y = @divFloor(termbox.tb_height(), 2) - @intCast(isize, ((options.len * 3) + 3) / 2);
    const x = @divFloor(termbox.tb_width(), 2) - @divFloor(line_width, 2);
    const endx = termbox.tb_width() - 1;

    y = _drawStr(x, y, endx, "{s}", .{msg}, .{ .fg = colors.WHITE });
    y = _drawStr(x, y, endx, usage_str, .{}, .{ .fg = colors.GREY });
    y += 1;
    const starty = y;

    var chosen: usize = 0;
    var cancelled = false;

    while (true) {
        y = starty;
        for (options) |name, i| {
            const dist_from_chosen = @intCast(u32, math.absInt(
                @intCast(isize, i) - @intCast(isize, chosen),
            ) catch unreachable);
            const darkening = math.max(30, 100 - math.min(100, dist_from_chosen * 10));
            const dark_bg_grey = colors.percentageOf(colors.BG_GREY, darkening);

            _clearLineWith(x, x + line_width, y + 0, '▂', dark_bg_grey, colors.BLACK);
            _clearLineWith(x, x + line_width, y + 1, ' ', colors.BLACK, dark_bg_grey);
            _clearLineWith(x, x + line_width, y + 2, '▆', colors.BLACK, dark_bg_grey);

            y += 1;

            if (i == chosen) {
                _ = _drawStr(x, y, endx, "▎", .{}, .{ .fg = 0xffd700, .bg = colors.BG_GREY });
            }

            const fg = if (i == chosen) colors.WHITE else colors.percentageOf(colors.GREY, darkening);
            y = _drawStr(x + 1, y, endx, " {} - {s}", .{ i, name }, .{ .fg = fg, .bg = dark_bg_grey });

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
                    => if (chosen < options.len - 1) {
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
                    'j', 'h' => if (chosen < options.len - 1) {
                        chosen += 1;
                    },
                    'k', 'l' => if (chosen > 0) {
                        chosen -= 1;
                    },
                    '0'...'9' => {
                        const c: usize = ev.ch - '0';
                        if (c < options.len) {
                            chosen = c;
                        }
                    },
                    else => {},
                }
            } else unreachable;
        }
    }

    clearScreen();
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

pub fn _getItemDescription(w: io.FixedBufferStream([]u8).Writer, item: Item, linewidth: usize) void {
    const S = struct {
        pub fn append(writer: io.FixedBufferStream([]u8).Writer, comptime fmt: []const u8, args: anytype) void {
            writer.print(fmt, args) catch err.wat();
        }

        pub fn appendChar(writer: io.FixedBufferStream([]u8).Writer, ch: u21, count: usize) void {
            var utf8buf: [4]u8 = undefined;
            const seqlen = std.unicode.utf8Encode(ch, &utf8buf) catch err.wat();
            var i: usize = 0;
            while (i < count) : (i += 1)
                writer.writeAll(utf8buf[0..seqlen]) catch err.wat();
        }
    };

    const shortname = (item.shortName() catch err.wat()).constSlice();

    //S.appendChar(w, ' ', (linewidth / 2) -| (shortname.len / 2));
    S.append(w, "$c{s}$.\n", .{shortname});

    S.append(w, "$G", .{});
    S.appendChar(w, '─', linewidth);
    S.append(w, "$.\n", .{});

    S.append(w, "\n", .{});

    var usable = false;
    var throwable = false;

    switch (item) {
        .Ring => S.append(w, "TODO: ring descriptions.", .{}),
        .Potion => |p| {
            S.append(w, "$ceffects$.:\n", .{});
            switch (p.type) {
                .Gas => |g| S.append(w, "$gGas$. {s}\n", .{gas.Gases[g].name}),
                .Status => |s| S.append(w, "$gTmp$. {s}\n", .{s.string(state.player)}),
                .Custom => S.append(w, "TODO: describe this potion\n", .{}),
            }
            usable = true;
            throwable = true;
        },
        .Projectile => |p| {
            const dmg = p.damage orelse @as(usize, 0);
            S.append(w, "$cdamage$.: {}\n", .{dmg});
            switch (p.effect) {
                .Status => |sinfo| {
                    S.append(w, "$ceffects$.:\n", .{});
                    const str = sinfo.status.string(state.player);
                    switch (sinfo.duration) {
                        .Prm => S.append(w, "$gPrm$. {s}\n", .{str}),
                        .Tmp => S.append(w, "$gTmp$. {s} ({})\n", .{ str, sinfo.duration.Tmp }),
                        .Ctx => S.append(w, "$gCtx$. {s}\n", .{str}),
                    }
                    throwable = true;
                },
            }
        },
        .Armor, .Cloak, .Weapon, .Evocable => S.append(w, "TODO", .{}),
        .Boulder, .Prop, .Vial => S.append(w, "$G(This item is useless.)$.", .{}),
    }

    S.append(w, "\n", .{});
    if (usable) S.append(w, "$cSPACE$. to use.\n", .{});
    if (throwable) S.append(w, "$ct$. to throw.\n", .{});
}

pub fn drawInventoryScreen() bool {
    const playerinfo_window = dimensions(.PlayerInfo);
    const main_window = dimensions(.Main);
    const iteminfo_window = dimensions(.EnemyInfo);
    const log_window = dimensions(.Log);

    // TODO: do some tests and figure out what's the practical limit to memory
    // usage, and reduce the buffer's size to that.
    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);

    const moblist = state.createMobList(false, true, state.player.coord.z, fba.allocator());

    const ItemListType = enum { Pack, Equip };

    var desc_scroll: usize = 0;
    var chosen: usize = 0;
    var chosen_itemlist: ItemListType = .Pack;
    var y: isize = 0;

    while (true) {
        clearScreen();

        drawPlayerInfo(moblist.items, playerinfo_window.startx, playerinfo_window.starty, playerinfo_window.endx, playerinfo_window.endy);

        const starty = main_window.starty;
        const x = main_window.startx;
        const endx = main_window.endx;

        const itemlist_len = if (chosen_itemlist == .Pack) state.player.inventory.pack.len else state.player.inventory.equ_slots.len;
        const chosen_item: ?Item = if (chosen_itemlist == .Pack) state.player.inventory.pack.data[chosen] else state.player.inventory.equ_slots[chosen];

        // Draw list of items
        {
            y = starty;
            for (state.player.inventory.pack.constSlice()) |item, i| {
                const startx = x;

                const name = (item.longName() catch err.wat()).constSlice();
                const color = if (i == chosen and chosen_itemlist == .Pack) colors.LIGHT_CONCRETE else colors.GREY;
                const arrow = if (i == chosen and chosen_itemlist == .Pack) ">" else " ";
                _clear_line(startx, endx, y);
                y = _drawStr(startx, y, endx, "{s} {s}", .{ arrow, name }, .{ .fg = color });
            }

            y = starty;
            inline for (@typeInfo(Mob.Inventory.EquSlot).Enum.fields) |slots_f, i| {
                const startx = endx - @divTrunc(endx - x, 2);
                const slot = @intToEnum(Mob.Inventory.EquSlot, slots_f.value);
                const arrow = if (i == chosen and chosen_itemlist == .Equip) ">" else " ";
                const color = if (i == chosen and chosen_itemlist == .Equip) colors.LIGHT_CONCRETE else colors.GREY;

                _clear_line(startx, endx, y);

                if (state.player.inventory.equipment(slot).*) |item| {
                    const name = (item.longName() catch unreachable).constSlice();
                    y = _drawStr(startx, y, endx, "{s} {s: >6}: {s}", .{ arrow, slot.name(), name }, .{ .fg = color });
                } else {
                    y = _drawStr(startx, y, endx, "{s} {s: >6}:", .{ arrow, slot.name() }, .{ .fg = color });
                }
            }
        }

        // Draw item info
        if (chosen_item != null and itemlist_len > 0) {
            const ii_startx = iteminfo_window.startx;
            const ii_endx = iteminfo_window.endx;
            const ii_starty = iteminfo_window.starty;
            const ii_endy = iteminfo_window.endy;

            var ii_y = ii_starty;
            while (ii_y < ii_endy) : (ii_y += 1)
                _clear_line(ii_startx, ii_endx, ii_y);

            var descbuf: [4096]u8 = undefined;
            var descbuf_stream = io.fixedBufferStream(&descbuf);
            _getItemDescription(
                descbuf_stream.writer(),
                chosen_item.?,
                RIGHT_INFO_WIDTH - 1,
            );
            _ = _drawStr(ii_startx, ii_starty, ii_endx, "{s}", .{descbuf_stream.getWritten()}, .{});
        }

        // Draw item description
        if (chosen_item != null) {
            const log_startx = log_window.startx;
            const log_endx = log_window.endx;
            const log_starty = log_window.starty;
            const log_endy = log_window.endy;

            if (itemlist_len > 0) {
                const id = chosen_item.?.id();
                const default_desc = "(Missing description)";
                const desc: []const u8 = if (id) |i_id| state.descriptions.get(i_id) orelse default_desc else default_desc;

                var log_y = log_starty;
                var scroll: usize = 0;
                const linewidth = @intCast(usize, log_endx - log_startx);

                var fold_iter = utils.FoldedTextIterator.init(desc, linewidth);
                while (fold_iter.next()) |line| {
                    if (scroll < desc_scroll) {
                        scroll += 1;
                        continue;
                    }

                    log_y = _drawStr(log_startx, log_y, log_endx, "{s}", .{line}, .{});

                    if (scroll > 0 and log_y == log_starty + 1) {
                        _ = _drawStr(log_endx - 11, log_y - 1, log_endx, " $p-- PgUp --$.", .{}, .{});
                    } else if (log_y == log_endy) {
                        _ = _drawStr(log_endx - 11, log_y - 1, log_endx, " $p-- PgDn --$.", .{}, .{});
                        break;
                    }
                }
            } else {
                _ = _drawStr(log_startx, log_starty, log_endx, "Your inventory is empty.", .{}, .{});
            }
        }

        termbox.tb_present();

        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                switch (ev.key) {
                    termbox.TB_KEY_ARROW_RIGHT => {
                        chosen_itemlist = .Equip;
                        chosen = 0;
                    },
                    termbox.TB_KEY_ARROW_LEFT => {
                        chosen_itemlist = .Pack;
                        chosen = 0;
                    },
                    termbox.TB_KEY_ARROW_DOWN => if (chosen < itemlist_len - 1) {
                        chosen += 1;
                    },
                    termbox.TB_KEY_ARROW_UP => chosen -|= 1,
                    termbox.TB_KEY_PGUP => desc_scroll -|= 1,
                    termbox.TB_KEY_PGDN => desc_scroll += 1,
                    termbox.TB_KEY_CTRL_C,
                    termbox.TB_KEY_CTRL_G,
                    termbox.TB_KEY_ESC,
                    => return false,
                    termbox.TB_KEY_SPACE,
                    termbox.TB_KEY_ENTER,
                    => if (itemlist_len > 0)
                        return player.useItem(chosen),
                    else => {},
                }
                continue;
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    'd' => if (chosen_itemlist == .Pack) {
                        if (itemlist_len > 0)
                            return player.dropItem(chosen);
                    } else {
                        drawAlert("You can't drop that!", .{});
                    },
                    't' => if (chosen_itemlist == .Pack) {
                        if (itemlist_len > 0)
                            return player.throwItem(chosen);
                    } else {
                        drawAlert("You can't throw that!", .{});
                    },
                    'l' => {
                        chosen_itemlist = .Equip;
                        chosen = 0;
                    },
                    'h' => {
                        chosen_itemlist = .Pack;
                        chosen = 0;
                    },
                    'j' => if (chosen < itemlist_len - 1) {
                        chosen += 1;
                    },
                    'k' => if (chosen > 0) {
                        chosen -= 1;
                    },
                    else => {},
                }
            } else unreachable;
        }
    }
}

pub fn drawAlert(comptime fmt: []const u8, args: anytype) void {
    const wind = dimensions(.Log);

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    std.fmt.format(fbs.writer(), fmt, args) catch err.bug("format error!", .{});
    const str = fbs.getWritten();

    const S = struct {
        pub fn _drawBorder(color: u32, d: Dimension) void {
            {
                var y = d.starty;
                while (y <= d.endy) : (y += 1) {
                    var x = d.startx;
                    while (x <= d.endx) : (x += 1) {
                        if (y != d.starty and y != d.endy and x != d.startx and x != d.endx) {
                            continue;
                        }
                        const char: u21 = if (y == d.starty or y == d.endy) '─' else '│';
                        termbox.tb_change_cell(x, y, char, color, colors.BG);
                    }
                }
            }

            // Fix corners
            termbox.tb_change_cell(d.startx, d.starty, '╭', color, colors.BG); // NW
            termbox.tb_change_cell(d.endx, d.starty, '╮', color, colors.BG); // NE
            termbox.tb_change_cell(d.startx, d.endy, '╰', color, colors.BG); // SW
            termbox.tb_change_cell(d.endx, d.endy, '╯', color, colors.BG); // SE

            termbox.tb_present();
        }
    };

    const linewidth = @intCast(usize, (wind.endx - wind.startx) - 4);
    var folded_text = StackBuffer([]const u8, 32).init(null);
    var fold_iter = utils.FoldedTextIterator.init(str, linewidth);
    while (fold_iter.next()) |line| folded_text.append(line) catch err.wat();

    var y: isize = undefined;

    // Clear log window
    y = wind.starty;
    while (y < wind.endy) : (y += 1) _clear_line(wind.startx, wind.endx, y);

    const txt_starty = wind.endy -
        @divTrunc(wind.endy - wind.starty, 2) -
        @intCast(isize, folded_text.len + 1 / 2);
    y = txt_starty;
    for (folded_text.constSlice()) |line| {
        const x = wind.endx -
            @divTrunc(wind.endx - wind.startx, 2) -
            @intCast(isize, line.len / 2);
        y = _drawStr(x, y, wind.endx, "{s}", .{str}, .{});
    }

    termbox.tb_present();

    S._drawBorder(colors.CONCRETE, wind);
    std.time.sleep(150_000_000);
    S._drawBorder(colors.BG, wind);
    std.time.sleep(150_000_000);
    S._drawBorder(colors.CONCRETE, wind);
    std.time.sleep(150_000_000);
    S._drawBorder(colors.BG, wind);
    std.time.sleep(150_000_000);
    S._drawBorder(colors.CONCRETE, wind);
    std.time.sleep(400_000_000);
}

pub fn drawAlertThenLog(comptime fmt: []const u8, args: anytype) void {
    const log_window = dimensions(.Log);
    drawAlert(fmt, args);
    drawLog(log_window.startx, log_window.endx, log_window.starty, log_window.endy);
}
