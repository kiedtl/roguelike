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
        W: *const Weapon,
        A: Armor,
        C: *const Cloak,
        X: *const Aux,
        P: *const Consumable,
        c: *const Consumable,
        r: Ring,
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
                .r => |i| i.name,
                .E => |i| i.id,
                .List => error.CannotGetListID,
            };
        }
    };
    pub const Type = meta.Tag(TemplateItem);
};
pub const RARE_ITEM_DROPS = [_]ItemTemplate{
    // Dilute this list by adding a few more common weapon
    .{ .w = 90, .i = .{ .W = &SwordWeapon } },
    // Armor and cloaks
    .{ .w = 50, .i = .{ .C = &PureGoldCloak } },
    // Bone weapons
    .{ .w = 10, .i = .{ .W = &BoneSwordWeapon } },
    .{ .w = 10, .i = .{ .W = &BoneDaggerWeapon } },
    .{ .w = 10, .i = .{ .W = &BoneMaceWeapon } },
    .{ .w = 10, .i = .{ .W = &BoneGreatMaceWeapon } },
    // Copper weapons
    .{ .w = 10, .i = .{ .W = &CopperSwordWeapon } },
    .{ .w = 10, .i = .{ .W = &CopperRapierWeapon } },
};
pub const ITEM_DROPS = [_]ItemTemplate{
    .{ .w = 1, .i = .{ .List = &RARE_ITEM_DROPS } },
    // Weapons
    .{ .w = 30, .i = .{ .W = &SwordWeapon } },
    .{ .w = 30, .i = .{ .W = &DaggerWeapon } },
    .{ .w = 25, .i = .{ .W = &RapierWeapon } },
    .{ .w = 25, .i = .{ .W = &GreatMaceWeapon } },
    .{ .w = 30, .i = .{ .W = &MorningstarWeapon } },
    .{ .w = 25, .i = .{ .W = &MonkSpadeWeapon } },
    .{ .w = 15, .i = .{ .W = &WoldoWeapon } },
    .{ .w = 10, .i = .{ .W = &GoldDaggerWeapon } },
    // Armor
    .{ .w = 20, .i = .{ .A = GambesonArmor } },
    .{ .w = 05, .i = .{ .A = SilusGambesonArmor } },
    .{ .w = 20, .i = .{ .A = HauberkArmor } },
    .{ .w = 20, .i = .{ .A = CuirassArmor } },
    .{ .w = 10, .i = .{ .A = SpikedLeatherArmor } },
    .{ .w = 10, .i = .{ .A = GoldArmor } },
    .{ .w = 05, .i = .{ .A = BrigandineArmor } },
    // Aux items
    .{ .w = 20, .i = .{ .X = &BucklerAux } },
    .{ .w = 20, .i = .{ .X = &ShieldAux } },
    .{ .w = 20, .i = .{ .X = &SpikedBucklerAux } },
    .{ .w = 20, .i = .{ .X = &GoldPendantAux } },
    .{ .w = 10, .i = .{ .X = &WolframOrbAux } },
    .{ .w = 10, .i = .{ .X = &MinersMapAux } },
    .{ .w = 10, .i = .{ .X = &DetectHeatAux } },
    .{ .w = 10, .i = .{ .X = &DetectElecAux } },
    // .{ .w = 10, .i = .{ .X = &DispelUndeadAux } },
    .{ .w = 05, .i = .{ .X = &TowerShieldAux } },
    // Potions
    .{ .w = 190, .i = .{ .P = &DisorientPotion } },
    .{ .w = 190, .i = .{ .P = &DebilitatePotion } },
    .{ .w = 190, .i = .{ .P = &IntimidatePotion } },
    .{ .w = 160, .i = .{ .P = &DistractPotion } },
    .{ .w = 160, .i = .{ .P = &BlindPotion } },
    .{ .w = 160, .i = .{ .P = &SmokePotion } },
    .{ .w = 160, .i = .{ .P = &ParalysisPotion } },
    .{ .w = 150, .i = .{ .P = &LeavenPotion } },
    .{ .w = 150, .i = .{ .P = &InvigoratePotion } },
    .{ .w = 150, .i = .{ .P = &FastPotion } },
    .{ .w = 150, .i = .{ .P = &IncineratePotion } },
    .{ .w = 140, .i = .{ .P = &RecuperatePotion } },
    .{ .w = 120, .i = .{ .P = &DecimatePotion } },
    .{ .w = 60, .i = .{ .P = &GlowPotion } },
    // Consumables
    // .{ .w = 80, .i = .{ .c = &HotPokerConsumable } },
    // .{ .w = 90, .i = .{ .c = &CoalConsumable } },
    .{ .w = 5, .i = .{ .c = &CopperIngotConsumable } },
    .{ .w = 5, .i = .{ .c = &GoldOrbConsumable } },
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
    .{ .w = 20, .i = .{ .C = &GoldCloak } },
    .{ .w = 10, .i = .{ .C = &AgilityCloak } },
    .{ .w = 10, .i = .{ .C = &WarringCloak } },
    .{ .w = 10, .i = .{ .C = &ThornyCloak } },
};
pub const NIGHT_ITEM_DROPS = [_]ItemTemplate{
    // Fluff
    .{ .w = 200, .i = .{ .P = &DisorientPotion } },
    .{ .w = 200, .i = .{ .P = &IntimidatePotion } },
    .{ .w = 170, .i = .{ .P = &BlindPotion } },
    .{ .w = 170, .i = .{ .P = &SmokePotion } },
    .{ .w = 170, .i = .{ .P = &ParalysisPotion } },
    // Weapons
    .{ .w = 30, .i = .{ .W = &ShadowSwordWeapon } },
    .{ .w = 30, .i = .{ .W = &ShadowMaulWeapon } },
    .{ .w = 30, .i = .{ .W = &ShadowMaceWeapon } },
    // Armors and cloaks
    .{ .w = 30, .i = .{ .A = ShadowMailArmor } },
    .{ .w = 30, .i = .{ .A = ShadowBrigandineArmor } },
    .{ .w = 30, .i = .{ .A = ShadowHauberkArmor } },
    .{ .w = 20, .i = .{ .A = FumingVestArmor } },
    .{ .w = 10, .i = .{ .A = SpectralVestArmor } },
    .{ .w = 10, .i = .{ .C = &SpectralCloak } },
    // Spectral orb
    .{ .w = 10, .i = .{ .c = &SpectralOrbConsumable } },
    // Auxes
    .{ .w = 20, .i = .{ .X = &ShadowShieldAux } },
    .{ .w = 10, .i = .{ .X = &SpectralCrownAux } },
    .{ .w = 05, .i = .{ .X = &EtherealShieldAux } },
};
pub const RINGS = [_]ItemTemplate{
    .{ .w = 9, .i = .{ .r = LightningRing } },
    .{ .w = 9, .i = .{ .r = CremationRing } },
    .{ .w = 9, .i = .{ .r = DistractionRing } },
    .{ .w = 9, .i = .{ .r = DamnationRing } },
    .{ .w = 9, .i = .{ .r = TeleportationRing } },
    .{ .w = 9, .i = .{ .r = InsurrectionRing } },
    .{ .w = 9, .i = .{ .r = MagnetizationRing } },
    .{ .w = 9, .i = .{ .r = AccelerationRing } },
};
pub const NIGHT_RINGS = [_]ItemTemplate{
    .{ .w = 9, .i = .{ .r = ExcisionRing } },
    .{ .w = 9, .i = .{ .r = ConjurationRing } },
};
pub const ALL_ITEMS = [_]ItemTemplate{
    .{ .w = 0, .i = .{ .List = &ITEM_DROPS } },
    .{ .w = 0, .i = .{ .List = &NIGHT_ITEM_DROPS } },
    .{ .w = 0, .i = .{ .List = &RINGS } },
    .{ .w = 0, .i = .{ .List = &NIGHT_RINGS } },
    .{ .w = 0, .i = .{ .E = SymbolEvoc } },
    .{ .w = 0, .i = .{ .A = OrnateGoldArmor } },
    .{ .w = 0, .i = .{ .X = &Earthen1ShieldAux } },
    .{ .w = 0, .i = .{ .X = &Earthen2ShieldAux } },
    .{ .w = 0, .i = .{ .r = DisintegrationRing } },
};

