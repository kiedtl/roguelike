const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const meta = std.meta;
const mem = std.mem;
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

pub fn getFieldByEnum(
    comptime E: type,
    struct_: anytype,
    variant: E,
) @typeInfo(@TypeOf(struct_)).Struct.fields[0].field_type {
    inline for (@typeInfo(E).Enum.fields) |enumv| {
        const e = @intToEnum(E, enumv.value);
        if (e == variant)
            return @field(struct_, @tagName(e));
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
// FIXME: don't break unicode codepoints
// FIXME: stress-test on abnormal inputs (empty input, input full of whitespace, etc)
pub const FoldedTextIterator = struct {
    str: []const u8,
    max_width: usize,
    last_space: ?usize = null,
    index: usize = 0,
    line_begin: usize = 0,

    const Self = @This();

    pub fn init(str: []const u8, max_width: usize) Self {
        return .{ .str = str, .max_width = max_width };
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.index >= self.str.len) {
            return null;
        }

        var cur_width: usize = 0;

        while (self.index < self.str.len and cur_width < self.max_width) {
            switch (self.str[self.index]) {
                // Skip our custom formatting directives.
                '$' => {
                    self.index += 2;
                    continue;
                },

                ' ', '\t', '\n', '\x0b', '\x0c', '\x0d' => {
                    // We've found some whitespace.
                    // If we're at the beginning of a line, ignore it; otherwise,
                    // save the current index.
                    if (cur_width == 0) {
                        self.index += 1;
                        self.line_begin += 1;
                        continue;
                    }

                    self.last_space = self.index;
                },
                else => {},
            }
            self.index += 1;
            cur_width += 1;
        }

        // Backup to the last space (if necessary) and return a new
        // line.
        if (self.index < self.str.len) {
            if (self.last_space) |spc| {
                self.index = spc;
                self.last_space = null;
            }
        }

        const old_line_begin = self.line_begin;
        self.line_begin = self.index;
        const res = self.str[old_line_begin..self.index];
        return if (res.len == 0) null else res;
    }
};
