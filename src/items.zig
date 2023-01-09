const std = @import("std");
const math = std.math;
const enums = std.enums;
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const ai = @import("ai.zig");
const colors = @import("colors.zig");
const combat = @import("combat.zig");
const dijkstra = @import("dijkstra.zig");
const err = @import("err.zig");
const explosions = @import("explosions.zig");
const fire = @import("fire.zig");
const fov = @import("fov.zig");
const gas = @import("gas.zig");
const ui = @import("ui.zig");
const rng = @import("rng.zig");
const mobs = @import("mobs.zig");
const state = @import("state.zig");
const sound = @import("sound.zig");
const surfaces = @import("surfaces.zig");
const types = @import("types.zig");
const ringbuffer = @import("ringbuffer.zig");
const player = @import("player.zig");
const spells = @import("spells.zig");
const utils = @import("utils.zig");

const Activity = types.Activity;
const Coord = types.Coord;
const Item = types.Item;
const Ring = types.Ring;
const DamageStr = types.DamageStr;
const Weapon = types.Weapon;
const Resistance = types.Resistance;
const StatusDataInfo = types.StatusDataInfo;
const Armor = types.Armor;
const SurfaceItem = types.SurfaceItem;
const Mob = types.Mob;
const Damage = types.Damage;
const Stat = types.Stat;
const Spatter = types.Spatter;
const Rect = types.Rect;
const Status = types.Status;
const Machine = types.Machine;
const Direction = types.Direction;

const DIRECTIONS = types.DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const LinkedList = @import("list.zig").LinkedList;
const StackBuffer = @import("buffer.zig").StackBuffer;

// Items to be dropped into rooms for the player's use.
//
pub const ItemTemplate = struct {
    w: usize,
    i: TemplateItem,

    pub const TemplateItem = union(enum) {
        W: Weapon,
        A: Armor,
        C: *const Cloak,
        X: *const Aux,
        P: *const Consumable,
        c: *const Consumable,
        E: Evocable,
        List: []const ItemTemplate,

        pub fn id(self: TemplateItem) ![]const u8 {
            return switch (self) {
                .W => |i| i.id,
                .A => |i| i.id,
                .C => |i| i.id,
                .X => |i| i.id,
                .P => |i| i.id,
                .c => |i| i.id,
                .E => |i| i.id,
                .List => error.CannotGetListID,
            };
        }
    };
    pub const Type = meta.Tag(TemplateItem);
};
pub const RARE_ITEM_DROPS = [_]ItemTemplate{
    // Dilute this list by adding a few more common weapon
    .{ .w = 100, .i = .{ .W = GlaiveWeapon } },
    .{ .w = 100, .i = .{ .W = SwordWeapon } },
    // Rare weapons
    .{ .w = 50, .i = .{ .W = MartialSwordWeapon } },
    // Bone weapons
    .{ .w = 1, .i = .{ .W = BoneSwordWeapon } },
    .{ .w = 1, .i = .{ .W = BoneDaggerWeapon } },
    .{ .w = 1, .i = .{ .W = BoneStilettoWeapon } },
    .{ .w = 1, .i = .{ .W = BoneMaceWeapon } },
    .{ .w = 1, .i = .{ .W = BoneGreatMaceWeapon } },
    .{ .w = 1, .i = .{ .W = BoneHalberdWeapon } },
    // Copper weapons
    .{ .w = 1, .i = .{ .W = CopperSwordWeapon } },
    .{ .w = 1, .i = .{ .W = CopperRapierWeapon } },
};
pub const ITEM_DROPS = [_]ItemTemplate{
    .{ .w = 1, .i = .{ .List = &RARE_ITEM_DROPS } },
    // Weapons
    .{ .w = 30, .i = .{ .W = SwordWeapon } },
    .{ .w = 30, .i = .{ .W = DaggerWeapon } },
    .{ .w = 20, .i = .{ .W = StilettoWeapon } },
    .{ .w = 25, .i = .{ .W = RapierWeapon } },
    //.{ .w = 025, .i = .{ .W = QuarterstaffWeapon } },
    //.{ .w = 030, .i = .{ .W = MaceWeapon } },
    .{ .w = 25, .i = .{ .W = GreatMaceWeapon } },
    .{ .w = 30, .i = .{ .W = MorningstarWeapon } },
    .{ .w = 30, .i = .{ .W = HalberdWeapon } },
    .{ .w = 30, .i = .{ .W = GlaiveWeapon } },
    .{ .w = 25, .i = .{ .W = MonkSpadeWeapon } },
    .{ .w = 15, .i = .{ .W = WoldoWeapon } },
    // Armor
    .{ .w = 20, .i = .{ .A = GambesonArmor } },
    .{ .w = 10, .i = .{ .A = SpikedLeatherArmor } },
    .{ .w = 20, .i = .{ .A = HauberkArmor } },
    .{ .w = 20, .i = .{ .A = CuirassArmor } },
    // Aux items
    .{ .w = 20, .i = .{ .X = &WolframOrbAux } },
    .{ .w = 20, .i = .{ .X = &MinersMapAux } },
    .{ .w = 20, .i = .{ .X = &DetectHeatAux } },
    .{ .w = 20, .i = .{ .X = &DetectElecAux } },
    .{ .w = 10, .i = .{ .X = &DispelUndeadAux } },
    .{ .w = 10, .i = .{ .X = &BucklerAux } },
    .{ .w = 10, .i = .{ .X = &SpikedBucklerAux } },
    // Potions
    .{ .w = 190, .i = .{ .P = &DisorientPotion } },
    .{ .w = 190, .i = .{ .P = &DebilitatePotion } },
    .{ .w = 190, .i = .{ .P = &IntimidatePotion } },
    .{ .w = 160, .i = .{ .P = &DistractPotion } },
    .{ .w = 160, .i = .{ .P = &BlindPotion } },
    .{ .w = 160, .i = .{ .P = &GlowPotion } },
    .{ .w = 160, .i = .{ .P = &SmokePotion } },
    .{ .w = 160, .i = .{ .P = &ParalysisPotion } },
    .{ .w = 150, .i = .{ .P = &LeavenPotion } },
    .{ .w = 150, .i = .{ .P = &InvigoratePotion } },
    .{ .w = 150, .i = .{ .P = &FastPotion } },
    .{ .w = 150, .i = .{ .P = &IncineratePotion } },
    .{ .w = 120, .i = .{ .P = &RecuperatePotion } },
    .{ .w = 120, .i = .{ .P = &DecimatePotion } },
    // Consumables
    // .{ .w = 80, .i = .{ .c = &HotPokerConsumable } },
    // .{ .w = 90, .i = .{ .c = &CoalConsumable } },
    .{ .w = 1, .i = .{ .c = &CopperIngotConsumable } },
    // Kits
    .{ .w = 50, .i = .{ .c = &FireTrapKit } },
    .{ .w = 50, .i = .{ .c = &ShockTrapKit } },
    .{ .w = 40, .i = .{ .c = &SparklingTrapKit } },
    .{ .w = 40, .i = .{ .c = &EmberlingTrapKit } },
    .{ .w = 40, .i = .{ .c = &AirblastTrapKit } },
    .{ .w = 30, .i = .{ .c = &GlueTrapKit } },
    .{ .w = 10, .i = .{ .c = &MineKit } },
    .{ .w = 10, .i = .{ .c = &BigFireTrapKit } },
    // Evocables
    .{ .w = 30, .i = .{ .E = FlamethrowerEvoc } },
    .{ .w = 30, .i = .{ .E = EldritchLanternEvoc } },
    .{ .w = 30, .i = .{ .E = BrazierWandEvoc } },
    // Cloaks
    .{ .w = 20, .i = .{ .C = &SilCloak } },
    .{ .w = 20, .i = .{ .C = &FurCloak } },
    .{ .w = 20, .i = .{ .C = &VelvetCloak } },
    .{ .w = 10, .i = .{ .C = &ThornyCloak } },
};
pub const ALL_ITEMS = [_]ItemTemplate{
    .{ .w = 0, .i = .{ .List = &ITEM_DROPS } },
    .{ .w = 0, .i = .{ .E = SymbolEvoc } },
};

pub const RINGS = [_]Ring{
    LightningRing,
    CremationRing,
    DistractionRing,
    DamnationRing,
    TeleportationRing,
    ElectrificationRing,
    InsurrectionRing,
    MagnetizationRing,
    ExcisionRing,
    ConjurationRing,
};

