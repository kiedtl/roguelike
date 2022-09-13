const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

// For the allocator
const state = @import("state.zig");
const colors = @import("colors.zig");

pub const sdl = @cImport(@cInclude("SDL.h"));
pub const termbox = @import("termbox.zig");
pub const font = @import("font.zig");

pub const driver: Driver = .SDL2;

// tb_shutdown() calls abort() if tb_init() wasn't called, or if tb_shutdown()
// was called twice. Keep track of termbox's state to prevent this.
var is_tb_inited = false;

// SDL2 state
var window: ?*sdl.SDL_Window = null;
var renderer: ?*sdl.SDL_Renderer = null;
var grid: []Cell = undefined;
var w_height: usize = undefined;
var w_width: usize = undefined;

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
    Quit,
};

// Enum values are in sync with termbox TB_KEY_* constants
pub const Key = enum(u16) {
    F1 = (0xFFFF - 0),
    F2 = (0xFFFF - 1),
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
    //Space = 0x20,
    Backspace2 = 0x7F,
    //Ctrl_8= 0x7F, // clash with 'BACKSPACE2'

    pub fn fromTermbox(v: u16) Key {
        // FIXME: handle crash here
        return @intToEnum(Key, v);
    }

    // TODO: some aren't handled, e.g. CtrlTilde
    pub fn fromSDL(kcode: i32, mod: i32) ?Key {
        return switch (kcode) {
            sdl.SDLK_F1 => .F1,
            sdl.SDLK_F2 => .F2,
            sdl.SDLK_F3 => .F3,
            sdl.SDLK_F4 => .F4,
            sdl.SDLK_F5 => .F5,
            sdl.SDLK_F6 => .F6,
            sdl.SDLK_F7 => .F7,
            sdl.SDLK_F8 => .F8,
            sdl.SDLK_F9 => .F9,
            sdl.SDLK_F10 => .F10,
            sdl.SDLK_F11 => .F11,
            sdl.SDLK_F12 => .F12,

            sdl.SDLK_INSERT => .Insert,
            sdl.SDLK_DELETE => .Delete,

            sdl.SDLK_HOME => .Home,
            sdl.SDLK_END => .End,

            sdl.SDLK_PAGEUP => .PgUp,
            sdl.SDLK_PAGEDOWN => .PgDn,

            sdl.SDLK_LEFT => .ArrowLeft,
            sdl.SDLK_RIGHT => .ArrowRight,
            sdl.SDLK_UP => .ArrowUp,
            sdl.SDLK_DOWN => .ArrowDown,

            sdl.SDLK_RETURN => .Enter,
            sdl.SDLK_TAB => .Tab,

            sdl.SDLK_BACKSPACE => .Backspace,
            sdl.SDLK_ESCAPE => .Esc,

            else => if (mod & sdl.KMOD_CTRL == sdl.KMOD_CTRL) b: {
                break :b @as(?Key, switch (kcode) {
                    sdl.SDLK_a => .CtrlA,
                    sdl.SDLK_b => .CtrlB,
                    sdl.SDLK_c => .CtrlC,
                    sdl.SDLK_d => .CtrlD,
                    sdl.SDLK_e => .CtrlE,
                    sdl.SDLK_f => .CtrlF,
                    sdl.SDLK_g => .CtrlG,
                    // sdl.SDLK_h => .CtrlH,
                    // sdl.SDLK_i => .CtrlI,
                    sdl.SDLK_j => .CtrlJ,
                    sdl.SDLK_k => .CtrlK,
                    sdl.SDLK_l => .CtrlL,
                    // sdl.SDLK_m => .CtrlM,
                    sdl.SDLK_n => .CtrlN,
                    sdl.SDLK_o => .CtrlO,
                    sdl.SDLK_p => .CtrlP,
                    sdl.SDLK_q => .CtrlQ,
                    sdl.SDLK_r => .CtrlR,
                    sdl.SDLK_s => .CtrlS,
                    sdl.SDLK_t => .CtrlT,
                    sdl.SDLK_u => .CtrlU,
                    sdl.SDLK_v => .CtrlV,
                    sdl.SDLK_w => .CtrlW,
                    sdl.SDLK_x => .CtrlX,
                    sdl.SDLK_y => .CtrlY,
                    sdl.SDLK_z => .CtrlZ,
                    else => null,
                });
            } else null,
        };
    }
};

