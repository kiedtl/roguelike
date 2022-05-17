const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const math = std.math;
const meta = std.meta;
const mem = std.mem;
const unicode = std.unicode;
const enums = std.enums;

const state = @import("state.zig");
const err = @import("err.zig");
const rng = @import("rng.zig");
const buffer = @import("buffer.zig");
const types = @import("types.zig");

const Coord = types.Coord;
const Direction = types.Direction;
const Tile = types.Tile;
const TileType = types.TileType;
const Mob = types.Mob;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const StackBuffer = buffer.StackBuffer;

pub fn findFirstNeedlePtr(
    haystack: anytype,
    ctx: anytype,
    func: fn (*meta.Elem(@TypeOf(haystack)), @TypeOf(ctx)) bool,
) ?*meta.Elem(@TypeOf(haystack)) {
    return for (haystack) |*straw| {
        if ((func)(straw, ctx)) {
            break straw;
        }
    } else null;
}

pub fn findFirstNeedle(
    haystack: anytype,
    ctx: anytype,
    func: fn (meta.Elem(@TypeOf(haystack)), @TypeOf(ctx)) bool,
) ?meta.Elem(@TypeOf(haystack)) {
    return for (haystack) |straw| {
        if ((func)(straw, ctx)) {
            break straw;
        }
    } else null;
}

// A utility struct to get around the fact that std.fmt puts a "+" on signed
// integers if padding is used.
//
// Cheers to tsmanner_ on #zig@libera.chat for this tip:
//
// > 2022-04-12 18:28:16  <tsmanner_> cot: Yeah, that makes sense. If you're
// > feeling motivated, the check-if-positive-maybe-cast when printing them could
// > be put in a single function, or contained inside a `struct SignedFormatter {
// > value: isize, }` that implements that logic in it's format method.
//
pub const SignedFormatter = struct {
    v: isize,

    pub fn format(value: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        if (value.v >= 0) {
            try std.fmt.formatType(@intCast(usize, value.v), fmt, options, writer, 0);
        } else {
            try std.fmt.formatType(value.v, fmt, options, writer, 0);
        }
    }
};

// Extract the value of enums.directEnumArrayLen indirectly, since that method
// is private >_>
//
// (Assumes max_unused_slots == 0)
//
pub fn directEnumArrayLen(comptime E: type) usize {
    return enums.directEnumArray(E, void, 0, undefined).len;
}

pub fn getFieldByEnumPtr(comptime E: type, comptime V: type, s: anytype, v: E) V {
    inline for (@typeInfo(E).Enum.fields) |enumv| {
        const e = @intToEnum(E, enumv.value);
        if (e == v) return &@field(s, @tagName(e));
    }
    unreachable;
}

pub fn getFieldByEnum(comptime E: type, s: anytype, v: E) @typeInfo(@TypeOf(s)).Struct.fields[0].field_type {
    inline for (@typeInfo(E).Enum.fields) |enumv| {
        const e = @intToEnum(E, enumv.value);
        if (e == v) return @field(s, @tagName(e));
    }
    unreachable;
}

pub fn getNearestCorpse(me: *Mob) ?Coord {
    var buf = StackBuffer(Coord, 32).init(null);

    search: for (me.fov) |row, y| for (row) |cell, x| {
        if (buf.isFull()) break :search;

        if (cell == 0) continue;
        const coord = Coord.new2(me.coord.z, x, y);

        if (state.dungeon.at(coord).surface) |s| switch (s) {
            .Corpse => |_| buf.append(coord) catch err.wat(),
            else => {},
        };
    };

    if (buf.len == 0) return null;

    // Sort according to distance.
    const _sortFunc = struct {
        fn _fn(mob: *Mob, a: Coord, b: Coord) bool {
            return a.distance(mob.coord) > b.distance(mob.coord);
        }
    };
    std.sort.insertionSort(Coord, buf.slice(), me, _sortFunc._fn);

    return buf.last().?;
}

pub fn hasClearLOF(from: Coord, to: Coord) bool {
    const line = from.drawLine(to, state.mapgeometry);
    return for (line.constSlice()) |c| {
        if (!c.eq(from) and !c.eq(to) and
            !state.is_walkable(c, .{ .right_now = true, .only_if_breaks_lof = true }))
        {
            break false;
        }
    } else true;
}

pub fn percentOf(comptime T: type, x: T, percent: T) T {
    return x * percent / 100;
}

pub fn used(slice: anytype) rt: {
    const SliceType = @TypeOf(slice);
    const ChildType = std.meta.Elem(SliceType);

    break :rt switch (@typeInfo(SliceType)) {
        .Pointer => |p| if (p.is_const) []const ChildType else []ChildType,
        .Array => []const ChildType,
        else => @compileError("Expected slice, got " ++ @typeName(SliceType)),
    };
} {
    const sentry = sentinel(@TypeOf(slice)) orelse return slice[0..];
    var i: usize = 0;
    while (slice[i] != sentry) i += 1;
    return slice[0..i];
}

