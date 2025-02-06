const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;
const meta = std.meta;
const assert = std.debug.assert;

const astar = @import("astar.zig");
const cbf = @import("cbf.zig");
const dijkstra = @import("dijkstra.zig");
const err = @import("err.zig");
const fov = @import("fov.zig");
const items = @import("items.zig");
const literature = @import("literature.zig");
const materials = @import("materials.zig");
const mobs = @import("mobs.zig");
const rng = @import("rng.zig");
const state = @import("state.zig");
const surfaces = @import("surfaces.zig");
const tsv = @import("tsv.zig");
const types = @import("types.zig");
const utils = @import("utils.zig");

const tunneler = @import("mapgen/tunneler.zig");

const LinkedList = @import("list.zig").LinkedList;
const Generator = @import("generators.zig").Generator;
const GeneratorCtx = @import("generators.zig").GeneratorCtx;
const StackBuffer = @import("buffer.zig").StackBuffer;

const Coord = types.Coord;
const Rect = types.Rect;
const Direction = types.Direction;
const MinMax = types.MinMax;
const minmax = types.minmax;
const Prop = types.Prop;
const Mob = types.Mob;
const Machine = types.Machine;
const Container = types.Container;
const SurfaceItem = types.SurfaceItem;
const Item = types.Item;
const Ring = types.Ring;
const Prisoner = types.Prisoner;
const SpatterType = types.SpatterType;
const TileType = types.TileType;
const Consumable = items.Consumable;
const SpatterArray = types.SpatterArray;
const Stockpile = types.Stockpile;
const ContainerArrayList = types.ContainerArrayList;
const CoordArrayList = types.CoordArrayList;
const Material = types.Material;
const Vial = types.Vial;
const Squad = types.Squad;
const MobSpawnInfo = mobs.spawns.MobSpawnInfo;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const ItemTemplate = items.ItemTemplate;
const Evocable = items.Evocable;
const EvocableList = items.EvocableList;
const Cloak = items.Cloak;
const Poster = literature.Poster;
const Stair = surfaces.Stair;

// Individual configurations.
//
// Deliberately kept separate from LevelConfigs because it applies as a whole
// to all levels.
//
// TODO: some of these will eventually (when?) be moved to level configs.
//
// {{{
const CONNECTIONS_MAX = 3;

pub const TRAPS = &[_]*const Machine{
    &surfaces.ParalysisGasTrap,
    &surfaces.DisorientationGasTrap,
    &surfaces.SeizureGasTrap,
    &surfaces.BlindingGasTrap,
};
pub const TRAP_WEIGHTS = &[_]usize{ 2, 3, 2, 1 };

pub const VaultType = enum(usize) {
    Iron = 0,
    Gold = 1,
    Marble = 2,
    Cuprite = 3,
    Obsidian = 4,
};
pub const VAULT_MATERIALS = [VAULT_KINDS]*const Material{
    &materials.Rust,
    &materials.Gold,
    &materials.Marble,
};
pub const VAULT_DOORS = [VAULT_KINDS]*const Machine{
    &surfaces.IronVaultDoor,
    &surfaces.GoldVaultDoor,
    &surfaces.MarbleVaultDoor,
};
// zig fmt: off
//
pub const VAULT_LEVELS = [LEVELS][]const VaultType{
    &.{                          }, // -1/Crypt/3
    &.{        .Marble           }, // -1/Crypt/2
    &.{        .Marble           }, // -1/Crypt
    &.{        .Marble           }, // -1/Prison
    &.{        .Marble           }, // -2/Prison
    &.{                          }, // -3/Holding
    &.{                          }, // -3/Laboratory/3
    &.{                          }, // -3/Laboratory/2
    &.{                          }, // -3/Shrine
    &.{        .Marble,          }, // -3/Laboratory
    &.{        .Marble,          }, // -4/Prison
    // &.{                          }, // -5/Caverns/3
    // &.{                          }, // -5/Caverns/2
    &.{                          }, // -5/Caverns
    &.{        .Marble,          }, // -5/Prison
    // &.{ .Iron, .Marble,          }, // -6/Workshop/3
    // &.{ .Iron,                   }, // -6/Workshop/2
    &.{                          }, // -6/Shrine
    &.{                          }, // -6/Workshop
    &.{                          }, // -7/Prison
    &.{                          }, // -8/Prison

    // &.{                          }, // Tutorial
};
// zig fmt: on
pub const VAULT_KINDS = 3;
pub const VAULT_SUBROOMS = [VAULT_KINDS]?[]const u8{
    null,
    null,
    "ANY_s_marble_vlts",
};
pub const VAULT_CROWD = [VAULT_KINDS]MinMax(usize){
    minmax(usize, 7, 14),
    minmax(usize, 7, 14),
    minmax(usize, 1, 4),
};
// }}}

// TODO: replace with MinMax
const Range = struct { from: Coord, to: Coord };

pub var s_fabs: PrefabArrayList = undefined;
pub var n_fabs: PrefabArrayList = undefined;

const gif = @import("build_options").tunneler_gif;
const giflib = if (gif) @cImport(@cInclude("gif_lib.h")) else null;
var frames: ?std.ArrayList([HEIGHT][WIDTH]u8) = null;

pub fn initGif() void {
    deinitGif();
    frames = if (gif) std.ArrayList([HEIGHT][WIDTH]u8).init(state.gpa.allocator()) else null;
}

pub fn deinitGif() void {
    if (gif) if (frames) |f| {
        f.deinit();
        frames = null;
    };
}

pub fn captureFrame(z: usize) void {
    if (!gif)
        return;

    var new: [HEIGHT][WIDTH]u8 = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                const c = Coord.new2(z, x, y);
                new[y][x] = if (state.dungeon.at(c).type == .Wall) 0 else 1;
            }
        }
    }

    // Something is wrecked here. Need to investigate.

    // for (state.rooms[z].items) |room| {
    //     var y: usize = room.rect.start.y;
    //     while (y < room.rect.end().y) : (y += 1) {
    //         var x: usize = room.rect.start.x;
    //         while (x < room.rect.end().x) : (x += 1) {
    //             const c = Coord.new2(z, x, y);
    //             const color: u8 = switch (room.type) {
    //                 .Corridor => 2,
    //                 .Junction => 3,
    //                 .Sideroom, .Room => 3,
    //             };
    //             new[y][x] = if (state.dungeon.at(c).type == .Wall) 0 else color;
    //         }
    //     }
    // }

    frames.?.append(new) catch err.wat();
}

pub fn emitGif(level: usize) void {
    if (gif) {
        const fname = std.fmt.allocPrintZ(state.gpa.allocator(), "L_{}_{s}.gif", .{ level, state.levelinfo[level].id }) catch err.oom();
        defer state.gpa.allocator().free(fname);

        var g_error: c_int = 0;
        var g_file = giflib.EGifOpenFileName(fname.ptr, false, &g_error);
        if (g_file == null) @panic("error (EGifOpenFileName)");

        if (giflib.EGifPutScreenDesc(g_file, WIDTH, HEIGHT, 8, 0, null) == giflib.GIF_ERROR)
            @panic("error (EGifPutScreenDesc)");

        const nsle = "NETSCAPE2.0";
        const subblock = [_]u8{ 1, 0, 0 };
        _ = giflib.EGifPutExtensionLeader(g_file, giflib.APPLICATION_EXT_FUNC_CODE);
        _ = giflib.EGifPutExtensionBlock(g_file, nsle.len, nsle);
        _ = giflib.EGifPutExtensionBlock(g_file, subblock.len, &subblock);
        _ = giflib.EGifPutExtensionTrailer(g_file);

        const pal = [16]giflib.GifColorType{
            .{ .Red = 0x2f, .Green = 0x1f, .Blue = 0x04 }, // background
            .{ .Red = 0xaf, .Green = 0x9f, .Blue = 0x84 }, // corridors
            .{ .Red = 0x8f, .Green = 0x7f, .Blue = 0x64 }, // junctions
            .{ .Red = 0x6f, .Green = 0x5f, .Blue = 0x44 }, // rooms
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
            .{ .Red = 0x9f, .Green = 0x8f, .Blue = 0x74 },
        };

        for (frames.?.items) |*frame, i| {
            const sec1: u8 = if (i == frames.?.items.len - 1) 0x04 else 0x00;
            const sec2: u8 = if (i == frames.?.items.len - 1) 0x00 else 0x01;
            const gce_str = [_]u8{
                0x04, // length of gce_str
                0x00, // misc packed fields (unused)
                sec1, // delay time in fractions of seconds (u16, continued below)
                sec2, // ...
            };

            if (giflib.EGifPutExtension(g_file, giflib.GRAPHICS_EXT_FUNC_CODE, gce_str.len, &gce_str) == giflib.GIF_ERROR)
                @panic("error (EGifPutExtension)");

            // Put frame headers.
            if (giflib.EGifPutImageDesc(g_file, 0, 0, WIDTH, HEIGHT, false, giflib.GifMakeMapObject(pal.len, &pal)) == giflib.GIF_ERROR)
                @panic("error (EGifPutImageDesc)");

            // Put frame, row-wise.
            for (frame) |*row| {
                if (giflib.EGifPutLine(g_file, row, WIDTH) == giflib.GIF_ERROR)
                    @panic("error (EGifPutLine)");
            }
        }

        _ = giflib.EGifCloseFile(g_file, &g_error);
    }
}

pub const LIMIT = Rect{
    .start = Coord.new(1, 1),
    .width = state.WIDTH - 1,
    .height = state.HEIGHT - 1,
};

const Corridor = struct {
    room: Room,

    // Return the parent/child again because in certain cases callers
    // don't know what child was passed, e.g., the BSP algorithm
    //
    // TODO: 2022-05-23: what the hell? need to remove this
    //
    parent: *Room,
    child: *Room,

    parent_connector: ?Coord,
    child_connector: ?Coord,
    distance: usize,

    // Distinct from parent_connector/child_connector, which are the prefab
    // connectors used.
    //
    parent_door: Coord,
    child_door: Coord,

    // The connector coords for the prefabs used, if any (the first is the parent's
    // connector, the second is the child's connector).
    //
    // When the corridor is excavated these must be marked as unused.
    //
    // (Note, this is distinct from parent_connector/child_connector. Those two
    // are absolute coordinates, fab_connectors is relative to the start of the
    // prefab's room.
    fab_connectors: [2]?Coord = .{ null, null },

    pub fn markConnectorsAsUsed(self: *const Corridor, parent: *Room, child: *Room) !void {
        if (parent.prefab) |fab| if (self.fab_connectors[0]) |c| try fab.useConnector(c);
        if (child.prefab) |fab| if (self.fab_connectors[1]) |c| try fab.useConnector(c);
    }
};

const VALID_WINDOW_PLACEMENT_PATTERNS = [_][]const u8{
    // ?.?
    // ###
    // ?.?
    "?.?###?.?",

    // ?#?
    // .#.
    // ?#?
    "?#?.#.?#?",
};

const VALID_DOOR_PLACEMENT_PATTERNS = [_][]const u8{
    // ?.?
    // #?#
    // ?.?
    "?.?#.#?.?",

    // ?#?
    // .?.
    // ?#?
    "?#?...?#?",
};

const VALID_STAIR_PLACEMENT_PATTERNS = [_][]const u8{
    // ###
    // ###
    // ?.?
    "######?.?",

    // ?.?
    // ###
    // ###
    "?.?######",

    // ?##
    // .##
    // ?##
    "?##.##?##",

    // ##?
    // ##.
    // ##?
    "##?##.##?",
};

const VALID_LIGHT_PLACEMENT_PATTERNS = [_][]const u8{
    // ...
    // ###
    // ...
    "...###...",

    // ###
    // ###
    // ?.?
    "######?.?",

    // ?.?
    // ###
    // ###
    "?.?######",

    // .#.
    // .#.
    // .#.
    ".#..#..#.",

    // ##?
    // ##.
    // ##?
    "##?##.##?",

    // ?##
    // .##
    // ?##
    "?##.##?##",
};

const VALID_FEATURE_TILE_PATTERNS = [_][]const u8{
    // ###
    // ?.?
    // ...
    "###?.?...",

    // ...
    // ?.?
    // ###
    "...?.?###",

    // .?#
    // ..#
    // .?#
    ".?#..#.?#",

    // #?.
    // #..
    // #?.
    "#?.#..#?.",
};

fn isTileAvailable(coord: Coord) bool {
    return state.dungeon.at(coord).type == .Floor and state.dungeon.at(coord).mob == null and state.dungeon.at(coord).surface == null and state.dungeon.itemsAt(coord).len == 0;
}

fn choosePoster(level: usize) ?*const Poster {
    var tries: usize = 256;
    while (tries > 0) : (tries -= 1) {
        var l: usize = 0;
        var iter = literature.posters.iterator();
        while (iter.next()) |_| l += 1;

        const i = rng.range(usize, 0, l - 1);
        const p = literature.posters.nth(i).?;

        if (p.placement_counter > 0 or !mem.eql(u8, state.levelinfo[level].id, p.level))
            continue;

        p.placement_counter += 1;
        return p;
    }

    return null;
}

pub fn chooseRing(night: bool) ItemTemplate {
    const drop_list = if (night) &items.NIGHT_RINGS else &items.RINGS;
    return _chooseLootItem(drop_list, minmax(usize, 1, 999), null);
}

// Given a parent and child room, return the direction a corridor between the two
// would go
fn getConnectionSide(parent: *const Room, child: *const Room) ?Direction {
    assert(!parent.rect.start.eq(child.rect.start)); // parent != child

    const x_overlap = math.max(parent.rect.start.x, child.rect.start.x) <
        math.min(parent.rect.end().x, child.rect.end().x);
    const y_overlap = math.max(parent.rect.start.y, child.rect.start.y) <
        math.min(parent.rect.end().y, child.rect.end().y);

    // assert that x_overlap or y_overlap, but not both
    assert(!(x_overlap and y_overlap));

    if (!x_overlap and !y_overlap) {
        return null;
    }

    if (x_overlap) {
        return if (parent.rect.start.y > child.rect.start.y) .North else .South;
    } else if (y_overlap) {
        return if (parent.rect.start.x > child.rect.start.x) .West else .East;
    } else err.wat();
}

fn computeWallAreas(rect: *const Rect, include_corners: bool) [4]Range {
    const rect_end = rect.end();

    if (include_corners) {
        return [_]Range{
            .{ .from = Coord.new(rect.start.x, rect.start.y - 1), .to = Coord.new(rect_end.x, rect.start.y - 1) }, // top
            .{ .from = Coord.new(rect.start.x, rect_end.y), .to = Coord.new(rect_end.x, rect_end.y) }, // bottom
            .{ .from = Coord.new(rect.start.x - 1, rect.start.y - 1), .to = Coord.new(rect.start.x - 1, rect_end.y) }, // left
            .{ .from = Coord.new(rect_end.x, rect.start.y), .to = Coord.new(rect_end.x, rect_end.y - 1) }, // right
        };
    } else {
        return [_]Range{
            .{ .from = Coord.new(rect.start.x + 1, rect.start.y - 1), .to = Coord.new(rect_end.x - 2, rect.start.y - 1) }, // top
            .{ .from = Coord.new(rect.start.x + 1, rect_end.y), .to = Coord.new(rect_end.x - 2, rect_end.y) }, // bottom
            .{ .from = Coord.new(rect.start.x - 1, rect.start.y + 1), .to = Coord.new(rect.start.x - 1, rect_end.y - 2) }, // left
            .{ .from = Coord.new(rect_end.x, rect.start.y + 1), .to = Coord.new(rect_end.x, rect_end.y - 2) }, // right
        };
    }
}

fn randomWallCoord(rect: *const Rect, i: ?usize) Coord {
    const ranges = computeWallAreas(rect, false);
    const range = if (i) |_i| ranges[(_i + 1) % ranges.len] else rng.chooseUnweighted(Range, &ranges);
    // Clump is set to 1 for now
    // (Was 2 previously, which wouldn't work when placing lights in gigantic
    // corridors since they'd all be clustered together)
    const x = rng.rangeClumping(usize, range.from.x, range.to.x, 1);
    const y = rng.rangeClumping(usize, range.from.y, range.to.y, 1);
    return Coord.new2(rect.start.z, x, y);
}

fn _chooseLootItem(list: []const ItemTemplate, value_range: MinMax(usize), class: ?ItemTemplate.Type) ItemTemplate {
    while (true) {
        var item_info = rng.choose2(ItemTemplate, list, "w") catch err.wat();

        if (!value_range.contains(item_info.w))
            continue;

        if (class) |_|
            if (item_info.i != class.?)
                continue;

        if (item_info.i == .List) {
            return rng.choose2(ItemTemplate, item_info.i.List, "w") catch err.wat();
        } else {
            return item_info;
        }
    }
}

pub fn placeProp(coord: Coord, prop_template: *const Prop) *Prop {
    var prop = prop_template.*;
    prop.coord = coord;
    state.props.append(prop) catch err.wat();
    const propptr = state.props.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Prop = propptr };
    return state.props.last().?;
}

fn placeContainer(coord: Coord, template: *const Container) *Container {
    var container = template.*;
    container.coord = coord;
    state.containers.append(container) catch err.wat();
    const ptr = state.containers.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Container = ptr };
    return ptr;
}

fn _place_machine(coord: Coord, machine_template: *const Machine) void {
    var machine = machine_template.*;
    machine.coord = coord;
    state.machines.append(machine) catch err.wat();
    const machineptr = state.machines.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = machineptr };
    if (machineptr.on_place) |on_place| on_place(machineptr);
}

pub fn placeDoor(coord: Coord, locked: bool) void {
    var door = if (locked) surfaces.LockedDoor else Configs[coord.z].door.*;
    door.coord = coord;
    state.machines.append(door) catch err.wat();
    const doorptr = state.machines.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = doorptr };
    state.dungeon.at(coord).type = .Floor;
}

pub fn placePlayer(coord: Coord, alloc: mem.Allocator) void {
    assert(!state.player_inited);

    if (state.dungeon.at(coord).mob) |mob|
        mob.deinitNoCorpse();

    state.player = mobs.placeMob(alloc, &mobs.PlayerTemplate, coord, .{ .phase = .Hunt });

    // state.player.inventory.equipment(.Ring1).* = Item{ .Ring = items.createItem(Ring, items.ConjurationRing) };
    // state.player.inventory.equipment(.Ring2).* = Item{ .Ring = items.createItem(Ring, items.ExcisionRing) };
    // state.player.inventory.equipment(.Ring3).* = Item{ .Ring = items.createItem(Ring, items.DamnationRing) };
    // state.player.inventory.equipment(.Ring4).* = Item{ .Ring = items.createItem(Ring, items.LightningRing) };
    // state.player.inventory.equipment(.Ring5).* = Item{ .Ring = items.createItem(Ring, items.TeleportationRing) };

    state.player.prisoner_status = Prisoner{ .of = .Necromancer };

    state.player.squad = Squad.allocNew();
    state.player.squad.?.leader = state.player;

    //state.player.inventory.pack.append(Item{ .Consumable = &items.DecimatePotion }) catch err.wat();
    //state.player.inventory.pack.append(Item{ .Evocable = items.createItem(Evocable, items.SymbolEvoc) }) catch err.wat();
    //state.player.inventory.pack.append(Item{ .Aux = &items.DetectHeatAux }) catch err.wat();
    //state.player.inventory.pack.append(Item{ .Aux = &items.DetectElecAux }) catch err.wat();

    state.player_inited = true;
}

pub const PrefabOpts = struct {
    t_only: bool = false,
    t_corridor_only: bool = false,
    t_orientation: Direction = .South,
    max_w: usize = 999,
    max_h: usize = 999,
};

fn prefabIsValid(level: usize, prefab: *Prefab, allow_invis: bool, need_lair: bool, opts: PrefabOpts) bool {
    if (prefab.width > opts.max_w or prefab.height > opts.max_h) {
        return false; // Too big
    }

    if (prefab.invisible and !allow_invis) {
        return false; // Can't be used unless specifically called for by name.
    }

    if (prefab.whitelist.len > 0 and prefab.whitelist.linearSearch(level) == null) {
        return false; // Prefab has a whitelist and this level isn't on it.
    }

    if (prefab.tunneler_prefab != opts.t_only) {
        return false; // Prefab is only for the tunneler algorithm.
    }

    if (prefab.tunneler_corridor_prefab != opts.t_corridor_only) {
        return false; // Prefab is only for tunneler subrooms
    }

    if (prefab.tunneler_prefab and prefab.tunneler_orientation.len != 0 and
        prefab.tunneler_orientation.linearSearch(opts.t_orientation) == null)
    {
        return false; // This is a prefab for tunneler's corridor and is the wrong orientation.
    }

    if (need_lair) {
        if (!mem.eql(u8, prefab.name.constSlice()[0..3], "LAI")) {
            return false; // We need a subroom for the lairs
        }
    } else {
        if (!mem.eql(u8, prefab.name.constSlice()[0..3], state.levelinfo[level].id) and
            !mem.eql(u8, prefab.name.constSlice()[0..3], "ANY"))
        {
            return false; // Prefab isn't for this level.
        }
    }

    const record = state.fab_records.getOrPut(prefab.name.constSlice()) catch err.wat();
    if (record.found_existing) {
        if (record.value_ptr.level[level] >= prefab.restriction or
            record.value_ptr.global >= prefab.global_restriction or
            prefab.level_uses[level] >= prefab.individual_restriction)
        {
            return false; // Prefab was used too many times.
        }
    } else {
        record.value_ptr.* = .{};
    }

    return true;
}

pub fn choosePrefab(level: usize, prefabs: *PrefabArrayList, opts: PrefabOpts) ?*Prefab {
    var fab_list = std.ArrayList(*Prefab).init(state.gpa.allocator());
    defer fab_list.deinit();
    for (prefabs.items) |*prefab| if (prefabIsValid(level, prefab, false, false, opts)) {
        fab_list.append(prefab) catch err.wat();
    };
    if (fab_list.items.len == 0) return null;
    return rng.choose2(*Prefab, fab_list.items, "priority") catch err.wat();
}

