// Key constants. See also struct tb_event's key field.
// These are a safe subset of terminfo keys, which exist on all popular
// terminals. Termbox uses only them to stay truly portable.
pub const TB_KEY_F1: u16 = (0xFFFF - 0);
pub const TB_KEY_F2: u16 = (0xFFFF - 1);
pub const TB_KEY_F3: u16 = (0xFFFF - 2);
pub const TB_KEY_F4: u16 = (0xFFFF - 3);
pub const TB_KEY_F5: u16 = (0xFFFF - 4);
pub const TB_KEY_F6: u16 = (0xFFFF - 5);
pub const TB_KEY_F7: u16 = (0xFFFF - 6);
pub const TB_KEY_F8: u16 = (0xFFFF - 7);
pub const TB_KEY_F9: u16 = (0xFFFF - 8);
pub const TB_KEY_F10: u16 = (0xFFFF - 9);
pub const TB_KEY_F11: u16 = (0xFFFF - 10);
pub const TB_KEY_F12: u16 = (0xFFFF - 11);
pub const TB_KEY_INSERT: u16 = (0xFFFF - 12);
pub const TB_KEY_DELETE: u16 = (0xFFFF - 13);
pub const TB_KEY_HOME: u16 = (0xFFFF - 14);
pub const TB_KEY_END: u16 = (0xFFFF - 15);
pub const TB_KEY_PGUP: u16 = (0xFFFF - 16);
pub const TB_KEY_PGDN: u16 = (0xFFFF - 17);
pub const TB_KEY_ARROW_UP: u16 = (0xFFFF - 18);
pub const TB_KEY_ARROW_DOWN: u16 = (0xFFFF - 19);
pub const TB_KEY_ARROW_LEFT: u16 = (0xFFFF - 20);
pub const TB_KEY_ARROW_RIGHT: u16 = (0xFFFF - 21);
pub const TB_KEY_MOUSE_LEFT: u16 = (0xFFFF - 22);
pub const TB_KEY_MOUSE_RIGHT: u16 = (0xFFFF - 23);
pub const TB_KEY_MOUSE_MIDDLE: u16 = (0xFFFF - 24);
pub const TB_KEY_MOUSE_RELEASE: u16 = (0xFFFF - 25);
pub const TB_KEY_MOUSE_WHEEL_UP: u16 = (0xFFFF - 26);
pub const TB_KEY_MOUSE_WHEEL_DOWN: u16 = (0xFFFF - 27);

