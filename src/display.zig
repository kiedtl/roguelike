const termbox = @import("termbox.zig");
const state = @import("state.zig");

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
}

pub fn draw() void {
    const playery = @intCast(isize, state.player.y);
    const playerx = @intCast(isize, state.player.x);

    const maxy: isize = termbox.tb_height() - 8;
    const maxx: isize = termbox.tb_width() - 30;
    const minx: isize = 0;
    const miny: isize = 0;

    const starty = playery - @divFloor(maxy, 2);
    const endy = playery + @divFloor(maxy, 2);
    const startx = playerx - @divFloor(maxx, 2);
    const endx = playerx + @divFloor(maxx, 2);

    var cursory: isize = 0;
    var cursorx: isize = 0;

    var y: isize = starty;
    while (y < endy) : (y += 1) {
        var x: isize = startx;
        while (x < endx) : (x += 1) {
            // if out of bounds on the map, draw a black tile
            if (y < 0 or x < 0 or y >= state.HEIGHT or x >= state.WIDTH) {
                termbox.tb_change_cell(cursorx, cursory, ' ', 0xffffff, 0x000000);
                if (cursorx >= maxx) {
                    break;
                } else {
                    cursorx += 1;
                }
                continue;
            }

            const u_x: usize = @intCast(usize, x);
            const u_y: usize = @intCast(usize, y);

            switch (state.dungeon[u_y][u_x].type) {
                .Wall => termbox.tb_change_cell(cursorx, cursory, '▒', 0x404040, 0x808080),
                .Floor => if (state.dungeon[u_y][u_x].mob) |mob| {
                    termbox.tb_change_cell(cursorx, cursory, mob.tile, 0xffffff, 0x121212);
                } else {
                    termbox.tb_change_cell(cursorx, cursory, '·', 0xffffff, 0x121212);
                },
            }

            if (u_y == playery and u_x == playerx)
                termbox.tb_change_cell(cursorx, cursory, '@', 0x0, 0xffffff);

            if (cursorx >= @intCast(usize, maxx)) {
                break;
            } else {
                cursorx += 1;
            }
        }

        if (cursory >= @intCast(usize, maxy)) {
            break;
        } else {
            cursory += 1;
        }
        cursorx = 0;
    }

    termbox.tb_present();
}
