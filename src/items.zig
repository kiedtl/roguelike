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

pub const POTIONS = [_]Potion{FogPotion};

pub const HeavyChainmailArmor = Armor{
    .id = "hvy_chainmail_armor",
    .name = "chainmail",
    .resists = .{
        .Crushing = 2,
        .Pulping = 8,
        .Slashing = 100,
        .Piercing = 4,
        .Lacerating = 100,
    },
};

pub const LeatherArmor = Armor{
    .id = "leather_armor",
    .name = "leather",
    .resists = .{
        .Crushing = 3,
        .Pulping = 3,
        .Slashing = 5,
        .Piercing = 0,
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
        .Crushing = 8,
        .Pulping = 1,
        .Slashing = 1,
        .Piercing = 0,
        .Lacerating = 1,
    },
    .main_damage = .Crushing,
    .secondary_damage = null,
};

pub const DaggerWeapon = Weapon{
    .id = "dagger",
    .name = "dagger",
    .required_strength = 14,
    .damages = .{
        .Crushing = 0,
        .Pulping = 0,
        .Slashing = 3,
        .Piercing = 13,
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
        .Piercing = 17,
        .Lacerating = 1,
    },
    .main_damage = .Piercing,
    .secondary_damage = null,
};
