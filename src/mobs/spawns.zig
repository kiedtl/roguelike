const std = @import("std");
const mem = std.mem;

const err = @import("../err.zig");
const tsv = @import("../tsv.zig");
const utils = @import("../utils.zig");
const state = @import("../state.zig");
const rng = @import("../rng.zig");
const mobs = @import("../mobs.zig");
const mapgen = @import("../mapgen.zig");

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

pub const MobSpawnInfo = struct {
    id: []const u8 = undefined,
    classtype: []const u8 = undefined,
    weight: usize,

    pub const AList = std.ArrayList(@This());
};

pub const SpawnTable = enum { Main, Vaults, Special, Lair };
pub var spawn_tables: [LEVELS]MobSpawnInfo.AList = undefined;
pub var spawn_tables_vaults: [mapgen.VAULT_KINDS]MobSpawnInfo.AList = undefined;
pub var spawn_tables_special: [LEVELS]MobSpawnInfo.AList = undefined;
pub var spawn_tables_lairs: [1]MobSpawnInfo.AList = undefined;

pub fn chooseMob(which_table: SpawnTable, z: usize, maybe_class: ?[]const u8) !*const mobs.MobTemplate {
    const chosen_table = switch (which_table) {
        .Main => spawn_tables[z],
        .Vaults => spawn_tables_vaults[z],
        .Special => spawn_tables_special[z],
        .Lair => spawn_tables_lairs[z],
    };

    var table: @TypeOf(chosen_table) = undefined;

    if (maybe_class) |class| {
        table = @TypeOf(table).init(state.GPA.allocator());
        for (chosen_table.items) |item| {
            const is_of_class = for (class) |class_char| {
                if (mem.indexOfScalar(u8, item.classtype, class_char)) |_|
                    break true;
            } else false;
            if (!is_of_class)
                continue;
            table.append(item) catch err.wat();
        }
    } else {
        table = chosen_table;
    }

    if (table.items.len == 0) {
        return error.NoSuitableMobs;
    }

    const mob_spawn_info = rng.choose2(MobSpawnInfo, table.items, "weight") catch err.wat();
    const class_str = maybe_class orelse @as([]const u8, "null");
    const mob = mobs.findMobById(mob_spawn_info.id) orelse err.bug(
        "Mob {s} specified in spawn table {} couldn't be found (class {s}).",
        .{ mob_spawn_info.id, which_table, class_str },
    );

    if (maybe_class) |_| {
        table.deinit();
    }

    return mob;
}

pub fn readSpawnTables(alloc: mem.Allocator) void {
    const TmpMobSpawnData = struct {
        id: []u8 = undefined,
        classtype: []u8 = undefined,
        levels: [LEVELS]usize = undefined,
    };

    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    var rbuf: [65535]u8 = undefined;

    const spawn_table_files = [_]struct {
        filename: []const u8,
        sptable: []MobSpawnInfo.AList,
        backwards: bool = false,
    }{
        .{ .filename = "spawns.tsv", .sptable = &spawn_tables, .backwards = true },
        .{ .filename = "spawns_vaults.tsv", .sptable = &spawn_tables_vaults },
        .{ .filename = "spawns_special.tsv", .sptable = &spawn_tables_special, .backwards = true },
        .{ .filename = "spawns_lairs.tsv", .sptable = &spawn_tables_lairs, .backwards = true },
    };

    // We need `inline for` because the schema needs to be comptime...
    //
    inline for (spawn_table_files) |sptable_file| {
        const data_file = data_dir.openFile(sptable_file.filename, .{ .read = true }) catch unreachable;
        const len = sptable_file.sptable.len;

        const read = data_file.readAll(rbuf[0..]) catch unreachable;

        const result = tsv.parse(TmpMobSpawnData, &[_]tsv.TSVSchemaItem{
            .{ .field_name = "id", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "classtype", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "levels", .parse_to = usize, .is_array = len, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
        }, .{}, rbuf[0..read], alloc);

        if (!result.is_ok()) {
            err.bug("Can't load {s}: {} (line {}, field {})", .{
                sptable_file.filename,
                result.Err.type,
                result.Err.context.lineno,
                result.Err.context.field,
            });
        }

        const spawndatas = result.unwrap();
        defer spawndatas.deinit();

        for (sptable_file.sptable) |*table, i| {
            table.* = @TypeOf(table.*).init(alloc);
            for (spawndatas.items) |spawndata| {
                table.append(.{
                    .id = utils.cloneStr(spawndata.id, state.GPA.allocator()) catch err.oom(),
                    .classtype = utils.cloneStr(spawndata.classtype, state.GPA.allocator()) catch err.oom(),
                    .weight = spawndata.levels[if (sptable_file.backwards) (len - 1) - i else i],
                }) catch err.wat();
            }
        }

        for (spawndatas.items) |spawndata| {
            alloc.free(spawndata.id);
            alloc.free(spawndata.classtype);
        }
        std.log.info("Loaded spawn tables ({s}).", .{sptable_file.filename});
    }
}

pub fn freeSpawnTables(alloc: mem.Allocator) void {
    for (spawn_tables) |table| {
        for (table.items) |spawn_info| {
            alloc.free(spawn_info.id);
            alloc.free(spawn_info.classtype);
        }
        table.deinit();
    }

    for (spawn_tables_vaults) |table| {
        for (table.items) |spawn_info| {
            alloc.free(spawn_info.id);
            alloc.free(spawn_info.classtype);
        }
        table.deinit();
    }

    for (spawn_tables_special) |table| {
        for (table.items) |spawn_info| {
            alloc.free(spawn_info.id);
            alloc.free(spawn_info.classtype);
        }
        table.deinit();
    }

    for (spawn_tables_lairs[0].items) |spawn_info| {
        alloc.free(spawn_info.id);
        alloc.free(spawn_info.classtype);
    }
    spawn_tables_lairs[0].deinit();
}
