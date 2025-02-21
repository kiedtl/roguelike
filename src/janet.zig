const builtin = @import("builtin");

pub const c = @cImport(@cInclude("janet.h"));

const std = @import("std");
const sort = std.sort;
const mem = std.mem;
const math = std.math;

const utils = @import("utils.zig");

var janet_env: ?*c.JanetTable = null;

pub fn init() !void {
    if (c.janet_init() != 0)
        return error.JanetInitError;
    janet_env = c.janet_core_env(null);
    // c.janet_cfuns(janet_env, "oathbreaker", janet_apis);
}

pub fn loadFile(path: []const u8, alloc: mem.Allocator) !c.Janet {
    const file = try (try std.fs.cwd().openDir("data", .{})).openFile(path, .{});
    defer file.close();
    const data = try file.readToEndAlloc(alloc, std.math.maxInt(usize));
    defer alloc.free(data);

    var out: c.Janet = undefined;
    if (c.janet_dobytes(janet_env, data.ptr, @intCast(data.len), @ptrCast(path), &out) != 0) {
        return error.JanetEvalError;
    }

    return out;
}

pub fn getGlobalOfType(j_type: c_uint, name: []const u8) !c.Janet {
    const j_namesym = c.janet_symbol(name.ptr, @intCast(name.len));
    const j_binding = c.janet_resolve_ext(janet_env, j_namesym);

    return switch (j_binding.type) {
        c.JANET_BINDING_NONE => error.NoSuchGlobal,
        c.JANET_BINDING_DEF, c.JANET_BINDING_VAR => b: {
            if (c.janet_checktype(j_binding.value, j_type) == 0)
                break :b error.InvalidType;
            break :b j_binding.value;
        },
        else => error.InvalidGlobal,
    };
}

pub fn toJanet(comptime T: type, arg: T) !c.Janet {
    return switch (T) {
        c.Janet => arg,
        comptime_float, f64 => c.janet_wrap_number(@floatCast(arg)),
        usize, comptime_int => c.janet_wrap_number(@floatFromInt(arg)),
        []const u8 => c.janet_stringv(arg.ptr, @as(i32, @intCast(arg.len))),
        else => if (@typeInfo(T) == .@"struct") b: {
            const t_info = @typeInfo(T).@"struct";
            const j_table = c.janet_table(@intCast(t_info.fields.len));
            comptime var i: usize = 0;
            inline while (i < t_info.fields.len) : (i += 1) {
                const key = c.janet_keywordv(t_info.fields[i].name.ptr, @as(u32, @intCast(t_info.fields[i].name.len)));
                const val = try toJanet(t_info.fields[i].type, @field(arg, t_info.fields[i].name));
                c.janet_table_put(j_table, key, val);
            }
            if (@hasDecl(T, "__JANET_PROTOTYPE")) {
                j_table.*.proto = c.janet_unwrap_table(try getGlobalOfType(c.JANET_TABLE, T.__JANET_PROTOTYPE));
            }
            break :b c.janet_wrap_table(j_table);
        } else if (comptime utils.isZigString(T)) b: {
            break :b c.janet_stringv(arg.ptr, @intCast(arg.len));
        } else if (comptime utils.isManyItemPtr(T) or utils.isSlice(T)) b: {
            const j_array = c.janet_array(@intCast(arg.len));
            for (arg) |item|
                c.janet_array_push(j_array, try toJanet(std.meta.Elem(T), item));
            break :b c.janet_wrap_array(j_array);
        } else {
            @compileError("Unsupported argument of type `" ++ @typeName(T) ++ "` found.");
        },
    };
}

pub fn callFunction(func: []const u8, args: anytype) !c.Janet {
    //comptime assert(@Type(args == <tuple type>)); // FIXME: assert this

    const j_sym = c.janet_csymbol(@ptrCast(func));
    const j_binding = c.janet_resolve_ext(janet_env, j_sym);
    if (j_binding.type != c.JANET_BINDING_NONE) {
        if (c.janet_checktype(j_binding.value, c.JANET_FUNCTION) == 0) {
            return error.NotAFunction;
        }

        var args_buf = [1]c.Janet{undefined} ** args.len;
        const args_info = @typeInfo(@TypeOf(args)).@"struct".fields;
        comptime var i: usize = 0;
        inline while (i < args_info.len) : (i += 1) {
            const arg = @field(args, args_info[i].name);
            args_buf[i] = try toJanet(@TypeOf(arg), arg);
        }

        var res: c.Janet = undefined;
        var fiber = c.janet_current_fiber();
        const j_fn = c.janet_unwrap_function(j_binding.value);
        const sig = c.janet_pcall(j_fn, args_buf.len, &args_buf, &res, &fiber);

        return switch (sig) {
            c.JANET_SIGNAL_OK => res,
            c.JANET_SIGNAL_ERROR => b: {
                c.janet_stacktrace(fiber, res);
                break :b error.JanetError;
            },
            c.JANET_SIGNAL_DEBUG => error.JanetDebug,
            c.JANET_SIGNAL_YIELD => error.JanetYield,
            c.JANET_SIGNAL_USER0 => error.JanetUser0,
            c.JANET_SIGNAL_USER1 => error.JanetUser1,
            c.JANET_SIGNAL_USER2 => error.JanetUser2,
            c.JANET_SIGNAL_USER3 => error.JanetUser3,
            c.JANET_SIGNAL_USER4 => error.JanetUser4,
            c.JANET_SIGNAL_USER5 => error.JanetUser5,
            c.JANET_SIGNAL_USER6 => error.JanetUser6,
            c.JANET_SIGNAL_USER7 => error.JanetUser7,
            c.JANET_SIGNAL_USER8 => error.JanetUser8,
            c.JANET_SIGNAL_USER9 => error.JanetUser9,
            else => unreachable,
        };
    } else return error.NoSuchFunction;
}

pub fn deinit() void {
    c.janet_deinit();
}
