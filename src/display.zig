const std = @import("std");

const termbox = @import("termbox.zig");

// tb_shutdown() calls abort() if tb_init() wasn't called, or if tb_shutdown()
// was called twice. Keep track of termbox's state to prevent this.
var is_tb_inited = false;

pub const Driver = enum {
    Termbox,
    SDL2,
};

pub const Cell = struct {
    fg: u32 = 0,
    bg: u32 = 0,
    ch: u32 = ' ', // TODO: change to u21

    // fl: Flags = .{},

    // pub const Flags = packed struct {
    //     underline: bool = false,
    //     strikethrough: bool = false,
    //     bold: bool = false,
    //     italic: bool = false,
    // };
};

pub const Event = union(enum) {
    Resize: struct { new_width: usize, new_height: usize },
    Key: Key,
    Char: u21,
};

// Enum values are in sync with termbox TB_KEY_* constants
pub const Key = enum(u16) {
    F1 = (0xFFFF - 0),
    f2 = (0xFFFF - 1),
    F3 = (0xFFFF - 2),
    F4 = (0xFFFF - 3),
    F5 = (0xFFFF - 4),
    F6 = (0xFFFF - 5),
    F7 = (0xFFFF - 6),
    F8 = (0xFFFF - 7),
    F9 = (0xFFFF - 8),
    F10 = (0xFFFF - 9),
    F11 = (0xFFFF - 10),
    F12 = (0xFFFF - 11),
    Insert = (0xFFFF - 12),
    Delete = (0xFFFF - 13),
    Home = (0xFFFF - 14),
    End = (0xFFFF - 15),
    PgUp = (0xFFFF - 16),
    PgDn = (0xFFFF - 17),
    ArrowUp = (0xFFFF - 18),
    ArrowDown = (0xFFFF - 19),
    ArrowLeft = (0xFFFF - 20),
    ArrowRight = (0xFFFF - 21),

    CtrlTilde = 0x00,
    //Ctrl_2= 0x00, // clash with 'CTRL_TILDE'
    CtrlA = 0x01,
    CtrlB = 0x02,
    CtrlC = 0x03,
    CtrlD = 0x04,
    CtrlE = 0x05,
    CtrlF = 0x06,
    CtrlG = 0x07,
    Backspace = 0x08,
    //Ctrl_h= 0x08, // clash with 'CTRL_BACKSPACE'
    Tab = 0x09,
    //Ctrl_i= 0x09, // clash with 'TAB'
    CtrlJ = 0x0A,
    CtrlK = 0x0B,
    CtrlL = 0x0C,
    Enter = 0x0D,
    //Ctrl_m= 0x0D, // clash with 'ENTER'
    CtrlN = 0x0E,
    CtrlO = 0x0F,
    CtrlP = 0x10,
    CtrlQ = 0x11,
    CtrlR = 0x12,
    CtrlS = 0x13,
    CtrlT = 0x14,
    CtrlU = 0x15,
    CtrlV = 0x16,
    CtrlW = 0x17,
    CtrlX = 0x18,
    CtrlY = 0x19,
    CtrlZ = 0x1A,
    Esc = 0x1B,
    //Ctrl_lsq_bracket= 0x1B, // clash with 'ESC'
    //Ctrl_3= 0x1B, // clash with 'ESC'
    Ctrl4 = 0x1C,
    //Ctrl_backslash= 0x1C, // clash with 'CTRL_4'
    Ctrl5 = 0x1D,
    //Ctrl_rsq_bracket= 0x1D, // clash with 'CTRL_5'
    Ctrl6 = 0x1E,
    Ctrl7 = 0x1F,
    //Ctrl_slash= 0x1F, // clash with 'CTRL_7'
    //Ctrl_underscore= 0x1F, // clash with 'CTRL_7'
    Space = 0x20,
    Backspace2 = 0x7F,
    //Ctrl_8= 0x7F, // clash with 'BACKSPACE2'

    pub fn fromTermbox(v: u16) Key {
        // FIXME: handle crash here
        return @intToEnum(Key, v);
    }
};

pub fn init(d: Driver) !void {
    switch (d) {
        .Termbox => {
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
        },
        .SDL2 => {},
    }
}

pub fn deinit(d: Driver) !void {
    switch (d) {
        .Termbox => {
            if (!is_tb_inited)
                return error.AlreadyDeinitialized;
            termbox.tb_shutdown();
            is_tb_inited = false;
        },
        .SDL2 => unreachable,
    }
}

// FIXME: handle negative value from tb_width() if called before/after tb_init/tb_shutdown
pub fn width(d: Driver) usize {
    return switch (d) {
        .Termbox => @intCast(usize, termbox.tb_width()),
        .SDL2 => unreachable,
    };
}

// FIXME: handle negative value from tb_height() if called before/after tb_init/tb_shutdown
pub fn height(d: Driver) usize {
    return switch (d) {
        .Termbox => @intCast(usize, termbox.tb_height()),
        .SDL2 => unreachable,
    };
}

pub fn present(d: Driver) void {
    switch (d) {
        .Termbox => termbox.tb_present(),
        .SDL2 => unreachable,
    }
}

pub fn setCell(d: Driver, x: usize, y: usize, cell: Cell) void {
    switch (d) {
        .Termbox => {
            termbox.tb_change_cell(@intCast(isize, x), @intCast(isize, y), cell.ch, cell.fg, cell.bg);
        },
        .SDL2 => unreachable,
    }
}

pub fn getCell(d: Driver, x: usize, y: usize) Cell {
    return switch (d) {
        .Termbox => {
            const tb_buf = termbox.tb_cell_buffer();
            const tb_old = tb_buf[y * width(.Termbox) + x];
            return .{
                .ch = tb_old.ch,
                .fg = tb_old.fg,
                .bg = tb_old.bg,
            };
        },
        .SDL2 => unreachable,
    };
}

pub fn waitForEvent(d: Driver, wait_period: ?usize) !Event {
    switch (d) {
        .Termbox => {
            var ev: termbox.tb_event = undefined;
            const t = if (wait_period) |v| termbox.tb_peek_event(&ev, @intCast(isize, v)) else termbox.tb_poll_event(&ev);

            switch (t) {
                0 => return error.NoInput,
                -1 => return error.TermboxError,
                termbox.TB_EVENT_KEY => {
                    if (ev.ch != 0) {
                        return Event{ .Char = @intCast(u21, ev.ch) };
                    } else if (ev.key != 0) {
                        return switch (ev.key) {
                            termbox.TB_KEY_SPACE => Event{ .Char = ' ' },
                            else => Event{ .Key = Key.fromTermbox(ev.key) },
                        };
                    } else unreachable;
                },
                termbox.TB_EVENT_RESIZE => {
                    return Event{ .Resize = .{
                        .new_width = @intCast(usize, ev.w),
                        .new_height = @intCast(usize, ev.h),
                    } };
                },
                termbox.TB_EVENT_MOUSE => @panic("TODO"),
                else => unreachable,
            }
        },
        .SDL2 => unreachable,
    }
}
