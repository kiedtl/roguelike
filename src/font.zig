const std = @import("std");
const builtin = @import("builtin");

const c_imp = @cImport({
    @cInclude("png.h");
    @cInclude("stdio.h"); // for fdopen()
});

const err = @import("err.zig");
const colors = @import("colors.zig");
const state = @import("state.zig");

pub const Sprite = @import("sprites.zig").Sprite;

pub const FONT_FALLBACK_GLYPH = 0x7F;

pub const FONT_HEIGHT = 16;
pub const FONT_WIDTH = 8;
pub const FONT_PATH = "./data/font/spleen.png";
pub var font_data: []u8 = undefined;

pub const FONT_W_WIDTH = 16;
pub const FONT_W_PATH = "./data/font/spleen-wide.png";
pub var font_w_data: []u8 = undefined;

fn _png_err(_: ?*c_imp.png_struct, msg: [*c]const u8) callconv(.C) void {
    err.fatal("libPNG tantrum: {s}", .{msg});
}

pub fn loadFontsData() void {
    loadFontData(FONT_PATH, &font_data);
    loadFontData(FONT_W_PATH, &font_w_data);
}

fn loadFontData(path: [*c]const u8, databuf: *[]u8) void {
    var png_ctx = c_imp.png_create_read_struct(c_imp.PNG_LIBPNG_VER_STRING, null, _png_err, null);
    var png_info = c_imp.png_create_info_struct(png_ctx);
    defer c_imp.png_destroy_read_struct(&png_ctx, &png_info, null);

    if (png_ctx == null or png_info == null) {
        err.fatal("{s}: Failed to read font data: libPNG error", .{path});
    }

    // var font_f = std.fs.cwd().openFile(FONT_PATH, .{ .read = true }) catch |e|
    //     err.fatal("Failed to read font data: {s}", .{@errorName(e)});
    // defer font_f.close();

    // png_init_io call doesn't compile on Windows if we use std.fs, due to
    // File.Handle being *anyopaque instead of whatever png_FILE_p is.
    //
    // So, we directly call the C apis instead.

    const font_f = c_imp.fopen(path, "rb");
    if (font_f == null) {
        err.fatal("{s}: Failed to read font data (unknown error)", .{path});
    }

    c_imp.png_init_io(png_ctx, font_f);
    c_imp.png_set_strip_alpha(png_ctx);
    c_imp.png_set_scale_16(png_ctx);
    c_imp.png_set_expand(png_ctx);
    c_imp.png_read_png(png_ctx, png_info, c_imp.PNG_TRANSFORM_GRAY_TO_RGB, null);

    const width = c_imp.png_get_image_width(png_ctx, png_info);
    const height = c_imp.png_get_image_height(png_ctx, png_info);

    databuf.* = state.gpa.allocator().alloc(u8, width * height) catch err.oom();

    const rows = c_imp.png_get_rows(png_ctx, png_info);
    var y: usize = 0;
    while (y < height) : (y += 1) {
        var x: usize = 0;
        while (x < width) : (x += 1) {
            const rgb: u32 =
                @intCast(u32, rows[y][(x * 3) + 0]) << 16 |
                @intCast(u32, rows[y][(x * 3) + 1]) << 8 |
                @intCast(u32, rows[y][(x * 3) + 2]);
            databuf.*[y * width + x] = @intCast(u8, colors.filterGrayscale(rgb) >> 16 & 0xFF);
        }
    }
}

pub fn freeFontData() void {
    state.gpa.allocator().free(font_data);
    state.gpa.allocator().free(font_w_data);
}
