// TODO: add state to machines

const std = @import("std");
const assert = std.debug.assert;
const mem = std.mem;
const meta = std.meta;

const main = @import("root");
const utils = @import("utils.zig");
const state = @import("state.zig");
const explosions = @import("explosions.zig");
const gas = @import("gas.zig");
const tsv = @import("tsv.zig");
const rng = @import("rng.zig");
const materials = @import("materials.zig");
usingnamespace @import("types.zig");

pub var props: PropArrayList = undefined;
pub var prison_item_props: PropArrayList = undefined;
pub var laboratory_item_props: PropArrayList = undefined;
pub var laboratory_props: PropArrayList = undefined;
pub var vault_props: PropArrayList = undefined;
pub var statue_props: PropArrayList = undefined;

pub const MACHINES = [_]Machine{
    ChainPress,
    ResearchCore,
    ElevatorMotor,
    Extractor,
    BlastFurnace,
    PowerSupply,
    NuclearPowerSupply,
    FuelPowerSupply,
    TurbinePowerSupply,
    HealingGasPump,
    Brazier,
    Lamp,
    StairExit,
    StairUp,
    NormalDoor,
    LockedDoor,
    ParalysisGasTrap,
    PoisonGasTrap,
    ConfusionGasTrap,
    AlarmTrap,
    NetTrap,
    RestrictedMachinesOpenLever,
    Mine,
};

pub const Bin = Container{ .name = "bin", .tile = '╳', .capacity = 14, .type = .Utility, .item_repeat = 20 };
pub const Barrel = Container{ .name = "barrel", .tile = 'ʊ', .capacity = 7, .type = .Eatables, .item_repeat = 0 };
pub const Cabinet = Container{ .name = "cabinet", .tile = 'π', .capacity = 5, .type = .Wearables };
//pub const Chest = Container{ .name = "chest", .tile = 'æ', .capacity = 7, .type = .Valuables };
pub const LabCabinet = Container{ .name = "cabinet", .tile = 'π', .capacity = 8, .type = .Utility, .item_repeat = 70 };
pub const VOreCrate = Container{ .name = "crate", .tile = '∐', .capacity = 21, .type = .VOres, .item_repeat = 60 };

pub const ChainPress = Machine{
    .id = "chain_press",
    .name = "chain press",

    .powered_tile = '≡',
    .unpowered_tile = '≡',

    .power_drain = 50,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerChainPress,
};

pub const ResearchCore = Machine{
    .id = "research_core",
    .name = "research core",

    .powered_tile = '█',
    .unpowered_tile = '▓',

    .power_drain = 50,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerResearchCore,
};

pub const ElevatorMotor = Machine{
    .id = "elevator_motor",
    .name = "motor",

    .powered_tile = '⊛',
    .unpowered_tile = '⊚',

    .power_drain = 50,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerElevatorMotor,
};

pub const Extractor = Machine{
    .id = "extractor",
    .name = "machine",

    .powered_tile = '⊟',
    .unpowered_tile = '⊞',

    .power_drain = 50,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .on_power = powerExtractor,
};

pub const BlastFurnace = Machine{
    .id = "blast_furnace",
    .name = "blast furnace",

    .powered_tile = '≡',
    .unpowered_tile = '≡',

    .power_drain = 50,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_luminescence = 100,
    .unpowered_luminescence = 0,
    .dims = true,

    .on_power = powerBlastFurnace,
};

pub const PowerSupply = Machine{
    .id = "power_supply",
    .name = "machine",

    .powered_tile = '█',
    .unpowered_tile = '▓',

    .power_drain = 30,
    .power_add = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .powered_luminescence = 75,
    .unpowered_luminescence = 5,

    .on_power = powerPowerSupply,
};

pub const NuclearPowerSupply = Machine{
    .id = "nuclear_power_supply",
    .name = "orthire furnace",

    .powered_tile = '≡',
    .unpowered_tile = '≡',

    .power_drain = 0,
    .power_add = 100,
    .power = 100, // Start out fully powered

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .powered_luminescence = 100,
    .unpowered_luminescence = 20,

    .on_power = powerPowerSupply,
};