fn attachRect(parent: *const Room, d: Direction, width: usize, height: usize, distance: usize, fab: ?*const Prefab) ?Rect {
    // "Preferred" X/Y coordinates to start the child at. preferred_x is only
    // valid if d == .North or d == .South, and preferred_y is only valid if
    // d == .West or d == .East.
    var preferred_x = parent.rect.start.x + (parent.rect.width / 2);
    var preferred_y = parent.rect.start.y + (parent.rect.height / 2);

    // Note: the coordinate returned by Prefab.connectorFor() is relative.

    if (parent.prefab != null and fab != null) {
        const parent_con = parent.prefab.?.connectorFor(d) orelse return null;
        const child_con = fab.?.connectorFor(d.opposite()) orelse return null;
        const parent_con_abs = Coord.new2(
            parent.rect.start.z,
            parent.rect.start.x + parent_con.x,
            parent.rect.start.y + parent_con.y,
        );
        preferred_x = parent_con_abs.x -| child_con.x;
        preferred_y = parent_con_abs.y -| child_con.y;
    } else if (parent.prefab) |pafab| {
        const con = pafab.connectorFor(d) orelse return null;
        preferred_x = parent.rect.start.x + con.x;
        preferred_y = parent.rect.start.y + con.y;
    } else if (fab) |chfab| {
        const con = chfab.connectorFor(d.opposite()) orelse return null;
        preferred_x = parent.rect.start.x -| con.x;
        preferred_y = parent.rect.start.y -| con.y;
    }

    return switch (d) {
        .North => Rect{
            .start = Coord.new2(parent.rect.start.z, preferred_x, parent.rect.start.y -| (height + distance)),
            .height = height,
            .width = width,
        },
        .East => Rect{
            .start = Coord.new2(parent.rect.start.z, parent.rect.end().x + distance, preferred_y),
            .height = height,
            .width = width,
        },
        .South => Rect{
            .start = Coord.new2(parent.rect.start.z, preferred_x, parent.rect.end().y + distance),
            .height = height,
            .width = width,
        },
        .West => Rect{
            .start = Coord.new2(parent.rect.start.z, parent.rect.start.x -| (width + distance), preferred_y),
            .width = width,
            .height = height,
        },
        else => err.todo(),
    };
}

pub fn findIntersectingRoom(
    rooms: *const Room.ArrayList,
    room: *const Room,
    ignore: ?*const Room,
    ignore2: ?*const Room,
    ignore_corridors: bool,
) ?usize {
    for (rooms.items) |other, i| {
        if (ignore) |ign| {
            if (other.rect.start.eq(ign.rect.start))
                if (other.rect.width == ign.rect.width and other.rect.height == ign.rect.height)
                    continue;
        }

        if (ignore2) |ign| {
            if (other.rect.start.eq(ign.rect.start))
                if (other.rect.width == ign.rect.width and other.rect.height == ign.rect.height)
                    continue;
        }

        if (other.type == .Corridor and (other.rect.width == 1 or other.rect.height == 1) and ignore_corridors) {
            continue;
        }

        if (room.rect.intersects(&other.rect, 1)) return i;
    }

    return null;
}

pub fn isRoomInvalid(
    rooms: *const Room.ArrayList,
    room: *const Room,
    ignore: ?*const Room,
    ignore2: ?*const Room,
    ign_c: bool,
) bool {
    if (room.rect.overflowsLimit(&LIMIT)) {
        return true;
    }

    if (Configs[room.rect.start.z].require_dry_rooms) {
        var y: usize = room.rect.start.y;
        while (y < room.rect.end().y) : (y += 1) {
            var x: usize = room.rect.start.x;
            while (x < room.rect.end().x) : (x += 1) {
                const coord = Coord.new2(room.rect.start.z, x, y);
                if (state.dungeon.at(coord).type == .Lava or
                    state.dungeon.at(coord).type == .Water or
                    state.dungeon.terrainAt(coord) == &surfaces.ShallowWaterTerrain or
                    state.dungeon.terrainAt(coord) == &surfaces.WaterTerrain)
                {
                    return true;
                }
            }
        }
    }

    if (findIntersectingRoom(rooms, room, ignore, ignore2, ign_c)) |_| {
        return true;
    }

    return false;
}

pub fn excavatePrefab(
    room: *Room,
    fab: *const Prefab,
    allocator: mem.Allocator,
    startx: usize,
    starty: usize,
) void {
    // Clear out prefab area.
    //
    // We could do this at the same time as excavation and placing objects, but
    // that breaks prefabs that have multitile mobs (since the mob is placed,
    // then subsequent tiles are cleared of that mob leaving only one tile
    // with the mob on it)
    //
    var y: usize = 0;
    while (y < fab.height) : (y += 1) {
        var x: usize = 0;
        while (x < fab.width) : (x += 1) {
            const rc = Coord.new2(
                room.rect.start.z,
                x + room.rect.start.x + startx,
                y + room.rect.start.y + starty,
            );
            assert(rc.x < WIDTH);
            assert(rc.y < HEIGHT);

            state.dungeon.at(rc).surface = null;
            state.dungeon.itemsAt(rc).clear();

            if (state.dungeon.at(rc).mob) |m| m.deinitNoCorpse();
            state.dungeon.at(rc).mob = null;
        }
    }

    y = 0;
    while (y < fab.height) : (y += 1) {
        var x: usize = 0;
        while (x < fab.width) : (x += 1) {
            const rc = Coord.new2(
                room.rect.start.z,
                x + room.rect.start.x + startx,
                y + room.rect.start.y + starty,
            );

            const tt: ?TileType = switch (fab.content[y][x]) {
                .Any, .Connection => null,
                .Window, .Wall => .Wall,
                .Water,
                .LevelFeature,
                .Feature,
                .LockedDoor,
                .HeavyLockedDoor,
                .Door,
                .Bars,
                .Brazier,
                .ShallowWater,
                .Floor,
                .Loot1,
                .RareLoot,
                .Corpse,
                .Ring,
                => .Floor,
                //.Water => .Water,
                .Lava => .Lava,
            };
            if (tt) |_tt| state.dungeon.at(rc).type = _tt;

            if (fab.material) |mat|
                if (fab.content[y][x] != .Any) {
                    state.dungeon.at(rc).material = mat;
                };

            if (fab.terrain) |t|
                state.dungeon.at(rc).terrain = t;

            switch (fab.content[y][x]) {
                .Window => state.dungeon.at(rc).material = Configs[room.rect.start.z].window_material,
                .LevelFeature => |l| (Configs[room.rect.start.z].level_features[l].?)(l, rc, room, fab, allocator),
                .Feature => |feature_id| {
                    if (fab.features[feature_id]) |feature| {
                        switch (feature) {
                            .Stair => |stair| {
                                state.dungeon.at(rc).surface = .{ .Stair = stair };
                            },
                            .Key => |key| {
                                state.dungeon.itemsAt(rc).append(Item{ .Key = .{
                                    .lock = key,
                                    .level = rc.z,
                                } }) catch err.wat();
                            },
                            .Item => |template| {
                                state.dungeon.itemsAt(rc).append(items.createItemFromTemplate(template)) catch err.wat();
                            },
                            .Mob => |mob| {
                                _ = mobs.placeMob(allocator, mob, rc, .{});
                            },
                            .CMob => |mob_info| {
                                _ = mobs.placeMob(allocator, mob_info.t, rc, mob_info.opts);
                            },
                            .CCont => |container_info| {
                                fillLootContainer(
                                    placeContainer(rc, container_info.t),
                                    rng.range(usize, 0, 1),
                                );
                            },
                            .Cpitem => |prop_info| {
                                const chosen = rng.choose(?*const Prop, prop_info.ts.constSlice(), prop_info.we.constSlice()) catch err.wat();
                                if (chosen) |c|
                                    state.dungeon.itemsAt(rc).append(Item{ .Prop = c }) catch err.wat();
                            },
                            .Poster => |poster| {
                                state.dungeon.at(rc).surface = SurfaceItem{ .Poster = poster };
                            },
                            .Prop => |pid| {
                                if (utils.findById(surfaces.props.items, pid)) |prop| {
                                    _ = placeProp(rc, &surfaces.props.items[prop]);
                                } else std.log.err(
                                    "{s}: Couldn't load prop {s}, skipping.",
                                    .{ fab.name.constSlice(), utils.used(pid) },
                                );
                            },
                            .Machine => |mid| {
                                if (utils.findById(&surfaces.MACHINES, mid.id)) |mach| {
                                    _place_machine(rc, &surfaces.MACHINES[mach]);
                                    const machine = state.dungeon.at(rc).surface.?.Machine;
                                    for (mid.points.constSlice()) |point| {
                                        const adj_point = Coord.new2(
                                            room.rect.start.z,
                                            point.x + room.rect.start.x + startx,
                                            point.y + room.rect.start.y + starty,
                                        );
                                        machine.areas.append(adj_point) catch err.wat();
                                    }
                                } else {
                                    std.log.err(
                                        "{s}: Couldn't load machine {s}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(mid.id) },
                                    );
                                }
                            },
                        }
                    } else {
                        std.log.err(
                            "{s}: Feature '{c}' not present, skipping.",
                            .{ fab.name.constSlice(), feature_id },
                        );
                    }
                },
                .LockedDoor => placeDoor(rc, true),
                .HeavyLockedDoor => _place_machine(rc, &surfaces.HeavyLockedDoor),
                .Door => placeDoor(rc, false),
                .Brazier => _place_machine(rc, Configs[room.rect.start.z].light),
                .ShallowWater => state.dungeon.at(rc).terrain = &surfaces.ShallowWaterTerrain,
                .Water => state.dungeon.at(rc).terrain = &surfaces.WaterTerrain,
                .Bars => {
                    const p_ind = utils.findById(surfaces.props.items, Configs[room.rect.start.z].bars);
                    _ = placeProp(rc, &surfaces.props.items[p_ind.?]);
                },
                .Loot1 => {
                    const drop_list = if (room.is_lair) &items.NIGHT_ITEM_DROPS else &items.ITEM_DROPS;
                    const loot_item1 = _chooseLootItem(drop_list, minmax(usize, 60, 200), null);
                    state.dungeon.itemsAt(rc).append(items.createItemFromTemplate(loot_item1)) catch err.wat();
                },
                .RareLoot => {
                    const drop_list = if (room.is_lair) &items.NIGHT_ITEM_DROPS else &items.ITEM_DROPS;
                    const rare_loot_item = _chooseLootItem(drop_list, minmax(usize, 0, 60), null);
                    state.dungeon.itemsAt(rc).append(items.createItemFromTemplate(rare_loot_item)) catch err.wat();
                },
                .Corpse => {
                    if (state.dungeon.at(rc).mob != null) {
                        // TODO: we should create the prisoner corpse somewhere else
                        // and then move it here.
                    } else {
                        const prisoner = mobs.placeMob(allocator, &mobs.GoblinTemplate, rc, .{});
                        prisoner.prisoner_status = Prisoner{ .of = .Necromancer };
                        prisoner.deinit();
                    }
                },
                .Ring => {
                    const ring = items.createItemFromTemplate(chooseRing(room.is_lair));
                    state.dungeon.itemsAt(rc).append(ring) catch err.wat();
                },
                else => {},
            }
        }
    }

    for (fab.mobs) |maybe_mob| {
        if (maybe_mob) |mob_f| {
            if (mobs.findMobById(mob_f.id)) |mob_template| {
                const coord = Coord.new2(
                    room.rect.start.z,
                    mob_f.spawn_at.x + room.rect.start.x + startx,
                    mob_f.spawn_at.y + room.rect.start.y + starty,
                );

                if (state.dungeon.at(coord).type == .Wall) {
                    std.log.err(
                        "{s}: Tried to place mob in wall. (this is a bug.)",
                        .{fab.name.constSlice()},
                    );
                    continue;
                }

                const work_area = Coord.new2(
                    room.rect.start.z,
                    (mob_f.work_at orelse mob_f.spawn_at).x + room.rect.start.x + startx,
                    (mob_f.work_at orelse mob_f.spawn_at).y + room.rect.start.y + starty,
                );

                _ = mobs.placeMob(allocator, mob_template, coord, .{
                    .work_area = work_area,
                });
            } else {
                std.log.err(
                    "{s}: Couldn't load mob {s}, skipping.",
                    .{ fab.name.constSlice(), utils.used(mob_f.id) },
                );
            }
        }
    }

    for (fab.prisons.constSlice()) |prison_area| {
        const prison_start = Coord.new2(
            room.rect.start.z,
            prison_area.start.x + room.rect.start.x + startx,
            prison_area.start.y + room.rect.start.y + starty,
        );
        const prison_end = Coord.new2(
            room.rect.start.z,
            prison_area.end().x + room.rect.start.x + startx,
            prison_area.end().y + room.rect.start.y + starty,
        );

        var p_y: usize = prison_start.y;
        while (p_y < prison_end.y) : (p_y += 1) {
            var p_x: usize = prison_start.x;
            while (p_x < prison_end.x) : (p_x += 1) {
                state.dungeon.at(Coord.new2(room.rect.start.z, p_x, p_y)).prison = true;
            }
        }
    }

    if (fab.stockpile) |stockpile| {
        const room_start = Coord.new2(
            room.rect.start.z,
            stockpile.start.x + room.rect.start.x + startx,
            stockpile.start.y + room.rect.start.y + starty,
        );
        var stckpl = Stockpile{
            .room = Rect{
                .start = room_start,
                .width = stockpile.width,
                .height = stockpile.height,
            },
            .type = undefined,
        };
        const inferred = stckpl.inferType();
        if (!inferred) {
            std.log.err("{s}: Couldn't infer type for stockpile! (skipping)", .{fab.name.constSlice()});
        } else {
            state.stockpiles[room.rect.start.z].append(stckpl) catch err.wat();
        }
    }

    if (fab.output) |output| {
        const room_start = Coord.new2(
            room.rect.start.z,
            output.start.x + room.rect.start.x + startx,
            output.start.y + room.rect.start.y + starty,
        );
        state.outputs[room.rect.start.z].append(Rect{
            .start = room_start,
            .width = output.width,
            .height = output.height,
        }) catch err.wat();
    }

    if (fab.input) |input| {
        const room_start = Coord.new2(
            room.rect.start.z,
            input.start.x + room.rect.start.x + startx,
            input.start.y + room.rect.start.y + starty,
        );
        var input_stckpl = Stockpile{
            .room = Rect{
                .start = room_start,
                .width = input.width,
                .height = input.height,
            },
            .type = undefined,
        };
        const inferred = input_stckpl.inferType();
        if (!inferred) {
            std.log.err("{s}: Couldn't infer type for input area! (skipping)", .{fab.name.constSlice()});
        } else {
            state.inputs[room.rect.start.z].append(input_stckpl) catch err.wat();
        }
    }

    // Don't place sub-subrooms if this is a subroom, that's placeSubroom's job
    if (!fab.subroom) {
        for (fab.subroom_areas.constSlice()) |subroom_area| {
            _ = placeSubroom(room, &subroom_area.rect, allocator, .{
                .specific_id = if (subroom_area.specific_id) |id| id.constSlice() else null,
                .no_padding = true,
            });
        }
    }
}

pub fn fillRect(rect: *const Rect, with: TileType) void {
    var y = rect.start.y;
    while (y < rect.end().y) : (y += 1) {
        var x = rect.start.x;
        while (x < rect.end().x) : (x += 1) {
            const c = Coord.new2(rect.start.z, x, y);
            assert(c.x < WIDTH and c.y < HEIGHT);
            state.dungeon.at(c).type = with;
        }
    }
}

pub fn excavateRect(rect: *const Rect) void {
    fillRect(rect, .Floor);
}

// Destroy items, machines, and mobs associated with level and reset level's
// terrain.
//
// Also, reset the `used` counters and connections for prefabs.
pub fn resetLevel(level: usize) void {
    for (n_fabs.items) |*fab| fab.reset(level);
    for (s_fabs.items) |*fab| fab.reset(level);

    var mobiter = state.mobs.iterator();
    while (mobiter.next()) |mob| {
        if (mob == state.player)
            state.player_inited = false;
        if (mob.coord.z == level and !mob.is_dead) {
            mob.deinitNoCorpse();
            state.mobs.remove(mob);
        }
    }

    var machiter = state.machines.iterator();
    while (machiter.next()) |machine| {
        if (machine.coord.z == level) {
            state.machines.remove(machine);
        }
    }
    state.alarm_locations[level].reinit(null);

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const is_edge = y == 0 or x == 0 or y == (HEIGHT - 1) or x == (WIDTH - 1);
            const coord = Coord.new2(level, x, y);

            const tile = state.dungeon.at(coord);
            tile.prison = false;
            tile.marked = false;
            tile.type = if (is_edge) .Wall else Configs[level].tiletype;
            tile.material = &materials.Basalt;
            tile.mob = null;
            tile.surface = null;
            tile.spatter = SpatterArray.initFill(0);

            state.layout[level][y][x] = .Unknown;
            state.dungeon.itemsAt(coord).clear();
        }
    }

    state.rooms[level].shrinkRetainingCapacity(0);
    state.stockpiles[level].shrinkRetainingCapacity(0);
    state.inputs[level].shrinkRetainingCapacity(0);
    state.outputs[level].shrinkRetainingCapacity(0);

    state.dungeon.entries[level] = undefined;
    state.dungeon.stairs[level].clear();
    state.mapgen_infos[level] = .{};
    state.shrine_locations[level] = null;
}

pub fn setLevelMaterial(level: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);

            // If it's not the default material, don't reset it
            // Doing so would destroy glass blocks, etc
            if (!mem.eql(u8, "basalt", state.dungeon.at(coord).material.name))
                continue;

            if (state.dungeon.neighboringWalls(coord, true) < 9)
                state.dungeon.at(coord).material = Configs[level].material;
        }
    }
}

// Validate levels, ensuring they're all connected.
//
// Also assign each room an "importance" number, because we may as well do it
// now when we're getting paths to all of them.
//
pub fn validateLevel(level: usize, alloc: mem.Allocator) !void {
    // utility functions
    const _f = struct {
        pub fn _getWalkablePoint(room: *const Room) Coord {
            var y: usize = room.rect.start.y;
            while (y < room.rect.end().y) : (y += 1) {
                var x: usize = room.rect.start.x;
                while (x < room.rect.end().x) : (x += 1) {
                    const point = Coord.new2(room.rect.start.z, x, y);
                    if (state.is_walkable(point, .{})) {
                        return point;
                    }
                }
            }
            std.log.err(
                "BUG: found no walkable point in room (dim: {}x{}, prefab: {s})",
                .{ room.rect.width, room.rect.height, room.prefabId() },
            );
            err.wat();
        }
    };

    const rooms = state.rooms[level].items;

    if (rooms.len < 1)
        return error.TooFewRooms;

    for (rooms) |room| {
        if (room.rect.height == 0 or room.rect.width == 0)
            return error.ZeroDimensionedRooms;
    }

    // Ensure that all required prefabs were used.
    for (Configs[level].prefabs) |required_fab| {
        const fab = Prefab.findPrefabByName(required_fab, &n_fabs) orelse
            Prefab.findPrefabByName(required_fab, &s_fabs).?;

        const rec = state.fab_records.getPtr(fab.name.constSlice());
        if (rec == null or rec.?.level[level] == 0) {
            return error.RequiredPrefabsNotUsed;
        }
    }

    const point = state.dungeon.entries[level];

    for (rooms) |*otherroom| {
        if (otherroom.type == .Corridor)
            continue;

        // Hack to fix mapgen screwing up when determining paths to machine-only
        // inset prefabs, like SIN candles or WRK alarms
        if (otherroom.prefab) |fab|
            if (fab.tunneler_inset)
                continue;

        const otherpoint = _f._getWalkablePoint(otherroom);

        if (astar.path(point, otherpoint, state.mapgeometry, state.is_walkable, .{
            .ignore_mobs = true,
        }, astar.dummyPenaltyFunc, &DIRECTIONS, alloc)) |p| {
            for (p.items) |path_coord| {
                const room_id = utils.getRoomFromCoord(level, path_coord) orelse continue;
                state.rooms[level].items[room_id].importance += 1;
            }
            p.deinit();
        } else {
            return error.RoomsNotConnected;
        }
    }
}

pub fn selectLevelVault(level: usize) void {
    if (VAULT_LEVELS[level].len == 0) {
        return;
    }

    const vault_kind = rng.chooseUnweighted(VaultType, VAULT_LEVELS[level]);

    var candidates = std.ArrayList(usize).init(state.gpa.allocator());
    defer candidates.deinit();

    for (state.rooms[level].items) |room, i| {
        if (room.connections.len == 1 and
            !room.is_lair and !room.is_extension_room and !room.has_subroom and room.prefab == null and
            !state.mapgen_infos[level].has_vault)
        {
            candidates.append(i) catch err.wat();
        }
    }

    if (candidates.items.len == 0) {
        return;
    }

    const selected_room_i = rng.chooseUnweighted(usize, candidates.items);
    state.rooms[level].items[selected_room_i].is_vault = vault_kind;
}

