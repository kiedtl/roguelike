const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;
const meta = std.meta;
const assert = std.debug.assert;

const astar = @import("astar.zig");
const err = @import("err.zig");
const rng = @import("rng.zig");
const dijkstra = @import("dijkstra.zig");
const mobs = @import("mobs.zig");
const StackBuffer = @import("buffer.zig").StackBuffer;
const items = @import("items.zig");
const surfaces = @import("surfaces.zig");
const literature = @import("literature.zig");
const materials = @import("materials.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
const tsv = @import("tsv.zig");
const types = @import("types.zig");

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
const Potion = types.Potion;
const SpatterArray = types.SpatterArray;
const Stockpile = types.Stockpile;
const ContainerArrayList = types.ContainerArrayList;
const CoordArrayList = types.CoordArrayList;
const Material = types.Material;
const Vial = types.Vial;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

const ItemTemplate = items.ItemTemplate;
const Evocable = items.Evocable;
const EvocableList = items.EvocableList;
const Cloak = items.Cloak;
const Poster = literature.Poster;

const CONNECTIONS_MAX = 4;

// TODO: replace with MinMax
const Range = struct { from: Coord, to: Coord };

const LIMIT = Rect{
    .start = Coord.new(1, 1),
    .width = state.WIDTH - 1,
    .height = state.HEIGHT - 1,
};

const Corridor = struct {
    room: Room,

    // Return the parent/child again because in certain cases callers
    // don't know what child was passed, e.g., the BSP algorithm
    //
    parent: *Room,
    child: *Room,

    parent_connector: ?Coord,
    child_connector: ?Coord,
    distance: usize,

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
    // ???
    // ###
    // ?.?
    "???###?.?",

    // ?.?
    // ###
    // ???
    "?.?###???",

    // ?#?
    // .#?
    // ?#?
    "?#?.#??#?",

    // ?#?
    // ?#.
    // ?#?
    "?#??#.?#?",
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
        const i = rng.range(usize, 0, literature.posters.items.len - 1);
        const p = &literature.posters.items[i];

        if (p.placement_counter > 0 or !mem.eql(u8, state.levelinfo[level].id, p.level))
            continue;

        p.placement_counter += 1;
        return p;
    }

    return null;
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

fn randomWallCoord(rect: *const Rect, i: ?usize) Coord {
    const rect_end = rect.end();

    const ranges = [_]Range{
        .{ .from = Coord.new(rect.start.x + 1, rect.start.y - 1), .to = Coord.new(rect_end.x - 2, rect.start.y - 1) }, // top
        .{ .from = Coord.new(rect.start.x + 1, rect_end.y), .to = Coord.new(rect_end.x - 2, rect_end.y) }, // bottom
        .{ .from = Coord.new(rect.start.x, rect.start.y + 1), .to = Coord.new(rect.start.x, rect_end.y - 2) }, // left
        .{ .from = Coord.new(rect_end.x, rect.start.y + 1), .to = Coord.new(rect_end.x, rect_end.y - 2) }, // left
    };

    const range = if (i) |_i| ranges[(_i + 1) % ranges.len] else rng.chooseUnweighted(Range, &ranges);
    const x = rng.rangeClumping(usize, range.from.x, range.to.x, 2);
    const y = rng.rangeClumping(usize, range.from.y, range.to.y, 2);
    return Coord.new2(rect.start.z, x, y);
}

fn _chooseLootItem(item_weights: []usize, value_range: MinMax(usize)) ItemTemplate {
    while (true) {
        const item_info = rng.choose(
            @TypeOf(items.ITEM_DROPS[0]),
            &items.ITEM_DROPS,
            item_weights,
        ) catch err.wat();

        if (!value_range.contains(item_info.w))
            continue;

        return item_info;
    }
}

fn placeProp(coord: Coord, prop_template: *const Prop) *Prop {
    var prop = prop_template.*;
    prop.coord = coord;
    state.props.append(prop) catch err.wat();
    const propptr = state.props.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Prop = propptr };
    return state.props.last().?;
}

fn placeContainer(coord: Coord, template: *const Container) void {
    var container = template.*;
    container.coord = coord;
    state.containers.append(container) catch err.wat();
    const ptr = state.containers.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Container = ptr };
}

fn _place_machine(coord: Coord, machine_template: *const Machine) void {
    var machine = machine_template.*;
    machine.coord = coord;
    state.machines.append(machine) catch err.wat();
    const machineptr = state.machines.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = machineptr };
}

fn placeDoor(coord: Coord, locked: bool) void {
    var door = if (locked) surfaces.LockedDoor else Configs[coord.z].door.*;
    door.coord = coord;
    state.machines.append(door) catch err.wat();
    const doorptr = state.machines.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = doorptr };
    state.dungeon.at(coord).type = .Floor;
}

fn _add_player(coord: Coord, alloc: mem.Allocator) void {
    const echoring = items.createItem(Ring, items.EcholocationRing);
    echoring.worn_since = state.ticks;

    state.player = mobs.placeMob(alloc, &mobs.PlayerTemplate, coord, .{ .phase = .Hunt });
    state.player.inventory.rings[0] = echoring;
    state.player.prisoner_status = Prisoner{ .of = .Necromancer };
}

fn prefabIsValid(level: usize, prefab: *Prefab) bool {
    if (prefab.invisible) {
        return false; // Can't be used unless specifically called for by name.
    }

    if (!mem.eql(u8, prefab.name.constSlice()[0..3], state.levelinfo[level].id) and
        !mem.eql(u8, prefab.name.constSlice()[0..3], "ANY"))
    {
        return false; // Prefab isn't for this level.
    }

    if (prefab.used[level] >= prefab.restriction) {
        return false; // Prefab was used too many times.
    }

    return true;
}

fn choosePrefab(level: usize, prefabs: *PrefabArrayList) ?*Prefab {
    var i: usize = 512;
    while (i > 0) : (i -= 1) {
        // Don't use rng.chooseUnweighted, as we need a pointer
        const p = &prefabs.items[rng.range(usize, 0, prefabs.items.len - 1)];

        if (prefabIsValid(level, p)) return p;
    }

    return null;
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

fn findIntersectingRoom(
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

        if (other.type == .Corridor and ignore_corridors) {
            continue;
        }

        if (room.rect.intersects(&other.rect, 1)) return i;
    }

    return null;
}

fn isRoomInvalid(
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
                    state.dungeon.at(coord).type == .Water)
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