const InitErr = error{
    AlreadyInitialized,
    TTYOpenFailed,
    UnsupportedTerminal,
    PipeTrapFailed,
    SDL2InitError,
    SDL2GetDimensionsError,
} || mem.Allocator.Error;

pub fn init(preferred_width: usize, preferred_height: usize) InitErr!void {
    switch (driver) {
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
        .SDL2 => {
            if (sdl.SDL_Init(sdl.SDL_INIT_EVERYTHING) != 0)
                return error.SDL2InitError;

            // TODO: get rid of this
            const SCALE = 1;

            window = sdl.SDL_CreateWindow(
                "Oathbreaker", // TODO: move to const
                sdl.SDL_WINDOWPOS_CENTERED,
                sdl.SDL_WINDOWPOS_CENTERED,
                @intCast(c_int, preferred_width * font.FONT_WIDTH * SCALE),
                @intCast(c_int, preferred_height * font.FONT_HEIGHT * SCALE),
                sdl.SDL_WINDOW_SHOWN,
            );
            if (window == null)
                return error.SDL2InitError;

            renderer = sdl.SDL_CreateRenderer(window, -1, sdl.SDL_RENDERER_SOFTWARE);
            if (renderer == null)
                return error.SDL2InitError;
            _ = sdl.SDL_RenderSetScale(renderer, SCALE, SCALE);

            grid = try state.GPA.allocator().alloc(Cell, preferred_width * preferred_height);
            mem.set(Cell, grid, .{ .ch = ' ', .fg = 0, .bg = colors.BG });

            sdl.SDL_StartTextInput();

            var w: c_int = undefined;
            var h: c_int = undefined;
            const r = sdl.SDL_GetRendererOutputSize(renderer, &w, &h);
            if (r < 0) {
                return error.SDL2GetDimensionsError;
            }
            w_width = @intCast(usize, w) / font.FONT_WIDTH / SCALE;
            w_height = @intCast(usize, h) / font.FONT_HEIGHT / SCALE;
        },
    }
}

pub fn deinit() !void {
    switch (driver) {
        .Termbox => {
            if (!is_tb_inited)
                return error.AlreadyDeinitialized;
            termbox.tb_shutdown();
            is_tb_inited = false;
        },
        .SDL2 => {
            sdl.SDL_StopTextInput();
            sdl.SDL_DestroyRenderer(renderer);
            sdl.SDL_DestroyWindow(window);
            sdl.SDL_Quit();

            state.GPA.allocator().free(grid);
        },
    }
}

// FIXME: handle negative value from tb_width() if called before/after tb_init/tb_shutdown
pub fn width() usize {
    return switch (driver) {
        .Termbox => @intCast(usize, termbox.tb_width()),
        .SDL2 => return w_width,
    };
}

// FIXME: handle negative value from tb_height() if called before/after tb_init/tb_shutdown
pub fn height() usize {
    return switch (driver) {
        .Termbox => @intCast(usize, termbox.tb_height()),
        .SDL2 => return w_height,
    };
}

