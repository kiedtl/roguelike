const std = @import("std");
const builtin = @import("builtin");

var __panic_stage: usize = 0;
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace) noreturn {
    nosuspend switch (__panic_stage) {
        0 => {
            __panic_stage = 1;
            reportError("0.1.0", null, "Panic", msg, trace, @returnAddress()) catch |err| {
                std.log.err("zig-sentry: Fail: {s}", .{@errorName(err)});
            };
            std.builtin.default_panic(msg, trace);
        },
        1 => {
            __panic_stage = 2;
            std.builtin.default_panic(msg, trace);
        },
        else => {
            std.os.abort();
        },
    };
}

pub fn reportError(release: []const u8, dist: ?[]const u8, ename: []const u8, msg: []const u8, trace: ?*std.builtin.StackTrace, addr: ?usize) !void {
    var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.timestamp()));
    var membuf: [65535]u8 = undefined;
    var alloc = std.heap.FixedBufferAllocator.init(membuf[0..]).allocator();

    const uuid = rng.random().int(u128);
    const m = try createEvent(uuid, release, dist, .Error, ename, msg, trace, addr, alloc);
    try uploadError(&m);
}

const net = @import("net.zig");

pub fn uploadError(ev: *const SentryEvent) !void {
    const HOST = "sentry.io";
    const PORT = 80;
    const DSN = "https://029cc3a31c3740d4a60e3747e48c4aa2@o110999.ingest.sentry.io/6550409";
    const DSN_HASH = "029cc3a31c3740d4a60e3747e48c4aa2";
    const DSN_ID = 6550409;
    const UA_STR = "zig-sentry";
    const UA_VER = "0.1.0";

    var membuf: [65535]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(membuf[0..]);
    var alloc = fba.allocator();

    std.log.info("zig-sentry: connecting...", .{});
    const stream = std.net.tcpConnectToHost(alloc, HOST, PORT) catch |e| return e;
    defer stream.close();

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.json.stringify(ev.sentry_event, .{ .string = .{ .String = .{} } }, fbs.writer());

    std.log.info("zig-sentry: sending content...", .{});
    try stream.writer().print("POST /api/{}/store/ HTTP/1.1\r\n", .{DSN_ID});
    try stream.writer().print("Host: {s}\r\n", .{HOST});
    try stream.writer().print("User-Agent: {s}/{s}\r\n", .{ UA_STR, UA_VER });
    try stream.writer().print("Accept: */*\r\n", .{}); // TODO: is this necessary
    try stream.writer().print("Content-Type: application/json\r\n", .{});
    try stream.writer().print("X-Sentry-Auth: Sentry sentry_key={s}\r\n", .{DSN_HASH});
    try stream.writer().print("Authorization: DSN {s}\r\n", .{DSN});
    try stream.writer().print("Content-Length: {}\r\n", .{fbs.getWritten().len});
    try stream.writer().print("\r\n", .{});
    try stream.writer().print("{s}", .{fbs.getWritten()});
    try stream.writer().print("\r\n", .{});

    // ---
    std.log.info("zig-sentry: waiting for response...", .{});
    var response: [2048]u8 = undefined;
    if (stream.read(&response)) |ret| {
        std.log.info("zig-sentry: response: {s}", .{response[0..ret]});
    } else |err| {
        std.log.info("zig-sentry: error when reading response: {s}", .{@errorName(err)});
    }
    // ---
}

pub const SentryEvent = struct {
    sentry_event: ActualEvent,
    exception: std.ArrayList(Value),
    frames: std.ArrayList(Frame),

    pub const ActualEvent = struct {
        event_id: [32]u8,
        timestamp: u64, // Seconds since Unix epoch
        level: Level = .Error,
        logger: []const u8 = "zig-sentry",
        release: []const u8,
        dist: ?[]const u8 = null,
        tags: ?TagSet,
        exception: []const Value,
    };

    pub const TagSet = struct {
        build: []const u8 = "",
        os: []const u8 = "",
        windows_version: [64]u8 = [1]u8{0} ** 64,
        zig_version: [64]u8 = [1]u8{0} ** 64,
        abi: []const u8 = "",
        cpu_arch: []const u8 = "",
        cpu_model: []const u8 = "",
    };

    const Frame = struct {
        filename: [128]u8 = [1]u8{0} ** 128,
        function: []const u8 = "???",
        lineno: ?usize = null,
        colno: ?usize = null,
    };

    pub const Value = struct {
        type: []const u8,
        value: []const u8,
        // TODO: mechanism
        stacktrace: ?StackTrace = null,
    };

    pub const StackTrace = struct {
        frames: []const Frame,
    };

    pub const Level = enum {
        Fatal,
        Error,
        Warning,
        Info,
        Debug,

        pub fn jsonStringify(val: Level, _: std.json.StringifyOptions, stream: anytype) !void {
            const s = switch (val) {
                .Fatal => "fatal",
                .Error => "error",
                .Warning => "warning",
                .Info => "info",
                .Debug => "debug",
            };
            try stream.writeByte('"');
            try stream.writeAll(s);
            try stream.writeByte('"');
        }
    };
};

