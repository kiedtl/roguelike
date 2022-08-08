const std = @import("std");
const math = std.math;

const state = @import("state.zig");
const rng = @import("rng.zig");
const types = @import("types.zig");
const items = @import("items.zig");

const Coord = types.Coord;
const Mob = types.Mob;
const DamageStr = types.DamageStr;
const Spatter = types.Spatter;
const Status = types.Status;
const Direction = types.Direction;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub const Gas = struct {
    name: []const u8,
    color: u32,
    dissipation_rate: f64,
    opacity: f64 = 0.0,
    trigger: fn (*Mob, f64) void,
    not_breathed: bool = false, // if true, will affect nonbreathing mobs
    id: usize,
    residue: ?Spatter = null,
};

pub const Poison = Gas{
    .name = "poison gas",
    .color = 0xa7e234,
    .dissipation_rate = 0.01,
    .trigger = triggerPoison,
    .id = 0,
};

pub const Paralysis = Gas{
    .name = "paralysing gas",
    .color = 0xaaaaff,
    .dissipation_rate = 0.05,
    .trigger = triggerParalysis,
    .id = 1,
};

pub const SmokeGas = Gas{
    .name = "smoke",
    .color = 0xffffff,
    .dissipation_rate = 0.02,
    // Lava emits smoke. If opacity >= 1.0, this causes massive lighting
    // fluctuations, which is not desirable.
    .opacity = 0.9,
    .trigger = triggerNone,
    .id = 2,
};

pub const Disorient = Gas{
    .name = "disorienting fumes",
    .color = 0x33cbca,
    .dissipation_rate = 0.05,
    .trigger = triggerDisorient,
    .id = 3,
};

pub const Slow = Gas{
    .name = "slowing gas",
    .color = 0x8e77dd,
    .dissipation_rate = 0.02,
    .trigger = triggerSlow,
    .id = 4,
};

pub const Healing = Gas{
    .name = "healing gas",
    .color = 0xdd6565,
    .dissipation_rate = 0.04,
    .trigger = triggerHealing,
    .id = 5,
};

pub const Dust = Gas{
    .name = "dust",
    .color = 0xd2b48c,
    .dissipation_rate = 0.07,
    .opacity = 0.4,
    .trigger = triggerNone,
    .residue = .Dust,
    .id = 6,
};

pub const Steam = Gas{
    .name = "steam",
    .color = 0x5f5f5f,
    .dissipation_rate = 0.05,
    .opacity = 0.00,
    .trigger = struct {
        pub fn f(mob: *Mob, _: f64) void {
            mob.takeDamage(.{ .amount = 2, .kind = .Fire }, .{
                .noun = "The steam",
                .strs = &[_]types.DamageStr{
                    items._dmgstr(00, "BUG", "scalds", ""),
                    items._dmgstr(20, "BUG", "burns", ""),
                },
            });
        }
    }.f,
    .id = 7,
};

pub const Miasma = Gas{
    .name = "miasma",
    .color = 0xd77fd7,
    .dissipation_rate = 0.08,
    .opacity = 0.00,
    .trigger = triggerMiasma,
    .id = 8,
};

pub const Seizure = Gas{
    .name = "seizure gas",
    .color = 0xd7d77f,
    .dissipation_rate = 0.03,
    .opacity = 0.00,
    .trigger = struct {
        pub fn f(mob: *Mob, _: f64) void {
            mob.addStatus(.Debil, 0, .{ .Tmp = Status.MAX_DURATION });
        }
    }.f,
    .id = 9,
};

pub const Blinding = Gas{
    .name = "tear gas",
    .color = 0x7fe7f7,
    .dissipation_rate = 0.08,
    .opacity = 0.00,
    .trigger = struct {
        pub fn f(mob: *Mob, _: f64) void {
            mob.addStatus(.Blind, 0, .{ .Tmp = Status.MAX_DURATION });
        }
    }.f,
    .id = 10,
};