fn excavatePrefab(
    room: *Room,
    fab: *const Prefab,
    allocator: mem.Allocator,
    startx: usize,
    starty: usize,
) void {
    // Generate loot items.
    //
    // FIXME: generate this once at comptime.
    var item_weights: [items.ITEM_DROPS.len]usize = undefined;
    for (items.ITEM_DROPS) |item, i| item_weights[i] = item.w;

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

            const tt: ?TileType = switch (fab.content[y][x]) {
                .Any, .Connection => null,
                .Window, .Wall => .Wall,
                .LevelFeature,
                .Feature,
                .LockedDoor,
                .Door,
                .Bars,
                .Brazier,
                .ShallowWater,
                .Floor,
                .Loot1,
                .RareLoot,
                => .Floor,
                .Water => .Water,
                .Lava => .Lava,
            };
            if (tt) |_tt| state.dungeon.at(rc).type = _tt;

            if (fab.material) |mat|
                if (fab.content[y][x] != .Any) {
                    state.dungeon.at(rc).material = mat;
                };

            switch (fab.content[y][x]) {
                .Window => state.dungeon.at(rc).material = &materials.Glass,
                .LevelFeature => |l| (Configs[room.rect.start.z].level_features[l].?)(l, rc, room, fab, allocator),
                .Feature => |feature_id| {
                    if (fab.features[feature_id]) |feature| {
                        switch (feature) {
                            .Potion => |pid| {
                                if (utils.findById(&items.POTIONS, pid)) |potion_i| {
                                    const potion_o = items.POTIONS[potion_i];
                                    state.dungeon.itemsAt(rc).append(Item{ .Potion = potion_o }) catch err.wat();
                                } else {
                                    std.log.err(
                                        "{s}: Couldn't load potion {s}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(pid) },
                                    );
                                }
                            },
                            .Prop => |pid| {
                                if (utils.findById(surfaces.props.items, pid)) |prop| {
                                    _ = placeProp(rc, &surfaces.props.items[prop]);
                                } else {
                                    std.log.err(
                                        "{s}: Couldn't load prop {s}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(pid) },
                                    );
                                }
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
                .Door => placeDoor(rc, false),
                .Brazier => _place_machine(rc, Configs[room.rect.start.z].light),
                .ShallowWater => state.dungeon.at(rc).terrain = &surfaces.ShallowWaterTerrain,
                .Bars => {
                    const p_ind = utils.findById(surfaces.props.items, Configs[room.rect.start.z].bars);
                    _ = placeProp(rc, &surfaces.props.items[p_ind.?]);
                },
                .Loot1 => {
                    const loot_item1 = _chooseLootItem(&item_weights, minmax(usize, 60, 200));
                    state.dungeon.itemsAt(rc).append(items.createItemFromTemplate(loot_item1)) catch err.wat();
                },
                .RareLoot => {
                    const rare_loot_item = _chooseLootItem(&item_weights, minmax(usize, 0, 60));
                    state.dungeon.itemsAt(rc).append(items.createItemFromTemplate(rare_loot_item)) catch err.wat();
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
}

fn excavateRect(rect: *const Rect) void {
    var y = rect.start.y;
    while (y < rect.end().y) : (y += 1) {
        var x = rect.start.x;
        while (x < rect.end().x) : (x += 1) {
            const c = Coord.new2(rect.start.z, x, y);
            assert(c.x < WIDTH and c.y < HEIGHT);
            state.dungeon.at(c).type = .Floor;
        }
    }
}

// Destroy items, machines, and mobs associated with level and reset level's
// terrain.
//
// Also, reset the `used` counters and connections for prefabs.
pub fn resetLevel(level: usize, n_fabs: *PrefabArrayList, s_fabs: *PrefabArrayList) void {
    for (n_fabs.items) |*fab| fab.reset(level);
    for (s_fabs.items) |*fab| fab.reset(level);

    var mobiter = state.mobs.iterator();
    while (mobiter.next()) |mob| {
        if (mob.coord.z == level) {
            mob.deinit();
            state.mobs.remove(mob);
        }
    }

    var machiter = state.machines.iterator();
    while (machiter.next()) |machine| {
        if (machine.coord.z == level) {
            state.machines.remove(machine);
        }
    }

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

            state.dungeon.itemsAt(coord).clear();
        }
    }

    state.rooms[level].shrinkRetainingCapacity(0);
    state.stockpiles[level].shrinkRetainingCapacity(0);
    state.inputs[level].shrinkRetainingCapacity(0);
    state.outputs[level].shrinkRetainingCapacity(0);
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

pub fn validateLevel(
    level: usize,
    alloc: mem.Allocator,
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
) bool {
    // utility functions
    const _f = struct {
        pub fn _getWalkablePoint(room: *const Rect) Coord {
            var y: usize = room.start.y;
            while (y < room.end().y) : (y += 1) {
                var x: usize = room.start.x;
                while (x < room.end().x) : (x += 1) {
                    const point = Coord.new2(room.start.z, x, y);
                    if (state.dungeon.at(point).type == .Floor and
                        state.dungeon.at(point).surface == null)
                    {
                        return point;
                    }
                }
            }
            std.log.err(
                "BUG: found no walkable point in room (dim: {}x{})",
                .{ room.width, room.height },
            );
            err.wat();
        }
    };

    const rooms = state.rooms[level].items;
    const base_room = b: while (true) {
        const r = rng.chooseUnweighted(Room, rooms);
        if (r.type != .Corridor) break :b r;
    } else err.wat();
    const point = _f._getWalkablePoint(&base_room.rect);

    // Ensure that all required prefabs were used.
    for (Configs[level].prefabs) |required_fab| {
        const fab = Prefab.findPrefabByName(required_fab, n_fabs) orelse
            Prefab.findPrefabByName(required_fab, s_fabs).?;

        if (fab.used[level] == 0) {
            return false;
        }
    }

    for (rooms) |otherroom| {
        if (otherroom.type == .Corridor) continue;
        if (otherroom.rect.start.eq(base_room.rect.start)) continue;

        const otherpoint = _f._getWalkablePoint(&otherroom.rect);

        if (astar.path(point, otherpoint, state.mapgeometry, state.is_walkable, .{
            .ignore_mobs = true,
        }, &DIRECTIONS, alloc)) |p| {
            p.deinit();
        } else {
            return false;
        }
    }

    return true;
}

pub fn placeMoarCorridors(level: usize, alloc: mem.Allocator) void {
    var newrooms = Room.ArrayList.init(alloc);
    defer newrooms.deinit();

    const rooms = &state.rooms[level];

    var i: usize = 0;
    while (i < rooms.items.len) : (i += 1) {
        const parent = &rooms.items[i];

        for (rooms.items) |*child| {
            if (parent.connections.isFull() or
                child.connections.isFull() or
                parent.connections.linearSearch(child.rect.start, Coord.eqNotInline) or
                child.connections.linearSearch(parent.rect.start, Coord.eqNotInline))
            {
                continue;
            }

            //if (child.type == .Corridor) continue;

            // Skip child prefabs for now, placeCorridor seems to be broken
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

                parent.connections.append(child.rect.start) catch err.wat();
                child.connections.append(parent.rect.start) catch err.wat();

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

    room.type = .Corridor;

    return Corridor{
        .room = room,
        .parent = parent,
        .child = child,
        .parent_connector = parent_connector_coord,
        .child_connector = child_connector_coord,
        .distance = switch (side) {
            .North, .South => room.rect.height,
            .West, .East => room.rect.width,
            else => err.wat(),
        },
        .fab_connectors = fab_connectors,
    };
}

const SubroomPlacementOptions = struct {};

fn placeSubroom(s_fabs: *PrefabArrayList, parent: *Room, area: *const Rect, alloc: mem.Allocator, _: SubroomPlacementOptions) void {
    for (s_fabs.items) |*subroom| {
        if (!prefabIsValid(parent.rect.start.z, subroom)) {
            continue;
        }

        if (subroom.center_align) {
            if (subroom.height % 2 != area.height % 2 or
                subroom.width % 2 != area.width % 2)
            {
                continue;
            }
        }

        if ((subroom.height + 2) < area.height and (subroom.width + 2) < area.width) {
            const rx = (area.width / 2) - (subroom.width / 2);
            const ry = (area.height / 2) - (subroom.height / 2);

            var parent_adj = parent.*;
            parent_adj.rect = parent_adj.rect.add(area);

            excavatePrefab(&parent_adj, subroom, alloc, rx, ry);
            subroom.used[parent.rect.start.z] += 1;
            parent.has_subroom = true;
            break;
        }
    }
}

fn _place_rooms(
    rooms: *Room.ArrayList,
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: mem.Allocator,
) void {
    const parent_i = rng.range(usize, 0, rooms.items.len - 1);
    var parent = &rooms.items[parent_i];

    if (parent.connections.isFull()) {
        return;
    }

    var fab: ?*Prefab = null;
    var distance = rng.choose(usize, &Configs[level].distances[0], &Configs[level].distances[1]) catch err.wat();
    var child: Room = undefined;
    var side = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);

    if (rng.onein(Configs[level].prefab_chance)) {
        if (distance == 0) distance += 1;

        fab = choosePrefab(level, n_fabs) orelse return;
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

        var child_w = rng.rangeClumping(usize, Configs[level].min_room_width, Configs[level].max_room_width, 2);
        var child_h = rng.rangeClumping(usize, Configs[level].min_room_height, Configs[level].max_room_height, 2);
        var childrect = attachRect(parent, side, child_w, child_h, distance, null) orelse return;

        var i: usize = 0;
        while (isRoomInvalid(rooms, &Room{ .rect = childrect }, parent, null, true) or
            childrect.overflowsLimit(&LIMIT)) : (i += 1)
        {
            if (child_w < Configs[level].min_room_width or
                child_h < Configs[level].min_room_height)
                return;

            // Alternate between shrinking the corridor and shrinking the room
            if (i % 2 == 0 and Configs[level].shrink_corridors_to_fit and distance > 1) {
                distance -= 1;
            } else {
                child_w -= 1;
                child_h -= 1;
            }

            childrect = attachRect(parent, side, child_w, child_h, distance, null) orelse return;
        }

        child = Room{ .rect = childrect };
    }

    var corridor: ?Corridor = null;

    if (distance > 0 and Configs[level].allow_corridors) {
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

    if (child.prefab) |f|
        f.used[level] += 1;

    if (child.prefab == null) {
        if (rng.percent(Configs[level].subroom_chance)) {
            placeSubroom(s_fabs, &child, &Rect{
                .start = Coord.new(0, 0),
                .width = child.rect.width,
                .height = child.rect.height,
            }, allocator, .{});
        }
    } else if (child.prefab.?.subroom_areas.len > 0) {
        for (child.prefab.?.subroom_areas.constSlice()) |subroom_area| {
            placeSubroom(s_fabs, &child, &subroom_area, allocator, .{});
        }
    }

    // Use parent's index, as we appended the corridor earlier and that may
    // have invalidated parent's pointer
    rooms.items[parent_i].connections.append(child.rect.start) catch err.wat();
    child.connections.append(parent.rect.start) catch err.wat();

    rooms.append(child) catch err.wat();
}

pub fn placeRandomRooms(
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: mem.Allocator,
) void {
    var first: ?Room = null;
    const rooms = &state.rooms[level];

    var required = Configs[level].prefabs;
    var reqctr: usize = 0;

    while (reqctr < required.len) {
        const fab_name = required[reqctr];
        const fab = Prefab.findPrefabByName(fab_name, n_fabs) orelse {
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

        const x = rng.rangeClumping(usize, 1, state.WIDTH - fab.width - 1, 2);
        const y = rng.rangeClumping(usize, 1, state.HEIGHT - fab.height - 1, 2);

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
        fab.used[level] += 1;
        excavatePrefab(&room, fab, allocator, 0, 0);
        rooms.append(room) catch err.wat();

        reqctr += 1;
    }

    if (first == null) {
        const width = rng.range(usize, Configs[level].min_room_width, Configs[level].max_room_width);
        const height = rng.range(usize, Configs[level].min_room_height, Configs[level].max_room_height);
        const x = rng.range(usize, 1, state.WIDTH - width - 1);
        const y = rng.range(usize, 1, state.HEIGHT - height - 1);
        first = Room{
            .rect = Rect{ .start = Coord.new2(level, x, y), .width = width, .height = height },
        };
        excavateRect(&first.?.rect);
        rooms.append(first.?) catch err.wat();
    }

    if (level == state.PLAYER_STARTING_LEVEL) {
        var p = Coord.new2(level, first.?.rect.start.x + 1, first.?.rect.start.y + 1);
        if (first.?.prefab) |prefab|
            if (prefab.player_position) |pos| {
                p = Coord.new2(level, first.?.rect.start.x + pos.x, first.?.rect.start.y + pos.y);
            };
        _add_player(p, allocator);
    }

    var c = Configs[level].mapgen_iters;
    while (c > 0) : (c -= 1) {
        _place_rooms(rooms, n_fabs, s_fabs, level, allocator);
    }
}

pub fn placeBSPRooms(
    _: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: mem.Allocator,
) void {
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
            alloc: mem.Allocator,
        ) mem.Allocator.Error!void {
            var branches = ArrayList.init(alloc);
            defer branches.deinit();
            try branches.append(self);

            var iters: usize = Configs[maplevel].mapgen_iters;
            while (iters > 0 and branches.items.len > 0) : (iters -= 1) {
                const cur = branches.swapRemove(rng.range(usize, 0, branches.items.len - 1));

                if (cur.rect.height <= 3 or cur.rect.width <= 3) {
                    continue;
                }

                var new1: Rect = undefined;
                var new2: Rect = undefined;

                // Ratio to split by.
                //
                // e.g., if percent == 30%, then new1 will be 30% of original,
                // and new2 will be 70% of original.
                const percent = rng.range(usize, 25, 75);

                // Split horizontally or vertically
                if ((cur.rect.height * 2) > cur.rect.width) {
                    cur.splitH(percent, &new1, &new2);
                } else if (cur.rect.width > (cur.rect.height * 2)) {
                    cur.splitV(percent, &new1, &new2);
                } else {
                    if (rng.tenin(18)) {
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

                    if (prospective_child.width > Configs[maplevel].min_room_width and
                        prospective_child.height > Configs[maplevel].min_room_height)
                    {
                        has_child = true;

                        if (prospective_child.width < Configs[maplevel].max_room_width or
                            prospective_child.height < Configs[maplevel].max_room_height)
                        {
                            try leaves.append(node);
                            node.group = .Leaf;
                        } else {
                            try branches.append(node);
                            node.group = .Branch;
                        }
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
        .rect = Rect{ .start = Coord.new2(level, 1, 1), .height = HEIGHT - 2, .width = WIDTH - 2 },
        .group = .Root,
    };
    grandma_node.splitTree(&failed, &leaves, level, allocator) catch err.wat();
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

        excavateRect(&room.rect);

        if (rng.percent(Configs[level].subroom_chance)) {
            placeSubroom(s_fabs, &room, &Rect{
                .start = Coord.new(0, 0),
                .width = room.rect.width,
                .height = room.rect.height,
            }, allocator, .{});
        }

        container_node.index = rooms.items.len;
        rooms.append(room) catch err.wat();
    }

    const S = struct {
        const Self = @This();

        // Recursively descend tree, looking for a leaf's rectangle
        fn getRectFromNode(node: *const Node) ?usize {
            if (node.group == .Leaf or node.group == .Failed)
                return node.index;

            if (node.childs[0]) |child| return getRectFromNode(child);
            if (node.childs[1]) |child| return getRectFromNode(child);

            return null;
        }

        fn tryNodeConnection(maplevel: usize, parent: Rect, child: Rect) ?Corridor {
            var parentr = Room{ .rect = parent };
            var childr = Room{ .rect = child };

            const d = getConnectionSide(&parentr, &childr) orelse return null;
            if (createCorridor(maplevel, &parentr, &childr, d)) |corridor| {
                // FIXME: 2021-09-18: uncomment this and disable intersecting
                // corridors, for some weird reason this code doesn't try
                // connecting another room if its first try fails...? (Far too
                // tired to fix this now after working on it for 48+ hours...)
                //
                // Addendum 2021-09-21: Might be because a room behind another
                // is trying to connect to a room in front of it? Need a way
                // to find another parent node if it's not valid.
                //
                // if (isRoomInvalid(roomlist, &corridor.room, parent, child, false))
                //     return null;
                return corridor;
            } else {
                return null;
            }
        }

        // Recursively attempt connection.
        fn tryRecursiveNodeConnection(
            maplevel: usize,
            parent: *Rect,
            child_tree: *const Node,
            roomlist: *Room.ArrayList,
        ) ?Corridor {
            if (child_tree.group == .Leaf or child_tree.group == .Failed) {
                const child = roomlist.items[child_tree.index].rect;
                return tryNodeConnection(maplevel, parent.*, child);
            }

            if (child_tree.childs[0]) |child|
                if (tryRecursiveNodeConnection(maplevel, parent, child, roomlist)) |c|
                    return c;

            if (child_tree.childs[1]) |child|
                if (tryRecursiveNodeConnection(maplevel, parent, child, roomlist)) |c|
                    return c;

            return null;
        }

        // Recursively excavate corridors.
        //
        // doorlist: a list of possible spots to place a door. Populated as
        //   such spots are found.
        //
        //   NOTE: We cannot place doors right away, because we might end up
        //   with empty spots next to it as we continue to recursively excavate
        //   corridors.
        //
        fn excavateCorridors(
            maplevel: usize,
            node: *Node,
            roomlist: *Room.ArrayList,
            doorlist: *CoordArrayList,
        ) void {
            const childs = node.childs;

            if (childs[0] != null and childs[1] != null) {
                var child1 = &roomlist.items[getRectFromNode(childs[0].?).?].rect;

                if (tryRecursiveNodeConnection(maplevel, child1, childs[1].?, roomlist)) |corridor| {
                    corridor.parent.connections.append(corridor.child.rect.start) catch err.wat();
                    corridor.child.connections.append(corridor.parent.rect.start) catch err.wat();

                    excavateRect(&corridor.room.rect);
                    roomlist.append(corridor.room) catch err.wat();
                    doorlist.append(corridor.room.rect.start) catch err.wat();
                }
            }

            if (childs[0]) |child| excavateCorridors(maplevel, child, roomlist, doorlist);
            if (childs[1]) |child| excavateCorridors(maplevel, child, roomlist, doorlist);
        }

        pub fn addCorridorsAndDoors(
            maplevel: usize,
            node: *Node,
            roomlist: *Room.ArrayList,
            alloc: mem.Allocator,
        ) void {
            var doorlist = CoordArrayList.init(alloc);
            defer doorlist.deinit();

            excavateCorridors(maplevel, node, roomlist, &doorlist);

            for (doorlist.items) |doorspot|
                if (utils.findPatternMatch(doorspot, &VALID_DOOR_PLACEMENT_PATTERNS) != null and
                    rng.tenin(Configs[maplevel].door_chance))
                {
                    placeDoor(doorspot, false);
                };
        }
    };

    S.addCorridorsAndDoors(level, &grandma_node, rooms, allocator);
}

pub fn placeItems(level: usize) void {
    // FIXME: generate this at comptime.
    var item_weights: [items.ITEM_DROPS.len]usize = undefined;
    for (items.ITEM_DROPS) |item, i| item_weights[i] = item.w;

    // Fill up containers first.
    var containers = state.containers.iterator();
    while (containers.next()) |container| {
        if (container.coord.z != level) continue;

        // How much should we fill the container?
        const fill = rng.rangeClumping(usize, 0, container.capacity, 2);

        switch (container.type) {
            .Utility => if (Configs[level].utility_items.*.len > 0) {
                const item_list = Configs[level].utility_items.*;
                var item = &item_list[rng.range(usize, 0, item_list.len - 1)];
                var i: usize = 0;
                while (i < fill) : (i += 1) {
                    if (rng.range(usize, 0, 100) < container.item_repeat) {
                        item = &item_list[rng.range(usize, 0, item_list.len - 1)];
                    }

                    container.items.append(Item{ .Prop = item }) catch err.wat();
                }
            },
            else => {},
        }
    }

    // Now drop items that the player could use.
    room_iter: for (state.rooms[level].items) |room| {
        // Don't place items if:
        // - Room is a corridor. Loot in corridors is dumb (looking at you, DCSS).
        // - Room has a subroom (might be too crowded!).
        // - Room is a prefab and the prefab forbids items.
        // - Random chance.
        //
        if (room.type == .Corridor or
            room.has_subroom or
            (room.prefab != null and room.prefab.?.noitems) or
            rng.tenin(15))
        {
            continue;
        }

        const max_items = rng.range(usize, 1, 2);
        var items_placed: usize = 0;

        while (items_placed < max_items) : (items_placed += 1) {
            var tries: usize = 500;
            var item_coord: Coord = undefined;

            while (true) {
                item_coord = room.rect.randomCoord();

                // FIXME: uhg, this will reject tiles with mobs on it, even
                // though that's not what we want. On the other hand, killing
                // a guard that has a potion underneath it will cause the
                // corpse to hide the potion...
                if (isTileAvailable(item_coord) and
                    !state.dungeon.at(item_coord).prison)
                    break; // we found a valid coord

                // didn't find a coord, continue to the next room...
                if (tries == 0) continue :room_iter;
                tries -= 1;
            }

            const t = _chooseLootItem(&item_weights, minmax(usize, 0, 200));
            const item = items.createItemFromTemplate(t);
            state.dungeon.itemsAt(item_coord).append(item) catch err.wat();
        }
    }
}

pub fn placeTraps(level: usize) void {
    room_iter: for (state.rooms[level].items) |maproom| {
        if (maproom.prefab) |rfb| if (rfb.notraps) continue;
        const room = maproom.rect;

        // Don't place traps in places where it's impossible to avoid
        if (room.height == 1 or room.width == 1 or maproom.type != .Room)
            continue;

        if (!rng.percent(Configs[level].room_trapped_chance))
            continue;

        var tries: usize = 30;
        var trap_coord: Coord = undefined;

        while (true) {
            trap_coord = room.randomCoord();

            if (isTileAvailable(trap_coord) and
                !state.dungeon.at(trap_coord).prison and
                state.dungeon.neighboringWalls(trap_coord, true) <= 1)
                break; // we found a valid coord

            // didn't find a coord, continue to the next room
            if (tries == 0) continue :room_iter;
            tries -= 1;
        }

        var trap = switch (rng.range(usize, 0, 4)) {
            0, 1 => surfaces.ConfusionGasTrap,
            2, 3 => surfaces.ParalysisGasTrap,
            4 => surfaces.PoisonGasTrap,
            else => err.wat(),
        };

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

            if (avg_dist < 4 or
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
    // Create spawn tables.
    var spawn_table_ids = std.ArrayList([]const u8).init(alloc);
    var spawn_table_weights = std.ArrayList(usize).init(alloc);
    {
        var iter = mob_spawn_tables.iterator();
        while (iter.next()) |mob_spawn_data| {
            if (mob_spawn_data.value_ptr[level] == 0) continue;
            spawn_table_ids.append(mob_spawn_data.key_ptr.*) catch err.oom();
            spawn_table_weights.append(mob_spawn_data.value_ptr.*[level]) catch err.oom();
        }
    }
    defer spawn_table_ids.deinit();
    defer spawn_table_weights.deinit();

    var level_mob_count: usize = 0;

    for (state.rooms[level].items) |*room| {
        if (Configs[level].level_crowd_max) |level_crowd_max| {
            if (level_mob_count >= level_crowd_max) {
                continue;
            }
        }

        if (room.prefab) |rfb| if (rfb.noguards) continue;
        if (room.type == .Corridor) continue;
        if (room.rect.height * room.rect.width < 25) continue;

        const max_crowd = rng.range(usize, 1, Configs[level].room_crowd_max);

        while (room.mob_count < max_crowd) {
            const mob_id = rng.choose(
                []const u8,
                spawn_table_ids.items,
                spawn_table_weights.items,
            ) catch err.wat();
            const mob = mobs.findMobById(mob_id) orelse err.bug(
                "Mob {s} specified in spawn tables couldn't be found.",
                .{mob_id},
            );

            var tries: usize = 100;
            while (tries > 0) : (tries -= 1) {
                const post_coord = room.rect.randomCoord();
                if (!isTileAvailable(post_coord) or state.dungeon.at(post_coord).prison)
                    continue;

                const m = mobs.placeMob(alloc, mob, post_coord, .{
                    .facing = rng.chooseUnweighted(Direction, &DIRECTIONS),
                });
                const new_mobs = 1 + m.squad_members.items.len;

                room.mob_count += new_mobs;
                level_mob_count += new_mobs;

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

pub fn placeRoomFeatures(level: usize, alloc: mem.Allocator) void {
    for (state.rooms[level].items) |*room| {
        const rect = room.rect;
        const room_area = rect.height * rect.width;

        // Don't fill or light up small rooms or corridors.
        if (room_area < 16 or rect.height <= 2 or rect.width <= 2 or room.type == .Corridor) {
            continue;
        }

        placeLights(room);
        placeWindow(room);

        if (room.prefab != null) continue;
        if (room.has_subroom and room_area < 25) continue;

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
            if (Configs[level].containers.len > 0) 10 else 0,
            if (Configs[level].machines.len > 0) 10 else 0,
            if (room_area >= 25) 6 else 0,
            5,
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
                        const prop = rng.chooseUnweighted(Prop, Configs[level].props.*);
                        _ = placeProp(coord, &prop);
                        props += 1;
                    }
                },
                .Containers => {
                    if (containers < max_containers) {
                        var cont = rng.chooseUnweighted(Container, Configs[level].containers);
                        placeContainer(coord, &cont);
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

fn _setTerrain(coord: Coord, terrain: *const surfaces.Terrain) void {
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
        if (rng.percent(@as(usize, 40)) or
            room.rect.width <= 4 or room.rect.height <= 4)
        {
            continue;
        }

        const rect = room.rect;

        const chosen_terrain = rng.choose(
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
                        _setTerrain(coord, chosen_terrain);
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
                        _setTerrain(coord, chosen_terrain);
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
    assert(level != 0);

    // Find a location for the "reciever" staircase.
    const down_staircase = b: for (state.dungeon.map[dest_floor]) |*row, y| {
        for (row) |_, x| {
            const room: ?*Room = switch (state.layout[dest_floor][y][x]) {
                .Unknown => null,
                .Room => |r| &state.rooms[dest_floor].items[r],
            };

            if (room != null and room.?.has_stair) {
                continue;
            }

            const coord = Coord.new2(dest_floor, x, y);

            if (state.dungeon.at(coord).type == .Wall and
                !state.dungeon.at(coord).prison and
                utils.hasPatternMatch(coord, &VALID_STAIR_PLACEMENT_PATTERNS))
            {
                break :b coord;
            }
        }
    } else err.bug("Couldn't place a downstair on {s}!", .{state.levelinfo[dest_floor].name});

    // Find coord candidates for stairs placement. Usually this will be in a room,
    // but we're not forcing it because that wouldn't work well for Caverns.
    //
    var locations = CoordArrayList.init(alloc);
    defer locations.deinit();
    for (state.dungeon.map[level]) |*row, y| {
        for (row) |_, x| {
            const room: ?*Room = switch (state.layout[level][y][x]) {
                .Unknown => null,
                .Room => |r| &state.rooms[level].items[r],
            };

            if (room != null and room.?.has_stair) {
                continue;
            }

            const coord = Coord.new2(level, x, y);

            if (state.dungeon.at(coord).type == .Wall and
                !state.dungeon.at(coord).prison and
                utils.hasPatternMatch(coord, &VALID_STAIR_PLACEMENT_PATTERNS))
            {
                locations.append(coord) catch err.wat();
            }
        }
    }

    if (locations.items.len == 0) {
        err.bug("Couldn't place stairs anywhere on {s}!", .{state.levelinfo[level].name});
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
    for (state.dungeon.stairs) |level_stairs| {
        for (level_stairs.constSlice()) |stair| {
            if (state.dungeon.at(stair).surface.?.Stair) |stair_dest|
                if (stair_dest.z == level) {
                    stair_dijkmap[stair_dest.y][stair_dest.x] = 0;
                };
        }
    }
    if (level == state.PLAYER_STARTING_LEVEL)
        stair_dijkmap[state.player.coord.y][state.player.coord.x] = 0;

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
    state.dungeon.at(up_staircase).surface = .{ .Stair = down_staircase };
    switch (state.layout[level][up_staircase.y][up_staircase.x]) {
        .Room => |r| state.rooms[level].items[r].has_stair = true,
        else => {},
    }
    state.dungeon.stairs[level].append(up_staircase) catch err.wat();

    state.dungeon.at(down_staircase).type = .Floor;
    state.dungeon.at(down_staircase).surface = .{ .Stair = null };
    switch (state.layout[dest_floor][down_staircase.y][down_staircase.x]) {
        .Room => |r| state.rooms[dest_floor].items[r].has_stair = true,
        else => {},
    }

    // Place a guardian near the stairs in a diagonal position, if possible.
    for (&DIRECTIONS) |d| {
        if (!d.is_diagonal()) continue;
        if (up_staircase.move(d, state.mapgeometry)) |neighbor| {
            if (state.is_walkable(neighbor, .{ .right_now = true })) {
                _ = mobs.placeMob(alloc, &mobs.SentinelTemplate, neighbor, .{});
                break;
            }
        }
    }

    // Remove mobs nearby upstairs.
    var dijk = dijkstra.Dijkstra.init(down_staircase, state.mapgeometry, 8, state.is_walkable, .{ .ignore_mobs = true, .right_now = true }, alloc);
    defer dijk.deinit();
    while (dijk.next()) |child| {
        if (state.dungeon.at(child).mob) |mob|
            if (mob.ai.is_combative and mob.isHostileTo(state.player)) {
                mob.deinit();
            };
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
                _setTerrain(coord, cfg.terrain);
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

fn levelFeaturePotions(_: usize, coord: Coord, _: *const Room, _: *const Prefab, _: mem.Allocator) void {
    const potion = rng.chooseUnweighted(Potion, &items.POTIONS);
    state.dungeon.itemsAt(coord).append(Item{ .Potion = potion }) catch err.wat();
}

fn levelFeatureVials(_: usize, coord: Coord, _: *const Room, _: *const Prefab, _: mem.Allocator) void {
    state.dungeon.itemsAt(coord).append(
        Item{ .Vial = rng.choose(Vial, &Vial.VIALS, &Vial.VIAL_COMMONICITY) catch err.wat() },
    ) catch err.wat();
}

fn levelFeatureExperiments(_: usize, coord: Coord, _: *const Room, _: *const Prefab, alloc: mem.Allocator) void {
    const exp_t = rng.chooseUnweighted(mobs.MobTemplate, &mobs.EXPERIMENTS);
    _ = mobs.placeMob(alloc, &exp_t, coord, .{});
}

// Randomly place a vial ore. If the Y coordinate is even, create a container and
// fill it up halfway; otherwise, place only one item on the ground.
fn levelFeatureOres(_: usize, coord: Coord, _: *const Room, _: *const Prefab, _: mem.Allocator) void {
    var using_container: ?*Container = null;

    if ((coord.y % 2) == 0) {
        placeContainer(coord, &surfaces.VOreCrate);
        using_container = state.dungeon.at(coord).surface.?.Container;
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

    connections: ConnectionsBuf = ConnectionsBuf.init(null),

    pub const ConnectionsBuf = StackBuffer(Coord, CONNECTIONS_MAX);

    pub const RoomType = enum { Corridor, Room, Sideroom };

    pub const ArrayList = std.ArrayList(Room);
};

pub const Prefab = struct {
    subroom: bool = false,
    center_align: bool = false,
    invisible: bool = false,
    restriction: usize = 1,
    priority: usize = 0,
    noitems: bool = false,
    noguards: bool = false,
    nolights: bool = false,
    notraps: bool = false,

    name: StackBuffer(u8, MAX_NAME_SIZE) = StackBuffer(u8, MAX_NAME_SIZE).init(null),

    material: ?*const Material = null,

    player_position: ?Coord = null,
    height: usize = 0,
    width: usize = 0,
    content: [40][40]FabTile = undefined,
    connections: [40]?Connection = undefined,
    features: [128]?Feature = [_]?Feature{null} ** 128,
    mobs: [45]?FeatureMob = [_]?FeatureMob{null} ** 45,
    prisons: StackBuffer(Rect, 16) = StackBuffer(Rect, 16).init(null),
    subroom_areas: StackBuffer(Rect, 8) = StackBuffer(Rect, 8).init(null),
    stockpile: ?Rect = null,
    input: ?Rect = null,
    output: ?Rect = null,

    used: [LEVELS]usize = [_]usize{0} ** LEVELS,

    pub const MAX_NAME_SIZE = 64;

    pub const FabTile = union(enum) {
        Window,
        Wall,
        LockedDoor,
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
        Any,
    };

    pub const FeatureMob = struct {
        id: [32:0]u8,
        spawn_at: Coord,
        work_at: ?Coord,
    };

    pub const Feature = union(enum) {
        Machine: struct {
            id: [32:0]u8,
            points: StackBuffer(Coord, 16),
        },
        Prop: [32:0]u8,
        Potion: [32:0]u8,
    };

    pub const Connection = struct {
        c: Coord,
        d: Direction,
        used: bool = false,
    };

    pub fn reset(self: *Prefab, level: usize) void {
        self.used[level] = 0;

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

    fn _finishParsing(
        name: []const u8,
        y: usize,
        w: usize,
        f: *Prefab,
        n_fabs: *PrefabArrayList,
        s_fabs: *PrefabArrayList,
    ) !void {
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

        const to = if (f.subroom) s_fabs else n_fabs;
        to.append(f.*) catch err.oom();
    }

    pub fn parseAndLoad(
        name: []const u8,
        from: []const u8,
        n_fabs: *PrefabArrayList,
        s_fabs: *PrefabArrayList,
    ) !void {
        var f: Prefab = .{};
        for (f.content) |*row| mem.set(FabTile, row, .Wall);
        mem.set(?Connection, &f.connections, null);

        var ci: usize = 0; // index for f.connections
        var cm: usize = 0; // index for f.mobs
        var w: usize = 0;
        var y: usize = 0;

        var lines = mem.tokenize(u8, from, "\n");
        while (lines.next()) |line| {
            switch (line[0]) {
                '%' => {}, // ignore comments
                '\\' => {
                    try _finishParsing(name, y, w, &f, n_fabs, s_fabs);

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
                    mem.set(?Feature, &f.features, null);
                    mem.set(?FeatureMob, &f.mobs, null);
                    f.stockpile = null;
                    f.input = null;
                    f.output = null;
                },
                ':' => {
                    var words = mem.tokenize(u8, line[1..], " ");
                    const key = words.next() orelse return error.MalformedMetadata;
                    const val = words.next() orelse "";

                    if (mem.eql(u8, key, "invisible")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.invisible = true;
                    } else if (mem.eql(u8, key, "subroom")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.subroom = true;
                    } else if (mem.eql(u8, key, "center_align")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.center_align = true;
                    } else if (mem.eql(u8, key, "material")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.material = for (materials.MATERIALS) |mat| {
                            if (mem.eql(u8, val, mat.id orelse mat.name))
                                break mat;
                        } else return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "restriction")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.restriction = std.fmt.parseInt(usize, val, 0) catch return error.InvalidMetadataValue;
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

                        f.subroom_areas.append(.{ .start = rect_start, .width = width, .height = height }) catch return error.TooManySubrooms;
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
                    }
                },
                '@' => {
                    var words = mem.tokenize(u8, line, " ");
                    _ = words.next(); // Skip the '@<ident>' bit

                    const identifier = line[1];
                    const feature_type = words.next() orelse return error.MalformedFeatureDefinition;
                    if (feature_type.len != 1) return error.InvalidFeatureType;
                    const id = words.next() orelse return error.MalformedFeatureDefinition;

                    switch (feature_type[0]) {
                        'P' => {
                            f.features[identifier] = Feature{ .Potion = [_:0]u8{0} ** 32 };
                            mem.copy(u8, &f.features[identifier].?.Potion, id);
                        },
                        'p' => {
                            f.features[identifier] = Feature{ .Prop = [_:0]u8{0} ** 32 };
                            mem.copy(u8, &f.features[identifier].?.Prop, id);
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
                            mem.copy(u8, &f.features[identifier].?.Machine.id, id);
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
                            '?' => .Any,
                            'α'...'δ' => FabTile{ .LevelFeature = @as(usize, c - 'α') },
                            '0'...'9', 'a'...'z' => FabTile{ .Feature = @intCast(u8, c) },
                            'L' => .Loot1,
                            'R' => .RareLoot,
                            else => return error.InvalidFabTile,
                        };
                    }

                    if (x > w) w = x;
                    y += 1;
                },
            }
        }

        try _finishParsing(name, y, w, &f, n_fabs, s_fabs);
    }

    pub fn findPrefabByName(name: []const u8, fabs: *const PrefabArrayList) ?*Prefab {
        for (fabs.items) |*f| if (mem.eql(u8, name, f.name.constSlice())) return f;
        return null;
    }

    pub fn lesserThan(_: void, a: Prefab, b: Prefab) bool {
        //return (a.priority > b.priority) or (a.height * a.width) > (b.height * b.width);
        return a.priority > b.priority;
    }
};

pub const PrefabArrayList = std.ArrayList(Prefab);

// FIXME: error handling
// FIXME: warn if prefab is zerowidth/zeroheight (prefabs file might not have fit in buffer)
pub fn readPrefabs(alloc: mem.Allocator, n_fabs: *PrefabArrayList, s_fabs: *PrefabArrayList) void {
    var buf: [8192]u8 = undefined;

    n_fabs.* = PrefabArrayList.init(alloc);
    s_fabs.* = PrefabArrayList.init(alloc);

    const fabs_dir = std.fs.cwd().openDir("prefabs", .{
        .iterate = true,
    }) catch err.wat();

    var fabs_dir_iterator = fabs_dir.iterate();
    while (fabs_dir_iterator.next() catch err.wat()) |fab_file| {
        if (fab_file.kind != .File) continue;

        var fab_f = fabs_dir.openFile(fab_file.name, .{
            .read = true,
            .lock = .None,
        }) catch err.wat();
        defer fab_f.close();

        const read = fab_f.readAll(buf[0..]) catch err.wat();

        Prefab.parseAndLoad(fab_file.name, buf[0..read], n_fabs, s_fabs) catch |e| {
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
                error.MalformedMetadata => "Malformed metadata",
                error.InvalidMetadataValue => "Invalid value for metadata",
                error.UnexpectedMetadataValue => "Unexpected value for metadata",
                error.ExpectedMetadataValue => "Expected value for metadata",
                error.InvalidUtf8 => "Encountered invalid UTF-8",
            };
            std.log.info("{s}: Couldn't load prefab: {s}", .{ fab_file.name, msg });
            continue;
        };
    }

    rng.shuffle(Prefab, s_fabs.items);
    std.sort.insertionSort(Prefab, s_fabs.items, {}, Prefab.lesserThan);
}

pub var mob_spawn_tables: std.StringHashMap([LEVELS]usize) = undefined;

pub fn readSpawnTables(alloc: mem.Allocator) void {
    const _MobSpawnData = struct {
        id: []u8 = undefined,

        _8_pri_: usize = undefined,
        _7_pri_: usize = undefined,
        _6_lab_: usize = undefined,
        _6_lab2: usize = undefined,
        _6_lab3: usize = undefined,
        _5_smi_: usize = undefined,
        _5_smi2: usize = undefined,
        _5_smi3: usize = undefined,
        _4_pri_: usize = undefined,
        _3_vlt_: usize = undefined,
        _3_vlt2: usize = undefined,
        _3_vlt3: usize = undefined,
        _2_pri_: usize = undefined,
        _1_pri_: usize = undefined,
    };

    mob_spawn_tables = @TypeOf(mob_spawn_tables).init(alloc);

    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("spawns.tsv", .{
        .read = true,
        .lock = .None,
    }) catch unreachable;

    var rbuf: [65535]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        _MobSpawnData,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "id", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "_8_pri_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_7_pri_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_6_lab_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_6_lab2", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_6_lab3", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_5_smi_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_5_smi2", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_5_smi3", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_4_pri_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_3_vlt_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_3_vlt2", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_3_vlt3", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_2_pri_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
            .{ .field_name = "_1_pri_", .parse_to = usize, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = 0 },
        },
        .{},
        rbuf[0..read],
        alloc,
    );

    if (!result.is_ok()) {
        err.bug(
            "Cannot read spawn table: {} (line {}, field {})",
            .{ result.Err.type, result.Err.context.lineno, result.Err.context.field },
        );
    } else {
        const spawndatas = result.unwrap();
        defer spawndatas.deinit();

        for (spawndatas.items) |spawndata| {
            var weights = [LEVELS]usize{
                spawndata._1_pri_,
                spawndata._2_pri_,
                spawndata._3_vlt3,
                spawndata._3_vlt2,
                spawndata._3_vlt_,
                spawndata._4_pri_,
                spawndata._5_smi3,
                spawndata._5_smi2,
                spawndata._5_smi_,
                spawndata._6_lab3,
                spawndata._6_lab2,
                spawndata._6_lab_,
                spawndata._7_pri_,
                spawndata._8_pri_,
            };
            mob_spawn_tables.putNoClobber(spawndata.id, weights) catch err.oom();
        }

        std.log.info("Loaded spawn tables.", .{});
    }
}

pub fn freeSpawnTables(alloc: mem.Allocator) void {
    var iter = mob_spawn_tables.iterator();
    while (iter.next()) |entry| alloc.free(entry.key_ptr.*);
    mob_spawn_tables.clearAndFree();
}

pub const LevelConfig = struct {
    stairs_to: []const usize = &[_]usize{},

    prefabs: []const []const u8 = .{},
    distances: [2][10]usize = [2][10]usize{
        .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
    },
    shrink_corridors_to_fit: bool = true,
    prefab_chance: usize,

    mapgen_func: fn (*PrefabArrayList, *PrefabArrayList, usize, mem.Allocator) void = placeRandomRooms,

    // If true, will not place rooms on top of lava/water.
    require_dry_rooms: bool = false,

    // Determines the number of iterations used by the mapgen algorithm.
    //
    // On placeRandomRooms: try mapgen_iters times to place a rooms randomly.
    // On placeBSPRooms:    try mapgen_iters times to split a BSP node.
    mapgen_iters: usize,

    // Dimensions include the first wall, so a minimum width of 2 guarantee that
    // there will be one empty space in the room, minimum.
    min_room_width: usize = 7,
    min_room_height: usize = 4,
    max_room_width: usize = 15,
    max_room_height: usize = 11,

    level_features: [4]?LevelFeatureFunc = [_]?LevelFeatureFunc{ null, null, null, null },

    required_mobs: []const RequiredMob = &[_]RequiredMob{
        .{ .count = 3, .template = &mobs.CleanerTemplate },
        .{ .count = 3, .template = &mobs.EngineerTemplate },
    },
    room_crowd_max: usize = 2,
    level_crowd_max: ?usize = null,

    no_lights: bool = false,
    no_windows: bool = false,
    tiletype: TileType = .Wall,
    material: *const Material = &materials.Concrete,
    window_material: *const Material = &materials.Glass,
    light: *const Machine = &surfaces.Brazier,
    door: *const Machine = &surfaces.NormalDoor,
    vent: []const u8 = "gas_vent",
    bars: []const u8 = "iron_bars",
    machines: []const *const Machine = null,
    props: *[]const Prop = &surfaces.statue_props.items,
    // Props that can be placed in bulk along a single wall.
    single_props: []const []const u8 = &[_][]const u8{},
    chance_for_single_prop_placement: usize = 33, // percentage
    containers: []const Container = &[_]Container{
        surfaces.Bin,
        surfaces.Barrel,
        surfaces.Cabinet,
        //surfaces.Chest,
    },
    utility_items: *[]const Prop = &surfaces.prison_item_props.items,
    allow_statues: bool = true,
    door_chance: usize = 30,
    room_trapped_chance: usize = 40,
    subroom_chance: usize = 60,
    allow_corridors: bool = true,

    blobs: []const BlobConfig = &[_]BlobConfig{},

    pub const LevelFeatureFunc = fn (usize, Coord, *const Room, *const Prefab, mem.Allocator) void;

    pub const RequiredMob = struct { count: usize, template: *const mobs.MobTemplate };

    pub const MobConfig = struct {
        chance: usize, // Ten in <chance>
        template: *const mobs.MobTemplate,
    };
};

// -----------------------------------------------------------------------------

pub const PRI_BASE_LEVELCONFIG = LevelConfig{
    .prefabs = &[_][]const u8{"ANY_s_recharging"},
    .distances = [2][10]usize{
        .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .{ 5, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
    },
    .prefab_chance = 2,
    .mapgen_iters = 1024,
    .level_features = [_]?LevelConfig.LevelFeatureFunc{
        levelFeaturePrisoners,
        levelFeaturePrisonersMaybe,
        null,
        null,
    },

    .machines = &[_]*const Machine{ &surfaces.Fountain, &surfaces.Drain },
    .single_props = &[_][]const u8{ "wood_table", "wood_chair" },
};

pub const QRT_BASE_LEVELCONFIG = LevelConfig{
    .prefabs = &[_][]const u8{"ANY_s_recharging"},
    .prefab_chance = 1000, // No prefabs for QRT
    .mapgen_func = placeBSPRooms,
    .mapgen_iters = 1024,
    .min_room_width = 8,
    .min_room_height = 5,
    .max_room_width = 10,
    .max_room_height = 6,

    .no_windows = true,
    .allow_statues = false,
    .door_chance = 10,
    .door = &surfaces.VaultDoor,

    .props = &surfaces.vault_props.items,
    //.containers = &[_]Container{surfaces.Chest},
    .single_props = &[_][]const u8{"fuel_barrel"},
    .chance_for_single_prop_placement = 90,

    .machines = &[_]*const Machine{&surfaces.Fountain},
};

pub const LAB_BASE_LEVELCONFIG = LevelConfig{
    .prefabs = &[_][]const u8{"ANY_s_recharging"},
    .distances = [2][10]usize{
        .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .{ 9, 3, 2, 1, 1, 1, 0, 0, 0, 0 },
    },
    .shrink_corridors_to_fit = true,
    .prefab_chance = 100, // No prefabs for LAB
    .mapgen_iters = 4096,
    .min_room_width = 9,
    .min_room_height = 7,
    .max_room_width = 25,
    .max_room_height = 20,

    .level_features = [_]?LevelConfig.LevelFeatureFunc{
        levelFeatureVials,
        levelFeaturePrisoners,
        levelFeatureExperiments,
        levelFeatureOres,
    },

    .door_chance = 10,
    .material = &materials.Dobalene,
    .window_material = &materials.LabGlass,
    .light = &surfaces.Lamp,
    .bars = "titanium_bars",
    .door = &surfaces.LabDoor,
    .props = &surfaces.laboratory_props.items,
    //.containers = &[_]Container{ surfaces.Chest, surfaces.LabCabinet },
    .containers = &[_]Container{surfaces.LabCabinet},
    .utility_items = &surfaces.laboratory_item_props.items,
    .single_props = &[_][]const u8{"table"},

    .allow_statues = false,

    .machines = &[_]*const Machine{&surfaces.Fountain},
};

pub const CAV_BASE_LEVELCONFIG = LevelConfig{
    .prefabs = &[_][]const u8{},
    .distances = [2][10]usize{
        .{ 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 },
        .{ 1, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
    },
    .shrink_corridors_to_fit = true,
    .prefab_chance = 3,
    .mapgen_iters = 4096,

    .min_room_width = 3,
    .min_room_height = 3,
    .max_room_width = 5,
    .max_room_height = 4,

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
    .tiletype = .Floor,

    .allow_statues = false,
    .door_chance = 10,
    .room_trapped_chance = 0,
    .subroom_chance = 60,
    .allow_corridors = false,
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
            .number = MinMax(usize){ .min = 5, .max = 6 },
            .type = .Lava,
            .min_blob_width = minmax(usize, 2, 9),
            .min_blob_height = minmax(usize, 2, 9),
            .max_blob_width = minmax(usize, 9, 15),
            .max_blob_height = minmax(usize, 9, 15),
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

pub var Configs = [LEVELS]LevelConfig{
    PRI_BASE_LEVELCONFIG,
    PRI_BASE_LEVELCONFIG,
    QRT_BASE_LEVELCONFIG,
    QRT_BASE_LEVELCONFIG,
    QRT_BASE_LEVELCONFIG,
    PRI_BASE_LEVELCONFIG,
    CAV_BASE_LEVELCONFIG,
    CAV_BASE_LEVELCONFIG,
    CAV_BASE_LEVELCONFIG,
    LAB_BASE_LEVELCONFIG,
    LAB_BASE_LEVELCONFIG,
    LAB_BASE_LEVELCONFIG,
    PRI_BASE_LEVELCONFIG,
    PRI_BASE_LEVELCONFIG,
};

// TODO: convert this to a comptime expression
// zig fmt: off
pub fn fixConfigs() void {
    Configs[0].prefabs = &[_][]const u8{ "ENT_start", "ANY_s_recharging" };
    Configs[state.PLAYER_STARTING_LEVEL].prefabs = &[_][]const u8{ "PRI_start", "ANY_s_recharging" };

    // Be careful when editing this
    Configs[00].stairs_to = &[_]usize{};      // -1/Prison       -> nothing
    Configs[01].stairs_to = &[_]usize{    0}; // -2/Prison       -> -1/Prison
    Configs[02].stairs_to = &[_]usize{    1}; // -3/Quarters/3   -> -2/Prison
    Configs[03].stairs_to = &[_]usize{1,  2}; // -3/Quarters/2   -> -3/Quarters/3,   -2/Prison
    Configs[04].stairs_to = &[_]usize{1,  3}; // -3/Quarters     -> -3/Quarters/2,   -2/Prison
    Configs[05].stairs_to = &[_]usize{    4}; // -4/Prison       -> -3/Quarters
    Configs[06].stairs_to = &[_]usize{    5}; // -5/Caverns/3    -> -4/Prison
    Configs[07].stairs_to = &[_]usize{5,  6}; // -5/Caverns/2    -> -5/Caverns/3,    -4/Prison
    Configs[08].stairs_to = &[_]usize{5,  7}; // -5/Caverns      -> -5/Caverns/2,    -4/Prison
    Configs[09].stairs_to = &[_]usize{    8}; // -6/Laboratory/3 -> -5/Caverns
    Configs[10].stairs_to = &[_]usize{8,  9}; // -6/Laboratory/2 -> -6/Laboratory/3, -5/Caverns
    Configs[11].stairs_to = &[_]usize{8, 10}; // -6/Laboratory   -> -6/Laboratory/2, -5/Caverns
    Configs[12].stairs_to = &[_]usize{   11}; // -7/Prison       -> -6/Laboratory
    Configs[13].stairs_to = &[_]usize{   12}; // -8/Prison       -> -7/Prison


    // Increase crowd sizes for difficult levels.
    Configs[ 0].room_crowd_max = 4;      Configs[ 1].room_crowd_max = 3;   // Upper prison
    Configs[ 2].room_crowd_max = 2;      Configs[ 3].room_crowd_max = 1;   // Quarters
    Configs[ 6].room_crowd_max = 6;      Configs[ 7].room_crowd_max = 5;   // Caverns
    Configs[ 9].room_crowd_max = 4;      Configs[10].room_crowd_max = 3;   // Laboratory

    Configs[ 6].level_crowd_max = 50;    Configs[ 7].level_crowd_max = 50; // Caverns
}
// zig fmt: on
