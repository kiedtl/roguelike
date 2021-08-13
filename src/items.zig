const std = @import("std");
const math = std.math;

const gas = @import("gas.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const machines = @import("machines.zig");
usingnamespace @import("types.zig");

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
pub const PreservePotion = Potion{ .id = "potion_preserve", .name = "preservation", .type = .{ .Custom = triggerPreservePotion }, .color = 0xda5353 };

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
};

pub const HeavyChainmailArmor = Armor{
    .id = "hvy_chainmail_armor",
    .name = "chainmail",
    .resists = .{
        .Crushing = 2,
        .Pulping = 8,
        .Slashing = 15,
        .Piercing = 4,
        .Lacerating = 15,
    },
};

pub const LeatherArmor = Armor{
    .id = "leather_armor",
    .name = "leather",
    .resists = .{
        .Crushing = 3,
        .Pulping = 3,
        .Slashing = 5,
        .Piercing = 1,
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

pub const UnarmedWeapon = Weapon{
    .id = "none",
    .name = "none",
    .required_strength = 1,
    .required_dexterity = 1,
    .damages = .{
        .Crushing = 5,
        .Pulping = 0,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 0,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
};

pub const ClubWeapon = Weapon{
    .id = "club",
    .name = "stone club",
    .required_strength = 17,
    .required_dexterity = 5,
    .damages = .{
        .Crushing = 10,
        .Pulping = 5,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 0,
    },
    .main_damage = .Crushing,
    .secondary_damage = .Pulping,
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
};

pub const SwordWeapon = Weapon{
    .id = "sword",
    .name = "sword",
    .required_strength = 15,
    .required_dexterity = 15,
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 15,
        .Piercing = 7,
        .Lacerating = 0,
    },
    .main_damage = .Slashing,
    .secondary_damage = .Piercing,
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
        .Lacerating = 0,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
};

// A heavy flail, essentially a knout
pub const ZinnagWeapon = Weapon{
    .id = "zinnag",
    .name = "zinnag",
    .required_strength = 20,
    .required_dexterity = 30,
    .damages = .{
        .Crushing = 9,
        .Pulping = 16,
        .Slashing = 2,
        .Piercing = 5,
        .Lacerating = 3,
    },
    .main_damage = .Pulping,
    .secondary_damage = .Crushing,
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
        .noise = Mob.NOISE_MOVE,
    },
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
        .noise = Mob.NOISE_YELL,
    },
};

fn triggerPreservePotion(_dork: ?*Mob) void {
    if (_dork) |dork| {

        // If the mob has a bad status, set the status' duration to 0 (thus removing it)
        if (dork.isUnderStatus(.Poison)) |_| dork.addStatus(.Poison, 0, 0, false);
        if (dork.isUnderStatus(.Confusion)) |_| dork.addStatus(.Confusion, 0, 0, false);

        dork.HP = math.min(dork.max_HP, dork.HP + (dork.max_HP * 150 / 100));
    }
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
                    var net = machines.NetTrap;
                    net.coord = c;
                    state.machines.append(net) catch unreachable;
                    state.dungeon.at(c).surface = SurfaceItem{ .Machine = state.machines.lastPtr().? };
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
