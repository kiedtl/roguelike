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

pub const LeatherArmor = Armor{
    .id = "leather_armor",
    .name = "leather",
    .crushing = 2,
    .pulping = 3,
    .slashing = 5,
    .piercing = 0,
    .lacerating = 8,
};

pub const DaggerWeapon = Weapon{
    .id = "dagger",
    .name = "dagger",
    .crushing = 0,
    .pulping = 0,
    .slashing = 3,
    .piercing = 13,
    .lacerating = 1,
};
