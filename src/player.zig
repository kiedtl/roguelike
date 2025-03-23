const std = @import("std");
const math = std.math;
const assert = std.debug.assert;
const sort = std.sort;
const mem = std.mem;
const meta = std.meta;

const StackBuffer = @import("buffer.zig").StackBuffer;

const ai = @import("ai.zig");
const alert = @import("alert.zig");
const colors = @import("colors.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const events = @import("events.zig");
const explosions = @import("explosions.zig");
const gas = @import("gas.zig");
const items = @import("items.zig");
const janet = @import("janet.zig");
const literature = @import("literature.zig");
const mapgen = @import("mapgen.zig");
const rng = @import("rng.zig");
const scores = @import("scores.zig");
const spells = @import("spells.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const tasks = @import("tasks.zig");
const types = @import("types.zig");
const ui = @import("ui.zig");
const utils = @import("utils.zig");

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
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub var wiz_lidless_eye: bool = false;

pub const ConjAugment = enum(usize) {
    // Survival,
    Melee = 0,
    Evade = 1,
    WallDisintegrate1 = 2,
    WallDisintegrate2 = 3,
    UndeadBloodthirst = 4,
    rElec_25 = 5,
    rElec_50 = 6,
    rFire_25 = 7,
    rFire_50 = 8,

    pub const TOTAL = std.meta.fields(@This()).len;

    pub fn name(self: ConjAugment) []const u8 {
        return switch (self) {
            .WallDisintegrate1 => "Wall Disintegration [1]",
            .WallDisintegrate2 => "Wall Disintegration [2]",
            .rFire_25 => "rFire+25",
            .rFire_50 => "rFire+50",
            .rElec_25 => "rElec+25",
            .rElec_50 => "rElec+50",
            .UndeadBloodthirst => "Undead Bloodthirst",
            .Melee => "+Melee",
            .Evade => "+Evasion",
        };
    }

    pub fn char(self: ConjAugment) []const u8 {
        return switch (self) {
            // .Survival => "Opposing spectral sabres will not always destroy your own. (TODO: update)",
            .WallDisintegrate1 => "$aw$.",
            .WallDisintegrate2 => "$aw+$.",
            .rFire_25 => "$rF$.",
            .rFire_50 => "$rF+$.",
            .rElec_25 => "$bE$.",
            .rElec_50 => "$bE+$.",
            .UndeadBloodthirst => "u",
            .Melee => "m",
            .Evade => "v",
        };
    }

    pub fn description(self: ConjAugment) []const u8 {
        return switch (self) {
            // .Survival => "Opposing spectral sabres will not always destroy your own. (TODO: update)",
            .WallDisintegrate1 => "50% chance for an adjacent wall to disintegrate into a new sabre when there are other sabres in your vision.",
            .WallDisintegrate2 => "10% chance for two adjacent walls to disintegrate into new sabres when there are other sabres in your vision.",
            .rFire_25 => "Your sabres possess +25% rFire.",
            .rFire_50 => "Your sabres possess +50% rFire.",
            .rElec_25 => "Your sabres possess +25% rElec.",
            .rElec_50 => "Your sabres possess +50% rElec.",
            .UndeadBloodthirst => "A new volley of sabres spawn when you see a hostile undead die.",
            .Melee => "Your sabres possess +25% Melee.",
            .Evade => "Your sabres possess +25% Evade.",
        };
    }
};

pub const ConjAugmentInfo = struct { received: bool, a: ConjAugment };
pub const ConjAugmentEntry = struct { w: usize, a: ConjAugment };

pub const CONJ_AUGMENT_DROPS = [_]ConjAugmentEntry{
    // .{ .w = 99, .a = .Survival },
    .{ .w = 99, .a = .WallDisintegrate1 },
    .{ .w = 25, .a = .WallDisintegrate2 },
    .{ .w = 50, .a = .rFire_25 },
    .{ .w = 50, .a = .rFire_50 },
    .{ .w = 99, .a = .rElec_25 },
    .{ .w = 99, .a = .rElec_50 },
    .{ .w = 50, .a = .UndeadBloodthirst },
    .{ .w = 99, .a = .Melee },
    .{ .w = 50, .a = .Evade },
};

pub const PlayerUpgradeInfo = struct {
    recieved: bool = false,
    upgrade: PlayerUpgrade,
};

pub const PlayerUpgrade = enum {
    Agile,
    OI_Enraged,
    Healthy,
    Powerful,
    Potent,
    Will,
    Echolocating,

    pub const TOTAL = std.meta.fields(@This()).len;
    pub const UPGRADES = [_]PlayerUpgrade{ .Agile, .OI_Enraged, .Healthy, .Will, .Echolocating };

    pub fn name(self: PlayerUpgrade) []const u8 {
        return switch (self) {
            .Agile => "Agility",
            .OI_Enraged => "Inner Rage",
            .Healthy => "Robust",
            .Powerful => "Powerful",
            .Potent => "Potent",
            .Will => "Hardened Will",
            .Echolocating => "Echolocation",
        };
    }

    pub fn announce(self: PlayerUpgrade) []const u8 {
        return switch (self) {
            .Agile => "You are good at evading blows.",
            .OI_Enraged => "You feel hatred building up inside.",
            .Healthy => "You are unusually robust.",
            .Powerful => "You feel powerful.",
            .Potent => "You feel a deeper connection to the Power here.",
            .Will => "Your will hardens.",
            .Echolocating => "Your sense of hearing becomes acute.",
        };
    }

    pub fn description(self: PlayerUpgrade) []const u8 {
        return switch (self) {
            .Agile => "You have a +20% dodging bonus.",
            .OI_Enraged => "You become enraged when badly hurt.",
            .Healthy => "You have 50% more health than usual.",
            .Powerful => "You have 2x max mana.",
            .Potent => "You 50% more mana and +25% Potential.",
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
            .Powerful => state.player.max_MP = state.player.max_MP * 2,
            .Potent => {
                state.player.max_MP = state.player.max_MP * 150 / 100;
                state.player.stats.Potential += 25;
            },
            .Will => state.player.stats.Willpower += 3,
            .Echolocating => state.player.addStatus(.Echolocation, 5, .Prm),
        }
    }
};

pub fn choosePlayerUpgrades() void {
    var upgrades = PlayerUpgrade.UPGRADES;
    rng.shuffle(PlayerUpgrade, &upgrades);

    var i: usize = 0;
    for (state.levelinfo) |level| if (level.upgr) {
        state.player_upgrades[i] = .{ .recieved = false, .upgrade = upgrades[i] };
        i += 1;
    };

    var augments = StackBuffer(ConjAugmentEntry, ConjAugment.TOTAL).init(&CONJ_AUGMENT_DROPS);
    for (&state.player_conj_augments) |*entry| {
        // Choose an augment...
        //
        const augment = rng.choose2(ConjAugmentEntry, augments.constSlice(), "w") catch err.wat();
        entry.* = .{ .received = false, .a = augment.a };

        // ...and then delete that entry to avoid it being given again
        //
        const index = augments.linearSearch(augment, struct {
            pub fn f(a: ConjAugmentEntry, b: ConjAugmentEntry) bool {
                return a.a == b.a;
            }
        }.f).?;
        _ = augments.orderedRemove(index) catch err.wat(); // FIXME: should be swapRemove()
    }
}

pub fn hasAugment(augment: ConjAugment) bool {
    return for (state.player_conj_augments) |augment_info| {
        if (augment_info.received and augment_info.a == augment)
            break true;
    } else false;
}

pub fn hasSabresInSight() bool {
    return for (state.player.squad.?.members.constSlice()) |squadling| {
        if (!squadling.is_dead and mem.eql(u8, squadling.id, "spec_sabre"))
            break true;
    } else false;
}

pub fn hasAlignedNC() bool {
    return repPtr().* > 0;
}

pub fn repPtr() *isize {
    return &state.night_rep[@intFromEnum(state.player.faction)];
}

pub fn triggerPoster(coord: Coord) bool {
    const poster = state.dungeon.at(coord).surface.?.Poster;
    ui.drawTextScreen("$oYou read:$.\n\n{s}", .{poster.text});
    return false;
}

pub fn triggerStair(stair: surfaces.Stair, cur_stair: Coord) bool {
    // if (state.levelinfo[dest_stair.z].optional) {
    //     if (!ui.drawYesNoPrompt("Really travel to optional level?", .{}))
    //         return false;
    // }

    // Index into inventory
    var stair_key: ?usize = null;

    if (stair.locked) {
        assert(stair.stairtype != .Down);
        stair_key = for (state.player.inventory.pack.constSlice(), 0..) |item, ind| {
            if (item == .Key and item.Key.level == cur_stair.z and
                item.Key.lock == @as(meta.Tag(surfaces.Stair.Type), stair.stairtype) and
                (item.Key.lock != .Up or item.Key.lock.Up == stair.stairtype.Up))
            {
                break ind;
            }
        } else null;
        if (stair_key == null) {
            ui.drawAlert("The stair is locked and you don't have a matching key.", .{});
            return false;
        }
    }

    if (stair.stairtype == .Access) {
        state.state = .Win;
        // Don't bother removing key
        return true;
    } else if (stair.stairtype == .Down) {
        ui.drawAlert("Why would you want to go back?", .{});
        return false;
    }

    const dest_floor = stair.stairtype.Up;

    // state.message(.Move, "You ascend...", .{});
    _ = ui.drawTextModalNoInput("You ascend...", .{});

    mapgen.initLevel(dest_floor);

    // The "sealing the steel doors" is just excuse for why guards don't follow
    // player.
    //
    // Soon enough though, they will, and this message can be removed.
    state.message(.Unimportant, "You ascend, sealing the steel doors behind you.", .{});

    const dest_stair = state.dungeon.entries[dest_floor];
    const dest = for (&DIRECTIONS) |d| {
        if (dest_stair.move(d, state.mapgeometry)) |neighbor| {
            if (state.is_walkable(neighbor, .{ .right_now = true }))
                break neighbor;
        }
    } else err.bug("Unable to find passable tile near upstairs!", .{});

    if (!state.player.teleportTo(dest, null, false, false)) {
        err.bug("Unable to ascend stairs! (something's in the way, maybe?)", .{});
    }

    if (state.levelinfo[state.player.coord.z].upgr) {
        state.player.max_HP += 2;

        const upgrade = for (&state.player_upgrades) |*u| {
            if (!u.recieved)
                break u;
        } else err.bug("Cannot find upgrade to grant! (upgrades: {} {} {})", .{
            state.player_upgrades[0], state.player_upgrades[1], state.player_upgrades[2],
        });

        upgrade.recieved = true;
        state.message(.Info, "You feel different... {s}", .{upgrade.upgrade.announce()});
        upgrade.upgrade.implement();
    }

    const rep = &state.night_rep[@intFromEnum(state.player.faction)];
    if (rep.* < 0) rep.* += 1;

    combat.disruptAllUndead(dest_stair.z);
    alert.deinit();
    alert.init();

    // "Garbage-collect" previous level.
    var iter = state.mobs.iterator();
    while (iter.next()) |mob| {
        if (mob.coord.z != cur_stair.z) continue;
        mob.path_cache.clearAndFree();
    }

    if (stair_key) |pack_ind|
        _ = state.player.inventory.pack.orderedRemove(pack_ind) catch err.wat();

    events.check(dest_stair.z, .EnteringNewLevel);

    return true;
}

pub const WizardFun = enum {
    Up,
    RotateFaction,
    Vision,
    Teleport,
    Particles,
    Reset,
    Misc,
};

pub fn executeWizardFun(w: WizardFun) void {
    switch (w) {
        //F1 => {
        //  if (state.player.coord.z != 0) {
        //      const l = state.player.coord.z - 1;
        //      const r = rng.chooseUnweighted(mapgen.Room, state.rooms[l].items);
        //      const c = r.rect.randomCoord();
        //      _ = state.player.teleportTo(c, null, false, false);
        //      action_taken = true;
        //  }
        //},
        //F2 => {
        //  if (state.player.coord.z < (LEVELS - 1)) {
        //      const l = state.player.coord.z + 1;
        //      const r = rng.chooseUnweighted(mapgen.Room, state.rooms[l].items);
        //      const c = r.rect.randomCoord();
        //      _ = state.player.teleportTo(c, null, false, false);
        //      action_taken = true;
        //  }
        //},
        .RotateFaction => {
            state.player.faction = switch (state.player.faction) {
                .Player => .Necromancer,
                .Necromancer => .CaveGoblins,
                .CaveGoblins => .Night,
                .Night => .Player,
                .Vermin, .Holy, .Revgenunkim => unreachable,
            };
            state.message(.Info, "[wizard] new faction: {}", .{state.player.faction});
        },
        .Vision => {
            wiz_lidless_eye = !wiz_lidless_eye;
        },
        .Reset => {
            state.player.HP = state.player.max_HP;
            state.player.MP = state.player.max_MP;
        },
        .Up => {
            const stairlocs = &state.dungeon.stairs[state.player.coord.z];
            if (stairlocs.len == 0)
                return;
            var closest_floor_z: usize = 0;
            var closest_floor_stair = Coord.new2(6, 6, 6);
            for (stairlocs.constSlice()) |stairloc| {
                const stair = state.dungeon.at(stairloc).surface.?.Stair;
                if (stair.stairtype == .Up and stair.stairtype.Up > closest_floor_z) {
                    closest_floor_z = stair.stairtype.Up;
                    closest_floor_stair = stairloc;
                }
            }
            _ = state.player.teleportTo(closest_floor_stair, null, true, false);
        },
        .Misc => {
            //state.player.innate_resists.rElec += 25;
            //state.player.addStatus(.Drunk, 0, .{ .Tmp = 20 });
            state.message(.Info, "Lorem ipsum, dolor sit amet. Lorem ipsum, dolor sit amet.. Lorem ipsum, dolor sit amet. {}", .{rng.int(usize)});
            // _ = ui.drawYesNoPrompt("foo, bar, baz. Lorem ipsum, dolor sit amet. Dolem Lipsum, solor ait smet. Iorem Aipsum, lolor dit asset.", .{});
            //ui.labels.addFor(state.player, "foo bar baz", .{});
            // state.player.addStatus(.Corruption, 0, .{ .Tmp = 5 });
            // state.player.addStatus(.RingTeleportation, 0, .{ .Tmp = 5 });
            // state.player.addStatus(.RingElectrocution, 0, .{ .Tmp = 5 });
            // state.player.addStatus(.RingConjuration, 0, .{ .Tmp = 2 });
            // state.night_rep[@intFromEnum(state.player.faction)] += 10;
            // state.player.HP = 0;
            // for (state.player_conj_augments) |aug, i| {
            //     if (!aug.received) {
            //         state.player_conj_augments[i].received = true;
            //         state.message(.Info, "[$oConjuration augment$.] {s}", .{state.player_conj_augments[i].a.description()});
            //         break;
            //     }
            // }
            // _ = ui.chooseCell(.{
            //     .require_seen = true,
            //     .targeter = ui.ChooseCellOpts.Targeter{
            //         .Gas = .{ .gas = gas.Dust.id },
            //     },
            // }) orelse return false;
            // state.player.HP = 1;
            // const cell = ui.chooseCell(.{}) orelse break :blk false;
            // state.dungeon.at(cell).mob.?.HP = 1;
            // @import("combat.zig").throwMob(null, state.player, .North, 7);
            // const gthreat = alert.getThreat(.General);
            // state.message(.Info, "G: {}, deadly: {}, active: {}, last: {}", .{
            //     gthreat.level, gthreat.deadly, gthreat.is_active, gthreat.last_incident,
            // });
            // const uthreat = alert.getThreat(.Unknown);
            // state.message(.Info, "U: {}, deadly: {}, active: {}, last: {}", .{
            //     uthreat.level, uthreat.deadly, uthreat.is_active, uthreat.last_incident,
            // });
            // const pthreat = alert.getThreat(.{ .Specific = state.player });
            // state.message(.Info, "P: {}, deadly: {}, active: {}, last: {}", .{
            //     pthreat.level, pthreat.deadly, pthreat.is_active, pthreat.last_incident,
            // });
            // while (true)
            //     switch (display.waitForEvent(null) catch err.wat()) {
            //         .Quit => break,
            //         .Click => |b| {
            //             std.log.info("event: x: {}, y: {}", .{ b.x, b.y });
            //             const wide = display.getCell(b.x, b.y).fl.wide;
            //             display.setCell(b.x, b.y, .{ .ch = ' ', .bg = 0xffffff, .fl = .{ .wide = wide } });
            //             display.present();
            //         },
            //         else => {},
            //     };
            // ui.hud_win.deinit();
            // ui.hud_win.init();
            // ui.map_win.drawTextLinef("This is a test.", .{}, .{});
            // serializer.serializeWorld() catch |e| {
            //     err.bug("Ser failed ({})", .{e});
            // };
            // serializer.deserializeWorld() catch |e| {
            //     err.bug("Deser failed ({})", .{e});
            // };
            // alert.queueThreatResponse(.{ .Assault = .{
            //     .waves = 3,
            //     .target = state.player,
            // } });

            // mapgen.initLevel(5);
            // const c = for (&DIRECTIONS) |d| {
            //     if (state.dungeon.entries[5].move(d, state.mapgeometry)) |n|
            //         if (state.is_walkable(n, .{ .right_now = true }))
            //             break n;
            // } else unreachable;
            // _ = state.player.teleportTo(c, null, false, false);
            //@panic("nooooooooooooo");
        },
        .Particles => {
            _ = janet.loadFile("scripts/particles.janet", state.alloc) catch return;
            const target = ui.chooseCell(.{}) orelse return;
            ui.Animation.apply(.{ .Particle = .{ .name = "test", .coord = state.player.coord, .target = .{ .C = target } } });
        },
        .Teleport => {
            const chosen = ui.chooseCell(.{}) orelse return;
            _ = state.player.teleportTo(chosen, null, true, false);
        },
    }
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
        if (item == .Prop and item.Prop.isFluff()) {
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
    for (state.player.fov, 0..) |row, y| for (row, 0..) |_, x| {
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
                        //S._addToAnnouncements(SBuf.init(m.name), &announcements),
                        ui.labels.addAt(fc, m.name, .{ .color = colors.LIGHT_STEEL_BLUE, .last_for = 5 }),
                    .Stair => |s| {
                        const color = if (s.locked) 0xff4400 else colors.GOLD;
                        switch (s.stairtype) {
                            .Up => |u| ui.labels.addAt(fc, state.levelinfo[u].name, .{ .color = color, .last_for = 5 }),
                            .Access => ui.labels.addAt(fc, "Main Exit", .{ .color = color, .last_for = 5 }),
                            .Down => {},
                        }
                    },
                    else => {},
                };
            }

            memorizeTile(fc, .Immediate);
        }
    };
}

