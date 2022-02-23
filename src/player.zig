const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;

const StackBuffer = @import("buffer.zig").StackBuffer;

const rng = @import("rng.zig");
const literature = @import("literature.zig");
const explosions = @import("explosions.zig");
const tasks = @import("tasks.zig");
const items = @import("items.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const mapgen = @import("mapgen.zig");
const surfaces = @import("surfaces.zig");
const display = @import("display.zig");
const types = @import("types.zig");
const state = @import("state.zig");
const err = @import("err.zig");
usingnamespace @import("types.zig");

pub fn triggerStair(stair: Coord, whence: usize) void {
    const upstair = Coord.new2(whence, stair.x, stair.y);
    const dest = for (&DIRECTIONS) |d| {
        if (upstair.move(d, state.mapgeometry)) |neighbor| {
            if (state.is_walkable(neighbor, .{ .right_now = true }))
                break neighbor;
        }
    } else err.bug("Unable to find passable tile near upstairs!", .{});

    if (state.player.teleportTo(dest, null)) {
        state.message(.Move, "You ascend. Welcome to {}!", .{state.levelinfo[whence].name});
    } else {
        err.bug("Unable to ascend stairs! (something's in the way, maybe?)", .{});
    }
}

// Iterate through each tile in FOV:
// - Add them to memory.
// - If they haven't existed in memory before as an .Immediate tile, check for
//   things of interest (items, machines, etc) and announce their presence.
pub fn bookkeepingFOV() void {
    const SBuf = StackBuffer(u8, 64);
    const Announcement = struct { count: usize, name: SBuf };
    const AList = std.ArrayList(Announcement);

    var announcements = AList.init(&state.GPA.allocator);
    defer announcements.deinit();

    const S = struct {
        // Add to announcements if it doesn't exist, otherwise increment counter
        pub fn _addToAnnouncements(name: SBuf, buf: *AList) void {
            for (buf.items) |*announcement| {
                if (mem.eql(u8, announcement.name.constSlice(), name.constSlice())) {
                    announcement.count += 1;
                    return;
                }
            }
            // Add, since we didn't encounter it before
            buf.append(.{ .count = 1, .name = name }) catch err.wat();
        }
    };

    for (state.player.fov) |row, y| for (row) |_, x| {
        if (state.player.fov[y][x] > 0) {
            const fc = Coord.new2(state.player.coord.z, x, y);

            var was_already_seen: bool = false;
            if (state.memory.get(fc)) |memtile|
                if (memtile.type == .Immediate) {
                    was_already_seen = true;
                };

            if (!was_already_seen) {
                if (state.dungeon.at(fc).surface) |surf| switch (surf) {
                    .Machine => |m| if (m.announce)
                        S._addToAnnouncements(SBuf.init(m.name), &announcements),
                    .Stair => |s| if (s != null)
                        S._addToAnnouncements(SBuf.init("upward stairs"), &announcements),
                    else => {},
                };
                if (state.dungeon.itemsAt(fc).last()) |item|
                    if (item.announce()) {
                        const n = item.shortName() catch err.wat();
                        S._addToAnnouncements(n, &announcements);
                    };
            }

            const t = Tile.displayAs(fc, true);
            const memt = state.MemoryTile{ .bg = t.bg, .fg = t.fg, .ch = t.ch };
            state.memory.put(fc, memt) catch err.wat();
        }
    };

    if (announcements.items.len > 7) {
        state.message(.Info, "Found {} objects.", .{announcements.items.len});
    } else {
        for (announcements.items) |ann| {
            const n = ann.name.constSlice();
            if (ann.count == 1) {
                state.message(.Info, "Found a {}.", .{n});
            } else {
                state.message(.Info, "Found {} {}.", .{ ann.count, n });
            }
        }
    }
}

pub fn moveOrFight(direction: Direction) bool {
    const current = state.player.coord;

    if (direction.is_diagonal() and state.player.isUnderStatus(.Confusion) != null) {
        state.message(.MetaError, "You cannot move diagonally whilst confused!", .{});
        return false;
    }

    if (current.move(direction, state.mapgeometry)) |dest| {
        if (state.dungeon.at(dest).mob) |mob| {
            if (state.player.isHostileTo(mob) and !state.player.canSwapWith(mob, direction)) {
                state.player.fight(mob);
                return true;
            }
        }

        if (state.dungeon.at(dest).surface) |surf| switch (surf) {
            .Machine => |m| if (m.evoke_confirm) |msg| {
                const r = state.messageKeyPrompt("{} [y/N]", .{msg}, 'n', "YyNn ", "yynnn");
                if (r == null or r.? == 'n') {
                    if (r != null)
                        state.message(.Prompt, "Okay then.", .{});
                    return false;
                }
            },
            else => {},
        };

        return state.player.moveInDirection(direction);
    } else {
        return false;
    }
}

pub fn invokeRecharger() bool {
    var recharger: ?*Machine = null;

    for (state.player.fov) |row, y| for (row) |_, x| {
        if (state.player.fov[y][x] > 0) {
            const fc = Coord.new2(state.player.coord.z, x, y);
            if (state.dungeon.at(fc).surface) |surf| switch (surf) {
                .Machine => |m| if (mem.eql(u8, m.id, "recharging_station")) {
                    recharger = m;
                },
                else => {},
            };
        }
    };

    if (recharger) |mach| {
        mach.evoke(state.player, &mach.interact1.?) catch |e| {
            switch (e) {
                error.NotPowered => state.message(.MetaError, "The station has no power!", .{}),
                error.UsedMax => state.message(.MetaError, "The station is out of charges!", .{}),
                error.NoEffect => state.message(.MetaError, "No evocables to recharge!", .{}),
            }
            return false;
        };

        state.player.declareAction(.Interact);
        state.message(.Info, "All evocables recharged.", .{});
        state.message(.Info, "You can use this station {} more times.", .{
            mach.interact1.?.max_use - mach.interact1.?.used,
        });
        return true;
    } else {
        state.message(.MetaError, "No recharging station in sight!", .{});
        return false;
    }
}

pub fn grabItem() bool {
    if (state.player.inventory.pack.isFull()) {
        state.message(.MetaError, "Your pack is full.", .{});
        return false;
    }

    var item: Item = undefined;

    if (state.dungeon.at(state.player.coord).surface) |surface| {
        switch (surface) {
            .Container => |container| {
                if (container.items.len == 0) {
                    state.message(.MetaError, "There's nothing in the {}.", .{container.name});
                    return false;
                } else {
                    const index = display.chooseInventoryItem(
                        "Take",
                        container.items.constSlice(),
                    ) orelse return false;
                    item = container.items.orderedRemove(index) catch err.wat();
                }
            },
            else => {},
        }
    }

    if (state.dungeon.itemsAt(state.player.coord).last()) |_| {
        item = state.dungeon.itemsAt(state.player.coord).pop() catch err.wat();
    } else {
        state.message(.MetaError, "There's nothing here.", .{});
        return false;
    }

    switch (item) {
        .Weapon => |weapon| {
            if (state.player.inventory.wielded) |old_w| {
                state.dungeon.itemsAt(state.player.coord).append(Item{ .Weapon = old_w }) catch err.wat();
                state.player.declareAction(.Drop);
                state.message(.Info, "You drop the {} to wield the {}.", .{ old_w.name, weapon.name });
            }

            state.player.inventory.wielded = weapon;
            state.player.declareAction(.Use);
            state.message(.Info, "Now wielding a {}.", .{weapon.name});
        },
        .Armor => |armor| {
            if (state.player.inventory.armor) |a| {
                state.dungeon.itemsAt(state.player.coord).append(Item{ .Armor = a }) catch err.wat();
                state.player.declareAction(.Drop);
                state.message(.Info, "You drop the {} to wear the {}.", .{ a.name, armor.name });
            }

            state.player.inventory.armor = armor;
            state.player.declareAction(.Use);
            state.message(.Info, "Now wearing a {}.", .{armor.name});
            if (armor.speed_penalty != null or armor.dex_penalty != null)
                state.message(.Info, "This armor is going to be annoying to wear.", .{});
        },
        .Cloak => |cloak| {
            if (state.player.inventory.cloak) |c| {
                state.dungeon.itemsAt(state.player.coord).append(Item{ .Cloak = c }) catch err.wat();
                state.player.declareAction(.Drop);
                state.message(.Info, "You drop the {} to wear the {}.", .{ c.name, cloak.name });
            }

            state.player.inventory.cloak = cloak;
            state.player.declareAction(.Use);
            state.message(.Info, "Now wearing a cloak of {}.", .{cloak.name});
        },
        else => {
            state.player.inventory.pack.append(item) catch err.wat();
            state.player.declareAction(.Grab);
            state.message(.Info, "Acquired: {}", .{
                (state.player.inventory.pack.last().?.longName() catch err.wat()).constSlice(),
            });
        },
    }
    return true;
}

pub fn throwItem() bool {
    if (state.player.inventory.pack.len == 0) {
        state.message(.MetaError, "Your pack is empty.", .{});
        return false;
    }

    const index = display.chooseInventoryItem(
        "Throw",
        state.player.inventory.pack.constSlice(),
    ) orelse return false;
    const dest = display.chooseCell() orelse return false;
    const item = &state.player.inventory.pack.slice()[index];

    if (state.player.throwItem(item, dest, &state.GPA.allocator)) {
        _ = state.player.removeItem(index) catch err.wat();
        return true;
    } else {
        state.message(.MetaError, "You can't throw that.", .{});
        return false;
    }
}

pub fn useItem() bool {
    if (state.player.inventory.pack.len == 0) {
        state.message(.MetaError, "Your pack is empty.", .{});
        return false;
    }

    const index = display.chooseInventoryItem(
        "Use",
        state.player.inventory.pack.constSlice(),
    ) orelse return false;

    switch (state.player.inventory.pack.slice()[index]) {
        .Corpse => |_| {
            state.message(.MetaError, "That doesn't look appetizing.", .{});
            return false;
        },
        .Ring => |_| {
            // So this message was in response to player going "I want to eat it"
            // But of course they might have just been intending to "invoke" the
            // ring, not knowing that there's no such thing.
            //
            // FIXME: so this message can definitely be improved...
            state.message(.MetaError, "Are you three?", .{});
            return false;
        },
        .Armor, .Cloak, .Weapon => err.wat(),
        .Potion => |p| {
            state.player.quaffPotion(p, true);
            const prevtotal = (state.chardata.potions_quaffed.getOrPutValue(p.id, 0) catch err.wat()).value;
            state.chardata.potions_quaffed.put(p.id, prevtotal + 1) catch err.wat();
        },
        .Vial => |v| err.todo(),
        .Projectile, .Boulder => {
            state.message(.MetaError, "You want to *eat* that?", .{});
            return false;
        },
        .Prop => |p| {
            state.message(.Info, "You admire the {}.", .{p.name});
            return false;
        },
        .Evocable => |v| {
            v.evoke(state.player) catch |e| {
                if (e == error.NoCharges) {
                    state.message(.MetaError, "You can't use the {} anymore!", .{v.name});
                }
                return false;
            };

            const prevtotal = (state.chardata.evocs_used.getOrPutValue(v.id, 0) catch err.wat()).value;
            state.chardata.evocs_used.put(v.id, prevtotal + 1) catch err.wat();
        },
    }

    switch (state.player.inventory.pack.slice()[index]) {
        .Evocable => |e| if (e.delete_when_inert and e.charges == 0) {
            _ = state.player.removeItem(index) catch err.wat();
        },
        else => _ = state.player.removeItem(index) catch err.wat(),
    }

    state.player.declareAction(.Use);

    return true;
}

pub fn dropItem() bool {
    if (state.player.inventory.pack.len == 0) {
        state.message(.MetaError, "Your pack is empty.", .{});
        return false;
    }

    if (state.nextAvailableSpaceForItem(state.player.coord, &state.GPA.allocator)) |coord| {
        const index = display.chooseInventoryItem(
            "Drop",
            state.player.inventory.pack.constSlice(),
        ) orelse return false;
        const item = state.player.removeItem(index) catch err.wat();

        const dropped = state.player.dropItem(item, coord);
        assert(dropped);

        state.message(.Info, "Dropped: {}.", .{
            (item.shortName() catch err.wat()).constSlice(),
        });
        return true;
    } else {
        state.message(.MetaError, "There's no nearby space to drop items.", .{});
        return false;
    }
}