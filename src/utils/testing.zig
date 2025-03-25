// Testing utilities, including snapshot testing inspired by Tigerbeetle.

const builtin = @import("builtin");
const std = @import("std");

const mem = std.mem;
const assert = std.debug.assert;
const testing = std.testing;

pub const Snap = struct {
    comptime {
        assert(builtin.is_test);
    }

    source: std.builtin.SourceLocation,
    bytes: []const u8,

    pub fn update(self: *const Snap, new: []const u8) !void {
        if (!std.process.hasEnvVarConstant("SNAP_UPDATE"))
            return;

        const file = try (try std.fs.cwd().openDir("src", .{}))
            .openFile(self.source.file, .{ .mode = .read_write });
        const data = try file.readToEndAlloc(testing.allocator, 65535);
        defer testing.allocator.free(data);

        try file.seekTo(0);
        try file.setEndPos(0);

        var file_lines = mem.splitScalar(u8, data, '\n');

        var l: usize = 1;
        while (file_lines.next()) |line| : (l += 1) {
            try file.writeAll(line);
            try file.writeAll("\n");
            if (l == self.source.line)
                break;
        }

        var lines = mem.splitScalar(u8, new, '\n');
        while (lines.next()) |line| {
            try file.writeAll("        \\\\");
            try file.writeAll(line);
            try file.writeAll("\n");
        }

        var past = false;
        while (file_lines.next()) |line| {
            const trimmed = mem.trimLeft(u8, line, " ");
            if (!past and mem.startsWith(u8, trimmed, "\\\\"))
                continue
            else
                past = true;
            try file.writeAll(line);
            try file.writeAll("\n");
        }

        std.log.err("Test updated. Refusing to continue", .{});
        std.process.exit(1);
    }
};

pub fn expectEqual(val: []const u8, s: Snap) !void {
    testing.expect(mem.eql(u8, val, s.bytes)) catch |e| {
        try s.update(val);
        return e;
    };
}

pub fn snap(loc: std.builtin.SourceLocation, val: []const u8) Snap {
    return .{ .source = loc, .bytes = val };
}

// Utility methods to convert stuff into a string that can be used with
// snapshot-testing.

pub fn mapToString(TH: comptime_int, TW: comptime_int, map: *const [TH][TW]u8) []const u8 {
    const S = struct {
        pub var buf: [TH * TW + TH]u8 = undefined; // "+ TH" -- add space for newlines
    };
    var i: usize = 0;
    for (0..TH) |y| {
        @memcpy(S.buf[i .. i + TW], map[y][0..]);
        S.buf[i + TW] = '\n';
        i += TW + 1;
    }
    return S.buf[0 .. i - 1]; // Trim last newline
}
