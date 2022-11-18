const build_options = @import("build_options");

const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;

// For the allocator
const state = @import("state.zig");
const colors = @import("colors.zig");

pub const driver: Driver = if (build_options.use_sdl) .SDL2 else .Termbox;
pub const driver_m = if (build_options.use_sdl) @cImport(@cInclude("SDL.h")) else @import("termbox.zig");
pub const font = @import("font.zig");

// tb_shutdown() calls abort() if tb_init() wasn't called, or if tb_shutdown()
// was called twice. Keep track of termbox's state to prevent this.
var is_tb_inited = false;

// SDL2 state
var window: ?*driver_m.SDL_Window = null;
var renderer: ?*driver_m.SDL_Renderer = null;
var texture: ?*driver_m.SDL_Texture = null;
var grid: []Cell = undefined;
var dirty: []bool = undefined;
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

    sch: ?font.Sprite = null,
    sfg: u32 = 0,
    sbg: u32 = 0,

    // Used for Console{}
    // TODO: move to flags
    trans: bool = false,

    fl: Flags = .{},

    pub const Flags = packed struct {
        underline: bool = false,
        strikethrough: bool = false,
        bold: bool = false,
        italic: bool = false,
        wide: bool = false,
    };
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
        _ = mod;
        return switch (kcode) {
            driver_m.SDLK_F1 => .F1,
            driver_m.SDLK_F2 => .F2,
            driver_m.SDLK_F3 => .F3,
            driver_m.SDLK_F4 => .F4,
            driver_m.SDLK_F5 => .F5,
            driver_m.SDLK_F6 => .F6,
            driver_m.SDLK_F7 => .F7,
            driver_m.SDLK_F8 => .F8,
            driver_m.SDLK_F9 => .F9,
            driver_m.SDLK_F10 => .F10,
            driver_m.SDLK_F11 => .F11,
            driver_m.SDLK_F12 => .F12,

            driver_m.SDLK_INSERT => .Insert,
            driver_m.SDLK_DELETE => .Delete,

            driver_m.SDLK_HOME => .Home,
            driver_m.SDLK_END => .End,

            driver_m.SDLK_PAGEUP => .PgUp,
            driver_m.SDLK_PAGEDOWN => .PgDn,

            driver_m.SDLK_LEFT => .ArrowLeft,
            driver_m.SDLK_RIGHT => .ArrowRight,
            driver_m.SDLK_UP => .ArrowUp,
            driver_m.SDLK_DOWN => .ArrowDown,

            driver_m.SDLK_RETURN => .Enter,
            driver_m.SDLK_TAB => .Tab,

            driver_m.SDLK_BACKSPACE => .Backspace,
            driver_m.SDLK_ESCAPE => .Esc,

            else => null,
            // TODO: fix ctrl keys
            // else => if (mod & driver_m.KMOD_CTRL != 0) b: {
            //     break :b @as(?Key, switch (kcode) {
            //         driver_m.SDLK_a => .CtrlA,
            //         driver_m.SDLK_b => .CtrlB,
            //         driver_m.SDLK_c => .CtrlC,
            //         driver_m.SDLK_d => .CtrlD,
            //         driver_m.SDLK_e => .CtrlE,
            //         driver_m.SDLK_f => .CtrlF,
            //         driver_m.SDLK_g => .CtrlG,
            //         // driver_m.SDLK_h => .CtrlH,
            //         // driver_m.SDLK_i => .CtrlI,
            //         driver_m.SDLK_j => .CtrlJ,
            //         driver_m.SDLK_k => .CtrlK,
            //         driver_m.SDLK_l => .CtrlL,
            //         // driver_m.SDLK_m => .CtrlM,
            //         driver_m.SDLK_n => .CtrlN,
            //         driver_m.SDLK_o => .CtrlO,
            //         driver_m.SDLK_p => .CtrlP,
            //         driver_m.SDLK_q => .CtrlQ,
            //         driver_m.SDLK_r => .CtrlR,
            //         driver_m.SDLK_s => .CtrlS,
            //         driver_m.SDLK_t => .CtrlT,
            //         driver_m.SDLK_u => .CtrlU,
            //         driver_m.SDLK_v => .CtrlV,
            //         driver_m.SDLK_w => .CtrlW,
            //         driver_m.SDLK_x => .CtrlX,
            //         driver_m.SDLK_y => .CtrlY,
            //         driver_m.SDLK_z => .CtrlZ,
            //         else => null,
            //     });
            // } else null,
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

            switch (driver_m.tb_init()) {
                0 => is_tb_inited = true,
                driver_m.TB_EFAILED_TO_OPEN_TTY => return error.TTYOpenFailed,
                driver_m.TB_EUNSUPPORTED_TERMINAL => return error.UnsupportedTerminal,
                driver_m.TB_EPIPE_TRAP_ERROR => return error.PipeTrapFailed,
                else => unreachable,
            }

            _ = driver_m.tb_select_output_mode(driver_m.TB_OUTPUT_TRUECOLOR);
            _ = driver_m.tb_set_clear_attributes(driver_m.TB_WHITE, driver_m.TB_BLACK);
        },
        .SDL2 => {
            if (driver_m.SDL_Init(driver_m.SDL_INIT_EVERYTHING) != 0)
                return error.SDL2InitError;

            // TODO: get rid of this
            const SCALE = 2;

            // SDL2 has scaling issues on Windows when using HiDPI displays.
            //
            // Convince Windows it doesn't need to babysit us, we can set our
            // own pixels just fine.
            if (@import("builtin").os.tag == .windows) {
                const win32 = @cImport({
                    @cInclude("windows.h");
                    @cInclude("winuser.h");
                });
                _ = win32.SetProcessDPIAware();
            }

            window = driver_m.SDL_CreateWindow(
                "Oathbreaker", // TODO: move to const
                driver_m.SDL_WINDOWPOS_CENTERED,
                driver_m.SDL_WINDOWPOS_CENTERED,
                @intCast(c_int, preferred_width * font.FONT_WIDTH * SCALE),
                @intCast(c_int, preferred_height * font.FONT_HEIGHT * SCALE),
                driver_m.SDL_WINDOW_SHOWN,
            );
            if (window == null)
                return error.SDL2InitError;

            renderer = driver_m.SDL_CreateRenderer(window, -1, driver_m.SDL_RENDERER_ACCELERATED);
            if (renderer == null)
                return error.SDL2InitError;
            _ = driver_m.SDL_RenderSetScale(renderer, SCALE, SCALE);

            texture = driver_m.SDL_CreateTexture(
                renderer,
                driver_m.SDL_PIXELFORMAT_RGBA8888,
                driver_m.SDL_TEXTUREACCESS_STREAMING,
                @intCast(c_int, preferred_width * font.FONT_WIDTH),
                @intCast(c_int, preferred_height * font.FONT_HEIGHT),
            );
            if (texture == null)
                return error.SDL2InitError;

            grid = try state.GPA.allocator().alloc(Cell, preferred_width * preferred_height);
            mem.set(Cell, grid, .{ .ch = ' ', .fg = 0, .bg = colors.BG });

            dirty = try state.GPA.allocator().alloc(bool, preferred_width * preferred_height);
            mem.set(bool, dirty, true);

            driver_m.SDL_StartTextInput();

            var w: c_int = undefined;
            var h: c_int = undefined;
            const r = driver_m.SDL_GetRendererOutputSize(renderer, &w, &h);
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
            driver_m.tb_shutdown();
            is_tb_inited = false;
        },
        .SDL2 => {
            driver_m.SDL_StopTextInput();
            driver_m.SDL_DestroyTexture(texture);
            driver_m.SDL_DestroyRenderer(renderer);
            driver_m.SDL_DestroyWindow(window);
            driver_m.SDL_Quit();

            state.GPA.allocator().free(grid);
            state.GPA.allocator().free(dirty);
        },
    }
}