pub fn modifyRoomToLair(room: *Room) void {
    room.is_lair = true;

    // Reset room to walls
    {
        var y: usize = room.rect.start.y;
        while (y < room.rect.end().y) : (y += 1) {
            var x: usize = room.rect.start.x;
            while (x < room.rect.end().x) : (x += 1) {
                const coord = Coord.new2(room.rect.start.z, x, y);
                state.dungeon.at(coord).type = .Wall;
            }
        }
    }

    const config = BlobConfig{
        .type = .Floor,
        .min_blob_width = minmax(usize, room.rect.width * 60 / 100, room.rect.width * 60 / 100),
        .min_blob_height = minmax(usize, room.rect.height * 60 / 100, room.rect.height * 60 / 100),
        .max_blob_width = minmax(usize, room.rect.width - 1, room.rect.width - 1),
        .max_blob_height = minmax(usize, room.rect.height - 1, room.rect.height - 1),
        .ca_rounds = 5,
        .ca_percent_seeded = 50,
        .ca_birth_params = "ffffftttt",
        .ca_survival_params = "ffffttttt",
    };

    placeBlob(config, Coord.new2(room.rect.start.z, room.rect.start.x + 1, room.rect.start.y + 1));

    var walkable_coord: Coord = undefined;

    {
        var y: usize = room.rect.start.y;
        walkable_coord_search: while (y < room.rect.end().y) : (y += 1) {
            var x: usize = room.rect.start.x;
            while (x < room.rect.end().x) : (x += 1) {
                const coord = Coord.new2(room.rect.start.z, x, y);
                if (state.dungeon.at(coord).type == .Floor) {
                    walkable_coord = coord;
                    break :walkable_coord_search;
                }
            }
        }
    }

    // FIXME: the door var should never, never be null...
    //
    if (room.connections.last().?.door != null) {
        const path = astar.path(walkable_coord, room.connections.last().?.door.?, state.mapgeometry, struct {
            pub fn f(c: Coord, opts: state.IsWalkableOptions) bool {
                return opts.confines.intersects(&c.asRect(), 1);
            }
        }.f, .{ .confines = room.rect }, struct {
            pub fn f(c: Coord, opts: state.IsWalkableOptions) usize {
                if (!opts.confines.intersects(&c.asRect(), 0)) {
                    return 10000;
                }
                return if (state.dungeon.at(c).type == .Wall) 10 else 0;
            }
        }.f, &CARDINAL_DIRECTIONS, state.gpa.allocator()) orelse return;
        defer path.deinit();
        for (path.items) |coord| {
            state.dungeon.at(coord).type = .Floor;
        }
    }
}

pub fn selectLevelLairs(level: usize) void {
    if (Configs[level].lair_max == 0)
        return;

    var candidates = std.ArrayList(usize).init(state.gpa.allocator());
    defer candidates.deinit();

    for (state.rooms[level].items) |room, i| {
        if (room.connections.len == 1 and
            !room.is_extension_room and !room.has_subroom and room.prefab == null and
            room.rect.width >= 8 and room.rect.height >= 8)
        {
            candidates.append(i) catch err.wat();
        }
    }

    if (candidates.items.len == 0)
        return;
    rng.shuffle(usize, candidates.items);

    var lair_count = rng.range(usize, 1, math.min(candidates.items.len, Configs[level].lair_max));
    while (lair_count > 0) : (lair_count -= 1) {
        modifyRoomToLair(&state.rooms[level].items[candidates.items[lair_count - 1]]);
    }
}

pub fn placeMoarCorridors(level: usize, alloc: mem.Allocator) void {
    var newrooms = Room.ArrayList.init(alloc);
    defer newrooms.deinit();

    const rooms = &state.rooms[level];

    var i: usize = 0;
    while (i < rooms.items.len) : (i += 1) {
        const parent = &rooms.items[i];

        for (rooms.items) |*child| {
            if (parent.is_lair or child.is_lair or
                parent.is_vault != null or child.is_vault != null or
                parent.connections.isFull() or
                child.connections.isFull() or
                parent.hasCloseConnectionTo(child.rect) or
                child.hasCloseConnectionTo(parent.rect))
            {
                continue;
            }

            //if (child.type == .Corridor) continue;

            // Skip child prefabs for now, placeCorridor seems to be broken
            // FIXME
            if (child.prefab != null) continue;

            if (parent.rect.intersects(&child.rect, 1)) {
                continue;
            }

            if (parent.rect.start.eq(child.rect.start)) {
                // skip ourselves
                continue;
            }

            var side: ?Direction = getConnectionSide(parent, child);
            if (side == null) continue;

            if (createCorridor(level, parent, child, side.?)) |corridor| {
                if (corridor.distance == 0 or corridor.distance > 9) {
                    continue;
                }

                if (isRoomInvalid(rooms, &corridor.room, parent, child, false) or
                    isRoomInvalid(&newrooms, &corridor.room, parent, child, false))
                {
                    continue;
                }

                parent.connections.append(.{ .room = child.rect.start, .door = corridor.parent_door }) catch err.wat();
                child.connections.append(.{ .room = parent.rect.start, .door = corridor.child_door }) catch err.wat();

                excavateRect(&corridor.room.rect);
                corridor.markConnectorsAsUsed(parent, child) catch err.wat();
                newrooms.append(corridor.room) catch err.wat();

                // When using a prefab, the corridor doesn't include the connectors. Excavate
                // the connectors (both the beginning and the end) manually.
                if (corridor.parent_connector) |acon| state.dungeon.at(acon).type = .Floor;
                if (corridor.child_connector) |acon| state.dungeon.at(acon).type = .Floor;

                if (rng.tenin(Configs[level].door_chance)) {
                    if (utils.findPatternMatch(corridor.room.rect.start, &VALID_DOOR_PLACEMENT_PATTERNS) != null)
                        placeDoor(corridor.room.rect.start, false);
                }
                if (rng.tenin(Configs[level].door_chance)) {
                    if (utils.findPatternMatch(corridor.room.rect.end(), &VALID_DOOR_PLACEMENT_PATTERNS) != null)
                        placeDoor(corridor.room.rect.end(), false);
                }
            }
        }
    }

    for (newrooms.items) |new| rooms.append(new) catch err.wat();
}

fn createCorridor(level: usize, parent: *Room, child: *Room, side: Direction) ?Corridor {
    var corridor_coord = Coord.new2(level, 0, 0);
    var parent_connector_coord: ?Coord = null;
    var child_connector_coord: ?Coord = null;
    var fab_connectors = [_]?Coord{ null, null };

    if (parent.prefab != null or child.prefab != null) {
        if (parent.prefab) |f| {
            const con = f.connectorFor(side) orelse return null;
            corridor_coord.x = parent.rect.start.x + con.x;
            corridor_coord.y = parent.rect.start.y + con.y;
            parent_connector_coord = corridor_coord;
            fab_connectors[0] = con;
        }
        if (child.prefab) |f| {
            const con = f.connectorFor(side.opposite()) orelse return null;
            corridor_coord.x = child.rect.start.x + con.x;
            corridor_coord.y = child.rect.start.y + con.y;
            child_connector_coord = corridor_coord;
            fab_connectors[1] = con;
        }
    } else {
        const rsx = math.max(parent.rect.start.x, child.rect.start.x);
        const rex = math.min(parent.rect.end().x, child.rect.end().x);
        const rsy = math.max(parent.rect.start.y, child.rect.start.y);
        const rey = math.min(parent.rect.end().y, child.rect.end().y);
        corridor_coord.x = rng.range(usize, math.min(rsx, rex), math.max(rsx, rex) - 1);
        corridor_coord.y = rng.range(usize, math.min(rsy, rey), math.max(rsy, rey) - 1);
    }

    var room = switch (side) {
        .North => Room{
            .rect = Rect{
                .start = Coord.new2(level, corridor_coord.x, child.rect.end().y),
                .height = parent.rect.start.y - child.rect.end().y,
                .width = 1,
            },
        },
        .South => Room{
            .rect = Rect{
                .start = Coord.new2(level, corridor_coord.x, parent.rect.end().y),
                .height = child.rect.start.y - parent.rect.end().y,
                .width = 1,
            },
        },
        .West => Room{
            .rect = Rect{
                .start = Coord.new2(level, child.rect.end().x, corridor_coord.y),
                .height = 1,
                .width = parent.rect.start.x - child.rect.end().x,
            },
        },
        .East => Room{
            .rect = Rect{
                .start = Coord.new2(level, parent.rect.end().x, corridor_coord.y),
                .height = 1,
                .width = child.rect.start.x - parent.rect.end().x,
            },
        },
        else => err.wat(),
    };

    // Hack
    const parent_door = if (room.rect.start.distance(parent.rect.start) < room.rect.end().distance(parent.rect.start)) room.rect.start else room.rect.end();
    const child_door = if (room.rect.start.distance(child.rect.start) < room.rect.end().distance(child.rect.start)) room.rect.start else room.rect.end();

    room.type = .Corridor;

    return Corridor{
        .room = room,
        .parent = parent,
        .child = child,
        .parent_connector = parent_connector_coord,
        .child_connector = child_connector_coord,
        .parent_door = parent_door,
        .child_door = child_door,
        .distance = switch (side) {
            .North, .South => room.rect.height,
            .West, .East => room.rect.width,
            else => err.wat(),
        },
        .fab_connectors = fab_connectors,
    };
}

pub const SubroomPlacementOptions = struct {
    specific_id: ?[]const u8 = null,
    specific_fab: ?*Prefab = null,
    for_lair: bool = false,
    no_padding: bool = false,
};

pub fn placeSubroom(parent: *Room, area: *const Rect, alloc: mem.Allocator, opts: SubroomPlacementOptions) bool {
    assert(area.end().y < HEIGHT and area.end().x < WIDTH);

    var buf = StackBuffer(*Prefab, 128).init(null);

    for (s_fabs.items) |*subroom| {
        if (opts.specific_id) |id| {
            if (!mem.eql(u8, subroom.name.constSlice(), id)) {
                continue;
            }
        }
        if (opts.specific_fab) |ptr| {
            if (subroom != ptr) {
                continue;
            }
        }

        if (!prefabIsValid(parent.rect.start.z, subroom, opts.specific_id != null, opts.for_lair, .{})) {
            continue;
        }

        if (subroom.center_align) {
            if (subroom.height % 2 != area.height % 2 or
                subroom.width % 2 != area.width % 2)
            {
                continue;
            }
        }

        const minheight = subroom.height + if (opts.no_padding or subroom.nopadding) @as(usize, 0) else 2;
        const minwidth = subroom.width + if (opts.no_padding or subroom.nopadding) @as(usize, 0) else 2;

        if (minheight > area.height or minwidth > area.width) {
            // if (mem.eql(u8, subroom.name.constSlice(), "PRI_s_s_cell_4_empty_walls_horiz") and opts.no_padding)
            //     std.log.info("rejected (invalid size): minheight={}, minwidth={}, areaheight={}, areawidth={}", .{ minheight, minwidth, area.height, area.width }); // DEBUG
            continue;
        }

        buf.append(subroom) catch {
            std.log.warn("More prefabs than can fit inside buffer", .{});
            break;
        };
    }

    if (buf.len == 0) return false;

    const subroom = buf.chooseUnweighted().?;

    const rx = (area.width / 2) - (subroom.width / 2);
    const ry = (area.height / 2) - (subroom.height / 2);

    var parent_adj = parent.*;
    parent_adj.rect = parent_adj.rect.add(area);

    //std.log.debug("mapgen: Using subroom {s} at ({}x{}+{}+{})", .{ subroom.name.constSlice(), parent_adj.rect.start.x, parent_adj.rect.start.y, rx, ry });

    excavatePrefab(&parent_adj, subroom, alloc, rx, ry);
    subroom.incrementRecord(parent.rect.start.z);
    parent.has_subroom = true;

    for (subroom.subroom_areas.constSlice()) |subroom_area| {
        const actual_subroom_area = Rect{
            .start = Coord.new2(
                0,
                rx + subroom_area.rect.start.x,
                ry + subroom_area.rect.start.y,
            ),
            .height = subroom_area.rect.height,
            .width = subroom_area.rect.width,
        };
        _ = placeSubroom(&parent_adj, &actual_subroom_area, alloc, .{
            .specific_id = if (subroom_area.specific_id) |id| id.constSlice() else null,
            .no_padding = true,
        });
    }

    return true;
}

fn _place_rooms(rooms: *Room.ArrayList, level: usize, allocator: mem.Allocator) !void {
    const parent_i = rng.range(usize, 0, rooms.items.len - 1);
    var parent = &rooms.items[parent_i];

    if (parent.connections.isFull()) {
        return;
    }

    var fab: ?*Prefab = null;
    var distance = rng.choose(usize, &Configs[level].distances[0], &Configs[level].distances[1]) catch err.wat();
    var child: Room = undefined;
    var side = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);

    if (rng.percent(Configs[level].prefab_chance)) {
        if (distance == 0) distance += 1;

        fab = choosePrefab(level, &n_fabs, .{}) orelse return;
        var childrect = attachRect(parent, side, fab.?.width, fab.?.height, distance, fab) orelse return;

        if (isRoomInvalid(rooms, &Room{ .rect = childrect }, parent, null, false) or
            childrect.overflowsLimit(&LIMIT))
        {
            if (Configs[level].shrink_corridors_to_fit) {
                while (isRoomInvalid(rooms, &Room{ .rect = childrect }, parent, null, true) or
                    childrect.overflowsLimit(&LIMIT))
                {
                    if (distance == 1) {
                        return;
                    }

                    distance -= 1;
                    childrect = attachRect(parent, side, fab.?.width, fab.?.height, distance, fab) orelse return;
                }
            } else {
                return;
            }
        }

        child = Room{ .rect = childrect, .prefab = fab };
    } else {
        if (parent.prefab != null and distance == 0) distance += 1;

        var child_w = rng.range(usize, Configs[level].min_room_width, Configs[level].max_room_width);
        var child_h = rng.range(usize, Configs[level].min_room_height, Configs[level].max_room_height);
        var childrect = attachRect(parent, side, child_w, child_h, distance, null) orelse return;

        var i: usize = 0;
        while (isRoomInvalid(rooms, &Room{ .rect = childrect }, parent, null, true) or
            childrect.overflowsLimit(&LIMIT)) : (i += 1)
        {
            if ((child_w <= Configs[level].min_room_width and
                child_h <= Configs[level].min_room_height) and
                (!Configs[level].shrink_corridors_to_fit or distance <= 1))
            {
                // We can't shrink the corridor and we can't resize the room,
                // bail out now
                return;
            }

            // Alternate between shrinking the corridor and shrinking the room
            switch (i % 2) {
                0 => {
                    if (Configs[level].shrink_corridors_to_fit and distance > 1) {
                        distance -= 1;
                    }
                },
                1 => {
                    if (child_w > Configs[level].min_room_width) child_w -= 1;
                    if (child_h > Configs[level].min_room_height) child_h -= 1;
                },
                else => unreachable,
            }

            childrect = attachRect(parent, side, child_w, child_h, distance, null) orelse return;
        }

        child = Room{ .rect = childrect };
    }

    var corridor: ?Corridor = null;

    if (distance == 0) {
        child.is_extension_room = true;
    } else {
        if (createCorridor(level, parent, &child, side)) |maybe_corridor| {
            if (isRoomInvalid(rooms, &maybe_corridor.room, parent, null, true)) {
                return;
            }
            corridor = maybe_corridor;
        } else {
            return;
        }
    }

    // Only now are we actually sure that we'd use the room

    if (child.prefab) |_| {
        excavatePrefab(&child, fab.?, allocator, 0, 0);
    } else {
        excavateRect(&child.rect);
    }

    if (corridor) |cor| {
        excavateRect(&cor.room.rect);
        cor.markConnectorsAsUsed(parent, &child) catch err.wat();

        // XXX: atchung, don't access <parent> var after this, as appending this
        // may have invalidated that pointer.
        //
        // FIXME: can't we append this along with the child at the end of this
        // function?
        rooms.append(cor.room) catch err.wat();

        // When using a prefab, the corridor doesn't include the connectors. Excavate
        // the connectors (both the beginning and the end) manually.

        if (cor.parent_connector) |acon| state.dungeon.at(acon).type = .Floor;
        if (cor.child_connector) |acon| state.dungeon.at(acon).type = .Floor;

        if (rng.tenin(Configs[level].door_chance)) {
            if (utils.findPatternMatch(
                cor.room.rect.start,
                &VALID_DOOR_PLACEMENT_PATTERNS,
            ) != null)
                placeDoor(cor.room.rect.start, false);
        }
    }

    if (child.prefab) |f| {
        f.incrementRecord(level);
    }

    if (child.prefab == null) {
        if (rng.percent(Configs[level].subroom_chance)) {
            _ = placeSubroom(&child, &Rect{
                .start = Coord.new(0, 0),
                .width = child.rect.width,
                .height = child.rect.height,
            }, allocator, .{});
        }
    } else if (child.prefab.?.subroom_areas.len > 0) {
        // for (child.prefab.?.subroom_areas.constSlice()) |subroom_area| {
        //     _ = placeSubroom(&child, &subroom_area.rect, allocator, .{
        //         .specific_id = if (subroom_area.specific_id) |id| id.constSlice() else null,
        //     });
        // }
    }

    const parent_door = if (corridor) |c| c.parent_door else null;
    const child_door = if (corridor) |c| c.child_door else null;

    // Use parent's index, as we appended the corridor earlier and that may
    // have invalidated parent's pointer
    rooms.items[parent_i].connections.append(.{ .room = child.rect.start, .door = parent_door }) catch err.wat();
    child.connections.append(.{ .room = rooms.items[parent_i].rect.start, .door = child_door }) catch err.wat();

    rooms.append(child) catch err.wat();

    captureFrame(level);
}

pub fn placeTunnelsThenRandomRooms(level: usize, alloc: mem.Allocator) void {
    tunneler.placeTunneledRooms(level, alloc);
    placeRandomRooms(level, alloc);
}

pub fn placeRandomRooms(
    level: usize,
    allocator: mem.Allocator,
) void {
    var first: ?Room = null;
    const rooms = &state.rooms[level];

    var required = Configs[level].prefabs;
    var reqctr: usize = 0;

    while (reqctr < required.len) {
        const fab_name = required[reqctr];
        const fab = Prefab.findPrefabByName(fab_name, &n_fabs) orelse {
            // Do nothing, it might be a required subroom.
            //
            // FIXME: we still should handle this error
            //
            //
            //std.log.err("Cannot find required prefab {}", .{fab_name});
            //return;
            reqctr += 1;
            continue;
        };

        const x = rng.rangeClumping(
            usize,
            math.min(fab.width, state.WIDTH - fab.width - 1),
            math.max(fab.width, state.WIDTH - fab.width - 1),
            2,
        );
        const y = rng.rangeClumping(
            usize,
            math.min(fab.height, state.HEIGHT - fab.height - 1),
            math.max(fab.height, state.HEIGHT - fab.height - 1),
            2,
        );

        var room = Room{
            .rect = Rect{
                .start = Coord.new2(level, x, y),
                .width = fab.width,
                .height = fab.height,
            },
            .prefab = fab,
        };

        if (isRoomInvalid(rooms, &room, null, null, false))
            continue;

        if (first == null) first = room;
        fab.incrementRecord(level);
        excavatePrefab(&room, fab, allocator, 0, 0);
        rooms.append(room) catch err.wat();

        reqctr += 1;
    }

    if (rooms.items.len == 0 and first == null) {
        const width = rng.range(usize, Configs[level].min_room_width, Configs[level].max_room_width);
        const height = rng.range(usize, Configs[level].min_room_height, Configs[level].max_room_height);
        const x = rng.range(usize, 1, state.WIDTH - width - 1);
        const y = rng.range(usize, 1, state.HEIGHT - height - 1);
        first = Room{
            .rect = Rect{ .start = Coord.new2(level, x, y), .width = width, .height = height },
        };
        excavateRect(&first.?.rect);
        rooms.append(first.?) catch err.wat();
    } else if (rooms.items.len > 0 and first == null) {
        first = rooms.items[0];
    }

    if (level == state.PLAYER_STARTING_LEVEL) {
        var p = Coord.new2(level, first.?.rect.start.x + 1, first.?.rect.start.y + 1);
        if (first.?.prefab) |prefab|
            if (prefab.player_position) |pos| {
                p = Coord.new2(level, first.?.rect.start.x + pos.x, first.?.rect.start.y + pos.y);
            };
        placePlayer(p, allocator);
    }

    var c = Configs[level].mapgen_iters;
    while (c > 0) : (c -= 1) {
        _place_rooms(rooms, level, allocator) catch |e| switch (e) {
            error.NoValidParent => break,
        };
    }
}

pub fn placeDrunkenWalkerCave(level: usize, alloc: mem.Allocator) void {
    const MIN_OPEN_SPACE = 50;

    var tiles_made_floors: usize = 0;
    var visited_stack = CoordArrayList.init(alloc);
    defer visited_stack.deinit();
    var walker = Coord.new2(level, WIDTH / 2, HEIGHT / 2);

    while ((tiles_made_floors * 100 / (HEIGHT * WIDTH)) < MIN_OPEN_SPACE) {
        var candidates = StackBuffer(Coord, 4).init(null);

        var gen = Generator(Coord.iterCardinalNeighbors).init(walker);
        while (gen.next()) |neighbor|
            if (state.dungeon.at(neighbor).type == .Wall) {
                candidates.append(neighbor) catch err.wat();
            };

        // for (&CARDINAL_DIRECTIONS) |d| if (walker.move(d, state.mapgeometry)) |neighbor| {
        //     if (state.dungeon.at(neighbor).type == .Wall) {
        //         candidates.append(neighbor) catch err.wat();
        //     }
        // };

        if (candidates.len == 0) {
            if (visited_stack.items.len > 0) {
                walker = visited_stack.pop();
                continue;
            } else break;
        }

        var picked = rng.chooseUnweighted(Coord, candidates.constSlice());
        state.dungeon.at(picked).type = .Floor;
        tiles_made_floors += 1;
        visited_stack.append(walker) catch err.wat();
        walker = picked;
    }

    var walls_to_remove = CoordArrayList.init(alloc);
    defer walls_to_remove.deinit();

    var gen = Generator(Rect.rectIter).init(state.mapRect(level));
    while (gen.next()) |coord| {
        if (state.dungeon.at(coord).type == .Wall and
            state.dungeon.neighboringOfType(coord, true, .Floor) >= 4)
        {
            walls_to_remove.append(coord) catch err.wat();
        }
    }

    // var y: usize = 0;
    // while (y < HEIGHT) : (y += 1) {
    //     var x: usize = 0;
    //     while (x < WIDTH) : (x += 1) {
    //         const coord = Coord.new2(level, x, y);
    //         if (state.dungeon.at(coord).type == .Wall and
    //             state.dungeon.neighboringOfType(coord, true, .Floor) >= 4)
    //         {
    //             walls_to_remove.append(coord) catch err.wat();
    //         }
    //     }
    // }

    for (walls_to_remove.items) |coord|
        state.dungeon.at(coord).type = .Floor;

    placeRandomRooms(level, alloc);
}

