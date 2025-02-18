// Old machines, kept here for my future reference.
//
// Mostly outdated either because their relevant mechanics were removed, they
// didn't fit gameplay, they were hard to balance, or a change in lore made
// them unneeded/contradictory.

// pub const WaterBarrel = Machine{
//     .id = "barrel_water",
//     .name = "barrel of water",
//     .announce = true,
//     .powered_tile = 'Θ',
//     .unpowered_tile = 'Θ',
//     .powered_fg = 0x00d7ff,
//     .unpowered_fg = 0x00d7ff,
//     .powered_walkable = false,
//     .unpowered_walkable = false,
//     .evoke_confirm = "Break open the barrel of water?",
//     .on_power = struct {
//         fn f(machine: *Machine) void {
//             assert(machine.last_interaction.? == state.player);

//             var dijk = dijkstra.Dijkstra.init(
//                 machine.coord,
//                 state.mapgeometry,
//                 3,
//                 state.is_walkable,
//                 .{ .ignore_mobs = true, .right_now = true },
//                 state.gpa.allocator(),
//             );
//             defer dijk.deinit();
//             while (dijk.next()) |item|
//                 if (machine.coord.distanceManhattan(item) < 4 or
//                     rng.percent(@as(usize, 20)))
//                 {
//                     state.dungeon.at(item).terrain = &ShallowWaterTerrain;
//                 };

//             state.message(.Info, "You break open the water barrel!", .{});

//             machine.disabled = true;
//             state.dungeon.at(machine.coord).surface = null;
//         }
//     }.f,
// };

pub const ElevatorMotor = Machine{
    .id = "elevator_motor",
    .name = "motor",

    .powered_tile = '⊛',
    .unpowered_tile = '⊚',
    .powered_sprite = .S_G_M_Machine,
    .unpowered_sprite = .S_G_M_Machine,

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerElevatorMotor,
};

pub const Extractor = Machine{
    .id = "extractor",
    .name = "machine",

    .powered_tile = '⊟',
    .unpowered_tile = '⊞',
    .powered_sprite = .S_G_M_Machine,
    .unpowered_sprite = .S_G_M_Machine,

    .power_drain = 0,
    .power = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerExtractor,
};

pub const BlastFurnace = Machine{
    .id = "blast_furnace",
    .name = "blast furnace",

    .powered_tile = '≡',
    .unpowered_tile = '≡',
    .powered_sprite = .S_G_M_Machine,
    .unpowered_sprite = .S_G_M_Machine,

    .power_drain = 0,
    .power = 0,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_luminescence = 100,
    .unpowered_luminescence = 0,
    .dims = true,

    .on_power = powerBlastFurnace,
};

pub const StalkerStation = Machine{
    .id = "stalker_station",
    .name = "stalker station",
    .announce = true,
    .powered_tile = 'S',
    .unpowered_tile = 'x',
    .powered_fg = 0x0,
    .unpowered_fg = 0x0,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .bg = 0x90b7a3,
    .power_drain = 0,
    .power = 100,
    .detect_with_elec = true,
    .detect_with_heat = true,
    .on_power = powerNone,
    .evoke_confirm = "Really use the stalkers for your own devious purposes?",
    .player_interact = .{
        .name = "use",
        .success_msg = "You loose the stalkers.",
        .no_effect_msg = null,
        .max_use = 1,
        .func = struct {
            fn f(_: *Machine, by: *Mob) bool {
                assert(by == state.player);

                const STALKER_MAX = 3;

                const Action = union(enum) {
                    SeekStairs,
                    Guard: Coord,
                };

                const choices = [_][]const u8{
                    "Seek nearest stairs and guard",
                    "Guard an area",
                };
                const CHOICE_SEEK = 0;
                const CHOICE_MOVE = 1;

                const chosen_action_i = ui.drawChoicePrompt("Order the stalkers to do what?", .{}, &choices) orelse return false;
                const action: Action = switch (chosen_action_i) {
                    CHOICE_SEEK => .SeekStairs,
                    CHOICE_MOVE => .{ .Guard = ui.chooseCell(.{ .require_seen = true }) orelse return false },
                    else => unreachable,
                };

                const coord = switch (action) {
                    .SeekStairs => state.dungeon.stairs[state.player.coord.z].constSlice()[0],
                    .Guard => |g| g,
                };

                var spawned_ctr: usize = 0;
                var first_stalker: ?*Mob = null;
                for (&DIRECTIONS) |d| if (state.player.coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.is_walkable(neighbor, .{ .right_now = true })) {
                        const stalker = mobs.placeMob(state.gpa.allocator(), &mobs.StalkerTemplate, neighbor, .{});

                        //state.player.squad.?.members.append(stalker) catch break;
                        //stalker.squad = state.player.squad;
                        if (first_stalker) |stalker_leader| {
                            stalker.squad = stalker_leader.squad;
                        } else {
                            stalker.squad = Squad.allocNew();
                            stalker.squad.?.leader = stalker;
                            first_stalker = stalker;
                        }

                        state.player.linked_fovs.append(stalker) catch {};
                        stalker.faction = .Player;

                        // Hack to keep stalkers not-hostile to goblin prisoners
                        stalker.prisoner_status = types.Prisoner{ .of = .Necromancer };

                        stalker.ai.work_area.items[0] = coord;

                        stalker.cancelStatus(.Sleeping);
                    }

                    spawned_ctr += 1;
                    if (spawned_ctr == STALKER_MAX) {
                        break;
                    }
                };

                if (spawned_ctr == 0) {
                    ui.drawAlertThenLog("No empty tiles near you to release stalkers.", .{});
                    return false;
                }

                return true;
            }
        }.f,
    },
};

