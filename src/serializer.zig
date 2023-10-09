const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const types = @import("types.zig");
const state = @import("state.zig");
const err = @import("err.zig");

const StackBuffer = @import("buffer.zig").StackBuffer;

pub const Error = error{ CorruptedData, MismatchedType, InvalidUnionField } || std.ArrayList(u8).Writer.Error || std.mem.Allocator.Error || std.fs.File.Reader.Error || error{EndOfStream};

// Cache type ids so we can look up a type by its id
var typelist = StackBuffer(_KV, 256).init(null);
pub const _KV = struct { k: []const u8, v: usize };

fn _cacheTypeId(t: []const u8, v: usize) void {
    const contains = for (typelist.constSlice()) |item| {
        if (mem.eql(u8, item.k, t)) break true;
    } else false;
    if (!contains)
        typelist.append(.{ .k = t, .v = v }) catch
            err.bug("Serialization: ran out of slots for type ids", .{});
}

fn _typeId(comptime T: type) usize {
    // From https://zig.news/xq/cool-zig-patterns-type-identifier-3mfd
    _ = T;
    const H = struct {
        var byte: u8 = 0;
    };
    const id = @ptrToInt(&H.byte);
    _cacheTypeId(@typeName(T), id);
    return id;
}

fn _fieldType(comptime T: type, fieldname: []const u8) type {
    return inline for (meta.fields(T)) |field| {
        if (mem.eql(u8, field.name, fieldname))
            break field.field_type;
    } else @compileError("Type " ++ @typeName(T) ++ " has no field " ++ fieldname);
}

fn _normIntT(comptime Int: type) type {
    const s = @typeInfo(Int).Int.signedness == .signed;
    return switch (@typeInfo(Int).Int.bits) {
        1...8 => if (s) i8 else u8,
        9...16 => if (s) i16 else u16,
        17...32 => if (s) i32 else u32,
        33...64 => if (s) i64 else u64,
        65...128 => if (s) i128 else u128,
        else => @compileError("Normalizing unimplemented for type " ++ @typeName(Int)),
    };
}

pub fn write(comptime IntType: type, value: IntType, out: anytype) !void {
    std.log.debug("..... => {: <20} {}", .{ _normIntT(IntType), value });
    try out.writeIntLittle(_normIntT(IntType), @as(_normIntT(IntType), value));
}

pub fn read(comptime IntType: type, in: anytype) !IntType {
    const value = try in.readIntLittle(_normIntT(IntType));
    std.log.debug("..... <= {: <20} {}", .{ _normIntT(IntType), value });
    return @intCast(IntType, value);
}

pub fn SerializeFunctionFromModule(comptime T: type, field: []const u8, container: type) fn (*const T, *const _fieldType(T, field), anytype) Error!void {
    return struct {
        pub fn f(_: *const T, field_value: *const _fieldType(T, field), out: anytype) Error!void {
            inline for (meta.declarations(container)) |decl|
                if (decl.is_pub and _fieldType(T, field) == @TypeOf(@field(container, decl.name))) {
                    std.log.info("comparing 0x{x:0>8} to 0x{x:0>8} ({s})", .{
                        @ptrToInt(field_value), @ptrToInt(@field(container, decl.name)), decl.name,
                    });
                    if (field_value.* == @field(container, decl.name)) {
                        try serialize([]const u8, decl.name, out);
                        return;
                    }
                };
            unreachable;
        }
    }.f;
}

pub fn DeserializeFunctionFromModule(comptime T: type, field: []const u8, container: type) fn (*_fieldType(T, field), anytype, mem.Allocator) Error!void {
    return struct {
        pub fn f(out: *_fieldType(T, field), in: anytype, alloc: mem.Allocator) Error!void {
            const val = try deserialize([]const u8, in, alloc);
            defer alloc.free(val);
            inline for (meta.declarations(container)) |decl| {
                if (comptime mem.eql(u8, field, decl.name))
                    out.* = @field(container, field);
            }
        }
    }.f;
}

pub fn serializeWE(comptime T: type, obj: T, out: anytype) Error!void {
    try serialize(usize, _typeId(T), out);
    try serialize(T, obj, out);
}

