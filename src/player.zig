const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;

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
const state = @import("state.zig");
const types = @import("types.zig");
const err = @import("err.zig");

const Coord = types.Coord;
const Tile = types.Tile;
const Item = types.Item;
const Ring = types.Ring;
const Weapon = types.Weapon;
const Resistance = types.Resistance;
const StatusDataInfo = types.StatusDataInfo;
const Armor = types.Armor;
const SurfaceItem = types.SurfaceItem;
const Mob = types.Mob;
const Status = types.Status;
const Machine = types.Machine;
const Direction = types.Direction;

const DIRECTIONS = types.DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub var auto_wait_enabled: bool = true;

pub const PlayerUpgradeInfo = struct {
    recieved: bool = false,
    upgrade: PlayerUpgrade,
};

pub const PlayerUpgrade = enum {
    Fast,
    Strong,
    Agile,
    OI_Enraged,
    OI_Fast,
    OI_Shove,
    Healthy,
    Mana,
    Camoflaged,
    Will,
    Echolocating,

    pub const UPGRADES = [_]PlayerUpgrade{ .Fast, .Strong, .Agile, .OI_Enraged, .OI_Fast, .OI_Shove, .Healthy, .Mana, .Camoflaged, .Will, .Echolocating };

    pub fn announce(self: PlayerUpgrade) []const u8 {
        return switch (self) {
            .Fast => "You feel yourself moving faster.",
            .Strong => "You feel mighty!",
            .Agile => "You are good at evading blows.",
            .OI_Enraged => "You feel hatred building up inside.",
            .OI_Fast => "You put on a burst of speed when injured.",
            .OI_Shove => "You begin shoving past foes when injured.",
            .Healthy => "You are unusually robust.",
            .Mana => "You sense your inner strength grow.",
            .Camoflaged => "Only observant foes notice you.",
            .Will => "Your will hardens.",
            .Echolocating => "Your sense of hearing becomes acute.",
        };
    }

    pub fn description(self: PlayerUpgrade) []const u8 {
        return switch (self) {
            .Fast => "You have a 10% speed bonus.",
            .Strong => "You have a +50% strength bonus.",
            .Agile => "You have a +20% dodging bonus.",
            .OI_Enraged => "You become enraged when badly hurt.",
            .OI_Fast => "You put on a burst of speed when injured.",
            .OI_Shove => "You begin shoving past foes when injured.",
            .Healthy => "You have 50% more health than usual.",
            .Mana => "You have 50% more mana than usual.",
            .Camoflaged => "You have one level of intrinsic camoflage.",
            .Will => "You have 3 extra pips of willpower.",
            .Echolocating => "You passively echolocate areas around sound.",
        };
    }

    pub fn implement(self: PlayerUpgrade) void {
        switch (self) {
            .Fast => state.player.stats.Speed -= 10,
            .Strong => state.player.stats.Strength += 15,
            .Agile => state.player.stats.Evade += 10,
            .OI_Enraged => state.player.ai.flee_effect = .{
                .status = .Enraged,
                .duration = .{ .Tmp = 10 },
                .exhausting = true,
            },
            .OI_Fast => state.player.ai.flee_effect = .{
                .status = .Fast,
                .duration = .{ .Tmp = 10 },
                .exhausting = true,
            },
            .OI_Shove => state.player.ai.flee_effect = .{
                .status = .Shove,
                .duration = .{ .Tmp = 10 },
                .exhausting = true,
            },
            .Healthy => state.player.max_HP = state.player.max_HP * 150 / 100,
            .Mana => state.player.max_MP = state.player.max_MP * 150 / 100,
            .Camoflaged => state.player.stats.Camoflage += 1,
            .Will => state.player.stats.Willpower += 3,
            .Echolocating => state.player.addStatus(.Echolocation, 7, .Prm),
        }
    }
};

pub fn choosePlayerUpgrades() void {
    var i: usize = 0;
    for (state.levelinfo) |level| if (level.upgr) {
        var upgrade: PlayerUpgrade = while (true) {
            const upgrade_c = rng.chooseUnweighted(PlayerUpgrade, &PlayerUpgrade.UPGRADES);
            const already_picked = for (state.player_upgrades) |existing_upgr| {
                if (existing_upgr.upgrade == upgrade_c) break true;
            } else false;
            if (!already_picked) break upgrade_c;
        } else err.wat();
        state.player_upgrades[i] = .{ .recieved = false, .upgrade = upgrade };
        i += 1;
    };
}