pub const Rune = enum {
    Basalt, // Caverns
    Twisted, // Laboratory
    Golden, // Quarters

    pub const COUNT = 3;

    pub fn name(self: Rune) []const u8 {
        return switch (self) {
            .Basalt => "Basalt",
            .Twisted => "Twisted",
            .Golden => "Golden",
        };
    }
};

// Cloaks {{{
pub const Cloak = struct {
    id: []const u8,
    name: []const u8,
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
};

pub const SilCloak = Cloak{ .id = "cloak_silicon", .name = "silicon", .resists = .{ .rFire = 25 } };
pub const FurCloak = Cloak{ .id = "cloak_fur", .name = "fur", .resists = .{ .rElec = 25 } };
pub const VelvetCloak = Cloak{ .id = "cloak_velvet", .name = "velvet", .stats = .{ .Sneak = 2 } };
pub const ThornyCloak = Cloak{ .id = "cloak_thorny", .name = "thorns", .stats = .{ .Spikes = 1 } };
// }}}

// Aux items {{{
pub const Aux = struct {
    id: []const u8,
    name: []const u8,

    equip_effects: []const StatusDataInfo = &[_]StatusDataInfo{},
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
};

pub const WolframOrbAux = Aux{
    .id = "aux_wolfram_orb",
    .name = "Orb of Wolfram",

    .stats = .{ .Evade = -10, .Martial = -1 },
    .resists = .{ .rElec = 25 },
};

pub const MinersMapAux = Aux{
    .id = "aux_miners_map",
    .name = "miner's map",

    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .Echolocation, .duration = .Equ, .power = 3 },
    },
};

pub const DetectHeatAux = Aux{
    .id = "aux_detect_heat",
    .name = "Detect Heat",
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .DetectHeat, .duration = .Equ },
    },
};

pub const DetectElecAux = Aux{
    .id = "aux_detect_elec",
    .name = "Detect Electricity",
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .DetectElec, .duration = .Equ },
    },
};

pub const DispelUndeadAux = Aux{
    .id = "aux_dispel_undead",
    .name = "Dispel Undead",

    .stats = .{ .Willpower = 2 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .TormentUndead, .duration = .Equ },
    },
};

pub const BucklerAux = Aux{
    .id = "aux_buckler",
    .name = "buckler",

    .stats = .{ .Evade = 10 },
};

pub const SpikedBucklerAux = Aux{
    .id = "aux_buckler_spiked",
    .name = "spiked buckler",

    .stats = .{ .Spikes = 1, .Evade = 10 },
};
// }}}

// Projectiles {{{

pub const Projectile = struct {
    id: []const u8,
    name: []const u8,
    color: u32,
    damage: ?usize = null,
    effect: union(enum) {
        Status: StatusDataInfo,
    },
};

pub const NetProj = Projectile{
    .id = "net",
    .name = "net",
    .color = 0xffd700,
    .effect = .{
        .Status = .{
            .status = .Held,
            .duration = .{ .Tmp = 10 },
        },
    },
};

pub const JavelinProj = Projectile{
    .id = "javelin",
    .name = "javelin",
    .color = 0xffd7d7,
    .damage = 2,
    .effect = .{
        .Status = .{
            .status = .Disorient,
            .duration = .{ .Tmp = 3 },
        },
    },
};

// }}}

// Evocables {{{

pub const EvocableList = LinkedList(Evocable);
pub const Evocable = struct {
    // linked list stuff
    __next: ?*Evocable = null,
    __prev: ?*Evocable = null,

    id: []const u8,
    name: []const u8,
    tile_fg: u32,

    charges: usize = 0,
    max_charges: usize, // Zero for infinite charges

    // Whether to destroy the evocable when it's finished.
    delete_when_inert: bool = false,

    // Whether a recharging station should recharge it.
    //
    // Must be false if max_charges == 0.
    rechargable: bool = true,

    trigger_fn: fn (*Mob, *Evocable) EvokeError!void,

    // TODO: targeting functionality

    pub const EvokeError = error{ NoCharges, BadPosition };

    pub fn evoke(self: *Evocable, by: *Mob) EvokeError!void {
        if (self.max_charges == 0 or self.charges > 0) {
            self.trigger_fn(by, self) catch |e| return e;
            if (self.max_charges > 0)
                self.charges -= 1;
        } else {
            return error.NoCharges;
        }
    }
};

pub const BrazierWandEvoc = Evocable{
    .id = "evoc_brazier_wand",
    .name = "brazier wand",
    .tile_fg = colors.GOLD,
    .max_charges = 2,
    .rechargable = true,
    .trigger_fn = struct {
        fn f(_: *Mob, _: *Evocable) Evocable.EvokeError!void {
            const chosen = ui.chooseCell(.{
                .require_seen = true,
                .targeter = .Trajectory,
            }) orelse return error.BadPosition;

            if (state.dungeon.machineAt(chosen)) |mach| {
                if (mem.startsWith(u8, mach.id, "light_")) {
                    // Don't want to destroy machine, because that
                    // could make holes in treasure vaults
                    mach.power = 0;

                    ui.Animation.apply(.{ .Particle = .{
                        .name = "lzap-golden",
                        .coord = state.player.coord,
                        .target = .{ .C = chosen },
                    } });

                    state.message(.Info, "The wand disables the {s}.", .{mach.name});
                } else {
                    ui.drawAlertThenLog("That's not a light source.", .{});
                    return error.BadPosition;
                }
            } else {
                ui.drawAlertThenLog("There's no light source there.", .{});
                return error.BadPosition;
            }
        }
    }.f,
};

pub const FlamethrowerEvoc = Evocable{
    .id = "evoc_flamethrower",
    .name = "flamethrower",
    .tile_fg = 0xff0000,
    .max_charges = 3,
    .rechargable = true,
    .trigger_fn = struct {
        fn f(_: *Mob, _: *Evocable) Evocable.EvokeError!void {
            const dest = ui.chooseCell(.{
                .require_seen = true,
                .targeter = .Trajectory,
            }) orelse return error.BadPosition;

            ui.Animation.apply(.{ .Particle = .{
                .name = "zap-fire-messy",
                .coord = state.player.coord,
                .target = .{ .C = dest },
            } });
            fire.setTileOnFire(dest, null);
        }
    }.f,
};

pub const EldritchLanternEvoc = Evocable{
    .id = "eldritch_lantern",
    .name = "eldritch lantern",
    .tile_fg = 0x23abef,
    .max_charges = 5,
    .trigger_fn = _triggerEldritchLantern,
};
fn _triggerEldritchLantern(mob: *Mob, _: *Evocable) Evocable.EvokeError!void {
    assert(mob == state.player);
    state.message(.Info, "The eldritch lantern flashes brilliantly!", .{});

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;

        const coord = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(coord).mob) |othermob| {
            // Treat evoker specially later on
            if (mob == othermob)
                continue;

            othermob.addStatus(.Daze, 0, .{ .Tmp = 8 });
        }
    };

    ui.Animation.apply(.{ .Particle = .{
        .name = "pulse-brief",
        .coord = state.player.coord,
        .target = .{ .I = state.player.stat(.Vision) },
    } });

    mob.addStatus(.Daze, 0, .{ .Tmp = rng.range(usize, 1, 4) });
    mob.makeNoise(.Explosion, .Medium);
}

pub const SymbolEvoc = Evocable{
    .id = "evoc_symbol",
    .name = "Symbol of Torment",
    .tile_fg = 0xffffff,
    .max_charges = 7,
    .rechargable = false,
    .trigger_fn = struct {
        fn f(_: *Mob, _: *Evocable) Evocable.EvokeError!void {
            const DIST = 7;
            const OPTS = .{ .ignore_mobs = true, .only_if_breaks_lof = true, .right_now = true };

            const dest = ui.chooseCell(.{
                .require_seen = true,
                .targeter = .{ .Duo = [2]*const ui.ChooseCellOpts.Targeter{
                    &.{ .AoE1 = .{ .dist = DIST, .opts = OPTS } },
                    &.{ .Trajectory = {} },
                } },
            }) orelse return error.BadPosition;

            var coordlist = types.CoordArrayList.init(state.GPA.allocator());
            defer coordlist.deinit();

            var dijk = dijkstra.Dijkstra.init(dest, state.mapgeometry, DIST, state.is_walkable, OPTS, state.GPA.allocator());
            defer dijk.deinit();

            while (dijk.next()) |child|
                coordlist.append(child) catch err.wat();

            state.message(.SpellCast, "You raise the $oSymbol of Torment$.!", .{});

            ui.Animation.apply(.{ .Particle = .{ .name = "zap-torment", .coord = state.player.coord, .target = .{ .C = dest } } });
            ui.Animation.apply(.{ .Particle = .{ .name = "explosion-torment", .coord = dest, .target = .{ .L = coordlist.items } } });

            for (coordlist.items) |coord|
                if (state.dungeon.at(coord).mob) |mob| {
                    if (mob != state.player and mob.life_type == .Living) {
                        assert(mob.corpse == .Normal);
                        mob.kill();
                        _ = mob.raiseAsUndead(mob.coord);
                    }
                };
        }
    }.f,
};