pub const FuelPowerSupply = Machine{
    .id = "fuel_power_supply",
    .name = "fuel furnace",

    .powered_tile = '█',
    .unpowered_tile = '█',

    .power_drain = 0,
    .power_add = 100,
    .power = 100, // Start out fully powered

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .powered_luminescence = 100,
    .unpowered_luminescence = 20,

    .on_power = powerPowerSupply,
};

pub const TurbinePowerSupply = Machine{
    .id = "turbine_power_supply",
    .name = "turbine controller",

    .powered_tile = '≡',
    .unpowered_tile = '≡',

    .power_drain = 2,
    .power_add = 100,
    .power = 100, // Start out fully powered

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .powered_luminescence = 0,
    .unpowered_luminescence = 0,

    .on_power = powerTurbinePowerSupply,
};

pub const HealingGasPump = Machine{
    .id = "healing_gas_pump",
    .name = "machine",

    .powered_tile = '█',
    .unpowered_tile = '▓',

    .power_drain = 100,
    .power_add = 100,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 0,
    .unpowered_opacity = 0,

    .on_power = powerHealingGasPump,
};

pub const Brazier = Machine{
    .name = "a brazier",

    .powered_tile = '╋',
    .unpowered_tile = '┽',

    .powered_fg = 0xeee088,
    .unpowered_fg = 0xffffff,

    .powered_bg = 0xb7b7b7,
    .unpowered_bg = 0xaaaaaa,

    .power_drain = 10,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 1.0,
    .unpowered_opacity = 1.0,

    // maximum, could be much lower (see mapgen:placeLights)
    .powered_luminescence = 90,
    .unpowered_luminescence = 0,

    .on_power = powerNone,
};

pub const Lamp = Machine{
    .name = "a lamp",

    .powered_tile = '•',
    .unpowered_tile = '○',

    .powered_fg = 0xffdf12,
    .unpowered_fg = 0x88e0ee,

    .power_drain = 10,
    .power_add = 100,
    .auto_power = true,

    .powered_walkable = false,
    .unpowered_walkable = false,

    .powered_opacity = 1.0,
    .unpowered_opacity = 1.0,

    // maximum, could be lower (see mapgen:placeLights)
    .powered_luminescence = 100,
    .unpowered_luminescence = 0,

    .on_power = powerNone,
};

pub const StairExit = Machine{
    .id = "stair_exit",
    .name = "exit staircase",
    .powered_tile = '»',
    .unpowered_tile = '»',
    .on_power = powerStairExit,
};

// TODO: Maybe define a "Doormat" prop that stairs have? And doormats should have
// a very welcoming message on it, of course
pub const StairUp = Machine{
    .name = "ascending staircase",
    .powered_tile = '▲',
    .unpowered_tile = '▲',
    .evoke_confirm = "Go upstairs?",
    .on_power = powerStairUp,
};

pub const AlarmTrap = Machine{
    .name = "alarm trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .evoke_confirm = "Really trigger the alarm trap?",
    .on_power = powerAlarmTrap,
};

pub const NetTrap = Machine{
    .name = "net",
    .powered_fg = 0xffff00,
    .unpowered_fg = 0xffff00,
    .powered_tile = ':',
    .unpowered_tile = ':',
    .on_power = powerNetTrap,
    .pathfinding_penalty = 80,
};

pub const PoisonGasTrap = Machine{
    .name = "poison gas trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .evoke_confirm = "Really trigger the poison gas trap?",
    .on_power = powerPoisonGasTrap,
};

pub const ParalysisGasTrap = Machine{
    .name = "paralysis gas trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .evoke_confirm = "Really trigger the paralysis gas trap?",
    .on_power = powerParalysisGasTrap,
};

pub const ConfusionGasTrap = Machine{
    .name = "confusion gas trap",
    .powered_tile = '^',
    .unpowered_tile = '^',
    .evoke_confirm = "Really trigger the confusion gas trap?",
    .on_power = powerConfusionGasTrap,
};

pub const NormalDoor = Machine{
    .name = "door",
    .powered_tile = '□',
    .unpowered_tile = '■',
    .power_drain = 49,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .powered_opacity = 0.0,
    .unpowered_opacity = 1.0,
    .on_power = powerNone,
};

