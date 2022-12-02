const std = @import("std");
const math = std.math;

const colors = @import("../colors.zig");
const state = @import("../state.zig");
const types = @import("../types.zig");
const ui = @import("../ui.zig");

const Mob = types.Mob;
const Coord = types.Coord;
const Rect = types.Rect;

pub const MapLabel = struct {
    text: []const u8,
    loc: union(enum) {
        Coord: Coord,
        Mob: *Mob,
    },
    color: u32,
    max_age: usize = 1000 / ui.FRAMERATE * 4, // ~5 seconds
    max_tick_age: usize,
    malloced: bool,

    created_on: usize = 0,
    win_lines: u21 = 0,
    win_loc: ?Rect = null,
    win_side: usize = 0,
    age: usize = 0,

    pub fn getLoc(self: @This()) Coord {
        return switch (self.loc) {
            .Coord => |c| c,
            .Mob => |m| m.coord,
        };
    }

    pub fn deinit(self: @This()) void {
        if (self.malloced)
            state.GPA.allocator().free(self.text);
    }
};
pub var labels: std.ArrayList(MapLabel) = undefined;
pub var last_player_position: Coord = Coord.new(0, 0);

pub const LabelOpts = struct {
    color: u32 = 0x888888,
    last_for: usize = 2,
};

pub fn addFor(mob: *Mob, text: []const u8, opts: LabelOpts) void {
    add(.{ .Mob = mob }, text, opts, false);
}

pub fn addForf(mob: *Mob, comptime fmt: []const u8, args: anytype, opts: LabelOpts) void {
    add(.{ .Mob = mob }, std.fmt.allocPrint(state.GPA.allocator(), fmt, args) catch unreachable, opts, true);
}

pub fn addAt(coord: Coord, text: []const u8, opts: LabelOpts) void {
    add(.{ .Coord = coord }, text, opts, false);
}

pub fn addAtf(coord: Coord, comptime fmt: []const u8, args: anytype, opts: LabelOpts) void {
    add(.{ .Coord = coord }, std.fmt.allocPrint(state.GPA.allocator(), fmt, args) catch unreachable, opts, true);
}

fn add(loc: std.meta.fieldInfo(MapLabel, .loc).field_type, text: []const u8, opts: LabelOpts, malloced: bool) void {
    labels.append(.{
        .text = text,
        .loc = loc,
        .max_tick_age = opts.last_for,
        .color = opts.color,
        .created_on = state.player_turns,
        .malloced = malloced,
    }) catch unreachable;
}

pub fn _setLabelWindowLocation(label: *MapLabel) !void {
    const w_loc = ui.coordToScreen(label.getLoc()) orelse return error.NoValidRect;
    const t_len = label.text.len;
    const possibles = [_]struct { z: usize, s: u21, r: Rect }{
        .{ .z = 0, .s = '┐', .r = Rect.new(Coord.new(w_loc.x -| (t_len + 3), w_loc.y -| 1), t_len + 5, 1) },
        .{ .z = 1, .s = '┌', .r = Rect.new(Coord.new(w_loc.x, w_loc.y -| 1), t_len + 3, 1) },
        .{ .z = 0, .s = '─', .r = Rect.new(Coord.new(w_loc.x -| (t_len + 5), w_loc.y), t_len + 5, 1) },
        .{ .z = 1, .s = '─', .r = Rect.new(Coord.new(w_loc.x + 2, w_loc.y), t_len + 5, 1) },
        .{ .z = 0, .s = '┘', .r = Rect.new(Coord.new(w_loc.x -| (t_len + 3), w_loc.y + 1), t_len + 5, 1) },
        .{ .z = 1, .s = '└', .r = Rect.new(Coord.new(w_loc.x, w_loc.y -| 1), 1, t_len + 5) },
    };
    const chosen = for (possibles) |possible| {
        if (possible.r.end().x > ui.map_win.annotations.width or
            possible.r.start.x == 0 or
            possible.r.end().y > ui.map_win.annotations.height or
            possible.r.start.y == 0)
        {
            continue;
        }
        if (for (labels.items) |other_label| {
            if (other_label.win_loc != null and other_label.win_loc.?.intersects(&possible.r, 0))
                break true;
        } else false) {
            continue;
        }
        break possible;
    } else return error.NoValidRect;
    label.win_lines = chosen.s;
    label.win_loc = chosen.r;
    label.win_side = chosen.z;
}

pub fn drawLabels() void {
    defer last_player_position = state.player.coord;

    ui.map_win.annotations.clear();

    var new_labels = @TypeOf(labels).init(state.GPA.allocator());
    while (labels.popOrNull()) |label|
        if (label.age < label.max_age and ui.coordToScreen(label.getLoc()) != null) {
            new_labels.append(label) catch unreachable;
            const last = &new_labels.items[new_labels.items.len - 1];

            // Set age to near max if label is too old, to begin slidein
            // animation
            if (state.player_turns >= label.created_on + label.max_tick_age and
                label.age < (label.max_age - (label.text.len / 2)))
            {
                last.max_age = label.age + (label.text.len / 2) + 1;
            }

            // If player has moved, then all labels are off-center (since camera
            // has moved).
            if (!state.player.coord.eq(last_player_position)) {
                last.win_loc = null;
            }
        } else label.deinit();
    labels.deinit();
    labels = new_labels;

    for (labels.items) |*label| {
        if (label.win_loc == null) {
            _setLabelWindowLocation(label) catch continue;
        }

        label.age += 1;

        const text = if (label.age < label.text.len / 2)
            label.text[0 .. label.age * 2]
        else if (label.age > (label.max_age - (label.text.len / 2)))
            label.text[0 .. (label.max_age - label.age) * 2]
        else
            label.text;
        const l_startx = label.win_loc.?.start.x;
        const l_starty = label.win_loc.?.start.y;
        const color_01 = colors.percentageOf(label.color, 40);
        const color_02 = label.color;
        const color_03 = colors.percentageOf(label.color, 200);

        if (label.win_side == 0) {
            const actual_startx = l_startx + (label.text.len - text.len);
            _ = ui.map_win.annotations.drawTextAtf(actual_startx, l_starty, " {s} ", .{text}, .{ .fg = color_03, .bg = color_01 });
            _ = ui.map_win.annotations.drawTextAt(actual_startx + text.len + 2, l_starty, "█", .{ .fg = color_02 });
            ui.map_win.annotations.setCell(actual_startx + text.len + 3, l_starty, .{ .ch = label.win_lines, .fg = color_02, .fl = .{ .wide = true } });
        } else if (label.win_side == 1) {
            ui.map_win.annotations.setCell(l_startx, l_starty, .{ .ch = label.win_lines, .fg = color_02, .fl = .{ .wide = true } });
            _ = ui.map_win.annotations.drawTextAt(l_startx + 2, l_starty, "█", .{ .fg = color_02 });
            _ = ui.map_win.annotations.drawTextAtf(l_startx + 3, l_starty, " {s} ", .{text}, .{ .fg = color_03, .bg = color_01 });
        }
    }
}
