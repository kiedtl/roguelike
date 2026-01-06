const builtin = @import("builtin");

const std = @import("std");
const sort = std.sort;
const assert = std.debug.assert;
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
const Machine = types.Machine;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;
const DIRECTIONS = types.DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;

const StackBuffer = buffer.StackBuffer;
// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;

pub const testing = @import("utils/testing.zig");

pub fn is(comptime id: std.builtin.TypeId) fn (type) bool {
    const Closure = struct {
        pub fn trait(comptime T: type) bool {
            return id == @typeInfo(T);
        }
    };
    return Closure.trait;
}

/// Copied from Zig 0.9.1 standard library.
///
/// Returns true if the passed type will coerce to []const u8.
/// Any of the following are considered strings:
/// ```
/// []const u8, [:S]const u8, *const [N]u8, *const [N:S]u8,
/// []u8, [:S]u8, *[:S]u8, *[N:S]u8.
/// ```
/// These types are not considered strings:
/// ```
/// u8, [N]u8, [*]const u8, [*:0]const u8,
/// [*]const [N]u8, []const u16, []const i8,
/// *const u8, ?[]const u8, ?*const [N]u8.
/// ```
pub fn isZigString(comptime T: type) bool {
    comptime {
        // Only pointer types can be strings, no optionals
        const info = @typeInfo(T);
        if (info != .pointer) return false;

        const ptr = &info.pointer;
        // Check for CV qualifiers that would prevent coerction to []const u8
        if (ptr.is_volatile or ptr.is_allowzero) return false;

        // If it's already a slice, simple check.
        if (ptr.size == .slice) {
            return ptr.child == u8;
        }

        // Otherwise check if it's an array type that coerces to slice.
        if (ptr.size == .one) {
            const child = @typeInfo(ptr.child);
            if (child == .array) {
                const arr = &child.array;
                return arr.child == u8;
            }
        }

        return false;
    }
}

/// Copied from Zig 0.9.1 standard library.
pub fn isManyItemPtr(comptime T: type) bool {
    if (comptime is(.pointer)(T)) {
        return @typeInfo(T).pointer.size == .many;
    }
    return false;
}

/// Copied from Zig 0.9.1 standard library.
pub fn isSlice(comptime T: type) bool {
    if (comptime is(.pointer)(T)) {
        return @typeInfo(T).pointer.size == .slice;
    }
    return false;
}

// Print into fixed buffer, no allocation
pub fn print(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    for (buf) |*i| i.* = 0;
    var fbs = std.io.fixedBufferStream(buf);
    std.fmt.format(fbs.writer(), fmt, args) catch err.wat();
    return fbs.getWritten();
}

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
    // FIXME: if this hasn't triggered by the next time I'm seeing this, remove
    // the level arg. It's ridiculous
    assert(level == coord.z);

    return switch (state.layout[level][coord.y][coord.x]) {
        .Unknown => null,
        .Room => |r| r,
    };
}

// Bounded string
// CLEANUP: merge this type with StringBuf<size>
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
        const ep_secs = std.time.epoch.EpochSeconds{ .secs = @intCast(std.time.timestamp()) };
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

pub const IterCircle = struct {
    buf: [HEIGHT][WIDTH]bool = [_][WIDTH]bool{[_]bool{false} ** WIDTH} ** HEIGHT,
    y: usize = 0,
    x: usize = 0,
    z: usize,

    pub fn next(self: *@This()) ?Coord {
        while (true) {
            if (self.y >= HEIGHT)
                return null;
            defer {
                self.x += 1;
                if (self.x >= WIDTH) {
                    self.x = 0;
                    self.y += 1;
                }
            }
            if (self.buf[self.y][self.x])
                return Coord.new2(self.z, self.x, self.y);
        }
    }
};

pub fn iterCircle(center: Coord, r: usize) IterCircle {
    assert(r < @min(HEIGHT, WIDTH));

    var i = IterCircle{ .z = center.z };

    fov.shadowCast(center, r, state.mapgeometry, &i.buf, struct {
        pub fn f(_: Coord) bool {
            return false;
        }
    }.f);

    return i;
}

