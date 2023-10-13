const std = @import("std");
const meta = std.meta;

const items = @import("../items.zig");
const mobs = @import("../items.zig");
const types = @import("../types.zig");

fn _createDeclList(comptime T: type) []const *const T {
    @setEvalBranchQuota(9999);
    comptime var buf: []const *const T = &[_]*const T{};

    inline for (meta.declarations(items)) |declinfo| if (declinfo.is_pub)
        comptime if (@TypeOf(@field(items, declinfo.name)) == T) {
            buf = buf ++ [_]*const T{&@field(items, declinfo.name)};
        };

    return buf;
}

pub var ARMORS = _createDeclList(types.Armor);
pub var AUXES = _createDeclList(items.Aux);
pub var CLOAKS = _createDeclList(items.Cloak);
pub var CONSUMABLES = _createDeclList(items.Consumable);
pub var EVOCABLES = _createDeclList(items.Evocable);
pub var HEADGEAR = _createDeclList(items.Headgear);
pub var WEAPONS = _createDeclList(types.Weapon);