pub const LockedDoor = Machine{
    .name = "locked door",
    .powered_tile = '□',
    .unpowered_tile = '■',
    .unpowered_fg = 0xcfcfff,
    .power_drain = 90,
    .restricted_to = .Necromancer,
    .powered_walkable = true,
    .unpowered_walkable = false,
    .on_power = powerNone,
};

pub const RestrictedMachinesOpenLever = Machine{
    .id = "restricted_machines_open_lever",
    .name = "lever",
    .powered_tile = '/',
    .unpowered_tile = '\\',
    .unpowered_fg = 0xdaa520,
    .powered_fg = 0xdaa520,
    .power_drain = 90,
    .powered_walkable = false,
    .unpowered_walkable = false,
    .on_power = powerRestrictedMachinesOpenLever,
};

pub const Mine = Machine{
    .name = "mine",
    .powered_fg = 0xff34d7,
    .unpowered_fg = 0xff3434,
    .powered_tile = ':',
    .unpowered_tile = ':',
    .power_drain = 0, // Stay powered on once activated
    .on_power = powerMine,
    .pathfinding_penalty = 10,
};

fn powerNone(_: *Machine) void {}

fn powerChainPress(machine: *Machine) void {
    assert(machine.areas.len == 16);

    const press1 = machine.areas.data[0];
    const press2 = machine.areas.data[1];
    const asm1 = machine.areas.data[2..8];
    const asm2 = machine.areas.data[8..14];
    const output = machine.areas.data[14];
    const input = machine.areas.data[15];

    assert(asm1.len == asm2.len);

    const press1_glyphs = [_]u21{ '▆', '▅', '▄', '▃', '▂', ' ' };
    const press1_glyph = press1_glyphs[state.ticks % press1_glyphs[0..].len];
    const press2_glyphs = [_]u21{ '▂', '▃', '▄', '▅', '▆', '█' };
    const press2_glyph = press2_glyphs[state.ticks % press2_glyphs[0..].len];

    state.dungeon.at(press1).surface.?.Prop.tile = press1_glyph;
    state.dungeon.at(press2).surface.?.Prop.tile = press2_glyph;

    var i: usize = 0;
    while (i < asm1.len) : (i += 1) {
        const prop1 = state.dungeon.at(asm1[i]).surface.?.Prop;
        const prop2 = state.dungeon.at(asm2[i]).surface.?.Prop;

        if (i % ((state.ticks % (asm1.len + 1)) + 1) == 0) {
            prop1.tile = '━';
            prop1.fg = 0xffe744;
        } else {
            prop1.tile = '┉';
            prop1.fg = 0xe0e0ff;
        }

        if ((state.ticks % asm2.len) == (asm2.len - 1 - i)) {
            prop2.tile = '━';
            prop2.fg = 0xffe744;
        } else {
            prop2.tile = '┅';
            prop2.fg = 0xe0e0ff;
        }
    }

    if ((state.ticks % (asm1.len * 4)) == 0 and
        !state.dungeon.itemsAt(output).isFull())
    {
        if (state.dungeon.getItem(input)) |_| {
            const prop_idx = utils.findById(props.items, "chain").?;
            state.dungeon.itemsAt(output).append(
                Item{ .Prop = &props.items[prop_idx] },
            ) catch unreachable;
        } else |_| {}
    }
}

fn powerResearchCore(machine: *Machine) void {
    // Only function on every 32nd turn, to give the impression that it takes
    // a while to process vials
    if ((state.ticks % 32) != 0 or rng.onein(3)) return;

    for (&DIRECTIONS) |direction| if (machine.coord.move(direction, state.mapgeometry)) |neighbor| {
        for (state.dungeon.itemsAt(neighbor).constSlice()) |item, i| switch (item) {
            .Vial => {
                _ = state.dungeon.itemsAt(neighbor).orderedRemove(i) catch unreachable;
                return;
            },
            else => {},
        };
    };
}