pub fn tryRest() bool {
    if (state.player.hasStatus(.Pain)) {
        ui.drawAlert("You cannot rest while in pain!", .{});
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
        .Container => |c| if (c.items.len > 0) return rummageContainer(dest),
        else => {},
    };

    if (direction.is_cardinal() and state.player.isUnderStatus(.Disorient) != null) {
        ui.drawAlert("You cannot move or attack cardinally whilst disoriented!", .{});
        return false;
    }

    // Does the player want to stab or fight?
    if (state.dungeon.at(dest).mob) |mob| {
        if (state.player.isHostileTo(mob)) {
            if (!combat.isAttackStab(state.player, mob) and
                (!ai.isEnemyKnown(mob, state.player) and !mob.hasStatus(.Amnesia)))
            {
                if (!ui.drawYesNoPrompt("Really attack unaware enemy?", .{}))
                    return false;
            }
            state.player.fight(mob, .{});
            return true;
        }
    }

    // Does the player want to move into a surveilled location?
    if (!isPlayerSpotted() and enemiesCanSee(dest) and state.is_walkable(dest, .{ .mob = state.player })) {
        if (!ui.drawYesNoPrompt("Really move into an enemy's view?", .{}))
            return false;
    }

    if (!movementTriggersA(direction)) {
        movementTriggersB(direction);
        state.player.declareAction(Activity{ .Move = direction });
        return true;
    }

    const ret = state.player.moveInDirection(direction);
    movementTriggersB(direction);

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

pub fn movementTriggersA(direction: Direction) bool {
    if (state.player.hasStatus(.RingTeleportation)) {
        // Get last enemy in chain of enemies.
        var last_coord = state.player.coord;
        var mob_chain_count: usize = 0;
        while (true) {
            if (last_coord.move(direction, state.mapgeometry)) |coord| {
                last_coord = coord;
                if (utils.getHostileAt(state.player, coord)) |_| {
                    mob_chain_count += 1;
                } else |_| {
                    if (mob_chain_count > 0) {
                        break;
                    }
                }
            } else break;
        }

        spells.BOLT_BLINKBOLT.use(state.player, state.player.coord, last_coord, .{
            .MP_cost = 0,
            .spell = &spells.BOLT_BLINKBOLT,
            .power = math.clamp(mob_chain_count, 2, 5),
        });

        return false;
    }

    return true;
}

pub fn movementTriggersB(direction: Direction) void {
    if (state.player.hasStatus(.RingDamnation) and !direction.is_diagonal()) {
        const power = state.player.isUnderStatus(.RingDamnation).?.power;
        spells.SUPER_DAMNATION.use(
            state.player,
            state.player.coord,
            state.player.coord,
            .{ .MP_cost = 0, .no_message = true, .context_direction1 = direction, .free = true, .power = power },
        );
    }
    if (state.player.hasStatus(.RingElectrocution)) {
        const power = state.player.isUnderStatus(.RingElectrocution).?.power;

        var anim_buf = StackBuffer(Coord, 4).init(null);
        for (&DIAGONAL_DIRECTIONS) |d|
            if (state.player.coord.move(d, state.mapgeometry)) |c|
                anim_buf.append(c) catch err.wat();

        ui.Animation.blink(anim_buf.constSlice(), '*', ui.Animation.ELEC_LINE_FG, .{}).apply();

        for (&DIAGONAL_DIRECTIONS) |d|
            if (utils.getHostileInDirection(state.player, d)) |hostile| {
                hostile.takeDamage(.{
                    .amount = power,
                    .by_mob = state.player,
                    .kind = .Electric,
                }, .{ .noun = "Lightning" });
            } else |_| {};
        state.player.makeNoise(.Combat, .Loud);
    }
    if (state.player.hasStatus(.RingExcision)) {
        state.player.squad.?.trimMembers();
        assert(state.player.squad.?.members.len > 0);
        for (state.player.squad.?.members.constSlice()) |mob|
            if (mem.eql(u8, mob.id, "spec_sword")) {
                const target = utils.getFarthestWalkableCoord(direction, mob.coord, .{ .only_if_breaks_lof = true, .ignore_mobs = true });
                const weapon = state.player.inventory.equipmentConst(.Weapon).*;
                const damage = if (weapon) |w| combat.damageOfWeapon(state.player, w.Weapon, null).total * 3 else 1;
                spells.BOLT_SPINNING_SWORD.use(mob, mob.coord, target, .{ .MP_cost = 0, .free = true, .power = damage, .duration = damage });
            };
    }
    if (state.player.hasStatus(.RingConjuration)) {
        const target = utils.getFarthestWalkableCoord(direction, state.player.coord, .{ .only_if_breaks_lof = true });
        spells.BOLT_CONJURE.use(state.player, state.player.coord, target, .{ .MP_cost = 0, .free = true });
    }
}

pub fn rummageContainer(coord: Coord) bool {
    const container = state.dungeon.at(coord).surface.?.Container;

    assert(container.items.len > 0);

    ui.Animation.apply(.{
        .PopChar = .{ .coord = state.player.coord, .char = '?', .fg = colors.GOLD, .delay = 125 },
    });

    var found_goodies = false;
    while (container.items.pop()) |item| {
        if (item.isUseful())
            found_goodies = true;

        if (state.nextAvailableSpaceForItem(coord, state.alloc)) |spot| {
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
        .Shoe, .Weapon, .Head, .Armor, .Cloak, .Aux => {
            const slot = Mob.Inventory.EquSlot.slotFor(item);
            if (state.player.inventory.equipment(slot).*) |old_item| {
                if (slot == .Weapon and old_item.Weapon.is_cursed) {
                    ui.drawAlert("You can't bring yourself to drop the {s}.", .{old_item.Weapon.name});
                    return false;
                }
                state.player.dequipItem(slot, state.player.coord);
                state.message(.Inventory, "You drop the {l}.", .{old_item});
                state.player.declareAction(.Drop);
            }

            state.player.equipItem(slot, item);
            state.message(.Inventory, "Equipped a {l}.", .{item});
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
                        state.player.inventory.equipment(.Ring5).*.?.Ring.name,
                        state.player.inventory.equipment(.Ring6).*.?.Ring.name,
                    },
                ) orelse return false;
                empty_slot = Inventory.RING_SLOTS[index];

                const old_ring = state.player.inventory.equipment(empty_slot.?).*.?;
                state.player.dequipItem(empty_slot.?, state.player.coord);
                state.message(.Inventory, "You drop the {l}.", .{old_ring});
                state.player.declareAction(.Drop);
            }

            state.player.equipItem(empty_slot.?, item);
            state.player.declareAction(.Use);
            state.message(.Inventory, "Equipped the {l}.", .{item});
        },
        else => unreachable,
    }
    return true;
}