// These are all ASCII code points below SPACE character and a BACKSPACE key.
pub const TB_KEY_CTRL_TILDE: u16 = 0x00;
pub const TB_KEY_CTRL_2: u16 = 0x00; // clash with 'CTRL_TILDE'
pub const TB_KEY_CTRL_A: u16 = 0x01;
pub const TB_KEY_CTRL_B: u16 = 0x02;
pub const TB_KEY_CTRL_C: u16 = 0x03;
pub const TB_KEY_CTRL_D: u16 = 0x04;
pub const TB_KEY_CTRL_E: u16 = 0x05;
pub const TB_KEY_CTRL_F: u16 = 0x06;
pub const TB_KEY_CTRL_G: u16 = 0x07;
pub const TB_KEY_BACKSPACE: u16 = 0x08;
pub const TB_KEY_CTRL_H: u16 = 0x08; // clash with 'CTRL_BACKSPACE'
pub const TB_KEY_TAB: u16 = 0x09;
pub const TB_KEY_CTRL_I: u16 = 0x09; // clash with 'TAB'
pub const TB_KEY_CTRL_J: u16 = 0x0A;
pub const TB_KEY_CTRL_K: u16 = 0x0B;
pub const TB_KEY_CTRL_L: u16 = 0x0C;
pub const TB_KEY_ENTER: u16 = 0x0D;
pub const TB_KEY_CTRL_M: u16 = 0x0D; // clash with 'ENTER'
pub const TB_KEY_CTRL_N: u16 = 0x0E;
pub const TB_KEY_CTRL_O: u16 = 0x0F;
pub const TB_KEY_CTRL_P: u16 = 0x10;
pub const TB_KEY_CTRL_Q: u16 = 0x11;
pub const TB_KEY_CTRL_R: u16 = 0x12;
pub const TB_KEY_CTRL_S: u16 = 0x13;
pub const TB_KEY_CTRL_T: u16 = 0x14;
pub const TB_KEY_CTRL_U: u16 = 0x15;
pub const TB_KEY_CTRL_V: u16 = 0x16;
pub const TB_KEY_CTRL_W: u16 = 0x17;
pub const TB_KEY_CTRL_X: u16 = 0x18;
pub const TB_KEY_CTRL_Y: u16 = 0x19;
pub const TB_KEY_CTRL_Z: u16 = 0x1A;
pub const TB_KEY_ESC: u16 = 0x1B;
pub const TB_KEY_CTRL_LSQ_BRACKET: u16 = 0x1B; // clash with 'ESC'
pub const TB_KEY_CTRL_3: u16 = 0x1B; // clash with 'ESC'
pub const TB_KEY_CTRL_4: u16 = 0x1C;
pub const TB_KEY_CTRL_BACKSLASH: u16 = 0x1C; // clash with 'CTRL_4'
pub const TB_KEY_CTRL_5: u16 = 0x1D;
pub const TB_KEY_CTRL_RSQ_BRACKET: u16 = 0x1D; // clash with 'CTRL_5'
pub const TB_KEY_CTRL_6: u16 = 0x1E;
pub const TB_KEY_CTRL_7: u16 = 0x1F;
pub const TB_KEY_CTRL_SLASH: u16 = 0x1F; // clash with 'CTRL_7'
pub const TB_KEY_CTRL_UNDERSCORE: u16 = 0x1F; // clash with 'CTRL_7'
pub const TB_KEY_SPACE: u16 = 0x20;
pub const TB_KEY_BACKSPACE2: u16 = 0x7F;
pub const TB_KEY_CTRL_8: u16 = 0x7F; // clash with 'BACKSPACE2'

// These are non-existing ones.
// pub const TB_KEY_CTRL_1 clash with '1'
// pub const TB_KEY_CTRL_9 clash with '9'
// pub const TB_KEY_CTRL_0 clash with '0'

// Alt modifier constant, see tb_event.mod field and tb_select_input_mode function.
// Mouse-motion modifier
pub const TB_MOD_ALT: usize = 0x01;
pub const TB_MOD_MOTION: usize = 0x02;

// Colors (see struct tb_cell's fg and bg fields).
pub const TB_DEFAULT: usize = 0x00;
pub const TB_BLACK: usize = 0x01;
pub const TB_RED: usize = 0x02;
pub const TB_GREEN: usize = 0x03;
pub const TB_YELLOW: usize = 0x04;
pub const TB_BLUE: usize = 0x05;
pub const TB_MAGENTA: usize = 0x06;
pub const TB_CYAN: usize = 0x07;
pub const TB_WHITE: usize = 0x08;

//  Attributes, it is possible to use multiple attributes by combining them
//  using bitwise OR ('|'). Although, colors cannot be combined. But you can
//  combine attributes and a single color. See also struct tb_cell's fg and bg
//  fields.
pub const TB_BOLD: usize = 0x01000000;
pub const TB_UNDERLINE: usize = 0x02000000;
pub const TB_REVERSE: usize = 0x04000000;

// A cell, single conceptual entity on the terminal screen. The terminal screen
// is basically a 2d array of cells. It has the following fields:
// - 'ch' is a unicode character
// - 'fg' foreground color and attributes
// - 'bg' background color and attributes
pub const tb_cell = extern struct {
    ch: u32 = ' ',
    fg: u32 = 0xffffff,
    bg: u32 = 0x000000,
};

pub const TB_EVENT_KEY: isize = 1;
pub const TB_EVENT_RESIZE: isize = 2;
pub const TB_EVENT_MOUSE: isize = 3;