// FIXME: handle negative value from tb_width() if called before/after tb_init/tb_shutdown
pub fn width() usize {
    return switch (driver) {
        .Termbox => @intCast(usize, driver_m.tb_width()),
        .SDL2 => return w_width,
    };
}

// FIXME: handle negative value from tb_height() if called before/after tb_init/tb_shutdown
pub fn height() usize {
    return switch (driver) {
        .Termbox => @intCast(usize, driver_m.tb_height()),
        .SDL2 => return w_height,
    };
}

pub fn present() void {
    switch (driver) {
        .Termbox => driver_m.tb_present(),
        .SDL2 => {
            var pixels: [*c]u32 = undefined;
            var pitch: c_int = undefined;

            _ = driver_m.SDL_LockTexture(texture, null, @ptrCast([*c]?*anyopaque, &pixels), &pitch);

            var dy: usize = 0;
            var py: usize = 0;
            while (dy < height()) : (dy += 1) {
                var dx: usize = 0;
                var px: usize = 0;
                while (dx < width()) : (dx += 1) {
                    const cell = grid[dy * width() + dx];
                    const skip_next = cell.fl.wide and grid[dy * w_width + dx + 1].fl.wide;

                    if (!dirty[dy * width() + dx]) {
                        if (skip_next) {
                            dx += 1;
                            px += font.FONT_W_WIDTH;
                        } else {
                            px += font.FONT_WIDTH;
                        }
                        continue;
                    }

                    const ch = if (cell.sch) |sch| @enumToInt(sch) else cell.ch;
                    const bg = if (cell.sch != null and cell.sbg != 0) cell.sbg else cell.bg;
                    const fg = if (cell.sch != null and cell.sbg != 0) cell.sfg else cell.fg;

                    const f_data = if (cell.fl.wide) font.font_w_data else font.font_data;
                    const f_width: usize = if (cell.fl.wide) font.FONT_W_WIDTH else font.FONT_WIDTH;

                    var fy: usize = 0;
                    while (fy < font.FONT_HEIGHT) : (fy += 1) {
                        var fx: usize = 0;
                        while (fx < f_width) : (fx += 1) {
                            const font_ch_y = ((ch - 32) / 16) * font.FONT_HEIGHT;
                            const font_ch_x = ((ch - 32) % 16) * f_width;
                            const font_ch = f_data[(font_ch_y + fy) * (16 * f_width) + font_ch_x + fx];

                            const color = (if (font_ch == 0) bg else colors.percentageOf(fg, @as(usize, font_ch) * 100 / 255)) << 8 | 0xFF;
                            pixels[((py + fy) * (w_width * font.FONT_WIDTH) + (px + fx))] = color;

                            //pixels[(((dy * f_height) + fy) * (w_width * font.FONT_WIDTH) + ((dx * f_width) + fx))] = color;
                        }
                    }

                    if (skip_next)
                        dx += 1;
                    px += f_width;
                }
                py += font.FONT_HEIGHT;
            }

            _ = driver_m.SDL_UnlockTexture(texture);
            _ = driver_m.SDL_RenderClear(renderer);
            _ = driver_m.SDL_RenderCopy(renderer, texture, null, null);
            _ = driver_m.SDL_RenderPresent(renderer);
        },
    }

    mem.set(bool, dirty, false);
}