pub fn createEvent(
    uuid: u128,
    release: []const u8,
    dist: ?[]const u8,
    level: SentryEvent.Level,
    error_name: []const u8,
    msg: []const u8,
    error_trace: ?*std.builtin.StackTrace,
    first_trace_addr: ?usize,
    alloc: std.mem.Allocator,
) !SentryEvent {
    var uuid_buf: [32]u8 = [1]u8{'0'} ** 32;
    {
        var x: u128 = 16;
        var d: usize = 0;
        while (x < uuid and x != std.math.maxInt(u128)) : (d += 1)
            x *|= 16;
        x /= 16;

        var y: usize = 0;
        while (x > 0) : (x /= 16) {
            const v = @intCast(u8, (uuid / x) % 16);
            uuid_buf[y] = if (v > 9) @as(u8, 'a') + (v - 10) else '0' + v;
            y += 1;
        }
        while (y < 32) : (y += 1)
            uuid_buf[y] = '0';
    }

    const timestamp = @intCast(u64, std.time.timestamp());

    var values = std.ArrayList(SentryEvent.Value).init(alloc);
    var frames = std.ArrayList(SentryEvent.Frame).init(alloc);

    const debug_info: ?*std.debug.DebugInfo = std.debug.getSelfDebugInfo() catch null;
    if (!builtin.strip_debug_info and debug_info != null and builtin.os.tag != .windows) {
        if (error_trace) |trace| {
            try values.append(try recordError(&frames, debug_info.?, error_name, msg, trace));
        }

        if (first_trace_addr) |addr| {
            const STACK_SIZE = 32;
            var addresses: [STACK_SIZE]usize = [1]usize{0} ** STACK_SIZE;
            var stack_trace = std.builtin.StackTrace{ .instruction_addresses = &addresses, .index = 0 };
            std.debug.captureStackTrace(addr, &stack_trace);
            try values.append(try recordError(&frames, debug_info.?, error_name, msg, &stack_trace));
        }
    }

    var tagset = SentryEvent.TagSet{};
    {
        tagset.build = @tagName(builtin.mode);
        tagset.os = @tagName(builtin.os.tag);
        if (builtin.os.tag == .windows) {
            var winver_fbs = std.io.fixedBufferStream(&tagset.windows_version);
            try std.fmt.format(winver_fbs.writer(), "{s}", .{builtin.os.version_range.windows});
        }
        {
            var zigver_fbs = std.io.fixedBufferStream(&tagset.zig_version);
            try std.fmt.format(zigver_fbs.writer(), "{}", .{builtin.zig_version});
        }
        tagset.abi = @tagName(builtin.abi);
        tagset.cpu_arch = @tagName(builtin.cpu.arch);
        tagset.cpu_model = builtin.cpu.model.name;
    }

    return SentryEvent{
        .sentry_event = .{
            .event_id = uuid_buf,
            .timestamp = timestamp,
            .level = level,
            .release = release,
            .dist = dist,
            .exception = values.items[0..],
            .tags = tagset,
        },
        .exception = values,
        .frames = frames,
    };
}

pub fn recordError(
    frames: *std.ArrayList(SentryEvent.Frame),
    debug_info: *std.debug.DebugInfo,
    ename: []const u8,
    emsg: []const u8,
    trace: *std.builtin.StackTrace,
) !SentryEvent.Value {
    std.debug.assert(builtin.os.tag != .windows);
    std.debug.assert(!builtin.strip_debug_info);

    var frame_index: usize = 0;
    var frame_buf_start_index = frames.items.len;
    var frames_left: usize = std.math.min(trace.index, trace.instruction_addresses.len);
    var v: SentryEvent.Value = .{ .type = ename, .value = emsg };

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % trace.instruction_addresses.len;
    }) {
        const address = trace.instruction_addresses[frame_index];

        var frame: SentryEvent.Frame = .{};

        if (debug_info.getModuleForAddress(address)) |module| {
            const symb_info = try module.getSymbolAtAddress(address);
            defer symb_info.deinit();
            frame.function = symb_info.symbol_name;
            if (symb_info.line_info) |li| {
                std.mem.copy(u8, &frame.filename, li.file_name);
                frame.lineno = li.line;
                frame.colno = li.column;
            }
        } else |err| switch (err) {
            error.MissingDebugInfo, error.InvalidDebugInfo => {
                // nothing
            },
            else => return err,
        }
        try frames.append(frame);
    }

    if (frames.items.len != frame_buf_start_index) {
        std.mem.reverse(SentryEvent.Frame, frames.items[frame_buf_start_index..]);
        v.stacktrace = SentryEvent.StackTrace{
            .frames = frames.items[frame_buf_start_index..],
        };
    }

    return v;
}

pub fn actualMain() anyerror!void {
    @panic("This is a very big test");
}

pub fn main() void {
    actualMain() catch |err| {
        if (@errorReturnTrace()) |trace| {
            reportError("0.1.0", null, @errorName(err), "error", trace, null) catch |zs_err| {
                std.log.err("zig-sentry: Fail: {s}", .{@errorName(zs_err)});
            };
        }
    };
}
