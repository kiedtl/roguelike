// Posters and books

const std = @import("std");
const mem = std.mem;

pub const Poster = struct {
    level: []const u8,
    text: []const u8,
    placement_counter: usize = 0,

    pub const ParseError = error{
        ExpectedTextField,
        ExpectedLevelField,
        InvalidLevelIdent,
    } || mem.Allocator.Error;

    pub fn init(level: []const u8, text: []const u8, alloc: *mem.Allocator) ParseError!Poster {
        if (level.len != 3) return error.InvalidLevelIdent;

        const level_ptr = try alloc.alloc(u8, 3);
        mem.copy(u8, level_ptr, level);

        const text_ptr = try alloc.alloc(u8, text.len);
        mem.copy(u8, text_ptr, text);

        return Poster{ .level = level_ptr, .text = text_ptr };
    }

    pub fn deinit(self: *const Poster, alloc: *mem.Allocator) void {
        alloc.free(self.level);
        alloc.free(self.text);
    }
};

pub const PosterArrayList = std.ArrayList(Poster);

pub fn readPosters(alloc: *mem.Allocator, buf: *PosterArrayList) void {
    const S = struct {
        fn _error(err: Poster.ParseError, lineno: usize) void {
            const err_str = switch (err) {
                Poster.ParseError.ExpectedLevelField => "expected level field",
                Poster.ParseError.ExpectedTextField => "expected text field",
                Poster.ParseError.InvalidLevelIdent => "invalid level identifier",
                Poster.ParseError.OutOfMemory => "hit alt-f4 a few times please",
            };
            std.log.warn("Line {}: Unable to parse poster: {}", .{ lineno, err_str });
        }
    };

    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("posters.tsv", .{
        .read = true,
        .lock = .None,
    }) catch unreachable;

    var rbuf: [8192]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const poster_data = rbuf[0..read];
    var lines = mem.split(poster_data, "\n");
    var lineno: usize = 0;
    while (lines.next()) |line| {
        // ignore blank/comment lines
        if (line.len == 0 or line[0] == '#') {
            lineno += 1;
            continue; // ignore blank lines
        }

        var fields = mem.split(line, "\t");

        const f_level = fields.next() orelse {
            S._error(error.ExpectedLevelField, lineno);
            continue;
        };
        const f_text = fields.next() orelse {
            S._error(error.ExpectedTextField, lineno);
            continue;
        };

        const poster = Poster.init(f_level, f_text, alloc) catch |e| {
            S._error(e, lineno);
            continue;
        };
        buf.append(poster) catch unreachable;

        lineno += 1;
    }

    std.log.warn("Loaded {} posters.", .{buf.items.len});
}