// }}}

pub const PatternChecker = struct { // {{{
    pub const MAX_TURNS = 10;
    pub const Func = fn (*Mob, *State, Activity, bool) bool;

    pub const State = struct {
        //history: ringbuffer.RingBuffer(bool, MAX_TURNS),
        //history: [MAX_TURNS]bool = undefined,
        mobs: [10]?*Mob = undefined,
        directions: [10]?Direction = undefined,
        coords: [10]?Coord = undefined,
    };

    turns: usize,
    init: ?fn (*Mob, Direction, *State) InitFnErr!Activity,
    funcs: [MAX_TURNS]Func,
    //state: [MAX_TURNS]State = undefined,
    state: State = undefined,
    turns_taken: usize = undefined,

    pub const InitFnErr = error{
        NeedCardinalDirection,
        NeedOppositeWalkableTile,
        NeedWalkableTile,
        NeedOppositeTileNearWalls,
        NeedTileNearWalls,
        NeedHostileOnTile,
        NeedOpenSpace,
        NeedOppositeWalkableTileInFrontOfWall,
        NeedLivingEnemy,
    };

    pub fn reset(self: *PatternChecker) void {
        //state_set.history.init();
        //mem.set(bool, self.state.history[0..], false);
        self.turns_taken = 0;
        mem.set(?*Mob, self.state.mobs[0..], null);
        mem.set(?Direction, self.state.directions[0..], null);
        mem.set(?Coord, self.state.coords[0..], null);
    }

    pub fn advance(self: *PatternChecker, mob: *Mob) union(enum) {
        Completed: PatternChecker.State,
        Failed,
        Continued,
    } {
        assert(self.turns_taken < state.player_turns);
        assert(self.turns_taken < self.turns);

        const cur = mob.activities.current().?;
        if ((self.funcs[self.turns_taken])(mob, &self.state, cur, false)) {
            self.turns_taken += 1;
            if (self.turns_taken == self.turns) {
                const oldstate = self.state;
                self.reset();
                return .{ .Completed = oldstate };
            } else {
                return .Continued;
            }
        } else {
            self.reset();
            return .Failed;
        }
    }

    // Utility methods for use in Ring definitions
    pub fn _util_getHostileInDirection(mob: *Mob, d: Direction) InitFnErr!*Mob {
        return utils.getHostileInDirection(mob, d) catch |e| switch (e) {
            error.NoHostileThere => return error.NeedHostileOnTile,
            error.OutOfMapBounds => unreachable, // Direction chooser should've taken care of this
        };
    }
}; // }}}

