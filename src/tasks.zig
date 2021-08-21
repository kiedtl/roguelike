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
