// Posters and books

const std = @import("std");
const mem = std.mem;
const meta = std.meta;

const err = @import("err.zig");
const tsv = @import("tsv.zig");
const LinkedList = @import("list.zig").LinkedList;

pub const Poster = struct {
    // linked list stuff
    __next: ?*Poster = null,
    __prev: ?*Poster = null,

    // What level this poster belongs on. E.g., "PRI" "LAB" "VLT"
    level: []u8,

    // Contents.
    text: []u8,

    // Mapgen state, storing number of times this poster has been placed.
    placement_counter: usize = 0,

    pub fn deinit(self: *const Poster, alloc: mem.Allocator) void {
        alloc.free(self.level);
        alloc.free(self.text);
    }
};

pub const PosterList = LinkedList(Poster);

pub var posters: PosterList = undefined;

pub fn readPosters(alloc: mem.Allocator) void {
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
        posters = @TypeOf(posters).init(alloc);
        for (result.unwrap().items) |poster| posters.append(poster) catch err.wat();
        std.log.info("Loaded {} posters.", .{result.unwrap().items.len});
        result.unwrap().deinit();
    }
}
