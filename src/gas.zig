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
    dissipation_rate: usize,
    opacity: f64 = 0.0,
    trigger: fn (*Mob, usize) void,
    not_breathed: bool = false, // if true, will affect nonbreathing mobs
    id: usize,
    residue: ?Spatter = null,
};

pub const Paralysis = Gas{
    .name = "paralysing gas",
    .color = 0xaaaaff,
    .dissipation_rate = 5,
    .trigger = triggerParalysis,
    .id = 0,
};

pub const SmokeGas = Gas{
    .name = "smoke",
    .color = 0xffffff,
    .dissipation_rate = 2,
    // Lava emits smoke. If opacity >= 1.0, this causes massive lighting
    // fluctuations, which is not desirable.
    .opacity = 0.9,
    .trigger = triggerNone,
    .id = 1,
};

pub const Disorient = Gas{
    .name = "disorienting fumes",
    .color = 0x33cbca,
    .dissipation_rate = 5,
    .trigger = triggerDisorient,
    .id = 2,
};

pub const Slow = Gas{
    .name = "slowing gas",
    .color = 0x8e77dd,
    .dissipation_rate = 2,
    .trigger = triggerSlow,
    .id = 3,
};

pub const Healing = Gas{
    .name = "healing gas",
    .color = 0xdd6565,
    .dissipation_rate = 4,
    .trigger = triggerHealing,
    .id = 4,
};

pub const Dust = Gas{
    .name = "dust",
    .color = 0xd2b48c,
    .dissipation_rate = 7,
    .opacity = 0.4,
    .trigger = triggerNone,
    .residue = .Dust,
    .id = 5,
};

pub const Steam = Gas{
    .name = "steam",
    .color = 0x5f5f5f,
    .dissipation_rate = 5,
    .opacity = 0.00,
    .trigger = struct {
        pub fn f(mob: *Mob, _: usize) void {
            mob.takeDamage(.{ .amount = 1, .kind = .Fire, .source = .Gas }, .{
                .noun = "The steam",
                .strs = &[_]types.DamageStr{
                    items._dmgstr(0, "BUG", "scalds", ""),
                    items._dmgstr(20, "BUG", "burns", ""),
                },
            });
        }
    }.f,
    .id = 6,
};

pub const Miasma = Gas{
    .name = "miasma",
    .color = 0xd77fd7,
    .dissipation_rate = 8,
    .opacity = 0.1,
    .trigger = triggerMiasma,
    .id = 7,
};

pub const Seizure = Gas{
    .name = "seizure gas",
    .color = 0xd7d77f,
    .dissipation_rate = 3,
    .opacity = 0.3,
    .trigger = struct {
        pub fn f(mob: *Mob, _: usize) void {
            mob.addStatus(.Debil, 0, .{ .Tmp = Status.MAX_DURATION });
        }
    }.f,
    .id = 8,
};

pub const Blinding = Gas{
    .name = "tear gas",
    .color = 0x7fe7f7,
    .dissipation_rate = 8,
    .opacity = 0.5,
    .trigger = struct {
        pub fn f(mob: *Mob, _: usize) void {
            mob.addStatus(.Blind, 0, .{ .Tmp = Status.MAX_DURATION });
        }
    }.f,
    .id = 9,
};

pub const Darkness = Gas{
    .name = "suffocating darkness",
    .color = 0x1f00ff,
    .dissipation_rate = 1,
    .opacity = 1.0,
    .trigger = struct {
        pub fn f(mob: *Mob, _: usize) void {
            mob.addStatus(.Insane, 0, .{ .Tmp = 3 });
        }
    }.f,
    .id = 10,
};

pub const Corrosive = Gas{
    .name = "acid cloud",
    .color = 0xa7e234,
    .dissipation_rate = 6,
    .opacity = 0.1,
    .trigger = struct {
        pub fn f(mob: *Mob, _: usize) void {
            if (!mob.isFullyResistant(.rAcid) and rng.onein(2)) {
                mob.takeDamage(.{ .amount = 1, .kind = .Acid, .blood = false, .source = .Gas }, .{
                    .noun = "The caustic gas",
                    .strs = &[_]DamageStr{
                        items._dmgstr(10, "BUG", "burns", ""),
                        items._dmgstr(20, "BUG", "eats away at", ""),
                        items._dmgstr(30, "BUG", "melts", ""),
                        items._dmgstr(99, "BUG", "dissolves", ""),
                    },
                });
            }
        }
    }.f,
    .not_breathed = true,
    .id = 11,
};

pub const Gases = [_]Gas{
    Paralysis, SmokeGas, Disorient, Slow,
    Healing,   Dust,     Steam,     Miasma,
    Seizure,   Blinding, Darkness,  Corrosive,
};
pub const GAS_NUM: usize = Gases.len;

// Ensure that each gas's ID matches the index that it appears as in Gases.
comptime {
    for (&Gases) |gas, i|
        if (i != gas.id) @compileError("Gas's ID doesn't match index");
}

fn triggerNone(_: *Mob, _: usize) void {}

