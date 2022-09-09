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
