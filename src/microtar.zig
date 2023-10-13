pub const cmtar = @cImport(@cInclude("microtar.h"));

const std = @import("std");

pub const MTar = struct {
    ctx: cmtar.mtar_t = undefined,
    write: bool = false,

    pub const Error = error{
        UnknownError,
        OpenFailure,
        ReadFailure,
        WriteFailure,
        SeekFailure,
        BadChecksum,
        NullRecord,
        NotFound,
    };

    pub inline fn errorFromC(v: c_int) Error {
        const f = switch (v) {
            cmtar.MTAR_EFAILURE => error.UnknownError,
            cmtar.MTAR_EREADFAIL => error.ReadFailure,
            cmtar.MTAR_EWRITEFAIL => error.WriteFailure,
            cmtar.MTAR_ESEEKFAIL => error.SeekFailure,
            cmtar.MTAR_EBADCHKSUM => error.BadChecksum,
            cmtar.MTAR_ENULLRECORD => error.NullRecord,
            cmtar.MTAR_EOPENFAIL => error.OpenFailure,
            cmtar.MTAR_ENOTFOUND => error.NotFound,
            else => unreachable,
        };
        std.log.info("f: {}", .{f});
        unreachable;
    }

    pub const WriterCtx = struct { mtar: *MTar, header: []const u8 };
    pub const Writer = std.io.Writer(WriterCtx, Error, write);

    pub const ReaderCtx = struct { mtar: *MTar, header: []const u8 };
    pub const Reader = std.io.Reader(ReaderCtx, Error, read);

    pub fn init(file: []const u8, mode: [:0]const u8) !@This() {
        var tar: cmtar.mtar_t = undefined;
        return switch (cmtar.mtar_open(&tar, file.ptr, mode)) {
            cmtar.MTAR_ESUCCESS => .{ .ctx = tar, .write = mode[0] == 'w' },
            else => |v| errorFromC(v),
        };
    }

    pub fn deinit(self: *@This()) !void {
        if (self.write) {
            const r1 = cmtar.mtar_finalize(&self.ctx);
            if (r1 != cmtar.MTAR_ESUCCESS) return errorFromC(r1);
        }
        const artoo = cmtar.mtar_close(&self.ctx);
        if (artoo != cmtar.MTAR_ESUCCESS) return errorFromC(artoo);
    }

    pub fn writer(self: *@This(), header: [:0]const u8) Error!Writer {
        var h: cmtar.mtar_header_t = undefined;
        const already_has = while (cmtar.mtar_read_header(&self.ctx, &h) == cmtar.MTAR_ESUCCESS) {
            if (std.mem.eql(u8, header, std.mem.span(&h.name))) break true;
        } else false;

        if (!already_has) {
            const r = cmtar.mtar_write_file_header(&self.ctx, header.ptr, @intCast(c_uint, header.len));
            if (r != cmtar.MTAR_ESUCCESS) return errorFromC(r);
        } else @panic("nah"); // TODO: see if mtar library can seek to area and append

        return Writer{ .context = .{ .mtar = self, .header = header } };
    }

    pub fn write(self: WriterCtx, bytes: []const u8) Error!usize {
        switch (cmtar.mtar_write_data(&self.mtar.ctx, bytes.ptr, @intCast(c_uint, bytes.len))) {
            cmtar.MTAR_ESUCCESS => return bytes.len,
            cmtar.MTAR_EFAILURE => return error.UnknownError,
            cmtar.MTAR_EREADFAIL => return error.ReadFailure,
            cmtar.MTAR_EWRITEFAIL => return error.WriteFailure,
            cmtar.MTAR_ESEEKFAIL => return error.SeekFailure,
            cmtar.MTAR_EBADCHKSUM => return error.BadChecksum,
            cmtar.MTAR_ENULLRECORD => return error.NullRecord,
            else => unreachable,
        }
    }

    pub fn reader(self: *@This(), header: [:0]const u8) Error!Reader {
        const r = cmtar.mtar_find(&self.ctx, header.ptr, null);
        if (r != cmtar.MTAR_ESUCCESS) return errorFromC(r);

        return Reader{ .context = .{ .mtar = self, .header = header } };
    }

    pub fn read(self: ReaderCtx, buffer: []u8) Error!usize {
        const r = cmtar.mtar_read_data(&self.mtar.ctx, buffer.ptr, @intCast(c_uint, buffer.len));
        return switch (r) {
            cmtar.MTAR_ESUCCESS => buffer.len,
            else => return errorFromC(r),
        };
    }
};
