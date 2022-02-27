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
const types = @import("types.zig");
const state = @import("state.zig");
const err = @import("err.zig");
usingnamespace @import("types.zig");

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
    Stealthy,
    Will,
    Sniffing,
    Echolocating,

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
            .Stealthy => "You move stealthily.",
            .Will => "Your will hardens.",
            .Sniffing => "Your sense of smell becomes acute.",
            .Echolocating => "Your sense of hearing becomes acute.",
        };
    }

    pub fn implement(self: PlayerUpgrade) void {
        switch (self) {
            .Fast => state.player.base_speed = state.player.base_speed * 90 / 100,
            .Strong => state.player.base_strength = state.player.base_strength * 130 / 100,
            .Agile => state.player.base_dexterity = state.player.base_dexterity * 130 / 100,
            .OI_Enraged => state.player.ai.flee_effect = .{
                .status = .Enraged,
                .duration = 10,
                .exhausting = true,
            },
            .OI_Fast => state.player.ai.flee_effect = .{
                .status = .Fast,
                .duration = 10,
                .exhausting = true,
            },
            .OI_Shove => state.player.ai.flee_effect = .{
                .status = .Shove,
                .duration = 10,
                .exhausting = true,
            },
            .Healthy => state.player.max_HP = state.player.max_HP * 150 / 100,
            .Mana => err.todo(),
            .Stealthy => state.player.base_stealth += 1,
            .Will => state.player.willpower = math.clamp(state.player.willpower + 3, 0, 10),
            .Sniffing => err.todo(),
            .Echolocating => state.player.addStatus(.Echolocation, 1, 7, true),
        }
    }
};

pub fn choosePlayerUpgrades() void {
    var i: usize = 0;
    for (state.levelinfo) |level| if (level.upgr) {
        var upgrade: PlayerUpgrade = while (true) {
            const upgrades = meta.fields(PlayerUpgrade);
            const upgrade_i = rng.chooseUnweighted(std.builtin.TypeInfo.EnumField, upgrades);
            const upgrade_v = @intToEnum(PlayerUpgrade, upgrade_i.value);
            const already_picked = for (state.player.upgrades) |existing_upgr| {
                if (existing_upgr.upgrade == upgrade_v) break true;
            } else false;
            if (!already_picked) break upgrade;
        } else err.wat();
        state.player_upgrades[i] = .{ .recieved = false, .upgrade = upgrade };
        i += 1;
    };
}

pub fn triggerStair(stair: Coord, dest_stair: Coord) void {
    const dest = for (&DIRECTIONS) |d| {
        if (dest_stair.move(d, state.mapgeometry)) |neighbor| {
            if (state.is_walkable(neighbor, .{ .right_now = true }))
                break neighbor;
        }
    } else err.bug("Unable to find passable tile near upstairs!", .{});

    if (state.player.teleportTo(dest, null)) {
        state.message(.Move, "You ascend. Welcome to {}!", .{state.levelinfo[dest_stair.z].name});
    } else {
        err.bug("Unable to ascend stairs! (something's in the way, maybe?)", .{});
    }

    // Remove all statuses and heal player.
    inline for (@typeInfo(Status).Enum.fields) |status| {
        const status_e = @field(Status, status.name);
        state.player.addStatus(status_e, 0, 0, false);
    }
    state.player.HP = state.player.max_HP;

    if (state.levelinfo[state.player.coord.z].upgr) {
        const upgrade = for (state.player_upgrades) |u| {
            if (!u.recieved) break u.upgrade;
        } else err.bug("Cannot find upgrade to grant!", .{});
        upgrade.implement();

        state.message(.Info, "You feel different... {}", .{upgrade.announce()});
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

fn _invokeMachine(mach: *Machine) bool {
    const interaction = &mach.interact1.?;
    mach.evoke(state.player, interaction) catch |e| {
        switch (e) {
            error.NotPowered => state.message(.MetaError, "The {} has no power!", .{mach.name}),
            error.UsedMax => state.message(.MetaError, "You can't use {} anymore.", .{mach.name}),
            error.NoEffect => state.message(.MetaError, "{}", .{interaction.no_effect_msg}),
        }
        return false;
    };

    state.player.declareAction(.Interact);
    state.message(.Info, "{}", .{interaction.success_msg});

    const left = mach.interact1.?.max_use - mach.interact1.?.used;
    if (left == 0) {
        state.message(.Info, "The {} becomes inert.", .{mach.name});
    } else {
        state.message(.Info, "You can use this {} {} more times.", .{ mach.name, left });
    }

    return true;
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
        return _invokeMachine(mach);
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
                        "Take what?",
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
        "Throw what?",
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

pub fn useSomething() bool {
    var mach: ?*Machine = null;
    if (state.dungeon.at(state.player.coord).surface) |s| switch (s) {
        .Machine => |m| if (m.interact1) |_| {
            mach = m;
        },
        else => {},
    };

    if (mach) |machine| {
        const choice = display.chooseOption(
            "Use what?",
            &[_][]const u8{ machine.name, "<Inventory>" },
        ) orelse return false;
        return switch (choice) {
            0 => _invokeMachine(machine),
            1 => _useItem(),
            else => err.wat(),
        };
    } else {
        return _useItem();
    }
}

fn _useItem() bool {
    if (state.player.inventory.pack.len == 0) {
        state.message(.MetaError, "Your pack is empty.", .{});
        return false;
    }

    const index = display.chooseInventoryItem(
        "Use what item?",
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
            if (state.player.isUnderStatus(.Nausea) != null) {
                state.message(.MetaError, "You can't drink potions while nauseated!", .{});
                return false;
            }

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
            "Drop what?",
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