// Cloaks {{{
pub const Cloak = struct {
    id: []const u8,
    name: []const u8,
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
};

pub const SpectralCloak = Cloak{ .id = "cloak_spectral", .name = "spectres", .stats = .{ .Conjuration = 1 } };
pub const SilCloak = Cloak{ .id = "cloak_silicon", .name = "silicon", .resists = .{ .rFire = 25 } };
pub const FurCloak = Cloak{ .id = "cloak_fur", .name = "fur", .resists = .{ .rElec = 25 } };
pub const GoldCloak = Cloak{ .id = "cloak_gold", .name = "gold", .stats = .{ .Potential = 10 } };
pub const PureGoldCloak = Cloak{ .id = "cloak_gold_pure", .name = "pure gold", .stats = .{ .Potential = 25, .Willpower = 1 }, .resists = .{ .rElec = -25 } };
pub const ThornyCloak = Cloak{ .id = "cloak_thorny", .name = "thorns", .stats = .{ .Spikes = 1 } };
pub const AgilityCloak = Cloak{ .id = "cloak_agility", .name = "agility", .stats = .{ .Martial = 2 } };
pub const WarringCloak = Cloak{ .id = "cloak_warring", .name = "warring", .stats = .{ .Melee = 20 } };
// }}}

// Aux items {{{
pub const Aux = struct {
    id: []const u8,
    name: []const u8,

    equip_effects: []const StatusDataInfo = &[_]StatusDataInfo{},
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
    night: bool = false,
    night_stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    night_resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},

    ring_upgrade_name: ?[]const u8 = null,
    ring_upgrade_dest: ?[]const u8 = null,
    ring_upgrade_mesg: ?[]const u8 = null,
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

    .stats = .{ .Evade = 5 },
};

