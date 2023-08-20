const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
const math = std.math;
const meta = std.meta;
const mem = std.mem;
const unicode = std.unicode;
const enums = std.enums;

const surfaces = @import("surfaces.zig");
const state = @import("state.zig");
const err = @import("err.zig");
const fov = @import("fov.zig");
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
const DIRECTIONS = types.DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;

const StackBuffer = buffer.StackBuffer;
const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;

// Should not be left in compiled code, as it's incompatible with Windows
pub fn debugPrintDirectCaller() void {
    const debug_info = std.debug.getSelfDebugInfo() catch err.wat();
    const startaddr = @returnAddress();
    var it = std.debug.StackIterator.init(startaddr, null);
    _ = it.next().?;
    const retaddr = it.next().?;

    const module = debug_info.getModuleForAddress(retaddr) catch err.wat();
    const symb_info = module.getSymbolAtAddress(retaddr) catch err.wat();
    defer symb_info.deinit();
    std.log.debug("direct caller: {s}:{}", .{
        symb_info.line_info.?.file_name, symb_info.line_info.?.line,
    });
}

pub fn getRoomFromCoord(level: usize, coord: Coord) ?usize {
    return switch (state.layout[level][coord.y][coord.x]) {
        .Unknown => null,
        .Room => |r| r,
    };
}

// Bounded string
pub fn BStr(comptime sz: usize) type {
    return StackBuffer(u8, sz);
}

pub const DateTime = struct {
    Y: usize,
    M: usize,
    D: usize,
    h: usize,
    m: usize,

    pub fn collect() @This() {
        const ep_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(u64, std.time.timestamp()) };
        const ep_day = ep_secs.getEpochDay();
        const year_day = ep_day.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const day_seconds = ep_secs.getDaySeconds();

        return .{
            .Y = year_day.year,
            .M = month_day.month.numeric(),
            .D = month_day.day_index,
            .h = day_seconds.getHoursIntoDay(),
            .m = day_seconds.getMinutesIntoHour(),
        };
    }
};

pub fn iterCircle(ctx: *GeneratorCtx(Coord), arg: struct { center: Coord, r: usize }) void {
    assert(arg.r < math.min(HEIGHT, WIDTH));
    var buf: [HEIGHT][WIDTH]bool = [_][WIDTH]bool{[_]bool{false} ** WIDTH} ** HEIGHT;

    fov.shadowCast(arg.center, arg.r, state.mapgeometry, &buf, struct {
        pub fn f(_: Coord) bool {
            return true;
        }
    }.f);

    for (buf) |row, y| for (row) |cell, x| if (cell) {
        ctx.yield(Coord.new2(arg.center.z, x, y));
    };

    ctx.finish();
}

// Count the characters needed to display some text
pub fn countFmt(comptime fmt: []const u8, args: anytype) u64 {
    var counting_writer = (struct {
        bytes_written: u64,
        ignore_next: bool = false,
        pub const E = error{};
        pub const Writer = std.io.Writer(*@This(), E, write);

        pub fn write(self: *@This(), bytes: []const u8) E!usize {
            for (bytes) |byte| if (byte == '$') {
                self.ignore_next = true;
            } else if (self.ignore_next) {
                self.ignore_next = false;
            } else {
                self.bytes_written += 1;
            };
            return bytes.len;
        }
        pub fn writer(self: *@This()) Writer {
            return .{ .context = self };
        }
    }){ .bytes_written = 0 };
    std.fmt.format(counting_writer.writer(), fmt, args) catch err.wat();
    return counting_writer.bytes_written;
}

pub fn getFarthestWalkableCoord(d: Direction, coord: Coord, opts: state.IsWalkableOptions) Coord {
    var target = coord;
    while (target.move(d, state.mapgeometry)) |newcoord| {
        if (!state.is_walkable(newcoord, opts)) break;
        target = newcoord;
    }
    return target;
}

pub fn walkableNeighbors(c: Coord, diagonals: bool, opts: state.IsWalkableOptions) usize {
    const directions = if (diagonals) &DIRECTIONS else &CARDINAL_DIRECTIONS;
    var ctr: usize = 0;
    for (directions) |d| if (c.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, opts))
            ctr += 1;
    };
    return ctr;
}

