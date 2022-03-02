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
usingnamespace @import("types.zig");

const LinkedList = @import("list.zig").LinkedList;

// TODO: remove
pub const POTIONS = [_]Potion{
    SmokePotion,
    ConfusionPotion,
    ParalysisPotion,
    FastPotion,
    RecuperatePotion,
    PoisonPotion,
    InvigoratePotion,
    DecimatePotion,
    IncineratePotion,
};

// Items to be dropped into rooms for the player's use.
//
pub const ItemTemplate = struct {
    w: usize,
    i: union(enum) {
        W: Weapon, A: Armor, C: *const Cloak, P: Potion, E: Evocable
    },
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
    .{ .w = 05, .i = .{ .A = ChainmailArmor } },
    .{ .w = 02, .i = .{ .A = ScalemailArmor } },
    // Potions
    .{ .w = 40, .i = .{ .P = SmokePotion } },
    .{ .w = 70, .i = .{ .P = ConfusionPotion } },
    .{ .w = 40, .i = .{ .P = ParalysisPotion } },
    .{ .w = 40, .i = .{ .P = FastPotion } },
    .{ .w = 80, .i = .{ .P = RecuperatePotion } },
    .{ .w = 70, .i = .{ .P = PoisonPotion } },
    .{ .w = 70, .i = .{ .P = InvigoratePotion } },
    .{ .w = 30, .i = .{ .P = IncineratePotion } },
    .{ .w = 10, .i = .{ .P = DecimatePotion } },
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
    name: []const u8,
    ego: union(enum) {
        Resist: Resistance, Stealth, Retaliate
    },
};

pub const SiliconCloak = Cloak{ .name = "silicon", .ego = .{ .Resist = .rFire } };
pub const FurCloak = Cloak{ .name = "fur", .ego = .{ .Resist = .rElec } };
pub const VelvetCloak = Cloak{ .name = "velvet", .ego = .Stealth };
pub const ThornsCloak = Cloak{ .name = "thorns", .ego = .Retaliate };

pub const Projectile = struct {
    id: []const u8,
    name: []const u8,
    color: u32,
    damages: ?Damages = null,
    main_damage: ?DamageType = null,
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
            .duration = 10,
        },
    },
};