pub const ShieldAux = Aux{
    .id = "aux_shield",
    .name = "kite shield",

    .stats = .{ .Evade = 10, .Martial = -1 },
};

pub const Earthen1ShieldAux = Aux{
    .id = "aux_shield_earthen1",
    .name = "earthen shield",

    // .resists = .{ .rAcid = 50 }, // Uncomment when Acid damage is added
    .stats = .{ .Evade = 5 },

    .ring_upgrade_name = "disintegration",
    .ring_upgrade_dest = "aux_shield_earthen2",
    .ring_upgrade_mesg = "You fit the ring into the broken clasp.",
};

pub const Earthen2ShieldAux = Aux{
    .id = "aux_shield_earthen2",
    .name = "Shield of Earth",

    // .resists = .{ .rAcid = 50 }, // Uncomment when Acid damage is added
    .stats = .{ .Evade = 10 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .EarthenShield, .duration = .Equ },
    },
};

// Reminder via comptime :)
// Glory to comptime, hail zig. (hmm... zig hail?)
comptime {
    if (@hasField(types.Resistance, "rAcid"))
        @compileError("TODO: Add rAcid to earth shields and remove this error");
}

pub const TowerShieldAux = Aux{
    .id = "aux_shield_tower",
    .name = "tower shield",

    .resists = .{ .rFire = -25, .rElec = 25 },
    .stats = .{ .Evade = 20, .Martial = -5 },
};

pub const SpikedBucklerAux = Aux{
    .id = "aux_buckler_spiked",
    .name = "spiked buckler",

    .stats = .{ .Spikes = 1, .Evade = 5 },
};

pub const GoldPendantAux = Aux{
    .id = "aux_gold_pendant",
    .name = "gold necklace",

    .stats = .{ .Potential = 10 },
};

pub const ShadowShieldAux = Aux{
    .id = "aux_shield_shadow",
    .name = "shadow shield",

    .stats = .{ .Evade = 5, .Potential = -5 },

    .night = true,
    .night_stats = .{ .Evade = 10 },
};

pub const EtherealShieldAux = Aux{
    .id = "aux_shield_ethereal",
    .name = "ethereal shield",

    .stats = .{ .Willpower = 1, .Evade = -5, .Potential = -5 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .EtherealShield, .duration = .Equ },
    },
};