// pub fn iterCircle(ctx: *GeneratorCtx(Coord), arg: struct { center: Coord, r: usize }) void {
//     assert(arg.r < @min(HEIGHT, WIDTH));
//     var buf: [HEIGHT][WIDTH]bool = [_][WIDTH]bool{[_]bool{false} ** WIDTH} ** HEIGHT;

//     fov.shadowCast(arg.center, arg.r, state.mapgeometry, &buf, struct {
//         pub fn f(_: Coord) bool {
//             return true;
//         }
//     }.f);

//     for (buf, 0..) |row, y| for (row, 0..) |cell, x| if (cell) {
//         ctx.yield(Coord.new2(arg.center.z, x, y));
//     };

//     ctx.finish();
// }

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

test "countFmt" {
    try std.testing.expectEqual(countFmt("$.$~$C$.foo$.", .{}), 3);
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

pub fn getSpecificMachineInRoom(coord: Coord, id: []const u8) ?*Machine {
    const room_ind = getRoomFromCoord(coord.z, coord) orelse return null;
    const room = state.rooms[coord.z].items[room_ind];

    var iter = room.rect.iter();
    return while (iter.next()) |roomcoord| {
        if (state.dungeon.machineAt(roomcoord)) |mach|
            if (mem.eql(u8, mach.id, id))
                break mach;
    } else null;
}

pub fn getSpecificMobInRoom(coord: Coord, id: []const u8) ?*Mob {
    const room_ind = getRoomFromCoord(coord.z, coord) orelse return null;
    const room = state.rooms[coord.z].items[room_ind];

    var iter = room.rect.iter();
    return while (iter.next()) |roomcoord| {
        if (state.dungeon.at(roomcoord).mob) |othermob|
            if (mem.eql(u8, othermob.id, id))
                break othermob;
    } else null;
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
    for (&DIRECTIONS) |d| {
        if (getHostileInDirection(self, d)) |_| {
            i += 1;
        } else |_| {}
    }
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
    func: *const fn (*meta.Elem(@TypeOf(haystack)), @TypeOf(ctx)) bool,
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
    func: *const fn (meta.Elem(@TypeOf(haystack)), @TypeOf(ctx)) bool,
) ?meta.Elem(@TypeOf(haystack)) {
    return for (haystack) |straw| {
        if ((func)(straw, ctx)) {
            break straw;
        }
    } else null;
}

pub const CountingAllocator = struct {
    parent_alloc: mem.Allocator,
    total_alloced: usize = 0,
    total_allocations: usize = 0,
    failed_resizes: usize = 0,

    const Self = @This();

    pub fn init(parent: mem.Allocator) Self {
        return .{ .parent_alloc = parent };
    }

    pub fn deinit(self: *Self) void {
        std.log.debug("Alloced: {} bytes, Total allocations: {}, Failed resizes: {}", .{ self.total_alloced, self.total_allocations, self.failed_resizes });
        self.* = undefined;
    }

    pub fn allocator(self: *Self) mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, ptr_align: mem.Alignment, ret_addr: usize) ?[*]u8 {
        const self: *Self = @alignCast(@ptrCast(ctx));
        self.total_alloced += len;
        self.total_allocations += 1;
        return self.parent_alloc.rawAlloc(len, ptr_align, ret_addr);
    }

    fn remap(ctx: *anyopaque, buf: []u8, buf_align: mem.Alignment, new_len: usize, ra: usize) ?[*]u8 {
        const self: *Self = @alignCast(@ptrCast(ctx));
        self.total_alloced = (self.total_alloced - buf.len) + new_len;
        return self.parent_alloc.rawRemap(buf, buf_align, new_len, ra);
    }

    fn resize(ctx: *anyopaque, buf: []u8, buf_align: mem.Alignment, new_len: usize, ret_addr: usize) bool {
        const self: *Self = @alignCast(@ptrCast(ctx));
        self.total_alloced = (self.total_alloced - buf.len) + new_len;
        const res = self.parent_alloc.rawResize(buf, buf_align, new_len, ret_addr);
        if (!res) self.failed_resizes += 1;
        return res;
    }

    fn free(ctx: *anyopaque, buf: []u8, buf_align: mem.Alignment, ret_addr: usize) void {
        const self: *Self = @alignCast(@ptrCast(ctx));
        //self.total_alloced -= buf.len;
        //self.total_allocations -= 1;
        return self.parent_alloc.rawFree(buf, buf_align, ret_addr);
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
            try std.fmt.formatType(@as(usize, @intCast(value.v)), fmt, options, writer, 0);
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
    inline for (@typeInfo(E).@"enum".fields) |enumv| {
        const e: E = @enumFromInt(enumv.value);
        if (e == v) return &@field(s, @tagName(e));
    }
    unreachable;
}

pub fn getFieldByEnum(comptime E: type, s: anytype, v: E) @typeInfo(@TypeOf(s)).@"struct".fields[0].type {
    inline for (@typeInfo(E).@"enum".fields) |enumv| {
        const e: E = @enumFromInt(enumv.value);
        if (e == v) return @field(s, @tagName(e));
    }
    unreachable;
}

pub fn getNearestCorpse(me: *Mob) ?Coord {
    var buf = StackBuffer(Coord, 32).init(null);

    search: for (me.fov.m, 0..) |row, y| for (row, 0..) |cell, x| {
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
    std.sort.insertion(Coord, buf.slice(), me, _sortFunc._fn);

    return buf.last().?;
}

fn _checkPath(from: Coord, to: Coord, opts: state.IsWalkableOptions) bool {
    const line = from.drawLine(to, state.mapgeometry, 0);
    return for (line.constSlice()) |c| {
        if (c.eq(from) or c.eq(to)) {
            continue;
        }
        if (!state.is_walkable(c, opts)) {
            break false;
        }
    } else true;
}

pub fn hasClearLOF(from: Coord, to: Coord) bool {
    return _checkPath(from, to, .{ .right_now = true, .only_if_breaks_lof = true });
}

pub fn hasStraightPath(from: Coord, to: Coord) bool {
    return _checkPath(from, to, .{ .right_now = true });
}

pub fn percentOf(comptime T: type, x: T, percent: T) T {
    return x * percent / 100;
}

// This function is broken for some reason on Zig 0.14.0
pub fn used(slice: anytype) rt: {
    const SliceType = @TypeOf(slice);
    const ChildType = std.meta.Elem(SliceType);

    break :rt switch (@typeInfo(SliceType)) {
        .pointer => |p| if (p.is_const) []const ChildType else []ChildType,
        .array => []const ChildType,
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

    for (haystack, 0..) |straw, i| {
        const id = used(straw.id);
        if (mem.eql(u8, needle, id)) return i;
    }

    return null;
}

pub fn cloneStr(str: []const u8, alloc: mem.Allocator) ![]const u8 {
    const new = alloc.alloc(u8, str.len) catch return error.OutOfMemory;
    mem.copyForwards(u8, new, str);
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

    patterns: for (patterns, 0..) |pattern, pattern_i| {
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
                    .Corpse, .Container, .Poster => tiletype = .Wall,

                    // Treating this as a wall can cause props etc to be placed
                    // in front of stairs -- very bad!
                    .Stair => {},
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

// A generic holder for benchmarker data, keeping track of min, max, and
// rolling averages. Used for performance data and serialization space usage
// data.
pub const Benchmarker = struct {
    records: std.StringHashMap(Record),

    pub const Record = struct {
        count: u64,
        average: u64,
        min: u64,
        max: u64,
        total: u64,

        pub fn default() Record {
            return Record{ .count = 0, .average = 0, .min = std.math.maxInt(u64), .max = 0, .total = 0 };
        }
    };

    pub const Timer = struct {
        benchmarker: *Benchmarker,
        id: []const u8,
        timer: std.time.Timer,

        pub fn end(self: *Timer) void {
            const time = self.timer.read();
            self.benchmarker.record(self.id, time);
        }
    };

    pub fn init(self: *Benchmarker) void {
        self.records = std.StringHashMap(Record).init(state.alloc);
    }

    pub fn deinit(self: *Benchmarker) void {
        self.records.clearAndFree();
    }

    pub fn record(self: *Benchmarker, id: []const u8, datapoint: usize) void {
        const entry = self.records.getOrPutValue(id, Record.default()) catch unreachable;
        const v = entry.value_ptr;

        v.count += 1;
        v.min = @min(v.min, datapoint);
        v.max = @max(v.max, datapoint);
        v.total += datapoint;

        const avg: i64 = @intCast(v.average);
        const ia = avg + @divFloor(@as(i64, @intCast(datapoint)) - avg, @as(i64, @intCast(v.count)));
        v.average = @intCast(ia);
    }

    pub fn timer(self: *Benchmarker, id: []const u8) Timer {
        return Timer{
            .benchmarker = self,
            .id = id,
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    pub fn printTimes(self: *const Benchmarker) void {
        var stderr = std.io.getStdErr().writer();
        var bench_records = self.records.iterator();
        while (bench_records.next()) |rec_entry| {
            const v = rec_entry.value_ptr;
            stderr.print("[{s:>24}] {:>7} recs: {d:.3}..{d:<8.3}\t{d:>7.3} avg\n", .{
                rec_entry.key_ptr.*,
                v.count,
                @as(f32, @floatFromInt(v.min)) * 1e-6,
                @as(f32, @floatFromInt(v.max)) * 1e-6,
                @as(f32, @floatFromInt(v.average)) * 1e-6,
            }) catch err.wat();
        }
    }

    pub fn print(self: *const Benchmarker) void {
        var total: u64 = 0;
        {
            var bench_records = self.records.iterator();
            while (bench_records.next()) |rec_entry|
                total += rec_entry.value_ptr.total;
        }

        var stderr = std.io.getStdErr().writer();
        var bench_records = self.records.iterator();
        while (bench_records.next()) |rec_entry| {
            const v = rec_entry.value_ptr;
            const perc = @as(f32, @floatFromInt(v.total)) * 100 / @as(f32, @floatFromInt(total));
            stderr.print("\x1b[1m{s}\x1b[m:\n{:<9} recs: {d:>8}..{d:<9} ~~ {d:>8} avg, {d:>9} sum ({d:.2}%)\n", .{
                rec_entry.key_ptr.*, v.count,
                v.min,               v.max,
                v.average,           v.total,
                perc,
            }) catch err.wat();
        }
    }
};

pub const OBSDTimer =
    if (builtin.os.tag == .openbsd)
        @import("utils/obsd_timer.zig").OBSDTimer
    else
        @compileError("OBSDTimer on non-OpenBSD platform");

// tests {{{
test "copy" {
    var one: [32:0]u8 = undefined;
    var two: [32:0]u8 = undefined;
    var three: [15]u8 = [_]u8{0} ** 15;

    // []const u8 => *[32:0]u8
    copyZ(&one, "Hello, world!");
    try std.testing.expect(mem.eql(u8, used(&one), "Hello, world!"));

    // []const u8 => *[32:0]u8
    copyZ(&two, "This is a test!");
    try std.testing.expect(mem.eql(u8, used(&two), "This is a test!"));

    // *[32:0]u8 => *[32:0]u8
    copyZ(&one, &two);
    try std.testing.expect(mem.eql(u8, used(&one), "This is a test!"));

    // *[32:0]u8 => []u8
    copyZ(&three, &one);
    try std.testing.expectEqualSlices(u8, &three, "This is a test!");

    // []u8 => []u8
    copyZ(&three, "str is 15 chars");
    try std.testing.expectEqualSlices(u8, &three, "str is 15 chars");
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