pub const LightningRing = Ring{ // {{{
    .name = "electrocution",
    .pattern_checker = .{
        // coords[0] is the original coord of the attacked enemy.
        // directions[0] is the attacked direction.
        // directions[1] is the first move away from the enemy.
        .turns = 3,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;
                stt.directions[0] = d;
                return Activity{ .Attack = .{
                    .direction = d,
                    .who = undefined,
                    .coord = undefined,
                } };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.direction == stt.directions[0].?;
                    if (r and !dry) {
                        stt.coords[0] = cur.Attack.coord;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Move and
                        !cur.Move.is_diagonal() and
                        cur.Move == stt.directions[0].?.opposite();
                    if (r and !dry) {
                        stt.directions[1] = cur.Move;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = !cur.Move.is_diagonal() and
                        (cur.Move == stt.directions[1].?.turnleft() or
                        cur.Move == stt.directions[1].?.turnright()) and
                        new_coord.distance(stt.coords[0].?) == 2;
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, _: PatternChecker.State) void {
            const rElec_pips = @intCast(usize, math.max(0, self.resistance(.rElec))) / 25;
            const power = 2 + (rElec_pips / 2);
            const duration = 4 + (rElec_pips * 4);

            self.addStatus(.RingElectrocution, power, .{ .Tmp = duration });
        }
    }.f,
}; // }}}

pub const CremationRing = Ring{ // {{{
    .name = "cremation",
    .pattern_checker = .{
        .turns = 4,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;
                stt.directions[0] = d;
                return Activity{ .Attack = .{
                    .direction = d,
                    .who = undefined,
                    .coord = undefined,
                } };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.direction == stt.directions[0].?;
                    if (r and !dry) {
                        stt.coords[0] = cur.Attack.coord;
                        stt.coords[1] = mob.coord;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = cur.Move.is_diagonal() and
                        new_coord.distance(stt.coords[0].?) == 1 and
                        !new_coord.eq(stt.coords[1].?);
                    if (r and !dry) {
                        stt.coords[2] = mob.coord;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = cur.Move.is_diagonal() and
                        new_coord.distance(stt.coords[0].?) == 1 and
                        !new_coord.eq(stt.coords[1].?) and
                        !new_coord.eq(stt.coords[2].?);
                    if (r and !dry) {
                        stt.coords[3] = mob.coord;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = cur.Move.is_diagonal() and
                        new_coord.distance(stt.coords[0].?) == 1 and
                        !new_coord.eq(stt.coords[1].?) and
                        !new_coord.eq(stt.coords[2].?) and
                        !new_coord.eq(stt.coords[3].?);
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            _ = stt;
            for (&DIRECTIONS) |d|
                if (self.coord.move(d, state.mapgeometry)) |neighbor| {
                    fire.setTileOnFire(neighbor, null);
                    if (state.dungeon.at(neighbor).mob) |mob| {
                        // Deliberately make both friend and foe flammable
                        mob.addStatus(.Flammable, 0, .{ .Tmp = 20 });
                    }
                };
        }
    }.f,
}; // }}}

pub const DistractionRing = Ring{ // {{{
    .name = "distraction",
    .pattern_checker = .{
        .turns = 3,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;
                stt.directions[0] = d;
                return Activity{ .Move = d };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur == .Move and !cur.Move.is_diagonal()) {
                        const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                        if (new_coord.move(cur.Move, state.mapgeometry)) |adj_mob_c| {
                            if (state.dungeon.at(adj_mob_c).mob) |other| {
                                if (other.isHostileTo(mob) and other.ai.is_combative) {
                                    if (!dry) {
                                        stt.mobs[0] = other;
                                        stt.coords[0] = adj_mob_c;
                                    }
                                    return true;
                                }
                            }
                        }
                    }
                    return false;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = !cur.Move.is_diagonal() and
                        (cur.Move == stt.directions[0].?.turnleft() or
                        cur.Move == stt.directions[0].?.turnright()) and
                        new_coord.distance(stt.coords[0].?) == 1;
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const foe_coord = stt.mobs[0].?.coord;
                    const r = cur == .Move and
                        cur.Move == stt.directions[0].? and
                        mob.coord.distance(foe_coord) == 1; // he's still there?
                    if (r and !dry) {
                        stt.directions[1] = Direction.from(mob.coord, foe_coord);
                    }
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, _: PatternChecker.State) void {
            const RADIUS = 4;

            var anim_buf = StackBuffer(Coord, (RADIUS * 2) * (RADIUS * 2)).init(null);
            var dijk = dijkstra.Dijkstra.init(self.coord, state.mapgeometry, RADIUS, state.is_walkable, .{ .ignore_mobs = true, .only_if_breaks_lof = true }, state.GPA.allocator());
            defer dijk.deinit();
            while (dijk.next()) |coord2| {
                if (utils.getHostileAt(self, coord2)) |hostile| {
                    hostile.addStatus(.Amnesia, 0, .{ .Tmp = 7 });
                } else |_| {}
                anim_buf.append(coord2) catch unreachable;
            }

            // TODO: use beams-ring-amnesia particle effect
            // ui.Animation.blink(anim_buf.constSlice(), '?', colors.AQUAMARINE, .{}).apply();
        }
    }.f,
}; // }}}

pub const DamnationRing = Ring{ // {{{
    .name = "damnation",
    .pattern_checker = .{
        .turns = 3,
        .init = struct {
            pub fn f(mob: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (mob.coord.move(d, state.mapgeometry)) |nextcoord| {
                    if (!state.is_walkable(nextcoord, .{ .mob = mob })) {
                        return error.NeedWalkableTile;
                    }
                    if (state.dungeon.neighboringWalls(nextcoord, true) == 0) {
                        return error.NeedTileNearWalls;
                    }
                } else {
                    return error.NeedWalkableTile;
                }

                stt.directions[0] = d;
                return Activity{ .Move = d };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = cur.Move == stt.directions[0].? and
                        state.dungeon.neighboringWalls(new_coord, true) > 0;
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Attack;
                    //cur.Attack.direction == stt.directions[0].?;
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, _: PatternChecker.State) void {
            const rFire_pips = @intCast(usize, math.max(0, self.resistance(.rFire))) / 25;
            const power = 2 + rFire_pips;
            const duration = 4 + (rFire_pips * 4);

            self.addStatus(.RingDamnation, power, .{ .Tmp = duration });
        }
    }.f,
}; // }}}

pub const TeleportationRing = Ring{ // {{{
    .name = "teleportation",
    .pattern_checker = .{
        // mobs[0]: attacked mob
        // directions[0]: first attack direction
        .turns = 5,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                stt.directions[0] = d;
                return Activity{ .Move = d.opposite() };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Move and
                        cur.Move == stt.directions[0].?.opposite();
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Move and
                        cur.Move == stt.directions[0].?.opposite();
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.direction == stt.directions[0].?;
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, _: PatternChecker.State) void {
            self.addStatus(.RingTeleportation, 0, .{ .Tmp = 5 });
        }
    }.f,
}; // }}}

pub const ElectrificationRing = Ring{ // {{{
    .name = "electrification",
    .pattern_checker = .{
        .turns = 3,
        .init = struct {
            pub fn f(mob: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;

                if (state.dungeon.neighboringWalls(mob.coord, false) > 0)
                    return error.NeedOpenSpace;

                stt.directions[0] = d;
                stt.mobs[0] = try PatternChecker._util_getHostileInDirection(mob, d);

                return Activity{ .Attack = .{
                    .direction = d,
                    .who = undefined,
                    .coord = undefined,
                } };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.direction == stt.directions[0].? and
                        cur.Attack.who == stt.mobs[0].?;
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move or cur.Move.is_diagonal())
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const side1_coord = new_coord.move(cur.Move.turnright(), state.mapgeometry) orelse return false;
                    const side2_coord = new_coord.move(cur.Move.turnleft(), state.mapgeometry) orelse return false;
                    const r = cur.Move == stt.directions[0].?.opposite() and
                        state.dungeon.at(side1_coord).type == .Wall and
                        state.dungeon.at(side2_coord).type == .Wall;
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.who == stt.mobs[0].?;
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            const directions = [_]Direction{
                stt.directions[0].?,
                stt.directions[0].?.turnLeftDiagonally(),
                stt.directions[0].?.turnRightDiagonally(),
            };

            var anim_buf = StackBuffer(Coord, 4).init(null);
            for (&directions) |d|
                if (self.coord.move(d, state.mapgeometry)) |c|
                    anim_buf.append(c) catch err.wat();

            ui.Animation.blink(anim_buf.constSlice(), '*', ui.Animation.ELEC_LINE_FG, .{}).apply();

            for (&directions) |d|
                if (utils.getHostileInDirection(self, d)) |hostile| {
                    hostile.takeDamage(.{
                        .amount = @intToFloat(f64, 2),
                        .by_mob = self,
                        .kind = .Electric,
                    }, .{ .noun = "Lightning" });
                } else |_| {};
        }
    }.f,
}; // }}}

pub const InsurrectionRing = Ring{ // {{{
    .name = "insurrection",
    .pattern_checker = .{
        .turns = 5,
        .init = struct {
            pub fn f(mob: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;

                stt.directions[0] = d;
                stt.coords[0] = mob.coord;
                stt.mobs[0] = try PatternChecker._util_getHostileInDirection(mob, d);
                stt.coords[1] = stt.mobs[0].?.coord;

                return .Rest;
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Move and
                        (cur.Move == stt.directions[0].?.turnLeftDiagonally() or
                        cur.Move == stt.directions[0].?.turnRightDiagonally()) and
                        stt.mobs[0].?.coord.eq(stt.coords[1].?); // Ensure he's still there
                    if (r and !dry) {
                        stt.coords[2] = mob.coord;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = new_coord.eq(stt.coords[0].?) and
                        stt.mobs[0].?.coord.eq(stt.coords[1].?); // Ensure he's still there
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = !new_coord.eq(stt.coords[2].?) and
                        (cur.Move == stt.directions[0].?.turnLeftDiagonally() or
                        cur.Move == stt.directions[0].?.turnRightDiagonally()) and
                        stt.mobs[0].?.coord.eq(stt.coords[1].?); // Ensure he's still there
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = new_coord.eq(stt.coords[0].?) and
                        stt.mobs[0].?.coord.eq(stt.coords[1].?); // Ensure he's still there
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            const lifetime = 14;
            const max_corpses = 3;

            var corpses_raised: usize = 0;
            while (utils.getNearestCorpse(self)) |corpse_coord| {
                const corpse_mob = state.dungeon.at(corpse_coord).surface.?.Corpse;
                if (corpse_mob.raiseAsUndead(corpse_coord)) {
                    corpses_raised += 1;

                    corpse_mob.addStatus(.Lifespan, 0, .{ .Tmp = lifetime });
                    corpse_mob.addStatus(.Blind, 0, .Prm);
                    self.addUnderling(corpse_mob);
                    ai.updateEnemyKnowledge(corpse_mob, stt.mobs[0].?, null);
                }

                if (corpses_raised > max_corpses)
                    break;
            }

            if (corpses_raised > 0) {
                state.message(.Info, "Nearby corpses rise to defend you!", .{});
            } else {
                state.message(.Info, "You feel lonely for a moment.", .{});
            }
        }
    }.f,
}; // }}}

pub const MagnetizationRing = Ring{ // {{{
    .name = "magnetization",
    .pattern_checker = .{
        // mobs[0] is the attacked enemy.
        // directions[0] is the original attacking direction.
        // coords[0] is the attacked enemy's initial coordinate.
        .turns = 3,
        .init = struct {
            pub fn f(mob: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;

                stt.mobs[0] = try PatternChecker._util_getHostileInDirection(mob, d);
                stt.directions[0] = d;
                stt.coords[0] = stt.mobs[0].?.coord;

                return Activity{ .Attack = .{
                    .direction = d,
                    .who = undefined,
                    .coord = undefined,
                } };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.who == stt.mobs[0].? and
                        cur.Attack.direction == stt.directions[0].?;
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Move and
                        (cur.Move == stt.directions[0].?.turnLeftDiagonally() or
                        cur.Move == stt.directions[0].?.turnRightDiagonally()) and
                        cur.Move.is_diagonal() and
                        stt.mobs[0].?.coord.eq(stt.coords[0].?); // Ensure he's still there
                    if (r and !dry) {
                        stt.directions[1] = cur.Move;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const next_d = if (stt.directions[1].? == stt.directions[0].?.turnLeftDiagonally())
                        stt.directions[0].?.turnRightDiagonally()
                    else
                        stt.directions[0].?.turnLeftDiagonally();
                    const r = cur == .Move and
                        cur.Move == next_d and
                        stt.mobs[0].?.coord.eq(stt.coords[0].?); // Ensure he's still there
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            const magnet = stt.mobs[0].?;

            var gen = Generator(Rect.rectIter).init(state.mapRect(self.coord.z));
            while (gen.next()) |coord| if (self.cansee(coord)) {
                if (state.dungeon.at(coord).mob) |othermob| {
                    if (othermob != magnet and
                        othermob.isHostileTo(self))
                    {
                        const d = othermob.coord.closestDirectionTo(magnet.coord, state.mapgeometry);
                        combat.throwMob(self, othermob, d, othermob.coord.distance(magnet.coord));
                    }
                }
            };

            // var y: usize = 0;
            // while (y < HEIGHT) : (y += 1) {
            //     var x: usize = 0;
            //     while (x < WIDTH) : (x += 1) {
            //         const coord = Coord.new2(self.coord.z, x, y);
            //         if (self.cansee(coord)) {
            //             if (state.dungeon.at(coord).mob) |othermob| {
            //                 if (othermob != magnet and
            //                     othermob.isHostileTo(self))
            //                 {
            //                     const d = othermob.coord.closestDirectionTo(magnet.coord, state.mapgeometry);
            //                     combat.throwMob(self, othermob, d, othermob.coord.distance(magnet.coord));
            //                 }
            //             }
            //         }
            //     }
            // }

            if (state.player.cansee(magnet.coord))
                state.message(.Info, "{c} becomes magnetic!", .{magnet});
        }
    }.f,
}; // }}}

pub const ExcisionRing = Ring{ // {{{
    .name = "excision",
    .pattern_checker = .{
        .turns = 4,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;

                stt.directions[0] = d;

                return .Rest;
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Move and
                        (cur.Move == stt.directions[0].?.turnleft() or
                        cur.Move == stt.directions[0].?.turnright());
                    if (r and !dry) {
                        stt.directions[1] = cur.Move;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Move and
                        cur.Move == stt.directions[1].?;
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Move and
                        cur.Move == stt.directions[0].?.opposite();
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            if (self.coord.move(stt.directions[0].?, state.mapgeometry)) |n| {
                if (state.is_walkable(n, .{})) {
                    const s = mobs.placeMob(state.GPA.allocator(), &mobs.SpectralSwordTemplate, n, .{});
                    self.addUnderling(s);
                    state.message(.Info, "A spectral blade appears mid-air, hovering precariously.", .{});

                    const will = @intCast(usize, self.stat(.Willpower));
                    self.addStatus(.RingExcision, 0, .{ .Tmp = will * 2 });

                    return;
                }
            }
            state.message(.Info, "A haftless sword seems to appear mid-air, then disappears abruptly.", .{});
        }
    }.f,
}; // }}}

pub const ConjurationRing = Ring{ // {{{
    .name = "conjuration",
    .pattern_checker = .{
        .turns = 3,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;
                stt.directions[0] = d;
                return Activity{ .Move = d };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur == .Move and !cur.Move.is_diagonal()) {
                        const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                        if (new_coord.move(cur.Move, state.mapgeometry)) |adj_mob_c| {
                            if (state.dungeon.at(adj_mob_c).mob) |other| {
                                if (other.isHostileTo(mob) and other.ai.is_combative) {
                                    if (!dry) {
                                        stt.mobs[0] = other;
                                        stt.coords[0] = adj_mob_c;
                                    }
                                    return true;
                                }
                            }
                        }
                    }
                    return false;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = !cur.Move.is_diagonal() and
                        (cur.Move == stt.directions[0].?.turnleft() or
                        cur.Move == stt.directions[0].?.turnright()) and
                        new_coord.distance(stt.coords[0].?) == 1;
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const foe_coord = stt.mobs[0].?.coord;
                    const r = cur == .Move and
                        cur.Move == stt.directions[0].? and
                        mob.coord.distance(foe_coord) == 1; // he's still there?
                    if (r and !dry) {
                        stt.directions[1] = Direction.from(mob.coord, foe_coord);
                    }
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, _: PatternChecker.State) void {
            const will = @intCast(usize, self.stat(.Willpower));
            const duration = math.max(1, will / 2);
            self.addStatus(.RingConjuration, 2, .{ .Tmp = duration });
        }
    }.f,
}; // }}}

pub const DefaultPinRing = Ring{ // {{{
    .name = "pin foe",
    .pattern_checker = .{
        // mobs[0]: attacked mob
        // directions[0]: first attack direction
        // coords[0]: initial coordinate
        // coords[1]: attacked mob's initial coordinate
        .turns = 4,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;
                stt.directions[0] = d;
                return Activity{ .Attack = .{
                    .direction = d,
                    .who = undefined,
                    .coord = undefined,
                } };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.direction == stt.directions[0].?;
                    if (r and !dry) {
                        stt.mobs[0] = cur.Attack.who;
                        stt.coords[0] = mob.coord;
                        stt.coords[1] = cur.Attack.coord;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    const r = cur.Move.is_diagonal() and
                        cur.Move.is_adjacent(stt.directions[0].?) and
                        // Is the new coord adjacent to both the attacked mob and
                        // the previous location?
                        new_coord.distance(stt.coords[0].?) == 1 and
                        new_coord.distance(stt.coords[1].?) == 1;
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    const r = cur == .Attack and
                        cur.Attack.who == stt.mobs[0].? and
                        cur.Attack.coord.eq(stt.coords[1].?);
                    if (r and !dry) {
                        stt.directions[1] = cur.Attack.direction;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Move and
                        cur.Move == stt.directions[1].?.opposite();
                    return r;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            _ = self;
            stt.mobs[0].?.addStatus(.Held, 0, .{ .Tmp = 5 });
        }
    }.f,
}; // }}}

pub const DefaultChargeRing = Ring{ // {{{
    .name = "charge",
    .pattern_checker = .{
        .turns = 3,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                stt.directions[0] = d;
                return Activity{ .Move = d.opposite() };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            // directions[0]: first movement direction
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    const r = cur == .Move and
                        cur.Move == stt.directions[0].?.opposite();
                    return r;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur == .Move and cur.Move == stt.directions[0].?) {
                        const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                        if (new_coord.move(cur.Move, state.mapgeometry)) |adj_mob_c| {
                            if (state.dungeon.at(adj_mob_c).mob) |other| {
                                if (other.isHostileTo(mob) and other.ai.is_combative) {
                                    if (!dry)
                                        stt.mobs[0] = other;
                                    return true;
                                }
                            }
                        }
                    }
                    return false;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            const target = stt.mobs[0].?;
            const verb = if (self == state.player) "charge" else "charges";
            if (player.canSeeAny(&.{ self.coord, target.coord })) {
                state.message(.Info, "{c} {s} {}!", .{ self, verb, target });
            }
            combat.throwMob(self, stt.mobs[0].?, stt.directions[0].?, 7);
        }
    }.f,
}; // }}}

pub const DefaultLungeRing = Ring{ // {{{
    .name = "lunge",
    .pattern_checker = .{
        .turns = 2,
        .init = struct {
            pub fn f(_: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                stt.directions[0] = d;
                return .Rest;
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            // directions[0]: first movement direction
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur == .Move and cur.Move == stt.directions[0].?) {
                        const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                        if (new_coord.move(cur.Move, state.mapgeometry)) |adj_mob_c| {
                            if (state.dungeon.at(adj_mob_c).mob) |other| {
                                if (other.isHostileTo(mob) and other.ai.is_combative) {
                                    if (!dry)
                                        stt.mobs[0] = other;
                                    return true;
                                }
                            }
                        }
                    }
                    return false;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            const target = stt.mobs[0].?;

            const msg_verb = if (target == state.player) "lunges" else "lunge";
            state.message(.Combat, "{c} {s} at {}!", .{ self, msg_verb, target });

            self.fight(target, .{ .free_attack = true, .auto_hit = true, .disallow_stab = true, .damage_bonus = 300, .loudness = .Loud });
            target.addStatus(.Fear, 0, .{ .Tmp = 7 });
        }
    }.f,
}; // }}}

pub const DefaultEyepunchRing = Ring{ // {{{
    .name = "eyepunch",
    .pattern_checker = .{
        // mobs[0]: enemy
        .turns = 4,
        .init = struct {
            pub fn f(mob: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (d.is_diagonal())
                    return error.NeedCardinalDirection;
                stt.mobs[0] = try PatternChecker._util_getHostileInDirection(mob, d);
                if (stt.mobs[0].?.life_type != .Living)
                    return error.NeedLivingEnemy;
                return .Rest;
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    return new_coord.distance(stt.mobs[0].?.coord) == 1;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur != .Move)
                        return false;
                    const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                    return new_coord.distance(stt.mobs[0].?.coord) == 1;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, stt: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Attack and cur.Attack.who == stt.mobs[0].?;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(_: *Mob, stt: PatternChecker.State) void {
            assert(stt.mobs[0].?.life_type == .Living);
            stt.mobs[0].?.addStatus(.Blind, 0, .{ .Tmp = 3 });
            stt.mobs[0].?.addStatus(.Disorient, 0, .{ .Tmp = 6 });
        }
    }.f,
}; // }}}

pub const DefaultLeapRing = Ring{ // {{{
    .name = "leap",
    .pattern_checker = .{
        .turns = 3,
        .init = struct {
            pub fn f(mob: *Mob, d: Direction, stt: *PatternChecker.State) PatternChecker.InitFnErr!Activity {
                if (mob.coord.move(d.opposite(), state.mapgeometry)) |opposite_coord| {
                    if (!state.is_walkable(opposite_coord, .{ .mob = mob })) {
                        return error.NeedOppositeWalkableTile;
                    }

                    if (opposite_coord.move(d.opposite(), state.mapgeometry)) |opposite_coord2| {
                        if (state.dungeon.at(opposite_coord2).type != .Wall) {
                            return error.NeedOppositeWalkableTileInFrontOfWall;
                        }
                    } else {
                        return error.NeedOppositeWalkableTileInFrontOfWall;
                    }
                } else {
                    return error.NeedOppositeWalkableTile;
                }

                stt.directions[0] = d;

                return Activity{ .Move = d.opposite() };
            }
        }.f,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State, cur: Activity, dry: bool) bool {
                    if (cur == .Move and cur.Move == stt.directions[0].?.opposite()) {
                        const new_coord = if (dry) mob.coord.move(cur.Move, state.mapgeometry).? else mob.coord;
                        if (new_coord.move(cur.Move, state.mapgeometry)) |adj_coord| {
                            if (state.dungeon.at(adj_coord).type == .Wall) {
                                return true;
                            }
                        }
                    }
                    return false;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            struct {
                pub fn f(_: *Mob, _: *PatternChecker.State, cur: Activity, _: bool) bool {
                    return cur == .Rest;
                }
            }.f,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
            undefined,
        },
    },
    .effect = struct {
        pub fn f(self: *Mob, stt: PatternChecker.State) void {
            self.makeNoise(.Combat, .Loud);
            combat.throwMob(null, self, stt.directions[0].?, 7);
        }
    }.f,
}; // }}}

// Consumables {{{
//

pub const Consumable = struct {
    id: []const u8,
    name: []const u8,
    color: u32,
    effects: []const Effect,
    is_potion: bool = false,
    throwable: bool = false,
    verbs_player: []const []const u8,
    verbs_other: []const []const u8,

    const Effect = union(enum) {
        Status: Status,
        Gas: usize,
        Kit: *const Machine,
        Damage: struct { amount: usize, kind: Damage.DamageKind, lethal: bool = true },
        Heal: usize,
        Resist: struct { r: Resistance, change: isize },
        Stat: struct { s: Stat, change: isize },
        Custom: fn (?*Mob, Coord) void,
    };

    const VERBS_PLAYER_POTION = &[_][]const u8{ "slurp", "quaff" };
    const VERBS_OTHER_POTION = &[_][]const u8{ "slurps", "quaffs" };

    const VERBS_PLAYER_KIT = &[_][]const u8{"use"};
    const VERBS_OTHER_KIT = &[_][]const u8{"uses"};

    const VERBS_PLAYER_CAUT = &[_][]const u8{"cauterise your wounds with"};
    const VERBS_OTHER_CAUT = &[_][]const u8{"cauterises itself with"};

    pub fn createTrapKit(
        comptime id: []const u8,
        comptime name: []const u8,
        func: fn (*Machine, *Mob) void,
    ) Consumable {
        return Consumable{
            .id = id,
            .name = name ++ " kit",
            .effects = &[_]Consumable.Effect{.{
                .Kit = &Machine{
                    .name = name,
                    .powered_fg = colors.PINK,
                    .unpowered_fg = colors.LIGHT_STEEL_BLUE,
                    .powered_tile = '^',
                    .unpowered_tile = '^',
                    .restricted_to = .Necromancer,
                    .on_power = struct {
                        pub fn f(machine: *Machine) void {
                            if (machine.last_interaction) |mob| {
                                if (state.player.cansee(machine.coord))
                                    state.message(.Info, "{c} triggers the {s}!", .{ mob, name });
                                state.dungeon.at(machine.coord).surface = null;
                                func(machine, mob);
                            }
                        }
                    }.f,
                },
            }},
            .color = colors.GOLD,
            .verbs_player = Consumable.VERBS_PLAYER_KIT,
            .verbs_other = Consumable.VERBS_OTHER_KIT,
        };
    }
};

// pub const HotPokerConsumable = Consumable{
//     .id = "cons_hot_poker",
//     .name = "red-hot poker",
//     .effects = &[_]Consumable.Effect{
//         .{ .Damage = .{ .amount = 20, .kind = .Fire, .lethal = false } },
//         .{ .Heal = 20 },
//     },
//     .color = 0xdd1010,
//     .verbs_player = Consumable.VERBS_PLAYER_CAUT,
//     .verbs_other = Consumable.VERBS_OTHER_CAUT,
// };

// pub const CoalConsumable = Consumable{
//     .id = "cons_coal",
//     .name = "burning coal",
//     .effects = &[_]Consumable.Effect{
//         .{ .Damage = .{ .amount = 10, .kind = .Fire, .lethal = false } },
//         .{ .Heal = 10 },
//     },
//     .color = 0xdd3a3a,
//     .verbs_player = Consumable.VERBS_PLAYER_CAUT,
//     .verbs_other = Consumable.VERBS_OTHER_CAUT,
// };

pub const CopperIngotConsumable = Consumable{
    .id = "cons_copper_ingot",
    .name = "copper ingot",
    .effects = &[_]Consumable.Effect{
        .{ .Stat = .{ .s = .Martial, .change = -1 } },
        .{ .Stat = .{ .s = .Evade, .change = -5 } },
        .{ .Resist = .{ .r = .rElec, .change = 25 } },
    },
    .color = 0xcacbca,
    .verbs_player = &[_][]const u8{ "choke down", "swallow" },
    .verbs_other = &[_][]const u8{"chokes down"},
};

pub const GlueTrapKit = Consumable.createTrapKit("kit_trap_glue", "glue trap", struct {
    pub fn f(_: *Machine, mob: *Mob) void {
        mob.addStatus(.Held, 0, .{ .Tmp = 20 });
    }
}.f);

pub const AirblastTrapKit = Consumable.createTrapKit("kit_trap_airblast", "airblast trap", struct {
    pub fn f(_: *Machine, mob: *Mob) void {
        combat.throwMob(null, mob, rng.chooseUnweighted(Direction, &DIRECTIONS), 10);
    }
}.f);

pub const ShockTrapKit = Consumable.createTrapKit("kit_trap_shock", "shock trap", struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        explosions.elecBurst(machine.coord, 5, state.player);
    }
}.f);