// An event, single interaction from the user. The 'mod' and 'ch' fields are
// valid if 'type' is TB_EVENT_KEY. The 'w' and 'h' fields are valid if 'type'
// is TB_EVENT_RESIZE. The 'x' and 'y' fields are valid if 'type' is
// TB_EVENT_MOUSE. The 'key' field is valid if 'type' is either TB_EVENT_KEY
// or TB_EVENT_MOUSE. The fields 'key' and 'ch' are mutually exclusive; only
// one of them can be non-zero at a time.
pub const tb_event = extern struct {
    type: u8,
    mod: u8, // modifiers to either 'key' or 'ch' below
    key: u16, // one of the TB_KEY_* constants
    ch: u32, // unicode character
    w: i32,
    h: i32,
    x: i32,
    y: i32,
};

//  Error codes returned by tb_init(). All of them are self-explanatory, except
//  the pipe trap error. Termbox uses unix pipes in order to deliver a message
//  from a signal handler (SIGWINCH) to the main event reading loop. Honestly in
//  most cases you should just check the returned code as < 0.
pub const TB_EUNSUPPORTED_TERMINAL: isize = -1;
pub const TB_EFAILED_TO_OPEN_TTY: isize = -2;
pub const TB_EPIPE_TRAP_ERROR: isize = -3;

// Initializes the termbox library. This function should be called before any
// other functions. Function tb_init is same as tb_init_file("/dev/tty"). After
// successful initialization, the library must be finalized using the
// tb_shutdown() function.
pub extern fn tb_init() isize;
pub extern fn tb_init_file(name: [*c]u8) isize;
pub extern fn tb_shutdown() void;

// Returns the size of the internal back buffer (which is the same as
// terminal's window size in characters). The internal buffer can be resized
// after tb_clear() or tb_present() function calls. Both dimensions have an
// unspecified negative value when called before tb_init() or after
// tb_shutdown().
pub extern fn tb_width() isize;
pub extern fn tb_height() isize;

// Clears the internal back buffer using TB_DEFAULT color or the
// color/attributes set by tb_set_clear_attributes() function.
pub extern fn tb_clear() void;
pub extern fn tb_set_clear_attributes(fg: u32, bg: u32) void;

// Synchronizes the internal back buffer with the terminal.
pub extern fn tb_present() void;

pub const TB_HIDE_CURSOR: isize = -1;

// Sets the position of the cursor. Upper-left character is (0, 0). If you pass
// TB_HIDE_CURSOR as both coordinates, then the cursor will be hidden. Cursor
// is hidden by default.
pub extern fn tb_set_cursor(cx: isize, cy: isize) void;

// Changes cell's parameters in the internal back buffer at the specified
// position.
pub extern fn tb_put_cell(x: isize, y: isize, cell: [*c]tb_cell) void;
pub extern fn tb_change_cell(x: isize, y: isize, ch: u32, fg: u32, bg: u32) void;

// Copies the buffer from 'cells' at the specified position, assuming the
// buffer is a two-dimensional array of size ('w' x 'h'), represented as a
// one-dimensional buffer containing lines of cells starting from the top.
// (DEPRECATED: use tb_cell_buffer() instead and copy memory on your own)
// pub extern fn tb_blit(int x, int y, int w, int h, cells: [*c]tb_cell) int;

// Returns a pointer to internal cell back buffer. You can get its dimensions
// using tb_width() and tb_height() functions. The pointer stays valid as long
// as no tb_clear() and tb_present() calls are made. The buffer is
// one-dimensional buffer containing lines of cells starting from the top.
pub extern fn tb_cell_buffer(void) [*c]tb_cell;

pub const TB_INPUT_CURRENT: usize = 0; // 000
pub const TB_INPUT_ESC: usize = 1; // 001
pub const TB_INPUT_ALT: usize = 2; // 010
pub const TB_INPUT_MOUSE: usize = 4; // 100

