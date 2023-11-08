const std = @import("std");
const math = std.math;

const ui = @import("fabedit/ui.zig");
const mapgen = @import("mapgen.zig");
const display = @import("display.zig");
const state = @import("state.zig");

const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;

pub const EdState = struct {
    fab: *mapgen.Prefab = undefined,
    y: usize = 0,
    x: usize = 0,
};
var edstate = EdState{};

pub fn main() anyerror!void {
    state.sentry_disabled = true;

    mapgen.readPrefabs(state.gpa.allocator());
    try ui.init();

    defer ui.deinit();
    defer _ = state.gpa.deinit();

    edstate.fab = &mapgen.n_fabs.items[0];

    var evgen = Generator(display.getEvents).init(ui.FRAMERATE);
    while (evgen.next()) |ev| {
        switch (ev) {
            .Quit => break,
            .Resize => ui.draw(&edstate),
            .Wheel, .Hover, .Click => if (ui.handleMouseEvent(ev))
                ui.draw(&edstate),
            .Key => |k| {
                switch (k) {
                    else => {},
                }
                ui.draw(&edstate);
            },
            .Char => |c| {
                switch (c) {
                    'j' => edstate.x = math.min(edstate.fab.width, edstate.x + 1),
                    'l' => edstate.y = math.min(edstate.fab.height, edstate.y + 1),
                    'h' => edstate.x -|= 1,
                    'k' => edstate.y -|= 1,
                    else => {},
                }
                ui.draw(&edstate);
            },
        }
    }
}
