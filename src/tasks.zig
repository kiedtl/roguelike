const std = @import("std");

const state = @import("state.zig");
const types = @import("types.zig");

const Coord = types.Coord;
const Direction = types.Direction;
const Tile = types.Tile;
const Item = types.Item;
const Ring = types.Ring;
const Weapon = types.Weapon;
const StatusDataInfo = types.StatusDataInfo;
const Armor = types.Armor;
const SurfaceItem = types.SurfaceItem;
const Mob = types.Mob;
const Status = types.Status;
const Machine = types.Machine;
const PropArrayList = types.PropArrayList;
const Container = types.Container;
const Material = types.Material;
const Prop = types.Prop;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub const TaskArrayList = std.ArrayList(Task);

pub const TaskType = union(enum) {
    Clean: Coord,
    Haul: struct { from: Coord, to: Coord },
    Repair: Coord,
};

pub const Task = struct {
    type: TaskType,
    assigned_to: ?*Mob = null,
    completed: bool = false,
};

// Scan for tasks
pub fn tickTasks(level: usize) void {
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(level, x, y);

                // Check for broken tiles
                if (state.dungeon.at(coord).broken and state.dungeon.fireAt(coord).* == 0) {
                    var already_reported: ?usize = null;

                    for (state.tasks.items) |task, id| switch (task.type) {
                        .Repair => |r| if (r.eq(coord)) {
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
                        state.tasks.append(Task{ .type = TaskType{ .Repair = coord } }) catch unreachable;
                    }
                }

                // Check for tile cleanliness
                if (!state.dungeon.at(coord).prison) { // Let the prisoners wallow in filth
                    var clean = true;

                    var spattering = state.dungeon.at(coord).spatter.iterator();
                    while (spattering.next()) |entry| {
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
        var item: ?*const Item = null;
        var itemcoord: ?Coord = null;

        // Search for a stray item
        {
            var y: usize = output_area.start.y;
            outer: while (y < output_area.end().y) : (y += 1) {
                var x: usize = output_area.start.x;
                while (x < output_area.end().x) : (x += 1) {
                    const coord = Coord.new2(level, x, y);

                    const t_items = state.dungeon.itemsAt(coord);
                    const c_items: ?*Container.ItemBuffer =
                        if (state.dungeon.hasContainer(coord)) |c| &c.items else null;

                    if ((c_items != null and c_items.?.len > 0) or
                        (c_items == null and t_items.len > 0))
                    {
                        var already_reported = false;

                        for (state.tasks.items) |task| switch (task.type) {
                            .Haul => |h| if (h.from.eq(coord) and !task.completed) {
                                already_reported = true;
                                break;
                            },
                            else => {},
                        };

                        if (!already_reported) {
                            item = if (c_items) |ci| &ci.data[0] else &t_items.data[0];
                            itemcoord = coord;
                            break :outer;
                        }
                    }
                }
            }
        }

        if (item) |_item| {
            var stockpile: ?Coord = null;

            // Now search for a stockpile
            for (state.stockpiles[level].items) |c_stockpile|
                if (c_stockpile.isItemOfSameType(_item)) {
                    if (c_stockpile.findEmptySlot()) |coord| {
                        stockpile = coord;
                        break;
                    }
                };

            if (stockpile) |dest| {
                state.tasks.append(
                    Task{ .type = TaskType{ .Haul = .{ .from = itemcoord.?, .to = dest } } },
                ) catch unreachable;
            }
        }
    }

    // Check for empty input areas that need to be filled
    for (state.inputs[level].items) |input_area| {
        var empty_slot_: ?Coord = null;
        var y: usize = input_area.room.start.y;
        outer: while (y < input_area.room.end().y) : (y += 1) {
            var x: usize = input_area.room.start.x;
            while (x < input_area.room.end().x) : (x += 1) {
                const coord = Coord.new2(level, x, y);

                const t_items = state.dungeon.itemsAt(coord);
                const c_items: ?*Container.ItemBuffer =
                    if (state.dungeon.hasContainer(coord)) |c| &c.items else null;

                if ((c_items != null and !c_items.?.isFull()) or
                    (c_items == null and !t_items.isFull()))
                {
                    var already_reported = false;

                    for (state.tasks.items) |task| switch (task.type) {
                        .Haul => |h| if (h.to.eq(coord) and !task.completed) {
                            already_reported = true;
                            break;
                        },
                        else => {},
                    };

                    if (!already_reported) {
                        empty_slot_ = coord;
                        break :outer;
                    }
                }
            }
        }

        if (empty_slot_) |empty_slot| {
            var take_from_: ?Coord = null;

            // Search stockpiles
            for (state.stockpiles[level].items) |stockpile|
                if (stockpile.isStockpileOfSameType(&input_area)) {
                    if (stockpile.findItem()) |coord| {
                        take_from_ = coord;
                        break;
                    }
                };

            if (take_from_) |take_from| {
                state.tasks.append(
                    Task{ .type = TaskType{ .Haul = .{ .from = take_from, .to = empty_slot } } },
                ) catch unreachable;
            }
        }
    }
}