pub fn placeBSPRooms(grandma_rect: Rect, _min_room_width: usize, _min_room_height: usize, _max_room_width: usize, _max_room_height: usize, allocator: mem.Allocator) void {
    const level = grandma_rect.start.z;

    const Node = struct {
        const Self = @This();

        rect: Rect,
        childs: [2]?*Self = [_]?*Self{ null, null },
        parent: ?*Self = null,
        group: Group,

        // Index in dungeon's room list
        index: usize = 0,

        pub const ArrayList = std.ArrayList(*Self);

        pub const Group = enum { Root, Branch, Leaf, Failed };

        pub fn freeRecursively(self: *Self, alloc: mem.Allocator) void {
            const childs = self.childs;

            // Don't free grandparent node, which is stack-allocated
            if (self.parent != null) alloc.destroy(self);

            if (childs[0]) |child| child.freeRecursively(alloc);
            if (childs[1]) |child| child.freeRecursively(alloc);
        }

        fn splitH(self: *const Self, percent: usize, out1: *Rect, out2: *Rect) void {
            assert(self.rect.width > 1);

            out1.* = self.rect;
            out2.* = self.rect;

            out1.height = out1.height * (percent) / 100;
            out2.height = (out2.height * (100 - percent) / 100) - 1;
            out2.start.y += out1.height + 1;

            if (out1.height == 0 or out2.height == 0) {
                splitH(self, 50, out1, out2);
            }
        }

        fn splitV(self: *const Self, percent: usize, out1: *Rect, out2: *Rect) void {
            assert(self.rect.height > 1);

            out1.* = self.rect;
            out2.* = self.rect;

            out1.width = out1.width * (percent) / 100;
            out2.width = (out2.width * (100 - percent) / 100) - 1;
            out2.start.x += out1.width + 1;

            if (out1.width == 0 or out2.width == 0) {
                splitV(self, 50, out1, out2);
            }
        }

        pub fn splitTree(
            self: *Self,
            failed: *ArrayList,
            leaves: *ArrayList,
            maplevel: usize,
            min_room_width: usize,
            min_room_height: usize,
            max_room_width: usize,
            max_room_height: usize,
            alloc: mem.Allocator,
        ) mem.Allocator.Error!void {
            var branches = ArrayList.init(alloc);
            defer branches.deinit();
            try branches.append(self);

            var iters: usize = Configs[maplevel].mapgen_iters;
            while (iters > 0 and branches.items.len > 0) : (iters -= 1) {
                const cur = branches.swapRemove(rng.range(usize, 0, branches.items.len - 1));

                if (cur.rect.height <= 4 or cur.rect.width <= 4) {
                    continue;
                }

                // Out params, set by splitH/splitV
                var new1: Rect = undefined;
                var new2: Rect = undefined;

                // Ratio to split by.
                //
                // e.g., if percent == 30%, then new1 will be 30% of original,
                // and new2 will be 70% of original.
                const percent = rng.range(usize, 30, 70);

                // Split horizontally or vertically
                if ((cur.rect.height * 2) > cur.rect.width) {
                    cur.splitH(percent, &new1, &new2);
                } else if (cur.rect.width > (cur.rect.height * 2)) {
                    cur.splitV(percent, &new1, &new2);
                } else {
                    if (rng.onein(2)) {
                        cur.splitH(percent, &new1, &new2);
                    } else {
                        cur.splitV(percent, &new1, &new2);
                    }
                }

                var has_child = false;
                const prospective_children = [_]Rect{ new1, new2 };
                for (prospective_children) |prospective_child, i| {
                    const node = try alloc.create(Self);
                    node.* = .{ .rect = prospective_child, .group = undefined, .parent = cur };
                    cur.childs[i] = node;

                    if (prospective_child.width >= min_room_width and
                        prospective_child.height >= min_room_height)
                    {
                        has_child = true;

                        if (prospective_child.width < max_room_width or
                            prospective_child.height < max_room_height)
                        {
                            try leaves.append(node);
                            node.group = .Leaf;
                        } else {
                            try branches.append(node);
                            node.group = .Branch;
                        }
                    } else if ((cur.rect.width > max_room_width and
                        cur.rect.width < min_room_width * 2) or
                        (cur.rect.height > max_room_height and
                        cur.rect.height < min_room_height * 2))
                    {
                        // Failed height/width test, but it's not possible to
                        // split it properly AND parent was previously greater than
                        // the max dimensions anyway. Give some slack.
                        //
                        has_child = true;
                        try leaves.append(node);
                        node.group = .Leaf;
                    } else {
                        try failed.append(node);
                        node.group = .Failed;
                    }
                }

                if (!has_child) {
                    try leaves.append(cur);
                    cur.group = .Leaf;
                }
            }
        }
    };

    const rooms = &state.rooms[level];

    var failed = Node.ArrayList.init(allocator);
    defer failed.deinit();
    var leaves = Node.ArrayList.init(allocator);
    defer leaves.deinit();

    var grandma_node = Node{
        .rect = grandma_rect, // orelse Rect{ .start = Coord.new2(level, 1, 1), .height = HEIGHT - 2, .width = WIDTH - 2 },
        .group = .Root,
    };
    grandma_node.splitTree(&failed, &leaves, level, _min_room_width, _min_room_height, _max_room_width, _max_room_height, allocator) catch err.wat();
    defer grandma_node.freeRecursively(allocator);

    for (failed.items) |container_node| {
        assert(container_node.group == .Failed);
        var room = Room{ .rect = container_node.rect };
        room.type = .Sideroom;
        container_node.index = rooms.items.len;
        excavateRect(&room.rect);
        rooms.append(room) catch err.wat();
    }

    for (leaves.items) |container_node| {
        assert(container_node.group == .Leaf);
        var room = Room{ .rect = container_node.rect };

        // Random room sizes are disabled for now.
        //const container = container_node.room;
        //const w = rng.range(usize, Configs[level].min_room_width, container.width);
        //const h = rng.range(usize, Configs[level].min_room_height, container.height);
        //const x = rng.range(usize, container.start.x, container.end().x - w);
        //const y = rng.range(usize, container.start.y, container.end().y - h);
        //var room = Room{ .start = Coord.new2(level, x, y), .width = w, .height = h };

        assert(room.rect.width > 0 and room.rect.height > 0);

        // XXX: papering over a BSP bug which sometimes gives overlapping rooms
        // (with other nasty side effects, like overlapping subrooms and such)
        if (isRoomInvalid(&state.rooms[level], &room, null, null, true))
            continue;

        excavateRect(&room.rect);

        container_node.index = rooms.items.len;
        rooms.append(room) catch err.wat();
    }

    // Rely on placeMoarCorridors, the previous corridor-placing thing was
    // horribly broken :/
    //
    //S.addCorridorsAndDoors(level, &grandma_node, rooms, allocator);
    placeMoarCorridors(level, allocator);

    // Add subrooms only after everything is placed and corridors are dug.
    //
    // This is a workaround for a bug where corridors are excavated right
    // through subrooms, destroying prisons and wreaking all sort of havoc.
    //
    // Used to iterate over rooms.items, but that creates issues when combining
    // with tunneling mapgen
    //
    for (leaves.items) |container_node| {
        const room = &rooms.items[container_node.index];
        if (rng.percent(Configs[level].subroom_chance)) {
            _ = placeSubroom(room, &Rect{
                .start = Coord.new(0, 0),
                .width = room.rect.width,
                .height = room.rect.height,
            }, allocator, .{});
        }
    }
}

pub fn _strewItemsAround(room: *Room, max_items: usize) void {
    var items_placed: usize = 0;

    while (items_placed < max_items) : (items_placed += 1) {
        var item_coord: Coord = undefined;
        var tries: usize = 500;
        while (true) {
            item_coord = room.rect.randomCoord();

            if (isTileAvailable(item_coord) and
                !state.dungeon.at(item_coord).prison)
                break; // we found a valid coord

            // didn't find a coord, bail out
            if (tries == 0) return;
            tries -= 1;
        }

        const t = _chooseLootItem(&items.ITEM_DROPS, minmax(usize, 0, 200), null);
        const item = items.createItemFromTemplate(t);
        state.dungeon.itemsAt(item_coord).append(item) catch err.wat();
    }
}

pub fn _placeLootChest(room: *Room, max_items: usize) void {
    var tries: usize = 1000;
    const container_coord = while (tries > 0) : (tries -= 1) {
        var item_coord = room.rect.randomCoord();
        if (isTileAvailable(item_coord) and
            !state.dungeon.at(item_coord).prison and
            utils.walkableNeighbors(item_coord, false, .{}) >= 3)
        {
            break item_coord;
        }
    } else return;

    const container_template = rng.choose(
        *const Container,
        &surfaces.LOOT_CONTAINERS,
        &surfaces.LOOT_CONTAINER_WEIGHTS,
    ) catch err.wat();
    fillLootContainer(placeContainer(container_coord, container_template), max_items);
}

pub fn fillLootContainer(container: *Container, max_items: usize) void {
    const item_class = container.type.itemType().?;

    var items_placed: usize = 0;

    while (items_placed < max_items and !container.isFull()) : (items_placed += 1) {
        const chosen_item_class = rng.chooseUnweighted(ItemTemplate.Type, item_class);
        // Special-case weapons, otherwise they take forever to fill up due to
        // rarity
        const list = if (chosen_item_class == .W) &items.WEAP_ITEM_DROPS else &items.ITEM_DROPS;
        const t = _chooseLootItem(list, minmax(usize, 0, 200), chosen_item_class);
        const item = items.createItemFromTemplate(t);
        container.items.append(item) catch err.wat();
    }
}

pub fn placeItems(level: usize) void {
    // Now drop items that the player could use.
    for (state.rooms[level].items) |*room| {
        // Don't place items if:
        // - Room is a corridor. Loot in corridors is dumb (looking at you, DCSS).
        // - Room is a lair of the night creatures.
        // - Room has a subroom (might be too crowded!).
        // - Room is a prefab and the prefab forbids items.
        // - Random chance.
        //
        if (room.type == .Corridor or
            room.has_subroom or room.is_lair or
            (room.prefab != null and room.prefab.?.noitems) or
            rng.onein(4))
        {
            continue;
        }

        if (rng.onein(2)) {
            // 1/12 chance to have chest full of rubbish
            if (rng.onein(12)) {
                _placeLootChest(room, 0);
            } else {
                _placeLootChest(room, rng.range(usize, 1, 3));
            }

            if (room.is_vault != null) {
                _placeLootChest(room, rng.range(usize, 2, 4));
                _placeLootChest(room, rng.range(usize, 2, 4));
            }
        } else {
            const max_items = if (room.is_vault != null) rng.range(usize, 3, 7) else rng.range(usize, 1, 2);
            _strewItemsAround(room, max_items);
        }
    }

    // Now fill up containers with junk
    // (Including any ones we placed earlier in this function)
    //
    var containers = state.containers.iterator();
    while (containers.next()) |container| {
        if (container.coord.z != level) continue;
        if (container.isFull()) continue;

        // 1/3 chance to skip filling a container if it already has items
        if (container.items.len > 0 and rng.onein(3)) continue;

        // How much should we fill the container?
        const fill = rng.range(usize, 1, container.capacity - container.items.len);

        const maybe_item_list: ?[]*const Prop = switch (container.type) {
            .Drinkables => surfaces.bottle_props.items,
            .Smackables => surfaces.weapon_props.items,
            .Evocables => surfaces.tools_props.items,
            .Utility => if (Configs[level].utility_items.*.len > 0) Configs[level].utility_items.* else null,
            else => null,
        };

        if (maybe_item_list) |item_list| {
            var item = rng.chooseUnweighted(*const Prop, item_list);
            var i: usize = 0;
            while (i < fill) : (i += 1) {
                if (!rng.percent(container.item_repeat))
                    item = rng.chooseUnweighted(*const Prop, item_list);

                container.items.append(Item{ .Prop = item }) catch err.wat();
            }
        }
    }
}

pub fn placeTraps(level: usize) void {
    room_iter: for (state.rooms[level].items) |maproom| {
        if (maproom.prefab) |rfb| if (rfb.notraps) continue;
        if (maproom.has_subroom) continue; // Too cluttered
        if (maproom.is_lair) continue;

        const room = maproom.rect;

        // Don't place traps in places where it's impossible to avoid
        if (room.height == 1 or room.width == 1 or maproom.type != .Room)
            continue;

        if (!rng.percent(Configs[level].room_trapped_chance))
            continue;

        var tries: usize = 1000;
        var trap_coord: Coord = undefined;

        while (true) {
            trap_coord = room.randomCoord();

            if (isTileAvailable(trap_coord) and
                !state.dungeon.at(trap_coord).prison and
                state.dungeon.neighboringWalls(trap_coord, true) <= 1)
            {
                break; // we found a valid coord
            }

            // didn't find a coord, continue to the next room
            if (tries == 0) continue :room_iter;
            tries -= 1;
        }

        var trap = (rng.choose(*const Machine, TRAPS, TRAP_WEIGHTS) catch err.wat()).*;

        var num_of_vents = rng.range(usize, 1, 3);
        var v_tries: usize = 1000;
        while (v_tries > 0 and num_of_vents > 0) : (v_tries -= 1) {
            const vent = room.randomCoord();

            var avg_dist: usize = undefined;
            var count: usize = 0;
            for (trap.props) |maybe_prop| if (maybe_prop) |prop| {
                avg_dist += vent.distance(prop.coord);
                count += 1;
            };
            avg_dist += vent.distance(trap_coord);
            avg_dist /= (count + 1);

            if (vent.distance(trap_coord) < 3 or
                avg_dist < 4 or
                state.dungeon.at(vent).surface != null or
                state.dungeon.at(vent).type != .Floor)
            {
                continue;
            }

            state.dungeon.at(vent).type = .Floor;
            const p_ind = utils.findById(surfaces.props.items, Configs[room.start.z].vent);
            const prop = placeProp(vent, &surfaces.props.items[p_ind.?]);
            trap.props[num_of_vents] = prop;
            num_of_vents -= 1;
        }
        _place_machine(trap_coord, &trap);
    }
}

pub fn placeMobs(level: usize, alloc: mem.Allocator) void {
    var level_mob_count: usize = 0;

    for (state.rooms[level].items) |*room| {
        if (Configs[level].level_crowd_max) |level_crowd_max| {
            if (level_mob_count >= level_crowd_max) {
                continue;
            }
        }

        if (room.prefab) |rfb| if (rfb.noguards) continue;
        if (room.type == .Corridor and !Configs[level].allow_spawn_in_corridors) continue;
        if (room.rect.height * room.rect.width < 25) continue;

        const vault_type: ?usize = if (room.is_vault) |v| @enumToInt(v) else null;

        const max_crowd = if (room.is_lair)
            rng.range(usize, 1, 2)
        else if (room.is_vault != null)
            rng.range(usize, VAULT_CROWD[vault_type.?].min, VAULT_CROWD[vault_type.?].max)
        else
            rng.range(usize, 1, Configs[level].room_crowd_max);

        const sptable: *MobSpawnInfo.AList = if (room.is_lair)
            &mobs.spawns.spawn_tables_lairs[0]
        else if (room.is_vault != null)
            &mobs.spawns.spawn_tables_vaults[vault_type.?]
        else
            &mobs.spawns.spawn_tables[level];

        loop: while (room.mob_count < max_crowd) {
            const mob_spawn_info = rng.choose2(MobSpawnInfo, sptable.items, "weight") catch err.wat();
            const mob = mobs.findMobById(mob_spawn_info.id) orelse err.bug(
                "Mob {s} specified in spawn tables couldn't be found.",
                .{mob_spawn_info.id},
            );

            var tries: usize = if (room.is_lair) 800 else 250;
            while (tries > 0) : (tries -= 1) {
                const post_coord = room.rect.randomCoord();

                {
                    var gen = Generator(Rect.rectIter).init(mob.mobAreaRect(post_coord));
                    while (gen.next()) |mobcoord|
                        if (!isTileAvailable(mobcoord) or state.dungeon.at(mobcoord).prison)
                            continue :loop;
                }

                const m = mobs.placeMob(alloc, mob, post_coord, .{
                    .facing = rng.chooseUnweighted(Direction, &DIRECTIONS),
                });

                var new_mobs: usize = 1;
                if (m.squad) |squad| {
                    new_mobs += squad.members.len;
                }

                room.mob_count += new_mobs;
                level_mob_count += new_mobs;

                break;
            }

            // We bailed out trying to place a monster, don't bother filling
            // the room up full.
            if (tries == 0) {
                break;
            }
        }
    }

    room_iter_required: for (Configs[level].required_mobs) |required_mob| {
        var placed_ctr: usize = required_mob.count;
        while (placed_ctr > 0) {
            const room_i = rng.range(usize, 0, state.rooms[level].items.len - 1);
            const room = &state.rooms[level].items[room_i];

            if (room.type == .Corridor) continue;
            if (room.mob_count >= Configs[level].room_crowd_max)
                continue :room_iter_required;

            var tries: usize = 10;
            while (tries > 0) : (tries -= 1) {
                const post_coord = room.rect.randomCoord();
                if (isTileAvailable(post_coord) and !state.dungeon.at(post_coord).prison) {
                    placed_ctr -= 1;
                    _ = mobs.placeMob(alloc, required_mob.template, post_coord, .{});

                    room.mob_count += 1;

                    break;
                }
            }
        }
    }
}

fn placeWindow(room: *Room) void {
    if (Configs[room.rect.start.z].no_windows) return;
    if (room.has_window) return;

    const material = Configs[room.rect.start.z].window_material;

    var tries: usize = 200;
    while (tries > 0) : (tries -= 1) {
        const coord = randomWallCoord(&room.rect, tries);

        if (state.dungeon.at(coord).type != .Wall or
            !utils.hasPatternMatch(coord, &VALID_WINDOW_PLACEMENT_PATTERNS) or
            state.dungeon.neighboringMachines(coord) > 0)
            continue; // invalid coord

        room.has_window = true;
        state.dungeon.at(coord).material = material;
        break;
    }
}

fn placeLights(room: *const Room) void {
    if (Configs[room.rect.start.z].no_lights) return;
    if (room.prefab) |rfb| if (rfb.nolights) return;

    const lights_needed = rng.range(usize, 1, 2);

    var lights: usize = 0;
    var light_tries: usize = 500;
    while (light_tries > 0 and lights < lights_needed) : (light_tries -= 1) {
        const coord = randomWallCoord(&room.rect, light_tries);

        if (state.dungeon.at(coord).type != .Wall or
            !utils.hasPatternMatch(coord, &VALID_LIGHT_PLACEMENT_PATTERNS) or
            state.dungeon.neighboringMachines(coord) > 0)
            continue; // invalid coord

        var brazier = Configs[room.rect.start.z].light.*;

        // Dim lights by a random amount.
        brazier.powered_luminescence -= rng.range(usize, 0, 10);

        _place_machine(coord, &brazier);
        state.dungeon.at(coord).type = .Floor;
        lights += 1;
    }
}

// Place a single prop along a Coord range.
fn _placePropAlongRange(level: usize, where: Range, prop: *const Prop, max: usize) usize {
    // FIXME: we *really* should just be iterating through each coordinate
    // in this Range, instead of randomly choosing a bunch over and over
    //
    var tries: usize = max;
    var placed: usize = 0;
    while (tries > 0) : (tries -= 1) {
        const x = rng.range(usize, where.from.x, where.to.x);
        const y = rng.range(usize, where.from.y, where.to.y);
        const coord = Coord.new2(level, x, y);

        if (!isTileAvailable(coord) or
            utils.findPatternMatch(coord, &VALID_FEATURE_TILE_PATTERNS) == null)
            continue;

        _ = placeProp(coord, prop);
        placed += 1;
    }

    return placed;
}

pub fn setVaultFeatures(room: *Room) void {
    const level = room.rect.start.z;

    const wall_areas = computeWallAreas(&room.rect, true);
    for (&wall_areas) |wall_area| {
        var y: usize = wall_area.from.y;
        while (y <= wall_area.to.y) : (y += 1) {
            var x: usize = wall_area.from.x;
            while (x <= wall_area.to.x) : (x += 1) {
                const coord = Coord.new2(level, x, y);

                // Material
                state.dungeon.at(coord).material = VAULT_MATERIALS[@enumToInt(room.is_vault.?)];

                // Door
                // XXX: hacky, in the future we should store door coords.
                if ((state.dungeon.at(coord).surface != null and
                    state.dungeon.at(coord).surface.? == .Machine and
                    mem.startsWith(u8, state.dungeon.at(coord).surface.?.Machine.id, "door")) or
                    (state.dungeon.at(coord).surface == null and
                    state.dungeon.at(coord).type == .Floor))
                {
                    assert(state.dungeon.at(coord).type == .Floor);
                    if (state.dungeon.at(coord).surface != null) {
                        state.dungeon.at(coord).surface.?.Machine.disabled = true;
                        state.dungeon.at(coord).surface = null;
                    }
                    _place_machine(coord, VAULT_DOORS[@enumToInt(room.is_vault.?)]);
                }
            }
        }
    }

    // Subroom, if any
    if (VAULT_SUBROOMS[@enumToInt(room.is_vault.?)]) |fab_name| {
        _ = placeSubroom(room, &Rect{
            .start = Coord.new(0, 0),
            .width = room.rect.width,
            .height = room.rect.height,
        }, state.gpa.allocator(), .{ .specific_id = fab_name });
    }
}

