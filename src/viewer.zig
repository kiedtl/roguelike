const state = @import("state.zig");
const termbox = @import("termbox.zig");
usingnamespace @import("types.zig");

fn display(level: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            var t = Tile.displayAs(Coord.new2(level, x, y));
            termbox.tb_put_cell(@intCast(isize, x), @intCast(isize, y), &t);
        }
    }
    termbox.tb_present();
}

pub fn main() void {
    var level: usize = PLAYER_STARTING_LEVEL;

    while (true) {
        display(level);

        var ev: termbox.tb_event = undefined;
        const t = termbox.tb_poll_event(&ev);

        if (t == -1) @panic("Fatal termbox error");

        if (t == termbox.TB_EVENT_KEY) {
            if (ev.key != 0) {
                if (ev.key == termbox.TB_KEY_CTRL_C) {
                    break;
                }
            } else if (ev.ch != 0) {
                switch (ev.ch) {
                    '<' => if (level > 0) {
                        level -= 1;
                    },
                    '>' => if (level < (LEVELS - 1)) {
                        level += 1;
                    },
                    else => {},
                }
            } else unreachable;
        }
    }
}
