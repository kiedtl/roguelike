const std = @import("std");
const math = std.math;
const enums = std.enums;
const meta = std.meta;
const mem = std.mem;
const assert = std.debug.assert;

const colors = @import("colors.zig");
const combat = @import("combat.zig");
const err = @import("err.zig");
const explosions = @import("explosions.zig");
const fire = @import("fire.zig");
const fov = @import("fov.zig");
const gas = @import("gas.zig");
const display = @import("display.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const types = @import("types.zig");
const ringbuffer = @import("ringbuffer.zig");

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
const Status = types.Status;
const Machine = types.Machine;
const Direction = types.Direction;

const DIRECTIONS = types.DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const LinkedList = @import("list.zig").LinkedList;

// Items to be dropped into rooms for the player's use.
//
pub const ItemTemplate = struct {
    w: usize,
    i: union(enum) { W: Weapon, A: Armor, C: *const Cloak, P: *const Consumable, E: Evocable },
};
pub const ITEM_DROPS = [_]ItemTemplate{
    // Weapons
    .{ .w = 020, .i = .{ .W = SwordWeapon } },
    .{ .w = 020, .i = .{ .W = DaggerWeapon } },
    .{ .w = 010, .i = .{ .W = StilettoWeapon } },
    .{ .w = 015, .i = .{ .W = RapierWeapon } },
    .{ .w = 001, .i = .{ .W = AxeWeapon } },
    .{ .w = 015, .i = .{ .W = QuarterstaffWeapon } },
    .{ .w = 020, .i = .{ .W = MaceWeapon } },
    .{ .w = 015, .i = .{ .W = GreatMaceWeapon } },
    .{ .w = 020, .i = .{ .W = MorningstarWeapon } },
    .{ .w = 020, .i = .{ .W = HalberdWeapon } },
    .{ .w = 020, .i = .{ .W = GlaiveWeapon } },
    .{ .w = 015, .i = .{ .W = MonkSpadeWeapon } },
    .{ .w = 005, .i = .{ .W = WoldoWeapon } },
    // Armor
    .{ .w = 010, .i = .{ .A = GambesonArmor } },
    .{ .w = 010, .i = .{ .A = LeatherArmor } },
    .{ .w = 010, .i = .{ .A = HauberkArmor } },
    .{ .w = 010, .i = .{ .A = ScalemailArmor } },
    // Potions
    .{ .w = 170, .i = .{ .P = &RecuperatePotion } },
    .{ .w = 170, .i = .{ .P = &ConfusionPotion } },
    .{ .w = 170, .i = .{ .P = &PoisonPotion } },
    .{ .w = 170, .i = .{ .P = &InvigoratePotion } },
    .{ .w = 140, .i = .{ .P = &SmokePotion } },
    .{ .w = 140, .i = .{ .P = &ParalysisPotion } },
    .{ .w = 140, .i = .{ .P = &FastPotion } },
    .{ .w = 130, .i = .{ .P = &IncineratePotion } },
    .{ .w = 100, .i = .{ .P = &DecimatePotion } },
    // Consumables
    .{ .w = 080, .i = .{ .P = &HotPokerConsumable } },
    .{ .w = 090, .i = .{ .P = &CoalConsumable } },
    .{ .w = 050, .i = .{ .P = &CopperIngotConsumable } },
    // Kits
    .{ .w = 030, .i = .{ .P = &FireTrapKit } },
    .{ .w = 030, .i = .{ .P = &ShockTrapKit } },
    .{ .w = 020, .i = .{ .P = &AirblastTrapKit } },
    .{ .w = 005, .i = .{ .P = &MineKit } },
    .{ .w = 002, .i = .{ .P = &BigFireTrapKit } },
    // Evocables
    .{ .w = 020, .i = .{ .E = IronSpikeEvoc } },
    .{ .w = 015, .i = .{ .E = EldritchLanternEvoc } },
    // Cloaks
    .{ .w = 020, .i = .{ .C = &SilCloak } },
    .{ .w = 020, .i = .{ .C = &FurCloak } },
    .{ .w = 020, .i = .{ .C = &VelvetCloak } },
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

pub const Cloak = struct {
    id: []const u8,
    name: []const u8,
    stats: enums.EnumFieldStruct(Stat, isize, 0) = .{},
    resists: enums.EnumFieldStruct(Resistance, isize, 0) = .{},
};

pub const SilCloak = Cloak{ .id = "silicon", .name = "silicon", .resists = .{ .rFire = 25 } };
pub const FurCloak = Cloak{ .id = "fur", .name = "fur", .resists = .{ .rElec = 25 } };
pub const VelvetCloak = Cloak{ .id = "velvet", .name = "velvet", .stats = .{ .Sneak = 2 } };

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
    .name = "poisoned javelin",
    .color = 0xffd7d7,
    .damage = 2,
    .effect = .{
        .Status = .{
            .status = .Poison,
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
    last_used: usize = 0,

    // Whether to destroy the evocable when it's finished.
    delete_when_inert: bool = false,

    // Whether a recharging station should recharge it.
    //
    // Must be false if max_charges == 0.
    rechargable: bool = true,

    purpose: Purpose,

    trigger_fn: fn (*Mob, *Evocable) EvokeError!void,

    // The AI uses this to determine whether to active an evocable in a mob's
    // inventory.
    pub const Purpose = enum {
        // The evocable can be activated during a fight, to debuff enemies.
        EnemyDebuff,

        // The evocable can be activated during a fight, to buff allies.
        AllyBuff,

        // The evocable can be activated during a fight, to buff self.
        SelfBuff,

        Other,
    };

    // TODO: targeting functionality

    pub const EvokeError = error{ NoCharges, BadPosition };

    pub fn evoke(self: *Evocable, by: *Mob) EvokeError!void {
        if (self.max_charges == 0 or self.charges > 0) {
            if (self.max_charges > 0)
                self.charges -= 1;
            self.last_used = state.ticks;
            try self.trigger_fn(by, self);
        } else {
            return error.NoCharges;
        }
    }
};

pub const IronSpikeEvoc = Evocable{
    .id = "iron_spike",
    .name = "iron spike",
    .tile_fg = 0xcacbca,
    .max_charges = 1,
    .delete_when_inert = true,
    .rechargable = false,
    .purpose = .Other,
    .trigger_fn = _triggerIronSpikeEvoc,
};

fn _triggerIronSpikeEvoc(mob: *Mob, _: *Evocable) Evocable.EvokeError!void {
    assert(mob == state.player);

    const dest = display.chooseCell(.{}) orelse return error.BadPosition;
    if (dest.distance(mob.coord) > 1) {
        display.drawAlertThenLog("Your arms aren't that long!", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).surface == null) {
        display.drawAlertThenLog("There's nothing there to break!", .{});
        return error.BadPosition;
    } else if (meta.activeTag(state.dungeon.at(dest).surface.?) != .Machine or
        !state.dungeon.at(dest).surface.?.Machine.can_be_jammed)
    {
        display.drawAlertThenLog("You can't jam that!", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).surface.?.Machine.jammed) {
        display.drawAlertThenLog("That's already jammed!", .{});
        return error.BadPosition;
    }

    const machine = state.dungeon.at(dest).surface.?.Machine;
    machine.jammed = true;
    machine.power = 0;

    state.message(.Info, "You jam the {s}...", .{machine.name});
}

pub const EldritchLanternEvoc = Evocable{
    .id = "eldritch_lantern",
    .name = "eldritch lantern",
    .tile_fg = 0x23abef,
    .max_charges = 5,
    .purpose = .EnemyDebuff,
    .trigger_fn = _triggerEldritchLantern,
};
fn _triggerEldritchLantern(mob: *Mob, _: *Evocable) Evocable.EvokeError!void {
    var affected: usize = 0;
    var player_was_affected: bool = false;

    if (mob == state.player) {
        state.message(.Info, "The eldritch lantern flashes brilliantly!", .{});
    } else if (state.player.cansee(mob.coord)) {
        state.message(.Info, "The {s} flashes an eldritch lantern!", .{mob.displayName()});
    }

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;

        const coord = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(coord).mob) |othermob| {
            // Treat evoker specially later on
            if (mob == othermob)
                continue;

            if (!othermob.cansee(mob.coord))
                continue;

            othermob.addStatus(.Daze, 0, .{ .Tmp = 10 });

            affected += 1;
            if (othermob == state.player)
                player_was_affected = true;
        }
    };

    mob.addStatus(.Daze, 0, .{ .Tmp = rng.range(usize, 1, 4) });
    mob.makeNoise(.Explosion, .Medium);
}

pub const WarningHornEvoc = Evocable{
    .id = "warning_horn",
    .name = "warning horn",
    .tile_fg = 0xefab23,
    .max_charges = 3,
    .purpose = .SelfBuff,
    .trigger_fn = _triggerWarningHorn,
};
fn _triggerWarningHorn(mob: *Mob, _: *Evocable) Evocable.EvokeError!void {
    mob.makeNoise(.Alarm, .Loudest);

    if (mob == state.player) {
        state.message(.Info, "You blow the horn!", .{});
    } else if (state.player.cansee(mob.coord)) {
        state.message(.Info, "The {s} blows its warning horn!", .{mob.displayName()});
    }
}

// }}}

pub const PatternChecker = struct {
    pub const MAX_TURNS = 10;
    pub const Func = fn (*Mob, *State) bool;

    pub const State = struct {
        history: ringbuffer.RingBuffer(bool, MAX_TURNS),
        mobs: [10]?*Mob = undefined,
        directions: [10]?Direction = undefined,
        coords: [10]?Coord = undefined,
    };

    turns: usize,
    funcs: [MAX_TURNS]Func,
    state: [MAX_TURNS]State = undefined,

    pub fn init(self: *PatternChecker) void {
        for (self.state) |*state_set| {
            state_set.history.init();
            mem.set(?*Mob, state_set.mobs[0..], null);
            mem.set(?Direction, state_set.directions[0..], null);
            mem.set(?Coord, state_set.coords[0..], null);
        }
    }

    pub fn _getConsecutiveTrues(self: *State) usize {
        var consecutive_true: usize = 0;
        {
            var iter = self.history.iterator();
            while (iter.next()) |item|
                if (item) {
                    consecutive_true += 1;
                } else {
                    break;
                };
        }
        return consecutive_true;
    }

    pub fn checkState(self: *PatternChecker, mob: *Mob) bool {
        for (self.state) |*state_i, i| {
            if (state.ticks < i) continue;
            const consecs = _getConsecutiveTrues(state_i);
            assert(consecs < self.turns);
            const r = (self.funcs[consecs])(mob, state_i);
            state_i.history.append(r);
            if (_getConsecutiveTrues(state_i) == self.turns) {
                self.init();
                return true;
            }
        }
        return false;
    }
};

pub const LightningRing = Ring{
    .name = "electrocution",
    .pattern_checker = .{
        // mobs[0] is the attacked enemy.
        // coords[0] is the original coord of the attacked enemy.
        // directions[0] is the attacked direction.
        // directions[1] is the first move away from the enemy.
        .turns = 3,
        .funcs = [_]PatternChecker.Func{
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State) bool {
                    const cur = mob.activities.current().?;
                    const r = cur == .Attack and
                        !cur.Attack.direction.is_diagonal();
                    if (r) {
                        stt.mobs[0] = cur.Attack.who;
                        stt.directions[0] = cur.Attack.direction;
                        stt.coords[0] = cur.Attack.coord;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State) bool {
                    const cur = mob.activities.current().?;
                    const r = cur == .Move and
                        !cur.Move.is_diagonal() and
                        cur.Move == stt.directions[0].?.opposite();
                    if (r) {
                        stt.directions[1] = cur.Move;
                    }
                    return r;
                }
            }.f,
            struct {
                pub fn f(mob: *Mob, stt: *PatternChecker.State) bool {
                    const cur = mob.activities.current().?;
                    const r = cur == .Move and
                        !cur.Move.is_diagonal() and
                        (cur.Move == stt.directions[1].?.turnleft() or
                        cur.Move == stt.directions[1].?.turnright()) and
                        mob.coord.distance(stt.coords[0].?) == 2 and
                        mob.coord.distance(stt.mobs[0].?.coord) == 1; // he's still there?
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
        pub fn f(self: *Mob) void {
            for (&DIAGONAL_DIRECTIONS) |d|
                if (self.coord.move(d, state.mapgeometry)) |neighbor| {
                    if (state.dungeon.at(neighbor).mob) |target| {
                        if (!target.isHostileTo(self)) continue;
                        target.takeDamage(.{
                            .amount = @intToFloat(f64, 3),
                            .by_mob = self,
                            .kind = .Electric,
                        }, .{ .noun = "Lightning" });
                    }
                };
        }
    }.f,
};

// Consumables {{{
//

pub const Consumable = struct {
    id: []const u8,
    name: []const u8,
    color: u32,
    effects: []const Effect,
    is_potion: bool = false,
    throwable: bool = false,
    dip_effect: ?StatusDataInfo = null,
    verbs_player: []const []const u8,
    verbs_other: []const []const u8,

    const Effect = union(enum) {
        Status: Status,
        Gas: usize,
        Kit: *const Machine,
        Damage: struct { amount: usize, kind: Damage.DamageKind },
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
                    .pathfinding_penalty = 10,
                },
            }},
            .color = colors.GOLD,
            .verbs_player = Consumable.VERBS_PLAYER_KIT,
            .verbs_other = Consumable.VERBS_OTHER_KIT,
        };
    }
};