pub fn setLairFeatures(room: *Room) void {
    const level = room.rect.start.z;

    // const wall_areas = computeWallAreas(&room.rect, true);
    // for (&wall_areas) |wall_area| {
    //     var y: usize = wall_area.from.y;
    //     while (y <= wall_area.to.y) : (y += 1) {
    //         var x: usize = wall_area.from.x;
    //         while (x <= wall_area.to.x) : (x += 1) {
    //             const coord = Coord.new2(level, x, y);
    //             state.dungeon.at(coord).material = &materials.Slade;
    //         }
    //     }
    // }

    const door_c = room.connections.slice()[0].door.?;
    if (state.dungeon.at(door_c).surface != null) {
        state.dungeon.at(door_c).surface.?.Machine.disabled = true;
        state.dungeon.at(door_c).surface = null;
    }
    _place_machine(door_c, &surfaces.SladeDoor);

    var walkable_point: Coord = undefined;

    // Set the entire room to rough slade
    var y: usize = room.rect.start.y;
    while (y < room.rect.end().y) : (y += 1) {
        var x: usize = room.rect.start.x;
        while (x < room.rect.end().x) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            if (state.dungeon.at(coord).type == .Floor)
                walkable_point = coord;
            state.dungeon.at(coord).material = &materials.Slade;
        }
    }

    // Set polished slade areas
    var dijk = dijkstra.Dijkstra.init(walkable_point, state.mapgeometry, 100, dijkstra.dummyIsValid, .{}, state.gpa.allocator());
    defer dijk.deinit();
    while (dijk.next()) |child| {
        if (child.asRect().overflowsLimit(&room.rect)) {
            dijk.skip();
        } else if (state.dungeon.at(child).type == .Wall) {
            dijk.skip();
            if (child.x > room.rect.start.x and child.x < room.rect.end().x - 1 and
                child.y > room.rect.start.y and child.y < room.rect.end().y - 1)
            {
                state.dungeon.at(child).material = &materials.PolishedSlade;
            }
        }
    }

    // Find areas to place subroom
    const subroom_area = Rect.new(
        Coord.new2(room.rect.start.z, room.rect.start.x + 1, room.rect.start.y + 1),
        room.rect.width - 1,
        room.rect.height - 1,
    );
    var tries: usize = 300;
    while (tries > 0) : (tries -= 1) {
        const coord = subroom_area.randomCoord();
        if (state.dungeon.at(coord).type == .Floor) {
            if (placeSubroom(room, &Rect{
                .start = Coord.new(coord.x - room.rect.start.x, coord.y - room.rect.start.y),
                .width = room.rect.end().x - coord.x,
                .height = room.rect.end().y - coord.y,
            }, state.gpa.allocator(), .{ .for_lair = true })) {
                break;
            }
        }
    }
}

pub fn placeRoomFeatures(level: usize, alloc: mem.Allocator) void {
    for (state.rooms[level].items) |*room| {
        const rect = room.rect;
        const room_area = rect.height * rect.width;

        // Don't light up narrow corridors
        if (room.rect.width > 2 and room.rect.height > 2 and !room.is_lair)
            placeLights(room);

        // Don't fill small rooms or corridors.
        if (room_area < 16 or rect.height <= 2 or rect.width <= 2 or room.type == .Corridor) {
            continue;
        }

        placeWindow(room);

        if (room.prefab != null) continue;
        if (room.has_subroom and room_area < 25) continue;

        if (room.is_vault != null) {
            setVaultFeatures(room);
        } else if (room.is_lair) {
            setLairFeatures(room);
            continue;
        }

        const rect_end = rect.end();

        const ranges = [_]Range{
            .{ .from = Coord.new(rect.start.x + 1, rect.start.y), .to = Coord.new(rect_end.x - 2, rect.start.y) }, // top
            .{ .from = Coord.new(rect.start.x + 1, rect_end.y - 1), .to = Coord.new(rect_end.x - 2, rect_end.y - 1) }, // bottom
            .{ .from = Coord.new(rect.start.x, rect.start.y + 1), .to = Coord.new(rect.start.x, rect_end.y - 2) }, // left
            .{ .from = Coord.new(rect_end.x - 1, rect.start.y + 1), .to = Coord.new(rect_end.x - 1, rect_end.y - 2) }, // left
        };

        var statues: usize = 0;
        var props: usize = 0;
        var containers: usize = 0;
        var machs: usize = 0;
        var posters: usize = 0;

        const max_containers = math.log(usize, 2, room_area);

        var forbidden_range: ?usize = null;

        if (room_area > 64 and
            rng.percent(Configs[level].chance_for_single_prop_placement) and
            Configs[level].single_props.len > 0)
        {
            const prop_id = rng.chooseUnweighted([]const u8, Configs[level].single_props);
            const prop_ind = utils.findById(surfaces.props.items, prop_id).?;
            const prop = surfaces.props.items[prop_ind];

            const range_ind = rng.range(usize, 0, ranges.len - 1);
            forbidden_range = range_ind;
            const range = ranges[range_ind];

            const tries = math.max(rect.width, rect.height) * 150 / 100;
            props += _placePropAlongRange(rect.start.z, range, &prop, tries);

            continue;
        }

        const Mode = enum { Statues, Containers, Machine, Poster, None };
        const modes = [_]Mode{ .Statues, .Containers, .Machine, .Poster, .None };
        const mode_weights = [_]usize{
            if (Configs[level].allow_statues) 10 else 0,
            if (Configs[level].containers.len > 0) 8 else 0,
            if (Configs[level].machines.len > 0) 10 else 0,
            if (room_area >= 25) 5 else 0,
            8,
        };
        const mode = rng.choose(Mode, &modes, &mode_weights) catch err.wat();

        if (mode == .None) continue;

        var tries = math.sqrt(room_area) * 5;
        while (tries > 0) : (tries -= 1) {
            const range_ind = tries % ranges.len;
            if (forbidden_range) |fr| if (range_ind == fr) continue;

            const range = ranges[tries % ranges.len];
            const x = rng.range(usize, range.from.x, range.to.x);
            const y = rng.range(usize, range.from.y, range.to.y);
            const coord = Coord.new2(rect.start.z, x, y);

            if (!isTileAvailable(coord) or
                utils.findPatternMatch(coord, &VALID_FEATURE_TILE_PATTERNS) == null)
                continue;

            switch (mode) {
                .Statues => {
                    assert(Configs[level].allow_statues);
                    if (statues == 0 and rng.onein(2)) {
                        const statue = rng.chooseUnweighted(mobs.MobTemplate, &mobs.STATUES);
                        _ = mobs.placeMob(alloc, &statue, coord, .{});
                        statues += 1;
                    } else if (props < 2) {
                        const prop = rng.chooseUnweighted(*const Prop, Configs[level].props.*);
                        _ = placeProp(coord, prop);
                        props += 1;
                    }
                },
                .Containers => {
                    if (containers < max_containers) {
                        var cont = rng.chooseUnweighted(Container, Configs[level].containers);
                        _ = placeContainer(coord, &cont);
                        containers += 1;
                    }
                },
                .Machine => {
                    if (machs < 1) {
                        assert(Configs[level].machines.len > 0);
                        var m = rng.chooseUnweighted(*const Machine, Configs[level].machines);
                        _place_machine(coord, m);
                        machs += 1;
                    }
                },
                .Poster => {
                    if (posters < 1) {
                        if (choosePoster(level)) |poster| {
                            state.dungeon.at(coord).surface = SurfaceItem{ .Poster = poster };
                            posters += 1;
                        }
                    }
                },
                else => err.wat(),
            }
        }
    }
}

pub fn setTerrain(coord: Coord, terrain: *const surfaces.Terrain) void {
    if (mem.eql(u8, state.dungeon.at(coord).terrain.id, "t_default")) {
        state.dungeon.at(coord).terrain = terrain;
    }
}

pub fn placeRoomTerrain(level: usize) void {
    var weights = StackBuffer(usize, surfaces.TERRAIN.len).init(null);
    var terrains = StackBuffer(*const surfaces.Terrain, surfaces.TERRAIN.len).init(null);
    for (&surfaces.TERRAIN) |terrain| {
        var allowed_for_level = for (terrain.for_levels) |allowed_id| {
            if (mem.eql(u8, allowed_id, state.levelinfo[level].id) or
                mem.eql(u8, allowed_id, "ANY"))
            {
                break true;
            }
        } else false;

        if (allowed_for_level) {
            weights.append(terrain.weight) catch err.wat();
            terrains.append(terrain) catch err.wat();
        }
    }

    for (state.rooms[level].items) |*room| {
        if (!room.is_lair and (rng.percent(@as(usize, 60)) or
            room.rect.width <= 4 or room.rect.height <= 4))
        {
            continue;
        }

        const rect = room.rect;

        const chosen_terrain = if (room.is_lair)
            &surfaces.SladeTerrain
        else
            rng.choose(
                *const surfaces.Terrain,
                terrains.constSlice(),
                weights.constSlice(),
            ) catch err.wat();

        switch (chosen_terrain.placement) {
            .EntireRoom, .RoomPortion => {
                var location = rect;
                if (chosen_terrain.placement == .RoomPortion) {
                    location = Rect{
                        .width = rng.range(usize, rect.width / 2, rect.width),
                        .height = rng.range(usize, rect.height / 2, rect.height),
                        .start = rect.start,
                    };
                    location.start = location.start.add(Coord.new(
                        rng.range(usize, 0, rect.width / 2),
                        rng.range(usize, 0, rect.height / 2),
                    ));
                }

                var y: usize = location.start.y;
                while (y < location.end().y) : (y += 1) {
                    var x: usize = location.start.x;
                    while (x < location.end().x) : (x += 1) {
                        const coord = Coord.new2(level, x, y);
                        if (coord.x >= WIDTH or coord.y >= HEIGHT)
                            continue;
                        setTerrain(coord, chosen_terrain);
                    }
                }
            },
            .RoomSpotty => |r| {
                const count = math.min(r, (rect.width * rect.height) * r / 100);

                var placed: usize = 0;
                while (placed < count) {
                    const coord = room.rect.randomCoord();
                    if (state.dungeon.at(coord).type == .Floor and
                        state.dungeon.at(coord).surface == null)
                    {
                        setTerrain(coord, chosen_terrain);
                        placed += 1;
                    }
                }
            },
            .RoomBlob => {
                const config_min_width = minmax(usize, rect.width / 2, rect.width / 2);
                const config_max_width = minmax(usize, rect.width, rect.width);
                const config_min_height = minmax(usize, rect.height / 2, rect.height / 2);
                const config_max_height = minmax(usize, rect.height, rect.height);

                const config = BlobConfig{
                    .type = null,
                    .terrain = chosen_terrain,
                    .min_blob_width = config_min_width,
                    .min_blob_height = config_min_height,
                    .max_blob_width = config_max_width,
                    .max_blob_height = config_max_height,
                    .ca_rounds = 5,
                    .ca_percent_seeded = 55,
                    .ca_birth_params = "ffffffttt",
                    .ca_survival_params = "ffffttttt",
                };

                placeBlob(config, rect.start);
            },
        }
    }
}

pub fn placeStair(level: usize, dest_floor: usize, alloc: mem.Allocator) void {
    // Find coord candidates for stairs placement. Usually this will be in a room,
    // but we're not forcing it because that wouldn't work well for Caverns.
    //
    var locations = CoordArrayList.init(alloc);
    defer locations.deinit();
    coord_search: for (state.dungeon.map[level]) |*row, y| {
        for (row) |_, x| {
            const coord = Coord.new2(level, x, y);

            for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
                const room: ?*Room = switch (state.layout[level][neighbor.y][neighbor.x]) {
                    .Unknown => null,
                    .Room => |r| &state.rooms[level].items[r],
                };

                if (state.dungeon.at(coord).prison or
                    room != null and ((room.?.prefab != null and room.?.prefab.?.nostairs) or room.?.is_lair or room.?.has_stair or room.?.is_vault != null))
                {
                    continue :coord_search;
                }
            };

            if (state.dungeon.at(coord).type == .Wall and
                !state.dungeon.at(coord).prison and
                utils.hasPatternMatch(coord, &VALID_STAIR_PLACEMENT_PATTERNS))
            {
                locations.append(coord) catch err.wat();
            }
        }
    }

    if (locations.items.len == 0) {
        //err.bug("Couldn't place stairs anywhere on {s}!", .{state.levelinfo[level].name});
        return;
    }

    // Map out the locations in a grid, so that we can easily tell what's in the
    // location list without scanning the whole list each time.
    var location_map: [HEIGHT][WIDTH]bool = undefined;
    for (location_map) |*row| for (row) |*cell| {
        cell.* = false;
    };
    for (locations.items) |c| {
        location_map[c.y][c.x] = true;
    }

    var walkability_map: [HEIGHT][WIDTH]bool = undefined;
    for (walkability_map) |*row, y| for (row) |*cell, x| {
        const coord = Coord.new2(level, x, y);
        cell.* = location_map[y][x] or
            state.is_walkable(coord, .{ .ignore_mobs = true });
    };

    // We'll use dijkstra to create a "ranking matrix", which we'll use to
    // sort out the candidates later.
    var stair_dijkmap: [HEIGHT][WIDTH]?f64 = undefined;
    for (stair_dijkmap) |*row| for (row) |*cell| {
        cell.* = null;
    };

    // First, find the entry/exit locations. These locations are either the
    // stairs leading from the previous levels, or the player's starting area.
    for (state.dungeon.stairs[level].constSlice()) |stair| {
        stair_dijkmap[stair.y][stair.x] = 0;
    }
    if (level == state.PLAYER_STARTING_LEVEL) {
        stair_dijkmap[state.player.coord.y][state.player.coord.x] = 0;
    } else {
        const entry = state.dungeon.entries[level];
        stair_dijkmap[entry.y][entry.x] = 0;
    }

    // Now fill out the dijkstra map to assign a score to each coordinate.
    // Farthest == best.
    dijkstra.dijkRollUphill(&stair_dijkmap, &CARDINAL_DIRECTIONS, &walkability_map);

    // Debugging code.
    //
    // std.log.info("{s}", .{state.levelinfo[level].name});
    // for (stair_dijkmap) |*row, y| {
    //     for (row) |cell, x| {
    //         if (cell == null) {
    //             std.io.getStdErr().writer().print(" ", .{}) catch unreachable;
    //         } else if (cell.? == 0) {
    //             std.io.getStdErr().writer().print("@", .{}) catch unreachable;
    //         } else if (location_map[y][x]) {
    //             std.io.getStdErr().writer().print("^", .{}) catch unreachable;
    //         } else {
    //             std.io.getStdErr().writer().print("{}", .{math.clamp(cell.? / 10, 0, 9)}) catch unreachable;
    //         }
    //     }
    //     std.io.getStdErr().writer().print("\n", .{}) catch unreachable;
    // }

    // Find the candidate farthest away from entry/exit locations.
    const _sortFunc = struct {
        pub fn f(map: *const [HEIGHT][WIDTH]?f64, a: Coord, b: Coord) bool {
            if (map[a.y][a.x] == null) return true else if (map[b.y][b.x] == null) return false;
            return map[a.y][a.x].? < map[b.y][b.x].?;
        }
    };
    std.sort.sort(Coord, locations.items, &stair_dijkmap, _sortFunc.f);

    // Create some stairs!
    const up_staircase = locations.items[locations.items.len - 1];
    state.dungeon.at(up_staircase).type = .Floor;
    state.dungeon.at(up_staircase).surface = Stair.newUp(dest_floor);
    switch (state.layout[level][up_staircase.y][up_staircase.x]) {
        .Room => |r| state.rooms[level].items[r].has_stair = true,
        else => {},
    }
    state.dungeon.stairs[level].append(up_staircase) catch err.wat();

    // Place a guardian near the stairs in a diagonal position, if possible.
    const guardian = mobs.spawns.chooseMob(.Special, level, "g") catch err.wat();
    for (&DIAGONAL_DIRECTIONS) |d| if (up_staircase.move(d, state.mapgeometry)) |neighbor| {
        if (state.is_walkable(neighbor, .{ .right_now = true })) {
            _ = mobs.placeMob(alloc, guardian, neighbor, .{});
            break;
        }
    };
}

// Note: must be run before placeStairs()
//
pub fn placeEntry(level: usize, alloc: mem.Allocator) bool {
    var reciever_locations = CoordArrayList.init(alloc);
    defer reciever_locations.deinit();

    coord_search: for (state.dungeon.map[level]) |*row, y| for (row) |_, x| {
        const coord = Coord.new2(level, x, y);

        for (&DIRECTIONS) |d| if (coord.move(d, state.mapgeometry)) |neighbor| {
            const room: ?*Room = switch (state.layout[level][neighbor.y][neighbor.x]) {
                .Unknown => null,
                .Room => |r| &state.rooms[level].items[r],
            };

            if (state.dungeon.at(coord).prison or
                room != null and ((room.?.prefab != null and room.?.prefab.?.nostairs) or room.?.is_lair or room.?.has_stair or room.?.is_vault != null))
            {
                continue :coord_search;
            }
        };

        if (state.dungeon.at(coord).type == .Wall and
            !state.dungeon.at(coord).prison and
            utils.hasPatternMatch(coord, &VALID_STAIR_PLACEMENT_PATTERNS))
        {
            reciever_locations.append(coord) catch err.wat();
        }
    };

    err.ensure(reciever_locations.items.len > 0, "Couldn't place an entrypoint on {s}", .{state.levelinfo[level].name}) catch return false;

    const down_staircase = rng.chooseUnweighted(Coord, reciever_locations.items);

    state.dungeon.at(down_staircase).type = .Floor;
    state.dungeon.at(down_staircase).surface = Stair.newDown();
    switch (state.layout[level][down_staircase.y][down_staircase.x]) {
        .Room => |r| state.rooms[level].items[r].has_stair = true,
        else => {},
    }
    state.dungeon.entries[level] = down_staircase;

    return true;
}

// Remove mobs nearby entry points to avoid punishing player too hard.
pub fn removeEnemiesNearEntry(level: usize) void {
    const down_staircase = state.dungeon.entries[level];
    var dijk = dijkstra.Dijkstra.init(
        down_staircase,
        state.mapgeometry,
        8,
        state.is_walkable,
        .{ .ignore_mobs = true, .right_now = true },
        state.gpa.allocator(),
    );
    defer dijk.deinit();
    while (dijk.next()) |child| {
        if (state.dungeon.at(child).mob) |mob| {
            if (!mob.isHostileTo(state.player))
                continue;

            const can_be_seen = for (&DIRECTIONS) |d| {
                if (child.move(d, state.mapgeometry)) |neighbor| {
                    if (fov.quickLOSCheck(
                        down_staircase,
                        neighbor,
                        types.Dungeon.tileOpacity,
                    ))
                        break true;
                }
            } else false;
            if (child.distance(down_staircase) <= 3 or can_be_seen)
                mob.deinitNoCorpse();
        }
    }
}

pub const BlobConfig = struct {
    // This is ignored by placeBlob, only used by placeBlobs
    number: MinMax(usize) = MinMax(usize){ .min = 1, .max = 1 },

    type: ?TileType,
    terrain: *const surfaces.Terrain = &surfaces.DefaultTerrain,
    min_blob_width: MinMax(usize),
    min_blob_height: MinMax(usize),
    max_blob_width: MinMax(usize),
    max_blob_height: MinMax(usize),
    ca_rounds: usize,
    ca_percent_seeded: usize,
    ca_birth_params: *const [9]u8,
    ca_survival_params: *const [9]u8,
};

fn placeBlob(cfg: BlobConfig, start: Coord) void {
    var grid: [WIDTH][HEIGHT]usize = undefined;

    const blob = createBlob(
        &grid,
        cfg.ca_rounds,
        rng.range(usize, cfg.min_blob_width.min, cfg.min_blob_width.max),
        rng.range(usize, cfg.min_blob_height.min, cfg.min_blob_height.max),
        rng.range(usize, cfg.max_blob_width.min, cfg.max_blob_width.max),
        rng.range(usize, cfg.max_blob_height.min, cfg.max_blob_height.max),
        cfg.ca_percent_seeded,
        cfg.ca_birth_params,
        cfg.ca_survival_params,
    );

    var map_y: usize = 0;
    var blob_y = blob.start.y;
    while (blob_y < blob.end().y) : ({
        blob_y += 1;
        map_y += 1;
    }) {
        var map_x: usize = 0;
        var blob_x = blob.start.x;
        while (blob_x < blob.end().x) : ({
            blob_x += 1;
            map_x += 1;
        }) {
            const coord = Coord.new2(start.z, map_x, map_y).add(start);
            if (coord.x >= WIDTH or coord.y >= HEIGHT)
                continue;

            if (grid[blob_x][blob_y] != 0) {
                if (cfg.type) |tiletype| state.dungeon.at(coord).type = tiletype;
                setTerrain(coord, cfg.terrain);
            }
        }
    }
}

pub fn placeBlobs(level: usize) void {
    const blob_configs = Configs[level].blobs;
    for (blob_configs) |cfg| {
        var i: usize = rng.range(usize, cfg.number.min, cfg.number.max);
        while (i > 0) : (i -= 1) {
            const start_y = rng.range(usize, 1, HEIGHT - 1);
            const start_x = rng.range(usize, 1, WIDTH - 1);
            const start = Coord.new2(level, start_x, start_y);
            placeBlob(cfg, start);
        }
    }
}

