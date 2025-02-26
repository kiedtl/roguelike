const std = @import("std");
const math = std.math;
const sort = std.sort;
const mem = std.mem;
const meta = std.meta;

const display = @import("display.zig");
const err = @import("err.zig");
const font = @import("font.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const ui = @import("fabedit/ui.zig");
const utils = @import("utils.zig");

// const Generator = @import("generators.zig").Generator;
// const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const StackBuffer = @import("buffer.zig").StackBuffer;

pub const EdState = struct {
    fab_path: []const u8 = "",
    fab_name: []const u8 = "", // fab_path trimmed of parent dir and .fab
    fab: *mapgen.Prefab = undefined,
    fab_variants: StackBuffer(*mapgen.Prefab, 32) = StackBuffer(*mapgen.Prefab, 32).init(null),
    fab_index: usize = 99999,
    fab_info: [32]FabInfo = [1]FabInfo{.{}} ** 32,
    fab_redraw: bool = true,
    hud_pane: HudPane = .Basic,
    y: usize = 0,
    x: usize = 0,
    cursor: Cursor = .{ .Basic = .Wall },

    pub const FabInfo = struct {
        unsaved: bool = false,
    };

    // TODO: terrain, mobs, machines
    pub const HudPane = enum(usize) { Basic = 0, Props = 1, Mobs = 2, Areas = 3 };

    pub const Cursor = union(enum) {
        Prop: usize, // index to surfaces.props
        Basic: BasicCursor,
        PrisonArea: usize,
        Mob: usize,

        pub fn incrBy(self: *Cursor, by: usize) void {
            switch (self.*) {
                .Prop => self.Prop = @min(surfaces.props.items.len - 1, self.Prop + by),
                .Basic => self.Basic = @enumFromInt(@min(meta.fields(BasicCursor).len - 1, @intFromEnum(self.Basic) + by)),
                .PrisonArea => self.PrisonArea = @min(st.fab.prisons.len - 1, self.PrisonArea + 1),
                .Mob => self.Mob = @min(mobs.MOBS.len - 1, self.Mob + by),
            }
        }

        pub fn decrBy(self: *Cursor, by: usize) void {
            switch (st.cursor) {
                .Prop => self.Prop -|= by,
                .Basic => self.Basic = @enumFromInt(@intFromEnum(self.Basic) -| by),
                .PrisonArea => self.PrisonArea -|= 1,
                .Mob => self.Mob -|= by,
            }
        }
    };

    pub const BasicCursor = enum(usize) {
        Wall = 0,
        Window = 1,
        Door = 2,
        LockedDoor = 3,
        Connection = 4,
        Corpse = 5,
        Any = 6,
    };
};
var st = EdState{};

pub fn prevFab() void {
    st.x = 0;
    st.y = 0;
    st.fab_index -|= 1;
    st.fab = st.fab_variants.slice()[st.fab_index];
    st.fab_redraw = true;
}

pub fn nextFab() void {
    st.x = 0;
    st.y = 0;
    st.fab_index = @min(st.fab_variants.len - 1, st.fab_index + 1);
    st.fab = st.fab_variants.slice()[st.fab_index];
    st.fab_redraw = true;
}

// Removes unused features, and returns first blank feature index if any
pub fn removeUnusedFeatures() ?u8 {
    var used_markers = [1]bool{false} ** 128;

    var y: usize = 0;
    while (y < st.fab.height) : (y += 1) {
        var x: usize = 0;
        while (x < st.fab.width) : (x += 1) {
            if (st.fab.content[y][x] == .Feature) {
                used_markers[st.fab.content[y][x].Feature] = true;
            }
        }
    }

    var first: ?u8 = null;
    for (used_markers, 0..) |used_marker, i| if (!used_marker) {
        if (first == null)
            switch (i) {
                '0'...'9', 'a'...'z' => first = @intCast(i),
                else => {},
            };
        st.fab.features[i] = null;
    };

    return first;
}

pub fn erase() void {
    st.fab.content[st.y][st.x] = .Floor;
    st.fab_redraw = true;
    st.fab_info[st.fab_index].unsaved = true;
}

pub fn applyCursorPrisonArea() void {
    st.fab.prisons.slice()[st.cursor.PrisonArea].start.x = st.x;
    st.fab.prisons.slice()[st.cursor.PrisonArea].start.y = st.y;
    st.fab_redraw = true;
    st.fab_info[st.fab_index].unsaved = true;
}

pub fn applyCursorBasic() void {
    st.fab.content[st.y][st.x] = switch (st.cursor.Basic) {
        .Wall => .Wall,
        .Window => .Window,
        .Door => .Door,
        .LockedDoor => .LockedDoor,
        .Connection => .Connection,
        .Corpse => .Corpse,
        .Any => .Any,
    };
    st.fab_redraw = true;
    st.fab_info[st.fab_index].unsaved = true;
}

pub fn applyCursorMob() void {
    const blank = removeUnusedFeatures();

    const selected = &mobs.MOBS[st.cursor.Mob];
    const feature = for (st.fab.features, 0..) |maybe_feature, i| {
        if (maybe_feature) |feature|
            if (feature == .Mob and feature.Mob == selected)
                break @as(u8, @intCast(i));
    } else b: {
        if (blank == null) {
            std.log.err("Fab features are full", .{});
            return;
        }
        st.fab.features[blank.?] = mapgen.Prefab.Feature{ .Mob = selected };
        break :b blank.?;
    };

    st.fab.content[st.y][st.x] = .{ .Feature = feature };
    st.fab_redraw = true;
    st.fab_info[st.fab_index].unsaved = true;
}

pub fn applyCursorProp() void {
    const blank = removeUnusedFeatures();

    const selected = &surfaces.props.items[st.cursor.Prop];
    const feature: u8 = for (st.fab.features, 0..) |maybe_feature, i| {
        if (maybe_feature) |feature|
            if (feature == .Prop and mem.eql(u8, feature.Prop.id, selected.id))
                break @intCast(i);
    } else b: {
        if (blank == null) {
            std.log.err("Fab features are full", .{});
            return;
        }
        st.fab.features[blank.?] = mapgen.Prefab.Feature{ .Prop = selected };
        break :b blank.?;
    };

    st.fab.content[st.y][st.x] = .{ .Feature = feature };
    st.fab_redraw = true;
    st.fab_info[st.fab_index].unsaved = true;
}

fn _saveVariant(ind: usize, writer: anytype) void {
    const fab = st.fab_variants.data[ind];

    const oldpos = writer.context.getPos() catch err.wat();

    if (fab.tunneler_prefab) {
        for (fab.tunneler_orientation.constSlice()) |orien|
            writer.print(":tunneler_orientation {s}\n", .{orien.name()}) catch err.wat();
        if (fab.tunneler_inset)
            writer.print(":tunneler_inset\n", .{}) catch err.wat();
    }

    for (fab.prisons.constSlice()) |prect|
        writer.print(":prison {},{} {} {}\n", .{
            prect.start.x, prect.start.y, prect.height, prect.width,
        }) catch unreachable;

    if (writer.context.getPos() catch err.wat() != oldpos)
        writer.writeByte('\n') catch err.wat();

    const oldpos2 = writer.context.getPos() catch err.wat();
    for (fab.features, 0..) |maybe_feature, i| if (maybe_feature) |feature| {
        const chr: u21 = switch (feature) {
            .Item => 'i',
            .Mob => 'M',
            .Machine => 'm',
            .Prop => 'p',
            .CMob, .Poster => {
                std.log.warn("Assuming Cmons/P definition is prior to FABEDIT_REPLACE directive", .{});
                continue;
            },
            else => {
                std.log.err("Can only serialize i/M/m/p features. Aborting save.", .{});
                return;
            },
        };
        const str: []const u8 = switch (feature) {
            .Item => |item| item.i.id() catch unreachable,
            .Mob => |m| m.mob.id,
            .Machine => |m| m.mach.id,
            .Prop => |p| p.id,
            else => {
                std.log.err("Can only serialize i/M/m/p features. Aborting save.", .{});
                return;
            },
        };
        writer.print("@{u} {u} {s}\n", .{ @as(u8, @intCast(i)), chr, str }) catch err.wat();
    };

    if (writer.context.getPos() catch err.wat() != oldpos2)
        writer.writeByte('\n') catch err.wat();

    var y: usize = 0;
    while (y < fab.height) : (y += 1) {
        var x: usize = 0;
        while (x < fab.width) : (x += 1) {
            const chr: u21 = switch (fab.content[y][x]) {
                .Window => '&',
                .Wall => '#',
                .LockedDoor => '±',
                .HeavyLockedDoor => '⊞',
                .Door => '+',
                .Brazier => '•',
                .ShallowWater => '˜',
                .Floor => '.',
                .Connection => '*',
                .Water => '~',
                .Lava => '≈',
                .Bars => '≡',
                .Feature => |u| u,
                .Loot1 => 'L',
                .RareLoot => 'R',
                .LevelFeature => |i| 'α' + @as(u21, @intCast(i)),
                .Corpse => 'C',
                .Ring => '=',
                .Any => '?',
            };
            writer.print("{u}", .{chr}) catch err.wat();
        }
        writer.writeByte('\n') catch err.wat();
    }
}

pub fn saveFile() void {
    var fab_f = std.fs.cwd().openFile(st.fab_path, .{ .mode = .read_write }) catch |e| {
        std.log.err("Could not save file: {}", .{e});
        return;
    };
    defer fab_f.close();

    var buf = [1]u8{0} ** 4096;
    const read = fab_f.readAll(buf[0..]) catch err.wat();
    const writer = fab_f.writer();
    fab_f.seekTo(0) catch err.wat();
    fab_f.setEndPos(0) catch err.wat();

    var lines = mem.splitScalar(u8, buf[0..read], '\n');
    while (lines.next()) |line| {
        writer.writeAll(line) catch err.wat();
        writer.writeByte('\n') catch err.wat();
        if (mem.eql(u8, "% FABEDIT_REPLACE", line)) {
            writer.writeByte('\n') catch err.wat();
            break;
        }
    }

    for (st.fab_variants.constSlice(), 0..) |_, i| {
        _saveVariant(i, writer);
        if (i < st.fab_variants.len - 1)
            writer.print("\n\\\n", .{}) catch err.wat();
    }

    for (&st.fab_info) |*inf| inf.unsaved = false;
    std.log.info("Saved file.", .{});
}

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

    var args = std.process.args();
    _ = args.skip();
    st.fab_path = args.next() orelse {
        std.log.err("Usage: rl_fabedit [path]", .{});
        return;
    };

    const trimmed = mem.trimRight(u8, st.fab_path, ".fab");
    const index = if (mem.lastIndexOfScalar(u8, trimmed, '/')) |sep| sep + 1 else 0;
    st.fab_name = trimmed[index..];
    for (mapgen.n_fabs.items) |*fab|
        if (mem.eql(u8, fab.name.constSlice(), st.fab_name))
            st.fab_variants.append(fab) catch err.wat();
    for (mapgen.s_fabs.items) |*fab|
        if (mem.eql(u8, fab.name.constSlice(), st.fab_name))
            st.fab_variants.append(fab) catch err.wat();
    st.fab = st.fab_variants.last() orelse {
        std.log.err("Could not find {s}", .{st.fab_name});
        return;
    };
    st.fab_index = st.fab_variants.len - 1;

    try ui.init();
    ui.draw(&st);

    main: while (true) {
        ui.draw(&st);

        var evgen = display.getEvents(ui.FRAMERATE);
        while (evgen.next()) |ev| {
            switch (ev) {
                .Quit => break :main,
                .Resize => ui.draw(&st),
                .Wheel, .Hover, .Click => _ = ui.handleMouseEvent(ev, &st),
                .Key => |k| {
                    switch (k) {
                        .Backspace => erase(),
                        .Enter => switch (st.cursor) {
                            .Prop => applyCursorProp(),
                            .Basic => applyCursorBasic(),
                            .PrisonArea => applyCursorPrisonArea(),
                            .Mob => applyCursorMob(),
                        },
                        else => {},
                    }
                    ui.draw(&st);
                },
                .Char => |c| {
                    switch (c) {
                        's' => saveFile(),
                        'l' => st.x = @min(st.fab.width - 1, st.x + 1),
                        'j' => st.y = @min(st.fab.height - 1, st.y + 1),
                        'h' => st.x -|= 1,
                        'k' => st.y -|= 1,
                        'J' => st.cursor.incrBy(14),
                        'K' => st.cursor.decrBy(14),
                        'L' => st.cursor.incrBy(1),
                        'H' => st.cursor.decrBy(14),
                        '>' => {
                            st.hud_pane = switch (st.hud_pane) {
                                .Basic => .Props,
                                .Props => .Mobs,
                                .Mobs => .Areas,
                                .Areas => .Props,
                            };
                            st.fab_redraw = true;
                        },
                        '<' => {
                            st.hud_pane = switch (st.hud_pane) {
                                .Basic => .Areas,
                                .Props => .Basic,
                                .Mobs => .Props,
                                .Areas => .Mobs,
                            };
                            st.fab_redraw = true;
                        },
                        '[' => prevFab(),
                        ']' => nextFab(),
                        'r' => {
                            surfaces.freeProps(state.gpa.allocator());
                            surfaces.readProps(state.gpa.allocator());
                        },
                        else => {},
                    }
                    ui.draw(&st);
                },
            }
        }
    }

    try ui.deinit();
}
