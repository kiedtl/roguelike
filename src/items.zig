const std = @import("std");
const math = std.math;
const meta = std.meta;
const assert = std.debug.assert;

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

const Coord = types.Coord;
const Item = types.Item;
const Potion = types.Potion;
const Ring = types.Ring;
const DamageStr = types.DamageStr;
const Weapon = types.Weapon;
const Resistance = types.Resistance;
const StatusDataInfo = types.StatusDataInfo;
const Armor = types.Armor;
const SurfaceItem = types.SurfaceItem;
const Mob = types.Mob;
const Spatter = types.Spatter;
const Status = types.Status;
const Direction = types.Direction;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const LinkedList = @import("list.zig").LinkedList;

// TODO: remove
pub const POTIONS = [_]*const Potion{
    &SmokePotion,
    &ConfusionPotion,
    &ParalysisPotion,
    &FastPotion,
    &RecuperatePotion,
    &PoisonPotion,
    &InvigoratePotion,
    &DecimatePotion,
    &IncineratePotion,
};

// Items to be dropped into rooms for the player's use.
//
pub const ItemTemplate = struct {
    w: usize,
    i: union(enum) { W: Weapon, A: Armor, C: *const Cloak, P: *const Potion, E: Evocable },
};
pub const ITEM_DROPS = [_]ItemTemplate{
    // Weapons
    .{ .w = 50, .i = .{ .W = MaceWeapon } },
    .{ .w = 30, .i = .{ .W = MorningstarWeapon } },
    .{ .w = 30, .i = .{ .W = DaggerWeapon } },
    .{ .w = 10, .i = .{ .W = StilettoWeapon } },
    .{ .w = 05, .i = .{ .W = RapierWeapon } },
    // Armor
    .{ .w = 40, .i = .{ .A = GambesonArmor } },
    .{ .w = 15, .i = .{ .A = LeatherArmor } },
    .{ .w = 05, .i = .{ .A = HauberkArmor } },
    .{ .w = 02, .i = .{ .A = ScalemailArmor } },
    // Potions
    .{ .w = 40, .i = .{ .P = &SmokePotion } },
    .{ .w = 70, .i = .{ .P = &ConfusionPotion } },
    .{ .w = 40, .i = .{ .P = &ParalysisPotion } },
    .{ .w = 40, .i = .{ .P = &FastPotion } },
    .{ .w = 80, .i = .{ .P = &RecuperatePotion } },
    .{ .w = 70, .i = .{ .P = &PoisonPotion } },
    .{ .w = 70, .i = .{ .P = &InvigoratePotion } },
    .{ .w = 30, .i = .{ .P = &IncineratePotion } },
    .{ .w = 10, .i = .{ .P = &DecimatePotion } },
    // Evocables
    .{ .w = 10, .i = .{ .E = IronSpikeEvoc } },
    .{ .w = 05, .i = .{ .E = MineKitEvoc } },
    .{ .w = 05, .i = .{ .E = EldritchLanternEvoc } },
    .{ .w = 02, .i = .{ .E = HammerEvoc } },
    // Cloaks
    .{ .w = 02, .i = .{ .C = &SiliconCloak } },
    .{ .w = 02, .i = .{ .C = &FurCloak } },
    .{ .w = 02, .i = .{ .C = &VelvetCloak } },
    .{ .w = 02, .i = .{ .C = &ThornsCloak } },
};

pub const Cloak = struct {
    id: []const u8,
    name: []const u8,
    ego: union(enum) { Resist: Resistance, Camoflage, Retaliate },
};

pub const SiliconCloak = Cloak{ .id = "silicon", .name = "silicon", .ego = .{ .Resist = .rFire } };
pub const FurCloak = Cloak{ .id = "fur", .name = "fur", .ego = .{ .Resist = .rElec } };
pub const VelvetCloak = Cloak{ .id = "velvet", .name = "velvet", .ego = .Camoflage };
pub const ThornsCloak = Cloak{ .id = "thorns", .name = "thorns", .ego = .Retaliate };

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

