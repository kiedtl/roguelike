const std = @import("std");
const meta = std.meta;

const items = @import("../items.zig");
const mobs = @import("../items.zig");
const types = @import("../types.zig");

const Armor = types.Armor;
const Aux = items.Aux;
const Cloak = items.Cloak;
const Consumable = items.Consumable;
const Headgear = items.Headgear;
const Weapon = types.Weapon;

fn _createDeclList(comptime T: type) []const *const T {
    @setEvalBranchQuota(9999);
    comptime var buf: []const *const T = &[_]*const T{};

    inline for (meta.declarations(items)) |declinfo| if (declinfo.is_pub)
        comptime if (@TypeOf(@field(items, declinfo.name)) == T) {
            buf = buf ++ [_]*const T{&@field(items, declinfo.name)};
        };

    return buf;
}

pub var ARMORS = _createDeclList(Armor);
pub var AUXES = _createDeclList(Aux);
pub var CLOAKS = _createDeclList(Cloak);
pub var CONSUMABLES = _createDeclList(Consumable);
pub var HEADGEAR = _createDeclList(Headgear);
pub var WEAPONS = _createDeclList(Weapon);