pub fn setCell(x: usize, y: usize, cell: Cell) void {
    if (x >= width() or y >= height()) {
        return;
    }

    switch (driver) {
        .Termbox => {
            driver_m.tb_change_cell(@intCast(isize, x), @intCast(isize, y), cell.ch, cell.fg, cell.bg);
        },
        .SDL2 => {
            grid[y * width() + x] = cell;
            dirty[y * width() + x] = true;
        },
    }
}

pub fn getCell(x: usize, y: usize) Cell {
    return switch (driver) {
        .Termbox => {
            const tb_buf = driver_m.tb_cell_buffer();
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
            var ev: driver_m.tb_event = undefined;
            const t = if (wait_period) |v| driver_m.tb_peek_event(&ev, @intCast(isize, v)) else driver_m.tb_poll_event(&ev);

            switch (t) {
                0 => return error.NoInput,
                -1 => return error.TermboxError,
                driver_m.TB_EVENT_KEY => {
                    if (ev.ch != 0) {
                        return Event{ .Char = @intCast(u21, ev.ch) };
                    } else if (ev.key != 0) {
                        return switch (ev.key) {
                            driver_m.TB_KEY_SPACE => Event{ .Char = ' ' },
                            else => Event{ .Key = Key.fromTermbox(ev.key) },
                        };
                    } else unreachable;
                },
                driver_m.TB_EVENT_RESIZE => {
                    return Event{ .Resize = .{
                        .new_width = @intCast(usize, ev.w),
                        .new_height = @intCast(usize, ev.h),
                    } };
                },
                driver_m.TB_EVENT_MOUSE => @panic("TODO"),
                else => unreachable,
            }
        },
        .SDL2 => {
            var ev: driver_m.SDL_Event = undefined;

            while (true) {
                const r = if (wait_period) |t| driver_m.SDL_WaitEventTimeout(&ev, @intCast(c_int, t)) else driver_m.SDL_WaitEvent(&ev);

                if (r != 1) {
                    if (wait_period != null) {
                        return error.NoInput;
                    } else {
                        return error.SDL2InputError;
                    }
                }

                switch (ev.type) {
                    driver_m.SDL_QUIT => return .Quit,
                    driver_m.SDL_TEXTINPUT => {
                        const text = ev.text.text[0..try std.unicode.utf8ByteSequenceLength(ev.text.text[0])];
                        return Event{ .Char = try std.unicode.utf8Decode(text) };
                    },
                    driver_m.SDL_KEYDOWN => {
                        const kcode = ev.key.keysym.sym;
                        if (Key.fromSDL(kcode, ev.key.keysym.mod)) |key| {
                            return Event{ .Key = key };
                        } else if (kcode == driver_m.SDLK_SPACE) {
                            return Event{ .Char = ' ' };
                        } else continue;
                    },
                    else => continue,
                }
            }
        },
    }
}
