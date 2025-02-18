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
    BuildMob: struct { mob: *const mobs.MobTemplate, coord: Coord, opts: mobs.PlaceMobOptions },
};

pub const Task = struct {
    type: TaskType,
    level: usize,
    assigned_to: ?*Mob = null,
    completed: bool = false,
};

pub fn reportTask(level: usize, newtask: TaskType) void {
    var reuse_task_slot: ?usize = null;

    // Check if task has already been reported
    for (state.tasks.items) |task, id| {
        if (@as(meta.Tag(TaskType), task.type) == newtask) {
            const is_same = task.level == level and switch (task.type) {
                .Clean => |c| c.eq(newtask.Clean),
                .Haul => |h| h.from.eq(newtask.Haul.from) and h.to.eq(newtask.Haul.to),
                .ExamineCorpse => |m| m == newtask.ExamineCorpse,
                .BuildMob => |b| mem.eql(u8, b.mob.mob.id, newtask.BuildMob.mob.mob.id) and
                    b.coord.eq(newtask.BuildMob.coord),
            };

            if (is_same and !task.completed) {
                // Already reported.
                return;
            }

            if (task.completed) {
                reuse_task_slot = id;
            }
        }
    }

    if (reuse_task_slot) |slot| {
        state.tasks.items[slot] = .{ .type = newtask, .level = level };
    } else {
        state.tasks.append(.{ .type = newtask, .level = level }) catch err.wat();
    }
}

pub fn getJobTypesForWorker(mob: *Mob) struct { tasktype: meta.Tag(TaskType), aijobtype: AIJob.Type } {
    if (mem.eql(u8, mob.id, "cleaner")) {
        return .{ .tasktype = .Clean, .aijobtype = .WRK_Clean };
    } else if (mem.eql(u8, mob.id, "hauler")) {
        err.todo(); // WRK_Haul isn't implemented yet
        // return .{ .tasktype = .Haul, .aijobtype = .WRK_Haul };
    } else if (mem.eql(u8, mob.id, "coroner")) {
        return .{ .tasktype = .ExamineCorpse, .aijobtype = .WRK_ExamineCorpse };
    } else if (mem.eql(u8, mob.id, "engineer")) {
        return .{ .tasktype = .BuildMob, .aijobtype = .WRK_BuildMob };
    } else unreachable;
}

// Scan for tasks
pub fn tickTasks(level: usize) void {
    if (!state.levelinfo[level].ecosystem)
        return;

    // Clear out tasks assigned to dead mobs and tasks on other levels
    for (state.tasks.items) |*task| {
        if (task.completed) continue;

        if (task.level != level) {
            task.completed = true;
        }

        if (task.assigned_to) |assigned_to| {
            if (assigned_to.is_dead and assigned_to.corpse_info.is_noticed) {
                switch (task.type) {
                    .Haul => task.completed = true,
                    else => task.assigned_to = null,
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
                    Task{ .level = level, .type = TaskType{ .Haul = .{ .from = itemcoord.?, .to = dest } } },
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
                    Task{ .level = level, .type = TaskType{ .Haul = .{ .from = take_from, .to = empty_slot } } },
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
                .BuildMob => &mobs.EngineerTemplate,
            };

            if (mobs.placeMobNearStairs(mob_template, level, .{})) |worker| {
                worker.ai.task_id = id;
                task.assigned_to = worker;
            } else |_| {
                // No space near stairs. Do nothing, wait until next time, hopefully
                // the traffic dissipates.
            }

            break;
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
                    !corpse.killed_by.?.is_dead and
                    (state.ticks - corpse.last_damage.?.inflicted_time) <= 2 and
                    corpse.killed_by.?.distance2(corpse.coord) <= 3 and
                    corpse.killed_by.?.isHostileTo(mob))
                {
                    ai.updateEnemyKnowledge(mob, corpse.killed_by.?, coord);
                }

                mob.newJob(.WRK_ScanCorpse);
                mob.newestJob().?.ctx.set(Coord, AIJob.CTX_CORPSE_LOCATION, corpse.coord);
            }
            corpse.corpse_info.is_noticed = true;
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
                reportTask(coord.z, .{ .Clean = coord });
            }
        }
    };
}