pub fn serialize(comptime T: type, obj: T, out: anytype) Error!void {
    if (comptime mem.startsWith(u8, @typeName(T), "std.hash_map.HashMap")) {
        try serialize(usize, obj.count(), out);
        var iter = obj.iterator();
        while (iter.next()) |entry| {
            try serialize(@TypeOf(entry.key_ptr.*), entry.key_ptr.*, out);
            try serialize(@TypeOf(entry.value_ptr.*), entry.value_ptr.*, out);
        }
        return;
    } else if (comptime mem.startsWith(u8, @typeName(T), "std.array_list.ArrayList")) {
        try serialize(@TypeOf(obj.items), obj.items, out);
        return;
    }

    switch (@typeInfo(T)) {
        .Bool => try write(u8, if (obj) @as(u8, 1) else 0, out),
        .Int => try write(_normIntT(T), obj, out),
        .Float => {
            const F = if (T == f32) u32 else u64;
            try write(F, @bitCast(F, obj), out);
        },
        .Pointer => |p| switch (p.size) {
            .One => {
                std.log.warn("WARN: serialize pointer to {}", .{p.child});
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
            } else {
                if (@hasDecl(T, "__SER_GET_ID")) {
                    comptime assert(@hasDecl(T, "__SER_GET_PROTO"));
                    try serialize([]const u8, obj.__SER_GET_ID(), out);
                }

                const noser = if (@hasDecl(T, "__SER_SKIP")) T.__SER_SKIP else [_][]const u8{};
                inline for (info.fields) |field| {
                    const noser_field = comptime for (noser) |item| {
                        @setEvalBranchQuota(9999);
                        if (mem.eql(u8, item, field.name)) break true;
                    } else false;
                    if (!noser_field) {
                        std.log.debug("Ser {s: <20} ({s})", .{ field.name, @typeName(field.field_type) });
                        try serialize(usize, _typeId(field.field_type), out);

                        if (@hasDecl(T, "__SER_FIELDW_" ++ field.name)) {
                            comptime assert(@hasDecl(T, "__SER_FIELDR_" ++ field.name));
                            try @field(T, "__SER_FIELDW_" ++ field.name)(&obj, &@field(obj, field.name), out);
                        } else {
                            try serialize(field.field_type, @field(obj, field.name), out);
                        }
                    }
                }
            }
        },
        .Optional => |o| if (obj) |v| {
            try serialize(u8, 1, out);
            try serialize(o.child, v, out);
        } else {
            try serialize(u8, 0, out);
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
        else => @compileError("Cannot serialize " ++ @typeName(T)),
    }
}

pub fn deserialize(comptime T: type, in: anytype, alloc: mem.Allocator) Error!T {
    if (comptime mem.startsWith(u8, @typeName(T), "std.hash_map.HashMap")) {
        var obj = T.init(state.GPA.allocator());
        var i = try deserialize(usize, in, alloc);
        while (i > 0) : (i -= 1) {
            const k = try deserialize(_fieldType(@field(T, "KV"), "key"), in, alloc);
            const v = try deserialize(_fieldType(@field(T, "KV"), "value"), in, alloc);
            try obj.putNoClobber(k, v);
        }
        return obj;
    } else if (comptime mem.startsWith(u8, @typeName(T), "std.array_list.ArrayList")) {
        var obj = std.ArrayList(meta.Elem(_fieldType(T, "items"))).init(alloc);
        var i = try deserialize(usize, in, alloc);
        while (i > 0) : (i -= 1)
            try obj.append(try deserialize(meta.Elem(_fieldType(T, "items")), in, alloc));
        return obj;
    }

    return switch (@typeInfo(T)) {
        .Bool => (try read(u8, in)) == 1,
        .Int => try read(T, in),
        .Float => try read(if (T == f32) u32 else u64, in),
        .Pointer => |p| switch (p.size) {
            .One => b: {
                std.log.warn("WARN: deserialize pointer to {}", .{p.child});
                const ptr = try deserialize(usize, in, alloc);
                break :b @intToPtr(T, ptr);
            },
            .Slice => b: {
                var i = try deserialize(usize, in, alloc);
                var obj = try alloc.alloc(p.child, i);
                while (i > 0) : (i -= 1) {
                    obj[obj.len - i] = try deserialize(p.child, in, alloc);
                }
                break :b obj;
            },
            .Many, .C => @compileError("Cannot deserialize " ++ @typeName(T)),
        },
        .Array => @compileError("Cannot directly deserialize array"),
        .Struct => |info| b: {
            if (comptime std.meta.trait.hasFn("deserialize")(T)) {
                break :b try T.deserialize(in, alloc);
            } else {
                var obj: T = undefined;

                if (@hasDecl(T, "__SER_GET_PROTO")) {
                    comptime assert(@hasDecl(T, "__SER_GET_ID"));
                    const id = try deserialize([]const u8, in, alloc);
                    defer alloc.free(id);
                    obj = T.__SER_GET_PROTO(id);
                }

                const noser = if (@hasDecl(T, "__SER_SKIP")) T.__SER_SKIP else [_][]const u8{};
                inline for (info.fields) |field| {
                    const noser_field = comptime for (noser) |item| {
                        @setEvalBranchQuota(9999);
                        if (mem.eql(u8, item, field.name)) break true;
                    } else false;
                    if (!noser_field) {
                        std.log.debug("Deser {s: <20} ({s})", .{
                            field.name,
                            @typeName(field.field_type),
                        });

                        try deserializeExpect(field.field_type, in, alloc);

                        if (@hasDecl(T, "__SER_FIELDR_" ++ field.name)) {
                            comptime assert(@hasDecl(T, "__SER_FIELDW_" ++ field.name));
                            try @field(T, "__SER_FIELDR_" ++ field.name)(&@field(obj, field.name), in, alloc);
                        } else if (@typeInfo(field.field_type) == .Array) {
                            try deserializeArray(field.field_type, &@field(obj, field.name), in, alloc);
                        } else {
                            @field(obj, field.name) = try deserialize(field.field_type, in, alloc);
                        }

                        switch (@typeInfo(field.field_type)) {
                            .Pointer => if (field.field_type == []const u8) std.log.debug("Deser value: {s}", .{@field(obj, field.name)}) else std.log.debug("Deser value: skip", .{}),
                            .Array => std.log.debug("Deser value: {any}", .{@field(obj, field.name)}),
                            .Bool, .Enum, .Int, .Float => {
                                std.log.debug("Deser value: {}", .{@field(obj, field.name)});
                            },
                            else => {
                                if (field.field_type == ?[]const u8) {
                                    if (@field(obj, field.name)) |v|
                                        std.log.debug("Deser value: {s}", .{v})
                                    else
                                        std.log.debug("Deser value: null", .{});
                                } else if (field.field_type == ?types.Damage or
                                    field.field_type == ?types.Direction)
                                {
                                    std.log.debug("Deser value: {}", .{@field(obj, field.name)});
                                } else {
                                    std.log.debug("Deser value: skip", .{});
                                }
                            },
                        }
                    }
                }
                break :b obj;
            }
        },
        .Optional => |o| b: {
            const flag = try deserialize(u8, in, alloc);
            break :b if (flag == 0) null else @as(T, try deserialize(o.child, in, alloc));
        },
        .Enum => |e| @intToEnum(T, try deserialize(e.tag_type, in, alloc)),
        .Union => |u| b: {
            const tag = try deserialize(meta.Tag(T), in, alloc);
            var o: T = undefined;
            inline for (u.fields) |ufield|
                if (mem.eql(u8, ufield.name, @tagName(tag)))
                    // Can't break here due to Zig comptime control-flow bug
                    if (ufield.field_type == void) {
                        o = @unionInit(T, ufield.name, {});
                    } else {
                        const value = try deserialize(ufield.field_type, in, alloc);
                        o = @unionInit(T, ufield.name, value);
                    };
            break :b o;
        },
        else => @compileError("Cannot deserialize " ++ @typeName(T)),
    };
}

pub fn deserializeArray(comptime T: type, out: *T, in: anytype, alloc: mem.Allocator) Error!void {
    var i = try deserialize(usize, in, alloc);
    assert(i == out.len);
    while (i > 0) : (i -= 1) {
        if (@typeInfo(meta.Child(T)) == .Array) {
            try deserializeArray(meta.Child(T), &out[out.len - i], in, alloc);
        } else {
            out[out.len - i] = try deserialize(meta.Child(T), in, alloc);
        }
    }
}

pub fn deserializeExpect(comptime T: type, in: anytype, alloc: mem.Allocator) !void {
    const typeid = try deserialize(usize, in, alloc);
    const typeid_str: ?[]const u8 = for (typelist.constSlice()) |typedata| {
        if (typeid == typedata.v) break typedata.k;
    } else null;
    if (typeid != _typeId(T)) {
        if (typeid_str) |f| {
            std.log.err("Serialization: expected type {}, found {s}", .{ T, f });
            return error.MismatchedType;
        } else {
            std.log.err("Serialization: expected type {}, found corrupted data", .{T});
            return error.CorruptedData;
        }
    } else {
        std.log.debug("*** ({} == {s})", .{ T, typeid_str });
    }
}

pub fn deserializeWE(comptime T: type, in: anytype, alloc: mem.Allocator) Error!T {
    try deserializeExpect(T, in, alloc);
    return deserialize(T, in, alloc);
}

test {
    std.log.warn("{}", .{@sizeOf(u64)});
}
