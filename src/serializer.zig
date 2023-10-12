const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const err = @import("err.zig");
const items = @import("items.zig");
const itemlists = items.itemlists;
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const microtar = @import("microtar.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const types = @import("types.zig");

const StackBuffer = @import("buffer.zig").StackBuffer;
const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;

pub const Error = error{ PointerNotFound, MismatchedPointerTypes, CorruptedData, MismatchedType, InvalidUnionField } || std.ArrayList(u8).Writer.Error || std.mem.Allocator.Error || std.fs.File.Reader.Error || std.fs.File.Writer.Error || error{EndOfStream} || microtar.MTar.Error;

const FIELDS_ALWAYS_KEEP_LIST = [_][]const u8{ "__next", "__prev" };

const STATIC_CONTAINERS = [_]struct {
    m: []const u8,
    t: type,
    s: anytype,
}
// zig fmt: off
{
.{ .m = "s.props",       .t = types.Prop,              .s = &surfaces.props.items   },
.{ .m = "s.TERRAIN",     .t = *const surfaces.Terrain, .s = &@as([]const *const surfaces.Terrain, &surfaces.TERRAIN)      },
.{ .m = "i.ARMORS",      .t = *const types.Armor,      .s = &itemlists.ARMORS      },
.{ .m = "i.WEAPONS",     .t = *const types.Weapon,     .s = &itemlists.WEAPONS     },
.{ .m = "i.CLOAKS",      .t = *const items.Cloak,      .s = &itemlists.CLOAKS      },
.{ .m = "i.HEADGEAR",    .t = *const items.Headgear,   .s = &itemlists.HEADGEAR    },
.{ .m = "i.AUXES",       .t = *const items.Aux,        .s = &itemlists.AUXES       },
.{ .m = "i.CONSUMABLES", .t = *const items.Consumable, .s = &itemlists.CONSUMABLES },
};
// zig fmt: on

pub const ContainerInit = struct { container: []const u8, init_up_to: usize };
pub const PointerData = struct { container: []const u8, ptrtype: []const u8, index: usize };
pub const PointerData2 = struct { ptr: usize, ptrtype: []const u8, ind: usize };
var ptrtable: std.AutoHashMap(u64, PointerData) = undefined;
var ptrinits: StackBuffer(ContainerInit, 32) = undefined;

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
    // std.log.debug("..... => {: <20} {}", .{ _normIntT(IntType), value });
    try out.writeIntLittle(_normIntT(IntType), @as(_normIntT(IntType), value));
}

pub fn read(comptime IntType: type, in: anytype) !IntType {
    const value = try in.readIntLittle(_normIntT(IntType));
    // std.log.debug("..... <= {: <20} {}", .{ _normIntT(IntType), value });
    return @intCast(IntType, value);
}

