const fabedit = @import("../fabedit.zig");
const display = @import("../display.zig");
const state = @import("../state.zig");
const mapgen = @import("../mapgen.zig");

const Console = @import("../ui/Console.zig");

pub const FRAMERATE = 1000 / 25;

pub var map_win: struct {
    map: Console = undefined,

    pub fn init(self: *@This()) void {
        self.map = Console.init(state.gpa.allocator(), 40 * 2, 40);
    }

    pub fn handleMouseEvent(_: *@This(), ev: display.Event) bool {
        return switch (ev) {
            .Click, .Hover => false,
            .Wheel => false,
            else => unreachable,
        };
    }

    pub fn deinit(self: *@This()) void {
        self.map.deinit();
    }
} = .{};

pub var container: struct {
    win: Console = undefined,

    pub fn init(self: *@This()) void {
        self.win = Console.init(state.gpa.allocator(), (40 * 2) + 20, 40);
        self.win.addSubconsole(&map_win.map, 0, 0);
    }
} = .{};

pub fn init() !void {
    try display.init((40 * 2) + 20, 40, 1.0);
}

pub fn draw(_: *fabedit.EdState) void {}

pub fn deinit() void {
    try display.deinit();
}

pub fn handleMouseEvent(ev: display.Event) bool {
    _ = ev;
    return false;
}
