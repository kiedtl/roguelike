const std = @import("std");
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const err = @import("err.zig");
const itemlists = items.itemlists;
const items = @import("items.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const materials = @import("materials.zig");
const microtar = @import("microtar.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const StackBuffer = @import("buffer.zig").StackBuffer;
// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;

pub const Error = error{ PointerNotFound, MismatchedPointerTypes, CorruptedData, MismatchedType, InvalidUnionField } || std.ArrayList(u8).Writer.Error || std.mem.Allocator.Error || std.fs.File.Reader.Error || std.fs.File.Writer.Error || error{EndOfStream} || microtar.MTar.Error;

const FIELDS_ALWAYS_SKIP_LIST = [_][]const u8{ "__next", "__prev" };
const FIELDS_ALWAYS_KEEP_LIST = [_][]const u8{ "__next", "__prev" };

// NOTE: need an extra level of indirection for the .s field, otherwise Zig
// fails on the .s=surfaces.props.items since that isn't comptime-evaluable
// (for some reason?).
const STATIC_CONTAINERS = .{
    // zig fmt: off
    .{ .m = "s.props", .t =        types.Prop,       .s = &surfaces.props.items     },
    .{ .m = "s.MAT",   .t = *const types.Material,   .s = &&materials.MATERIALS     },
    .{ .m = "s.TER",   .t = *const surfaces.Terrain, .s = &&surfaces.TERRAIN        },
    .{ .m = "i.ARM",   .t = *const types.Armor,      .s = &itemlists.ARMORS         },
    .{ .m = "i.AUX",   .t = *const items.Aux,        .s = &itemlists.AUXES          },
    .{ .m = "i.CLK",   .t = *const items.Cloak,      .s = &itemlists.CLOAKS         },
    .{ .m = "i.CON",   .t = *const items.Consumable, .s = &itemlists.CONSUMABLES    },
    .{ .m = "i.HDG",   .t = *const items.Headgear,   .s = &itemlists.HEADGEAR       },
    .{ .m = "i.SHO",   .t = *const items.Shoe,       .s = &itemlists.SHOES          },
    .{ .m = "i.WEP",   .t = *const types.Weapon,     .s = &itemlists.WEAPONS        },
    .{ .m = "m.post",  .t = *const literature.Poster,.s = &literature.posters.items },
    .{ .m = "m.nfab",  .t =        mapgen.Prefab,    .s = &mapgen.n_fabs.items      },
    .{ .m = "m.sfab",  .t =        mapgen.Prefab,    .s = &mapgen.s_fabs.items      },
};
// zig fmt: on

const GAME_OBJECTS = blk: {
    // This extremely cursed code comes from:
    // https://ziggit.dev/t/how-to-construct-a-tuple-at-compile-time-using-a-for-loop/6702/5

    var init_val = .{};
    var cur_ptr: *const anyopaque = &init_val;
    var CurTy = @TypeOf(init_val);

    var begin = false;
    for (@typeInfo(state).@"struct".decls) |declinfo| {
        if (mem.eql(u8, declinfo.name, "__SER_BEGIN")) {
            begin = true;
        } else if (mem.eql(u8, declinfo.name, "__SER_STOP")) {
            begin = false;
        } else if (begin) {
            const item = .{ @TypeOf(@field(state, declinfo.name)), &@field(state, declinfo.name) };

            const cur_val = @as(*const CurTy, @alignCast(@ptrCast(cur_ptr))).*;
            const new_val = cur_val ++ .{item};
            cur_ptr = &new_val;
            CurTy = @TypeOf(new_val);
        }
    }

    const final = @as(*const CurTy, @alignCast(@ptrCast(cur_ptr))).*;
    break :blk final;
};

pub const ContainerInit = struct { container: []const u8, init_up_to: usize };
pub const PointerData = struct { container: []const u8, ptrtype: []const u8, index: usize };
pub const PointerData2 = struct { ptr: usize, ind: usize, ptrtype: []const u8 };

const PtrTable = std.AutoHashMap(u64, PointerData);
var ptrtable: PtrTable = undefined;
var ptrinits: StackBuffer(ContainerInit, 32) = undefined;

var benchmarker: utils.Benchmarker = undefined;
var is_benchmarking = false;

// Cache type ids so we can look up a type by its id
var typelist = StackBuffer([]const u8, 256).init(null);
const TypeId = u8;

fn _typeId(comptime T: type) TypeId {
    // Following commented out code was from
    // https://zig.news/xq/cool-zig-patterns-type-identifier-3mfd
    //
    // Stopped using it because a perfect hash was better for space savings.
    //
    // const H = struct {
    //     var byte: u8 = 0;
    // };
    // const id = @intFromPtr(&H.byte);
    // return id;

    const s = @typeName(T);

    return for (typelist.constSlice(), 0..) |tyname, ind| {
        if (mem.eql(u8, tyname, s))
            break @intCast(ind);
    } else blk: {
        typelist.append(s) catch
            err.bug("Serialization: ran out of slots for type ids", .{});
        break :blk @intCast(typelist.len - 1);
    };
}

fn _fieldType(comptime T: type, fieldname: []const u8) type {
    return inline for (meta.fields(T)) |field| {
        if (mem.eql(u8, field.name, fieldname))
            break field.type;
    } else @compileError("Type " ++ @typeName(T) ++ " has no field " ++ fieldname);
}

fn _normIntT(comptime Int: type) type {
    const s = @typeInfo(Int).int.signedness == .signed;
    return switch (@typeInfo(Int).int.bits) {
        0 => u0,
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
    try out.writeInt(_normIntT(IntType), @as(_normIntT(IntType), value), .little);
}

pub fn read(comptime IntType: type, in: anytype) !IntType {
    const value = try in.readInt(_normIntT(IntType), .little);
    // std.log.debug("..... <= {: <20} {}", .{ _normIntT(IntType), value });
    return @intCast(value);
}

pub fn SerializeFunctionFromModule(
    comptime T: type,
    field: []const u8,
    comptime container: type,
) fn (*const T, *Serializer, *const _fieldType(T, field), anytype) Error!void {
    return struct {
        pub fn f(_: *const T, serializer: *Serializer, field_value: *const _fieldType(T, field), out: anytype) Error!void {
            inline for (@typeInfo(container).@"struct".decls) |decl|
                if (_fieldType(T, field) == *const @TypeOf(@field(container, decl.name))) {
                    // std.log.debug("comparing 0x{x:0>8} to 0x{x:0>8} ({s})", .{
                    //     @intFromPtr(field_value), @intFromPtr(&@field(container, decl.name)), decl.name,
                    // });
                    if (field_value.* == @field(container, decl.name)) {
                        try serializer.serialize([]const u8, &decl.name, out);
                        return;
                    }
                };
            unreachable;
        }
    }.f;
}

pub fn DeserializeFunctionFromModule(
    comptime T: type,
    field: []const u8,
    container: type,
) fn (*Serializer, *_fieldType(T, field), anytype, mem.Allocator) Error!void {
    return struct {
        pub fn f(serializer: *Serializer, out: *_fieldType(T, field), in: anytype, alloc: mem.Allocator) Error!void {
            var val: []const u8 = undefined;
            try serializer.deserialize([]const u8, &val, in, alloc);
            defer alloc.free(val);
            inline for (@typeInfo(container).@"struct".decls) |decl| {
                if (comptime mem.eql(u8, field, decl.name))
                    out.* = @field(container, field);
            }
        }
    }.f;
}

pub const Serializer = struct {
    stderr: std.fs.File,
    debug: bool = false,
    fields: std.ArrayList(struct { name: []const u8, ty: []const u8 }),
    indent: usize = 0,

    fn debugLog(self: *Serializer, comptime fmt: []const u8, args: anytype) void {
        if (!self.debug)
            return;

        var w = self.stderr.writer();
        for (0..self.indent) |_|
            w.print("  ", .{}) catch unreachable;
        w.print(fmt, args) catch unreachable;
    }

    fn debugField(self: *Serializer, name: []const u8, ty: []const u8) void {
        self.fields.append(.{ .name = name, .ty = ty }) catch unreachable;
        self.debugLog("-> {s} ('{s}')\n", .{ ty, name });
    }

    fn debugFieldPop(self: *Serializer) void {
        _ = self.fields.pop().?;
    }

    fn debugFieldsPrint(self: *Serializer) void {
        for (self.fields.items) |f|
            self.debugLog("{s}.", .{f.name});
    }

    pub fn serializeWE(self: *Serializer, comptime T: type, obj: *const T, out: anytype) Error!void {
        try self.serializeScalar(TypeId, _typeId(T), out);
        try self.serialize(T, obj, out);
    }

    pub fn serializeScalar(self: *Serializer, comptime T: type, obj: T, out: anytype) Error!void {
        switch (@typeInfo(T)) {
            .bool => try write(u8, if (obj) @as(u8, 1) else 0, out),
            .int => try write(_normIntT(T), obj, out),
            .float => {
                const F = if (T == f32) u32 else u64;
                try write(F, @bitCast(obj), out);
            },
            .@"enum" => |e| try self.serializeScalar(e.tag_type, @intFromEnum(obj), out),
            else => @compileError("Cannot serialize non-scalar " ++ @typeName(T)),
        }
    }

    pub fn serialize(self: *Serializer, comptime T: type, obj: *const T, p_out: anytype) Error!void {
        self.debugLog("* Serializing {} ...\n", .{T});
        self.indent += 1;
        defer self.indent -= 1;

        var counting_writer = std.io.countingWriter(p_out);
        defer if (is_benchmarking) benchmarker.record(@typeName(T), counting_writer.bytes_written);
        const out = counting_writer.writer();

        if (comptime mem.startsWith(u8, @typeName(T), "hash_map.HashMap")) {
            try self.serializeScalar(usize, obj.count(), out);
            var iter = obj.iterator();
            while (iter.next()) |entry| {
                try self.serialize(@TypeOf(entry.key_ptr.*), entry.key_ptr, out);
                try self.serialize(@TypeOf(entry.value_ptr.*), entry.value_ptr, out);
            }
            return;
        } else if (comptime mem.startsWith(u8, @typeName(T), "array_list.ArrayList")) {
            try self.serialize(@TypeOf(obj.items), &obj.items, out);
            return;
        }

        switch (@typeInfo(T)) {
            .bool, .int, .float, .@"enum" => try self.serializeScalar(T, obj.*, out),
            .pointer => |p| switch (p.size) {
                .one => {
                    const is_game_data_ref = switch (@typeInfo(p.child)) {
                        .@"struct", .@"union", .@"enum", .@"opaque" => !@hasDecl(p.child, "__SER_ALWAYS_OWNED"),
                        else => true,
                    };

                    if (is_game_data_ref) {
                        const ptrval = @intFromPtr(obj.*);
                        if (!ptrtable.contains(ptrval)) {
                            std.log.warn("serialize: found {} pointer {x} not in table (child of {})", .{ p.child, ptrval, T });
                            const maybe_id: ?[]const u8 = switch (p.child) {
                                types.Weapon, types.Material => obj.*.id,
                                else => null,
                            };
                            if (maybe_id) |id|
                                std.log.warn("Pointer object id: {s}", .{id});
                        }
                        try self.serializeScalar(usize, ptrval, out);
                    } else {
                        std.log.info("Treated {} as owned data, serializing as {}", .{ T, p.child });
                        try self.serialize(p.child, obj.*, out);
                    }
                },
                .slice => {
                    try self.serializeScalar(usize, obj.len, out);
                    for (obj.*) |*value| try self.serialize(p.child, value, out);
                },
                .many, .c => @compileError("Cannot serialize " ++ @typeName(T)),
            },
            .array => |a| {
                try self.serializeScalar(usize, a.len, out);
                for (obj) |*value| try self.serialize(a.child, value, out);
            },
            .@"struct" => |info| {
                if (comptime @hasDecl(T, "serialize")) {
                    try T.serialize(obj, self, out);
                } else {
                    if (@hasDecl(T, "__SER_GET_ID")) {
                        comptime assert(@hasDecl(T, "__SER_GET_PROTO"));
                        try self.serialize([]const u8, &obj.__SER_GET_ID(), out);
                    }

                    const noser = if (@hasDecl(T, "__SER_SKIP")) T.__SER_SKIP else [_][]const u8{};
                    inline for (info.fields) |field| {
                        const noser_field = comptime for (noser ++ FIELDS_ALWAYS_SKIP_LIST) |item| {
                            @setEvalBranchQuota(9999);
                            if (mem.eql(u8, item, field.name)) break true;
                        } else false;
                        if (!noser_field) {
                            self.debugField(field.name, @typeName(field.type));
                            defer self.debugFieldPop();
                            // std.log.debug("Ser {s: <20} ({s})", .{ field.name, @typeName(field.type) });

                            try self.serializeScalar(TypeId, _typeId(field.type), out);

                            if (@hasDecl(T, "__SER_FIELDW_" ++ field.name)) {
                                comptime assert(@hasDecl(T, "__SER_FIELDR_" ++ field.name));
                                try @field(T, "__SER_FIELDW_" ++ field.name)(obj, self, &@field(obj, field.name), out);
                            } else {
                                const ptr = &@field(obj, field.name);

                                // Need to treat some pointers specially if they have weird alignment.
                                // (Obviously we can't just deref all fields, because that'd lead to stack overflows
                                // in case of huge types/arrays.)
                                //
                                // Non-ordinary pointer...
                                if (@TypeOf(ptr) != *const field.type) {
                                    const value = ptr.*;
                                    try self.serialize(field.type, &value, out);
                                }
                                // Ordinary pointer
                                else {
                                    try self.serialize(field.type, &@field(obj, field.name), out);
                                }
                            }
                            // } else {
                            //     std.log.info("-> {} ('{s}') (skipping)", .{ field.type, field.name });
                        }
                    }
                }
            },
            .optional => |o| if (obj.*) |v| {
                try self.serializeScalar(u8, 1, out);
                try self.serialize(o.child, &v, out);
            } else {
                try self.serializeScalar(u8, 0, out);
            },
            .@"union" => |u| {
                const tag = meta.activeTag(obj.*);
                try self.serializeScalar(meta.Tag(T), tag, out);
                inline for (u.fields) |ufield|
                    if (mem.eql(u8, ufield.name, @tagName(tag))) {
                        if (ufield.type != void)
                            try self.serialize(ufield.type, &@field(obj, ufield.name), out);
                        break;
                    };
            },
            else => @compileError("Cannot serialize " ++ @typeName(T)),
        }
    }

    pub fn deserializeQ(self: *Serializer, comptime T: type, in: anytype, alloc: mem.Allocator) Error!T {
        var r: T = undefined;
        try self.deserialize(T, &r, in, alloc);
        return r;
    }

    pub fn deserializeExpect(self: *Serializer, comptime T: type, in: anytype, alloc: mem.Allocator) !void {
        const data_type_id = try self.deserializeQ(TypeId, in, alloc);
        const data_type_id_str = typelist.get(data_type_id);

        if (data_type_id != _typeId(T)) {
            if (data_type_id_str) |f| {
                std.log.err("Deserialization: expected type {}, found {s}", .{ T, f });
                return error.MismatchedType;
            } else {
                std.log.err("Deserialization: expected type {}, found corrupted data", .{T});
                return error.CorruptedData;
            }
        }
    }

    pub fn deserializeWE(self: *Serializer, comptime T: type, out: *T, in: anytype, alloc: mem.Allocator) Error!void {
        try self.deserializeExpect(T, in, alloc);
        try self.deserialize(T, out, in, alloc);
    }

    pub fn deserialize(self: *Serializer, comptime T: type, out: *T, in: anytype, alloc: mem.Allocator) Error!void {
        self.debugLog("* Deserializing {} ...\n", .{T});
        self.indent += 1;
        defer self.indent -= 1;

        if (comptime mem.startsWith(u8, @typeName(T), "hash_map.HashMap")) {
            const K = _fieldType(@field(T, "KV"), "key");
            const V = _fieldType(@field(T, "KV"), "value");
            var obj = T.init(state.alloc);
            var i = try self.deserializeQ(usize, in, alloc);
            std.log.info("* hash map entries: {}", .{i});
            while (i > 0) : (i -= 1) {
                const k = try self.deserializeQ(K, in, alloc);
                const v = try self.deserializeQ(V, in, alloc);
                try obj.putNoClobber(k, v);
            }
            out.* = obj;
            return;
        } else if (comptime mem.startsWith(u8, @typeName(T), "array_list.ArrayList")) {
            out.* = std.ArrayList(meta.Elem(_fieldType(T, "items"))).init(alloc);
            var i = try self.deserializeQ(usize, in, alloc);
            while (i > 0) : (i -= 1)
                try out.append(try self.deserializeQ(meta.Elem(_fieldType(T, "items")), in, alloc));
            return;
        }

        switch (@typeInfo(T)) {
            .bool => out.* = (try read(u8, in)) == 1,
            .int => out.* = @intCast(try read(_normIntT(T), in)),
            .float => out.* = @bitCast(try read(if (T == f32) u32 else u64, in)),
            .pointer => |p| switch (p.size) {
                .one => {
                    const is_game_data_ref = switch (@typeInfo(p.child)) {
                        .@"struct", .@"union", .@"enum", .@"opaque" => !@hasDecl(p.child, "__SER_ALWAYS_OWNED"),
                        else => true,
                    };

                    if (!is_game_data_ref) {
                        std.log.info("Treated {} as owned data, deserializing as {}", .{ T, p.child });
                        // FIXME: we don't do a heap allocation here. This is fine
                        // for the one and only __SER_ALWAYS_OWNED type as of
                        // writing this (Dungeon), since initGameState should take
                        // care of that, but it definitely won't work if there are
                        // other owned types in the future that appear inside other
                        // non-inited containers.
                        try self.deserialize(p.child, out.*, in, alloc);
                    } else {
                        const ptr = try self.deserializeQ(usize, in, alloc);
                        if (ptrtable.get(ptr)) |ptrdata| {
                            if (!mem.eql(u8, ptrdata.ptrtype, @typeName(T))) {
                                std.log.err("Wanted pointer of type {}, found {s}", .{ T, ptrdata.ptrtype });
                                return error.MismatchedPointerTypes;
                            }

                            inline for (STATIC_CONTAINERS) |container|
                                if (container.t == T) {
                                    if (mem.eql(u8, container.m, ptrdata.container)) {
                                        out.* = container.s.*[ptrdata.index];
                                        return;
                                    }
                                } else if (*const container.t == T) {
                                    if (mem.eql(u8, container.m, ptrdata.container)) {
                                        out.* = &container.s.*[ptrdata.index];
                                        return;
                                    }
                                };

                            inline for (@typeInfo(state).@"struct".decls) |declinfo|
                                if (@typeInfo(@TypeOf(@field(state, declinfo.name))) == .@"struct" and
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
                    }
                },
                .slice => {
                    var i = try self.deserializeQ(usize, in, alloc);
                    self.debugFieldsPrint();
                    self.debugLog(": Allocating {} blocks...\n", .{i});
                    if (i > 0) {
                        var o = try alloc.alloc(p.child, i);
                        while (i > 0) : (i -= 1)
                            try self.deserialize(p.child, &o[o.len - i], in, alloc);
                        out.* = o;
                    } else {
                        out.* = &[0]p.child{};
                    }
                },
                .many, .c => @compileError("Cannot deserialize " ++ @typeName(T)),
            },
            .array => {
                var i = try self.deserializeQ(usize, in, alloc);
                assert(i == out.len);
                while (i > 0) : (i -= 1)
                    try self.deserialize(meta.Child(T), &out[out.len - 1], in, alloc);
            },
            .@"struct" => |info| {
                if (@hasDecl(T, "deserialize")) {
                    try T.deserialize(self, out, in, alloc);
                } else {
                    const oldobj = out.*;

                    if (@hasDecl(T, "__SER_GET_PROTO")) {
                        comptime assert(@hasDecl(T, "__SER_GET_ID"));
                        const id = try self.deserializeQ([]const u8, in, alloc);
                        defer alloc.free(id);
                        out.* = T.__SER_GET_PROTO(id);
                        self.debugLog("Used prototype (id: {s})\n", .{id});
                    }

                    const noser = if (@hasDecl(T, "__SER_SKIP")) T.__SER_SKIP else [_][]const u8{};
                    inline for (info.fields) |field| {
                        const noser_field = comptime for (noser ++ FIELDS_ALWAYS_SKIP_LIST) |item| {
                            @setEvalBranchQuota(9999);
                            if (mem.eql(u8, item, field.name)) break true;
                        } else false;
                        const keep_field = comptime for (FIELDS_ALWAYS_KEEP_LIST) |item| {
                            @setEvalBranchQuota(9999);
                            if (mem.eql(u8, item, field.name)) break true;
                        } else false;
                        if (!noser_field) {
                            self.debugField(field.name, @typeName(field.type));
                            defer self.debugFieldPop();
                            // std.log.debug("Deser {s: <20} ({s})", .{
                            //     field.name,
                            //     @typeName(field.type),
                            // });

                            try self.deserializeExpect(field.type, in, alloc);

                            if (@hasDecl(T, "__SER_FIELDR_" ++ field.name)) {
                                comptime assert(@hasDecl(T, "__SER_FIELDW_" ++ field.name));
                                try @field(T, "__SER_FIELDR_" ++ field.name)(self, &@field(out, field.name), in, alloc);
                            } else {
                                const ptr = &@field(out, field.name);

                                // Need to treat some pointers specially if they have weird alignment.
                                // (Obviously we can't just deref all fields, because that'd lead to stack overflows
                                // in case of huge types/arrays.)
                                //
                                // Non-ordinary pointer...
                                if (@TypeOf(ptr) != *field.type) {
                                    @field(out, field.name) = try self.deserializeQ(field.type, in, alloc);
                                }
                                // Ordinary pointer
                                else {
                                    try self.deserialize(field.type, ptr, in, alloc);
                                }
                            }

                            // switch (@typeInfo(field.type)) {
                            //     .pointer => if (field.type == []const u8) std.log.debug("Deser value: {s}", .{@field(out, field.name)}) else std.log.debug("Deser value: skip", .{}),
                            //     .array => std.log.debug("Deser value: {any}", .{@field(out, field.name)}),
                            //     .@"bool", .@"enum", .int, .float => {
                            //         std.log.debug("Deser value: {}", .{@field(out, field.name)});
                            //     },
                            //     else => {
                            //         if (field.type == ?[]const u8) {
                            //             if (@field(out, field.name)) |v|
                            //                 std.log.debug("Deser value: {s}", .{v})
                            //             else
                            //                 std.log.debug("Deser value: null", .{});
                            //         } else if (field.type == ?types.Damage or
                            //             field.type == ?types.Direction)
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
            .optional => |o| {
                const flag = try self.deserializeQ(u8, in, alloc);
                out.* = if (flag == 0) null else @as(T, try self.deserializeQ(o.child, in, alloc));
            },
            .@"enum" => |e| out.* = @enumFromInt(try self.deserializeQ(e.tag_type, in, alloc)),
            .@"union" => |u| {
                const tag = try self.deserializeQ(meta.Tag(T), in, alloc);
                inline for (u.fields) |ufield|
                    if (mem.eql(u8, ufield.name, @tagName(tag)))
                        // Can't break here due to Zig comptime control-flow bug
                        if (ufield.type == void) {
                            out.* = @unionInit(T, ufield.name, {});
                        } else {
                            const value = try self.deserializeQ(ufield.type, in, alloc);
                            out.* = @unionInit(T, ufield.name, value);
                        };
            },
            else => @compileError("Cannot deserialize " ++ @typeName(T)),
        }
    }
};

pub fn buildPointerTable() void {
    ptrtable = PtrTable.init(state.alloc);

    inline for (STATIC_CONTAINERS) |container| {
        const Ptr = if (@typeInfo(container.t) == .pointer) container.t else *const container.t;

        for (container.s.*, 0..) |*item, ind| {
            const ptr: Ptr = if (@typeInfo(container.t) == .pointer) item.* else item;

            ptrtable.putNoClobber(@intFromPtr(ptr), .{
                .container = container.m,
                .index = ind,
                .ptrtype = @typeName(Ptr),
            }) catch err.wat();
        }
    }

    inline for (@typeInfo(state).@"struct".decls) |declinfo| {
        const decl = @field(state, declinfo.name);
        const declptr = &@field(state, declinfo.name);
        if (@typeInfo(@TypeOf(decl)) == .@"struct" and
            @hasDecl(@TypeOf(decl), "__SER_PointerDataIter"))
        {
            var max: usize = 0;
            var g = @TypeOf(decl).__SER_PointerDataIter.new(declptr);
            while (g.next()) |ptrdata2| {
                if (ptrtable.get(ptrdata2.ptr)) |otherptr| {
                    std.log.err("Pointer collision for {} (indexes: {} vs {}, types: {s} vs {s})", .{
                        ptrdata2.ptr, otherptr.index, ptrdata2.ind, otherptr.ptrtype, ptrdata2.ptrtype,
                    });
                    // it'll crash below, no need to return/raise error
                }
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
    }
}

pub fn initPointerContainers() void {
    for (ptrinits.constSlice()) |ptrinit| {
        std.log.info("* ptrinit: {s}, init to {}", .{ ptrinit.container, ptrinit.init_up_to });
        inline for (@typeInfo(state).@"struct".decls) |declinfo| {
            if (@typeInfo(@TypeOf(@field(state, declinfo.name))) == .@"struct" and
                @hasDecl(@TypeOf(@field(state, declinfo.name)), "nth"))
            {
                if (mem.eql(u8, declinfo.name, ptrinit.container)) {
                    const container = &@field(state, declinfo.name);
                    std.log.info("* initing {s}", .{declinfo.name});
                    var i: usize = ptrinit.init_up_to -| container.len();
                    while (i > 0) : (i -= 1) {
                        container.append(undefined) catch err.wat();
                    }
                }
            }
        }
    }
}

pub fn serializeWorld() !void {
    is_benchmarking = true;
    benchmarker.init();

    // if (true)
    //     @compileError(
    //         \\ Stop, you forgot about Angels.
    //         \\
    //         \\ Mob serialization assumes that spell list will be immutable,
    //         \\ but angels violate this principle. (Probably other fields that
    //         \\ I'm forgetting now as well.)
    //         \\
    //         \\ In theory we can regenerate angels on deserialization just fine given the
    //         \\ seed. But this will have to be tested.
    //     );

    // var tar = try microtar.MTar.init("dump.tar", "w");
    // defer tar.deinit();

    var f = std.fs.cwd().createFile("dump.dat", .{}) catch err.wat();
    defer f.close();

    // tar.writer()
    //
    // - ptrtable.dat, ptrinits.dat, mobs.dat

    buildPointerTable();

    // var iter = ptrtable.iterator();
    // while (iter.next()) |item| {
    //     std.log.debug("ptr entry: 0x{X:0>16} -> {: >4} @ {s: >16} ({s})", .{
    //         item.key_ptr.*, item.value_ptr.index, item.value_ptr.container, item.value_ptr.ptrtype,
    //     });
    // }

    var ser = Serializer{
        .fields = .init(state.alloc),
        .stderr = std.io.getStdErr(),
    };

    try ser.serializeWE(@TypeOf(ptrtable), &ptrtable, f.writer());
    try ser.serializeWE(@TypeOf(ptrinits), &ptrinits, f.writer());

    inline for (GAME_OBJECTS) |gobj| {
        const T, const ptr = gobj;
        try ser.serializeWE(T, ptr, f.writer());
    }

    benchmarker.print();
    benchmarker.deinit();
    is_benchmarking = false;
}

pub fn deserializeWorld() !void {
    const alloc = state.alloc;

    // var tar = try microtar.MTar.init("dump.tar", "w");
    // defer tar.deinit();

    var f = std.fs.cwd().openFile("dump.dat", .{}) catch err.wat();
    defer f.close();

    var ser = Serializer{
        .fields = .init(alloc),
        .stderr = std.io.getStdErr(),
        .debug = true,
    };

    try ser.deserializeWE(@TypeOf(ptrtable), &ptrtable, f.reader(), alloc);
    try ser.deserializeWE(@TypeOf(ptrinits), &ptrinits, f.reader(), alloc);
    initPointerContainers();

    inline for (GAME_OBJECTS) |gobj| {
        const T, const ptr = gobj;
        try ser.deserializeWE(T, ptr, f.reader(), alloc);
    }

    var ptrtable_iter = ptrtable.iterator();
    while (ptrtable_iter.next()) |entry| {
        alloc.free(entry.value_ptr.container);
        alloc.free(entry.value_ptr.ptrtype);
    }
}
