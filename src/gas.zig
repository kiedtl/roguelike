const std = @import("std");
const math = std.math;

const state = @import("state.zig");
const rng = @import("rng.zig");
usingnamespace @import("types.zig");

pub const Poison = Gas{
    .color = 0xa7e234,
    .dissipation_rate = 0.01,
    .opacity = 0.05,
    .trigger = triggerPoison,
    .id = 0,
};

pub const Paralysis = Gas{
    .color = 0xaaaaff,
    .dissipation_rate = 0.05,
    .opacity = 0.03,
    .trigger = triggerParalysis,
    .id = 1,
};

pub const SmokeGas = Gas{
    .color = 0xffffff,
    .dissipation_rate = 0.02,
    // Lava emits smoke. If opacity >= 1.0, this causes massive lighting
    // fluctuations, which is not desirable.
    .opacity = 0.8,
    .trigger = triggerNone,
    .id = 2,
};

pub const Confusion = Gas{
    .color = 0x33cbca,
    .dissipation_rate = 0.05,
    .opacity = 0.0,
    .trigger = triggerConfusion,
    .id = 3,
};

pub const Slow = Gas{
    .color = 0x8e77dd,
    .dissipation_rate = 0.02,
    .opacity = 0.0,
    .trigger = triggerSlow,
    .id = 4,
};

pub const Healing = Gas{
    .color = 0xbb97aa,
    .dissipation_rate = 0.02,
    .opacity = 0.0,
    .trigger = triggerHealing,
    .id = 5,
};

pub const Dust = Gas{
    .color = 0xd2b48c,
    .dissipation_rate = 0.07,
    .opacity = 0.1,
    .trigger = triggerDust,
    .residue = .Dust,
    .id = 6,
};

pub const Steam = Gas{
    .color = 0x5f5f5f,
    .dissipation_rate = 0.12,
    .opacity = 0.00,
    .trigger = triggerNone,
    .id = 7,
};

pub const Gases = [_]Gas{
    Poison, Paralysis, SmokeGas, Confusion, Slow, Healing, Dust, Steam,
};
pub const GAS_NUM: usize = Gases.len;

// Ensure that each gas's ID matches the index that it appears as in Gases.
comptime {
    for (&Gases) |gas, i|
        if (i != gas.id) @compileError("Gas's ID doesn't match index");
}

fn triggerNone(_: *Mob, __: f64) void {}

fn triggerPoison(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Poison, 0, Status.MAX_DURATION, false);
}

fn triggerParalysis(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Paralysis, 0, Status.MAX_DURATION, false);
}

fn triggerConfusion(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Confusion, 0, Status.MAX_DURATION, false);
}

fn triggerSlow(idiot: *Mob, quantity: f64) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    idiot.addStatus(.Slow, 0, Status.MAX_DURATION, false);
}

fn triggerHealing(mob: *Mob, quantity: f64) void {
    mob.HP *= 1.1 * (quantity + 1.0);
    mob.HP = math.clamp(mob.HP, 0, mob.max_HP);
}

fn triggerDust(mob: *Mob, quantity: f64) void {}

// Create and dissipate gas.
pub fn tickGases(cur_lev: usize, cur_gas: usize) void {
    // First make hot water emit steam, and lava emit smoke.
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);
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
                        if (rng.onein(3000)) {
                            c_gas[SmokeGas.id] += 0.15;
                        }
                    },
                    else => {},
                }
            }
        }
    }

    // ...then spread it.
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

                var avg: f64 = state.dungeon.atGas(coord)[cur_gas];
                var neighbors: f64 = 1;
                for (&DIRECTIONS) |d, i| {
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
