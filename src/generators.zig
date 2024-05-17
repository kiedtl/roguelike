const std = @import("std");
const mem = std.mem;
const testing = std.testing;

pub fn GeneratorCtx(comptime Out: type) type {
    return struct {
        frame: anyframe = undefined,
        out: Out = undefined,
        done: bool = false,

        const Self = @This();

        pub fn yield(self: *Self, val: Out) void {
            self.out = val;
            suspend {
                self.frame = @frame();
            }
        }

        pub fn finish(self: *Self) void {
            self.done = true;
            suspend {
                self.frame = @frame();
            }
        }
    };
}

pub fn Generator(comptime function: anytype) type {
    const Fun = @TypeOf(function);
    const info = @typeInfo(Fun).Fn;

    return struct {
        const Self = @This();

        const CtxType = @typeInfo(info.args[0].arg_type.?).Pointer.child;
        const VType = std.meta.fieldInfo(CtxType, .out).field_type;
        const ArgType = info.args[1].arg_type.?;

        frame: @Frame(function) = undefined,
        was_init: bool = false,
        ctx: CtxType = .{ .out = undefined, .done = false },
        args: ArgType,

        pub fn init(args: ArgType) Self {
            return Self{
                .args = args,
                .frame = undefined,
                .was_init = false,
                .ctx = .{},
            };
        }

        pub fn next(self: *Self) ?VType {
            if (!self.ctx.done) {
                if (self.was_init) {
                    resume self.ctx.frame;
                } else {
                    self.frame = async function(&self.ctx, self.args);
                    self.was_init = true;
                }
            }
            return if (!self.ctx.done) self.ctx.out else null;
        }
    };
}

pub fn RangeOpts(comptime T: type) type {
    return struct { from: T, to: T, inc: T = 0 };
}

pub fn RangeFn(comptime T: type) fn (*GeneratorCtx(T), args: RangeOpts(T)) void {
    return struct {
        pub fn f(ctx: *GeneratorCtx(T), args: RangeOpts(T)) void {
            var result: usize = args.from;
            while (result < args.to) {
                ctx.yield(result);
                result += args.inc;
            }

            ctx.finish();
        }
    }.f;
}

pub const rangeUsize = RangeFn(usize);

test "rangeUsize" {
    const start = 23;
    const end = 49;
    const inc = 3;

    var i: usize = 23;
    var gen = Generator(rangeUsize).init(.{ .from = start, .to = end, .inc = inc });
    while (gen.next()) |result| {
        try testing.expectEqual(i, result);
        i += inc;
    }
}