// Ported from BrogueCE (src/brogue/Grid.c)
// (c) Contributors to BrogueCE. I do not claim authorship of the following function.
fn createBlob(
    grid: *[WIDTH][HEIGHT]usize,
    rounds: usize,
    min_blob_width: usize,
    min_blob_height: usize,
    max_blob_width: usize,
    max_blob_height: usize,
    percent_seeded: usize,
    birth_params: *const [9]u8,
    survival_params: *const [9]u8,
) Rect {
    const S = struct {
        fn cellularAutomataRound(buf: *[WIDTH][HEIGHT]usize, births: *const [9]u8, survivals: *const [9]u8) void {
            var buf2: [WIDTH][HEIGHT]usize = undefined;
            for (buf) |*col, x| for (col) |*cell, y| {
                buf2[x][y] = cell.*;
            };

            var x: usize = 0;
            while (x < WIDTH) : (x += 1) {
                var y: usize = 0;
                while (y < HEIGHT) : (y += 1) {
                    const coord = Coord.new(x, y);

                    var nb_count: usize = 0;

                    for (&DIRECTIONS) |direction|
                        if (coord.move(direction, state.mapgeometry)) |neighbor| {
                            if (buf2[neighbor.x][neighbor.y] != 0) {
                                nb_count += 1;
                            }
                        };

                    if (buf2[x][y] == 0 and births[nb_count] == 't') {
                        buf[x][y] = 1; // birth
                    } else if (buf2[x][y] != 0 and survivals[nb_count] == 't') {
                        // survival
                    } else {
                        buf[x][y] = 0; // death
                    }
                }
            }
        }

        fn fillContiguousRegion(buf: *[WIDTH][HEIGHT]usize, x: usize, y: usize, value: usize) usize {
            var num: usize = 1;

            const coord = Coord.new(x, y);
            buf[x][y] = value;

            // Iterate through the four cardinal neighbors.
            for (&CARDINAL_DIRECTIONS) |direction| {
                if (coord.move(direction, state.mapgeometry)) |neighbor| {
                    if (buf[neighbor.x][neighbor.y] == 1) { // If the neighbor is an unmarked region cell,
                        num += fillContiguousRegion(buf, neighbor.x, neighbor.y, value); // then recurse.
                    }
                } else {
                    break;
                }
            }

            return num;
        }
    };

    var i: usize = 0;
    var j: usize = 0;
    var k: usize = 0;

    var blob_num: usize = 0;
    var blob_size: usize = 0;
    var top_blob_num: usize = 0;
    var top_blob_size: usize = 0;

    var top_blob_min_x: usize = 0;
    var top_blob_min_y: usize = 0;
    var top_blob_max_x: usize = 0;
    var top_blob_max_y: usize = 0;

    var blob_width: usize = 0;
    var blob_height: usize = 0;

    var found_cell_this_line = false;

    // Generate blobs until they satisfy the provided restraints
    var first = true; // Zig, get a do-while already
    while (first or blob_width < min_blob_width or blob_height < min_blob_height or top_blob_num == 0) {
        first = false;

        for (grid) |*col| for (col) |*cell| {
            cell.* = 0;
        };

        // Fill relevant portion with noise based on the percentSeeded argument.
        i = 0;
        while (i < max_blob_width) : (i += 1) {
            j = 0;
            while (j < max_blob_height) : (j += 1) {
                grid[i][j] = if (rng.range(usize, 0, 100) < percent_seeded) 1 else 0;
            }
        }

        // Some iterations of cellular automata
        k = 0;
        while (k < rounds) : (k += 1) {
            S.cellularAutomataRound(grid, birth_params, survival_params);
        }

        // Now to measure the result. These are best-of variables; start them out at worst-case values.
        top_blob_size = 0;
        top_blob_num = 0;
        top_blob_min_x = max_blob_width;
        top_blob_max_x = 0;
        top_blob_min_y = max_blob_height;
        top_blob_max_y = 0;

        // Fill each blob with its own number, starting with 2 (since 1 means floor), and keeping track of the biggest:
        blob_num = 2;

        i = 0;
        while (i < WIDTH) : (i += 1) {
            j = 0;
            while (j < HEIGHT) : (j += 1) {
                if (grid[i][j] == 1) { // an unmarked blob
                    // Mark all the cells and returns the total size:
                    blob_size = S.fillContiguousRegion(grid, i, j, blob_num);
                    if (blob_size > top_blob_size) { // if this blob is a new record
                        top_blob_size = blob_size;
                        top_blob_num = blob_num;
                    }
                    blob_num += 1;
                }
            }
        }

        // Figure out the top blob's height and width:
        // First find the max & min x:
        i = 0;
        while (i < WIDTH) : (i += 1) {
            found_cell_this_line = false;
            j = 0;
            while (j < HEIGHT) : (j += 1) {
                if (grid[i][j] == top_blob_num) {
                    found_cell_this_line = true;
                    break;
                }
            }

            if (found_cell_this_line) {
                if (i < top_blob_min_x) {
                    top_blob_min_x = i;
                }

                if (i > top_blob_max_x) {
                    top_blob_max_x = i;
                }
            }
        }

        // Then the max & min y:
        j = 0;
        while (j < HEIGHT) : (j += 1) {
            found_cell_this_line = false;
            i = 0;
            while (i < WIDTH) : (i += 1) {
                if (grid[i][j] == top_blob_num) {
                    found_cell_this_line = true;
                    break;
                }
            }

            if (found_cell_this_line) {
                if (j < top_blob_min_y) {
                    top_blob_min_y = j;
                }

                if (j > top_blob_max_y) {
                    top_blob_max_y = j;
                }
            }
        }

        blob_width = (top_blob_max_x - top_blob_min_x) + 1;
        blob_height = (top_blob_max_y - top_blob_min_y) + 1;
    }

    // Replace the winning blob with 1's, and everything else with 0's:
    i = 0;
    while (i < WIDTH) : (i += 1) {
        j = 0;
        while (j < HEIGHT) : (j += 1) {
            if (grid[i][j] == top_blob_num) {
                grid[i][j] = 1;
            } else {
                grid[i][j] = 0;
            }
        }
    }

    return .{
        .start = Coord.new(top_blob_min_x, top_blob_min_y),
        .width = blob_width,
        .height = blob_height,
    };
}

pub fn generateLayoutMap(level: usize) void {
    const rooms = &state.rooms[level];

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            const room = Room{ .rect = coord.asRect() };

            if (findIntersectingRoom(rooms, &room, null, null, false)) |r| {
                state.layout[level][y][x] = state.Layout{ .Room = r };
            } else {
                state.layout[level][y][x] = .Unknown;
            }
        }
    }
}

fn levelFeatureDormantConstruct(_: usize, coord: Coord, _: *const Room, _: *const Prefab, alloc: mem.Allocator) void {
    while (true) {
        const mob = mobs.spawns.chooseMob(.Main, coord.z, null) catch err.wat();
        if (mob.mob.life_type != .Construct) continue;
        const mob_ptr = mobs.placeMob(alloc, mob, coord, .{});
        mob_ptr.addStatus(.Sleeping, 0, .Prm);
        return;
    }
}

fn levelFeaturePrisonersMaybe(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: mem.Allocator) void {
    if (rng.onein(2)) levelFeaturePrisoners(c, coord, room, prefab, alloc);
}

fn levelFeaturePrisoners(_: usize, coord: Coord, _: *const Room, _: *const Prefab, alloc: mem.Allocator) void {
    const prisoner_t = rng.chooseUnweighted(mobs.MobTemplate, &mobs.PRISONERS);
    const prisoner = mobs.placeMob(alloc, &prisoner_t, coord, .{});
    prisoner.prisoner_status = Prisoner{ .of = .Necromancer };

    for (&CARDINAL_DIRECTIONS) |direction|
        if (coord.move(direction, state.mapgeometry)) |neighbor| {
            //if (direction == .North) err.wat();
            if (state.dungeon.at(neighbor).surface) |surface| {
                if (meta.activeTag(surface) == .Prop and surface.Prop.holder) {
                    prisoner.prisoner_status.?.held_by = .{ .Prop = surface.Prop };
                    break;
                }
            }
        };
}

fn levelFeatureVials(_: usize, coord: Coord, _: *const Room, _: *const Prefab, _: mem.Allocator) void {
    state.dungeon.itemsAt(coord).append(
        Item{ .Vial = rng.choose(Vial, &Vial.VIALS, &Vial.VIAL_COMMONICITY) catch err.wat() },
    ) catch err.wat();
}

fn levelFeatureConstructParts(_: usize, coord: Coord, _: *const Room, _: *const Prefab, alloc: mem.Allocator) void {
    var props = std.ArrayList(*const Prop).init(alloc);
    defer props.deinit();

    for (surfaces.props.items) |*prop|
        if (prop.function != null and prop.function.? == .WRK_CompA) {
            props.append(prop) catch err.wat();
        };

    state.dungeon.itemsAt(coord).append(
        Item{ .Prop = rng.chooseUnweighted(*const Prop, props.items) },
    ) catch err.wat();
}

// Randomly place a vial ore. If the Y coordinate is even, create a container and
// fill it up halfway; otherwise, place only one item on the ground.
fn levelFeatureOres(_: usize, coord: Coord, _: *const Room, _: *const Prefab, _: mem.Allocator) void {
    var using_container: ?*Container = null;

    if ((coord.y % 2) == 0) {
        using_container = placeContainer(coord, &surfaces.VOreCrate);
    }

    var placed: usize = rng.rangeClumping(usize, 3, 8, 2);
    var tries: usize = 50;
    while (tries > 0) : (tries -= 1) {
        const v = rng.choose(Vial.OreAndVial, &Vial.VIAL_ORES, &Vial.VIAL_COMMONICITY) catch err.wat();

        if (v.m) |material| {
            const item = Item{ .Boulder = material };
            if (using_container) |container| {
                container.items.append(item) catch err.wat();
                if (placed == 0) break;
                placed -= 1;
            } else {
                state.dungeon.itemsAt(coord).append(item) catch err.wat();
                break;
            }
        }
    }
}

pub fn initLevelTest(prefab: []const u8, entry: bool) !void {
    resetLevel(0);

    const fab = Prefab.findPrefabByName(prefab, &n_fabs) orelse return error.NoSuchPrefab;
    var room = Room{
        .rect = Rect{ .start = Coord.new2(0, 0, 0), .width = fab.width, .height = fab.height },
        .prefab = fab,
    };
    excavatePrefab(&room, fab, state.gpa.allocator(), 0, 0);
    state.rooms[0].append(room) catch err.wat();

    const p_coord = Coord.new2(0, WIDTH - 1, HEIGHT - 1);
    state.dungeon.at(p_coord).type = .Floor;
    placePlayer(p_coord, state.gpa.allocator());
    state.player.kill();

    generateLayoutMap(0);
    if (entry) _ = placeEntry(0, state.gpa.allocator());
}

pub fn initLevel(level: usize) void {
    rng.useTemp(state.floor_seeds[level]);

    var tries: usize = 0;
    while (true) {
        tries += 1;

        resetLevel(level);
        initGif();
        placeBlobs(level);
        (Configs[level].mapgen_func)(level, state.gpa.allocator());
        selectLevelLairs(level);
        selectLevelVault(level);
        if (Configs[level].allow_extra_corridors)
            placeMoarCorridors(level, state.gpa.allocator());
        generateLayoutMap(level);

        if (!placeEntry(level, state.gpa.allocator())) {
            // We should be checking tries here...
            std.log.info("{s}: Invalid map (couldn't place entry), retrying...", .{
                state.levelinfo[level].name,
            });
            continue; // try again
        }

        for (state.levelinfo[level].stairs) |maybe_stair| if (maybe_stair) |dest_stair| {
            const floor = for (state.levelinfo) |levelinfo, i| {
                if (mem.eql(u8, levelinfo.name, dest_stair)) {
                    break i;
                }
            } else err.bug("Levelinfo stairs {s} invalid", .{dest_stair});

            placeStair(level, floor, state.gpa.allocator());
        };

        emitGif(level);

        if (validateLevel(level, state.gpa.allocator())) |_| {
            // .
        } else |e| {
            if (tries < 28) {
                std.log.info("{s}: Invalid map ({s}), retrying...", .{
                    state.levelinfo[level].name,
                    @errorName(e),
                });
                continue; // try again
            } else {
                // Give up!
                err.bug("{s}: Couldn't generate valid map!", .{state.levelinfo[level].name});
            }
        }

        placeRoomFeatures(level, state.gpa.allocator());
        placeRoomTerrain(level);
        placeTraps(level);
        placeItems(level);
        placeMobs(level, state.gpa.allocator());
        setLevelMaterial(level);
        removeEnemiesNearEntry(level);

        std.log.info("Generated map {s}.", .{state.levelinfo[level].name});
        rng.useNorm();
        return;
    }
}

pub const LevelAnalysis = struct {
    alloc: mem.Allocator,
    prefabs: std.ArrayList(Pair),
    items: std.ArrayList(Pair2),
    mobs: std.ArrayList(Pair),
    ring: ?[]const u8 = null,
    seed: u64,
    floor_seed: u64,

    pub const Pair = struct { id: []const u8, c: usize };
    pub const Pair2 = struct { id: []const u8, t: []const u8, c: usize };

    pub fn init(alloc: mem.Allocator, z: usize) @This() {
        return .{
            .alloc = alloc,
            .prefabs = std.ArrayList(Pair).init(alloc),
            .items = std.ArrayList(Pair2).init(alloc),
            .mobs = std.ArrayList(Pair).init(alloc),
            .seed = state.seed,
            .floor_seed = state.floor_seeds[z],
        };
    }

    pub fn incrMob(self: *@This(), id: []const u8) !void {
        const slot = for (self.mobs.items) |*mobr| {
            if (mem.eql(u8, mobr.id, id)) break mobr;
        } else b: {
            const _id = try self.alloc.dupe(u8, id);
            self.mobs.append(.{ .id = _id, .c = 0 }) catch err.wat();
            break :b &self.mobs.items[self.mobs.items.len - 1];
        };
        slot.c += 1;
    }

    pub fn incrItem(self: *@This(), itemtype: types.ItemType, id: []const u8) !void {
        const slot = for (self.items.items) |*itemr| {
            if (mem.eql(u8, itemr.id, id)) break itemr;
        } else b: {
            const _id = try self.alloc.dupe(u8, id);
            self.items.append(
                .{ .id = _id, .t = @tagName(itemtype), .c = 0 },
            ) catch err.wat();
            break :b &self.items.items[self.items.items.len - 1];
        };
        slot.c += 1;
    }

    pub fn jsonStringify(val: *const @This(), opts: std.json.StringifyOptions, stream: anytype) !void {
        const object: struct {
            prefabs: []const Pair,
            items: []const Pair2,
            mobs: []const Pair,
            ring: ?[]const u8,
            seed: u64,
            floor_seed: u64,
        } = .{
            .prefabs = val.prefabs.items,
            .items = val.items.items,
            .mobs = val.mobs.items,
            .ring = val.ring,
            .seed = val.seed,
            .floor_seed = val.floor_seed,
        };

        try std.json.stringify(object, opts, stream);
    }
};

pub fn analyzeLevel(level: usize, alloc: mem.Allocator) !LevelAnalysis {
    var a = LevelAnalysis.init(alloc, level);

    var riter = state.fab_records.iterator();
    while (riter.next()) |prefab_record| {
        if (prefab_record.value_ptr.level[level] > 0)
            a.prefabs.append(.{
                .id = try alloc.dupe(u8, prefab_record.key_ptr.*),
                .c = prefab_record.value_ptr.level[level],
            }) catch err.wat();
    }

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            if (utils.getRoomFromCoord(level, coord)) |room_id| {
                if (state.rooms[level].items[room_id].is_lair or
                    state.rooms[level].items[room_id].is_vault != null)
                {
                    continue;
                }
            }
            for (state.dungeon.itemsAt(coord).constSlice()) |item| {
                if (item == .Ring) {
                    assert(state.dungeon.itemsAt(coord).len == 1);
                    a.ring = try alloc.dupe(u8, item.Ring.name);
                } else if (item != .Prop and item != .Vial and item != .Boulder) {
                    if (item.id()) |id|
                        try a.incrItem(item, id);
                }
            }
            if (state.dungeon.at(coord).surface) |s| if (s == .Container)
                for (s.Container.items.constSlice()) |item|
                    if (item != .Prop and item != .Vial and item != .Boulder)
                        if (item.id()) |id|
                            try a.incrItem(item, id);

            // Hack to make sure counting mobs works right
            //
            // Mobs are only counted if there is a straight path from them to
            // the stair. However, if we didn't remove mobs from the map, this
            // would break for multitile mobs in Shrine, as most of them
            // wouldn't have a path.
            state.dungeon.at(coord).mob = null;
        }
    }

    var miter = state.mobs.iterator();
    while (miter.next()) |mob|
        if (!mob.is_dead and mob.coord.z == level and mob != state.player)
            if (mob.immobile or mob.nextDirectionTo(state.dungeon.entries[level]) != null)
                try a.incrMob(mob.id);

    return a;
}

// Room: "Annotated Room{}"
// Contains additional information necessary for mapgen.
//
pub const Room = struct {
    // linked list stuff
    __next: ?*Room = null,
    __prev: ?*Room = null,

    rect: Rect,

    type: RoomType = .Room,

    prefab: ?*Prefab = null,
    has_subroom: bool = false,
    has_window: bool = false,
    has_stair: bool = false,
    mob_count: usize = 0,
    is_vault: ?VaultType = null,
    is_extension_room: bool = false,
    is_lair: bool = false,

    connections: ConnectionsBuf = ConnectionsBuf.init(null),
    importance: usize = 0,

    pub const Connection = struct { room: Coord, door: ?Coord };
    pub const ConnectionsBuf = StackBuffer(Connection, CONNECTIONS_MAX);
    pub const RoomType = enum { Corridor, Room, Sideroom, Junction };
    pub const ArrayList = std.ArrayList(Room);

    pub fn prefabId(self: *const Room) []const u8 {
        return if (self.prefab) |prefab| prefab.name.constSlice() else "NONE";
    }

    pub fn getByStart(start: Coord) ?*Room {
        return for (state.rooms[start.z].items) |*room| {
            if (room.rect.start.eq(start)) break room;
        } else null;
    }

    pub fn hasCloseConnectionTo(self: *const Room, room: Rect) bool {
        for (self.connections.constSlice()) |connection| {
            if (connection.room.eq(room.start))
                return true;
            if (getByStart(connection.room)) |connection_r| {
                for (connection_r.connections.constSlice()) |child_connection|
                    if (child_connection.room.eq(room.start))
                        return true;
            }
        }
        return false;
    }
};