pub fn findById(haystack: anytype, _needle: anytype) ?usize {
    const needle = used(_needle);

    for (haystack) |straw, i| {
        const id = used(straw.id);
        if (mem.eql(u8, needle, id)) return i;
    }

    return null;
}

pub fn sentinel(comptime T: type) switch (@typeInfo(T)) {
    .Pointer => |p| switch (@typeInfo(p.child)) {
        .Pointer, .Array => @TypeOf(sentinel(p.child)),
        else => if (p.sentinel) |s| @TypeOf(s) else ?p.child,
    },
    .Array => |a| if (a.sentinel) |s| ?@TypeOf(s) else ?a.child,
    else => @compileError("Expected array or slice, found " ++ @typeName(T)),
} {
    return switch (@typeInfo(T)) {
        .Pointer => |p| switch (@typeInfo(p.child)) {
            .Pointer, .Array => sentinel(p.child),
            else => if (p.sentinel) |s| s else null,
        },
        .Array => |a| if (a.sentinel) |s| s else null,
        else => @compileError("Expected array or slice, found " ++ @typeName(T)),
    };
}

// TODO: remove all uses of this, untyped null-terminated arrays should never
// be used.
//
pub fn copyZ(dest: anytype, src: anytype) void {
    const DestElem = meta.Elem(@TypeOf(dest));
    const SourceChild = meta.Elem(@TypeOf(src));
    if (DestElem != SourceChild) {
        const d = @typeName(@TypeOf(dest));
        const s = @typeName(@TypeOf(src));
        @compileError("Expected source to be " ++ d ++ ", got " ++ s);
    }

    const srclen = mem.sliceTo(src, 0).len;

    assert(dest.len >= srclen);

    var i: usize = 0;
    while (i < srclen) : (i += 1)
        dest[i] = src[i];

    if (sentinel(@TypeOf(dest))) |s| {
        assert((dest.len - 1) > srclen);
        dest[srclen] = s;
    }
}

pub fn hasPatternMatch(coord: Coord, patterns: []const []const u8) bool {
    return findPatternMatch(coord, patterns) != null;
}

pub fn findPatternMatch(coord: Coord, patterns: []const []const u8) ?usize {
    const coords = [_]?Coord{
        coord.move(.NorthWest, state.mapgeometry),
        coord.move(.North, state.mapgeometry),
        coord.move(.NorthEast, state.mapgeometry),
        coord.move(.West, state.mapgeometry),
        coord,
        coord.move(.East, state.mapgeometry),
        coord.move(.SouthWest, state.mapgeometry),
        coord.move(.South, state.mapgeometry),
        coord.move(.SouthEast, state.mapgeometry),
    };

    patterns: for (patterns) |pattern, pattern_i| {
        var i: usize = 0;
        while (i < 9) : (i += 1) {
            if (pattern[i] == '?') continue;

            var tiletype: TileType = .Wall;

            if (coords[i]) |c| {
                tiletype = state.dungeon.at(c).type;
                if (state.dungeon.at(c).surface) |s| switch (s) {
                    .Machine => |m| if (!m.powered_walkable and !m.unpowered_walkable) {
                        tiletype = .Wall;
                    },
                    .Prop => |p| if (!p.walkable) {
                        tiletype = .Wall;
                    },
                    .Corpse, .Container, .Poster, .Stair => tiletype = .Wall,
                };
            }

            const typech: u21 = if (tiletype == .Floor) '.' else '#';
            if (typech != pattern[i]) continue :patterns;
        }

        // we have a match if we haven't continued to the next iteration
        // by this point
        return pattern_i;
    }

    // no match found
    return null;
}

// FIXME: split long words along '-'
// FIXME: add tests to ensure that long words aren't put on separate lines with
//        nothing on the previous line, like the fold implementation in lurch
// FIXME: stress-test on abnormal inputs (empty input, input full of whitespace, etc)
pub const FoldedTextIterator = struct {
    str: []const u8,
    max_width: usize,
    last_space: ?usize = null,
    index: usize = 0,

    const Self = @This();

    pub fn init(str: []const u8, w: usize) Self {
        return .{ .str = str, .max_width = w };
    }

    pub fn next(self: *Self, line_buf: anytype) ?[]const u8 {
        if (self.index >= self.str.len) {
            return null;
        }

        line_buf.clear();

        self.last_space = null;
        var cur_width: usize = 0;

        while (self.index < self.str.len and cur_width < self.max_width) {
            const seqlen = unicode.utf8ByteSequenceLength(self.str[self.index]) catch unreachable;
            const char = unicode.utf8Decode(self.str[self.index .. self.index + seqlen]) catch unreachable;
            const slice = self.str[self.index..(self.index + seqlen)];

            switch (char) {
                // Skip our custom formatting directives.
                '$' => {
                    const esc_slice = self.str[self.index..(self.index + seqlen + 1)];
                    line_buf.appendSlice(esc_slice) catch unreachable;
                    self.index += seqlen + 1;
                    continue;
                },

                ' ', '\n', '\t', '\x0b', '\x0c', '\x0d' => {
                    // We've found some whitespace. If we're at the beginning
                    // of a line, ignore it (unless it's a newline); otherwise,
                    // save the current index.
                    if (char != '\n' and line_buf.len == 0 and self.index != 0) {
                        self.index += seqlen;
                        continue;
                    }

                    self.last_space = self.index;

                    if (char == '\n') {
                        if (self.index != 0 and self.str[self.index - 1] == '\n') {
                            self.index += seqlen;
                            break;
                        } else {
                            self.index += seqlen;
                            if (line_buf.len > 0) {
                                line_buf.append(' ') catch unreachable;
                            }
                            continue;
                        }
                    }
                },
                else => {},
            }

            self.index += seqlen;
            line_buf.appendSlice(slice) catch unreachable;
            cur_width += 1;
        }

        // If we broke out of the loop because we ran over the line limit,
        // backup to the last space.
        if (cur_width >= self.max_width) {
            if (self.last_space) |spc| {
                line_buf.resizeTo(line_buf.len - (self.index - spc));
                self.index = spc;
                self.last_space = null;
            }
        }

        return line_buf.constSlice();
    }
};

