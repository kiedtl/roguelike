// TODO: rename this module to 'ui'

const std = @import("std");
const math = std.math;

const termbox = @import("termbox.zig");
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
    _ = _draw_string(startx, y, 0xffffff, 0, "{s}", .{description}) catch unreachable;

    var x = startx + @intCast(isize, description.len) + 1;
    const percent = (current * 100) / max;

    if (percent == 0)
        return;

    const bar = @divTrunc((endx - x - 1) * @intCast(isize, percent), 100);
    const bar_end = x + bar;

    while (x < bar_end) : (x += 1)
        termbox.tb_change_cell(x, y, ' ', fg, bg);
}

fn _draw_infopanel(player: *Mob, moblist: *const std.ArrayList(*Mob), startx: isize, starty: isize, endx: isize, endy: isize) void {
    var y = starty;
    while (y < endy) : (y += 1) _clear_line(startx, endx, y);
    y = starty;

    y = _draw_string(startx, y, 0xffffff, 0, "@: You", .{}) catch unreachable;

    _draw_bar(y, startx, endx, @floatToInt(usize, player.HP), @floatToInt(usize, player.max_HP), "HP", 0xffffff, 0);
    y += 1;
    _draw_bar(y, startx, endx, player.noise, 20, "NS", 0x232faa, 0);
    y += 1;
    y = _draw_string(startx, y, 0xffffff, 0, "score: {}", .{state.score}) catch unreachable;
    y += 2;

    for (moblist.items) |mob| {
        _clear_line(startx, endx, y);
        _clear_line(startx, endx, y + 1);

        // Draw the tile manually, _draw_string complains of invalid UTF-8 otherwise
        //var tile: [4]u8 = undefined;
        //_ = std.unicode.utf8Encode(mob.tile, &tile) catch unreachable;
        termbox.tb_change_cell(startx, y, mob.tile, 0xffffff, 0);

        y = _draw_string(startx + 1, y, 0xffffff, 0, ": {} ({})", .{ mob.species, mob.activity_description() }) catch unreachable;

        _draw_bar(y, startx, endx, @floatToInt(usize, mob.HP), @floatToInt(usize, mob.max_HP), "HP", 0xffffff, 0);
        y += 2;
    }
}

fn _draw_messages(startx: isize, endx: isize, starty: isize, endy: isize) void {
    if (state.messages.items.len == 0)
        return;

    var y: isize = starty;
    var i: usize = state.messages.items.len - 1;
    while (i > 0 and y < endy) : (i -= 1) {
        const msg = state.messages.items[i].msg;
        y = _draw_string(startx, y, 0xffffff, 0, "{}", .{msg}) catch unreachable;
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
                if (state.player.canHear(coord)) |noise| {
                    const blue = @intCast(u32, math.clamp(noise * 30, 30, 255));
                    const bg: u32 = if (state.player.memory.contains(coord)) 0x101010 else 0;
                    const color = 0x23 << 16 | 0x2f << 8 | blue;
                    termbox.tb_change_cell(cursorx, cursory, '?', color, bg);
                } else {
                    if (state.player.memory.contains(coord)) {
                        const tile = @as(u32, state.player.memory.get(coord) orelse unreachable);
                        termbox.tb_change_cell(cursorx, cursory, tile, 0x3f3f3f, 0x101010);
                    } else {
                        termbox.tb_change_cell(cursorx, cursory, ' ', 0xffffff, 0);
                    }
                }
                continue;
            }

            switch (state.dungeon.at(coord).type) {
                .Wall => termbox.tb_change_cell(cursorx, cursory, '#', 0x505050, 0x9e9e9e),
                .Floor => if (state.dungeon.at(coord).mob) |mob| {
                    if (state.player.coord.eq(coord) and _mobs_can_see(&moblist, coord))
                        is_player_watched = true;

                    var color: u32 = 0x1e1e1e;

                    if (mob.current_pain() > 0.0) {
                        var red = @floatToInt(u32, mob.current_pain() * 0x7ff);
                        color = math.clamp(red, 0x00, 0xee) << 16;
                    }

                    if (mob.is_dead) {
                        color = 0xdc143c;
                    }

                    termbox.tb_change_cell(cursorx, cursory, mob.tile, 0xffffff, color);
                } else if (state.dungeon.at(coord).surface) |surfaceitem| {
                    const tile = switch (surfaceitem) {
                        .Machine => |m| m.tile,
                        .Prop => |p| p.tile,
                    };

                    termbox.tb_change_cell(cursorx, cursory, tile, 0xffffff, 0x1e1e1e);
                } else {
                    var can_mob_see = _mobs_can_see(&moblist, coord);
                    if (state.player.coord.eq(coord) and can_mob_see)
                        is_player_watched = can_mob_see;

                    const tile: u32 = if (can_mob_see) '·' else ' ';
                    var bg: u32 = if (state.dungeon.at(coord).marked) 0x454545 else 0x1e1e1e;
                    termbox.tb_change_cell(cursorx, cursory, tile, 0xffffff, bg);
                },
            }
        }
    }

    const player_bg: u32 = if (is_player_watched) 0x4682b4 else 0xffffff;
    termbox.tb_change_cell(playerx - startx, playery - starty, '@', 0, player_bg);

    _draw_infopanel(state.player, &moblist, maxx, 1, termbox.tb_width(), termbox.tb_height() - 1);
    _draw_messages(0, maxx, maxy, termbox.tb_height() - 1);

    termbox.tb_present();
    state.reset_marks();
}