pub const Gases = [_]Gas{
    Poison,   Paralysis, SmokeGas, Disorient, Slow,
    Healing,  Dust,      Steam,    Miasma,    Seizure,
    Blinding,
};
pub const GAS_NUM: usize = Gases.len;

// Ensure that each gas's ID matches the index that it appears as in Gases.
// comptime {
//     for (&Gases) |gas, i|
//         if (i != gas.id) @compileError("Gas's ID doesn't match index");
// }

fn triggerNone(_: *Mob, _: f64) void {}

fn triggerPoison(mob: *Mob, _: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    mob.addStatus(.Poison, 0, .{ .Tmp = Status.MAX_DURATION });
}

fn triggerParalysis(mob: *Mob, _: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    mob.addStatus(.Paralysis, 0, .{ .Tmp = Status.MAX_DURATION });
}

fn triggerDisorient(mob: *Mob, _: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    mob.addStatus(.Disorient, 0, .{ .Tmp = Status.MAX_DURATION });
}

fn triggerSlow(mob: *Mob, _: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    mob.addStatus(.Slow, 0, .{ .Tmp = Status.MAX_DURATION });
}

fn triggerHealing(mob: *Mob, quantity: f64) void {
    _ = quantity;
    mob.addStatus(.Recuperate, 0, .{ .Tmp = 15 });
}

fn triggerMiasma(mob: *Mob, _: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    mob.addStatus(.Nausea, 0, .{ .Tmp = Status.MAX_DURATION });
}

// Make hot water emit steam, and lava emit smoke.
pub fn tickGasEmitters(level: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            const c_gas = state.dungeon.atGas(coord);
            switch (state.dungeon.at(coord).type) {
                .Water => {
                    var near_lavas: f64 = 0;
                    for (&DIRECTIONS) |d|
                        if (coord.move(d, state.mapgeometry)) |neighbor| {
                            if (state.dungeon.at(neighbor).type == .Lava)
                                near_lavas += 1;
                        };
                    c_gas[Steam.id] = near_lavas;
                },
                .Lava => {
                    if (rng.onein(300)) {
                        c_gas[SmokeGas.id] += 0.20;
                    }
                },
                else => {},
            }
        }
    }
}

// Create and dissipate gas.
pub fn tickGases(cur_lev: usize, cur_gas: usize) void {
    const std_dissipation = Gases[cur_gas].dissipation_rate;
    const residue = Gases[cur_gas].residue;

    var new: [HEIGHT][WIDTH]f64 = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);

                if (state.dungeon.at(coord).type == .Wall)
                    continue;

                if (state.dungeon.machineAt(coord)) |mach|
                    if (!mach.porous)
                        continue;

                var avg: f64 = state.dungeon.atGas(coord)[cur_gas];
                var neighbors: f64 = 1;
                for (&DIRECTIONS) |d| {
                    if (coord.move(d, state.mapgeometry)) |n| {
                        if (state.dungeon.atGas(n)[cur_gas] < 0.1)
                            continue;

                        avg += state.dungeon.atGas(n)[cur_gas];
                        neighbors += 1;
                    }
                }

                const max_dissipation = @floatToInt(usize, std_dissipation * 100);
                const dissipation = rng.rangeClumping(usize, 0, max_dissipation * 2, 2);
                const dissipation_f = @intToFloat(f64, dissipation) / 100;

                avg /= neighbors;
                avg -= dissipation_f;
                avg = math.max(avg, 0);

                new[y][x] = avg;
            }
        }
    }

    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);
                state.dungeon.atGas(coord)[cur_gas] = new[y][x];
                if (residue != null and new[y][x] > 0.3)
                    state.dungeon.spatter(coord, residue.?);
            }
        }
    }

    if (cur_gas < (GAS_NUM - 1))
        tickGases(cur_lev, cur_gas + 1);
}