pub const CapacitorArray = Machine{
    .id = "capacitor_array",
    .name = "capacitor array",
    .announce = true,
    .powered_tile = 'C',
    .unpowered_tile = 'x',
    .powered_fg = 0x10243e,
    .unpowered_fg = 0x10243e,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .bg = 0xb0c4de,
    .power_drain = 0,
    .power = 100,
    .detect_with_elec = true,
    .on_power = powerNone,
    .flammability = 20,
    .evoke_confirm = "Really discharge the capacitor array?",
    .player_interact = .{
        .name = "discharge",
        .success_msg = "You discharge the capacitor.",
        .no_effect_msg = null,
        .max_use = 1,
        .func = struct {
            fn f(_: *Machine, by: *Mob) bool {
                assert(by == state.player);

                if (state.player.resistance(.rElec) <= 0) {
                    ui.drawAlertThenLog("Cannot discharge without rElec.", .{});
                    return false;
                }

                var affected = StackBuffer(*Mob, 128).init(null);

                var gen = Generator(Rect.rectIter).init(state.mapRect(by.coord.z));
                while (gen.next()) |coord| if (state.player.cansee(coord)) {
                    if (utils.getHostileAt(state.player, coord)) |hostile| {
                        if (hostile.resistance(.rElec) <= 0) {
                            hostile.takeDamage(.{
                                .amount = 27,
                                .by_mob = state.player,
                                .blood = false,
                                .source = .RangedAttack,
                                .kind = .Electric,
                            }, .{ .basic = true });
                            affected.append(hostile) catch err.wat();
                        }
                    } else |_| {}
                };

                //                 var y: usize = 0;
                //                 while (y < HEIGHT) : (y += 1) {
                //                     var x: usize = 0;
                //                     while (x < WIDTH) : (x += 1) {
                //                         const coord = Coord.new2(by.coord.z, x, y);
                //                         if (state.player.cansee(coord)) {
                //                             if (utils.getHostileAt(state.player, coord)) |hostile| {
                //                                 if (hostile.resistance(.rElec) <= 0) {
                //                                     hostile.takeDamage(.{
                //                                         .amount = 27,
                //                                         .by_mob = state.player,
                //                                         .blood = false,
                //                                         .source = .RangedAttack,
                //                                         .kind = .Electric,
                //                                     }, .{ .basic = true });
                //                                     affected.append(coord) catch err.wat();
                //                                 }
                //                             } else |_| {}
                //                         }
                //                     }
                //                 }

                if (affected.len == 0) {
                    ui.drawAlertThenLog("No electricity-vulnerable monsters in sight.", .{});
                    return false;
                } else {
                    state.player.makeNoise(.Explosion, .Loudest);
                    ui.Animation.blinkMob(affected.constSlice(), '*', ui.Animation.ELEC_LINE_FG, .{});
                }

                return true;
            }
        }.f,
    },
};

pub const RechargingStation = Machine{
    .id = "recharging_station",
    .name = "recharging station",
    .announce = true,
    .powered_tile = 'R',
    .unpowered_tile = 'x',
    .powered_fg = 0x000000,
    .unpowered_fg = 0x000000,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .detect_with_elec = true,
    .bg = 0x90a3b7,
    .power_drain = 0,
    .power = 100,
    .on_power = powerNone,
    .flammability = 20,
    .player_interact = .{
        .name = "recharge",
        .success_msg = "All evocables recharged.",
        .no_effect_msg = "No evocables to recharge!",
        .max_use = 1,
        .func = interact1RechargingStation,
    },
};
