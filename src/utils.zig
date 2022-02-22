const std = @import("std");
const assert = std.debug.assert;
const math = std.math;
const meta = std.meta;
const mem = std.mem;

const state = @import("state.zig");
usingnamespace @import("types.zig");

pub fn hasClearLOF(from: Coord, to: Coord) bool {
    const line = from.drawLine(to, state.mapgeometry);
    return for (line.constSlice()) |c| {
        if (!c.eq(from) and !c.eq(to) and
            !state.is_walkable(c, .{ .right_now = true }))
        {
            break false;
        }
    } else true;
}

pub fn saturating_sub(a: anytype, b: anytype) @TypeOf(a, b) {
    return switch (@typeInfo(@TypeOf(a))) {
        .ComptimeInt, .Int => if ((a -% b) > a) 0 else a - b,
        .ComptimeFloat, .Float => if ((a - b) > a) 0 else a - b,
        else => @compileError("Type '" ++ @typeName(a) ++ "' not supported"),
    };
}

// interpolate linearly between two vals
fn interpolate(a: u32, b: u32, f: f64) u32 {
    const aa = @intToFloat(f64, a) / 255;
    const ab = @intToFloat(f64, b) / 255;
    return @floatToInt(u32, (aa + f * (ab - aa)) * 255);
}

// STYLE: move to separate colors module
pub fn mixColors(a: u32, b: u32, frac: f64) u32 {
    assert(frac <= 100);

    const ar = (a >> 16) & 0xFF;
    const ag = (a >> 08) & 0xFF;
    const ab = (a >> 00) & 0xFF;
    const br = (b >> 16) & 0xFF;
    const bg = (b >> 08) & 0xFF;
    const bb = (b >> 00) & 0xFF;
    const rr = interpolate(ar, br, frac);
    const rg = interpolate(ag, bg, frac);
    const rb = interpolate(ab, bb, frac);
    return (rr << 16) | (rg << 8) | rb;
}

pub fn percentOf(comptime T: type, x: T, percent: T) T {
    return x * percent / 100;
}

pub fn percentageOfColor(color: u32, _p: usize) u32 {
    const percentage = math.clamp(_p, 0, 100);
    var r = ((color >> 16) & 0xFF) * @intCast(u32, percentage) / 100;
    var g = ((color >> 08) & 0xFF) * @intCast(u32, percentage) / 100;
    var b = ((color >> 00) & 0xFF) * @intCast(u32, percentage) / 100;
    r = math.clamp(r, 0, 0xFF);
    g = math.clamp(g, 0, 0xFF);
    b = math.clamp(b, 0, 0xFF);
    return (r << 16) | (g << 8) | b;
}

pub fn darkenColor(color: u32, by: u32) u32 {
    const r = ((color >> 16) & 0xFF) / by;
    const g = ((color >> 08) & 0xFF) / by;
    const b = ((color >> 00) & 0xFF) / by;
    return (r << 16) | (g << 8) | b;
}

pub fn filterColorGrayscale(color: u32) u32 {
    const r = @intToFloat(f64, ((color >> 16) & 0xFF));
    const g = @intToFloat(f64, ((color >> 08) & 0xFF));
    const b = @intToFloat(f64, ((color >> 00) & 0xFF));
    const brightness = @floatToInt(u32, 0.299 * r + 0.587 * g + 0.114 * b);
    return (brightness << 16) | (brightness << 8) | brightness;
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
    return slice[0..mem.lenZ(slice)];
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

pub fn copyZ(dest: anytype, src: anytype) void {
    const DestElem = meta.Elem(@TypeOf(dest));
    const SourceChild = meta.Elem(@TypeOf(src));
    if (DestElem != SourceChild) {
        const d = @typeName(@TypeOf(dest));
        const s = @typeName(@TypeOf(src));
        @compileError("Expected source to be " ++ d ++ ", got " ++ s);
    }

    const srclen = mem.lenZ(src);

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
                    .Container, .Poster, .Stair => tiletype = .Wall,
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
    width: usize,
    last_space: ?usize = null,
    index: usize = 0,
    line_begin: usize = 0,

    const Self = @This();

    pub fn init(str: []const u8, width: usize) Self {
        return .{ .str = str, .width = width };
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.index >= self.str.len) {
            return null;
        }

        while (self.index < self.str.len and (self.index - self.line_begin) < self.width) {
            switch (self.str[self.index]) {
                ' ', '\t', '\n', '\x0b', '\x0c', '\x0d' => {
                    // We've found some whitespace.
                    // If we're at the beginning of a line, ignore it; otherwise,
                    // save the current index.
                    if ((self.index - self.line_begin) == 0) {
                        self.index += 1;
                        self.line_begin += 1;
                        continue;
                    }

                    self.last_space = self.index;
                },
                else => {},
            }
            self.index += 1;
        }

        // Backup to the last space (if necessary) and return a new
        // line.
        if (self.last_space) |spc| {
            self.index = spc;
            self.last_space = null;
        }

        const old_line_begin = self.line_begin;
        self.line_begin = self.index;
        const res = self.str[old_line_begin..self.index];
        return if (res.len == 0) null else res;
    }
};
