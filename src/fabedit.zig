const std = @import("std");
const math = std.math;
const mem = std.mem;

const display = @import("display.zig");
const font = @import("font.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const ui = @import("fabedit/ui.zig");

const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;

pub const EdState = struct {
    fab: *mapgen.Prefab = undefined,
    y: usize = 0,
    x: usize = 0,
};
var st = EdState{};

pub fn main() anyerror!void {
    state.sentry_disabled = true;

    font.loadFontsData();
    state.loadStatusStringInfo();
    state.loadLevelInfo();
    surfaces.readProps(state.gpa.allocator());
    literature.readPosters(state.gpa.allocator());
    mapgen.readPrefabs(state.gpa.allocator());

    defer _ = state.gpa.deinit();

    defer mapgen.s_fabs.deinit();
    defer mapgen.n_fabs.deinit();
    defer state.fab_records.deinit();

    defer {
        var iter = literature.posters.iterator();
        while (iter.next()) |poster|
            poster.deinit(state.gpa.allocator());
        literature.posters.deinit();
    }

    defer font.freeFontData();
    defer state.freeStatusStringInfo();
    defer state.freeLevelInfo();
    defer surfaces.freeProps(state.gpa.allocator());

    for (mapgen.n_fabs.items) |*fab| {
        if (mem.eql(u8, fab.name.constSlice(), "LAB_transmitter")) {
            st.fab = fab;
            std.log.info("Using {s}", .{st.fab.name.constSlice()});
        }
    }

    try ui.init();
    ui.draw(&st);

    main: while (true) {
        var evgen = Generator(display.getEvents).init(ui.FRAMERATE);
        while (evgen.next()) |ev| {
            switch (ev) {
                .Quit => break :main,
                .Resize => ui.draw(&st),
                .Wheel, .Hover, .Click => if (ui.handleMouseEvent(ev))
                    ui.draw(&st),
                .Key => |k| {
                    switch (k) {
                        else => {},
                    }
                    ui.draw(&st);
                },
                .Char => |c| {
                    switch (c) {
                        'l' => st.x = math.min(st.fab.width - 1, st.x + 1),
                        'j' => st.y = math.min(st.fab.height - 1, st.y + 1),
                        'h' => st.x -|= 1,
                        'k' => st.y -|= 1,
                        else => {},
                    }
                    ui.draw(&st);
                },
            }
        }
    }

    try ui.deinit();
}