pub const BigFireTrapKit = Consumable.createTrapKit("kit_trap_bigfire", "incineration trap", struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        explosions.fireBurst(machine.coord, 7, .{});
    }
}.f);

pub const FireTrapKit = Consumable.createTrapKit("kit_trap_fire", "fire trap", struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        explosions.fireBurst(machine.coord, 3, .{});
    }
}.f);

pub const EmberlingTrapKit = Consumable.createTrapKit("kit_trap_emberling", "emberling trap", struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        mobs.placeMobSurrounding(machine.coord, &mobs.EmberlingTemplate, .{ .no_squads = true, .allegiance = state.player.allegiance });
    }
}.f);

pub const SparklingTrapKit = Consumable.createTrapKit("kit_trap_sparkling", "sparkling trap", struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        mobs.placeMobSurrounding(machine.coord, &mobs.SparklingTemplate, .{ .no_squads = true, .allegiance = state.player.allegiance });
    }
}.f);

pub const MineKit = Consumable{
    .id = "kit_mine",
    .name = "mine kit",
    .effects = &[_]Consumable.Effect{.{ .Kit = &surfaces.Mine }},
    .color = 0xffd7d7,
    .verbs_player = Consumable.VERBS_PLAYER_KIT,
    .verbs_other = Consumable.VERBS_OTHER_KIT,
};