pub fn getMobInDirection(self: *Mob, d: Direction) !*Mob {
    if (self.coord.move(d, state.mapgeometry)) |neighbor| {
        if (state.dungeon.at(neighbor).mob) |othermob| {
            return othermob;
        } else return error.NoMobThere;
    } else {
        return error.OutOfMapBounds;
    }
}

pub fn adjacentHostiles(self: *const Mob) usize {
    var i: usize = 0;
    for (&DIRECTIONS) |d| if (getHostileInDirection(self, d)) {
        i += 1;
    } else |_| {};
    return i;
}

pub fn getHostileInDirection(self: *const Mob, d: Direction) !*Mob {
    if (self.coord.move(d, state.mapgeometry)) |neighbor| {
        return getHostileAt(self, neighbor);
    } else {
        return error.OutOfMapBounds;
    }
}

pub fn getHostileAt(self: *const Mob, coord: Coord) !*Mob {
    if (state.dungeon.at(coord).mob) |othermob| {
        if (othermob.isHostileTo(self) and othermob.ai.is_combative) {
            return othermob;
        } else return error.NoHostileThere;
    } else return error.NoHostileThere;
}

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

// Used to deduplicate code in HUD and drawPlayerInfoScreen
//
// A bit idiosyncratic...
pub const ReputationFormatter = struct {
    pub fn dewIt(_: @This()) bool {
        const rep = state.night_rep[@enumToInt(state.player.faction)];
        const is_on_slade = state.dungeon.terrainAt(state.player.coord) == &surfaces.SladeTerrain;
        return rep != 0 or is_on_slade;
    }

    pub fn format(self: *const @This(), comptime f: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (comptime !mem.eql(u8, f, "")) @compileError("Unknown format string: '" ++ f ++ "'");

        const rep = state.night_rep[@enumToInt(state.player.faction)];
        const is_on_slade = state.dungeon.terrainAt(state.player.coord) == &surfaces.SladeTerrain;

        if (self.dewIt()) {
            const str = if (rep == 0) "$g$~ NEUTRAL $." else if (rep > 0) "$a$~ FRIENDLY $." else if (rep >= -5) "$p$~ DISLIKED $." else "$r$~ HATED $.";
            if (is_on_slade and rep < 1) {
                try std.fmt.format(writer, "$cNight rep:$. {} $r$~ TRESPASSING $.\n", .{rep});
            } else {
                try std.fmt.format(writer, "$cNight rep:$. {} {s}\n", .{ rep, str });
            }
        }
    }
};

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
    const line = from.drawLine(to, state.mapgeometry, 0);
    return for (line.constSlice()) |c| {
        if (c.eq(from) or c.eq(to)) {
            continue;
        }
        if (!state.is_walkable(c, .{ .right_now = true, .only_if_breaks_lof = true })) {
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
    const sentry = std.meta.sentinel(@TypeOf(slice)) orelse return slice[0..];
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

pub fn cloneStr(str: []const u8, alloc: mem.Allocator) ![]const u8 {
    var new = alloc.alloc(u8, str.len) catch return error.OutOfMemory;
    mem.copy(u8, new, str);
    return new;
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

    if (std.meta.sentinel(@TypeOf(dest))) |s| {
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
                        // if (self.index != 0 and self.str[self.index - 1] == '\n') {
                        self.index += seqlen;
                        break;
                        // } else {
                        //     self.index += seqlen;
                        //     if (line_buf.len > 0) {
                        //         line_buf.append(' ') catch unreachable;
                        //     }
                        //     continue;
                        // }
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

// test "folding text" {
//     {
//         const str = "  abcd efgh  ijkl $.mnop ";
//         var folder = FoldedTextIterator.init(str, 4);
//         var buf = StackBuffer(u8, 4096).init(null);
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "abcd");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "efgh");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "ijkl");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "mnop");
//         try testing.expectEqual(folder.next(&buf), null);
//     }

//     {
//         const str = "I had a vision when the night was late: a youth came riding toward the palace-gate.";
//         var folder = FoldedTextIterator.init(str, 10);
//         var buf = StackBuffer(u8, 4096).init(null);
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "I had a");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "vision");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "when the");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "night was");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "late: a");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "youth");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "came");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "riding");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "toward");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "the");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "palace-gat");
//         try testing.expectEqualSlices(u8, folder.next(&buf).?, "e.");
//         try testing.expectEqual(folder.next(&buf), null);
//     }
// }
// }}}