pub fn triggerStair(_: Coord, dest_stair: Coord) void {
    const dest = for (&DIRECTIONS) |d| {
        if (dest_stair.move(d, state.mapgeometry)) |neighbor| {
            if (state.is_walkable(neighbor, .{ .right_now = true }))
                break neighbor;
        }
    } else err.bug("Unable to find passable tile near upstairs!", .{});

    if (state.player.teleportTo(dest, null, false)) {
        state.message(.Move, "You ascend. Welcome to {s}!", .{state.levelinfo[dest_stair.z].name});
    } else {
        err.bug("Unable to ascend stairs! (something's in the way, maybe?)", .{});
    }

    // Remove all statuses and heal player.
    inline for (@typeInfo(Status).Enum.fields) |status| {
        state.player.cancelStatus(@field(Status, status.name));
    }
    state.player.HP = state.player.max_HP;

    if (state.levelinfo[state.player.coord.z].upgr) {
        for (state.player_upgrades) |*u| {
            if (!u.recieved) {
                u.recieved = true;
                state.message(.Info, "You feel different... {s}", .{u.upgrade.announce()});
                u.upgrade.implement();
                break;
            }
        } else err.bug("Cannot find upgrade to grant! (upgrades: {} {} {})", .{
            state.player_upgrades[0], state.player_upgrades[1], state.player_upgrades[2],
        });
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

    var announcements = AList.init(state.GPA.allocator());
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
                state.message(.Info, "Found a {s}.", .{n});
            } else {
                state.message(.Info, "Found {} {s}.", .{ ann.count, n });
            }
        }
    }
}

pub fn moveOrFight(direction: Direction) bool {
    const current = state.player.coord;

    if (direction.is_diagonal() and state.player.isUnderStatus(.Confusion) != null) {
        display.drawAlertThenLog("You cannot move diagonally whilst confused!", .{});
        return false;
    }

    const dest = current.move(direction, state.mapgeometry) orelse return false;

    // Does the player want to fight?
    if (state.dungeon.at(dest).mob) |mob| {
        if (state.player.isHostileTo(mob) and !state.player.canSwapWith(mob, direction)) {
            state.player.fight(mob, .{});
            return true;
        }
    }

    // Does the player want to trigger a machine that requires confirmation?
    if (state.dungeon.at(dest).surface) |surf| switch (surf) {
        .Machine => |m| if (m.evoke_confirm) |msg| {
            if (!display.drawYesNoPrompt("{s}", .{msg})) return false;
        },
        else => {},
    };

    // Should we auto-rest?
    if (auto_wait_enabled and
        state.player.turnsSpentMoving() >= @intCast(usize, state.player.stat(.Sneak)))
    {
        _ = state.player.rest();
        state.message(.Info, "Auto-waited.", .{});
        return true;
    }

    const ret = state.player.moveInDirection(direction);

    if (!state.player.coord.eq(current)) {
        if (state.dungeon.at(state.player.coord).surface) |s| switch (s) {
            .Machine => |m| if (m.interact1 != null) {
                state.message(.Info, "$c({s})$. Press $ba$. to activate.", .{m.name});
            },
            else => {},
        };
    }

    return ret;
}

pub fn grabItem() bool {
    if (state.player.inventory.pack.isFull()) {
        display.drawAlertThenLog("Your pack is full!", .{});
        return false;
    }

    var item: Item = undefined;
    var found_item = false;

    if (state.dungeon.at(state.player.coord).surface) |surface| {
        switch (surface) {
            .Container => |container| {
                if (container.items.len == 0) {
                    display.drawAlertThenLog("There's nothing in the {s}.", .{container.name});
                    return false;
                } else {
                    const index = display.drawItemChoicePrompt(
                        "Take what?",
                        .{},
                        container.items.constSlice(),
                    ) orelse return false;
                    item = container.items.orderedRemove(index) catch err.wat();
                    found_item = true;
                }
            },
            else => {},
        }
    }

    if (!found_item) {
        if (state.dungeon.itemsAt(state.player.coord).last()) |_| {
            item = state.dungeon.itemsAt(state.player.coord).pop() catch err.wat();
        } else {
            display.drawAlertThenLog("There's nothing here.", .{});
            return false;
        }
    }

    switch (item) {
        .Weapon, .Armor, .Cloak => {
            const slot = Mob.Inventory.EquSlot.slotFor(item);
            if (state.player.inventory.equipment(slot).*) |old_item| {
                state.player.dequipItem(slot, state.player.coord);
                state.message(.Info, "You drop the {s}.", .{
                    (old_item.longName() catch err.wat()).constSlice(),
                });
            }

            state.player.equipItem(slot, item);
            state.message(.Info, "Equipped a {s}.", .{
                (item.longName() catch err.wat()).constSlice(),
            });
        },
        else => {
            state.player.inventory.pack.append(item) catch err.wat();
            state.player.declareAction(.Grab);
            state.message(.Info, "Acquired: {s}", .{
                (state.player.inventory.pack.last().?.longName() catch err.wat()).constSlice(),
            });
        },
    }
    return true;
}

