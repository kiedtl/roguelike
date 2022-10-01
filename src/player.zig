const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;

const StackBuffer = @import("buffer.zig").StackBuffer;

const ai = @import("ai.zig");
const colors = @import("colors.zig");
const rng = @import("rng.zig");
const literature = @import("literature.zig");
const explosions = @import("explosions.zig");
const tasks = @import("tasks.zig");
const items = @import("items.zig");
const utils = @import("utils.zig");
const gas = @import("gas.zig");
const mapgen = @import("mapgen.zig");
const surfaces = @import("surfaces.zig");
const ui = @import("ui.zig");
const state = @import("state.zig");
const types = @import("types.zig");
const err = @import("err.zig");

const Activity = types.Activity;
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
const MobArrayList = types.MobArrayList;
const Status = types.Status;
const Machine = types.Machine;
const Direction = types.Direction;
const Inventory = types.Mob.Inventory;

const DIRECTIONS = types.DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub var wiz_lidless_eye: bool = false;

pub var auto_wait_enabled: bool = false;

pub const PlayerUpgradeInfo = struct {
    recieved: bool = false,
    upgrade: PlayerUpgrade,
};

pub const PlayerUpgrade = enum {
    Agile,
    OI_Enraged,
    Healthy,
    Will,
    Echolocating,

    pub const UPGRADES = [_]PlayerUpgrade{ .Agile, .OI_Enraged, .Healthy, .Will, .Echolocating };

    pub fn announce(self: PlayerUpgrade) []const u8 {
        return switch (self) {
            .Agile => "You are good at evading blows.",
            .OI_Enraged => "You feel hatred building up inside.",
            .Healthy => "You are unusually robust.",
            .Will => "Your will hardens.",
            .Echolocating => "Your sense of hearing becomes acute.",
        };
    }

    pub fn description(self: PlayerUpgrade) []const u8 {
        return switch (self) {
            .Agile => "You have a +20% dodging bonus.",
            .OI_Enraged => "You become enraged when badly hurt.",
            .Healthy => "You have 50% more health than usual.",
            .Will => "You have 3 extra pips of willpower.",
            .Echolocating => "You passively echolocate areas around sound.",
        };
    }

    pub fn implement(self: PlayerUpgrade) void {
        switch (self) {
            .Agile => state.player.stats.Evade += 10,
            .OI_Enraged => state.player.ai.flee_effect = .{
                .status = .Enraged,
                .duration = .{ .Tmp = 10 },
                .exhausting = true,
            },
            .Healthy => state.player.max_HP = state.player.max_HP * 150 / 100,
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

pub fn triggerPoster(coord: Coord) bool {
    const poster = state.dungeon.at(coord).surface.?.Poster;
    ui.drawTextScreen("$oYou read:$.\n\n{s}", .{poster.text});
    return false;
}

pub fn triggerStair(cur_stair: Coord, dest_stair: Coord) bool {
    if (state.levelinfo[dest_stair.z].optional) {
        if (!ui.drawYesNoPrompt("Really travel to optional level?", .{}))
            return false;
    }

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

    if (state.levelinfo[state.player.coord.z].upgr) {
        state.player.max_HP += 2;

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

    // Remove all statuses and heal player.
    inline for (@typeInfo(Status).Enum.fields) |status| {
        const st = @field(Status, status.name);
        if (state.player.isUnderStatus(st)) |st_info| {
            if (st_info.duration == .Tmp) {
                state.player.cancelStatus(st);
            }
        }
    }
    state.player.HP = state.player.max_HP;

    // "Garbage-collect" previous level.
    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
        if (mob.coord.z != cur_stair.z) continue;
        mob.path_cache.clearAndFree();
    }

    return true;
}

// Called on each player's turn.
//
// Checks if there's garbage/useless stuff where the player is standing, and
// discards it if that's the case.
//
// Won't act if the player is currently spotted.
pub fn checkForGarbage() void {
    if (isPlayerSpotted()) {
        return;
    }

    if (state.dungeon.itemsAt(state.player.coord).last()) |item| {
        // Don't use item.isUseful() here because that would toss Boulders
        // and Vials
        //
        if (item == .Prop) {
            ui.Animation.apply(.{ .PopChar = .{ .coord = state.player.coord, .char = '/' } });
            state.message(.Unimportant, "You toss the useless $g{s}$..", .{item.Prop.name});
            _ = state.dungeon.itemsAt(state.player.coord).pop() catch err.wat();
        }
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

                // Disabled for now. Will need to decide if it's worth keeping in
                // later on from player feedback.
                //
                // Reasons to keep:
                //   - New players realize that there are items they can pick up/use
                //   - ???
                //
                // Reasons to remove:
                //   - Clutters map, especially in loot-heavy areas (vaults, Cavern)
                //
                // if (state.dungeon.itemsAt(fc).last()) |item|
                //     if (item.announce()) {
                //         const n = item.shortName() catch err.wat();
                //         S._addToAnnouncements(n, &announcements);
                //     };
            }

            memorizeTile(fc, .Immediate);
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

pub fn tryRest() bool {
    if (state.player.hasStatus(.Pain)) {
        ui.drawAlertThenLog("You cannot rest while in pain!", .{});
        return false;
    }

    state.player.rest();
    return true;
}

pub fn moveOrFight(direction: Direction) bool {
    const current = state.player.coord;

    const dest = current.move(direction, state.mapgeometry) orelse return false;

    // Does the player want to trigger a machine that requires confirmation, or
    // maybe rummage a container?
    //
    if (state.dungeon.at(dest).surface) |surf| switch (surf) {
        .Machine => |m| if (m.evoke_confirm) |msg| {
            if (!ui.drawYesNoPrompt("{s}", .{msg}))
                return false;
        },
        .Container => |_| return rummageContainer(dest),
        else => {},
    };

    if (direction.is_diagonal() and state.player.isUnderStatus(.Disorient) != null) {
        ui.drawAlertThenLog("You cannot move or attack diagonally whilst disoriented!", .{});
        return false;
    }

    // Should we auto-rest?
    if (shouldAutoWait()) {
        state.player.rest();
        state.message(.Info, "Auto-waited.", .{});
        return true;
    }

    // Does the player want to stab?
    if (state.dungeon.at(dest).mob) |mob| {
        if (state.player.isHostileTo(mob)) switch (mob.ai.phase) {
            .Work => {
                state.player.fight(mob, .{ .free_attack = true });
                return false;
            },
            .Hunt, .Investigate => if (!ai.isEnemyKnown(mob, state.player)) {
                if (!ui.drawYesNoPrompt("Really push past unaware enemy?", .{}))
                    return false;
            },
            else => {},
        };
    }

    // Does the player want to move into a surveilled location?
    if (!isPlayerSpotted() and enemiesCanSee(dest)) {
        if (!ui.drawYesNoPrompt("Really move into an enemy's view?", .{}))
            return false;
    }

    const ret = state.player.moveInDirection(direction);

    if (!state.player.coord.eq(current)) {
        if (state.dungeon.at(state.player.coord).surface) |s| switch (s) {
            .Machine => |m| if (m.player_interact) |interaction| {
                if (m.canBeInteracted(state.player, &interaction)) {
                    state.message(.Info, "$c({s})$. Press $bA$. to activate.", .{m.name});
                } else {
                    state.message(.Info, "$c({s})$. $gCannot be activated.$.", .{m.name});
                }
            },
            else => {},
        };
    }

    return ret;
}

pub fn rummageContainer(coord: Coord) bool {
    const container = state.dungeon.at(coord).surface.?.Container;

    if (container.items.len == 0) {
        ui.drawAlertThenLog("There's nothing in the {s}.", .{container.name});
        return false;
    }

    ui.Animation.apply(.{
        .PopChar = .{ .coord = state.player.coord, .char = '?', .fg = colors.GOLD, .delay = 125 },
    });

    var found_goodies = false;
    while (container.items.pop()) |item| {
        if (item.isUseful())
            found_goodies = true;

        if (state.nextAvailableSpaceForItem(coord, state.GPA.allocator())) |spot| {
            state.dungeon.itemsAt(spot).append(item) catch err.wat();
        } else {
            // FIXME: an item gets swallowed up here!
            break;
        }
    } else |_| {}

    if (container.items.len == 0) {
        state.message(.Info, "You rummage through the {s}...", .{container.name});
    } else {
        state.message(.Info, "You rummage through part of the {s}...", .{container.name});
    }

    if (found_goodies) {
        state.message(.Info, "You found some goodies!", .{});
    } else {
        state.message(.Unimportant, "You found some junk.", .{});
    }

    state.player.declareAction(.Interact);
    return true;
}

pub fn equipItem(item: Item) bool {
    switch (item) {
        .Weapon, .Armor, .Cloak, .Aux => {
            const slot = Mob.Inventory.EquSlot.slotFor(item);
            if (state.player.inventory.equipment(slot).*) |old_item| {
                state.player.dequipItem(slot, state.player.coord);
                state.message(.Inventory, "You drop the {s}.", .{
                    (old_item.longName() catch err.wat()).constSlice(),
                });
                state.player.declareAction(.Drop);
            }

            state.player.equipItem(slot, item);
            state.message(.Inventory, "Equipped a {s}.", .{
                (item.longName() catch err.wat()).constSlice(),
            });
            state.player.declareAction(.Use);
        },
        .Ring => |r| {
            var empty_slot: ?Inventory.EquSlot = for (Inventory.RING_SLOTS) |slot| {
                if (state.player.inventory.equipment(slot).* == null)
                    break slot;
            } else null;

            if (empty_slot == null) {
                const index = ui.drawChoicePrompt(
                    "Replace what ring with the $b{s}$.?",
                    .{r.name},
                    &[Inventory.RING_SLOTS.len][]const u8{
                        state.player.inventory.equipment(.Ring1).*.?.Ring.name,
                        state.player.inventory.equipment(.Ring2).*.?.Ring.name,
                        state.player.inventory.equipment(.Ring3).*.?.Ring.name,
                        state.player.inventory.equipment(.Ring4).*.?.Ring.name,
                    },
                ) orelse return false;
                empty_slot = Inventory.RING_SLOTS[index];
            }

            state.player.equipItem(empty_slot.?, item);
            state.player.declareAction(.Use);
            state.message(.Inventory, "Equipped the {s}.", .{
                (item.longName() catch err.wat()).constSlice(),
            });
        },
        else => unreachable,
    }
    return true;
}

pub fn grabItem() bool {
    var item: Item = undefined;
    var found_item = false;

    if (state.dungeon.at(state.player.coord).surface) |surface| {
        switch (surface) {
            .Container => |_| return rummageContainer(state.player.coord),
            else => {},
        }
    }

    if (!found_item) {
        if (state.dungeon.itemsAt(state.player.coord).last()) |_| {
            item = state.dungeon.itemsAt(state.player.coord).pop() catch err.wat();
        } else {
            ui.drawAlertThenLog("There's nothing here.", .{});
            return false;
        }
    }

    switch (item) {
        .Rune => |rune| {
            state.message(.Info, "You grab the {s} rune.", .{rune.name()});
            state.collected_runes.set(rune, true);

            state.message(.Important, "The alarm goes off!!", .{});
            state.markMessageNoisy();
            state.player.makeNoise(.Alarm, .Loudest);

            state.player.declareAction(.Grab);
        },
        .Ring, .Armor, .Cloak, .Aux, .Weapon => return equipItem(item),
        else => {
            if (state.player.inventory.pack.isFull()) {
                ui.drawAlertThenLog("Your pack is full!", .{});
                return false;
            }

            state.player.inventory.pack.append(item) catch err.wat();
            state.player.declareAction(.Grab);
            state.message(.Inventory, "Acquired: {s}", .{
                (state.player.inventory.pack.last().?.longName() catch err.wat()).constSlice(),
            });
        },
    }

    ui.Animation.apply(.{ .PopChar = .{ .coord = state.player.coord, .char = '/' } });

    return true;
}

pub fn throwItem(index: usize) bool {
    assert(state.player.inventory.pack.len > index);

    const item = state.player.inventory.pack.slice()[index];

    if (item != .Projectile and !(item == .Consumable and item.Consumable.throwable)) {
        ui.drawAlertThenLog("You can't throw that.", .{});
        return false;
    }

    const dest = ui.chooseCell(.{
        .require_seen = true,
        .show_trajectory = true,
    }) orelse return false;

    state.player.throwItem(&item, dest, state.GPA.allocator());
    _ = state.player.removeItem(index) catch err.wat();
    return true;
}

pub fn activateSurfaceItem(coord: Coord) bool {
    var mach: *Machine = undefined;

    // FIXME: simplify this, DRY
    if (state.dungeon.at(coord).surface) |s| {
        switch (s) {
            .Machine => |m| if (m.player_interact) |_| {
                mach = m;
            } else {
                ui.drawAlertThenLog("You can't activate that.", .{});
                return false;
            },
            else => {
                ui.drawAlertThenLog("There's nothing here to activate.", .{});
                return false;
            },
        }
    } else {
        ui.drawAlertThenLog("There's nothing here to activate.", .{});
        return false;
    }

    const interaction = &mach.player_interact.?;
    mach.evoke(state.player, interaction) catch |e| {
        switch (e) {
            error.UsedMax => ui.drawAlertThenLog("You can't use the {s} again.", .{mach.name}),
            error.NoEffect => if (interaction.no_effect_msg) |msg| {
                ui.drawAlertThenLog("{s}", .{msg});
            },
        }
        return false;
    };

    state.player.declareAction(.Interact);
    state.message(.Info, "{s}", .{interaction.success_msg});

    if (mach.player_interact.?.max_use != 0) {
        const left = mach.player_interact.?.max_use - mach.player_interact.?.used;
        if (left == 0) {
            state.message(.Unimportant, "You cannot use the {s} again.", .{mach.name});
        } else {
            state.message(.Info, "You can use this {s} {} more times.", .{ mach.name, left });
        }
    }

    return true;
}

pub fn dipWeapon(potion_index: usize) bool {
    assert(state.player.inventory.pack.len > potion_index);

    const potion = state.player.inventory.pack.slice()[potion_index].Consumable;
    if (!potion.is_potion or potion.dip_effect == null) {
        ui.drawAlertThenLog("You can't dip your weapon in that!", .{});
        return false;
    }

    const weapon = if (state.player.inventory.equipment(.Weapon).*) |w|
        w.Weapon
    else {
        ui.drawAlertThenLog("You aren't wielding a weapon!", .{});
        return false;
    };

    if (!weapon.is_dippable) {
        ui.drawAlertThenLog("You can't dip that weapon!", .{});
        return false;
    }

    if (weapon.dip_counter > 0) {
        const response = ui.drawYesNoPrompt("Really dip again? It's already dipped in a potion of {s}.", .{weapon.dip_effect.?.name});
        if (!response) return false;
    }

    weapon.dip_counter = 10;
    weapon.dip_effect = potion;
    _ = state.player.inventory.pack.orderedRemove(potion_index) catch err.wat();
    state.message(.Info, "You dip your {s} in the potion of {s}.", .{ weapon.name, potion.name });

    state.player.declareAction(.Use);
    return true;
}

pub fn useItem(index: usize) bool {
    assert(state.player.inventory.pack.len > index);

    const item = state.player.inventory.pack.slice()[index];
    switch (item) {
        .Rune => err.wat(),
        .Ring, .Armor, .Cloak, .Aux, .Weapon => return equipItem(item),
        .Consumable => |p| {
            if (p.is_potion and state.player.isUnderStatus(.Nausea) != null) {
                ui.drawAlertThenLog("You can't drink potions while nauseated!", .{});
                return false;
            }

            state.player.useConsumable(p, true) catch |e| switch (e) {
                error.BadPosition => {
                    ui.drawAlertThenLog("You can't use this kit here.", .{});
                    return false;
                },
            };

            const prevtotal = (state.chardata.items_used.getOrPutValue(p.id, 0) catch err.wat()).value_ptr.*;
            state.chardata.items_used.put(p.id, prevtotal + 1) catch err.wat();
        },
        .Vial => |_| err.todo(),
        .Projectile, .Boulder => {
            ui.drawAlertThenLog("You want to *eat* that?", .{});
            return false;
        },
        .Prop => |p| {
            state.message(.Info, "You admire the {s}.", .{p.name});
            return false;
        },
        .Evocable => |v| {
            v.evoke(state.player) catch |e| {
                if (e == error.NoCharges) {
                    ui.drawAlertThenLog("You can't use the {s} anymore!", .{v.name});
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

        state.message(.Inventory, "Dropped: {s}.", .{
            (item.shortName() catch err.wat()).constSlice(),
        });
        return true;
    } else {
        ui.drawAlertThenLog("There's no nearby space to drop items.", .{});
        return false;
    }
}

pub fn memorizeTile(fc: Coord, mtype: state.MemoryTile.Type) void {
    const memt = state.MemoryTile{ .tile = Tile.displayAs(fc, true, false), .type = mtype };
    state.memory.put(fc, memt) catch err.wat();
}

pub fn shouldAutoWait() bool {
    if (!auto_wait_enabled)
        return false;

    if (state.player.hasStatus(.Pain))
        return false;

    if (state.player.turnsSpentMoving() < @intCast(usize, state.player.stat(.Sneak)))
        return false;

    if (isPlayerSpotted())
        return false;

    return true;
}

pub fn enemiesCanSee(coord: Coord) bool {
    const moblist = state.createMobList(false, true, state.player.coord.z, state.GPA.allocator());
    defer moblist.deinit();

    return b: for (moblist.items) |mob| {
        if (!mob.no_show_fov and mob.ai.is_combative and mob.isHostileTo(state.player) and !mob.should_be_dead()) {
            if (mob.cansee(coord)) {
                break :b true;
            }
        }
    } else false;
}

// Returns true if player is known by any nearby enemies.
pub fn isPlayerSpotted() bool {
    if (state.player_is_spotted.turn_cached == state.player_turns) {
        return state.player_is_spotted.is_spotted;
    }

    const moblist = state.createMobList(false, true, state.player.coord.z, state.GPA.allocator());
    defer moblist.deinit();

    const is_spotted = enemiesCanSee(state.player.coord) or (b: for (moblist.items) |mob| {
        if (!mob.no_show_fov and mob.ai.is_combative and mob.isHostileTo(state.player)) {
            if (ai.isEnemyKnown(mob, state.player))
                break :b true;
        }
    } else false);

    state.player_is_spotted = .{
        .is_spotted = is_spotted,
        .turn_cached = state.player_turns,
    };

    return is_spotted;
}

pub fn canSeeAny(coords: []const ?Coord) bool {
    return for (coords) |m_coord| {
        if (m_coord) |coord| {
            if (state.player.cansee(coord)) {
                break true;
            }
        }
    } else false;
}

pub fn getRingByIndex(index: usize) ?*Ring {
    assert(index <= 9);

    if (index >= state.default_patterns.len) {
        const rel_index = index - state.default_patterns.len;
        if (rel_index >= Inventory.RING_SLOTS.len) return null;
        return if (state.player.inventory.equipment(Inventory.RING_SLOTS[rel_index]).*) |r| r.Ring else null;
    } else {
        return &state.default_patterns[index];
    }
}

pub fn getActiveRing() ?*Ring {
    var i: usize = 0;
    return while (i <= 9) : (i += 1) {
        if (getRingByIndex(i)) |ring| {
            if (ring.activated)
                break ring;
        }
    } else null;
}

pub fn getRingHints(ring: *Ring) void {
    var buf = StackBuffer(Activity, 16).init(null);

    const chk_func = ring.pattern_checker.funcs[ring.pattern_checker.turns_taken];

    for (&DIRECTIONS) |d| if (state.player.coord.move(d, state.mapgeometry)) |neighbor_tile| {
        const move_activity = Activity{ .Move = d };
        if (state.is_walkable(neighbor_tile, .{ .mob = state.player })) {
            if ((chk_func)(state.player, &ring.pattern_checker.state, move_activity, true))
                buf.append(move_activity) catch err.wat();
        }

        if (state.dungeon.at(neighbor_tile).mob) |neighbor_mob| {
            if (neighbor_mob.isHostileTo(state.player) and neighbor_mob.ai.is_combative) {
                const attack_activity = Activity{ .Attack = .{
                    .who = neighbor_mob,
                    .direction = d,
                    .coord = neighbor_tile,
                    .delay = 0,
                } };
                if ((chk_func)(state.player, &ring.pattern_checker.state, attack_activity, true))
                    buf.append(attack_activity) catch err.wat();
            }
        }
    };

    const wait_activity: Activity = .Rest;
    if ((chk_func)(state.player, &ring.pattern_checker.state, wait_activity, true))
        buf.append(wait_activity) catch err.wat();

    if (buf.len == 0) {
        state.message(.Info, "[$o{s}$.] No valid moves!", .{ring.name});
    }

    var strbuf = std.ArrayList(u8).init(state.GPA.allocator());
    defer strbuf.deinit();
    const writer = strbuf.writer();
    writer.print("[$o{s}$.] ", .{ring.name}) catch err.wat();
    formatActivityList(buf.constSlice(), writer);
    state.message(.Info, "{s}", .{strbuf.items});
}

pub fn formatActivityList(activities: []const Activity, writer: anytype) void {
    for (activities) |activity, i| {
        if (i != 0 and i < activities.len - 1)
            writer.print(", ", .{}) catch err.wat()
        else if (i != 0 and i == activities.len - 1)
            writer.print(", or ", .{}) catch err.wat();

        (switch (activity) {
            .Rest => writer.print("wait", .{}),
            .Attack => |d| writer.print("attack $b{}$.", .{d.direction}),
            .Move => |d| writer.print("go $b{}$.", .{d}),
            else => unreachable,
        }) catch err.wat();
    }
}
