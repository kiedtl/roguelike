// Posters and books

const std = @import("std");
const mem = std.mem;
const meta = std.meta;

const tsv = @import("tsv.zig");

pub const Poster = struct {
    level: []u8,
    text: []u8,
    placement_counter: usize = 0,

    pub fn deinit(self: *const Poster, alloc: *mem.Allocator) void {
        alloc.free(self.level);
        alloc.free(self.text);
    }
};

pub const PosterArrayList = std.ArrayList(Poster);

pub var posters: PosterArrayList = undefined;

pub fn readPosters(alloc: *mem.Allocator) void {
    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("posters.tsv", .{
        .read = true,
        .lock = .None,
    }) catch unreachable;

    var rbuf: [8192]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        Poster,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "level", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "text", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
        },
        .{ .level = undefined, .text = undefined },
        rbuf[0..read],
        alloc,
    );

    if (!result.is_ok()) {
        std.log.err(
            "Cannot read props: {} (line {}, field {})",
            .{ result.Err.type, result.Err.context.lineno, result.Err.context.field },
        );
    } else {
        posters = result.unwrap();
        std.log.warn("Loaded {} posters.", .{posters.items.len});
    }
}