pub const Prefab = struct {
    subroom: bool = false,
    center_align: bool = false,
    invisible: bool = false,
    global_restriction: usize = LEVELS,
    restriction: usize = 1,
    individual_restriction: usize = 999,
    priority: usize = 0,
    noitems: bool = false,
    noguards: bool = false,
    nolights: bool = false,
    notraps: bool = false,
    nostairs: bool = false,
    nopadding: bool = false,
    transforms: StackBuffer(Transform, 5) = StackBuffer(Transform, 5).init(null),

    tunneler_prefab: bool = false,
    tunneler_corridor_prefab: bool = false,
    tunneler_inset: bool = false,
    tunneler_orientation: StackBuffer(Direction, 4) = StackBuffer(Direction, 4).init(null),

    name: StackBuffer(u8, MAX_NAME_SIZE) = StackBuffer(u8, MAX_NAME_SIZE).init(null),

    level_uses: [LEVELS]usize = [1]usize{0} ** LEVELS,

    material: ?*const Material = null,
    terrain: ?*const surfaces.Terrain = null,

    player_position: ?Coord = null,
    height: usize = 0,
    width: usize = 0,
    content: [40][60]FabTile = undefined,
    connections: [40]?Connection = undefined,
    features: [128]?Feature = [_]?Feature{null} ** 128,
    features_global: [128]bool = [_]bool{false} ** 128,
    mobs: [45]?FeatureMob = [_]?FeatureMob{null} ** 45,
    prisons: StackBuffer(Rect, 16) = StackBuffer(Rect, 16).init(null),
    subroom_areas: StackBuffer(SubroomArea, 8) = StackBuffer(SubroomArea, 8).init(null),
    whitelist: StackBuffer(usize, LEVELS) = StackBuffer(usize, LEVELS).init(null),
    stockpile: ?Rect = null,
    input: ?Rect = null,
    output: ?Rect = null,

    allow_walls_overwrite_other: bool = false,

    pub const MAX_NAME_SIZE = 64;

    pub const Transform = struct {
        // File memory isn't freed until after parsing, so we can get away with
        // not using a stackbuffer here
        transform_into: ?[]const u8 = null,
        transform_type: Type,

        pub const Type = enum { Turn1, Turn2, Turn3 };
    };

    pub const PlacementRecord = struct {
        level: [LEVELS]usize = [_]usize{0} ** LEVELS,
        global: usize = 0,
    };

    pub const SubroomArea = struct {
        rect: Rect,
        specific_id: ?StackBuffer(u8, 64) = null,
    };

    pub const FabTile = union(enum) {
        Window,
        Wall,
        LockedDoor,
        HeavyLockedDoor,
        Door,
        Brazier,
        ShallowWater,
        Floor,
        Connection,
        Water,
        Lava,
        Bars,
        Feature: u8,
        LevelFeature: usize,
        Loot1,
        RareLoot,
        Corpse,
        Ring,
        Any,
    };

    pub const FeatureMob = struct {
        id: [32:0]u8,
        spawn_at: Coord,
        work_at: ?Coord,
    };

    pub const Feature = union(enum) {
        Item: items.ItemTemplate,
        Mob: *const mobs.MobTemplate,
        // Same as Mob, but with more options
        CMob: struct {
            t: *const mobs.MobTemplate,
            opts: mobs.PlaceMobOptions,
        },
        CCont: struct {
            t: *const Container,
        },
        Cpitem: struct {
            ts: StackBuffer(?*const Prop, 16),
            we: StackBuffer(usize, 16),
        },
        Poster: *const Poster,
        Machine: struct {
            id: [32:0]u8,
            points: StackBuffer(Coord, 16),
        },
        Prop: [32:0]u8,
        Stair: surfaces.Stair,
        Key: surfaces.Stair.Type,
    };

    pub const Connection = struct {
        c: Coord,
        d: Direction,
        used: bool = false,
    };

    pub fn reset(self: *Prefab, level: usize) void {
        if (state.fab_records.getPtr(self.name.constSlice())) |record| {
            record.global -= record.level[level];
            record.level[level] = 0;
        }

        self.level_uses[level] = 0;

        for (self.connections) |maybe_con, i| {
            if (maybe_con == null) break;
            self.connections[i].?.used = false;
        }
    }

    pub fn useConnector(self: *Prefab, c: Coord) !void {
        for (self.connections) |maybe_con, i| {
            const con = maybe_con orelse break;
            if (con.c.eq(c)) {
                if (con.used) return error.ConnectorAlreadyUsed;
                self.connections[i].?.used = true;
                return;
            }
        }
        return error.NoSuchConnector;
    }

    pub fn connectorFor(self: *const Prefab, d: Direction) ?Coord {
        for (self.connections) |maybe_con| {
            const con = maybe_con orelse break;
            if (con.d == d and !con.used) return con.c;
        }
        return null;
    }

    fn _parseTransform(f: *Prefab, origname: []const u8, t: Transform) !void {
        var new = f.*;

        if (f.input != null or f.output != null or f.stockpile != null or
            f.connections[0] != null or f.mobs[0] != null or
            f.subroom_areas.len != 0 or f.prisons.len != 0)
        {
            return error.UnimplementedTransformation;
        }

        new.transforms.clear();
        for (new.content) |*row| mem.set(FabTile, row, .Wall);

        var width: usize = undefined;
        var height: usize = undefined;

        switch (t.transform_type) {
            .Turn1 => {
                width = f.height;
                height = f.width;
                if (width >= f.content[0].len or height >= f.content.len)
                    return error.OverflowingTransform;
                for (f.content) |row, y| for (row) |cell, x| {
                    if (y >= width or x >= height) continue;
                    new.content[x][(width - 1) - y] = cell;
                };
                for (f.tunneler_orientation.slice()) |*orient|
                    orient.* = orient.turnright();
            },
            .Turn2 => {
                width = f.width;
                height = f.height;
                for (f.content) |row, y| for (row) |cell, x| {
                    if (y >= height or x >= width) continue;
                    new.content[(height - 1) - y][(width - 1) - x] = cell;
                };
                for (f.tunneler_orientation.slice()) |*orient|
                    orient.* = orient.turnright().turnright();
            },
            .Turn3 => {
                width = f.height;
                height = f.width;
                if (width >= f.content[0].len or height >= f.content.len)
                    return error.OverflowingTransform;
                for (f.content) |row, y| for (row) |cell, x| {
                    if (y >= width or x >= height) continue;
                    new.content[(height - 1) - x][y] = cell;
                };
                for (f.tunneler_orientation.slice()) |*orient|
                    orient.* = orient.turnright().turnright().turnright();
            },
        }

        // std.log.info("Did transform {}. Old:", .{t.transform_type});
        // for (f.content) |row, y| {
        //     if (y >= height) continue;
        //     for (row) |cell, x| {
        //         if (x >= width) continue;
        //         const ch = switch (cell) {
        //             .Wall => '#',
        //             .Feature => |z| z,
        //             .Floor => '.',
        //             else => ',',
        //         };
        //         _ = std.io.getStdErr().writer().print("{u}", .{ch}) catch err.wat();
        //     }
        //     _ = std.io.getStdErr().writer().write("\n") catch err.wat();
        // }
        // std.log.info("New:", .{});
        // for (new.content) |row, y| {
        //     if (y >= height) continue;
        //     for (row) |cell, x| {
        //         if (x >= width) continue;
        //         const ch = switch (cell) {
        //             .Wall => '#',
        //             .Feature => |z| z,
        //             .Floor => '.',
        //             else => ',',
        //         };
        //         _ = std.io.getStdErr().writer().print("{u}", .{ch}) catch err.wat();
        //     }
        //     _ = std.io.getStdErr().writer().write("\n") catch err.wat();
        // }

        try _finishParsing(t.transform_into orelse origname, height, width, &new);
    }

    fn _finishParsing(
        name: []const u8,
        y: usize,
        w: usize,
        f: *Prefab,
    ) anyerror!void { // TODO: add Prefab.Error type and remove this anyerror nonsense
        f.width = w;
        f.height = y;

        for (&f.connections) |*con, i| {
            if (con.*) |c| {
                if (c.c.x == 0) {
                    f.connections[i].?.d = .West;
                } else if (c.c.y == 0) {
                    f.connections[i].?.d = .North;
                } else if (c.c.y == (f.height - 1)) {
                    f.connections[i].?.d = .South;
                } else if (c.c.x == (f.width - 1)) {
                    f.connections[i].?.d = .East;
                } else {
                    return error.InvalidConnection;
                }
            }
        }

        const prefab_name = mem.trimRight(u8, name, ".fab");
        f.name = StackBuffer(u8, Prefab.MAX_NAME_SIZE).init(prefab_name);

        const to = if (f.subroom) &s_fabs else &n_fabs;
        to.append(f.*) catch err.oom();

        for (f.transforms.constSlice()) |transform|
            try f._parseTransform(name, transform);
    }

    // XXX: anyerror is a hack because we call ourselves, meaning Zig can't
    // infer the error type
    //
    pub fn parseAndLoad(name: []const u8, from: []const u8) anyerror!void {
        var f: Prefab = .{};
        for (f.content) |*row| mem.set(FabTile, row, .Wall);
        mem.set(?Connection, &f.connections, null);

        var ci: usize = 0; // index for f.connections
        var cm: usize = 0; // index for f.mobs
        var w: usize = 0;
        var y: usize = 0;

        var lines = mem.split(u8, from, "\n");
        while (lines.next()) |line| {
            if (line.len == 0) {
                continue;
            }

            switch (line[0]) {
                '%' => {}, // ignore comments
                '\\' => {
                    try _finishParsing(name, y, w, &f);

                    ci = 0;
                    cm = 0;
                    w = 0;
                    y = 0;
                    f.player_position = null;
                    f.height = 0;
                    f.width = 0;
                    f.prisons.clear();
                    f.subroom_areas.clear();
                    for (f.content) |*row| mem.set(FabTile, row, .Wall);
                    mem.set(?Connection, &f.connections, null);
                    for (&f.features) |*feat, i| {
                        if (!f.features_global[i])
                            feat.* = null;
                    }
                    mem.set(?FeatureMob, &f.mobs, null);
                    f.stockpile = null;
                    f.input = null;
                    f.output = null;
                    f.tunneler_orientation = @TypeOf(f.tunneler_orientation).init(null);
                    f.tunneler_inset = false;
                },
                ':' => {
                    var words = mem.tokenize(u8, line[1..], " ");
                    const key = words.next() orelse return error.MalformedMetadata;
                    const val = words.next() orelse "";

                    // At some point I really need to sit down and cleanup this mess
                    //
                    if (mem.eql(u8, key, "begin_prefab")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        const next = lines.next() orelse return error.UnexpectedEndOfFile;
                        const ptr = @ptrToInt(next.ptr) - @ptrToInt(from.ptr);
                        try parseAndLoad(val, from[ptr..]);
                        break;
                    } else if (mem.eql(u8, key, "invisible")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.invisible = true;
                    } else if (mem.eql(u8, key, "g_whitelist")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        if (mem.eql(u8, val, "$SPAWN_LEVEL")) {
                            f.whitelist.append(state.PLAYER_STARTING_LEVEL) catch err.wat();
                        } else {
                            f.whitelist.append(state.findLevelByName(val) orelse return error.InvalidMetadataValue) catch err.wat();
                        }
                    } else if (mem.eql(u8, key, "g_tunneler")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.tunneler_prefab = true;
                    } else if (mem.eql(u8, key, "g_tunneler_corridor_subroom")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.tunneler_corridor_prefab = true;
                    } else if (mem.eql(u8, key, "tunneler_inset")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.tunneler_inset = true;
                    } else if (mem.eql(u8, key, "tunneler_orientation")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.tunneler_orientation.append(if (Direction.fromStr(val)) |d| d else |_| return error.InvalidMetadataValue) catch err.wat();
                    } else if (mem.eql(u8, key, "g_subroom")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.subroom = true;
                    } else if (mem.eql(u8, key, "center_align")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.center_align = true;
                    } else if (mem.eql(u8, key, "g_material")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.material = for (materials.MATERIALS) |mat| {
                            if (mem.eql(u8, val, mat.id orelse mat.name))
                                break mat;
                        } else return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "g_terrain")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.terrain = for (surfaces.TERRAIN) |t| {
                            if (mem.eql(u8, val, t.id))
                                break t;
                        } else return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "g_restriction")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.restriction = std.fmt.parseInt(usize, val, 0) catch return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "g_global_restriction")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.global_restriction = std.fmt.parseInt(usize, val, 0) catch return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "g_individual_restriction")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.individual_restriction = std.fmt.parseInt(usize, val, 0) catch return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "priority")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.priority = std.fmt.parseInt(usize, val, 0) catch return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "noguards")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.noguards = true;
                    } else if (mem.eql(u8, key, "nolights")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.nolights = true;
                    } else if (mem.eql(u8, key, "notraps")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.notraps = true;
                    } else if (mem.eql(u8, key, "noitems")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.noitems = true;
                    } else if (mem.eql(u8, key, "nostairs")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.nostairs = true;
                    } else if (mem.eql(u8, key, "spawn")) {
                        const spawn_at_str = words.next() orelse return error.ExpectedMetadataValue;
                        const maybe_work_at_str: ?[]const u8 = words.next() orelse null;

                        var spawn_at = Coord.new(0, 0);
                        var spawn_at_tokens = mem.tokenize(u8, spawn_at_str, ",");
                        const spawn_at_str_a = spawn_at_tokens.next() orelse return error.InvalidMetadataValue;
                        const spawn_at_str_b = spawn_at_tokens.next() orelse return error.InvalidMetadataValue;
                        spawn_at.x = std.fmt.parseInt(usize, spawn_at_str_a, 0) catch return error.InvalidMetadataValue;
                        spawn_at.y = std.fmt.parseInt(usize, spawn_at_str_b, 0) catch return error.InvalidMetadataValue;

                        f.mobs[cm] = FeatureMob{
                            .id = undefined,
                            .spawn_at = spawn_at,
                            .work_at = null,
                        };
                        utils.copyZ(&f.mobs[cm].?.id, val);

                        if (maybe_work_at_str) |work_at_str| {
                            var work_at = Coord.new(0, 0);
                            var work_at_tokens = mem.tokenize(u8, work_at_str, ",");
                            const work_at_str_a = work_at_tokens.next() orelse return error.InvalidMetadataValue;
                            const work_at_str_b = work_at_tokens.next() orelse return error.InvalidMetadataValue;
                            work_at.x = std.fmt.parseInt(usize, work_at_str_a, 0) catch return error.InvalidMetadataValue;
                            work_at.y = std.fmt.parseInt(usize, work_at_str_b, 0) catch return error.InvalidMetadataValue;
                            f.mobs[cm].?.work_at = work_at;
                        }

                        cm += 1;
                    } else if (mem.eql(u8, key, "prison")) {
                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(u8, val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch return error.InvalidMetadataValue;

                        f.prisons.append(.{ .start = rect_start, .width = width, .height = height }) catch return error.TooManyPrisons;
                    } else if (mem.eql(u8, key, "g_transform")) {
                        var ttype = Transform.Type.Turn1;

                        if (val.len > 0) {
                            if (mem.eql(u8, val, ".Turn1")) {
                                ttype = .Turn1;
                            } else if (mem.eql(u8, val, ".Turn2")) {
                                ttype = .Turn2;
                            } else if (mem.eql(u8, val, ".Turn3")) {
                                ttype = .Turn3;
                            } else return error.InvalidMetadataValue;
                        }

                        f.transforms.append(.{
                            .transform_into = words.next(),
                            .transform_type = ttype,
                        }) catch return error.TooManyTransforms;
                    } else if (mem.eql(u8, key, "subroom_area")) {
                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(u8, val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch return error.InvalidMetadataValue;
                        const specific_id = words.next();

                        f.subroom_areas.append(.{
                            .rect = Rect{ .start = rect_start, .width = width, .height = height },
                            .specific_id = if (specific_id) |str| StackBuffer(u8, 64).init(str) else null,
                        }) catch return error.TooManySubrooms;
                    } else if (mem.eql(u8, key, "g_nopadding")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.nopadding = true;
                    } else if (mem.eql(u8, key, "stockpile")) {
                        if (f.stockpile) |_| return error.StockpileAlreadyDefined;

                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(u8, val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch return error.InvalidMetadataValue;

                        f.stockpile = .{ .start = rect_start, .width = width, .height = height };
                    } else if (mem.eql(u8, key, "output")) {
                        if (f.output) |_| return error.OutputAreaAlreadyDefined;

                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(u8, val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch return error.InvalidMetadataValue;

                        f.output = .{ .start = rect_start, .width = width, .height = height };
                    } else if (mem.eql(u8, key, "input")) {
                        if (f.input) |_| return error.InputAreaAlreadyDefined;

                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(u8, val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch return error.InvalidMetadataValue;

                        f.input = .{ .start = rect_start, .width = width, .height = height };
                    } else return error.InvalidMetadataValue;
                },
                '@' => {
                    var words = mem.tokenize(u8, line, " ");
                    _ = words.next(); // Skip the '@<ident>' bit

                    const is_global = line[1] == '@';
                    const identifier = if (is_global) line[2] else line[1];
                    const feature_type = words.next() orelse return error.MalformedFeatureDefinition;
                    const id = words.next();

                    switch (feature_type[0]) {
                        'C' => {
                            if (mem.eql(u8, feature_type, "Cmons")) {
                                const mob_t = mobs.findMobById(id orelse return error.MalformedFeatureDefinition) orelse
                                    return error.NoSuchMob;

                                const ind = @ptrToInt((words.next() orelse return error.MalformedFeatureDefinition).ptr) - @ptrToInt(line.ptr);
                                const rest = line[ind..];
                                var cbf_p = cbf.Parser{ .input = rest };
                                var res = try cbf_p.parse(state.gpa.allocator());
                                defer cbf.Parser.deinit(&res);

                                const r = cbf.deserializeStruct(mobs.PlaceMobOptions, res.items[0].value.List, .{}) catch
                                    return error.InvalidMetadataValue;
                                f.features[identifier] = Feature{ .CMob = .{ .t = mob_t, .opts = r } };
                                f.features_global[identifier] = is_global;
                            } else if (mem.eql(u8, feature_type, "Ccont")) {
                                const container = for (&surfaces.ALL_CONTAINERS) |c| {
                                    if (mem.eql(u8, c.id, id orelse return error.MalformedFeatureDefinition)) break c;
                                } else return error.NoSuchContainer;

                                f.features[identifier] = Feature{ .CCont = .{ .t = container } };
                                f.features_global[identifier] = is_global;
                            } else if (mem.eql(u8, feature_type, "Cpitem")) {
                                const rest = line[@ptrToInt((id orelse return error.MalformedFeatureDefinition).ptr) - @ptrToInt(line.ptr) ..];
                                var cbf_p = cbf.Parser{ .input = rest };
                                var res = try cbf_p.parse(state.gpa.allocator());
                                defer cbf.Parser.deinit(&res);

                                // Probably more informative to just crash, given
                                // lack of error context if we return an error
                                //
                                // if (res.items.len > 1 or res.items[0].value != .List)
                                //     return error.MalformedFeatureDefinition;

                                var feature = Feature{ .Cpitem = .{
                                    .ts = StackBuffer(?*const Prop, 16).init(null),
                                    .we = StackBuffer(usize, 16).init(null),
                                } };
                                for (res.items[0].value.List.items) |entry| {
                                    const weight = entry.value.List.items[1].value.Usize;
                                    const prop = switch (entry.value.List.items[0].value) {
                                        .None => null,
                                        .String => |s| &surfaces.props.items[utils.findById(surfaces.props.items, s.constSlice()) orelse return error.NoSuchProp],
                                        else => return error.MalformedFeatureDefinition,
                                    };
                                    feature.Cpitem.ts.append(prop) catch err.wat();
                                    feature.Cpitem.we.append(weight) catch err.wat();
                                }

                                f.features[identifier] = feature;
                                f.features_global[identifier] = is_global;
                            } else if (mem.eql(u8, feature_type, "Ckey")) {
                                const rest = line[@ptrToInt((id orelse return error.MalformedFeatureDefinition).ptr) - @ptrToInt(line.ptr) ..];
                                var cbf_p = cbf.Parser{ .input = rest };
                                var res = try cbf_p.parse(state.gpa.allocator());
                                defer cbf.Parser.deinit(&res);

                                const r = cbf.deserializeValue(union(enum) { Up: []const u8, Down, Access }, res.items[0].value, null) catch return error.InvalidMetadataValue;
                                const artoo: surfaces.Stair.Type = switch (r) {
                                    .Up => |stairid| .{ .Up = state.findLevelByName(stairid) orelse return error.InvalidMetadataValue },
                                    .Access => .Access,
                                    .Down => return error.InvalidMetadataValue,
                                };
                                f.features[identifier] = Feature{ .Key = artoo };
                            } else if (mem.eql(u8, feature_type, "Cstair")) {
                                const rest = line[@ptrToInt((id orelse return error.MalformedFeatureDefinition).ptr) - @ptrToInt(line.ptr) ..];
                                var cbf_p = cbf.Parser{ .input = rest };
                                var res = try cbf_p.parse(state.gpa.allocator());
                                defer cbf.Parser.deinit(&res);

                                const r = cbf.deserializeStruct(struct {
                                    locked: bool = false,
                                    stairtype: union(enum) { Up: []const u8, Down, Access },
                                }, res.items[0].value.List, .{ .stairtype = .Down }) catch
                                    return error.InvalidMetadataValue;
                                const artoo = surfaces.Stair{
                                    .locked = r.locked,
                                    .stairtype = switch (r.stairtype) {
                                        .Up => |stairid| .{ .Up = state.findLevelByName(stairid) orelse return error.InvalidMetadataValue },
                                        .Access => .Access,
                                        .Down => .Down,
                                    },
                                };
                                f.features[identifier] = Feature{ .Stair = artoo };
                            } else {
                                return error.InvalidFeatureType;
                            }
                        },
                        's' => {
                            const level = state.findLevelByName(id orelse return error.InvalidMetadataValue) orelse
                                return error.InvalidMetadataValue;
                            f.features[identifier] = Feature{ .Stair = .{ .stairtype = .{ .Up = level } } };
                            f.features_global[identifier] = is_global;
                        },
                        'M' => {
                            if (mobs.findMobById(id orelse return error.MalformedFeatureDefinition)) |mob_template| {
                                f.features[identifier] = Feature{ .Mob = mob_template };
                                f.features_global[identifier] = is_global;
                            } else return error.NoSuchMob;
                        },
                        'P' => {
                            var buf = std.ArrayList(u8).init(state.gpa.allocator());
                            while (lines.next()) |poster_line| {
                                if (mem.eql(u8, poster_line, "END POSTER")) {
                                    break;
                                }
                                if (poster_line.len == 0) {
                                    try buf.appendSlice("\n\n");
                                } else {
                                    try buf.appendSlice(poster_line);
                                }
                                try buf.appendSlice(" ");
                            }
                            const poster_ptr = try literature.posters.appendAndReturn(.{
                                .level = try state.gpa.allocator().dupe(u8, "NUL"),
                                .text = buf.items,
                                .placement_counter = 0,
                            });
                            f.features[identifier] = Feature{ .Poster = poster_ptr };
                            f.features_global[identifier] = is_global;
                        },
                        'p' => {
                            f.features[identifier] = Feature{ .Prop = [_:0]u8{0} ** 32 };
                            f.features_global[identifier] = is_global;
                            mem.copy(u8, &f.features[identifier].?.Prop, id orelse return error.MalformedFeatureDefinition);
                        },
                        'm' => {
                            var points = StackBuffer(Coord, 16).init(null);
                            while (words.next()) |word| {
                                var coord = Coord.new2(0, 0, 0);
                                var coord_tokens = mem.tokenize(u8, word, ",");
                                const coord_str_a = coord_tokens.next() orelse return error.InvalidMetadataValue;
                                const coord_str_b = coord_tokens.next() orelse return error.InvalidMetadataValue;
                                coord.x = std.fmt.parseInt(usize, coord_str_a, 0) catch return error.InvalidMetadataValue;
                                coord.y = std.fmt.parseInt(usize, coord_str_b, 0) catch return error.InvalidMetadataValue;
                                points.append(coord) catch err.wat();
                            }
                            f.features[identifier] = Feature{
                                .Machine = .{
                                    .id = [_:0]u8{0} ** 32,
                                    .points = points,
                                },
                            };
                            mem.copy(u8, &f.features[identifier].?.Machine.id, id orelse return error.MalformedFeatureDefinition);
                            f.features_global[identifier] = is_global;
                        },
                        'i' => {
                            if (items.findItemById(id orelse return error.MalformedFeatureDefinition)) |template| {
                                f.features[identifier] = Feature{ .Item = template };
                                f.features_global[identifier] = is_global;
                            } else {
                                return error.NoSuchItem;
                            }
                        },
                        else => return error.InvalidFeatureType,
                    }
                },
                else => {
                    if (y > f.content.len) return error.FabTooTall;

                    var x: usize = 0;
                    var utf8view = std.unicode.Utf8View.init(line) catch {
                        return error.InvalidUtf8;
                    };
                    var utf8 = utf8view.iterator();
                    while (utf8.nextCodepointSlice()) |encoded_codepoint| : (x += 1) {
                        if (x > f.content[0].len) return error.FabTooWide;

                        const c = std.unicode.utf8Decode(encoded_codepoint) catch {
                            return error.InvalidUtf8;
                        };

                        f.content[y][x] = switch (c) {
                            '&' => .Window,
                            '#' => .Wall,
                            '+' => .Door,
                            '±' => .LockedDoor,
                            '⊞' => .HeavyLockedDoor,
                            '•' => .Brazier,
                            '˜' => .ShallowWater,
                            '@' => player: {
                                f.player_position = Coord.new(x, y);
                                break :player .Floor;
                            },
                            '.' => .Floor,
                            '*' => con: {
                                f.connections[ci] = .{
                                    .c = Coord.new(x, y),
                                    .d = .North,
                                };
                                ci += 1;

                                break :con .Connection;
                            },
                            '~' => .Water,
                            '≈' => .Lava,
                            '≡' => .Bars,
                            '=' => .Ring,
                            '?' => .Any,
                            'α'...'δ' => FabTile{ .LevelFeature = @as(usize, c - 'α') },
                            '0'...'9', 'a'...'z' => FabTile{ .Feature = @intCast(u8, c) },
                            'L' => .Loot1,
                            'R' => .RareLoot,
                            'C' => .Corpse,
                            else => return error.InvalidFabTile,
                        };
                    }

                    if (x > w) w = x;
                    y += 1;
                },
            }
        }

        try _finishParsing(name, y, w, &f);
    }

    pub fn findPrefabByName(name: []const u8, fabs: *const PrefabArrayList) ?*Prefab {
        for (fabs.items) |*f| if (mem.eql(u8, name, f.name.constSlice())) return f;
        return null;
    }

    pub fn lesserThan(_: void, a: Prefab, b: Prefab) bool {
        //return (a.priority > b.priority) or (a.height * a.width) > (b.height * b.width);
        return a.priority > b.priority;
    }

    pub fn incrementRecord(self: *Prefab, level: usize) void {
        const record = (state.fab_records.getOrPutValue(self.name.constSlice(), .{}) catch err.wat()).value_ptr;
        record.level[level] += 1;
        record.global += 1;
        self.level_uses[level] += 1;
    }
};