pub fn grabItem() bool {
    // if (state.dungeon.at(state.player.coord).surface) |surface| {
    //     switch (surface) {
    //         .Container => |_| return rummageContainer(state.player.coord),
    //         else => {},
    //     }
    // }

    const item = state.dungeon.itemsAt(state.player.coord).last() orelse {
        ui.drawAlert("There's nothing here.", .{});
        return false;
    };
    const item_index = state.dungeon.itemsAt(state.player.coord).len - 1;

    switch (item) {
        .Shoe, .Ring, .Armor, .Cloak, .Head, .Aux, .Weapon => {
            if (equipItem(item)) {
                // Delete item on the ground
                _ = state.dungeon.itemsAt(state.player.coord).orderedRemove(item_index) catch err.wat();
                return true;
            } else {
                return false;
            }
        },
        else => {
            if (state.player.inventory.pack.isFull()) {
                ui.drawAlert("Your pack is full!", .{});
                return false;
            }

            state.player.inventory.pack.append(item) catch err.wat();
            state.player.declareAction(.Grab);
            state.message(.Inventory, "Acquired: {l}", .{
                state.player.inventory.pack.last().?,
            });

            // Delete item on the ground
            _ = state.dungeon.itemsAt(state.player.coord).pop() catch err.wat();
        },
    }

    ui.Animation.apply(.{ .PopChar = .{ .coord = state.player.coord, .char = '/' } });

    return true;
}

