const std = @import("std");
const builtin = @import("builtin");

const c_imp = @cImport({
    @cInclude("png.h");
    @cInclude("stdio.h"); // for fdopen()
});

const err = @import("err.zig");
const colors = @import("colors.zig");
const state = @import("state.zig");

pub const FONT_HEIGHT = 16; //8;
pub const FONT_WIDTH = 8; //7;
pub const FONT_FALLBACK_GLYPH = 0x7F;
pub const FONT_PATH = "./data/font/spleen.png";
pub const Sprite = @import("sprites.zig").Sprite;

pub var font_data: []u8 = undefined;

var png_ctx: ?*c_imp.png_struct = null;
var png_info: ?*c_imp.png_info = null;

fn _png_err(_: ?*c_imp.png_struct, msg: [*c]const u8) callconv(.C) void {
    err.fatal("libPNG tantrum: {s}", .{msg});
}

pub fn loadFontData() void {
    png_ctx = c_imp.png_create_read_struct(c_imp.PNG_LIBPNG_VER_STRING, null, _png_err, null);
    png_info = c_imp.png_create_info_struct(png_ctx);

    if (png_ctx == null or png_info == null) {
        err.fatal("Failed to read font data: libPNG error", .{});
    }

    // var font_f = std.fs.cwd().openFile(FONT_PATH, .{ .read = true }) catch |e|
    //     err.fatal("Failed to read font data: {s}", .{@errorName(e)});
    // defer font_f.close();

    // png_init_io call doesn't compile on Windows if we use std.fs, due to
    // File.Handle being *anyopaque instead of whatever png_FILE_p is.
    //
    // So, we directly call the C apis instead.

    const font_f = c_imp.fopen(FONT_PATH, "rb");
    if (font_f == null) {
        err.fatal("Failed to read font data (unknown error)", .{});
    }

    c_imp.png_init_io(png_ctx, font_f);
    c_imp.png_set_strip_alpha(png_ctx);
    c_imp.png_set_scale_16(png_ctx);
    c_imp.png_set_expand(png_ctx);
    c_imp.png_read_png(png_ctx, png_info, c_imp.PNG_TRANSFORM_GRAY_TO_RGB, null);

    const width = c_imp.png_get_image_width(png_ctx, png_info);
    const height = c_imp.png_get_image_height(png_ctx, png_info);

    font_data = state.GPA.allocator().alloc(u8, width * height) catch err.oom();

    const rows = c_imp.png_get_rows(png_ctx, png_info);
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const rgb: u32 =
                @intCast(u32, rows[y][(x * 3) + 0]) << 16 |
                @intCast(u32, rows[y][(x * 3) + 1]) << 8 |
                @intCast(u32, rows[y][(x * 3) + 2]);
            font_data[y * width + x] = @intCast(u8, colors.filterGrayscale(rgb) >> 16 & 0xFF);
        }
    }
}

pub fn freeFontData() void {
    c_imp.png_destroy_read_struct(&png_ctx, &png_info, null);
    state.GPA.allocator().free(font_data);
}