pub const PrefabArrayList = std.ArrayList(Prefab);

fn _readPrefab(name: []const u8, fab_f: std.fs.File, buf: []u8) void {
    const read = fab_f.readAll(buf[0..]) catch err.wat();

    Prefab.parseAndLoad(name, buf[0..read]) catch |e| {
        const msg = switch (e) {
            error.StockpileAlreadyDefined => "Stockpile already defined for prefab",
            error.OutputAreaAlreadyDefined => "Output area already defined for prefab",
            error.InputAreaAlreadyDefined => "Input area already defined for prefab",
            error.TooManyPrisons => "Too many prisons",
            error.TooManySubrooms => "Too many subroom areas",
            error.InvalidFabTile => "Invalid prefab tile",
            error.InvalidConnection => "Out of place connection tile",
            error.FabTooWide => "Prefab exceeds width limit",
            error.FabTooTall => "Prefab exceeds height limit",
            error.InvalidFeatureType => "Unknown feature type encountered",
            error.MalformedFeatureDefinition => "Invalid syntax for feature definition",
            error.NoSuchMob => "Encountered non-existent mob id",
            error.NoSuchItem => "Encountered non-existent item id",
            error.NoSuchContainer => "Encountered non-existent container id",
            error.NoSuchProp => "Encountered non-existent prop id",
            error.MalformedMetadata => "Malformed metadata",
            error.InvalidMetadataValue => "Invalid value for metadata",
            error.UnexpectedMetadataValue => "Unexpected value for metadata",
            error.UnexpectedEndOfFile => "Unexpected end of file",
            error.ExpectedMetadataValue => "Expected value for metadata",
            error.InvalidUtf8 => "Encountered invalid UTF-8",
            error.TooManyTransforms => "Too many transforms",
            error.UnimplementedTransformation => "Unimplemented transformation",
            error.OverflowingTransform => "Requested transform would overflow limits",
            else => "Unknown error",
        };
        std.log.err("{s}: Couldn't load prefab: {s} [{s}]", .{ name, msg, e });
    };
}

// FIXME: error handling
// FIXME: warn if prefab is zerowidth/zeroheight (prefabs file might not have fit in buffer)
pub fn readPrefabs(alloc: mem.Allocator) void {
    var buf: [8192]u8 = undefined;

    n_fabs = PrefabArrayList.init(alloc);
    s_fabs = PrefabArrayList.init(alloc);
    state.fab_records = @TypeOf(state.fab_records).init(alloc);

    for (&[_][]const u8{ "data/prefabs", "data/prefabs/tests", "data/prefabs/profiler" }) |dir| {
        const fabs_dir = std.fs.cwd().openDir(dir, .{ .iterate = true }) catch err.wat();

        var fabs_dir_iterator = fabs_dir.iterate();
        while (fabs_dir_iterator.next() catch err.wat()) |fab_file| {
            if (fab_file.kind != .File) continue;
            var fab_f = fabs_dir.openFile(fab_file.name, .{ .read = true }) catch err.wat();
            defer fab_f.close();
            _readPrefab(fab_file.name, fab_f, &buf);
        }
    }

    rng.shuffle(Prefab, s_fabs.items);
    std.sort.insertionSort(Prefab, s_fabs.items, {}, Prefab.lesserThan);

    std.log.info("Loaded {} prefabs.", .{n_fabs.items.len + s_fabs.items.len});
}

pub const LevelConfig = struct {
    stairs_to: []const usize = &[_]usize{},

    prefabs: []const []const u8 = &[_][]const u8{},
    distances: [2][10]usize = [2][10]usize{
        .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .{ 7, 4, 4, 3, 2, 1, 1, 0, 0, 0 },
    },
    shrink_corridors_to_fit: bool = true,
    prefab_chance: usize,

    mapgen_func: fn (usize, mem.Allocator) void = placeTunnelsThenRandomRooms,

    tunneler_opts: tunneler.TunnelerOptions = .{},

    // If true, will not place rooms on top of lava/water.
    require_dry_rooms: bool = false,

    // Determines the number of iterations used by the mapgen algorithm.
    //
    // On placeRandomRooms: try mapgen_iters times to place a rooms randomly.
    // On placeBSPRooms:    try mapgen_iters times to split a BSP node.
    mapgen_iters: usize = 2048,

    // Dimensions include the first wall, so a minimum width of 2 guarantee that
    // there will be one empty space in the room, minimum.
    min_room_width: usize = 8,
    min_room_height: usize = 8,
    max_room_width: usize = 18,
    max_room_height: usize = 18,

    level_features: [4]?LevelFeatureFunc = [_]?LevelFeatureFunc{ null, null, null, null },

    required_mobs: []const RequiredMob = &[_]RequiredMob{
        // .{ .count = 3, .template = &mobs.CleanerTemplate },
    },
    room_crowd_max: usize = 2,
    level_crowd_max: ?usize = null,
    lair_max: usize = 3,

    no_lights: bool = false,
    no_windows: bool = false,
    tiletype: TileType = .Wall,
    material: *const Material = &materials.Concrete,
    window_material: *const Material = &materials.Glass,
    light: *const Machine = &surfaces.Brazier,
    door: *const Machine = &surfaces.NormalDoor,
    vent: []const u8 = "gas_vent",
    bars: []const u8 = "iron_bars",
    machines: []const *const Machine = &[_]*const Machine{},
    props: *[]*const Prop = &surfaces.statue_props.items,
    // Props that can be placed in bulk along a single wall.
    single_props: []const []const u8 = &[_][]const u8{},
    chance_for_single_prop_placement: usize = 33, // percentage
    containers: []const Container = &[_]Container{
        //surfaces.Bin,
        //surfaces.Barrel,
        //surfaces.Cabinet,
        //surfaces.Chest,
    },
    utility_items: *[]*const Prop = &surfaces.prison_item_props.items,

    allow_statues: bool = true,
    door_chance: usize = 10,
    room_trapped_chance: usize = 60,
    subroom_chance: usize = 33,
    allow_spawn_in_corridors: bool = false,
    allow_extra_corridors: bool = true,

    blobs: []const BlobConfig = &[_]BlobConfig{},

    pub const LevelFeatureFunc = fn (usize, Coord, *const Room, *const Prefab, mem.Allocator) void;

    pub const RequiredMob = struct { count: usize, template: *const mobs.MobTemplate };

    pub const MobConfig = struct {
        chance: usize, // Ten in <chance>
        template: *const mobs.MobTemplate,
    };
};

// -----------------------------------------------------------------------------

pub fn createLevelConfig_PRI(crowd: usize, comptime prefabs: []const []const u8) LevelConfig {
    return LevelConfig{
        .prefabs = prefabs,
        .prefab_chance = 20,
        .mapgen_iters = 2048,
        .mapgen_func = placeRandomRooms,
        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeaturePrisoners,
            levelFeaturePrisonersMaybe,
            null,
            null,
        },

        .room_crowd_max = crowd,
        .machines = &[_]*const Machine{ &surfaces.FirstAidStation, &surfaces.Drain },
        .single_props = &[_][]const u8{ "wood_table", "wood_chair" },
    };
}

const HLD_BASE_LEVELCONFIG = LevelConfig{
    .prefabs = &[_][]const u8{"HLD_first_aid"},
    .tunneler_opts = .{
        .max_iters = 450,
        .max_length = math.max(WIDTH, HEIGHT),
        .turn_chance = 0,
        .branch_chance = 5,
        .reduce_branch_chance = true,
        .shrink_chance = 90,
        .grow_chance = 10,
        .room_bsp_split = true,
        .room_chance_min_size = 30,
        .room_chance_max_size = 45,
        .intersect_chance = 100,
        .intersect_with_childless = true,
        .initial_tunnelers = &[_]tunneler.TunnelerOptions.InitialTunneler{
            .{ .start = Coord.new(WIDTH - 14, 20), .width = 2, .height = 0, .direction = .South },
            .{ .start = Coord.new(14, HEIGHT - 20), .width = 2, .height = 0, .direction = .North },
        },
    },
    .prefab_chance = 70,
    .mapgen_func = tunneler.placeTunneledRooms,
    .lair_max = 0,

    .min_room_width = 6,
    .min_room_height = 6,
    .max_room_width = 25,
    .max_room_height = 25,

    .level_features = [_]?LevelConfig.LevelFeatureFunc{ null, null, null, null },

    .material = &materials.PlatedDobalene,
    .window_material = &materials.LabGlass,
    .light = &surfaces.Lamp,
    .bars = "titanium_bars",
    .door = &surfaces.LabDoor,
    .subroom_chance = 100,
    .allow_statues = false,

    .machines = &[_]*const Machine{},
};

pub fn createLevelConfig_LAB(comptime prefabs: []const []const u8) LevelConfig {
    return LevelConfig{
        .prefabs = prefabs,
        .tunneler_opts = .{
            .max_iters = 450,
            .max_length = math.max(WIDTH, HEIGHT),
            .turn_chance = 0,
            .branch_chance = 5,
            .reduce_branch_chance = true,
            .shrink_chance = 90,
            .grow_chance = 10,
            .intersect_chance = 100,
            .intersect_with_childless = true,
            .initial_tunnelers = &[_]tunneler.TunnelerOptions.InitialTunneler{
                .{ .start = Coord.new(14, 20), .width = 0, .height = 1, .direction = .East },
                .{ .start = Coord.new(WIDTH - 14, 20), .width = 1, .height = 0, .direction = .South },
                .{ .start = Coord.new(WIDTH - 13, HEIGHT - 21), .width = 0, .height = 1, .direction = .West },
                .{ .start = Coord.new(14, HEIGHT - 20), .width = 1, .height = 0, .direction = .North },
            },
        },
        .prefab_chance = 60,
        .mapgen_func = tunneler.placeTunneledRooms,
        .lair_max = 1,

        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeatureVials,
            levelFeaturePrisoners,
            levelFeatureDormantConstruct,
            levelFeatureOres,
        },

        .material = &materials.Dobalene,
        .window_material = &materials.LabGlass,
        .light = &surfaces.Lamp,
        .bars = "titanium_bars",
        .door = &surfaces.LabDoor,
        //.containers = &[_]Container{ surfaces.Chest, surfaces.LabCabinet },
        .containers = &[_]Container{surfaces.LabCabinet},
        .utility_items = &surfaces.laboratory_item_props.items,
        .props = &surfaces.laboratory_props.items,
        .single_props = &[_][]const u8{ "table", "centrifuge", "compact_turbine", "water_purifier", "distiller" },

        .subroom_chance = 70,
        .allow_statues = false,

        .machines = &[_]*const Machine{&surfaces.FirstAidStation},
    };
}

pub fn createLevelConfig_SIN(comptime width: usize) LevelConfig {
    return LevelConfig{
        .prefabs = &[_][]const u8{"SIN_candle"},
        .tunneler_opts = .{
            .min_tunneler_distance = 0,
            .turn_chance = 7,
            .branch_chance = 6,
            .room_tries = 1,
            .shrink_chance = 0,
            .grow_chance = 0,
            .intersect_chance = 99,
            .intersect_with_childless = true,
            .add_extra_rooms = false,
            .add_junctions = false,
            .remove_childless = false,
            .force_prefabs = true,
            .max_room_per_tunnel = 1,

            .initial_tunnelers = &[_]tunneler.TunnelerOptions.InitialTunneler{
                .{ .start = Coord.new(1, 1), .width = 0, .height = width, .direction = .East },
                // .{ .start = Coord.new(WIDTH - 5, 1), .width = width, .height = 0, .direction = .South },
                .{ .start = Coord.new(WIDTH - 1, HEIGHT - width - 2), .width = 0, .height = width, .direction = .West },
                // .{ .start = Coord.new(1, HEIGHT - 1), .width = width, .height = 0, .direction = .North },
            },
        },
        .prefab_chance = 100, // Only prefabs for SIN
        .mapgen_func = tunneler.placeTunneledRooms,
        .level_features = [_]?LevelConfig.LevelFeatureFunc{ null, null, null, null },
        .required_mobs = &[_]LevelConfig.RequiredMob{},
        .room_crowd_max = 1,
        .level_crowd_max = 18,
        .lair_max = 0,

        .material = &materials.Marble,
        .no_windows = true,

        .allow_spawn_in_corridors = true,
        .allow_statues = false,
        .allow_extra_corridors = false,
    };
}

pub fn createLevelConfig_CRY() LevelConfig {
    return LevelConfig{
        .tunneler_opts = .{
            .max_iters = 350,
            .turn_chance = 8,
            .turn_min_ticks_since_last = 20,
            .turn_min_factor = 5,
            .branch_chance = 6,
            .reduce_branch_chance = true,
            .allow_chaotic_branching = false,
            .shrink_chance = 80,
            .grow_chance = 20,
            // .remove_childless = false,
            .shrink_corridors = false,

            .initial_tunnelers = &[_]tunneler.TunnelerOptions.InitialTunneler{
                .{ .start = Coord.new(WIDTH - (WIDTH / 4), 10), .width = 0, .height = 1, .direction = .West },
                .{ .start = Coord.new(WIDTH / 4, HEIGHT - 10), .width = 0, .height = 1, .direction = .East },
            },
        },
        .prefab_chance = 0, // No prefabs for CRY
        .mapgen_func = tunneler.placeTunneledRooms,

        .min_room_width = 6,
        .min_room_height = 6,
        .max_room_width = 9,
        .max_room_height = 9,
        .lair_max = 0,

        .level_features = [_]?LevelConfig.LevelFeatureFunc{ null, null, null, null },

        .material = &materials.Marble,
        .no_windows = true,
        .door = &surfaces.VaultDoor,
        .allow_statues = false,
    };
}

pub fn createLevelConfig_WRK(crowd: usize, comptime prefabs: []const []const u8) LevelConfig {
    return LevelConfig{
        .prefabs = prefabs,
        .tunneler_opts = .{
            .max_length = math.max(WIDTH, HEIGHT),
            .turn_chance = 0,
            .branch_chance = 5,
            .allow_chaotic_branching = false,
            .reduce_branch_chance = true,
            .shrink_chance = 65,
            .grow_chance = 5,
            .intersect_chance = 100,
            .intersect_with_childless = true,
            .corridor_prefab_interval = 6,
            .pardon_first_gen = true,

            .initial_tunnelers = &[_]tunneler.TunnelerOptions.InitialTunneler{
                .{ .start = Coord.new(1, 1), .width = 0, .height = 3, .direction = .East },
                .{ .start = Coord.new(WIDTH - 4, 1), .width = 3, .height = 0, .direction = .South },
                .{ .start = Coord.new(WIDTH - 1, HEIGHT - 4), .width = 0, .height = 3, .direction = .West },
                .{ .start = Coord.new(1, HEIGHT - 1), .width = 3, .height = 0, .direction = .North },
            },
        },
        .prefab_chance = 65,
        .mapgen_func = tunneler.placeTunneledRooms,

        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeatureConstructParts,
            null,
            levelFeatureDormantConstruct,
            null,
        },

        .lair_max = 1,

        .material = &materials.Dobalene,
        .window_material = &materials.LabGlass,
        .light = &surfaces.Lamp,
        .bars = "titanium_bars",
        .door = &surfaces.LabDoor,
        //.containers = &[_]Container{ surfaces.Chest, surfaces.LabCabinet },
        .containers = &[_]Container{surfaces.LabCabinet},
        .utility_items = &surfaces.laboratory_item_props.items,
        .props = &surfaces.laboratory_props.items,
        .single_props = &[_][]const u8{"table"},

        .room_crowd_max = crowd,
        .subroom_chance = 90,
        .allow_statues = false,

        .machines = &[_]*const Machine{&surfaces.FirstAidStation},
    };
}

pub const CAV_BASE_LEVELCONFIG = LevelConfig{
    .prefabs = &[_][]const u8{},
    .distances = [2][10]usize{
        .{ 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 },
        .{ 1, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
    },
    .shrink_corridors_to_fit = true,
    .prefab_chance = 33,
    .mapgen_func = placeDrunkenWalkerCave,
    .mapgen_iters = 64,

    .min_room_width = 4,
    .min_room_height = 4,
    .max_room_width = 7,
    .max_room_height = 7,

    .required_mobs = &[_]LevelConfig.RequiredMob{
        .{ .count = 3, .template = &mobs.MellaentTemplate },

        // TODO: remove these entries when the mob placer is fixed
        // and stops dumping treacherously low numbers of enemies
        .{ .count = 3, .template = &mobs.ConvultTemplate },
        .{ .count = 3, .template = &mobs.VapourMageTemplate },
    },
    .room_crowd_max = 4,
    .level_crowd_max = 40,

    .require_dry_rooms = true,

    .level_features = [_]?LevelConfig.LevelFeatureFunc{
        null, null, null, null,
    },

    .no_windows = true,
    .material = &materials.Basalt,
    //.tiletype = .Floor,

    .allow_statues = false,
    .room_trapped_chance = 0,
    .allow_extra_corridors = false,
    .door = &surfaces.VaultDoor,

    .blobs = &[_]BlobConfig{
        .{
            .number = MinMax(usize){ .min = 10, .max = 15 },
            .type = null,
            .terrain = &surfaces.DeadFungiTerrain,
            .min_blob_width = minmax(usize, 2, 8),
            .min_blob_height = minmax(usize, 2, 8),
            .max_blob_width = minmax(usize, 9, 20),
            .max_blob_height = minmax(usize, 9, 20),
            .ca_rounds = 10,
            .ca_percent_seeded = 55,
            .ca_birth_params = "ffffffftt",
            .ca_survival_params = "ffftttttt",
        },
        .{
            .number = MinMax(usize){ .min = 2, .max = 3 },
            .type = .Lava,
            .min_blob_width = minmax(usize, 10, 12),
            .min_blob_height = minmax(usize, 8, 9),
            .max_blob_width = minmax(usize, 18, 19),
            .max_blob_height = minmax(usize, 14, 15),
            .ca_rounds = 5,
            .ca_percent_seeded = 55,
            .ca_birth_params = "ffffffttt",
            .ca_survival_params = "ffffttttt",
        },
    },

    .machines = &[_]*const Machine{
        // All machines are provided as subrooms
    },
};

pub const TUT_BASE_LEVELCONFIG = LevelConfig{
    .prefabs = &[_][]const u8{"TUT_basic"},
    .mapgen_func = placeRandomRooms,
    .prefab_chance = 100,
    .mapgen_iters = 0,
    .level_features = [_]?LevelConfig.LevelFeatureFunc{ null, null, null, null },
};

pub var Configs = [LEVELS]LevelConfig{
    createLevelConfig_CRY(),
    createLevelConfig_CRY(),
    createLevelConfig_CRY(),
    createLevelConfig_PRI(2, &[_][]const u8{ "PRI_main_exit", "PRI_main_exit_key" }),
    createLevelConfig_PRI(2, &[_][]const u8{}),
    HLD_BASE_LEVELCONFIG,
    createLevelConfig_LAB(&[_][]const u8{"LAB_HLD_stair"}),
    createLevelConfig_LAB(&[_][]const u8{}),
    createLevelConfig_SIN(6),
    createLevelConfig_LAB(&[_][]const u8{"LAB_s_SIN_stair_1"}),
    createLevelConfig_PRI(2, &[_][]const u8{}),
    // CAV_BASE_LEVELCONFIG,
    // CAV_BASE_LEVELCONFIG,
    CAV_BASE_LEVELCONFIG,
    createLevelConfig_PRI(2, &[_][]const u8{}),
    // createLevelConfig_WRK(2, &[_][]const u8{}),
    // createLevelConfig_WRK(2, &[_][]const u8{}),
    createLevelConfig_SIN(4),
    createLevelConfig_WRK(1, &[_][]const u8{"WRK_s_SIN_stair_1"}),
    createLevelConfig_PRI(1, &[_][]const u8{"PRI_NC"}),
    createLevelConfig_PRI(1, &[_][]const u8{"PRI_start"}),

    // TUT_BASE_LEVELCONFIG,
};