pub const JavelinProj = Projectile{
    .id = "javelin",
    .name = "poisoned javelin",
    .color = 0xffd7d7,
    .damages = .{ .Piercing = 15 },
    .main_damage = .Piercing,
    .effect = .{
        .Status = .{
            .status = .Poison,
            .duration = 3,
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
fn _triggerHammerEvoc(mob: *Mob, evoc: *Evocable) Evocable.EvokeError!void {
    assert(mob == state.player);

    const dest = display.chooseCell() orelse return error.BadPosition;
    if (dest.distance(mob.coord) > 1) {
        state.message(.MetaError, "Your arms aren't that long!", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).surface == null) {
        state.message(.MetaError, "There's nothing there to break!", .{});
        return error.BadPosition;
    } else if (meta.activeTag(state.dungeon.at(dest).surface.?) != .Machine) {
        state.message(.MetaError, "Smashing that would be a waste of time.", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).broken) {
        state.message(.MetaError, "Some rogue already smashed that.", .{});
        return error.BadPosition;
    }

    const machine = state.dungeon.at(dest).surface.?.Machine;
    machine.malfunctioning = true;
    state.dungeon.at(dest).broken = true;

    mob.makeNoise(.Crash, .Medium);

    switch (rng.range(usize, 0, 3)) {
        0 => state.message(.Info, "You viciously smash the {}.", .{machine.name}),
        1 => state.message(.Info, "You noisily break the {}.", .{machine.name}),
        2 => state.message(.Info, "You pound the {} into fine dust!", .{machine.name}),
        3 => state.message(.Info, "You smash the {} savagely.", .{machine.name}),
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

fn _triggerIronSpikeEvoc(mob: *Mob, evoc: *Evocable) Evocable.EvokeError!void {
    assert(mob == state.player);

    const dest = display.chooseCell() orelse return error.BadPosition;
    if (dest.distance(mob.coord) > 1) {
        state.message(.MetaError, "Your arms aren't that long!", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).surface == null) {
        state.message(.MetaError, "There's nothing there to break!", .{});
        return error.BadPosition;
    } else if (meta.activeTag(state.dungeon.at(dest).surface.?) != .Machine or
        !state.dungeon.at(dest).surface.?.Machine.can_be_jammed)
    {
        state.message(.MetaError, "You can't jam that!", .{});
        return error.BadPosition;
    } else if (state.dungeon.at(dest).surface.?.Machine.jammed) {
        state.message(.MetaError, "That's already jammed!", .{});
        return error.BadPosition;
    }

    const machine = state.dungeon.at(dest).surface.?.Machine;
    machine.jammed = true;
    machine.power = 0;

    state.message(.Info, "You jam the {}...", .{machine.name});
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
fn _triggerMineKit(mob: *Mob, evoc: *Evocable) Evocable.EvokeError!void {
    assert(mob == state.player);

    if (state.dungeon.at(mob.coord).surface) |_| {
        state.message(.MetaError, "You can't build a mine where you're standing.", .{});
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
fn _triggerEldritchLantern(mob: *Mob, evoc: *Evocable) Evocable.EvokeError!void {
    var affected: usize = 0;
    var player_was_affected: bool = false;

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;

        const coord = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(coord).mob) |othermob| {
            if (!othermob.cansee(mob.coord))
                continue;

            const dur = rng.rangeClumping(usize, 5, 20, 2);
            othermob.addStatus(.Confusion, 0, dur, false);

            affected += 1;
            if (othermob == state.player)
                player_was_affected = true;
        }
    };

    mob.addStatus(.Confusion, 0, rng.range(usize, 1, 4), false);
    mob.makeNoise(.Explosion, .Quiet);

    if (mob == state.player) {
        state.message(.Info, "The eldritch lantern flashes brilliantly!", .{});

        if (affected > 1) {
            state.message(.Info, "You and those nearby are dazed by the light.", .{});
        } else {
            state.message(.Info, "You are dazed by the light.", .{});
        }
    } else if (state.player.cansee(mob.coord)) {
        state.message(.Info, "The {} flashes an eldritch lantern!", .{mob.displayName()});
        if (player_was_affected) { // Player *should* always be affected...
            state.message(.Info, "You feel dazed by the blinding light.", .{});
        }
    }
}

pub const WarningHornEvoc = Evocable{
    .id = "warning_horn",
    .name = "warning horn",
    .tile_fg = 0xefab23,
    .max_charges = 3,
    .purpose = .SelfBuff,
    .trigger_fn = _triggerWarningHorn,
};
fn _triggerWarningHorn(mob: *Mob, evoc: *Evocable) Evocable.EvokeError!void {
    mob.makeNoise(.Alarm, .Loudest);

    if (mob == state.player) {
        state.message(.Info, "You blow the horn!", .{});
    } else if (state.player.cansee(mob.coord)) {
        state.message(.Info, "The {} blows its warning horn!", .{mob.displayName()});
    }
}

pub const EcholocationRing = Ring{
    .name = "echolocation",
    .status = .Echolocation,
    .status_start_power = 1,
    .status_max_power = 5,
    .status_power_increase = 100,
};

pub const SmokePotion = Potion{ .id = "potion_smoke", .name = "smoke", .type = .{ .Gas = gas.SmokeGas.id }, .color = 0x00A3D9 };
pub const ConfusionPotion = Potion{ .id = "potion_confusion", .name = "confuzzlementation", .type = .{ .Gas = gas.Confusion.id }, .color = 0x33cbca };
pub const ParalysisPotion = Potion{ .id = "potion_paralysis", .name = "petrification", .type = .{ .Gas = gas.Paralysis.id }, .color = 0xaaaaff };
pub const FastPotion = Potion{ .id = "potion_fast", .name = "acceleration", .type = .{ .Status = .Fast }, .ingested = true, .color = 0xbb6c55 };
pub const RecuperatePotion = Potion{ .id = "potion_recuperate", .name = "recuperation", .type = .{ .Status = .Recuperate }, .color = 0xffffff };
pub const PoisonPotion = Potion{ .id = "potion_poison", .name = "coagulation", .type = .{ .Gas = gas.Poison.id }, .color = 0xa7e234 };
pub const InvigoratePotion = Potion{ .id = "potion_invigorate", .name = "invigoration", .type = .{ .Status = .Invigorate }, .ingested = true, .color = 0xdada53 };
pub const IncineratePotion = Potion{ .id = "potion_incinerate", .name = "incineration", .type = .{ .Custom = triggerIncineratePotion }, .ingested = false, .color = 0xff3434 }; // TODO: unique color
pub const DecimatePotion = Potion{ .id = "potion_decimate", .name = "decimation", .type = .{ .Custom = triggerDecimatePotion }, .color = 0xda5353 }; // TODO: unique color

pub const ChainmailArmor = Armor{
    .id = "chainmail_armor",
    .name = "chainmail",
    .resists = .{
        .Crushing = 15,
        .Pulping = 20,
        .Slashing = 50,
        .Piercing = 35,
        .Lacerating = 80,
    },
    .speed_penalty = 40,
};

pub const ScalemailArmor = Armor{
    .id = "scalemail_armor",
    .name = "scale mail",
    .resists = .{
        .Crushing = 25,
        .Pulping = 20,
        .Slashing = 50,
        .Piercing = 30,
        .Lacerating = 80,
    },
    .speed_penalty = 20,
    .dex_penalty = 40,
};

pub const RobeArmor = Armor{
    .id = "robe_armor",
    .name = "robe",
    .resists = .{
        .Crushing = 0,
        .Pulping = 5,
        .Slashing = 2,
        .Piercing = 2,
        .Lacerating = 8,
    },
};

pub const GambesonArmor = Armor{
    .id = "gambeson_armor",
    .name = "gambeson",
    .resists = .{
        .Crushing = 10,
        .Pulping = 8,
        .Slashing = 15,
        .Piercing = 10,
        .Lacerating = 15,
    },
};

pub const LeatherArmor = Armor{
    .id = "leather_armor",
    .name = "leather",
    .resists = .{
        .Crushing = 8,
        .Pulping = 10,
        .Slashing = 18,
        .Piercing = 15,
        .Lacerating = 25,
    },
};

pub const NoneArmor = Armor{
    .id = "none",
    .name = "none",
    .resists = .{
        .Crushing = 1,
        .Pulping = 1,
        .Slashing = 1,
        .Piercing = 1,
        .Lacerating = 1,
    },
};

fn dmgstr(p: usize, vself: []const u8, vother: []const u8, vdeg: []const u8) DamageStr {
    return .{ .dmg_percent = p, .verb_self = vself, .verb_other = vother, .verb_degree = vdeg };
}

const CRUSHING_STRS = [_]DamageStr{
    dmgstr(000, "whack", "whacks", ""),
    dmgstr(010, "cudgel", "cudgels", ""),
    dmgstr(030, "bash", "bashes", ""),
    dmgstr(040, "hammer", "hammers", ""),
    dmgstr(060, "batter", "batters", ""),
    dmgstr(070, "thrash", "thrashes", ""),
    dmgstr(120, "flatten", "flattens", " like a chapati"),
    dmgstr(150, "smash", "smashes", " like an overripe mango"),
    dmgstr(200, "grind", "grinds", " into powder"),
    dmgstr(400, "pulverise", "pulverises", " into a thin bloody mist"),
};
const SLASHING_STRS = [_]DamageStr{
    dmgstr(000, "hit", "hits", ""),
    dmgstr(020, "slash", "slashes", ""),
    dmgstr(040, "slice", "slices", ""),
    dmgstr(050, "shred", "shreds", ""),
    dmgstr(070, "chop", "chops", " into pieces"),
    dmgstr(090, "chop", "chops", " into tiny pieces"),
    dmgstr(110, "slice", "slices", " into ribbons"),
    dmgstr(140, "cut", "cuts", " asunder"),
    dmgstr(200, "mince", "minces", " like boiled poultry"),
};
const PIERCING_STRS = [_]DamageStr{
    dmgstr(010, "prick", "pricks", ""),
    dmgstr(020, "puncture", "punctures", ""),
    dmgstr(030, "hit", "hits", ""),
    dmgstr(040, "perforate", "perforates", ""),
    dmgstr(050, "skewer", "skewers", ""),
    dmgstr(070, "impale", "impales", ""),
    dmgstr(100, "skewer", "skewers", " like a kebab"),
    dmgstr(110, "spit", "spits", " like a pig"),
    dmgstr(120, "perforate", "perforates", " like a sieve"),
};
const LACERATING_STRS = [_][]DamageStr{
    dmgstr(020, "whip", "whips", ""),
    dmgstr(040, "lash", "lashes", ""),
    dmgstr(050, "lacerate", "lacerates", ""),
    dmgstr(070, "shred", "shreds", ""),
    dmgstr(090, "shred", "shreds", " like wet paper"),
    dmgstr(150, "mangle", "mangles", " beyond recognition"),
};

pub const LivingIceHitWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 80,
    .damages = .{
        .Crushing = 15,
        .Pulping = 0,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 0,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
    .strs = &[_]DamageStr{
        dmgstr(010, "hit", "hits", ""),
    },
};

pub const FistWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 80,
    .damages = .{
        .Crushing = 10,
        .Pulping = 0,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 0,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
    .strs = &[_]DamageStr{
        dmgstr(020, "punch", "punches", ""),
        dmgstr(030, "hit", "hits", ""),
        dmgstr(040, "bludgeon", "bludgeons", ""),
        dmgstr(060, "pummel", "pummels", ""),
    },
};

pub const ClawWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 90,
    .damages = .{
        .Crushing = 0,
        .Pulping = 3,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 9,
    },
    .main_damage = .Lacerating,
    .secondary_damage = .Pulping,
    .strs = &[_]DamageStr{
        dmgstr(010, "scratch", "scratches", ""),
        dmgstr(030, "claw", "claws", ""),
        dmgstr(050, "shred", "shreds", ""),
        dmgstr(090, "shred", "shreds", " like wet paper"),
        dmgstr(100, "tear", "tears", " into pieces"),
        dmgstr(150, "tear", "tears", " into tiny pieces"),
        dmgstr(200, "mangle", "mangles", " beyond recognition"),
    },
};

pub const KickWeapon = Weapon{
    .id = "none",
    .name = "none",
    .delay = 100,
    .damages = .{
        .Crushing = 0,
        .Pulping = 3,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 9,
    },
    .main_damage = .Lacerating,
    .secondary_damage = .Pulping,
    .strs = &[_]DamageStr{
        dmgstr(080, "kick", "kicks", ""),
        dmgstr(081, "curbstomp", "curbstomps", ""),
    },
};

pub const KnifeWeapon = Weapon{
    .id = "knife",
    .name = "knife",
    .damages = .{
        .Crushing = 0,
        .Pulping = 1,
        .Slashing = 1,
        .Piercing = 10,
        .Lacerating = 1,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
    .strs = &PIERCING_STRS,
};

pub const DaggerWeapon = Weapon{
    .id = "dagger",
    .name = "dagger",
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 3,
        .Piercing = 15,
        .Lacerating = 2,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
    .strs = &PIERCING_STRS,
};

pub const StilettoWeapon = Weapon{
    .id = "stiletto",
    .name = "stiletto",
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 2,
        .Piercing = 19,
        .Lacerating = 2,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
    .strs = &PIERCING_STRS,
};

pub const RapierWeapon = Weapon{
    .id = "rapier",
    .name = "rapier",
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 1,
        .Piercing = 24,
        .Lacerating = 1,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
    .strs = &PIERCING_STRS,
};

pub const SpearWeapon = Weapon{
    .id = "spear",
    .name = "spear",
    .delay = 110,
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 2,
        .Piercing = 15,
        .Lacerating = 1,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
    .strs = &PIERCING_STRS,
};

pub const KnoutWeapon = Weapon{
    .id = "knout",
    .name = "knout",
    .delay = 150,
    .damages = .{
        .Crushing = 12,
        .Pulping = 19,
        .Slashing = 2,
        .Piercing = 5,
        .Lacerating = 5,
    },
    .main_damage = .Pulping,
    .secondary_damage = .Crushing,
    .strs = &CRUSHING_STRS,
};

pub const MorningstarWeapon = Weapon{
    .id = "morningstar",
    .name = "morningstar",
    .damages = .{
        .Crushing = 5,
        .Pulping = 10,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 5,
    },
    .main_damage = .Pulping,
    .secondary_damage = .Crushing,
    .strs = &CRUSHING_STRS,
};

pub const ClubWeapon = Weapon{
    .id = "club",
    .name = "stone club",
    .delay = 110,
    .damages = .{
        .Crushing = 12,
        .Pulping = 2,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 2,
    },
    .main_damage = .Crushing,
    .secondary_damage = .Pulping,
    .strs = &CRUSHING_STRS,
};

pub const MaceWeapon = Weapon{
    .id = "mace",
    .name = "mace",
    .damages = .{
        .Crushing = 15,
        .Pulping = 1,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 1,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
    .strs = &CRUSHING_STRS,
};

// Purely for skeletal axemasters for now; lore describes axes as being
// experimental
//
pub const AxeWeapon = Weapon{
    .id = "battleaxe",
    .name = "battleaxe",
    .delay = 110,
    .damages = .{
        .Crushing = 7,
        .Pulping = 5,
        .Slashing = 9,
    },
    .main_damage = .Slashing,
    .secondary_damage = .Crushing,
    .strs = &SLASHING_STRS,
};

fn triggerIncineratePotion(_dork: ?*Mob, coord: Coord) void {
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

fn triggerDecimatePotion(_dork: ?*Mob, coord: Coord) void {
    const MIN_EXPLOSION_RADIUS: usize = 2;
    explosions.kaboom(coord, .{
        .strength = MIN_EXPLOSION_RADIUS * 100,
        .culprit = state.player,
    });
}

// ----------------------------------------------------------------------------

pub fn createItem(comptime T: type, item: T) *T {
    comptime const list = switch (T) {
        Potion => &state.potions,
        Ring => &state.rings,
        Armor => &state.armors,
        Weapon => &state.weapons,
        Evocable => &state.evocables,
        else => @compileError("uh wat"),
    };
    return list.appendAndReturn(item) catch err.oom();
}

pub fn createItemFromTemplate(template: ItemTemplate) Item {
    return switch (template.i) {
        .W => |i| Item{ .Weapon = createItem(Weapon, i) },
        .A => |i| Item{ .Armor = createItem(Armor, i) },
        .P => |i| Item{ .Potion = createItem(Potion, i) },
        .E => |i| Item{ .Evocable = createItem(Evocable, i) },
        .C => |i| Item{ .Cloak = i },
        //else => err.todo(),
    };
}
