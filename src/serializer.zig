const std = @import("std");
const meta = std.meta;
const mem = std.mem;

const types = @import("types.zig");

pub fn serialize(comptime T: type, obj: T, out: anytype) !void {
    if (comptime mem.startsWith(u8, @typeName(T), "std.hash_map.HashMap(")) {
        try serialize(usize, obj.count(), out);
        var iter = obj.iterator();
        while (iter.next()) |entry| {
            try serialize(@TypeOf(entry.key_ptr.*), entry.key_ptr.*, out);
            try serialize(@TypeOf(entry.value_ptr.*), entry.value_ptr.*, out);
        }
        return;
    } else if (comptime mem.startsWith(u8, @typeName(T), "std.array_list.ArrayList(")) {
        try serialize(@TypeOf(obj.items), obj.items, out);
        return;
    }

    switch (@typeInfo(T)) {
        .Bool => try out.writeIntLittle(u1, if (obj) @as(u1, 1) else 0),
        .Int => try out.writeIntLittle(T, obj),
        .Float => {
            const F = if (T == f32) u32 else u64;
            try out.writeIntLittle(F, @bitCast(F, obj));
        },
        .Pointer => |p| switch (p.size) {
            .One => {
                std.log.warn("Refusing to serialize pointer to {}", .{p.child});
                try serialize(usize, @ptrToInt(obj), out);
            },
            .Slice => {
                try serialize(usize, obj.len, out);
                for (obj) |value| try serialize(p.child, value, out);
            },
            .Many, .C => @compileError("Cannot serialize " ++ @typeName(T)),
        },
        .Array => |a| {
            try serialize(usize, a.len, out);
            for (obj) |value| try serialize(a.child, value, out);
        },
        .Struct => |info| {
            if (comptime std.meta.trait.hasFn("serialize")(T)) {
                try obj.serialize(out);
            } else inline for (info.fields) |field| {
                std.log.debug("Serializing {s: <20} ({s})", .{ field.name, @typeName(field.field_type) });
                const f = @field(obj, field.name);
                try serialize(field.field_type, f, out);
            }
        },
        .Optional => |o| {
            try serialize(u1, if (obj == null) @as(u1, 0) else 1, out);
            try serialize(o.child, if (obj == null) undefined else obj.?, out);
        },
        .Enum => |e| try serialize(e.tag_type, @enumToInt(obj), out),
        .Union => |u| {
            try serialize(meta.Tag(T), meta.activeTag(obj), out);
            inline for (u.fields) |ufield|
                if (mem.eql(u8, ufield.name, @tagName(meta.activeTag(obj)))) {
                    if (ufield.field_type != void)
                        try serialize(ufield.field_type, @field(obj, ufield.name), out);
                    break;
                };
        },
        .Fn => {},
        else => @compileError("Cannot serialize " ++ @typeName(T)),
    }
}

test {
    std.log.warn("{}", .{@sizeOf(u64)});
}
