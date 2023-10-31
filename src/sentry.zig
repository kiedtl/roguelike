// zig-sentry Sentry SDK.
// (c) Kiëd Llaentenn 2022
//
// ## TODO list to make this a standalone library:
// - Completely rework the API to be more like standard SDK APIs
// - DSN configuration/parsing
// - Gracefully failing when unable to connect to sentry server
// - Setting `extra' data
// - Support for Windows
// - Logging framework integration?
// - Non-blocking event submission (if possible, not high priority)
// - Context data helpers (e.g. setting current user)
// - Event sampling
// - Honor Sentry's Rate Limiting HTTP headers
// - Pre/Post event send hooks
// - Check if it's possible to get local variable values in stack trace
// - Send an `environment` on each event
// - gzip/zlib-deflate/brotli compression of payload
// - Gracefully handle non-200 responses from Sentry
// - Support for threads
// - Support for async

const std = @import("std");
const builtin = @import("builtin");

// TODO: *don't* encode this in here
const DSN = "http://029cc3a31c3740d4a60e3747e48c4aa2@o110999.ingest.sentry.io/6550409";
const DSN_HASH = "029cc3a31c3740d4a60e3747e48c4aa2";
const DSN_ID = 6550409;

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
        tags: TagSet,
        exception: []const Value,
    };

    pub const TagSet = struct {
        inner: std.ArrayList(Tag),

        pub const Tag = struct {
            name: []const u8,
            value: []const u8,
        };

        pub fn jsonStringify(val: TagSet, _: std.json.StringifyOptions, stream: anytype) !void {
            try stream.writeByte('{');
            for (val.inner.items) |tag, i| {
                try stream.writeByte('"');
                try stream.writeAll(tag.name);
                try stream.writeByte('"');
                try stream.writeByte(':');
                try stream.writeByte('"');
                try stream.writeAll(tag.value);
                try stream.writeByte('"');
                if (i < val.inner.items.len - 1)
                    try stream.writeByte(',');
            }
            try stream.writeByte('}');
        }
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

pub fn captureError(
    release: []const u8,
    dist: ?[]const u8,
    ename: []const u8,
    msg: []const u8,
    user_tags: []const SentryEvent.TagSet.Tag,
    trace: ?*std.builtin.StackTrace,
    addr: ?usize,
    alloc: std.mem.Allocator,
) !void {
    var rng = std.rand.DefaultPrng.init(@intCast(u64, std.time.timestamp()));
    const uuid = rng.random().int(u128);

    std.log.info("*** zig-sentry: uploading crash report", .{});
    const m = try createEvent(uuid, release, dist, .Error, ename, msg, user_tags, trace, addr, alloc);
    try uploadError(&m, alloc);
    std.log.info("*** zig-sentry: done", .{});
}

fn uploadError(ev: *const SentryEvent, alloc: std.mem.Allocator) !void {
    const HOST = "sentry.io";
    const PORT = 80;
    const UA_STR = "zig-sentry";
    const UA_VER = "0.1.0";

    std.log.debug("zig-sentry: connecting...", .{});
    const stream = std.net.tcpConnectToHost(alloc, HOST, PORT) catch |e| return e;
    defer stream.close();

    var buf: [65535]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try std.json.stringify(ev.sentry_event, .{ .string = .{ .String = .{} } }, fbs.writer());

    std.log.debug("zig-sentry: sending content...", .{});
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
    std.log.debug("zig-sentry: waiting for response...", .{});
    var response: [2048]u8 = undefined;
    if (stream.read(&response)) |ret| {
        var lines = std.mem.tokenize(u8, response[0..ret], "\n");
        while (lines.next()) |line|
            std.log.debug("zig-sentry: response: > {s}", .{line});
    } else |err| {
        std.log.debug("zig-sentry: error when reading response: {s}", .{@errorName(err)});
    }
    // ---
}

pub fn createEvent(
    uuid: u128,
    release: []const u8,
    dist: ?[]const u8,
    level: SentryEvent.Level,
    error_name: []const u8,
    msg: []const u8,
    user_tags: []const SentryEvent.TagSet.Tag,
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

    var tagset = SentryEvent.TagSet{ .inner = std.ArrayList(SentryEvent.TagSet.Tag).init(alloc) };
    {
        try tagset.inner.append(.{ .name = "build", .value = @tagName(builtin.mode) });
        try tagset.inner.append(.{ .name = "os", .value = @tagName(builtin.os.tag) });
        if (builtin.os.tag == .windows) {
            const v = try std.fmt.allocPrint(alloc, "{s}", .{builtin.os.version_range.windows});
            try tagset.inner.append(.{ .name = "windows_version", .value = v });
        }
        {
            const v = try std.fmt.allocPrint(alloc, "{}", .{builtin.zig_version});
            try tagset.inner.append(.{ .name = "zig_version", .value = v });
        }
        try tagset.inner.append(.{ .name = "abi", .value = @tagName(builtin.abi) });
        try tagset.inner.append(.{ .name = "cpu_arch", .value = @tagName(builtin.cpu.arch) });
        try tagset.inner.append(.{ .name = "cpu_model", .value = builtin.cpu.model.name });

        for (user_tags) |tag|
            try tagset.inner.append(tag);
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
            std.log.info("function: {s}", .{frame.function});
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