fn powerElevatorMotor(machine: *Machine) void {
    assert(machine.areas.len > 0);

    // Only function on every 32th turn or so, to give the impression that it takes
    // a while to bring up more ores
    if ((state.ticks % 32) != 0 or rng.onein(3)) return;

    // XXX: should there be a better way than checking level num?
    const level = state.levelinfo[machine.coord.z].id;

    for (machine.areas.constSlice()) |coord| {
        if (!state.dungeon.itemsAt(coord).isFull()) {
            var material: ?*const Material = null;

            if (mem.eql(u8, level, "LAB")) {
                material = (rng.choose(Vial.OreAndVial, &Vial.VIAL_ORES, &Vial.VIAL_COMMONICITY) catch unreachable).m;
            } else if (mem.eql(u8, level, "SMI")) {
                const metals = [_]*const Material{&materials.Hematite};
                material = metals[rng.range(usize, 0, metals.len - 1)];
            } else unreachable;

            if (material) |mat| {
                state.dungeon.itemsAt(coord).append(Item{ .Boulder = mat }) catch unreachable;
            }
        }
    }
}

fn powerExtractor(machine: *Machine) void {
    assert(machine.areas.len == 2);

    // Only function on every 32th turn, to give the impression that it takes
    // a while to extract more vials
    if ((state.ticks % 32) != 0) return;

    var input = machine.areas.data[0];
    var output = machine.areas.data[1];

    if (state.dungeon.itemsAt(output).isFull())
        return;

    // TODO: don't eat items that can't be processed

    var input_item: ?Item = null;
    if (state.dungeon.hasContainer(input)) |container| {
        if (container.items.len > 0) input_item = container.items.pop() catch unreachable;
    } else {
        const t_items = state.dungeon.itemsAt(input);
        if (t_items.len > 0) input_item = t_items.pop() catch unreachable;
    }

    if (input_item != null) switch (input_item.?) {
        .Boulder => |b| for (&Vial.VIAL_ORES) |vd| if (vd.m) |m|
            if (mem.eql(u8, m.name, b.name)) {
                state.dungeon.itemsAt(output).append(Item{ .Vial = vd.v }) catch unreachable;
                state.dungeon.atGas(machine.coord)[gas.Dust.id] = rng.range(f64, 0.1, 0.2);
            },
        else => {},
    };
}

fn powerBlastFurnace(machine: *Machine) void {
    assert(machine.areas.len == 9);

    // Only function on every 8th turn, to give the impression that it takes
    // a while to smelt more ores
    if ((state.ticks % 8) != 0) return;

    const areas = machine.areas.constSlice();
    const input_areas = areas[0..4];
    const furnace_area = areas[4];
    const output_areas = areas[5..7];
    const refuse_areas = areas[7..9];

    // Move input items to furnace
    for (input_areas) |input_area| {
        if (state.dungeon.itemsAt(furnace_area).isFull())
            break;

        var input_item: ?Item = null;
        if (state.dungeon.hasContainer(input_area)) |container| {
            if (container.items.len > 0) input_item = container.items.pop() catch unreachable;
        } else {
            const t_items = state.dungeon.itemsAt(input_area);
            if (t_items.len > 0) input_item = t_items.pop() catch unreachable;
        }

        if (input_item) |item| {
            // XXX: it may be desirable later to handle this in a cleaner manner
            assert(meta.activeTag(item) == .Boulder);

            state.dungeon.itemsAt(furnace_area).append(item) catch unreachable;
            return;
        }
    }

    // Process items in furnace area and move to output area.
    var output_spot: ?Coord = null;
    for (output_areas) |output_area| {
        if (state.dungeon.hasContainer(output_area)) |container| {
            if (!container.items.isFull()) {
                output_spot = output_area;
                break;
            }
        } else {
            if (!state.dungeon.itemsAt(output_area).isFull()) {
                output_spot = output_area;
                break;
            }
        }
    }

    if (output_spot != null and state.dungeon.itemsAt(furnace_area).len > 0) {
        const item = state.dungeon.itemsAt(furnace_area).pop() catch unreachable;

        // XXX: it may be desirable later to handle this in a cleaner manner
        assert(meta.activeTag(item) == .Boulder);

        state.dungeon.heat[machine.coord.z][machine.coord.y][machine.coord.x] += item.Boulder.melting_point;
        const result_mat = item.Boulder.smelt_result.?;
        state.dungeon.itemsAt(output_spot.?).append(Item{ .Boulder = result_mat }) catch unreachable;
    }
}

