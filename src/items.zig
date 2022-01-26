const std = @import("std");
const math = std.math;
const assert = std.debug.assert;

const explosions = @import("explosions.zig");
const gas = @import("gas.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
usingnamespace @import("types.zig");

const LinkedList = @import("list.zig").LinkedList;

pub const EvocableList = LinkedList(Evocable);
pub const Evocable = struct {
    // linked list stuff
    __next: ?*Evocable = null,
    __prev: ?*Evocable = null,

    id: []const u8,
    name: []const u8,
    tile_fg: u32,

    charges: usize = 0,
    max_charges: usize,
    last_used: usize = 0,

    // Whether to destroy the evocable when it's finished.
    delete_when_inert: bool = false,

    purpose: Purpose,

    trigger_fn: fn (*Mob, *Evocable) bool,

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

    pub fn evoke(self: *Evocable, by: *Mob) bool {
        if (self.charges > 0) {
            self.charges -= 1;
            self.last_used = state.ticks;
            return self.trigger_fn(by, self);
        } else {
            return false;
        }
    }
};

pub const MineKitEvoc = Evocable{
    .id = "mine_kit",
    .name = "mine kit",
    .tile_fg = 0xffffff,
    .max_charges = 2,
    .delete_when_inert = true,
    .purpose = .Other,
    .trigger_fn = _triggerMineKit,
};
fn _triggerMineKit(mob: *Mob, evoc: *Evocable) bool {
    assert(mob == state.player);

    if (state.dungeon.at(mob.coord).surface) |_| {
        state.message(.MetaError, "You can't build a mine where you're standing.", .{});
        return false;
    }

    var mine = surfaces.Mine;
    mine.coord = mob.coord;
    state.machines.append(mine) catch unreachable;
    state.dungeon.at(mob.coord).surface = SurfaceItem{ .Machine = state.machines.last().? };

    state.message(.Info, "You build a mine. You'd better be far away when it detonates!", .{});

    return true;
}

pub const EldritchLanternEvoc = Evocable{
    .id = "eldritch_lantern",
    .name = "eldritch lantern",
    .tile_fg = 0x23abef,
    .max_charges = 5,
    .purpose = .EnemyDebuff,
    .trigger_fn = _triggerEldritchLantern,
};
fn _triggerEldritchLantern(mob: *Mob, evoc: *Evocable) bool {
    var affected: usize = 0;
    var player_was_affected: bool = false;

    for (mob.fov) |row, y| for (row) |cell, x| {
        if (cell == 0) continue;

        const coord = Coord.new2(mob.coord.z, x, y);

        if (state.dungeon.at(coord).mob) |othermob| {
            if (othermob == mob) continue;

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
        // ↓ this isn't needed, but it's a workaround for a Zig compiler bug
        // FIXME: when upgraded to Zig v9, poke this code and see if the bug's
        // still there
        const mobname = mob.ai.profession_name orelse mob.species;
        state.message(.Info, "The {} flashes an eldritch lantern!", .{mobname});
        if (player_was_affected) {
            state.message(.Info, "You feel dazed by the blinding light.", .{});
        }
    }

    return true;
}

pub const WarningHornEvoc = Evocable{
    .id = "warning_horn",
    .name = "warning horn",
    .tile_fg = 0xefab23,
    .max_charges = 3,
    .purpose = .SelfBuff,
    .trigger_fn = _triggerWarningHorn,
};
fn _triggerWarningHorn(mob: *Mob, evoc: *Evocable) bool {
    mob.makeNoise(.Alarm, .Loudest);

    if (mob == state.player) {
        state.message(.Info, "You blow the horn!", .{});
    } else if (state.player.cansee(mob.coord)) {
        // ↓ this isn't needed, but it's a workaround for a Zig compiler bug
        // FIXME: when upgraded to Zig v9, poke this code and see if the bug's
        // still there
        const mobname = mob.ai.profession_name orelse mob.species;
        state.message(.Info, "The {} blows its warning horn!", .{mobname});
    }

    return true;
}

pub const EcholocationRing = Ring{
    .name = "echolocation",
    .status = .Echolocation,
    .status_start_power = 1,
    .status_max_power = 5,
    .status_power_increase = 100,
};

pub const FogPotion = Potion{ .id = "potion_fog", .name = "fog", .type = .{ .Gas = gas.SmokeGas.id }, .color = 0x00A3D9 };
pub const ConfusionPotion = Potion{ .id = "potion_confusion", .name = "confuzzlementation", .type = .{ .Gas = gas.Confusion.id }, .color = 0x33cbca };
pub const ParalysisPotion = Potion{ .id = "potion_paralysis", .name = "petrification", .type = .{ .Gas = gas.Paralysis.id }, .color = 0xaaaaff };
pub const FastPotion = Potion{ .id = "potion_fast", .name = "acceleration", .type = .{ .Status = .Fast }, .ingested = true, .color = 0xbb6c55 };
pub const SlowPotion = Potion{ .id = "potion_slow", .name = "deceleration", .type = .{ .Gas = gas.Slow.id }, .color = 0x8e77dd };
pub const RecuperatePotion = Potion{ .id = "potion_recuperate", .name = "recuperation", .type = .{ .Status = .Recuperate }, .color = 0xffffff };
pub const PoisonPotion = Potion{ .id = "potion_poison", .name = "coagulation", .type = .{ .Gas = gas.Poison.id }, .color = 0xa7e234 };
pub const InvigoratePotion = Potion{ .id = "potion_invigorate", .name = "invigoration", .type = .{ .Status = .Invigorate }, .ingested = true, .color = 0xdada53 };
pub const PreservePotion = Potion{ .id = "potion_preserve", .name = "preservation", .type = .{ .Custom = triggerPreservePotion }, .ingested = true, .color = 0xda5353 };
pub const DecimatePotion = Potion{ .id = "potion_decimate", .name = "decimation", .type = .{ .Custom = triggerDecimatePotion }, .color = 0xffffff }; // TODO: unique color

pub const POTIONS = [_]Potion{
    FogPotion,
    ConfusionPotion,
    ParalysisPotion,
    FastPotion,
    SlowPotion,
    RecuperatePotion,
    PoisonPotion,
    InvigoratePotion,
    PreservePotion,
    DecimatePotion,
};

pub const ChainmailArmor = Armor{
    .id = "chainmail_armor",
    .name = "chainmail",
    .resists = .{
        .Crushing = 2,
        .Pulping = 8,
        .Slashing = 15,
        .Piercing = 3,
        .Lacerating = 15,
    },
};

pub const RobeArmor = Armor{
    .id = "robe_armor",
    .name = "robe",
    .resists = .{
        .Crushing = 0,
        .Pulping = 1,
        .Slashing = 2,
        .Piercing = 0,
        .Lacerating = 3,
    },
};

pub const GambesonArmor = Armor{
    .id = "gambeson_armor",
    .name = "gambeson",
    .resists = .{
        .Crushing = 1,
        .Pulping = 3,
        .Slashing = 4,
        .Piercing = 2,
        .Lacerating = 6,
    },
};

pub const LeatherArmor = Armor{
    .id = "leather_armor",
    .name = "leather",
    .resists = .{
        .Crushing = 2,
        .Pulping = 5,
        .Slashing = 5,
        .Piercing = 3,
        .Lacerating = 8,
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
    dmgstr(000, "nip", "nips", ""),
    dmgstr(010, "hit", "hits", ""),
    dmgstr(030, "slash", "slashes", ""),
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
    dmgstr(100, "skewers", "skewers", " like a kebab"),
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

pub const UnarmedWeapon = Weapon{
    .id = "none",
    .name = "none",
    .required_strength = 1,
    .required_dexterity = 1,
    .damages = .{
        .Crushing = 6,
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

pub const KnifeWeapon = Weapon{
    .id = "knife",
    .name = "knife",
    .required_strength = 8,
    .required_dexterity = 7,
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
    .required_strength = 14,
    .required_dexterity = 10,
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
    .required_strength = 14,
    .required_dexterity = 13,
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
    .required_strength = 13,
    .required_dexterity = 16,
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
    .required_strength = 18,
    .required_dexterity = 20,
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
    .required_strength = 20,
    .required_dexterity = 30,
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

pub const ClubWeapon = Weapon{
    .id = "club",
    .name = "stone club",
    .required_strength = 15,
    .required_dexterity = 5,
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
    .required_strength = 17,
    .required_dexterity = 6,
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

pub const NetLauncher = Weapon{
    .id = "net_launcher",
    .name = "net launcher",
    .required_strength = 10,
    .required_dexterity = 10,
    .damages = .{
        .Crushing = 5,
        .Pulping = 0,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 0,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
    .launcher = .{
        .projectile = Projectile{
            .main_damage = .Crushing,
            .damages = .{
                .Crushing = 5,
                .Pulping = 0,
                .Slashing = 0,
                .Piercing = 0,
                .Lacerating = 0,
            },
            .effect = triggerNetLauncherProjectile,
        },
    },
    .strs = &CRUSHING_STRS,
};

pub const DartLauncher = Weapon{
    .id = "dart_launcher",
    .name = "dart launcher",
    .required_strength = 12,
    .required_dexterity = 12,
    .damages = .{
        .Crushing = 4,
        .Pulping = 2,
        .Slashing = 1,
        .Piercing = 0,
        .Lacerating = 0,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
    .launcher = .{
        .projectile = Projectile{
            .main_damage = .Pulping,
            .damages = .{
                .Crushing = 0,
                .Pulping = 8,
                .Slashing = 3,
                .Piercing = 2,
                .Lacerating = 2,
            },
        },
    },
    .strs = &CRUSHING_STRS,
};

fn triggerPreservePotion(_dork: ?*Mob, coord: Coord) void {
    if (_dork) |dork| {

        // If the mob has a bad status, set the status' duration to 0 (thus removing it)
        if (dork.isUnderStatus(.Poison)) |_| dork.addStatus(.Poison, 0, 0, false);
        if (dork.isUnderStatus(.Confusion)) |_| dork.addStatus(.Confusion, 0, 0, false);

        dork.HP = math.min(dork.max_HP, dork.HP + (dork.max_HP * 150 / 100));
    }
}

fn triggerDecimatePotion(_dork: ?*Mob, coord: Coord) void {
    const MIN_EXPLOSION_RADIUS: usize = 2;
    explosions.kaboom(coord, .{
        .strength = MIN_EXPLOSION_RADIUS * 100,
        .culprit = state.player,
    });
}

fn triggerNetLauncherProjectile(coord: Coord) void {
    const _f = struct {
        fn _addNet(c: Coord) void {
            if (state.dungeon.at(c).mob) |mob| {
                mob.addStatus(.Held, 0, 10, false);
            } else {
                if (state.is_walkable(c, .{ .right_now = true }) and
                    state.dungeon.at(c).surface == null)
                {
                    var net = surfaces.NetTrap;
                    net.coord = c;
                    state.machines.append(net) catch unreachable;
                    state.dungeon.at(c).surface = SurfaceItem{ .Machine = state.machines.last().? };
                }
            }
        }
    };

    for (&DIRECTIONS) |direction| {
        if (coord.move(direction, state.mapgeometry)) |neighbor| {
            // if there's no mob on a tile, give a chance for a net
            // to not fall there
            if (state.dungeon.at(neighbor).mob == null and rng.onein(4)) continue;

            _f._addNet(neighbor);
        }
    }
}