pub const DistractPotion = Consumable{
    .id = "potion_distract",
    .name = "potion of distraction",
    .effects = &[_]Consumable.Effect{.{ .Custom = triggerDistractPotion }},
    .is_potion = true,
    .color = 0xffd700,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const DebilitatePotion = Consumable{
    .id = "potion_debilitate",
    .name = "potion of debilitation",
    .effects = &[_]Consumable.Effect{.{ .Gas = gas.Seizure.id }},
    .is_potion = true,
    .color = 0xd7d77f,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const IntimidatePotion = Consumable{
    .id = "potion_intimidate",
    .name = "potion of intimidation",
    .effects = &[_]Consumable.Effect{.{ .Status = .Intimidating }},
    .is_potion = true,
    .color = colors.PALE_VIOLET_RED,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = false,
};

pub const LeavenPotion = Consumable{
    .id = "potion_leaven",
    .name = "potion of leavenation",
    .effects = &[_]Consumable.Effect{.{ .Status = .Fireproof }},
    .is_potion = true,
    .color = colors.CONCRETE,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = false,
};

pub const BlindPotion = Consumable{
    .id = "potion_blind",
    .name = "potion of irritation",
    .effects = &[_]Consumable.Effect{.{ .Gas = gas.Blinding.id }},
    .is_potion = true,
    .color = 0x7fe7f7,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const GlowPotion = Consumable{
    .id = "potion_glow",
    .name = "potion of illumination",
    .effects = &[_]Consumable.Effect{.{ .Status = .Corona }},
    .is_potion = true,
    .color = 0xffffff,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const SmokePotion = Consumable{
    .id = "potion_smoke",
    .name = "potion of smoke",
    .effects = &[_]Consumable.Effect{.{ .Gas = gas.SmokeGas.id }},
    .is_potion = true,
    .color = 0x00A3D9,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const DisorientPotion = Consumable{
    .id = "potion_disorient",
    .name = "potion of disorientation",
    .effects = &[_]Consumable.Effect{.{ .Gas = gas.Disorient.id }},
    .is_potion = true,
    .color = 0x33cbca,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const ParalysisPotion = Consumable{
    .id = "potion_paralysis",
    .name = "potion of petrification",
    .effects = &[_]Consumable.Effect{.{ .Gas = gas.Paralysis.id }},
    .is_potion = true,
    .color = 0xaaaaff,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const FastPotion = Consumable{
    .id = "potion_fast",
    .name = "potion of acceleration",
    .effects = &[_]Consumable.Effect{.{ .Status = .Fast }},
    .is_potion = true,
    .color = 0xbb6c55,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const RecuperatePotion = Consumable{
    .id = "potion_recuperate",
    .name = "potion of recuperation",
    .effects = &[_]Consumable.Effect{.{ .Status = .Recuperate }},
    .is_potion = true,
    .color = 0xffffff,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
};

pub const InvigoratePotion = Consumable{
    .id = "potion_invigorate",
    .name = "potion of invigoration",
    .effects = &[_]Consumable.Effect{.{ .Status = .Invigorate }},
    .is_potion = true,
    .color = 0xdada53,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
};

pub const IncineratePotion = Consumable{
    .id = "potion_incinerate",
    .name = "potion of incineration",
    .effects = &[_]Consumable.Effect{.{ .Custom = triggerIncineratePotion }},
    .is_potion = true,
    .color = 0xff3434, // TODO: unique color
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

pub const DecimatePotion = Consumable{
    .id = "potion_decimate",
    .name = "potion of decimation",
    .effects = &[_]Consumable.Effect{.{ .Custom = triggerDecimatePotion }},
    .is_potion = true,
    .color = 0xda5353, // TODO: unique color
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
};

// Potion effects {{{

fn triggerDistractPotion(_: ?*Mob, coord: Coord) void {
    sound.makeNoise(coord, .Explosion, .Medium);
    ui.Animation.apply(.{ .Particle = .{ .name = "chargeover-noise", .coord = coord, .target = .{ .C = coord } } });
}

fn triggerIncineratePotion(_: ?*Mob, coord: Coord) void {
    explosions.fireBurst(coord, 4, .{});
}

fn triggerDecimatePotion(_: ?*Mob, coord: Coord) void {
    const MIN_EXPLOSION_RADIUS: usize = 3;
    explosions.kaboom(coord, .{
        .strength = MIN_EXPLOSION_RADIUS * 100,
        .culprit = state.player,
    });
}

// }}}

// }}}

// Armors {{{
//
pub const CuirassArmor = Armor{
    .id = "cuirass_armor",
    .name = "cuirass",
    .resists = .{ .rElec = -25, .Armor = 35 },
};

pub const HauberkArmor = Armor{
    .id = "chainmail_armor",
    .name = "hauberk",
    .resists = .{ .Armor = 25 },
    .stats = .{ .Evade = -10, .Martial = -1 },
};

pub const RobeArmor = Armor{
    .id = "robe_armor",
    .name = "robe",
    .resists = .{ .Armor = 0 },
};

pub const GambesonArmor = Armor{
    .id = "gambeson_armor",
    .name = "gambeson",
    .resists = .{ .Armor = 15 },
};

pub const SpikedLeatherArmor = Armor{
    .id = "spiked_leather_armor",
    .name = "spiked leather armor",
    .resists = .{ .Armor = 15 },
    .stats = .{ .Spikes = 1, .Sneak = -1, .Martial = -1 },
};

// }}}

pub fn _dmgstr(p: usize, vself: []const u8, vother: []const u8, vdeg: []const u8) DamageStr {
    return .{ .dmg_percent = p, .verb_self = vself, .verb_other = vother, .verb_degree = vdeg };
}

pub const CRUSHING_STRS = [_]DamageStr{
    _dmgstr(5, "whack", "whacks", ""),
    _dmgstr(10, "cudgel", "cudgels", ""),
    _dmgstr(30, "bash", "bashes", ""),
    _dmgstr(40, "hit", "hits", ""),
    _dmgstr(50, "hammer", "hammers", ""),
    _dmgstr(60, "batter", "batters", ""),
    _dmgstr(70, "thrash", "thrashes", ""),
    _dmgstr(130, "smash", "smashes", " like an overripe mango"),
    _dmgstr(160, "flatten", "flattens", " like a pancake"),
    _dmgstr(190, "flatten", "flattens", " like a chapati"),
    _dmgstr(200, "grind", "grinds", " into powder"),
    _dmgstr(400, "pulverise", "pulverises", " into a bloody mist"),
};
pub const SLASHING_STRS = [_]DamageStr{
    _dmgstr(40, "hit", "hits", ""),
    _dmgstr(50, "slash", "slashes", ""),
    _dmgstr(100, "chop", "chops", " into pieces"),
    _dmgstr(110, "chop", "chops", " into tiny pieces"),
    _dmgstr(150, "slice", "slices", " into ribbons"),
    _dmgstr(200, "cut", "cuts", " asunder"),
    _dmgstr(250, "mince", "minces", " like boiled poultry"),
};
pub const PIERCING_STRS = [_]DamageStr{
    _dmgstr(5, "prick", "pricks", ""),
    _dmgstr(30, "hit", "hits", ""),
    _dmgstr(40, "impale", "impales", ""),
    _dmgstr(50, "skewer", "skewers", ""),
    _dmgstr(60, "perforate", "perforates", ""),
    _dmgstr(100, "skewer", "skewers", " like a kebab"),
    _dmgstr(200, "spit", "spits", " like a pig"),
    _dmgstr(300, "perforate", "perforates", " like a sieve"),
};
pub const LACERATING_STRS = [_]DamageStr{
    _dmgstr(20, "whip", "whips", ""),
    _dmgstr(40, "lash", "lashes", ""),
    _dmgstr(50, "lacerate", "lacerates", ""),
    _dmgstr(70, "shred", "shreds", ""),
    _dmgstr(90, "shred", "shreds", " like wet paper"),
    _dmgstr(150, "mangle", "mangles", " beyond recognition"),
};

pub const BITING_STRS = [_]DamageStr{
    _dmgstr(80, "bite", "bites", ""),
    _dmgstr(81, "mangle", "mangles", ""),
};
pub const CLAW_STRS = [_]DamageStr{
    _dmgstr(5, "scratch", "scratches", ""),
    _dmgstr(60, "claw", "claws", ""),
    _dmgstr(61, "mangle", "mangles", ""),
    _dmgstr(90, "shred", "shreds", " like wet paper"),
    _dmgstr(100, "tear", "tears", " into pieces"),
    _dmgstr(150, "tear", "tears", " into tiny pieces"),
    _dmgstr(200, "mangle", "mangles", " beyond recognition"),
};
pub const FIST_STRS = [_]DamageStr{
    _dmgstr(20, "punch", "punches", ""),
    _dmgstr(30, "hit", "hits", ""),
    _dmgstr(40, "bludgeon", "bludgeons", ""),
    _dmgstr(60, "pummel", "pummels", ""),
};
pub const KICK_STRS = [_]DamageStr{
    _dmgstr(80, "kick", "kicks", ""),
    _dmgstr(81, "curbstomp", "curbstomps", ""),
};

pub const SHOCK_STRS = [_]DamageStr{
    _dmgstr(10, "zap", "zaps", ""),
    _dmgstr(40, "shock", "shocks", ""),
    _dmgstr(70, "strike", "strikes", ""),
    _dmgstr(100, "electrocute", "electrocutes", ""),
};

// Body weapons {{{
pub const FistWeapon = Weapon{
    .id = "none",
    .name = "none",
    .damage = 2,
    .strs = &FIST_STRS,
};

// }}}

// Edged weapons {{{

pub const SwordWeapon = Weapon{
    .id = "sword",
    .name = "longsword",
    .damage = 2,
    .stats = .{ .Evade = 10 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .OpenMelee, .duration = .Equ },
    },
    .strs = &SLASHING_STRS,
};
pub const BoneSwordWeapon = Weapon.createBoneWeapon(&SwordWeapon, .{});
pub const CopperSwordWeapon = Weapon.createCopperWeapon(&SwordWeapon, .{});

// Rare foreign weapon, so no copper/bone weapons (since that'd have
// to be produced at home in Irtraummisem).
//
// .Melee-10 represents difficulty for Obmirnul to use since it's foreign (of
// course, it's also there for balance :P)
//
pub const MartialSwordWeapon = Weapon{
    .id = "martial_sword",
    .name = "martial sword",
    .damage = 2,
    .martial = true,
    .stats = .{ .Evade = 10, .Martial = 2, .Melee = -10 },
    .strs = &SLASHING_STRS,
};

pub const ShadowSwordWeapon = Weapon{
    .id = "shadow_sword",
    .name = "shadow sword",
    .damage = 1,
    .martial = true,
    .stats = .{ .Evade = 10, .Martial = 2 },
    .ego = .NC_Insane,
    .strs = &SLASHING_STRS,
};

pub const DaggerWeapon = Weapon{
    .id = "dagger",
    .name = "dagger",
    .damage = 1,
    .martial = true,
    .stats = .{ .Martial = 1 },
    .strs = &PIERCING_STRS,
};
pub const BoneDaggerWeapon = Weapon.createBoneWeapon(&DaggerWeapon, .{});

pub const StilettoWeapon = Weapon{
    .id = "stiletto",
    .name = "stiletto",
    .damage = 5,
    .stats = .{ .Melee = -25 },
    .strs = &PIERCING_STRS,
};
pub const BoneStilettoWeapon = Weapon.createBoneWeapon(&StilettoWeapon, .{});

pub const RapierWeapon = Weapon{
    .id = "rapier",
    .name = "rapier",
    .damage = 3,
    .stats = .{ .Melee = -10, .Evade = 10 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .Riposte, .duration = .Equ },
    },
    .strs = &PIERCING_STRS,
};
pub const CopperRapierWeapon = Weapon.createCopperWeapon(&RapierWeapon, .{});

// }}}

// Polearms {{{
//
// XXX: no copper weapons for polearms, as it might create some imbalance
// with players being allowed to stand on copper ground and attack safely at a
// distance...?

pub const HalberdWeapon = Weapon{
    .id = "halberd",
    .name = "halberd",
    .damage = 2,
    .stats = .{ .Sneak = -1 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .OpenMelee, .duration = .Equ },
    },
    .strs = &SLASHING_STRS,
};
pub const BoneHalberdWeapon = Weapon.createBoneWeapon(&HalberdWeapon, .{});

// Glaive without the closed-melee effect, and with reaching.
pub const SpearWeapon = Weapon{
    .id = "spear",
    .name = "spear",
    .damage = 2,
    .stats = .{ .Melee = 10, .Sneak = -1 },
    .strs = &SLASHING_STRS,
    .reach = 2,
};

pub const GlaiveWeapon = Weapon{
    .id = "glaive",
    .name = "glaive",
    .damage = 2,
    .stats = .{ .Melee = 10, .Sneak = -1 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .ClosedMelee, .duration = .Equ },
    },
    .strs = &SLASHING_STRS,
};

pub const MonkSpadeWeapon = Weapon{
    .id = "monk_spade",
    .name = "monk's spade",
    .damage = 1,
    .knockback = 2,
    .stats = .{ .Melee = 20, .Sneak = -1 },
    .strs = &PIERCING_STRS,
};

pub const WoldoWeapon = Weapon{
    .id = "woldo",
    .name = "woldo",
    .damage = 3,
    .martial = true,
    .stats = .{ .Melee = -15, .Martial = 1, .Sneak = -1 },
    .strs = &SLASHING_STRS,
};

// }}}

// Blunt weapons {{{

// Temporarily removed:
// - Dilutes weapon pool, I'd like to give quarterstaff's gimmicks to another
//   boring weapon.
// - High damage doesn't make sense. Quarterstaff is a piece of wood, how
//   does it do damage?
//
// pub const QuarterstaffWeapon = Weapon{
//     .id = "quarterstaff",
//     .name = "quarterstaff",
//     .damage = 2,
//     .martial = true,
//     .stats = .{ .Martial = 1, .Evade = 15 },
//     .equip_effects = &[_]StatusDataInfo{
//         .{ .status = .OpenMelee, .duration = .Equ },
//     },
//     .strs = &CRUSHING_STRS,
// };

pub const KnoutWeapon = Weapon{
    .id = "knout",
    .name = "knout",
    .damage = 6,
    .strs = &CRUSHING_STRS,
};

pub const MorningstarWeapon = Weapon{
    .id = "morningstar",
    .name = "morningstar",
    .damage = 3,
    .stats = .{ .Melee = 10 },
    .strs = &CRUSHING_STRS,
};

pub const ClubWeapon = Weapon{
    .id = "club",
    .name = "club",
    .damage = 1,
    .strs = &CRUSHING_STRS,
};

pub const BludgeonWeapon = Weapon{
    .id = "bludgeon",
    .name = "bludgeon",
    .damage = 1,
    .strs = &CRUSHING_STRS,
};

// XXX: not dropped as loot, as it's not interesting enough to warrant giving
// it to player
pub const MaceWeapon = Weapon{
    .id = "mace",
    .name = "mace",
    .damage = 2,
    //.stats = .{ .Melee = 10 }, // Not for player, no reason to entice them to use it. Plus spoils balance
    .strs = &CRUSHING_STRS,
};
pub const BoneMaceWeapon = Weapon.createBoneWeapon(&MaceWeapon, .{});
//pub const CopperMaceWeapon = Weapon.createCopperWeapon(&MaceWeapon, .{});

pub const GreatMaceWeapon = Weapon{
    .id = "great_mace",
    .name = "great mace",
    .damage = 2,
    .effects = &[_]StatusDataInfo{
        .{ .status = .Debil, .duration = .{ .Tmp = 6 } },
    },
    .strs = &CRUSHING_STRS,
};
pub const BoneGreatMaceWeapon = Weapon.createBoneWeapon(&GreatMaceWeapon, .{});

pub const ShadowMaceWeapon = Weapon{
    .id = "shadow_mace",
    .name = "shadow mace",
    .damage = 1,
    .ego = .NC_MassPara,
    .strs = &CRUSHING_STRS,
};

// }}}

// ----------------------------------------------------------------------------

pub fn createItem(comptime T: type, item: T) *T {
    const list = switch (T) {
        Ring => &state.rings,
        Armor => &state.armors,
        Weapon => &state.weapons,
        Evocable => &state.evocables,
        else => @compileError("uh wat"),
    };
    const it = list.appendAndReturn(item) catch err.oom();
    if (T == Ring) it.pattern_checker.reset();
    if (T == Evocable) it.charges = it.max_charges;
    return it;
}

pub fn createItemFromTemplate(template: ItemTemplate) Item {
    return switch (template.i) {
        .W => |i| Item{ .Weapon = createItem(Weapon, i) },
        .A => |i| Item{ .Armor = createItem(Armor, i) },
        .P, .c => |i| Item{ .Consumable = i },
        .E => |i| Item{ .Evocable = createItem(Evocable, i) },
        .C => |i| Item{ .Cloak = i },
        .X => |i| Item{ .Aux = i },
        .List => unreachable,
        //else => err.todo(),
    };
}

pub fn findItemById(p_id: []const u8) ?*const ItemTemplate {
    const _helper = struct {
        pub fn f(id: []const u8, list: []const ItemTemplate) ?*const ItemTemplate {
            return for (list) |*entry| {
                if (entry.i.id()) |entry_id| {
                    if (mem.eql(u8, entry_id, id)) {
                        break entry;
                    }
                } else |e| if (e == error.CannotGetListID) {
                    if (f(id, entry.i.List)) |ret| break ret;
                }
            } else null;
        }
    };
    return (_helper.f)(p_id, &ALL_ITEMS);
}