pub const HammerEvoc = Evocable{
    .id = "hammer",
    .name = "hammer",
    .tile_fg = 0xffffff,
    .max_charges = 0,
    .rechargable = false,
    .purpose = .Other,
    .trigger_fn = _triggerHammerEvoc,
};
fn _triggerHammerEvoc(mob: *Mob, _: *Evocable) Evocable.EvokeError!void {
    assert(mob == state.player);

    const dest = display.chooseCell(.{}) orelse return error.BadPosition;
    if (dest.distance(mob.coord) > 1) {
        display.drawAlertThenLog("Your arms aren't that long!", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).surface == null) {
        display.drawAlertThenLog("There's nothing there to break!", .{});
        return error.BadPosition;
    } else if (meta.activeTag(state.dungeon.at(dest).surface.?) != .Machine) {
        display.drawAlertThenLog("Smashing that would be a waste of time.", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).broken) {
        display.drawAlertThenLog("Some rogue already smashed that.", .{});
        return error.BadPosition;
    }

    const machine = state.dungeon.at(dest).surface.?.Machine;
    machine.malfunctioning = true;
    state.dungeon.at(dest).broken = true;

    mob.makeNoise(.Crash, .Medium);

    switch (rng.range(usize, 0, 3)) {
        0 => state.message(.Info, "You viciously smash the {s}.", .{machine.name}),
        1 => state.message(.Info, "You noisily break the {s}.", .{machine.name}),
        2 => state.message(.Info, "You pound the {s} into fine dust!", .{machine.name}),
        3 => state.message(.Info, "You smash the {s} savagely.", .{machine.name}),
        else => err.wat(),
    }
}

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