pub fn throwItem(index: usize) bool {
    assert(state.player.inventory.pack.len > index);

    const item = &state.player.inventory.pack.slice()[index];

    switch (item.*) {
        .Projectile, .Potion => {},
        else => {
            display.drawAlertThenLog("You can't throw that.", .{});
            return false;
        },
    }

    const dest = display.chooseCell(.{}) orelse return false;
    state.player.throwItem(item, dest, state.GPA.allocator());
    _ = state.player.removeItem(index) catch err.wat();
    return true;
}

pub fn activateSurfaceItem() bool {
    var mach: *Machine = undefined;
    if (state.dungeon.at(state.player.coord).surface) |s| switch (s) {
        .Machine => |m| if (m.interact1) |_| {
            mach = m;
        },
        else => {
            display.drawAlertThenLog("There's nothing here to activate.", .{});
            return false;
        },
    };

    const interaction = &mach.interact1.?;
    mach.evoke(state.player, interaction) catch |e| {
        switch (e) {
            error.NotPowered => display.drawAlertThenLog("The {s} has no power!", .{mach.name}),
            error.UsedMax => display.drawAlertThenLog("You can't use {s} anymore.", .{mach.name}),
            error.NoEffect => display.drawAlertThenLog("{s}", .{interaction.no_effect_msg}),
        }
        return false;
    };

    state.player.declareAction(.Interact);
    state.message(.Info, "{s}", .{interaction.success_msg});

    const left = mach.interact1.?.max_use - mach.interact1.?.used;
    if (left == 0) {
        state.message(.Info, "The {s} becomes inert.", .{mach.name});
    } else {
        state.message(.Info, "You can use this {s} {} more times.", .{ mach.name, left });
    }

    return true;
}

pub fn useItem(index: usize) bool {
    assert(state.player.inventory.pack.len > index);

    switch (state.player.inventory.pack.slice()[index]) {
        .Ring => |_| {
            // So this message was in response to player going "I want to eat it"
            // But of course they might have just been intending to "invoke" the
            // ring, not knowing that there's no such thing.
            //
            // FIXME: so this message can definitely be improved...
            display.drawAlertThenLog("Are you three?", .{});
            return false;
        },
        .Armor, .Cloak, .Weapon => err.wat(),
        .Potion => |p| {
            if (state.player.isUnderStatus(.Nausea) != null) {
                display.drawAlertThenLog("You can't drink potions while nauseated!", .{});
                return false;
            }

            state.player.quaffPotion(p, true);
            const prevtotal = (state.chardata.potions_quaffed.getOrPutValue(p.id, 0) catch err.wat()).value_ptr.*;
            state.chardata.potions_quaffed.put(p.id, prevtotal + 1) catch err.wat();
        },
        .Vial => |_| err.todo(),
        .Projectile, .Boulder => {
            display.drawAlertThenLog("You want to *eat* that?", .{});
            return false;
        },
        .Prop => |p| {
            state.message(.Info, "You admire the {s}.", .{p.name});
            return false;
        },
        .Evocable => |v| {
            v.evoke(state.player) catch |e| {
                if (e == error.NoCharges) {
                    display.drawAlertThenLog("You can't use the {s} anymore!", .{v.name});
                }
                return false;
            };

            const prevtotal = (state.chardata.evocs_used.getOrPutValue(v.id, 0) catch err.wat()).value_ptr.*;
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

pub fn dropItem(index: usize) bool {
    assert(state.player.inventory.pack.len > index);

    if (state.nextAvailableSpaceForItem(state.player.coord, state.GPA.allocator())) |coord| {
        const item = state.player.removeItem(index) catch err.wat();

        const dropped = state.player.dropItem(item, coord);
        assert(dropped);

        state.message(.Info, "Dropped: {s}.", .{
            (item.shortName() catch err.wat()).constSlice(),
        });
        return true;
    } else {
        display.drawAlertThenLog("There's no nearby space to drop items.", .{});
        return false;
    }
}