pub fn SerializeFunctionFromModule(comptime T: type, field: []const u8, container: type) fn (*const T, *const _fieldType(T, field), anytype) Error!void {
    return struct {
        pub fn f(_: *const T, field_value: *const _fieldType(T, field), out: anytype) Error!void {
            inline for (meta.declarations(container)) |decl|
                if (decl.is_pub and _fieldType(T, field) == @TypeOf(@field(container, decl.name))) {
                    // std.log.debug("comparing 0x{x:0>8} to 0x{x:0>8} ({s})", .{
                    //     @ptrToInt(field_value), @ptrToInt(@field(container, decl.name)), decl.name,
                    // });
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
            var val: []const u8 = undefined;
            try deserialize([]const u8, &val, in, alloc);
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
                if (!ptrtable.contains(@ptrToInt(obj)))
                    std.log.warn("serialize: found {} pointer not in table", .{p.child});
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
                        // std.log.debug("Ser {s: <20} ({s})", .{ field.name, @typeName(field.field_type) });
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

pub fn deserializeQ(comptime T: type, in: anytype, alloc: mem.Allocator) Error!T {
    var r: T = undefined;
    try deserialize(T, &r, in, alloc);
    return r;
}

pub fn deserialize(comptime T: type, out: *T, in: anytype, alloc: mem.Allocator) Error!void {
    if (comptime mem.startsWith(u8, @typeName(T), "std.hash_map.HashMap(")) {
        const K = _fieldType(@field(T, "KV"), "key");
        const V = _fieldType(@field(T, "KV"), "value");
        var obj = T.init(state.GPA.allocator());
        var i = try deserializeQ(usize, in, alloc);
        while (i > 0) : (i -= 1) {
            const k = try deserializeQ(K, in, alloc);
            const v = try deserializeQ(V, in, alloc);
            try obj.putNoClobber(k, v);
        }
        out.* = obj;
        return;
    } else if (comptime mem.startsWith(u8, @typeName(T), "std.array_list.ArrayList")) {
        out.* = std.ArrayList(meta.Elem(_fieldType(T, "items"))).init(alloc);
        var i = try deserializeQ(usize, in, alloc);
        while (i > 0) : (i -= 1)
            try out.append(try deserializeQ(meta.Elem(_fieldType(T, "items")), in, alloc));
        return;
    }

    switch (@typeInfo(T)) {
        .Bool => out.* = (try read(u8, in)) == 1,
        .Int => out.* = try read(T, in),
        .Float => out.* = try read(if (T == f32) u32 else u64, in),
        .Pointer => |p| switch (p.size) {
            .One => {
                const ptr = try deserializeQ(usize, in, alloc);
                if (ptrtable.get(ptr)) |ptrdata| {
                    if (!mem.eql(u8, ptrdata.ptrtype, @typeName(T))) {
                        std.log.err("Wanted pointer of type {s}, found {}", .{ ptrdata.ptrtype, T });
                        return error.MismatchedPointerTypes;
                    }

                    inline for (&STATIC_CONTAINERS) |container|
                        if (container.t == T)
                            if (mem.eql(u8, container.m, ptrdata.container)) {
                                out.* = @as(*const []const T, container.s).*[ptrdata.index];
                                return;
                            };

                    inline for (meta.declarations(state)) |declinfo|
                        if (declinfo.is_pub and
                            @typeInfo(@TypeOf(@field(state, declinfo.name))) == .Struct and
                            @hasDecl(@TypeOf(@field(state, declinfo.name)), "nth") and
                            *@TypeOf(@field(state, declinfo.name)).ChildType == T)
                        {
                            if (mem.eql(u8, declinfo.name, ptrdata.container)) {
                                if (@field(state, declinfo.name).nth(ptrdata.index)) |d| {
                                    out.* = d;
                                    return;
                                } else {
                                    std.log.err("Pointer {s},{s},{} not in container (len: {})", .{
                                        ptrdata.container,
                                        ptrdata.ptrtype,
                                        ptrdata.index,
                                        @field(state, declinfo.name).len(),
                                    });
                                    return error.PointerNotFound;
                                }
                            }
                        };

                    std.log.err("Could not find pointer {s},{s},{}", .{
                        ptrdata.container, ptrdata.ptrtype, ptrdata.index,
                    });
                    return error.PointerNotFound;
                } else {
                    std.log.warn("deserialize: found {} pointer not in table", .{p.child});
                    out.* = undefined;
                }
            },
            .Slice => {
                var i = try deserializeQ(usize, in, alloc);
                var o = try alloc.alloc(p.child, i);
                while (i > 0) : (i -= 1)
                    try deserialize(p.child, &o[o.len - i], in, alloc);
                out.* = o;
            },
            .Many, .C => @compileError("Cannot deserialize " ++ @typeName(T)),
        },
        .Array => {
            var i = try deserializeQ(usize, in, alloc);
            assert(i == out.len);
            while (i > 0) : (i -= 1)
                try deserialize(meta.Child(T), &out[out.len - 1], in, alloc);
        },
        .Struct => |info| {
            if (comptime std.meta.trait.hasFn("deserialize")(T)) {
                try T.deserialize(out, in, alloc);
            } else {
                const oldobj = out.*;

                if (@hasDecl(T, "__SER_GET_PROTO")) {
                    comptime assert(@hasDecl(T, "__SER_GET_ID"));
                    const id = try deserializeQ([]const u8, in, alloc);
                    defer alloc.free(id);
                    out.* = T.__SER_GET_PROTO(id);
                }

                const noser = if (@hasDecl(T, "__SER_SKIP")) T.__SER_SKIP else [_][]const u8{};
                inline for (info.fields) |field| {
                    const noser_field = comptime for (noser) |item| {
                        @setEvalBranchQuota(9999);
                        if (mem.eql(u8, item, field.name)) break true;
                    } else false;
                    const keep_field = comptime for (FIELDS_ALWAYS_KEEP_LIST) |item| {
                        @setEvalBranchQuota(9999);
                        if (mem.eql(u8, item, field.name)) break true;
                    } else false;
                    if (!noser_field) {
                        // std.log.debug("Deser {s: <20} ({s})", .{
                        //     field.name,
                        //     @typeName(field.field_type),
                        // });

                        try deserializeExpect(field.field_type, in, alloc);

                        if (@hasDecl(T, "__SER_FIELDR_" ++ field.name)) {
                            comptime assert(@hasDecl(T, "__SER_FIELDW_" ++ field.name));
                            try @field(T, "__SER_FIELDR_" ++ field.name)(&@field(out, field.name), in, alloc);
                        } else {
                            try deserialize(field.field_type, &@field(out, field.name), in, alloc);
                        }

                        // switch (@typeInfo(field.field_type)) {
                        //     .Pointer => if (field.field_type == []const u8) std.log.debug("Deser value: {s}", .{@field(out, field.name)}) else std.log.debug("Deser value: skip", .{}),
                        //     .Array => std.log.debug("Deser value: {any}", .{@field(out, field.name)}),
                        //     .Bool, .Enum, .Int, .Float => {
                        //         std.log.debug("Deser value: {}", .{@field(out, field.name)});
                        //     },
                        //     else => {
                        //         if (field.field_type == ?[]const u8) {
                        //             if (@field(out, field.name)) |v|
                        //                 std.log.debug("Deser value: {s}", .{v})
                        //             else
                        //                 std.log.debug("Deser value: null", .{});
                        //         } else if (field.field_type == ?types.Damage or
                        //             field.field_type == ?types.Direction)
                        //         {
                        //             std.log.debug("Deser value: {}", .{@field(out, field.name)});
                        //         } else {
                        //             std.log.debug("Deser value: skip", .{});
                        //         }
                        //     },
                        // }
                    } else if (keep_field) {
                        @field(out, field.name) = @field(oldobj, field.name);
                    }
                }
            }
        },
        .Optional => |o| {
            const flag = try deserializeQ(u8, in, alloc);
            out.* = if (flag == 0) null else @as(T, try deserializeQ(o.child, in, alloc));
        },
        .Enum => |e| out.* = @intToEnum(T, try deserializeQ(e.tag_type, in, alloc)),
        .Union => |u| {
            const tag = try deserializeQ(meta.Tag(T), in, alloc);
            inline for (u.fields) |ufield|
                if (mem.eql(u8, ufield.name, @tagName(tag)))
                    // Can't break here due to Zig comptime control-flow bug
                    if (ufield.field_type == void) {
                        out.* = @unionInit(T, ufield.name, {});
                    } else {
                        const value = try deserializeQ(ufield.field_type, in, alloc);
                        out.* = @unionInit(T, ufield.name, value);
                    };
        },
        else => @compileError("Cannot deserialize " ++ @typeName(T)),
    }
}

pub fn deserializeExpect(comptime T: type, in: anytype, alloc: mem.Allocator) !void {
    const typeid = try deserializeQ(usize, in, alloc);
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
        // std.log.debug("*** ({} == {s})", .{ T, typeid_str });
    }
}

pub fn deserializeWE(comptime T: type, out: *T, in: anytype, alloc: mem.Allocator) Error!void {
    try deserializeExpect(T, in, alloc);
    try deserialize(T, out, in, alloc);
}

pub fn buildPointerTable() void {
    ptrtable = @TypeOf(ptrtable).init(state.GPA.allocator());

    inline for (meta.declarations(state)) |declinfo| if (declinfo.is_pub) {
        const decl = @field(state, declinfo.name);
        const declptr = &@field(state, declinfo.name);
        if (@typeInfo(@TypeOf(decl)) == .Struct and
            @hasDecl(@TypeOf(decl), "__SER_getPointerData"))
        {
            var max: usize = 0;
            var g = Generator(@TypeOf(decl).__SER_getPointerData).init(declptr);
            while (g.next()) |ptrdata2| {
                ptrtable.putNoClobber(ptrdata2.ptr, .{
                    .container = declinfo.name,
                    .index = ptrdata2.ind,
                    .ptrtype = ptrdata2.ptrtype,
                }) catch err.wat();
                if (ptrdata2.ind > max)
                    max = ptrdata2.ind;
            }
            ptrinits.append(.{ .container = declinfo.name, .init_up_to = max + 1 }) catch err.wat();
        }
    };

    inline for (&STATIC_CONTAINERS) |container| {
        const Ptr = if (@typeInfo(container.t) == .Pointer) container.t else *const container.t;
        const slice = @intToPtr(*const []const container.t, @ptrToInt(container.s));
        for (slice.*) |*item, ind| {
            const ptr = if (@typeInfo(container.t) == .Pointer) @ptrToInt(item.*) else @ptrToInt(item);
            if (ptrtable.contains(ptr)) {
                std.log.err("Pointer collision for {} (types: {s} vs {})", .{
                    ptr, ptrtable.get(ptr).?.ptrtype, Ptr,
                });
                // it'll crash below, no need to return/raise error
            }
            ptrtable.putNoClobber(ptr, .{
                .container = container.m,
                .index = ind,
                .ptrtype = @typeName(Ptr),
            }) catch err.wat();
        }
    }
}

pub fn initPointerContainers() void {
    for (ptrinits.constSlice()) |ptrinit| {
        inline for (meta.declarations(state)) |declinfo|
            if (declinfo.is_pub and
                @typeInfo(@TypeOf(@field(state, declinfo.name))) == .Struct and
                @hasDecl(@TypeOf(@field(state, declinfo.name)), "nth"))
            {
                if (mem.eql(u8, declinfo.name, ptrinit.container)) {
                    const container = &@field(state, declinfo.name);
                    var i: usize = ptrinit.init_up_to -| container.len();
                    std.log.info("initing {s} ({s}), up to {} ({})", .{ ptrinit.container, declinfo.name, ptrinit.init_up_to, i });
                    while (i > 0) : (i -= 1) {
                        container.append(undefined) catch err.wat();
                    }
                }
            };
    }
}

pub fn serializeWorld() !void {
    // var tar = try microtar.MTar.init("dump.tar", "w");
    // defer tar.deinit();
    var f = std.fs.cwd().openFile("dump.dat", .{ .write = true }) catch err.wat();
    defer f.close();

    // tar.writer()
    // - ptrtable.dat, ptrinits.dat, mobs.dat

    buildPointerTable();

    // var iter = ptrtable.iterator();
    // while (iter.next()) |item| {
    //     std.log.debug("ptr entry: 0x{X:0>16} -> {: >4} @ {s: >16} ({s})", .{
    //         item.key_ptr.*, item.value_ptr.index, item.value_ptr.container, item.value_ptr.ptrtype,
    //     });
    // }

    try serializeWE(@TypeOf(ptrtable), ptrtable, f.writer());
    try serializeWE(@TypeOf(ptrinits), ptrinits, f.writer());

    try serializeWE(@TypeOf(state.mobs), state.mobs, f.writer());
    // try serializeWE(types.Mob, state.player.*, f.writer());
}

pub fn deserializeWorld() !void {
    const alloc = state.GPA.allocator();

    // var tar = try microtar.MTar.init("dump.tar", "w");
    // defer tar.deinit();

    var f = std.fs.cwd().openFile("dump.dat", .{ .write = true }) catch err.wat();
    defer f.close();

    try deserializeWE(@TypeOf(ptrtable), &ptrtable, f.reader(), alloc);
    try deserializeWE(@TypeOf(ptrinits), &ptrinits, f.reader(), alloc);
    initPointerContainers();

    try deserializeWE(@TypeOf(state.mobs), &state.mobs, f.reader(), alloc);
    // try deserializeWE(types.Mob, state.player, f.reader(), alloc);
}