pub const SpectralCrownAux = Aux{
    .id = "aux_spectral_crown",
    .name = "spectral crown",

    .stats = .{ .Willpower = 1, .Conjuration = 2 },
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

    hated_by_nc: bool = false,

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

    pub const EvokeError = error{ HatedByNight, NoCharges, BadPosition };

    pub fn evoke(self: *Evocable, by: *Mob) EvokeError!void {
        if (by == state.player and player.hasAlignedNC() and self.hated_by_nc) {
            return error.HatedByNight;
        }

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
                .targeter = .{ .Trajectory = .{} },
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
    .hated_by_nc = true,
    .max_charges = 3,
    .rechargable = true,
    .trigger_fn = struct {
        fn f(_: *Mob, _: *Evocable) Evocable.EvokeError!void {
            const dest = ui.chooseCell(.{
                .require_seen = true,
                .targeter = .{ .Trajectory = .{} },
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
    .hated_by_nc = true,
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
                .targeter = .{ .Duo = [2]*const ui.ChooseCellOpts.Targeter{
                    &.{ .AoE1 = .{ .dist = DIST, .opts = OPTS } },
                    &.{ .Trajectory = .{} },
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

pub const LightningRing = Ring{ // {{{
    .name = "electrocution",
    .required_MP = 1,
    .effect = struct {
        pub fn f() bool {
            const rElec_pips = @intCast(usize, math.max(0, state.player.resistance(.rElec))) / 25;
            const power = 2 + (rElec_pips / 2);
            const duration = 4 + (rElec_pips * 4);

            state.player.addStatus(.RingElectrocution, power, .{ .Tmp = duration });
            return true;
        }
    }.f,
}; // }}}

pub const CremationRing = Ring{ // {{{
    .name = "cremation",
    .required_MP = 2,
    .hated_by_nc = true,
    .effect = struct {
        pub fn f() bool {
            for (&DIRECTIONS) |d|
                if (state.player.coord.move(d, state.mapgeometry)) |neighbor| {
                    fire.setTileOnFire(neighbor, null);
                    if (state.dungeon.at(neighbor).mob) |mob| {
                        // Deliberately make both friend and foe flammable
                        mob.addStatus(.Flammable, 0, .{ .Tmp = 20 });
                    }
                };
            return true;
        }
    }.f,
}; // }}}

pub const DistractionRing = Ring{ // {{{
    .name = "distraction",
    .required_MP = 8,
    .effect = struct {
        pub fn f() bool {
            const RADIUS = 4;

            var anim_buf = StackBuffer(Coord, (RADIUS * 2) * (RADIUS * 2)).init(null);
            var dijk = dijkstra.Dijkstra.init(state.player.coord, state.mapgeometry, RADIUS, state.is_walkable, .{ .ignore_mobs = true, .only_if_breaks_lof = true }, state.GPA.allocator());
            defer dijk.deinit();
            while (dijk.next()) |coord2| {
                if (utils.getHostileAt(state.player, coord2)) |hostile| {
                    hostile.addStatus(.Amnesia, 0, .{ .Tmp = 7 });
                } else |_| {}
                anim_buf.append(coord2) catch unreachable;
            }

            return true;

            // TODO: use beams-ring-amnesia particle effect
            // ui.Animation.blink(anim_buf.constSlice(), '?', colors.AQUAMARINE, .{}).apply();
        }
    }.f,
}; // }}}

pub const DamnationRing = Ring{ // {{{
    .name = "damnation",
    .required_MP = 4,
    .hated_by_nc = true,
    .effect = struct {
        pub fn f() bool {
            const rFire_pips = @intCast(usize, math.max(0, state.player.resistance(.rFire))) / 25;
            const power = 2 + rFire_pips;
            const duration = 4 + (rFire_pips * 4);

            state.player.addStatus(.RingDamnation, power, .{ .Tmp = duration });
            return true;
        }
    }.f,
}; // }}}

pub const TeleportationRing = Ring{ // {{{
    .name = "teleportation",
    .required_MP = 4,
    .effect = struct {
        pub fn f() bool {
            state.player.addStatus(.RingTeleportation, 0, .{ .Tmp = 5 });
            return true;
        }
    }.f,
}; // }}}

pub const InsurrectionRing = Ring{ // {{{
    .name = "insurrection",
    .required_MP = 3,
    .hated_by_nc = true,
    .effect = struct {
        pub fn f() bool {
            const lifetime = 14;
            const max_corpses = 3;

            var corpses_raised: usize = 0;
            while (utils.getNearestCorpse(state.player)) |corpse_coord| {
                const corpse_mob = state.dungeon.at(corpse_coord).surface.?.Corpse;
                if (corpse_mob.raiseAsUndead(corpse_coord)) {
                    corpses_raised += 1;

                    corpse_mob.addStatus(.Lifespan, 0, .{ .Tmp = lifetime });
                    state.player.addUnderling(corpse_mob);

                    // Refraining from deleting this in case I want to bring it back
                    //
                    // corpse_mob.addStatus(.Blind, 0, .Prm);
                    // ai.updateEnemyKnowledge(corpse_mob, stt.mobs[0].?, null);
                }

                if (corpses_raised == max_corpses)
                    break;
            }

            if (corpses_raised > 0) {
                state.message(.Info, "Nearby corpses rise to defend you!", .{});
            } else {
                state.message(.Info, "You feel lonely for a moment.", .{});
            }

            return true;
        }
    }.f,
}; // }}}

pub const MagnetizationRing = Ring{ // {{{
    .name = "magnetization",
    .required_MP = 5,
    .effect = struct {
        pub fn f() bool {
            const magnet = state.dungeon.at(ui.chooseCell(.{
                .max_distance = 1,
                .require_enemy_on_tile = true,
            }) orelse return false).mob.?;

            var gen = Generator(Rect.rectIter).init(state.mapRect(state.player.coord.z));
            while (gen.next()) |coord| if (state.player.cansee(coord)) {
                if (state.dungeon.at(coord).mob) |othermob| {
                    if (othermob != magnet and
                        othermob.isHostileTo(state.player))
                    {
                        const d = othermob.coord.closestDirectionTo(magnet.coord, state.mapgeometry);
                        combat.throwMob(state.player, othermob, d, othermob.coord.distance(magnet.coord));
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
                state.message(.Info, "{c} becomes briefly magnetic!", .{magnet});

            return true;
        }
    }.f,
}; // }}}

pub const AccelerationRing = Ring{ // {{{
    .name = "acceleration",
    .required_MP = 2,
    .effect = struct {
        pub fn f() bool {
            const ev = @intCast(usize, state.player.stat(.Evade));
            const duration = math.max(3, ev / 4);
            state.player.addStatus(.RingAcceleration, 0, .{ .Tmp = duration });

            if (utils.adjacentHostiles(state.player) == 0) {
                state.message(.Info, "You begin moving faster.", .{});
            } else {
                state.message(.Info, "You feel like you could be moving faster.", .{});
            }

            return true;

            // Too bad we return immediately if the player cancels, this message was nice flavor
            //state.message(.Info, "A haftless sword seems to appear mid-air, then disappears abruptly.", .{});
        }
    }.f,
}; // }}}

pub const DisintegrationRing = Ring{ // {{{
    .name = "disintegration",
    .color = 0xd5aa6a,
    .required_MP = 4,
    .effect = struct {
        pub fn f() bool {
            const will = @intCast(usize, state.player.stat(.Willpower));

            const dest = ui.chooseCell(.{
                .require_seen = false,
                .targeter = .{ .Trajectory = .{ .require_lof = false } },
                .max_distance = will,
            }) orelse return false;
            const overhang = will - state.player.coord.distance(dest);
            const path = state.player.coord.drawLine(dest, state.mapgeometry, overhang);

            // Get dest of bolt, including overhang
            //
            // Hacky, might not work all the time since I'm not sure if there's
            // a guarantee that the trajectory will be the same
            //
            const anim_dest = path.data[path.len - 1];
            ui.Animation.apply(.{ .Particle = .{ .name = "zap-disintegrate", .coord = state.player.coord, .target = .{ .C = anim_dest } } });

            var i: usize = will;
            var d: usize = 2; // damage
            var v: usize = 0; // victims so far
            for (path.constSlice()) |coord| {
                if (coord.eq(state.player.coord)) continue;

                if (state.is_walkable(coord, .{ .only_if_breaks_lof = true })) {
                    if (v > 0)
                        d -|= 1;
                } else {
                    if (state.dungeon.at(coord).mob) |mob| {
                        mob.takeDamage(.{
                            .amount = d,
                            .by_mob = state.player,
                            .kind = .Irresistible,
                            .blood = false,
                            .source = .RangedAttack,
                            .stealth = v == 0,
                        }, .{
                            .strs = &[_]DamageStr{
                                _dmgstr(10, "zap", "zaps", ""),
                                _dmgstr(99, "disintegrate", "disintegrates", ""),
                                _dmgstr(200, "annihilate", "annihilates", ""),
                            },
                        });
                        v += 1;
                    } else if (state.dungeon.at(coord).surface) |surface| {
                        // It's not walkable
                        if (surface != .Stair) {
                            surface.destroy(coord);
                            if (v == 0)
                                d += 1;
                        }
                    } else if (state.dungeon.at(coord).type == .Wall) {
                        state.dungeon.at(coord).type = .Floor;
                        if (v == 0)
                            d += 3;
                    }
                }

                i -= 1;
                if (i == 0 or d == 0) break;
            }

            return true;
        }
    }.f,
}; // }}}

pub const ExcisionRing = Ring{ // {{{
    .name = "excision",
    .required_MP = 5,
    .effect = struct {
        pub fn f() bool {
            const n = ui.chooseCell(.{ .max_distance = 1, .require_walkable = .{} }) orelse return false;
            const s = mobs.placeMob(state.GPA.allocator(), &mobs.SpectralSwordTemplate, n, .{});
            state.player.addUnderling(s);
            state.message(.Info, "A spectral blade appears mid-air, hovering precariously.", .{});

            const will = @intCast(usize, state.player.stat(.Willpower));
            state.player.addStatus(.RingExcision, 0, .{ .Tmp = will * 2 });

            return true;

            // Too bad we return immediately if the player cancels, this message was nice flavor
            //state.message(.Info, "A haftless sword seems to appear mid-air, then disappears abruptly.", .{});
        }
    }.f,
}; // }}}

pub const ConjurationRing = Ring{ // {{{
    .name = "conjuration",
    .required_MP = 2,
    .stats = .{ .Conjuration = 2 },
    .effect = struct {
        pub fn f() bool {
            const will = @intCast(usize, state.player.stat(.Willpower));
            const duration = math.max(1, will / 2);
            state.player.addStatus(.RingConjuration, 0, .{ .Tmp = duration });
            return true;
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
    hated_by_nc: bool = false,

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
        hated_by_nc: bool,
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
            .hated_by_nc = hated_by_nc,
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

pub const GoldOrbConsumable = Consumable{
    .id = "cons_gold_orb",
    .name = "gold orb",
    .effects = &[_]Consumable.Effect{
        .{ .Resist = .{ .r = .rElec, .change = 25 } },
        .{ .Stat = .{ .s = .Potential, .change = 25 } },
    },
    .color = 0xffd700,
    .verbs_player = &[_][]const u8{ "choke down", "swallow" },
    .verbs_other = &[_][]const u8{"chokes down"},
};

pub const SpectralOrbConsumable = Consumable{
    .id = "cons_spectral_orb",
    .name = "spectral orb",
    .effects = &[_]Consumable.Effect{
        .{ .Custom = struct {
            pub fn f(mob: ?*Mob, _: Coord) void {
                assert(mob.? == state.player);
                const next_aug = for (state.player_conj_augments) |aug, i| {
                    if (!aug.received)
                        break i;
                } else {
                    state.message(.Info, "Nothing happens. You feel a dryness within...", .{});
                    return;
                };
                state.player_conj_augments[next_aug].received = true;
                state.message(.Info, "[$oConjuration augment$.] {s}", .{state.player_conj_augments[next_aug].a.description()});
            }
        }.f },
    },
    .color = 0xcacbca,
    .verbs_player = &[_][]const u8{"use"},
    .verbs_other = &[_][]const u8{"[this is a bug]"},
};

pub const GlueTrapKit = Consumable.createTrapKit("kit_trap_glue", "glue trap", false, struct {
    pub fn f(_: *Machine, mob: *Mob) void {
        mob.addStatus(.Held, 0, .{ .Tmp = 20 });
    }
}.f);

pub const AirblastTrapKit = Consumable.createTrapKit("kit_trap_airblast", "airblast trap", false, struct {
    pub fn f(_: *Machine, mob: *Mob) void {
        combat.throwMob(null, mob, rng.chooseUnweighted(Direction, &DIRECTIONS), 10);
    }
}.f);

pub const ShockTrapKit = Consumable.createTrapKit("kit_trap_shock", "shock trap", false, struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        explosions.elecBurst(machine.coord, 5, state.player);
    }
}.f);

pub const BigFireTrapKit = Consumable.createTrapKit("kit_trap_bigfire", "incineration trap", true, struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        explosions.fireBurst(machine.coord, 7, .{});
    }
}.f);

pub const FireTrapKit = Consumable.createTrapKit("kit_trap_fire", "fire trap", true, struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        explosions.fireBurst(machine.coord, 3, .{});
    }
}.f);

pub const EmberlingTrapKit = Consumable.createTrapKit("kit_trap_emberling", "emberling trap", false, struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        mobs.placeMobSurrounding(machine.coord, &mobs.EmberlingTemplate, .{ .no_squads = true, .faction = state.player.faction });
    }
}.f);

pub const SparklingTrapKit = Consumable.createTrapKit("kit_trap_sparkling", "sparkling trap", false, struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        mobs.placeMobSurrounding(machine.coord, &mobs.SparklingTemplate, .{ .no_squads = true, .faction = state.player.faction });
    }
}.f);

pub const MineKit = Consumable{
    .id = "kit_mine",
    .name = "mine kit",
    .effects = &[_]Consumable.Effect{.{ .Kit = &surfaces.Mine }},
    .color = 0xffd7d7,
    .verbs_player = Consumable.VERBS_PLAYER_KIT,
    .verbs_other = Consumable.VERBS_OTHER_KIT,
    .hated_by_nc = true,
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
    .hated_by_nc = true,
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
    .hated_by_nc = true,
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
    .hated_by_nc = true,
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
    .stats = .{ .Evade = -5, .Martial = -1 },
};

pub const BrigandineArmor = Armor{
    .id = "brigandine_armor",
    .name = "brigandine",
    .resists = .{ .Armor = 25 },
    .stats = .{ .Melee = 10, .Martial = 1 },
};

pub const GambesonArmor = Armor{
    .id = "gambeson_armor",
    .name = "gambeson",
    .resists = .{ .Armor = 15 },
};

pub const SilusGambesonArmor = Armor{
    .id = "silus_gambeson_armor",
    .name = "silus gambeson",
    .resists = .{ .Armor = 15, .rFire = 25 },
};

pub const SpikedLeatherArmor = Armor{
    .id = "spiked_leather_armor",
    .name = "spiked leather armor",
    .resists = .{ .Armor = 15 },
    .stats = .{ .Spikes = 1, .Martial = -1 },
};

pub const GoldArmor = Armor{
    .id = "gold_armor",
    .name = "golden armor",
    .resists = .{ .Armor = 05 },
    .stats = .{ .Potential = 10 },
};

pub const OrnateGoldArmor = Armor{
    .id = "ornate_gold_armor",
    .name = "ornate golden armor",
    .resists = .{ .Armor = 10 },
    .stats = .{ .Potential = 25, .Willpower = 2, .Melee = 10 },
};

pub const ShadowMailArmor = Armor{
    .id = "shadow_mail_armor",
    .name = "shadow mail",
    .stats = .{ .Potential = -10 },
    .resists = .{ .Armor = 15 },

    .night = true,
    .night_stats = .{ .Potential = -10 },
    .night_resists = .{ .rFire = -25, .Armor = 35 },
};

pub const ShadowHauberkArmor = Armor{
    .id = "shadow_hauberk_armor",
    .name = "shadow hauberk",
    .resists = .{ .Armor = 10 },
    .stats = .{ .Potential = -10 },

    .night = true,
    .night_resists = .{ .Armor = 25 },
    .night_stats = .{ .Evade = -5, .Martial = -1, .Potential = 10 },
};

pub const ShadowBrigandineArmor = Armor{
    .id = "shadow_brigandine_armor",
    .name = "shadow brigandine",
    .resists = .{ .Armor = 10 },
    .stats = .{ .Melee = 5, .Martial = 1, .Potential = -10 },

    .night = true,
    .night_resists = .{ .Armor = 25 },
    .night_stats = .{ .Melee = 10, .Martial = 2, .Potential = -10 },
};

pub const FumingVestArmor = Armor{
    .id = "fuming_vest_armor",
    .name = "fuming vest",

    .resists = .{ .rFire = -25 },

    .night = true,
    .night_resists = .{ .Armor = 5, .rFire = -25 },
    .night_stats = .{ .Melee = 10, .Willpower = 1 },

    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .FumesVest, .duration = .Equ },
    },
};

pub const SpectralVestArmor = Armor{
    .id = "spectral_vest_armor",
    .name = "spectral vest",

    .stats = .{ .Melee = 10, .Conjuration = 1 },
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
    .martial = true,
    .stats = .{ .Evade = 10, .Martial = 2 },
    .strs = &SLASHING_STRS,
};
pub const BoneSwordWeapon = Weapon.createBoneWeapon(&SwordWeapon, .{});
pub const CopperSwordWeapon = Weapon.createCopperWeapon(&SwordWeapon, .{});

pub const ShadowSwordWeapon = Weapon{
    .id = "shadow_sword",
    .name = "shadow sword",
    .damage = 1,
    .martial = true,
    .stats = .{ .Evade = 10, .Martial = 2, .Potential = -5 },
    .ego = .NC_Insane,
    .strs = &SLASHING_STRS,
};

pub const DaggerWeapon = Weapon{
    .id = "dagger",
    .name = "dagger",
    .damage = 1,
    .martial = true,
    .stats = .{ .Martial = 1 },
    .ego = .Swap,
    .strs = &PIERCING_STRS,
};
pub const BoneDaggerWeapon = Weapon.createBoneWeapon(&DaggerWeapon, .{});

pub const GoldDaggerWeapon = Weapon{
    .id = "dagger_gold",
    .name = "golden dagger",
    .damage = 1,
    .stats = .{ .Melee = -25, .Potential = 25 },
    .ego = .Drain,
    .strs = &PIERCING_STRS,
};

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

pub const MonkSpadeWeapon = Weapon{
    .id = "monk_spade",
    .name = "monk's spade",
    .damage = 1,
    .knockback = 2,
    .stats = .{ .Melee = 20 },
    .strs = &PIERCING_STRS,
};

pub const WoldoWeapon = Weapon{
    .id = "woldo",
    .name = "woldo",
    .damage = 3,
    .martial = true,
    .stats = .{ .Melee = -15, .Martial = 2 },
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
    .effects = &[_]StatusDataInfo{
        .{ .status = .Fear, .duration = .{ .Tmp = 2 } },
    },
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
    .stats = .{ .Potential = -5 },
    .ego = .NC_MassPara,
    .strs = &CRUSHING_STRS,
};

pub const ShadowMaulWeapon = Weapon{
    .id = "shadow_maul",
    .name = "shadow maul",
    .damage = 2,
    .stats = .{ .Potential = -5 },
    .ego = .NC_Duplicate,
    .strs = &CRUSHING_STRS,
};

// }}}

// ----------------------------------------------------------------------------

pub fn createItem(comptime T: type, item: T) *T {
    const list = switch (T) {
        Armor => &state.armors,
        Ring => &state.rings,
        Evocable => &state.evocables,
        else => @compileError("uh wat"),
    };
    const it = list.appendAndReturn(item) catch err.oom();
    if (T == Evocable) it.charges = it.max_charges;
    return it;
}

pub fn createItemFromTemplate(template: ItemTemplate) Item {
    return switch (template.i) {
        .W => |i| Item{ .Weapon = i },
        .A => |i| Item{ .Armor = createItem(Armor, i) },
        .P, .c => |i| Item{ .Consumable = i },
        .r => |i| Item{ .Ring = createItem(Ring, i) },
        .E => |i| Item{ .Evocable = createItem(Evocable, i) },
        .C => |i| Item{ .Cloak = i },
        .X => |i| Item{ .Aux = i },
        .List => unreachable,
        //else => err.todo(),
    };
}

pub fn findItemById(p_id: []const u8) ?ItemTemplate {
    const _helper = struct {
        pub fn f(id: []const u8, list: []const ItemTemplate) ?ItemTemplate {
            return for (list) |entry| {
                if (id[0] == '=') {
                    if (entry.i != .r and entry.i != .List) continue;
                } else {
                    if (entry.i == .r) continue;
                }
                if (entry.i.id()) |entry_id| {
                    const match_against = if (id[0] == '=') id[1..] else id;
                    if (mem.eql(u8, entry_id, match_against)) break entry;
                } else |e| if (e == error.CannotGetListID) {
                    if (f(id, entry.i.List)) |ret| break ret;
                }
            } else null;
        }
    };
    return (_helper.f)(p_id, &ALL_ITEMS);
}