fn powerPowerSupply(machine: *Machine) void {
    var iter = state.machines.iterator();
    while (iter.next()) |mach| {
        if (mach.coord.z == machine.coord.z and mach.auto_power)
            mach.addPower(null);
    }
}

fn powerTurbinePowerSupply(machine: *Machine) void {
    assert(machine.areas.len > 0);

    var steam: f64 = 0.0;

    for (machine.areas.constSlice()) |area| {
        const prop = state.dungeon.at(area).surface.?.Prop;

        // Anathema, we're modifying a game object this way! the horrors!
        prop.tile = switch (prop.tile) {
            '◴' => rng.chooseUnweighted(u21, &[_]u21{ '◜', '◠', '◝', '◡' }),
            '◜' => '◠',
            '◠' => '◝',
            '◝' => '◟',
            '◟' => '◡',
            '◡' => '◞',
            '◞' => '◜',
            else => unreachable,
        };

        steam += state.dungeon.atGas(area)[gas.Steam.id];
    }

    powerPowerSupply(machine);

    // Bypass machine.addPower
    machine.power += @floatToInt(usize, steam * 10);
    machine.last_interaction = null;
}

fn powerHealingGasPump(machine: *Machine) void {
    assert(machine.areas.len > 0);

    for (machine.areas.constSlice()) |coord| {
        state.dungeon.atGas(coord)[gas.Healing.id] = 1.0;
    }
}

fn powerAlarmTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Necromancer) return;

        culprit.makeNoise(.Alarm, .Deafening); // muahahaha
        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "You hear a loud clanging noise!", .{});
    }
}

fn powerNetTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        culprit.addStatus(.Held, 0, null, false);
    }
    state.dungeon.at(machine.coord).surface = null;
    machine.disabled = true;
}

fn powerPoisonGasTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Necromancer) return;

        for (machine.props) |maybe_prop| {
            if (maybe_prop) |vent| {
                state.dungeon.atGas(vent.coord)[gas.Poison.id] = 1.0;
            }
        }

        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "Noxious fumes seep through the gas vents!", .{});
    }
}

fn powerParalysisGasTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Necromancer) return;

        for (machine.props) |maybe_prop| {
            if (maybe_prop) |vent| {
                state.dungeon.atGas(vent.coord)[gas.Paralysis.id] = 1.0;
            }
        }

        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "Paralytic gas seeps out of the gas vents!", .{});
    }
}

fn powerConfusionGasTrap(machine: *Machine) void {
    if (machine.last_interaction) |culprit| {
        if (culprit.allegiance == .Necromancer) return;

        for (machine.props) |maybe_prop| {
            if (maybe_prop) |vent| {
                state.dungeon.atGas(vent.coord)[gas.Confusion.id] = 1.0;
            }
        }

        if (culprit.coord.eq(state.player.coord))
            state.message(.Trap, "Confusing gas seeps out of the gas vents!", .{});
    }
}

fn powerStairExit(machine: *Machine) void {
    assert(machine.coord.z == 0);
    if (machine.last_interaction) |culprit| {
        if (!culprit.coord.eq(state.player.coord)) return;
        state.state = .Win;
    }
}

fn powerStairUp(machine: *Machine) void {
    assert(machine.coord.z >= 1);
    const culprit = machine.last_interaction.?;
    if (!culprit.coord.eq(state.player.coord)) return;

    const dst = Coord.new2(machine.coord.z - 1, machine.coord.x, machine.coord.y);
    if (culprit.teleportTo(dst, null))
        state.message(.Move, "You ascend.", .{});
}

fn powerRestrictedMachinesOpenLever(machine: *Machine) void {
    const room_i = switch (state.layout[machine.coord.z][machine.coord.y][machine.coord.x]) {
        .Unknown => return,
        .Room => |r| r,
    };
    const room = &state.rooms[machine.coord.z].items[room_i].rect;

    var y: usize = room.start.y;
    while (y < room.end().y) : (y += 1) {
        var x: usize = room.start.x;
        while (x < room.end().x) : (x += 1) {
            const coord = Coord.new2(machine.coord.z, x, y);

            if (state.dungeon.at(coord).surface) |surface| {
                switch (surface) {
                    .Machine => |m| if (m.restricted_to != null)
                        m.addPower(null),
                    else => {},
                }
            }
        }
    }
}