pub const MineKitEvoc = Evocable{
    .id = "mine_kit",
    .name = "mine kit",
    .tile_fg = 0xffd7d7,
    .max_charges = 2,
    .delete_when_inert = true,
    .rechargable = false,
    .purpose = .Other,
    .trigger_fn = _triggerMineKit,
};
fn _triggerMineKit(mob: *Mob, _: *Evocable) Evocable.EvokeError!void {
    assert(mob == state.player);

    if (state.dungeon.at(mob.coord).surface) |_| {
        display.drawAlertThenLog("You can't build a mine where you're standing.", .{});
        return error.BadPosition;
    }

    var mine = surfaces.Mine;
    mine.coord = mob.coord;
    state.machines.append(mine) catch unreachable;
    state.dungeon.at(mob.coord).surface = SurfaceItem{ .Machine = state.machines.last().? };

    state.message(.Info, "You build a mine. You'd better be far away when it detonates!", .{});
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

pub const EcholocationRing = Ring{
    .name = "echolocation",
    .status = .Echolocation,
    .status_start_power = 1,
    .status_max_power = 5,
    .status_power_increase = 100,
};

// Potions {{{
pub const SmokePotion = Potion{
    .id = "potion_smoke",
    .name = "smoke",
    .type = .{ .Gas = gas.SmokeGas.id },
    .color = 0x00A3D9,
};

pub const ConfusionPotion = Potion{
    .id = "potion_confusion",
    .name = "confuzzlementation",
    .type = .{ .Gas = gas.Confusion.id },
    .dip_effect = .{ .status = .Confusion, .duration = .{ .Tmp = 3 } },
    .color = 0x33cbca,
};

pub const ParalysisPotion = Potion{
    .id = "potion_paralysis",
    .name = "petrification",
    .type = .{ .Gas = gas.Paralysis.id },
    .dip_effect = .{ .status = .Paralysis, .duration = .{ .Tmp = 2 } },
    .color = 0xaaaaff,
};

pub const FastPotion = Potion{
    .id = "potion_fast",
    .name = "acceleration",
    .type = .{ .Status = .Fast },
    .ingested = true,
    .dip_effect = .{ .status = .Fast, .duration = .{ .Tmp = 5 } },
    .color = 0xbb6c55,
};

pub const RecuperatePotion = Potion{
    .id = "potion_recuperate",
    .name = "recuperation",
    .type = .{ .Status = .Recuperate },
    .dip_effect = .{ .status = .Recuperate, .duration = .{ .Tmp = 5 } },
    .color = 0xffffff,
};

pub const PoisonPotion = Potion{
    .id = "potion_poison",
    .name = "coagulation",
    .type = .{ .Gas = gas.Poison.id },
    .dip_effect = .{ .status = .Poison, .duration = .{ .Tmp = 5 } },
    .color = 0xa7e234,
};

pub const InvigoratePotion = Potion{
    .id = "potion_invigorate",
    .name = "invigoration",
    .type = .{ .Status = .Invigorate },
    .ingested = true,
    .color = 0xdada53,
};

pub const IncineratePotion = Potion{
    .id = "potion_incinerate",
    .name = "incineration",
    .type = .{ .Custom = triggerIncineratePotion },
    .ingested = false,
    .dip_effect = .{ .status = .Fire, .duration = .{ .Tmp = 5 } },
    .color = 0xff3434, // TODO: unique color
};

pub const DecimatePotion = Potion{
    .id = "potion_decimate",
    .name = "decimation",
    .type = .{ .Custom = triggerDecimatePotion },
    .color = 0xda5353, // TODO: unique color
};
// }}}

pub const HauberkArmor = Armor{
    .id = "chainmail_armor",
    .name = "chainmail",
    .resists = .{ .Armor = 30 },
    .speed_penalty = 10,
    .evasion_penalty = 5,
};

pub const ScalemailArmor = Armor{
    .id = "scalemail_armor",
    .name = "scale mail",
    .resists = .{ .Armor = 25 },
    .speed_penalty = 10,
    .evasion_penalty = 10,
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

pub fn _dmgstr(p: usize, vself: []const u8, vother: []const u8, vdeg: []const u8) DamageStr {
    return .{ .dmg_percent = p, .verb_self = vself, .verb_other = vother, .verb_degree = vdeg };
}

const CRUSHING_STRS = [_]DamageStr{
    _dmgstr(000, "whack", "whacks", ""),
    _dmgstr(010, "cudgel", "cudgels", ""),
    _dmgstr(030, "bash", "bashes", ""),
    _dmgstr(040, "hammer", "hammers", ""),
    _dmgstr(060, "batter", "batters", ""),
    _dmgstr(070, "thrash", "thrashes", ""),
    _dmgstr(120, "flatten", "flattens", " like a chapati"),
    _dmgstr(150, "smash", "smashes", " like an overripe mango"),
    _dmgstr(200, "grind", "grinds", " into powder"),
    _dmgstr(400, "pulverise", "pulverises", " into a thin bloody mist"),
};
const SLASHING_STRS = [_]DamageStr{
    _dmgstr(000, "hit", "hits", ""),
    _dmgstr(020, "slash", "slashes", ""),
    _dmgstr(040, "slice", "slices", ""),
    _dmgstr(050, "shred", "shreds", ""),
    _dmgstr(070, "chop", "chops", " into pieces"),
    _dmgstr(090, "chop", "chops", " into tiny pieces"),
    _dmgstr(110, "slice", "slices", " into ribbons"),
    _dmgstr(140, "cut", "cuts", " asunder"),
    _dmgstr(200, "mince", "minces", " like boiled poultry"),
};
const PIERCING_STRS = [_]DamageStr{
    _dmgstr(010, "prick", "pricks", ""),
    _dmgstr(020, "puncture", "punctures", ""),
    _dmgstr(030, "hit", "hits", ""),
    _dmgstr(040, "perforate", "perforates", ""),
    _dmgstr(050, "skewer", "skewers", ""),
    _dmgstr(070, "impale", "impales", ""),
    _dmgstr(100, "skewer", "skewers", " like a kebab"),
    _dmgstr(110, "spit", "spits", " like a pig"),
    _dmgstr(120, "perforate", "perforates", " like a sieve"),
};
const LACERATING_STRS = [_][]DamageStr{
    _dmgstr(020, "whip", "whips", ""),
    _dmgstr(040, "lash", "lashes", ""),
    _dmgstr(050, "lacerate", "lacerates", ""),
    _dmgstr(070, "shred", "shreds", ""),
    _dmgstr(090, "shred", "shreds", " like wet paper"),
    _dmgstr(150, "mangle", "mangles", " beyond recognition"),
};

pub const FistWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 80,
    .damage = 2,
    .strs = &[_]DamageStr{
        _dmgstr(020, "punch", "punches", ""),
        _dmgstr(030, "hit", "hits", ""),
        _dmgstr(040, "bludgeon", "bludgeons", ""),
        _dmgstr(060, "pummel", "pummels", ""),
    },
};

pub const ClawWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 90,
    .damage = 3,
    .strs = &[_]DamageStr{
        _dmgstr(010, "scratch", "scratches", ""),
        _dmgstr(030, "claw", "claws", ""),
        _dmgstr(050, "shred", "shreds", ""),
        _dmgstr(090, "shred", "shreds", " like wet paper"),
        _dmgstr(100, "tear", "tears", " into pieces"),
        _dmgstr(150, "tear", "tears", " into tiny pieces"),
        _dmgstr(200, "mangle", "mangles", " beyond recognition"),
    },
};