pub fn present() void {
    switch (driver) {
        .Termbox => termbox.tb_present(),
        .SDL2 => {
            _ = sdl.SDL_RenderClear(renderer);

            var dy: usize = 0;
            while (dy < height()) : (dy += 1) {
                var dx: usize = 0;
                while (dx < width()) : (dx += 1) {
                    const cell = grid[dy * width() + dx];
                    const ch = if (cell.ch < 32 or cell.ch > 126) font.FONT_FALLBACK_GLYPH else cell.ch;

                    var fy: usize = 0;
                    while (fy < font.FONT_HEIGHT) : (fy += 1) {
                        var fx: usize = 0;
                        while (fx < font.FONT_WIDTH) : (fx += 1) {
                            // const font_ch = font.font_data[((ch - 32) * font.FONT_HEIGHT) + fy][fx];
                            // const font_ch = font.font_data[(ch * font.FONT_HEIGHT) + (fy * font.FONT_WIDTH + fx)];

                            const font_ch_y = ((ch - 32) / 16) * font.FONT_HEIGHT;
                            const font_ch_x = ((ch - 32) % 16) * font.FONT_WIDTH;
                            const font_ch = font.font_data[(font_ch_y + fy) * (16 * font.FONT_WIDTH) + font_ch_x + fx];

                            const color = if (font_ch == 0) cell.bg else cell.fg;
                            //const color = colors.percentageOf(whole_color, @as(usize, font_ch) * 255 / 100);

                            _ = sdl.SDL_SetRenderDrawColor(
                                renderer,
                                @intCast(u8, color >> 16 & 0xFF),
                                @intCast(u8, color >> 8 & 0xFF),
                                @intCast(u8, color >> 0 & 0xFF),
                                0,
                            );
                            _ = sdl.SDL_RenderDrawPoint(
                                renderer,
                                @intCast(c_int, (dx * font.FONT_WIDTH) + fx),
                                @intCast(c_int, (dy * font.FONT_HEIGHT) + fy),
                            );
                        }
                    }
                }
            }

            _ = sdl.SDL_RenderPresent(renderer);
        },
    }
}

pub fn setCell(x: usize, y: usize, cell: Cell) void {
    if (x >= width() or y >= height()) {
        return;
    }

    switch (driver) {
        .Termbox => {
            termbox.tb_change_cell(@intCast(isize, x), @intCast(isize, y), cell.ch, cell.fg, cell.bg);
        },
        .SDL2 => grid[y * width() + x] = cell,
    }
}

pub fn getCell(x: usize, y: usize) Cell {
    return switch (driver) {
        .Termbox => {
            const tb_buf = termbox.tb_cell_buffer();
            const tb_old = tb_buf[y * width() + x];
            return .{
                .ch = tb_old.ch,
                .fg = tb_old.fg,
                .bg = tb_old.bg,
            };
        },
        .SDL2 => return grid[y * width() + x],
    };
}

pub fn waitForEvent(wait_period: ?usize) !Event {
    switch (driver) {
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
        .SDL2 => {
            var ev: sdl.SDL_Event = undefined;

            while (true) {
                const r = if (wait_period) |t| sdl.SDL_WaitEventTimeout(&ev, @intCast(c_int, t)) else sdl.SDL_WaitEvent(&ev);

                if (r != 1) {
                    if (wait_period != null) {
                        return error.NoInput;
                    } else {
                        return error.SDL2InputError;
                    }
                }

                switch (ev.type) {
                    sdl.SDL_QUIT => return .Quit,
                    sdl.SDL_TEXTINPUT => {
                        const text = ev.text.text[0..try std.unicode.utf8ByteSequenceLength(ev.text.text[0])];
                        std.log.info("text: {s}", .{ev.text.text[0..]});
                        return Event{ .Char = try std.unicode.utf8Decode(text) };
                    },
                    sdl.SDL_KEYDOWN => {
                        const kcode = ev.key.keysym.sym;
                        std.log.info("key: {s}", .{sdl.SDL_GetKeyName(kcode)});
                        if (Key.fromSDL(kcode, ev.key.keysym.mod)) |key| {
                            return Event{ .Key = key };
                        } else continue;
                    },
                    else => continue,
                }
            }
        },
    }
}
