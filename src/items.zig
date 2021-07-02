const gas = @import("gas.zig");
usingnamespace @import("types.zig");

pub const EcholocationRing = Ring{
    .name = "echolocation",
    .status = .Echolocation,
    .status_start_power = 10,
    .status_max_power = 25,
    .status_power_increase = 10,
};

pub const FogPotion = Potion{
    .name = "fog",
    .type = .{ .Gas = gas.SmokeGas.id },
    .color = 0x00A3D9,
};

pub const ConfusionPotion = Potion{
    .name = "confuzzlementation",
    .type = .{ .Gas = gas.Confusion.id },
    .color = 0x33cbca,
};

pub const POTIONS = [_]Potion{ FogPotion, ConfusionPotion };

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
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 3,
        .Piercing = 10,
        .Lacerating = 2,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
};

pub const SpearWeapon = Weapon{
    .id = "spear",
    .name = "spear",
    .required_strength = 18,
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

pub const CrossbowLauncher = Weapon{
    .id = "crossbow",
    .name = "crossbow",
    .required_strength = 20,
    .damages = .{
        .Crushing = 3,
        .Pulping = 1,
        .Slashing = 0,
        .Piercing = 0,
        .Lacerating = 0,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
    .launcher = .{ .need = .Bolt },
};

pub const CrossbowBoltProjectile = Projectile{
    .id = "bolt",
    .name = "bolt",
    .main_damage = .Piercing,
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 1,
        .Piercing = 15,
        .Lacerating = 0,
    },
    .type = .Bolt,
};