// tests {{{
test "sentinel" {
    try testing.expectEqual(@TypeOf(sentinel([]const u8)), ?u8);
    try testing.expectEqual(@TypeOf(sentinel([32:0]u23)), ?u23);
    try testing.expectEqual(@TypeOf(sentinel([128:3]u23)), ?u23);
    try testing.expectEqual(@TypeOf(sentinel([28]u64)), ?u64);
    try testing.expectEqual(@TypeOf(sentinel([18:0.34]f64)), ?f64);
    try testing.expectEqual(@TypeOf(sentinel(*[32:0]u8)), ?u8);
    try testing.expectEqual(@TypeOf(sentinel(***[32:0]u8)), ?u8);
    try testing.expectEqual(@TypeOf(sentinel(***[10]isize)), ?isize);

    try testing.expectEqual(sentinel([]const u8), null);
    try testing.expectEqual(sentinel([32:0]u23), 0);
    try testing.expectEqual(sentinel([128:3]u23), 3);
    try testing.expectEqual(sentinel([28]u64), null);
    try testing.expectEqual(sentinel([18:0.34]f64), 0.34);
    try testing.expectEqual(sentinel(*[32:0]u8), 0);
    try testing.expectEqual(sentinel(***[32:0]u8), 0);
    try testing.expectEqual(sentinel(***[10]isize), null);
}

test "copy" {
    var one: [32:0]u8 = undefined;
    var two: [32:0]u8 = undefined;
    var three: [15]u8 = [_]u8{0} ** 15;

    // []const u8 => *[32:0]u8
    copyZ(&one, "Hello, world!");
    try testing.expect(mem.eql(u8, used(&one), "Hello, world!"));

    // []const u8 => *[32:0]u8
    copyZ(&two, "This is a test!");
    try testing.expect(mem.eql(u8, used(&two), "This is a test!"));

    // *[32:0]u8 => *[32:0]u8
    copyZ(&one, &two);
    try testing.expect(mem.eql(u8, used(&one), "This is a test!"));

    // *[32:0]u8 => []u8
    copyZ(&three, &one);
    try testing.expectEqualSlices(u8, &three, "This is a test!");

    // []u8 => []u8
    copyZ(&three, "str is 15 chars");
    try testing.expectEqualSlices(u8, &three, "str is 15 chars");
}

test "folding text" {
    {
        const str = "  abcd efgh  ijkl mnop ";
        var folder = FoldedTextIterator.init(str, 4);
        try testing.expectEqualSlices(u8, folder.next().?, "abcd");
        try testing.expectEqualSlices(u8, folder.next().?, "efgh");
        try testing.expectEqualSlices(u8, folder.next().?, "ijkl");
        try testing.expectEqualSlices(u8, folder.next().?, "mnop");
        try testing.expectEqual(folder.next(), null);
    }

    {
        const str = "I had a vision when the night was late: a youth came riding toward the palace-gate.";
        var folder = FoldedTextIterator.init(str, 10);
        try testing.expectEqualSlices(u8, folder.next().?, "I had a");
        try testing.expectEqualSlices(u8, folder.next().?, "vision");
        try testing.expectEqualSlices(u8, folder.next().?, "when the");
        try testing.expectEqualSlices(u8, folder.next().?, "night was");
        try testing.expectEqualSlices(u8, folder.next().?, "late: a");
        try testing.expectEqualSlices(u8, folder.next().?, "youth");
        try testing.expectEqualSlices(u8, folder.next().?, "came");
        try testing.expectEqualSlices(u8, folder.next().?, "riding");
        try testing.expectEqualSlices(u8, folder.next().?, "toward");
        try testing.expectEqualSlices(u8, folder.next().?, "the");
        try testing.expectEqualSlices(u8, folder.next().?, "palace-gat");
        try testing.expectEqualSlices(u8, folder.next().?, "e.");
        try testing.expectEqual(folder.next(), null);
    }
}
// }}}
