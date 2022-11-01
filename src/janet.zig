const c = @cImport(@cInclude("janet.h"));

const std = @import("std");
const mem = std.mem;
const math = std.math;

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
    const data = try file.readToEndAlloc(alloc, math.maxInt(usize));
    defer alloc.free(data);

    var out: c.Janet = undefined;
    if (c.janet_dobytes(janet_env, data.ptr, @intCast(i32, data.len), @ptrCast([*c]const u8, path), &out) != 0) {
        return error.JanetEvalError;
    }

    return out;
}

pub fn callFunction(func: []const u8, comptime args: anytype) !void {
    //comptime assert(@Type(args == <tuple type>)); // FIXME: assert this

    const j_sym = c.janet_csymbol(@ptrCast([*c]const u8, func));
    const j_binding = c.janet_resolve_ext(janet_env, j_sym);
    if (j_binding.type != c.JANET_BINDING_NONE) {
        if (c.janet_checktype(j_binding.value, c.JANET_FUNCTION) == 0) {
            return error.NotAFunction;
        }

        var args_buf = [1]c.Janet{undefined} ** args.len;
        inline for (args) |arg, i| {
            const T = @TypeOf(arg);
            switch (T) {
                []const u8 => args_buf[i] = c.janet_stringv(arg.ptr, @intCast(i32, arg.len)),
                comptime_float, f64 => args_buf[i] = c.janet_wrap_number(@floatCast(f64, arg)),
                comptime_int => args_buf[i] = c.janet_wrap_number(@intToFloat(f64, arg)),
                else => @compileError("Unsupported argument of type `" ++ @typeName(T) ++ "` found."),
            }
        }

        var res: c.Janet = undefined;
        var fiber = c.janet_current_fiber();
        const j_fn = c.janet_unwrap_function(j_binding.value);
        const sig = c.janet_pcall(j_fn, args_buf.len, &args_buf, &res, &fiber);

        return switch (sig) {
            c.JANET_SIGNAL_OK => {},
            c.JANET_SIGNAL_ERROR => error.JanetError, //janet_stacktrace(fiber, res);
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
