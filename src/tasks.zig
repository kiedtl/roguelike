const std = @import("std");
const mem = std.mem;
const enums = std.enums;
const meta = std.meta;

const ai = @import("ai.zig");
const err = @import("err.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const types = @import("types.zig");

const AIJob = types.AIJob;
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
    ExamineCorpse: *Mob,
};

pub const Task = struct {
    type: TaskType,
    assigned_to: ?*Mob = null,
    completed: bool = false,
};

pub fn getJobTypesForWorker(mob: *Mob) struct { tasktype: meta.Tag(TaskType), aijobtype: AIJob.Type } {
    if (mem.eql(u8, mob.id, "cleaner")) {
        return .{ .tasktype = .Clean, .aijobtype = .WRK_Clean };
    } else if (mem.eql(u8, mob.id, "hauler")) {
        err.todo(); // WRK_Haul isn't implemented yet
        // return .{ .tasktype = .Haul, .aijobtype = .WRK_Haul };
    } else if (mem.eql(u8, mob.id, "coroner")) {
        return .{ .tasktype = .ExamineCorpse, .aijobtype = .WRK_ExamineCorpse };
    } else unreachable;
}

// Scan for tasks
pub fn tickTasks(level: usize) void {
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

    // Check if we need to dispatch workers. (Only one is dispatched each time,
    // to prevent 10 workers from suddenly teleporting into the floor in a
    // single turn, which is unrealistic.)
    //
    // First, get a count of all workers, sorted by type, on the floor
    var worker_count = enums.EnumArray(meta.Tag(TaskType), usize).initFill(0);
    for (state.tasks.items) |task|
        if (task.assigned_to != null and !task.completed)
            worker_count.set(task.type, worker_count.get(task.type) + 1);

    // Now go through orders again and dispatch workers if necessary.
    for (state.tasks.items) |*task, id|
        if (task.assigned_to == null and !task.completed and
            worker_count.get(task.type) <= 2)
        {
            const mob_template = switch (task.type) {
                .Clean => &mobs.CleanerTemplate,
                .Haul => &mobs.HaulerTemplate,
                .ExamineCorpse => &mobs.CoronerTemplate,
            };
            const coord = for (state.dungeon.stairs[level].constSlice()) |stair| {
                if (state.nextSpotForMob(stair, null)) |coord| {
                    break coord;
                }
            } else null;
            if (coord) |spawn_coord| {
                const worker = mobs.placeMob(state.GPA.allocator(), mob_template, spawn_coord, .{});
                worker.ai.task_id = id;
                task.assigned_to = worker;
                break;
            }
        };
}

pub fn scanForCorpses(mob: *Mob) void {
    if (mob.faction != .Necromancer) return;

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;
        const coord = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(coord).surface) |surface| if (surface == .Corpse) {
            const corpse = surface.Corpse;
            if (corpse.faction == .Necromancer and !corpse.corpse_info.is_noticed) {
                if (corpse.killed_by != null and
                    (state.ticks - corpse.last_damage.?.inflicted_time) < 2 and
                    corpse.killed_by.?.distance2(corpse.coord) < 4 and
                    corpse.killed_by.?.isHostileTo(mob))
                {
                    ai.updateEnemyKnowledge(mob, corpse.killed_by.?, coord);
                }

                mob.newJob(.WRK_ScanCorpse);
                mob.newestJob().?.setCtx(Coord, AIJob.CTX_CORPSE_LOCATION, corpse.coord);
                corpse.corpse_info.is_noticed = true;
            }
        };
    };
}

pub fn scanForCleaningJobs(mob: *Mob) void {
    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;
        const coord = Coord.new2(mob.coord.z, x, y);

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
    };
}
