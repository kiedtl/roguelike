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
const sort = std.sort;
const builtin = @import("builtin");

const curl = @import("curl");
const Easy = curl.Easy;

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

        pub fn jsonStringify(val: TagSet, jw: anytype) !void {
            // try stream.write('{');
            // for (val.inner.items, 0..) |tag, i| {
            //     try stream.write('"');
            //     try stream.write(tag.name);
            //     try stream.write('"');
            //     try stream.write(':');
            //     try stream.write('"');
            //     try stream.write(tag.value);
            //     try stream.write('"');
            //     if (i < val.inner.items.len - 1)
            //         try stream.write(',');
            // }
            // try stream.write('}');
            try jw.beginObject();
            for (val.inner.items) |tag| {
                try jw.objectField(tag.name);
                try jw.write(tag.value);
            }
            try jw.endObject();
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

        pub fn jsonStringify(val: Level, jws: anytype) !void {
            const s: []const u8 = switch (val) {
                .Fatal => "fatal",
                .Error => "error",
                .Warning => "warning",
                .Info => "info",
                .Debug => "debug",
            };
            try jws.write(s);
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
    var rng = std.Random.DefaultPrng.init(@intCast(std.time.timestamp()));
    const uuid = rng.random().int(u128);

    const m = try createEvent(uuid, release, dist, .Error, ename, msg, user_tags, trace, addr, alloc);
    try uploadError(&m, alloc);
}

fn uploadError(ev: *const SentryEvent, alloc: std.mem.Allocator) !void {
    const HOST = "sentry.io";
    const PORT = 443;
    const UA_STR = "zig-sentry";
    const UA_VER = "0.1.0";

    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    std.log.info("*** zig-sentry: connecting to {s}:{}", .{ HOST, PORT });

    const ca_bundle = try curl.allocCABundle(alloc);
    defer ca_bundle.deinit();
    const easy = try Easy.init(.{ .ca_bundle = ca_bundle });
    defer easy.deinit();

    const body = try std.json.stringifyAlloc(alloc, ev.sentry_event, .{});
    defer alloc.free(body);

    const headers = blk: {
        var h: Easy.Headers = .{};
        errdefer h.deinit();
        try h.add("Accept: */*");
        try h.add("Content-Type: application/json");
        try h.add(std.fmt.comptimePrint("User-Agent: {s}/{s}", .{ UA_STR, UA_VER }));
        try h.add(std.fmt.comptimePrint("X-Sentry-Auth: Sentry sentry_key={s}", .{DSN_HASH}));
        try h.add(std.fmt.comptimePrint("Authorization: DSN {s}", .{DSN}));
        break :blk h;
    };
    defer headers.deinit();

    try easy.setUrl(std.fmt.comptimePrint("https://sentry.io/api/{}/store/", .{DSN_ID}));
    try easy.setHeaders(headers);
    try easy.setMethod(.POST);
    try easy.setPostFields(body);

    var writer = curl.ResizableResponseWriter.init(alloc);
    defer writer.deinit();
    try easy.setAnyWriter(&writer.asAny());

    const resp = try easy.perform();
    std.log.info("*** zig-sentry: Status code: {d}", .{resp.status_code});
    std.log.info("*** zig-sentry: Response body: {s}", .{writer.asSlice()});
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
            const v: u8 = @intCast((uuid / x) % 16);
            uuid_buf[y] = if (v > 9) @as(u8, 'a') + (v - 10) else '0' + v;
            y += 1;
        }
        while (y < 32) : (y += 1)
            uuid_buf[y] = '0';
    }

    const timestamp: u64 = @intCast(std.time.timestamp());

    var values = std.ArrayList(SentryEvent.Value).init(alloc);
    var frames = std.ArrayList(SentryEvent.Frame).init(alloc);

    const debug_info = std.debug.getSelfDebugInfo() catch null;
    if (!builtin.strip_debug_info and debug_info != null and builtin.os.tag != .windows) {
        if (error_trace) |trace| {
            try values.append(try recordError(&frames, debug_info.?, error_name, msg, trace, alloc));
        }

        if (first_trace_addr) |addr| {
            const STACK_SIZE = 32;
            var addresses: [STACK_SIZE]usize = [1]usize{0} ** STACK_SIZE;
            var stack_trace = std.builtin.StackTrace{ .instruction_addresses = &addresses, .index = 0 };
            std.debug.captureStackTrace(addr, &stack_trace);
            try values.append(try recordError(&frames, debug_info.?, error_name, msg, &stack_trace, alloc));
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
    debug_info: *std.debug.SelfInfo,
    ename: []const u8,
    emsg: []const u8,
    trace: *std.builtin.StackTrace,
    alloc: std.mem.Allocator,
) !SentryEvent.Value {
    std.debug.assert(builtin.os.tag != .windows);
    std.debug.assert(!builtin.strip_debug_info);

    var frame_index: usize = 0;
    const frame_buf_start_index = frames.items.len;
    var frames_left: usize = @min(trace.index, trace.instruction_addresses.len);
    var v: SentryEvent.Value = .{ .type = ename, .value = emsg };

    while (frames_left != 0) : ({
        frames_left -= 1;
        frame_index = (frame_index + 1) % trace.instruction_addresses.len;
    }) {
        const address = trace.instruction_addresses[frame_index];

        var frame: SentryEvent.Frame = .{};

        if (debug_info.getModuleForAddress(address)) |module| {
            const symb_info = try module.getSymbolAtAddress(alloc, address);
            // MIGRATION defer symb_info.deinit(fba.allocator());
            frame.function = symb_info.name;
            std.log.info("function: {s}", .{frame.function});
            if (symb_info.source_location) |li| {
                std.mem.copyForwards(u8, &frame.filename, li.file_name);
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
