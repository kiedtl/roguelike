// TODO: rename this module to 'ui'

const std = @import("std");
const math = std.math;

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

fn _draw_bar(y: isize, startx: isize, endx: isize, current: usize, max: usize, description: []const u8, bg: u32, fg: u32) void {
    const labelx = startx + 1;
    _ = _draw_string(labelx, y, 0xffffff, 0, "{s}", .{description}) catch unreachable;

    var barx = startx;
    const percent = (current * 100) / max;
    if (percent == 0) return;
    const bar = @divTrunc((endx - barx - 1) * @intCast(isize, percent), 100);
    const bar_end = barx + bar;
    while (barx < bar_end) : (barx += 1) termbox.tb_change_cell(barx, y, ' ', fg, bg);

    const bar_len = bar_end - startx;
    const description2 = description[0..math.min(@intCast(usize, bar_len), description.len)];
    _ = _draw_string(labelx, y, 0xffffff, bg, "{s}", .{description2}) catch unreachable;
}

fn _draw_infopanel(player: *Mob, moblist: *const std.ArrayList(*Mob), startx: isize, starty: isize, endx: isize, endy: isize) void {
    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty;

    y = _draw_string(startx, y, 0xffffff, 0, "@: You", .{}) catch unreachable;

    _draw_bar(y, startx, endx, @floatToInt(usize, player.HP), @floatToInt(usize, player.max_HP), "Health", 0x232faa, 0);
    y += 1;
    //_draw_bar(y, startx, endx, player.noise, 20, "Noise", 0x232faa, 0); // TODO
    y += 1;
    y = _draw_string(startx, y, 0xffffff, 0, "score: {}", .{state.score}) catch unreachable;
    y += 2;

    for (moblist.items) |mob| {
        if (mob.is_dead) continue;

        _clear_line(startx, endx, y);
        _clear_line(startx, endx, y + 1);

        // Draw the tile manually, _draw_string complains of invalid UTF-8 otherwise
        // (FIXME)
        //
        //var tile: [4]u8 = undefined;
        //_ = std.unicode.utf8Encode(mob.tile, &tile) catch unreachable;
        termbox.tb_change_cell(startx, y, mob.tile, 0xffffff, 0);

        y = _draw_string(startx + 1, y, 0xffffff, 0, ": {} ({})", .{ mob.species, mob.activity_description() }) catch unreachable;

        _draw_bar(y, startx, endx, @floatToInt(usize, mob.HP), @floatToInt(usize, mob.max_HP), "Health", 0x232faa, 0);
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
        const col = if (msg.turn == state.ticks or i == first)
            state.messages.items[i].type.color()
        else
            0xa0a0a0;
        y = _draw_string(startx, y, col, 0, "{}", .{msg.msg}) catch unreachable;
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

            // if player can't see area, draw a blank/grey tile, depending on
            // what they saw last there
            if (!state.player.cansee(coord)) {
                if (state.player.memory.contains(coord)) {
                    var tile = state.player.memory.get(coord) orelse unreachable;

                    if (state.player.canHear(coord)) |noise| {
                        const blue = @intCast(u32, math.clamp(noise * 30, 30, 255));
                        tile.fg = 0x23 << 16 | 0x2f << 8 | blue;
                        tile.ch = '!';
                    }

                    tile.fg = utils.darkenColor(tile.fg, 3);
                    tile.bg = utils.darkenColor(tile.bg, 3);
                    tile.ch = if (state.dungeon.at(coord).type == .Wall) ' ' else tile.ch;

                    termbox.tb_put_cell(cursorx, cursory, &tile);
                } else {
                    termbox.tb_change_cell(cursorx, cursory, ' ', 0xffffff, 0);
                }

                continue;
            }

            const material = state.dungeon.at(coord).material;
            var tile = Tile.displayAs(coord);

            switch (state.dungeon.at(coord).type) {
                .Wall => {},
                .Floor => {
                    if (state.dungeon.at(coord).mob) |mob| {
                        if (state.player.coord.eq(coord) and _mobs_can_see(&moblist, coord))
                            is_player_watched = true;
                    } else if (state.dungeon.at(coord).surface) |surfaceitem| {} else {
                        if (state.player.canHear(coord)) |noise| {
                            const blue = @intCast(u32, math.clamp(noise * 30, 30, 255));
                            const color = 0x23 << 16 | 0x2f << 8 | blue;
                            tile.ch = '!';
                            tile.fg = color;
                        } else if (_mobs_can_see(&moblist, coord)) {
                            var can_mob_see = true;
                            if (state.player.coord.eq(coord))
                                is_player_watched = can_mob_see;
                            tile.ch = '·';
                        }
                    }
                },
            }

            termbox.tb_put_cell(cursorx, cursory, &tile);
        }
    }

    if (!state.player.is_dead) {
        const player_bg: u32 = if (is_player_watched) 0x4682b4 else 0xffffff;
        termbox.tb_change_cell(playerx - startx, playery - starty, '@', 0, player_bg);
    }

    _draw_infopanel(state.player, &moblist, maxx, 1, termbox.tb_width(), termbox.tb_height() - 1);
    _draw_messages(0, maxx, maxy, termbox.tb_height() - 1);

    termbox.tb_present();
    state.reset_marks();
}