//  Sets the termbox input mode. Termbox has two input modes:
//  1. Esc input mode.
//    When ESC sequence is in the buffer and it doesn't match any known
//    ESC sequence => ESC means TB_KEY_ESC.
//  2. Alt input mode.
//    When ESC sequence is in the buffer and it doesn't match any known
//    sequence => ESC enables TB_MOD_ALT modifier for the next keyboard event.
//
//  You can also apply TB_INPUT_MOUSE via bitwise OR operation to either of the
//  modes (e.g. TB_INPUT_ESC | TB_INPUT_MOUSE). If none of the main two modes
//  were set, but the mouse mode was, TB_INPUT_ESC mode is used. If for some
//  reason you've decided to use (TB_INPUT_ESC | TB_INPUT_ALT) combination, it
//  will behave as if only TB_INPUT_ESC was selected.
//
//  If 'mode' is TB_INPUT_CURRENT, it returns the current input mode.
//
//  Default termbox input mode is TB_INPUT_ESC.
pub extern fn tb_select_input_mode(mode: isize) isize;

pub const TB_OUTPUT_CURRENT: isize = 0;
pub const TB_OUTPUT_NORMAL: isize = 1;
pub const TB_OUTPUT_256: isize = 2;
pub const TB_OUTPUT_216: isize = 3;
pub const TB_OUTPUT_GRAYSCALE: isize = 4;
pub const TB_OUTPUT_TRUECOLOR: isize = 5;

// Sets the termbox output mode. Termbox has three output options:
// 1. TB_OUTPUT_NORMAL     => [1..8]
//   This mode provides 8 different colors:
//   black, red, green, yellow, blue, magenta, cyan, white
//   Shortcut: TB_BLACK, TB_RED, ...
//   Attributes: TB_BOLD, TB_UNDERLINE, TB_REVERSE
//
//   Example usage:
//       tb_change_cell(x, y, '@', TB_BLACK | TB_BOLD, TB_RED);
//
// 2. TB_OUTPUT_256        => [0..256]
//   In this mode you can leverage the 256 terminal mode:
//   0x00 - 0x07: the 8 colors as in TB_OUTPUT_NORMAL
//   0x08 - 0x0f: TB_* | TB_BOLD
//   0x10 - 0xe7: 216 different colors
//   0xe8 - 0xff: 24 different shades of grey
//
//   Example usage:
//       tb_change_cell(x, y, '@', 184, 240);
//       tb_change_cell(x, y, '@', 0xb8, 0xf0);
//
// 3. TB_OUTPUT_216        => [0..216]
//   This mode supports the 3rd range of the 256 mode only.
//   But you don't need to provide an offset.
//
// 4. TB_OUTPUT_GRAYSCALE  => [0..23]
//   This mode supports the 4th range of the 256 mode only.
//   But you dont need to provide an offset.
//
// 5. TB_OUTPUT_TRUECOLOR  => [0x000000..0xFFFFFF]
//   This mode supports 24-bit true color. Format is 0xRRGGBB.
//
// Execute build/src/demo/output to see its impact on your terminal.
//
// If 'mode' is TB_OUTPUT_CURRENT, it returns the current output mode.
//
// Default termbox output mode is TB_OUTPUT_NORMAL.
pub extern fn tb_select_output_mode(mode: isize) isize;

// Wait for an event up to 'timeout' milliseconds and fill the 'event'
// structure with it, when the event is available. Returns the type of the
// event (one of TB_EVENT_* constants) or -1 if there was an error or 0 in case
// there were no event during 'timeout' period.
pub extern fn tb_peek_event(event: [*c]tb_event, timeout: isize) isize;

// Wait for an event forever and fill the 'event' structure with it, when the
// event is available. Returns the type of the event (one of TB_EVENT_
// constants) or -1 if there was an error.
pub extern fn tb_poll_event(event: [*c]tb_event) isize;

// Utility utf8 functions.
//#define TB_EOF -1
//int utf8_char_length(char c);
//int utf8_char_to_unicode(uint32_t* out, const char* c);
//int utf8_unicode_to_char(char* out, uint32_t c);
