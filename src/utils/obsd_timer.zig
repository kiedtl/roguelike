const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/types.h");
    @cInclude("sys/event.h");
    @cInclude("sys/time.h");
});

// Initialized on first use of OBSDTimer. As of now, never deinited, though
// that shouldn't be a problem.
var kq: c_int = -1;

pub const OBSDTimer = struct {
    change: c.struct_kevent,
    event: c.struct_kevent,

    const Self = @This();

    pub fn new() !Self {
        if (kq == -1) {
            kq = c.kqueue();
            if (kq == -1)
                return error.CouldNotGetKqueue;
        }

        return Self {
            .change = c.struct_kevent {
                .ident = 1,
                .filter = c.EVFILT_TIMER,
                .flags = c.EV_ADD | c.EV_ENABLE | c.EV_ONESHOT,
                .fflags = c.NOTE_NSECONDS,
                .data = undefined,
                .udata = null,
            },
            .event = undefined,
        };
    }

    pub fn set(self: *Self, amount_ns: u64) !void {
        self.change.data = @intCast(amount_ns);

        if (c.kevent(kq, &self.change, 1, null, 0, null) == -1) {
            return error.CouldNotSetEvent;
        }
    }

    pub fn wait(self: *Self) void {
        while (true)
            switch (c.kevent(kq, null, 0, &self.event, 1, null)) {
                0 => unreachable, // No events somehow
                -1 => {}, // Wait
                else => break, // Event fired
            };
    }
};