fn triggerParalysis(mob: *Mob, _: usize) void {
    const dur = if (mob == state.player) 10 else Status.MAX_DURATION;
    mob.addStatus(.Paralysis, 0, .{ .Tmp = dur });
}

fn triggerDisorient(mob: *Mob, _: usize) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    mob.addStatus(.Disorient, 0, .{ .Tmp = Status.MAX_DURATION });
}

fn triggerSlow(mob: *Mob, _: usize) void {
    // TODO: Make the duration a clumping random value, depending on quantity
    mob.addStatus(.Slow, 0, .{ .Tmp = Status.MAX_DURATION });
}

fn triggerHealing(mob: *Mob, quantity: usize) void {
    _ = quantity;
    mob.addStatus(.Recuperate, 0, .{ .Tmp = 15 });
}

fn triggerMiasma(mob: *Mob, _: usize) void {
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
                    var near_lavas: usize = 0;
                    for (&DIRECTIONS) |d|
                        if (coord.move(d, state.mapgeometry)) |neighbor| {
                            if (state.dungeon.at(neighbor).type == .Lava)
                                near_lavas += 1;
                        };
                    c_gas[Steam.id] = near_lavas * 100;
                },
                .Lava => {
                    if (rng.onein(300)) {
                        c_gas[SmokeGas.id] += 20;
                    }
                },
                else => {},
            }
        }
    }
}

// Minimum gas needed to spread to adjacent tiles.
pub const MIN_GAS_SPREAD = 10;

pub fn spreadGas(matrix: anytype, z: usize, cur_gas: usize, deterministic: bool) void {
    const is_conglomerate = @TypeOf(matrix) == *[HEIGHT][WIDTH][GAS_NUM]usize;
    if (!is_conglomerate and @TypeOf(matrix) != *[HEIGHT][WIDTH]usize)
        @compileError("Invalid argument to spreadGas");

    const dis = Gases[cur_gas].dissipation_rate;

    var new: [HEIGHT][WIDTH]usize = std.mem.zeroes([HEIGHT][WIDTH]usize);
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(z, x, y);

            if (state.dungeon.at(coord).type == .Wall)
                continue;

            if (state.dungeon.machineAt(coord)) |mach|
                if (!mach.porous)
                    continue;

            var avg = if (is_conglomerate) matrix[y][x][cur_gas] else matrix[y][x];
            var neighbors: usize = 1;
            for (&DIRECTIONS) |d| {
                if (coord.move(d, state.mapgeometry)) |n| {
                    const n_gas = if (is_conglomerate) matrix[n.y][n.x][cur_gas] else matrix[n.y][n.x];
                    if (n_gas < MIN_GAS_SPREAD) continue;

                    avg += n_gas;
                    neighbors += 1;
                }
            }

            avg /= neighbors;
            avg -|= if (deterministic) dis else rng.rangeClumping(usize, 0, dis * 2, 2);

            new[y][x] = avg;
        }
    }

    {
        var dy: usize = 0;
        while (dy < HEIGHT) : (dy += 1) {
            var dx: usize = 0;
            while (dx < WIDTH) : (dx += 1) {
                const ptr = if (is_conglomerate) &matrix[dy][dx][cur_gas] else &matrix[dy][dx];
                ptr.* = new[dy][dx];
            }
        }
    }
}

pub fn mockGasSpread(gas: usize, amount: usize, coord: Coord, result: *[HEIGHT][WIDTH]usize) usize {
    const MAX_J = 20;

    var buf = std.mem.zeroes([HEIGHT][WIDTH]usize);
    buf[coord.y][coord.x] = amount;
    var j: usize = MAX_J;
    while (j > 0) : (j -= 1) {
        spreadGas(&buf, coord.z, gas, true);
        var anyleft = false;
        for (buf) |row, y| for (row) |cell, x| if (cell > 0) {
            anyleft = true;
            result[y][x] += 1;
        };
        if (!anyleft) break;
    }
    for (result) |*row| for (row) |*cell| if (cell.* > 0) {
        cell.* = cell.* * 100 / (MAX_J - j);
    };
    return MAX_J - j;
}

// Spread and dissipate gas.
pub fn tickGases(cur_lev: usize) void {
    var dirty_flags = [1]bool{false} ** GAS_NUM;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);
                const gases = state.dungeon.atGas(coord);
                for (gases) |gas, gas_i| if (gas != 0) {
                    dirty_flags[gas_i] = true;
                };
            }
        }
    }

    var cur_gas: usize = 0;
    while (cur_gas < GAS_NUM) : (cur_gas += 1) if (dirty_flags[cur_gas]) {
        spreadGas(&state.dungeon.gas[cur_lev], cur_lev, cur_gas, false);

        const residue = Gases[cur_gas].residue;

        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const coord = Coord.new2(cur_lev, x, y);
                if (residue != null and state.dungeon.atGas(coord)[cur_gas] > 30)
                    state.dungeon.spatter(coord, residue.?);
            }
        }
    };
}
