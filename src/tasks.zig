const std = @import("std");

const state = @import("state.zig");
usingnamespace @import("types.zig");

pub const TaskArrayList = std.ArrayList(Task);

pub const TaskType = union(enum) {
    Clean: Coord,
    Haul: struct { from: Coord, to: Coord },
};

pub const Task = struct {
    type: TaskType,
    assigned_to: ?*Mob = null,
    completed: bool = false,
};

// Scan for tasks
pub fn tickTasks(level: usize) void {
    const s = @ptrCast(*volatile TaskArrayList, &state.tasks);
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(level, x, y);

                // Check for tile cleanliness
                if (!state.dungeon.at(coord).prison) { // Let the prisoners wallow in filth
                    var clean = true;

                    var spattering = state.dungeon.at(coord).spatter.iterator();
                    while (spattering.next()) |entry| {
                        const num = entry.value.*;
                        if (entry.value.* > 0) {
                            clean = false;
                            break;
                        }
                    }

                    if (!clean) {
                        var already_reported: ?usize = null;

                        for (state.tasks.items) |task, id| switch (task.type) {
                            .Clean => |c| if (c.eq(coord)) {
                                already_reported = id;
                                break;
                            },
                            else => {},
                        };

                        if (already_reported) |id| {
                            if (state.tasks.items[id].completed) {
                                state.tasks.items[id].completed = false;
                                state.tasks.items[id].assigned_to = null;
                            }
                        } else {
                            state.tasks.append(Task{ .type = TaskType{ .Clean = coord } }) catch unreachable;
                        }
                    }
                }
            }
        }
    }

    // Check for items in outputs that need to be hauled to stockpiles
    for (state.outputs[level].items) |output_area| {
        var itemttype: ?ItemType = null;
        var itemcoord: ?Coord = null;

        // Search for a stray item
        {
            var y: usize = output_area.start.y;
            outer: while (y < output_area.end().y) : (y += 1) {
                var x: usize = output_area.start.x;
                while (x < output_area.end().x) : (x += 1) {
                    const coord = Coord.new2(level, x, y);
                    const t_items = state.dungeon.itemsAt(coord);
                    if (t_items.len > 0) {
                        var already_reported = false;

                        for (state.tasks.items) |task, id| switch (task.type) {
                            .Haul => |h| if (h.from.eq(coord) and !task.completed) {
                                already_reported = true;
                                break;
                            },
                            else => {},
                        };

                        if (!already_reported) {
                            itemttype = std.meta.activeTag(t_items.data[0]);
                            itemcoord = coord;
                            break :outer;
                        }
                    }
                }
            }
        }

        if (itemttype) |_type| {
            var stockpile: ?Coord = null;

            // Now search for a stockpile
            stckpl_search: for (state.stockpiles[level].items) |item| if (item.type == _type) {
                var y: usize = item.room.start.y;
                while (y < item.room.end().y) : (y += 1) {
                    var x: usize = item.room.start.x;
                    while (x < item.room.end().x) : (x += 1) {
                        const coord = Coord.new2(level, x, y);
                        if (!state.dungeon.itemsAt(coord).isFull()) {
                            stockpile = coord;
                            break :stckpl_search;
                        }
                    }
                }
            };

            if (stockpile) |dest| {
                state.tasks.append(
                    Task{ .type = TaskType{ .Haul = .{ .from = itemcoord.?, .to = dest } } },
                ) catch unreachable;
            }
        }
    }
}