fn powerMine(machine: *Machine) void {
    if (machine.last_interaction) |mob|
        if (mob == state.player) {
            // Deactivate.
            // TODO: either one of two things should be done:
            //       - Make it so that goblins won't trigger it, and make use of the
            //         restricted_to field on this machine.
            //       - Add a restricted_from field to ensure player won't trigger it.
            machine.power = 0;
            return;
        };

    if (rng.tenin(25)) {
        state.dungeon.at(machine.coord).surface = null;
        machine.disabled = true;

        explosions.kaboom(machine.coord, .{
            .strength = 3 * 100,
            .culprit = state.player,
        });
    }
}

pub fn readProps(alloc: *mem.Allocator) void {
    const PropData = struct {
        id: []u8 = undefined,
        name: []u8 = undefined,
        tile: u21 = undefined,
        fg: ?u32 = undefined,
        bg: ?u32 = undefined,
        walkable: bool = undefined,
        opacity: f64 = undefined,
        function: Function = undefined,
        holder: bool = undefined,

        pub const Function = enum {
            ActionPoint, Laboratory, Vault, LaboratoryItem, Statue, None
        };
    };

    props = PropArrayList.init(alloc);
    prison_item_props = PropArrayList.init(alloc);
    laboratory_item_props = PropArrayList.init(alloc);
    laboratory_props = PropArrayList.init(alloc);
    vault_props = PropArrayList.init(alloc);
    statue_props = PropArrayList.init(alloc);

    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("props.tsv", .{
        .read = true,
        .lock = .None,
    }) catch unreachable;

    var rbuf: [65535]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        PropData,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "id", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "name", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "tile", .parse_to = u21, .parse_fn = tsv.parseCharacter },
            .{ .field_name = "fg", .parse_to = ?u32, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = null },
            .{ .field_name = "bg", .parse_to = ?u32, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = null },
            .{ .field_name = "walkable", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = true },
            .{ .field_name = "opacity", .parse_to = f64, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0.0 },
            .{ .field_name = "function", .parse_to = PropData.Function, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = .None },
            .{ .field_name = "holder", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = false },
        },
        .{},
        rbuf[0..read],
        alloc,
    );

    if (!result.is_ok()) {
        std.log.err(
            "Cannot read props: {} (line {}, field {})",
            .{ result.Err.type, result.Err.context.lineno, result.Err.context.field },
        );
    } else {
        const propdatas = result.unwrap();
        defer propdatas.deinit();

        for (propdatas.items) |propdata| {
            const prop = Prop{
                .id = propdata.id,
                .name = propdata.name,
                .tile = propdata.tile,
                .fg = propdata.fg,
                .bg = propdata.bg,
                .walkable = propdata.walkable,
                .opacity = propdata.opacity,
                .holder = propdata.holder,
            };

            switch (propdata.function) {
                .Laboratory => laboratory_props.append(prop) catch unreachable,
                .LaboratoryItem => laboratory_item_props.append(prop) catch unreachable,
                .Vault => vault_props.append(prop) catch unreachable,
                .Statue => statue_props.append(prop) catch unreachable,
                else => {},
            }

            props.append(prop) catch unreachable;
        }

        std.log.info("Loaded {} props.", .{props.items.len});
    }
}

pub fn freeProps(alloc: *mem.Allocator) void {
    for (props.items) |prop| prop.deinit(alloc);

    props.deinit();
    prison_item_props.deinit();
    laboratory_item_props.deinit();
    laboratory_props.deinit();
    vault_props.deinit();
    statue_props.deinit();
}

pub fn tickMachines(level: usize) void {
    var iter = state.machines.iterator();
    while (iter.next()) |machine| {
        if (machine.coord.z != level or !machine.isPowered() or machine.disabled)
            continue;

        machine.on_power(machine);
        machine.power = utils.saturating_sub(machine.power, machine.power_drain);
    }
}