pub const KickWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 100,
    .damage = 2,
    .strs = &[_]DamageStr{
        _dmgstr(080, "kick", "kicks", ""),
        _dmgstr(081, "curbstomp", "curbstomps", ""),
    },
};

pub const QuarterstaffWeapon = Weapon{
    .id = "quarterstaff",
    .name = "quarterstaff",
    .damage = 2,
    .stats = .{ .Martial = 2, .Evade = 15 },
    .equip_effects = &[_]StatusDataInfo{
        .{ .status = .OpenMelee, .duration = .Equ },
    },
    .strs = &CRUSHING_STRS,
};

pub const SwordWeapon = Weapon{
    .id = "sword",
    .name = "longsword",
    .damage = 2,
    .stats = .{ .Evade = 10 },
    .is_dippable = true,
    .strs = &CRUSHING_STRS,
};

pub const KnifeWeapon = Weapon{
    .id = "knife",
    .name = "knife",
    .damage = 1,
    .is_dippable = true,
    .strs = &PIERCING_STRS,
};

pub const DaggerWeapon = Weapon{
    .id = "dagger",
    .name = "dagger",
    .damage = 2,
    .stats = .{ .Martial = 1, .Melee = -15 },
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
    .is_dippable = true,
    .strs = &PIERCING_STRS,
};

pub const HalberdWeapon = Weapon{
    .id = "halberd",
    .name = "halberd",
    .damage = 2,
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
    .stats = .{ .Melee = 10 },
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
    .strs = &PIERCING_STRS,
    .reach = 2,
};

pub const WoldoWeapon = Weapon{
    .id = "woldo",
    .name = "woldo",
    .damage = 3,
    .stats = .{ .Melee = -10, .Martial = 2 },
    .is_dippable = true,
    .strs = &SLASHING_STRS,
    .reach = 2,
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

fn triggerIncineratePotion(_: ?*Mob, coord: Coord) void {
    const mean_radius: usize = 4;
    const S = struct {
        pub fn _opacityFunc(c: Coord) usize {
            return switch (state.dungeon.at(c).type) {
                .Lava, .Water, .Wall => 100,
                .Floor => if (state.dungeon.at(c).surface) |surf| switch (surf) {
                    .Machine => |m| if (m.isWalkable()) @as(usize, 0) else 50,
                    .Prop => |p| if (p.walkable) @as(usize, 0) else 50,
                    .Container => 100,
                    else => 0,
                } else 0,
            };
        }
    };

    var result: [HEIGHT][WIDTH]usize = undefined;
    for (result) |*row| for (row) |*cell| {
        cell.* = 0;
    };

    var deg: usize = 0;
    while (deg < 360) : (deg += 60) {
        const s = rng.range(usize, mean_radius / 2, mean_radius * 2) * 10;
        fov.rayCastOctants(coord, mean_radius, s, S._opacityFunc, &result, deg, deg + 61);
    }
    result[coord.y][coord.x] = 100; // Ground zero is always incinerated

    for (result) |row, y| for (row) |cell, x| {
        if (cell > 0) {
            const cellc = Coord.new2(coord.z, x, y);
            fire.setTileOnFire(cellc);
        }
    };
}

fn triggerDecimatePotion(_: ?*Mob, coord: Coord) void {
    const MIN_EXPLOSION_RADIUS: usize = 2;
    explosions.kaboom(coord, .{
        .strength = MIN_EXPLOSION_RADIUS * 100,
        .culprit = state.player,
    });
}

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
    if (T == Evocable) it.charges = it.max_charges;
    return it;
}

pub fn createItemFromTemplate(template: ItemTemplate) Item {
    return switch (template.i) {
        .W => |i| Item{ .Weapon = createItem(Weapon, i) },
        .A => |i| Item{ .Armor = createItem(Armor, i) },
        .P => |i| Item{ .Potion = i },
        .E => |i| Item{ .Evocable = createItem(Evocable, i) },
        .C => |i| Item{ .Cloak = i },
        //else => err.todo(),
    };
}