pub fn throwItem(index: usize) bool {
    assert(state.player.inventory.pack.len > index);

    const item = state.player.inventory.pack.slice()[index];

    if (item != .Projectile and !(item == .Consumable and item.Consumable.throwable)) {
        ui.drawAlert("You can't throw that.", .{});
        return false;
    }

    if (item == .Consumable and item.Consumable.hated_by_nc and hasAlignedNC()) {
        ui.drawAlert("Using that would anger the Night!", .{});
        return false;
    }

    //     var gas_targeter = ui.ChooseCellOpts.Targeter{
    //         .Duo = [2]*const ui.ChooseCellOpts.Targeter{
    //             &.{ .Gas = .{ .gas = 0 } },
    //             &.{ .Trajectory = .{} },
    //         },
    //     };

    const targeter: ui.ChooseCellOpts.Targeter = switch (item) {
        .Projectile => .{ .Trajectory = .{} },
        .Consumable => |c| b: {
            const gas_effect = for (c.effects) |e| {
                if (e == .Gas) break e.Gas;
            } else null;

            if (gas_effect) |_| {
                // gas_targeter.Duo[0].Gas.gas = g;
                // break :b gas_targeter;
                break :b ui.ChooseCellOpts.Targeter{
                    .Duo = [2]*const ui.ChooseCellOpts.Targeter{
                        &.{ .Gas = .{ .gas = 0 } },
                        &.{ .Trajectory = .{} },
                    },
                };
            } else {
                break :b ui.ChooseCellOpts.Targeter{ .Trajectory = .{} };
            }
        },
        else => err.wat(),
    };

    const dest = ui.chooseCell(.{ .require_seen = true, .targeter = targeter }) orelse return false;

    state.player.throwItem(&item, dest, state.alloc);
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
                ui.drawAlert("You can't activate that.", .{});
                return false;
            },
            else => {
                ui.drawAlert("There's nothing here to activate.", .{});
                return false;
            },
        }
    } else {
        ui.drawAlert("There's nothing here to activate.", .{});
        return false;
    }

    const interaction = &mach.player_interact.?;
    mach.evoke(state.player, interaction) catch |e| {
        switch (e) {
            error.UsedMax => ui.drawAlert("You can't use the {s} again.", .{mach.name}),
            error.NoEffect => if (interaction.no_effect_msg) |msg| {
                ui.drawAlert("{s}", .{msg});
            },
        }
        return false;
    };

    state.player.declareAction(.Interact);
    if (interaction.success_msg) |msg|
        state.message(.Info, "{s}", .{msg});

    if (mach.player_interact.?.max_use != 0) {
        const left = mach.player_interact.?.max_use - mach.player_interact.?.used;
        if (left == 0) {
            if (interaction.expended_msg) |msg|
                state.message(.Unimportant, "{s}", .{msg});
        } else {
            state.message(.Info, "You can use this {s} {} more times.", .{ mach.name, left });
        }
    }

    return true;
}