pub const HotPokerConsumable = Consumable{
    .id = "cons_hot_poker",
    .name = "red-hot poker",
    .effects = &[_]Consumable.Effect{
        .{ .Heal = 20 },
        .{ .Damage = .{ .amount = 20, .kind = .Fire } },
    },
    .color = 0xdd1010,
    .verbs_player = Consumable.VERBS_PLAYER_CAUT,
    .verbs_other = Consumable.VERBS_OTHER_CAUT,
};

pub const CoalConsumable = Consumable{
    .id = "cons_coal",
    .name = "burning coal",
    .effects = &[_]Consumable.Effect{
        .{ .Heal = 10 },
        .{ .Damage = .{ .amount = 10, .kind = .Fire } },
    },
    .color = 0xdd3a3a,
    .verbs_player = Consumable.VERBS_PLAYER_CAUT,
    .verbs_other = Consumable.VERBS_OTHER_CAUT,
};

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
        explosions.fireBurst(machine.coord, 7);
    }
}.f);

pub const FireTrapKit = Consumable.createTrapKit("kit_trap_fire", "fire trap", struct {
    pub fn f(machine: *Machine, _: *Mob) void {
        explosions.fireBurst(machine.coord, 3);
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

pub const ConfusionPotion = Consumable{
    .id = "potion_confusion",
    .name = "potion of confuzzlementation",
    .effects = &[_]Consumable.Effect{.{ .Gas = gas.Confusion.id }},
    .dip_effect = .{ .status = .Confusion, .duration = .{ .Tmp = 5 } },
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
    .dip_effect = .{ .status = .Paralysis, .duration = .{ .Tmp = 3 } },
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
    .dip_effect = .{ .status = .Fast, .duration = .{ .Tmp = 5 } },
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
    .dip_effect = .{ .status = .Recuperate, .duration = .{ .Tmp = 5 } },
    .is_potion = true,
    .color = 0xffffff,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
};

pub const PoisonPotion = Consumable{
    .id = "potion_poison",
    .name = "potion of coagulation",
    .effects = &[_]Consumable.Effect{.{ .Gas = gas.Poison.id }},
    .dip_effect = .{ .status = .Poison, .duration = .{ .Tmp = 5 } },
    .is_potion = true,
    .color = 0xa7e234,
    .verbs_player = Consumable.VERBS_PLAYER_POTION,
    .verbs_other = Consumable.VERBS_OTHER_POTION,
    .throwable = true,
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
    .dip_effect = .{ .status = .Fire, .duration = .{ .Tmp = 5 } },
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

fn triggerIncineratePotion(_: ?*Mob, coord: Coord) void {
    explosions.fireBurst(coord, 4);
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

pub const HauberkArmor = Armor{
    .id = "chainmail_armor",
    .name = "chainmail",
    .resists = .{ .Armor = 30 },
    .stats = .{ .Speed = 10 },
};

pub const ScalemailArmor = Armor{
    .id = "scalemail_armor",
    .name = "scale mail",
    .resists = .{ .Armor = 25 },
    .stats = .{ .Evade = -10 },
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

pub const LeatherArmor = Armor{
    .id = "leather_armor",
    .name = "leather",
    .resists = .{ .Armor = 20 },
};

// }}}

pub fn _dmgstr(p: usize, vself: []const u8, vother: []const u8, vdeg: []const u8) DamageStr {
    return .{ .dmg_percent = p, .verb_self = vself, .verb_other = vother, .verb_degree = vdeg };
}

pub const CRUSHING_STRS = [_]DamageStr{
    _dmgstr(005, "whack", "whacks", ""),
    _dmgstr(010, "cudgel", "cudgels", ""),
    _dmgstr(030, "bash", "bashes", ""),
    _dmgstr(040, "hit", "hits", ""),
    _dmgstr(050, "hammer", "hammers", ""),
    _dmgstr(060, "batter", "batters", ""),
    _dmgstr(070, "thrash", "thrashes", ""),
    _dmgstr(130, "smash", "smashes", " like an overripe mango"),
    _dmgstr(160, "flatten", "flattens", " like a pancake"),
    _dmgstr(190, "flatten", "flattens", " like a chapati"),
    _dmgstr(200, "grind", "grinds", " into powder"),
    _dmgstr(400, "pulverise", "pulverises", " into a bloody mist"),
};
pub const SLASHING_STRS = [_]DamageStr{
    _dmgstr(040, "hit", "hits", ""),
    _dmgstr(050, "slash", "slashes", ""),
    _dmgstr(090, "chop", "chops", " into pieces"),
    _dmgstr(110, "chop", "chops", " into tiny pieces"),
    _dmgstr(150, "slice", "slices", " into ribbons"),
    _dmgstr(200, "cut", "cuts", " asunder"),
    _dmgstr(250, "mince", "minces", " like boiled poultry"),
};
pub const PIERCING_STRS = [_]DamageStr{
    _dmgstr(005, "prick", "pricks", ""),
    _dmgstr(030, "hit", "hits", ""),
    _dmgstr(040, "impale", "impales", ""),
    _dmgstr(050, "skewer", "skewers", ""),
    _dmgstr(060, "perforate", "perforates", ""),
    _dmgstr(100, "skewer", "skewers", " like a kebab"),
    _dmgstr(200, "spit", "spits", " like a pig"),
    _dmgstr(300, "perforate", "perforates", " like a sieve"),
};
pub const LACERATING_STRS = [_]DamageStr{
    _dmgstr(020, "whip", "whips", ""),
    _dmgstr(040, "lash", "lashes", ""),
    _dmgstr(050, "lacerate", "lacerates", ""),
    _dmgstr(070, "shred", "shreds", ""),
    _dmgstr(090, "shred", "shreds", " like wet paper"),
    _dmgstr(150, "mangle", "mangles", " beyond recognition"),
};

pub const BITING_STRS = [_]DamageStr{
    _dmgstr(080, "bite", "bites", ""),
    _dmgstr(081, "mangle", "mangles", ""),
};
pub const CLAW_STRS = [_]DamageStr{
    _dmgstr(005, "scratch", "scratches", ""),
    _dmgstr(060, "claw", "claws", ""),
    _dmgstr(061, "mangle", "mangles", ""),
    _dmgstr(090, "shred", "shreds", " like wet paper"),
    _dmgstr(100, "tear", "tears", " into pieces"),
    _dmgstr(150, "tear", "tears", " into tiny pieces"),
    _dmgstr(200, "mangle", "mangles", " beyond recognition"),
};
pub const FIST_STRS = [_]DamageStr{
    _dmgstr(020, "punch", "punches", ""),
    _dmgstr(030, "hit", "hits", ""),
    _dmgstr(040, "bludgeon", "bludgeons", ""),
    _dmgstr(060, "pummel", "pummels", ""),
};
pub const KICK_STRS = [_]DamageStr{
    _dmgstr(080, "kick", "kicks", ""),
    _dmgstr(081, "curbstomp", "curbstomps", ""),
};

// Body weapons {{{
pub const FistWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 80,
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
    .is_dippable = true,
    .strs = &SLASHING_STRS,
};

pub const DaggerWeapon = Weapon{
    .id = "dagger",
    .name = "dagger",
    .damage = 2,
    .martial = true,
    .stats = .{ .Martial = 1 },
    .is_dippable = true,
    .strs = &PIERCING_STRS,
};

pub const StilettoWeapon = Weapon{
    .id = "stiletto",
    .name = "stiletto",
    .damage = 5,
    .stats = .{ .Melee = -25 },
    .is_dippable = true,
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
    .is_dippable = true,
    .strs = &PIERCING_STRS,
};

// Purely for skeletal axemasters for now; lore describes axes as being
// experimental
//
pub const AxeWeapon = Weapon{
    .id = "battleaxe",
    .name = "battleaxe",
    .delay = 120,
    .damage = 4,
    .stats = .{ .Melee = -15 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .OpenMelee, .duration = .Equ },
    },
    .is_dippable = true,
    .strs = &SLASHING_STRS,
};

// }}}

// Polearms {{{

pub const HalberdWeapon = Weapon{
    .id = "halberd",
    .name = "halberd",
    .damage = 2,
    .stats = .{ .Sneak = -1 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .OpenMelee, .duration = .Equ },
    },
    .is_dippable = true,
    .strs = &SLASHING_STRS,
    .reach = 2,
};

pub const GlaiveWeapon = Weapon{
    .id = "glaive",
    .name = "glaive",
    .damage = 2,
    .stats = .{ .Melee = 10, .Sneak = -1 },
    .is_dippable = true,
    .strs = &SLASHING_STRS,
    .reach = 2,
};

pub const MonkSpadeWeapon = Weapon{
    .id = "monk_spade",
    .name = "monk's spade",
    .damage = 1,
    .delay = 50,
    .knockback = 1,
    .stats = .{ .Sneak = -1 },
    .strs = &PIERCING_STRS,
    .reach = 2,
};

pub const WoldoWeapon = Weapon{
    .id = "woldo",
    .name = "woldo",
    .damage = 3,
    .martial = true,
    .stats = .{ .Melee = -15, .Sneak = -1 },
    .is_dippable = true,
    .strs = &SLASHING_STRS,
    .reach = 2,
};

// }}}

// Blunt weapons {{{

pub const QuarterstaffWeapon = Weapon{
    .id = "quarterstaff",
    .name = "quarterstaff",
    .damage = 2,
    .martial = true,
    .stats = .{ .Martial = 1, .Evade = 15 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .OpenMelee, .duration = .Equ },
    },
    .strs = &CRUSHING_STRS,
};

pub const KnoutWeapon = Weapon{
    .id = "knout",
    .name = "knout",
    .delay = 150,
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

pub const MaceWeapon = Weapon{
    .id = "mace",
    .name = "mace",
    .damage = 2,
    .stats = .{ .Melee = 10 },
    .strs = &CRUSHING_STRS,
};

pub const GreatMaceWeapon = Weapon{
    .id = "great_mace",
    .name = "great mace",
    .damage = 2,
    .effects = &[_]StatusDataInfo{
        .{ .status = .Stun, .duration = .{ .Tmp = 3 } },
    },
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
    if (T == Ring) it.pattern_checker.init();
    if (T == Evocable) it.charges = it.max_charges;
    return it;
}

pub fn createItemFromTemplate(template: ItemTemplate) Item {
    return switch (template.i) {
        .W => |i| Item{ .Weapon = createItem(Weapon, i) },
        .A => |i| Item{ .Armor = createItem(Armor, i) },
        .P => |i| Item{ .Consumable = i },
        .E => |i| Item{ .Evocable = createItem(Evocable, i) },
        .C => |i| Item{ .Cloak = i },
        //else => err.todo(),
    };
}