pub fn useItem(index: usize) bool {
    assert(state.player.inventory.pack.len > index);

    const item = state.player.inventory.pack.slice()[index];
    switch (item) {
        .Shoe, .Ring, .Armor, .Cloak, .Head, .Aux => return equipItem(item),
        .Weapon => |w| {
            if (w.is_hated_by_nc) {
                ui.drawAlert("You can't equip that (hated by the Night)!", .{});
                return false;
            }

            return equipItem(item);
        },
        .Consumable => |p| {
            if (p.hated_by_nc and hasAlignedNC()) {
                ui.drawAlert("You can't use that item (hated by the Night)!", .{});
                return false;
            }

            if (p.is_potion and state.player.isUnderStatus(.Nausea) != null) {
                ui.drawAlert("You can't drink potions while nauseated!", .{});
                return false;
            }

            state.player.useConsumable(p, true) catch |e| switch (e) {
                error.BadPosition => {
                    ui.drawAlert("You can't use this kit here.", .{});
                    return false;
                },
            };

            scores.recordTaggedUsize(.ItemsUsed, .{ .I = item }, 1);
        },
        .Vial => |_| {
            state.message(.Info, "You angrily remind kiedtl for the 2048th time that vials are still in the game", .{});
            return false;
        },
        .Key => {
            ui.drawAlert("You stare at the key, wondering which staircase it unlocks.", .{});
            return false;
        },
        .Projectile, .Boulder => {
            ui.drawAlert("You want to *eat* that?", .{});
            return false;
        },
        .Prop => |p| {
            state.message(.Info, "You admire the {s}.", .{p.name});
            return false;
        },
        .Evocable => |v| {
            v.evoke(state.player) catch |e| {
                switch (e) {
                    error.NoCharges => ui.drawAlert("You can't use the {s} anymore!", .{v.name}),
                    error.HatedByNight => ui.drawAlert("Using that would anger the Night!", .{}),
                    error.BadPosition => ui.drawAlert("Invalid target position.", .{}),
                    error.NeedSpaceNearPlayer => ui.drawAlert("There needs to be a free spot adjacent you.", .{}),
                }
                return false;
            };

            scores.recordTaggedUsize(.ItemsUsed, .{ .I = item }, 1);
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

pub fn isPlayerMartial() bool {
    const martial = state.player.stat(.Martial);
    const weapon = state.player.inventory.equipment(.Weapon).*;
    return martial > 0 and weapon != null and weapon.?.Weapon.martial;
}

// Returns ring slot number
pub fn isAuxUpgradable(index: usize) ?Inventory.EquSlot {
    const slot: Inventory.EquSlot = @enumFromInt(index);
    const item = state.player.inventory.equipment(slot).*.?;

    if (item == .Aux)
        if (item.Aux.ring_upgrade_name) |ring_name|
            if (for (&Inventory.RING_SLOTS) |ring_slot| {
                const ind = getRingIndexBySlot(ring_slot);
                const ring = getRingByIndex(ind) orelse continue;
                if (mem.eql(u8, ring.name, ring_name))
                    break ring_slot;
            } else null) |ring_slot|
                return ring_slot;
    return null;
}

pub fn upgradeAux(index: usize, ring_slot: Inventory.EquSlot) void {
    const slot: Inventory.EquSlot = @enumFromInt(index);
    const i = state.player.inventory.equipment(slot).*.?;
    assert(i == .Aux and i.Aux.ring_upgrade_name != null);
    state.player.dequipItem(slot, null);
    state.player.dequipItem(ring_slot, null);

    const dst_id = i.Aux.ring_upgrade_dest.?;
    const dst_template = items.findItemById(dst_id) orelse err.bug("Upgrade doesn't exist", .{});
    const dst = items.createItemFromTemplate(dst_template);

    state.message(.Info, "{s}", .{i.Aux.ring_upgrade_mesg.?});
    state.player.equipItem(slot, dst);
}

pub const UserActionResult = union(enum) {
    Success,
    Failure: []const u8,
};

// if is_inventory, index=pack index; otherwise, equipment id
//
pub fn dropItem(index: usize, is_inventory: bool) UserActionResult {
    if (is_inventory)
        assert(state.player.inventory.pack.len > index);

    if (!is_inventory and @as(Inventory.EquSlot, @enumFromInt(index)) == .Shoe)
        return .{ .Failure = "Sorry, you need shoes." };

    if (!is_inventory and @as(Inventory.EquSlot, @enumFromInt(index)) == .Weapon and
        state.player.inventory.equipment(.Weapon).*.?.Weapon.is_cursed)
    {
        return .{ .Failure = "You cannot bring yourself to let go of this item." };
    }

    if (state.nextAvailableSpaceForItem(state.player.coord, state.alloc)) |coord| {
        const item = if (is_inventory) b: {
            const i = state.player.removeItem(index) catch err.wat();
            const dropped = state.player.dropItem(i, coord);
            assert(dropped);
            break :b i;
        } else b: {
            const slot: Inventory.EquSlot = @enumFromInt(index);
            const i = state.player.inventory.equipment(slot).*.?;
            state.player.dequipItem(slot, coord);
            break :b i;
        };

        state.message(.Inventory, "Dropped: {h}.", .{item});
        return .Success;
    } else {
        return .{ .Failure = "No nearby space to drop the item." };
    }
}

pub fn memorizeTile(fc: Coord, mtype: state.MemoryTile.Type) void {
    const memt = state.MemoryTile{ .tile = Tile.displayAs(fc, true, false), .type = mtype };
    state.memory.put(fc, memt) catch err.wat();
}

pub fn enemiesCanSee(coord: Coord) bool {
    const moblist = state.createMobList(false, true, state.player.coord.z, state.alloc);
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

    const moblist = state.createMobList(false, true, state.player.coord.z, state.alloc);
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

pub const RingError = enum {
    NotEnoughMP,
    HatedByNight,
    CannotBeCorrupted,
    CannotBeInPain,
    CannotBeGlowing,
    CannotBeUnholy,

    pub fn text1(self: @This()) []const u8 {
        return switch (self) {
            .NotEnoughMP => "low mana",
            .HatedByNight => "hated by the Night",
            // TODO: compress the text here with "musn't" ?
            .CannotBeCorrupted => "must be uncorrupted",
            .CannotBeInPain => "must not be in pain",
            .CannotBeGlowing => "must not be glowing",
            .CannotBeUnholy => "must not be unclean",
        };
    }
};

pub fn checkRing(index: usize) ?RingError {
    const ring = getRingByIndex(index).?;
    if (ring.required_MP > state.player.MP) {
        return .NotEnoughMP;
    }
    if (ring.hated_by_nc and hasAlignedNC()) {
        return .HatedByNight;
    }
    if (ring.requires_uncorrupt and state.player.hasStatus(.Corruption)) {
        return .CannotBeCorrupted;
    }
    if (ring.requires_nounholy and state.player.resistance(.rHoly) < 0) {
        return .CannotBeUnholy;
    }
    if (ring.requires_nopain and state.player.hasStatus(.Pain)) {
        return .CannotBeInPain;
    }
    if (ring.requires_noglow and state.player.hasStatus(.Corona)) {
        return .CannotBeGlowing;
    }
    return null;
}

pub fn beginUsingRing(index: usize) void {
    const ring = getRingByIndex(index).?;

    if (checkRing(index)) |e| {
        state.message(.Info, "[$o{s}$.] You cannot use this ring ({s}).", .{ ring.name, e.text1() });
        return;
    }

    if (state.player.MP < ring.required_MP) {
        err.wat();
    }

    if (ring.effect()) {
        if (state.player.hasStatus(.Sceptre) and rng.onein(10)) {
            // No mana used
            state.message(.SpellCast, "The Sceptre feels unexpectedly heavy.", .{});
        } else {
            state.player.MP -= ring.required_MP;
        }
    }

    scores.recordTaggedUsize(.RingsUsed, .{ .s = ring.name }, 1);
}

pub fn getRingIndexBySlot(slot: Mob.Inventory.EquSlot) usize {
    return for (Mob.Inventory.RING_SLOTS, 0..) |item, i| {
        if (item == slot) break i + state.default_patterns.len;
    } else err.bug("Tried to get ring index from non-ring slot", .{});
}

pub fn getRingByIndex(index: usize) ?*Ring {
    if (index >= state.default_patterns.len) {
        const rel_index = index - state.default_patterns.len;
        if (rel_index >= Inventory.RING_SLOTS.len) return null;
        return if (state.player.inventory.equipment(Inventory.RING_SLOTS[rel_index]).*) |r| r.Ring else null;
    } else {
        return &state.default_patterns[index];
    }
}

pub fn calculateDrainableMana(total: usize) usize {
    const S = struct {
        pub fn _helper(a: usize, pot: usize) usize {
            const pot1 = @min(pot, 100);
            const pot2 = pot -| 100;
            var n: usize = 0;
            var ctr = a;
            while (ctr > 0) : (ctr -= 1) {
                if (rng.percent(pot1)) n += 1;
                if (rng.percent(pot2)) n += 1;
            }
            return n;
        }
    };

    const pot: usize = @intCast(state.player.stat(.Potential));
    return (S._helper(total, pot) + S._helper(total, pot) + S._helper(total, pot)) / 3;
}

// Note, lots of duplicated code here and in Shrine draining code
//
pub fn drainMob(mob: *Mob) void {
    if (!mob.is_drained and mob.max_drainable_MP > 0) {
        const pot: usize = @intCast(state.player.stat(.Potential));
        const amount = calculateDrainableMana(mob.max_drainable_MP);

        state.player.MP = @min(state.player.max_MP, state.player.MP + amount);
        mob.is_drained = true;
        mob.MP = 0;
        mob.max_MP = 0;

        state.message(.Drain, "You absorbed $o{}$. / $g{}$. mana ($o{}% potential$.).", .{ amount, mob.max_drainable_MP, pot });

        if (mob.is_dead) {
            state.message(.Drain, "You drained the corpse of the Necromancer's power.", .{});
        } else {
            state.message(.Drain, "You drained {} of the Necromancer's power.", .{mob});
        }
    }
}

pub fn drainRing(ring: *Ring) void {
    if (!ring.drained) {
        const max_drainable_MP = ring.required_MP * 3;
        const pot: usize = @intCast(state.player.stat(.Potential));
        const amount = calculateDrainableMana(max_drainable_MP);

        state.player.MP = @min(state.player.max_MP, state.player.MP + amount);
        ring.drained = true;

        state.message(.Drain, "You absorbed $o{}$. / $g{}$. mana ($o{}% potential$.).", .{ amount, max_drainable_MP, pot });
        state.message(.Drain, "You drained some of the ring's stored power.", .{});
    }
}

pub fn formatActivityList(activities: []const Activity, writer: anytype) void {
    for (activities, 0..) |activity, i| {
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
