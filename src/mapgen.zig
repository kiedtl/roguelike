const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const astar = @import("astar.zig");
const rng = @import("rng.zig");
const mobs = @import("mobs.zig");
const StackBuffer = @import("buffer.zig").StackBuffer;
const items = @import("items.zig");
const machines = @import("machines.zig");
const literature = @import("literature.zig");
const materials = @import("materials.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

const Poster = literature.Poster;

const LIMIT = Room{
    .start = Coord.new(1, 1),
    .width = state.WIDTH - 1,
    .height = state.HEIGHT - 1,
};

const Corridor = struct {
    room: Room,
    parent_connector: ?Coord,
    child_connector: ?Coord,
    distance: usize,
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
    return state.dungeon.at(coord).type == .Floor and
        state.dungeon.at(coord).mob == null and
        state.dungeon.at(coord).surface == null and
        state.dungeon.itemsAt(coord).len == 0;
}

fn choosePoster(level: usize) ?*const Poster {
    var tries: usize = 256;
    while (tries > 0) : (tries -= 1) {
        const p = &state.posters.items[rng.range(usize, 0, state.posters.items.len - 1)];
        if (p.placement_counter > 0 or !mem.eql(u8, Configs[level].identifier, p.level))
            continue;
        p.placement_counter += 1;
        return p;
    }

    return null;
}

const PlaceMobOptions = struct {
    facing: ?Direction = null,
    phase: AIPhase = .Work,
    work_area: ?Coord = null,
};

fn placeMob(
    alloc: *mem.Allocator,
    template: *const mobs.MobTemplate,
    coord: Coord,
    opts: PlaceMobOptions,
) *Mob {
    var mob = template.mob;
    mob.init(alloc);
    mob.coord = coord;
    mob.ai.phase = opts.phase;

    if (template.weapon) |w| mob.inventory.wielded = _createItem(Weapon, w.*);
    if (template.backup_weapon) |w| mob.inventory.backup = _createItem(Weapon, w.*);
    if (template.armor) |a| mob.inventory.armor = _createItem(Armor, a.*);

    if (opts.facing) |dir| mob.facing = dir;
    mob.ai.work_area.append(opts.work_area orelse coord) catch unreachable;

    for (template.statuses) |status_info| {
        mob.addStatus(status_info.status, status_info.power, status_info.duration, status_info.permanent);
    }

    state.mobs.append(mob) catch unreachable;
    const ptr = state.mobs.lastPtr().?;
    state.dungeon.at(coord).mob = ptr;
    return ptr;
}

fn randomWallCoord(room: *const Room, i: ?usize) Coord {
    const Range = struct { from: Coord, to: Coord };
    const room_end = room.end();

    const ranges = [_]Range{
        .{ .from = Coord.new(room.start.x + 1, room.start.y - 1), .to = Coord.new(room_end.x - 2, room.start.y - 1) }, // top
        .{ .from = Coord.new(room.start.x + 1, room_end.y), .to = Coord.new(room_end.x - 2, room_end.y) }, // bottom
        .{ .from = Coord.new(room.start.x, room.start.y + 1), .to = Coord.new(room.start.x, room_end.y - 2) }, // left
        .{ .from = Coord.new(room_end.x, room.start.y + 1), .to = Coord.new(room_end.x, room_end.y - 2) }, // left
    };

    const range = if (i) |_i| ranges[(_i + 1) % ranges.len] else rng.chooseUnweighted(Range, &ranges);
    const x = rng.rangeClumping(usize, range.from.x, range.to.x, 2);
    const y = rng.rangeClumping(usize, range.from.y, range.to.y, 2);
    return Coord.new2(room.start.z, x, y);
}

fn _createItem(comptime T: type, item: T) *T {
    comptime const list = switch (T) {
        Potion => &state.potions,
        Ring => &state.rings,
        Armor => &state.armors,
        Weapon => &state.weapons,
        Projectile => &state.projectiles,
        else => @compileError("uh wat"),
    };
    list.append(item) catch @panic("OOM");
    return list.lastPtr().?;
}

fn _place_prop(coord: Coord, prop_template: *const Prop) *Prop {
    var prop = prop_template.*;
    prop.coord = coord;
    state.props.append(prop) catch unreachable;
    const propptr = state.props.lastPtr().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Prop = propptr };
    return state.props.lastPtr().?;
}

fn placeContainer(coord: Coord, template: *const Container) void {
    var container = template.*;
    container.coord = coord;
    state.containers.append(container) catch unreachable;
    const ptr = state.containers.lastPtr().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Container = ptr };
}

fn _place_machine(coord: Coord, machine_template: *const Machine) void {
    var machine = machine_template.*;
    machine.coord = coord;
    state.machines.append(machine) catch unreachable;
    const machineptr = state.machines.lastPtr().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = machineptr };
}

fn placeDoor(coord: Coord, locked: bool) void {
    var door = if (locked) machines.LockedDoor else machines.NormalDoor;
    door.coord = coord;
    state.machines.append(door) catch unreachable;
    const doorptr = state.machines.lastPtr().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = doorptr };
    state.dungeon.at(coord).type = .Floor;
}

fn _add_player(coord: Coord, alloc: *mem.Allocator) void {
    const echoring = _createItem(Ring, items.EcholocationRing);
    echoring.worn_since = state.ticks;

    state.player = placeMob(alloc, &mobs.PlayerTemplate, coord, .{ .phase = .Hunt });
    state.player.inventory.r_rings[0] = echoring;
    state.player.prisoner_status = Prisoner{ .of = .Sauron };
}

fn prefabIsValid(level: usize, prefab: *Prefab) bool {
    if (prefab.invisible)
        return false; // Can't be used unless specifically called for by name.

    if (!mem.eql(u8, prefab.name.constSlice()[0..3], Configs[level].identifier))
        return false; // Prefab isn't for this level.

    if (prefab.used[level] >= prefab.restriction)
        return false; // Prefab was used too many times.

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

fn attachRoom(parent: *const Room, d: Direction, width: usize, height: usize, distance: usize, fab: ?*const Prefab) ?Room {
    // "Preferred" X/Y coordinates to start the child at. preferred_x is only
    // valid if d == .North or d == .South, and preferred_y is only valid if
    // d == .West or d == .East.
    var preferred_x = parent.start.x + (parent.width / 2);
    var preferred_y = parent.start.y + (parent.height / 2);

    // Note: the coordinate returned by Prefab.connectorFor() is relative.

    if (parent.prefab != null and fab != null) {
        const parent_con = parent.prefab.?.connectorFor(d) orelse return null;
        const child_con = fab.?.connectorFor(d.opposite()) orelse return null;
        const parent_con_abs = Coord.new2(
            parent.start.z,
            parent.start.x + parent_con.x,
            parent.start.y + parent_con.y,
        );
        preferred_x = utils.saturating_sub(parent_con_abs.x, child_con.x);
        preferred_y = utils.saturating_sub(parent_con_abs.y, child_con.y);
    } else if (parent.prefab) |pafab| {
        const con = pafab.connectorFor(d) orelse return null;
        preferred_x = parent.start.x + con.x;
        preferred_y = parent.start.y + con.y;
    } else if (fab) |chfab| {
        const con = chfab.connectorFor(d.opposite()) orelse return null;
        preferred_x = utils.saturating_sub(parent.start.x, con.x);
        preferred_y = utils.saturating_sub(parent.start.y, con.y);
    }

    return switch (d) {
        .North => Room{
            .start = Coord.new2(parent.start.z, preferred_x, utils.saturating_sub(parent.start.y, height + distance)),
            .height = height,
            .width = width,
        },
        .East => Room{
            .start = Coord.new2(parent.start.z, parent.end().x + distance, preferred_y),
            .height = height,
            .width = width,
        },
        .South => Room{
            .start = Coord.new2(parent.start.z, preferred_x, parent.end().y + distance),
            .height = height,
            .width = width,
        },
        .West => Room{
            .start = Coord.new2(parent.start.z, utils.saturating_sub(parent.start.x, width + distance), preferred_y),
            .width = width,
            .height = height,
        },
        else => @panic("unimplemented"),
    };
}

fn findIntersectingRoom(
    rooms: *const RoomArrayList,
    room: *const Room,
    ignore: ?*const Room,
    ignore2: ?*const Room,
    ignore_corridors: bool,
) ?usize {
    for (rooms.items) |other, i| {
        if (ignore) |ign| {
            if (other.start.eq(ign.start))
                if (other.width == ign.width and other.height == ign.height)
                    continue;
        }

        if (ignore2) |ign| {
            if (other.start.eq(ign.start))
                if (other.width == ign.width and other.height == ign.height)
                    continue;
        }

        if (other.type == .Corridor and ignore_corridors) {
            continue;
        }

        if (room.intersects(&other, 1)) return i;
    }

    return null;
}

fn roomIntersects(
    rooms: *const RoomArrayList,
    room: *const Room,
    ignore: ?*const Room,
    ignore2: ?*const Room,
    ign_c: bool,
) bool {
    return if (findIntersectingRoom(rooms, room, ignore, ignore2, ign_c)) |r| true else false;
}

fn _excavate_prefab(
    room: *const Room,
    fab: *const Prefab,
    allocator: *mem.Allocator,
    startx: usize,
    starty: usize,
) void {
    var y: usize = 0;
    while (y < fab.height) : (y += 1) {
        var x: usize = 0;
        while (x < fab.width) : (x += 1) {
            const rc = Coord.new2(
                room.start.z,
                x + room.start.x + startx,
                y + room.start.y + starty,
            );
            assert(rc.x < WIDTH);
            assert(rc.y < HEIGHT);

            const tt: ?TileType = switch (fab.content[y][x]) {
                .Any, .Connection => null,
                .Wall => .Wall,
                .LevelFeature,
                .Feature,
                .LockedDoor,
                .Door,
                .Bars,
                .Brazier,
                .Floor,
                => .Floor,
                .Water => .Water,
                .Lava => .Lava,
            };
            if (tt) |_tt| state.dungeon.at(rc).type = _tt;

            switch (fab.content[y][x]) {
                .LevelFeature => |l| (Configs[room.start.z].level_features[l].?)(l, rc, room, fab, allocator),
                .Feature => |feature_id| {
                    if (fab.features[feature_id]) |feature| {
                        switch (feature) {
                            .Potion => |pid| {
                                if (utils.findById(&items.POTIONS, pid)) |potion_i| {
                                    const potion_o = _createItem(Potion, items.POTIONS[potion_i]);
                                    state.dungeon.itemsAt(rc).append(Item{ .Potion = potion_o }) catch unreachable;
                                } else {
                                    std.log.warn(
                                        "{}: Couldn't load potion {}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(pid) },
                                    );
                                }
                            },
                            .Prop => |pid| {
                                if (utils.findById(&machines.PROPS, pid)) |prop| {
                                    _ = _place_prop(rc, &machines.PROPS[prop]);
                                } else {
                                    std.log.warn(
                                        "{}: Couldn't load prop {}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(pid) },
                                    );
                                }
                            },
                            .Machine => |mid| {
                                if (utils.findById(&machines.MACHINES, mid)) |mach| {
                                    _place_machine(rc, &machines.MACHINES[mach]);
                                } else {
                                    std.log.warn(
                                        "{}: Couldn't load machine {}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(mid) },
                                    );
                                }
                            },
                        }
                    } else {
                        std.log.warn(
                            "{}: Feature '{c}' not present, skipping.",
                            .{ fab.name.constSlice(), feature_id },
                        );
                    }
                },
                .LockedDoor => placeDoor(rc, true),
                .Door => placeDoor(rc, false),
                .Brazier => _place_machine(rc, Configs[room.start.z].light),
                .Bars => _ = _place_prop(rc, Configs[room.start.z].bars),
                else => {},
            }
        }
    }

    for (fab.mobs) |maybe_mob| {
        if (maybe_mob) |mob_f| {
            if (utils.findById(&mobs.MOBS, mob_f.id)) |mob_template| {
                const coord = Coord.new2(
                    room.start.z,
                    mob_f.spawn_at.x + room.start.x + startx,
                    mob_f.spawn_at.y + room.start.y + starty,
                );
                const work_area = Coord.new2(
                    room.start.z,
                    (mob_f.work_at orelse mob_f.spawn_at).x + room.start.x + startx,
                    (mob_f.work_at orelse mob_f.spawn_at).y + room.start.y + starty,
                );

                _ = placeMob(allocator, &mobs.MOBS[mob_template], coord, .{
                    .work_area = work_area,
                });
            } else {
                std.log.warn(
                    "{}: Couldn't load mob {}, skipping.",
                    .{ fab.name.constSlice(), utils.used(mob_f.id) },
                );
            }
        }
    }

    for (fab.prisons.constSlice()) |prison_area| {
        const prison_start = Coord.new2(
            room.start.z,
            prison_area.start.x + room.start.x + startx,
            prison_area.start.y + room.start.y + starty,
        );
        const prison_end = Coord.new2(
            room.start.z,
            prison_area.end().x + room.start.x + startx,
            prison_area.end().y + room.start.y + starty,
        );

        var p_y: usize = prison_start.y;
        while (p_y < prison_end.y) : (p_y += 1) {
            var p_x: usize = prison_start.x;
            while (p_x < prison_end.x) : (p_x += 1) {
                state.dungeon.at(Coord.new2(room.start.z, p_x, p_y)).prison = true;
            }
        }
    }

    if (fab.stockpile) |stockpile| {
        const room_start = Coord.new2(
            room.start.z,
            stockpile.start.x + room.start.x + startx,
            stockpile.start.y + room.start.y + starty,
        );
        var stckpl = Stockpile{
            .room = Room{
                .start = room_start,
                .width = stockpile.width,
                .height = stockpile.height,
            },
            .type = undefined,
        };
        const inferred = stckpl.inferType();
        if (!inferred) {
            std.log.err("{}: Couldn't infer type for stockpile! (skipping)", .{fab.name.constSlice()});
        } else {
            state.stockpiles[room.start.z].append(stckpl) catch unreachable;
        }
    }

    if (fab.output) |output| {
        const room_start = Coord.new2(
            room.start.z,
            output.start.x + room.start.x + startx,
            output.start.y + room.start.y + starty,
        );
        state.outputs[room.start.z].append(Room{
            .start = room_start,
            .width = output.width,
            .height = output.height,
        }) catch unreachable;
    }

    if (fab.input) |input| {
        const room_start = Coord.new2(
            room.start.z,
            input.start.x + room.start.x + startx,
            input.start.y + room.start.y + starty,
        );
        var input_stckpl = Stockpile{
            .room = Room{
                .start = room_start,
                .width = input.width,
                .height = input.height,
            },
            .type = undefined,
        };
        const inferred = input_stckpl.inferType();
        if (!inferred) {
            std.log.err("{}: Couldn't infer type for input area! (skipping)", .{fab.name.constSlice()});
        } else {
            state.inputs[room.start.z].append(input_stckpl) catch unreachable;
        }
    }
}

fn _excavate_room(room: *const Room) void {
    var y = room.start.y;
    while (y < room.end().y) : (y += 1) {
        var x = room.start.x;
        while (x < room.end().x) : (x += 1) {
            const c = Coord.new2(room.start.z, x, y);
            assert(c.x < WIDTH and c.y < HEIGHT);
            state.dungeon.at(c).type = .Floor;
        }
    }
}

// Destroy items, machines, and mobs associated with level and reset level's
// terrain.
pub fn resetLevel(level: usize) void {
    var mobiter = state.mobs.iterator();
    while (mobiter.nextNode()) |node| {
        if (node.data.coord.z == level) {
            node.data.kill();
            state.mobs.remove(node);
        }
    }

    var machiter = state.machines.iterator();
    while (machiter.nextNode()) |node| {
        if (node.data.coord.z == level) {
            state.machines.remove(node);
        }
    }

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);

            const tile = state.dungeon.at(coord);
            tile.prison = false;
            tile.marked = false;
            tile.type = .Wall;
            tile.material = &materials.Basalt;
            tile.mob = null;
            tile.surface = null;
            tile.spatter = SpatterArray.initFill(0);

            state.dungeon.itemsAt(coord).clear();
        }
    }

    state.dungeon.rooms[level].shrinkRetainingCapacity(0);
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
            if (state.dungeon.neighboringWalls(coord, true) < 9)
                state.dungeon.at(coord).material = Configs[level].material;
        }
    }
}

pub fn validateLevel(level: usize, alloc: *mem.Allocator) bool {
    // utility functions
    const _f = struct {
        pub fn _getWalkablePoint(room: *const Room) Coord {
            var point: Coord = room.start;
            var tries: usize = 100;
            while (tries > 0) : (tries -= 1) {
                if (state.dungeon.at(point).type == .Floor)
                    return point;
                point = room.randomCoord();
            }
            unreachable;
        }

        pub fn _isWalkable(coord: Coord, opts: state.IsWalkableOptions) bool {
            return state.dungeon.at(coord).type != .Wall;
        }
    };

    const rooms = state.dungeon.rooms[level].items;
    const base_room = rng.chooseUnweighted(Room, rooms); // FIXME: ensure is not corridor
    const point = _f._getWalkablePoint(&base_room);

    for (rooms) |otherroom| {
        if (otherroom.type == .Corridor) continue;
        if (otherroom.start.eq(base_room.start)) continue;

        const otherpoint = _f._getWalkablePoint(&otherroom);

        if (astar.path(point, otherpoint, state.mapgeometry, _f._isWalkable, .{}, alloc)) |p| {
            p.deinit();
        } else {
            return false;
        }
    }

    return true;
}

pub fn placeMoarCorridors(level: usize) void {
    const rooms = &state.dungeon.rooms[level];

    var i: usize = 0;
    while (i < rooms.items.len) : (i += 1) {
        const parent = &rooms.items[i];

        if (parent.type == .Corridor) continue;

        for (rooms.items) |*child| {
            if (child.type == .Corridor) continue;

            // Skip child prefabs for now, placeCorridor seems to be broken
            if (child.prefab != null) continue;

            if (parent.intersects(child, 1)) {
                continue;
            }

            if (parent.start.eq(child.start)) {
                // skip ourselves
                continue;
            }

            const x_overlap = math.max(parent.start.x, child.start.x) <
                math.min(parent.end().x, child.end().x);
            const y_overlap = math.max(parent.start.y, child.start.y) <
                math.min(parent.end().y, child.end().y);

            // FIXME: assert that x_overlap or y_overlap, but not both

            if (!x_overlap and !y_overlap) {
                continue;
            }

            var side: Direction = undefined;
            if (x_overlap) {
                side = if (parent.start.y > child.start.y) .North else .South;
            } else if (y_overlap) {
                side = if (parent.start.x > child.start.x) .West else .East;
            }

            if (_createCorridor(level, parent, child, side)) |corridor| {
                if (corridor.distance == 0 or corridor.distance > 4) {
                    continue;
                }

                if (roomIntersects(rooms, &corridor.room, parent, child, false)) {
                    continue;
                }

                _excavate_room(&corridor.room);
                rooms.append(corridor.room) catch unreachable;

                // When using a prefab, the corridor doesn't include the connectors. Excavate
                // the connectors (both the beginning and the end) manually.
                if (corridor.parent_connector) |acon| state.dungeon.at(acon).type = .Floor;
                if (corridor.child_connector) |acon| state.dungeon.at(acon).type = .Floor;

                if (corridor.distance == 1) placeDoor(corridor.room.start, false);

                // Restart loop, as the slice pointer might have been modified if a
                // reallocation took place
                break;
            }
        }
    }
}

fn _createCorridor(level: usize, parent: *Room, child: *Room, side: Direction) ?Corridor {
    var corridor_coord = Coord.new2(level, 0, 0);
    var parent_connector_coord: ?Coord = null;
    var child_connector_coord: ?Coord = null;

    if (parent.prefab != null or child.prefab != null) {
        if (parent.prefab) |f| {
            const con = f.connectorFor(side) orelse return null;
            corridor_coord.x = parent.start.x + con.x;
            corridor_coord.y = parent.start.y + con.y;
            parent_connector_coord = corridor_coord;
            f.useConnector(con) catch unreachable;
        }
        if (child.prefab) |f| {
            const con = f.connectorFor(side.opposite()) orelse return null;
            corridor_coord.x = child.start.x + con.x;
            corridor_coord.y = child.start.y + con.y;
            child_connector_coord = corridor_coord;
            f.useConnector(con) catch unreachable;
        }
    } else {
        const rsx = math.max(parent.start.x, child.start.x);
        const rex = math.min(parent.end().x, child.end().x);
        const rsy = math.max(parent.start.y, child.start.y);
        const rey = math.min(parent.end().y, child.end().y);
        corridor_coord.x = rng.range(usize, math.min(rsx, rex), math.max(rsx, rex) - 1);
        corridor_coord.y = rng.range(usize, math.min(rsy, rey), math.max(rsy, rey) - 1);
    }

    var room = switch (side) {
        .North => Room{
            .start = Coord.new2(level, corridor_coord.x, child.end().y),
            .height = parent.start.y - child.end().y,
            .width = 1,
        },
        .South => Room{
            .start = Coord.new2(level, corridor_coord.x, parent.end().y),
            .height = child.start.y - parent.end().y,
            .width = 1,
        },
        .West => Room{
            .start = Coord.new2(level, child.end().x, corridor_coord.y),
            .height = 1,
            .width = parent.start.x - child.end().x,
        },
        .East => Room{
            .start = Coord.new2(level, parent.end().x, corridor_coord.y),
            .height = 1,
            .width = child.start.x - parent.end().x,
        },
        else => unreachable,
    };

    room.type = .Corridor;

    return Corridor{
        .room = room,
        .parent_connector = parent_connector_coord,
        .child_connector = child_connector_coord,
        .distance = switch (side) {
            .North, .South => room.height,
            .West, .East => room.width,
            else => unreachable,
        },
    };
}

fn placeSubroom(s_fabs: *PrefabArrayList, parent: *Room, area: *const Room, alloc: *mem.Allocator) void {
    for (s_fabs.items) |*subroom| {
        if (!prefabIsValid(parent.start.z, subroom))
            continue;

        if ((subroom.height + 2) < area.height and (subroom.width + 2) < area.width) {
            const rx = (area.width / 2) - (subroom.width / 2);
            const ry = (area.height / 2) - (subroom.height / 2);
            _excavate_prefab(&parent.add(area), subroom, alloc, rx, ry);
            subroom.used[parent.start.z] += 1;
            parent.has_subroom = true;
            break;
        }
    }
}

fn _place_rooms(
    rooms: *RoomArrayList,
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: *mem.Allocator,
) void {
    //const parent = &rooms.items[rng.range(usize, 0, rooms.items.len - 1)];
    var _parent = rng.chooseUnweighted(Room, rooms.items);
    const parent = &_parent;

    var fab: ?*Prefab = null;
    var distance = rng.choose(
        usize,
        &Configs[level].distances[0],
        &Configs[level].distances[1],
    ) catch unreachable;
    var child: Room = undefined;
    var side = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);

    if (rng.onein(Configs[level].prefab_chance)) {
        if (distance == 0) distance += 1;

        fab = choosePrefab(level, n_fabs) orelse return;
        child = attachRoom(parent, side, fab.?.width, fab.?.height, distance, fab) orelse return;
        child.prefab = fab;

        if (roomIntersects(rooms, &child, parent, null, false) or child.overflowsLimit(&LIMIT))
            return;
    } else {
        if (parent.prefab != null and distance == 0) distance += 1;

        var child_w = rng.rangeClumping(usize, Configs[level].min_room_width, Configs[level].max_room_width, 2);
        var child_h = rng.rangeClumping(usize, Configs[level].min_room_height, Configs[level].max_room_height, 2);
        child = attachRoom(parent, side, child_w, child_h, distance, null) orelse return;

        while (roomIntersects(rooms, &child, parent, null, true) or child.overflowsLimit(&LIMIT)) {
            if (child_w < Configs[level].min_room_width or
                child_h < Configs[level].min_room_height)
                return;

            child_w -= 1;
            child_h -= 1;
            child = attachRoom(parent, side, child_w, child_h, distance, null).?;
        }
    }

    if (distance > 0) {
        if (_createCorridor(level, parent, &child, side)) |corridor| {
            if (roomIntersects(rooms, &corridor.room, parent, null, true)) {
                return;
            }

            _excavate_room(&corridor.room);
            rooms.append(corridor.room) catch unreachable;

            // When using a prefab, the corridor doesn't include the connectors. Excavate
            // the connectors (both the beginning and the end) manually.

            if (corridor.parent_connector) |acon| state.dungeon.at(acon).type = .Floor;
            if (corridor.child_connector) |acon| state.dungeon.at(acon).type = .Floor;

            if (distance == 1) placeDoor(corridor.room.start, false);
        } else {
            return;
        }
    }

    // Only now are we actually sure that we'd use the room

    if (child.prefab) |_| {
        _excavate_prefab(&child, fab.?, allocator, 0, 0);
    } else {
        _excavate_room(&child);
    }

    if (child.prefab) |f|
        f.used[level] += 1;

    if (child.prefab == null) {
        const area = Room{ .start = Coord.new(0, 0), .width = child.width, .height = child.height };
        placeSubroom(s_fabs, &child, &area, allocator);
    } else if (child.prefab.?.subroom_areas.len > 0) {
        for (child.prefab.?.subroom_areas.constSlice()) |subroom_area| {
            placeSubroom(s_fabs, &child, &subroom_area, allocator);
        }
    }

    rooms.append(child) catch unreachable;
}

pub fn placeRandomRooms(
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: *mem.Allocator,
) void {
    var first: ?Room = null;
    const rooms = &state.dungeon.rooms[level];

    var required = Configs[level].prefabs.constSlice();
    var reqctr: usize = 0;

    while (reqctr < required.len) {
        const fab_name = required[reqctr];
        const fab = Prefab.findPrefabByName(fab_name, n_fabs) orelse {
            std.log.warn("Cannot find required prefab {}", .{fab_name});
            return;
        };

        const x = rng.rangeClumping(usize, 1, state.WIDTH - fab.width - 1, 2);
        const y = rng.rangeClumping(usize, 1, state.HEIGHT - fab.height - 1, 2);

        const room = Room{
            .start = Coord.new2(level, x, y),
            .width = fab.width,
            .height = fab.height,
            .prefab = fab,
        };

        if (roomIntersects(rooms, &room, null, null, false))
            continue;

        if (first == null) first = room;
        fab.used[level] += 1;
        _excavate_prefab(&room, fab, allocator, 0, 0);
        rooms.append(room) catch unreachable;

        reqctr += 1;
    }

    if (first == null) {
        const width = rng.range(usize, Configs[level].min_room_width, Configs[level].max_room_width);
        const height = rng.range(usize, Configs[level].min_room_height, Configs[level].max_room_height);
        const x = rng.range(usize, 1, state.WIDTH - width - 1);
        const y = rng.range(usize, 1, state.HEIGHT - height - 1);
        first = Room{ .start = Coord.new2(level, x, y), .width = width, .height = height };
        _excavate_room(&first.?);
        rooms.append(first.?) catch unreachable;
    }

    if (level == PLAYER_STARTING_LEVEL) {
        var p = Coord.new2(level, first.?.start.x + 1, first.?.start.y + 1);
        if (first.?.prefab) |prefab|
            if (prefab.player_position) |pos| {
                p = Coord.new2(level, first.?.start.x + pos.x, first.?.start.y + pos.y);
            };
        _add_player(p, allocator);
    }

    var c = Configs[level].max_rooms;
    while (c > 0) : (c -= 1) {
        _place_rooms(rooms, n_fabs, s_fabs, level, allocator);
    }
}

pub fn placeItems(level: usize) void {
    var containers = state.containers.iterator();
    while (containers.nextPtr()) |container| {
        if (container.coord.z != level) continue;

        // How much should we fill the container?
        const fill = rng.rangeClumping(usize, 0, container.capacity, 2);

        switch (container.type) {
            .Valuables => {
                var i: usize = 0;
                var potion = rng.chooseUnweighted(Potion, &items.POTIONS);
                while (i < fill) : (i += 1) {
                    if (rng.range(usize, 0, 100) < container.item_repeat) {
                        potion = rng.chooseUnweighted(Potion, &items.POTIONS);
                    }

                    state.potions.append(potion) catch unreachable;
                    container.items.append(
                        Item{ .Potion = state.potions.lastPtr().? },
                    ) catch unreachable;
                }
            },
            .Utility => if (Configs[level].utility_items.len > 0) {
                const item_list = Configs[level].utility_items;
                var item = &item_list[rng.range(usize, 0, item_list.len - 1)];
                var i: usize = 0;
                while (i < fill) : (i += 1) {
                    if (rng.range(usize, 0, 100) < container.item_repeat) {
                        item = &item_list[rng.range(usize, 0, item_list.len - 1)];
                    }

                    container.items.append(Item{ .Prop = item }) catch unreachable;
                }
            },
            else => {},
        }
    }
}

pub fn placeTraps(level: usize) void {
    room_iter: for (state.dungeon.rooms[level].items) |room| {
        if (room.prefab) |rfb| if (rfb.notraps) continue;

        // Don't place traps in places where it's impossible to avoid
        if (room.height == 1 or room.width == 1) continue;

        if (rng.onein(2)) continue;

        var tries: usize = 40;
        var trap_coord: Coord = undefined;

        while (tries > 0) : (tries -= 1) {
            trap_coord = room.randomCoord();

            if (isTileAvailable(trap_coord) and
                !state.dungeon.at(trap_coord).prison and
                state.dungeon.neighboringWalls(trap_coord, true) <= 1)
                break; // we found a valid coord

            // didn't find a coord, continue to the next room
            if (tries == 0) continue :room_iter;
        }

        var trap: Machine = undefined;
        if (rng.onein(4)) {
            trap = machines.AlarmTrap;
        } else {
            trap = if (rng.onein(3)) machines.PoisonGasTrap else machines.ParalysisGasTrap;
            trap = switch (rng.range(usize, 0, 4)) {
                0, 1 => machines.ConfusionGasTrap,
                2, 3 => machines.ParalysisGasTrap,
                4 => machines.PoisonGasTrap,
                else => unreachable,
            };

            var num_of_vents = rng.range(usize, 1, 3);
            var v_tries: usize = 100;
            while (v_tries > 0 and num_of_vents > 0) : (v_tries -= 1) {
                const vent = randomWallCoord(&room, v_tries);
                if (state.dungeon.hasMachine(vent) or
                    state.dungeon.at(vent).type != .Wall or
                    state.dungeon.neighboringWalls(vent, true) == 9) continue;

                state.dungeon.at(vent).type = .Floor;
                const prop = _place_prop(vent, Configs[level].vent);
                trap.props[num_of_vents] = prop;
                num_of_vents -= 1;
            }
        }
        _place_machine(trap_coord, &trap);
    }
}

pub fn placeMobs(level: usize, alloc: *mem.Allocator) void {
    var squads: usize = Configs[level].patrol_squads;

    while (squads > 0) : (squads -= 1) {
        const room = rng.chooseUnweighted(Room, state.dungeon.rooms[level].items);
        const patrol_units = rng.range(usize, 2, 4) % math.max(room.width, room.height);
        var patrol_warden: ?*Mob = null;

        if (room.prefab) |rfb| if (rfb.noguards) continue;
        if (room.type == .Corridor) continue;

        var placed_units: usize = 0;
        while (placed_units < patrol_units) {
            const rnd = room.randomCoord();
            if (!isTileAvailable(rnd)) continue;

            if (state.dungeon.at(rnd).mob == null) {
                const guard = placeMob(alloc, &mobs.PatrolTemplate, rnd, .{});

                if (patrol_warden) |warden| {
                    warden.squad_members.append(guard) catch unreachable;
                } else {
                    guard.base_strength += 2;
                    patrol_warden = guard;
                }

                placed_units += 1;
            }
        }
    }

    for (state.dungeon.rooms[level].items) |room| {
        if (room.prefab) |rfb| if (rfb.noguards) continue;
        if (room.type == .Corridor) continue;
        if (room.height * room.width < 16) continue;

        for (Configs[level].mob_options.data) |mob| {
            if (rng.tenin(mob.chance)) {
                var tries: usize = 100;
                while (tries > 0) : (tries -= 1) {
                    const post_coord = room.randomCoord();
                    if (isTileAvailable(post_coord) and !state.dungeon.at(post_coord).prison) {
                        _ = placeMob(alloc, mob.template, post_coord, .{
                            .facing = rng.chooseUnweighted(Direction, &DIRECTIONS),
                        });
                        break;
                    }
                }
            }
        }
    }
}

fn placeLights(room: *const Room) void {
    if (Configs[room.start.z].no_lights) return;
    if (room.prefab) |rfb| if (rfb.nolights) return;

    var lights: usize = 0;
    var lights_needed = rng.rangeClumping(usize, 0, 4, 2);
    var light_tries: usize = rng.range(usize, 0, 50);
    while (light_tries > 0 and lights < lights_needed) : (light_tries -= 1) {
        const coord = randomWallCoord(room, light_tries);

        if (state.dungeon.at(coord).type != .Wall or
            state.dungeon.at(coord).surface != null or
            state.dungeon.neighboringWalls(coord, true) != 6 or
            state.dungeon.neighboringMachines(coord) > 0)
            continue; // invalid coord

        var brazier = Configs[room.start.z].light.*;

        // Dim light by random amount, depending on how many lights there are in
        // room.
        //
        // Rooms with lots of lights can have their lights dimmed quite a bit.
        // Rooms with only one light shouldn't have their lights dimmed by a lot.
        const max_dim: usize = switch (lights_needed) {
            0 => unreachable,
            1 => 5,
            2 => 10,
            3 => 20,
            4 => 30,
            else => unreachable,
        };
        brazier.powered_luminescence -= rng.rangeClumping(usize, 0, max_dim, 2);

        _place_machine(coord, &brazier);
        state.dungeon.at(coord).type = .Floor;
        lights += 1;
    }
}

pub fn placeRoomFeatures(level: usize, alloc: *mem.Allocator) void {
    for (state.dungeon.rooms[level].items) |room| {
        // Don't fill small rooms or corridors.
        if ((room.width * room.height) < 16 or room.type == .Corridor)
            continue;

        placeLights(&room);

        if (room.prefab != null) continue;

        const Range = struct { from: Coord, to: Coord };
        const room_end = room.end();

        const ranges = [_]Range{
            .{ .from = Coord.new(room.start.x + 1, room.start.y), .to = Coord.new(room_end.x - 2, room.start.y) }, // top
            .{ .from = Coord.new(room.start.x + 1, room_end.y - 1), .to = Coord.new(room_end.x - 2, room_end.y - 1) }, // bottom
            .{ .from = Coord.new(room.start.x, room.start.y + 1), .to = Coord.new(room.start.x, room_end.y - 2) }, // left
            .{ .from = Coord.new(room_end.x - 1, room.start.y + 1), .to = Coord.new(room_end.x - 1, room_end.y - 2) }, // left
        };

        var statues: usize = 0;
        var capacity: usize = 0;
        var levers: usize = 0;
        var posters: usize = 0;

        var tries = math.sqrt(room.width * room.height) * 5;
        while (tries > 0) : (tries -= 1) {
            const range = ranges[tries % ranges.len];
            const x = rng.range(usize, range.from.x, range.to.x);
            const y = rng.range(usize, range.from.y, range.to.y);
            const coord = Coord.new2(room.start.z, x, y);

            if (!isTileAvailable(coord) or
                utils.findPatternMatch(coord, &VALID_FEATURE_TILE_PATTERNS) == null)
                continue;

            switch (rng.range(usize, 1, 4)) {
                1 => {
                    if (Configs[level].allow_statues and statues < 3 and rng.onein(3)) {
                        const statue = rng.chooseUnweighted(mobs.MobTemplate, &mobs.STATUES);
                        _ = placeMob(alloc, &statue, coord, .{});
                        statues += 1;
                    } else {
                        const statue = rng.chooseUnweighted(Prop, Configs[level].props);
                        _ = _place_prop(coord, &statue);
                    }
                },
                2 => {
                    if (capacity < (math.sqrt(room.width * room.height) * 4)) {
                        var cont = rng.chooseUnweighted(Container, Configs[level].containers);
                        placeContainer(coord, &cont);
                        capacity += cont.capacity;
                    }
                },
                3 => {
                    if (levers < 1 and room.has_subroom) {
                        _place_machine(coord, &machines.RestrictedMachinesOpenLever);
                        levers += 1;
                    }
                },
                4 => {
                    if ((room.width * room.height) > 16 and posters < 2) {
                        if (choosePoster(level)) |poster| {
                            state.dungeon.at(coord).surface = SurfaceItem{ .Poster = poster };
                            posters += 1;
                        }
                    }
                },
                else => unreachable,
            }
        }
    }
}

pub fn placeRandomStairs(level: usize) void {
    if (level == 0) return;

    const rooms = state.dungeon.rooms[level].items;

    var room_i: usize = 0;
    var placed: usize = 0;

    while (placed < 3 and room_i < rooms.len) : (room_i += 1) {
        const room = &rooms[room_i];

        // Don't place stairs in narrow rooms where it's impossible to avoid.
        if (room.width == 1 or room.height == 1) continue;

        var tries: usize = 5;
        tries: while (tries > 0) : (tries -= 1) {
            const rand = room.randomCoord();
            const current = Coord.new2(level, rand.x, rand.y);
            const above = Coord.new2(level - 1, rand.x, rand.y);

            if (isTileAvailable(current) and
                isTileAvailable(above) and
                !state.dungeon.at(current).prison and
                !state.dungeon.at(above).prison and
                state.dungeon.neighboringWalls(current, true) == 0 and
                state.is_walkable(current, .{ .right_now = true }) and
                state.is_walkable(above, .{ .right_now = true }))
            {
                _place_machine(current, &machines.StairUp);
                _ = _place_prop(above, &machines.StairDstProp);

                placed += 1;
                break :tries;
            }
        }
    }
}

pub fn cellularAutomata(layout: *const [HEIGHT][WIDTH]state.Layout, level: usize, req: usize, isle_req: usize, ttype: TileType) void {
    var old: [HEIGHT][WIDTH]TileType = undefined;
    {
        var y: usize = 1;
        while (y < HEIGHT - 1) : (y += 1) {
            var x: usize = 1;
            while (x < WIDTH - 1) : (x += 1)
                old[y][x] = state.dungeon.at(Coord.new2(level, x, y)).type;
        }
    }

    var y: usize = 1;
    while (y < HEIGHT - 1) : (y += 1) {
        var x: usize = 1;
        while (x < WIDTH - 1) : (x += 1) {
            if (layout[y][x] != .Unknown) continue;

            const coord = Coord.new2(level, x, y);

            var neighbor_on_cells: usize = if (old[coord.y][coord.x] == ttype) 1 else 0;
            for (&CARDINAL_DIRECTIONS) |direction| {
                if (coord.move(direction, state.mapgeometry)) |new| {
                    if (old[new.y][new.x] == ttype)
                        neighbor_on_cells += 1;
                }
            }

            if (neighbor_on_cells >= req) {
                state.dungeon.at(coord).type = ttype;
            } else if (neighbor_on_cells < isle_req) {
                state.dungeon.at(coord).type = ttype;
            } else if (old[coord.y][coord.x] == ttype) {
                state.dungeon.at(coord).type = .Floor;
            }
        }
    }
}

pub fn fillBar(level: usize, height: usize) void {
    // add a horizontal bar of floors in the center of the map as it may
    // prevent a continuous vertical wall from forming during cellular automata,
    // thus preventing isolated sections
    const halfway = HEIGHT / 2;
    var y: usize = halfway;
    while (y < (halfway + height)) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            state.dungeon.at(Coord.new2(level, x, y)).type = .Floor;
        }
    }
}

pub fn fillRandom(layout: *const [HEIGHT][WIDTH]state.Layout, level: usize, chance: usize, ttype: TileType) void {
    var y: usize = 1;
    while (y < HEIGHT - 1) : (y += 1) {
        var x: usize = 1;
        while (x < WIDTH - 1) : (x += 1) {
            if (layout[y][x] != .Unknown) continue;

            const coord = Coord.new2(level, x, y);

            if (rng.range(usize, 0, 100) < chance) {
                state.dungeon.at(coord).type = ttype;
            }
        }
    }
}

pub fn generateLayoutMap(level: usize) void {
    const rooms = &state.dungeon.rooms[level];

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            const coord = Coord.new2(level, x, y);
            const room = Room{ .start = coord, .width = 1, .height = 1 };

            if (findIntersectingRoom(rooms, &room, null, null, false)) |r| {
                state.layout[level][y][x] = state.Layout{ .Room = r };
            } else {
                state.layout[level][y][x] = .Unknown;
            }
        }
    }
}

fn levelFeaturePrisonersMaybe(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    if (rng.onein(2)) levelFeaturePrisoners(c, coord, room, prefab, alloc);
}

fn levelFeaturePrisoners(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const prisoner_t = rng.chooseUnweighted(mobs.MobTemplate, &mobs.PRISONERS);
    const prisoner = placeMob(alloc, &prisoner_t, coord, .{});
    prisoner.prisoner_status = Prisoner{ .of = .Sauron };
}

fn levelFeaturePotions(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const potion = rng.chooseUnweighted(Potion, &items.POTIONS);
    state.potions.append(potion) catch unreachable;
    state.dungeon.itemsAt(coord).append(
        Item{ .Potion = state.potions.lastPtr().? },
    ) catch unreachable;
}

fn levelFeatureVials(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    state.dungeon.itemsAt(coord).append(
        Item{ .Vial = rng.choose(Vial, &Vial.VIALS, &Vial.VIAL_COMMONICITY) catch unreachable },
    ) catch unreachable;
}

fn levelFeatureExperiments(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const exp_t = rng.chooseUnweighted(mobs.MobTemplate, &mobs.EXPERIMENTS);
    const exp = placeMob(alloc, &exp_t, coord, .{});
}

// Randomly place a vial ore. If the Y coordinate is even, create a container and
// fill it up halfway; otherwise, place only one item on the ground.
fn levelFeatureOres(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    var using_container: ?*Container = null;

    if ((coord.y % 2) == 0) {
        placeContainer(coord, &machines.VOreCrate);
        using_container = state.dungeon.at(coord).surface.?.Container;
    }

    var placed: usize = rng.rangeClumping(usize, 3, 8, 2);
    var tries: usize = 50;
    while (tries > 0) : (tries -= 1) {
        const v = rng.choose(Vial.OreAndVial, &Vial.VIAL_ORES, &Vial.VIAL_COMMONICITY) catch unreachable;

        if (v.m) |material| {
            const item = Item{ .Boulder = material };
            if (using_container) |container| {
                container.items.append(item) catch unreachable;
                if (placed == 0) break;
                placed -= 1;
            } else {
                state.dungeon.itemsAt(coord).append(item) catch unreachable;
                break;
            }
        }
    }
}

pub const Prefab = struct {
    subroom: bool = false,
    invisible: bool = false,
    restriction: usize = 1,
    noitems: bool = false,
    noguards: bool = false,
    nolights: bool = false,
    notraps: bool = false,

    name: StackBuffer(u8, MAX_NAME_SIZE) = StackBuffer(u8, MAX_NAME_SIZE).init(null),

    player_position: ?Coord = null,
    height: usize = 0,
    width: usize = 0,
    content: [40][40]FabTile = undefined,
    connections: [40]?Connection = undefined,
    features: [128]?Feature = [_]?Feature{null} ** 128,
    mobs: [45]?FeatureMob = [_]?FeatureMob{null} ** 45,
    prisons: StackBuffer(Room, 8) = StackBuffer(Room, 8).init(null),
    subroom_areas: StackBuffer(Room, 8) = StackBuffer(Room, 8).init(null),
    stockpile: ?Room = null,
    input: ?Room = null,
    output: ?Room = null,

    used: [LEVELS]usize = [_]usize{0} ** LEVELS,

    pub const MAX_NAME_SIZE = 64;

    pub const FabTile = union(enum) {
        Wall,
        LockedDoor,
        Door,
        Brazier,
        Floor,
        Connection,
        Water,
        Lava,
        Bars,
        Feature: u8,
        LevelFeature: usize,
        Any,
    };

    pub const FeatureMob = struct {
        id: [32:0]u8,
        spawn_at: Coord,
        work_at: ?Coord,
    };

    pub const Feature = union(enum) {
        Machine: [32:0]u8,
        Prop: [32:0]u8,
        Potion: [32:0]u8,
    };

    pub const Connection = struct {
        c: Coord,
        d: Direction,
        used: bool = false,
    };

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
        to.append(f.*) catch @panic("OOM");
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

        var lines = mem.tokenize(from, "\n");
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
                    var words = mem.tokenize(line[1..], " ");
                    const key = words.next() orelse return error.MalformedMetadata;
                    const val = words.next() orelse "";

                    if (mem.eql(u8, key, "invisible")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.invisible = true;
                    } else if (mem.eql(u8, key, "subroom")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.subroom = true;
                    } else if (mem.eql(u8, key, "restriction")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.restriction = std.fmt.parseInt(usize, val, 0) catch |_| return error.InvalidMetadataValue;
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
                        var spawn_at_tokens = mem.tokenize(spawn_at_str, ",");
                        const spawn_at_str_a = spawn_at_tokens.next() orelse return error.InvalidMetadataValue;
                        const spawn_at_str_b = spawn_at_tokens.next() orelse return error.InvalidMetadataValue;
                        spawn_at.x = std.fmt.parseInt(usize, spawn_at_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        spawn_at.y = std.fmt.parseInt(usize, spawn_at_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        f.mobs[cm] = FeatureMob{
                            .id = undefined,
                            .spawn_at = spawn_at,
                            .work_at = null,
                        };
                        utils.copyZ(&f.mobs[cm].?.id, val);

                        if (maybe_work_at_str) |work_at_str| {
                            var work_at = Coord.new(0, 0);
                            var work_at_tokens = mem.tokenize(work_at_str, ",");
                            const work_at_str_a = work_at_tokens.next() orelse return error.InvalidMetadataValue;
                            const work_at_str_b = work_at_tokens.next() orelse return error.InvalidMetadataValue;
                            work_at.x = std.fmt.parseInt(usize, work_at_str_a, 0) catch |_| return error.InvalidMetadataValue;
                            work_at.y = std.fmt.parseInt(usize, work_at_str_b, 0) catch |_| return error.InvalidMetadataValue;
                            f.mobs[cm].?.work_at = work_at;
                        }

                        cm += 1;
                    } else if (mem.eql(u8, key, "prison")) {
                        var room_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var room_start_tokens = mem.tokenize(val, ",");
                        const room_start_str_a = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const room_start_str_b = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        room_start.x = std.fmt.parseInt(usize, room_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        room_start.y = std.fmt.parseInt(usize, room_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.prisons.append(.{ .start = room_start, .width = width, .height = height }) catch |_| return error.TooManyPrisons;
                    } else if (mem.eql(u8, key, "subroom_area")) {
                        var room_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var room_start_tokens = mem.tokenize(val, ",");
                        const room_start_str_a = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const room_start_str_b = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        room_start.x = std.fmt.parseInt(usize, room_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        room_start.y = std.fmt.parseInt(usize, room_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.subroom_areas.append(.{ .start = room_start, .width = width, .height = height }) catch |_| return error.TooManySubrooms;
                    } else if (mem.eql(u8, key, "stockpile")) {
                        if (f.stockpile) |_| return error.StockpileAlreadyDefined;

                        var room_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var room_start_tokens = mem.tokenize(val, ",");
                        const room_start_str_a = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const room_start_str_b = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        room_start.x = std.fmt.parseInt(usize, room_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        room_start.y = std.fmt.parseInt(usize, room_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.stockpile = .{ .start = room_start, .width = width, .height = height };
                    } else if (mem.eql(u8, key, "output")) {
                        if (f.output) |_| return error.OutputAreaAlreadyDefined;

                        var room_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var room_start_tokens = mem.tokenize(val, ",");
                        const room_start_str_a = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const room_start_str_b = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        room_start.x = std.fmt.parseInt(usize, room_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        room_start.y = std.fmt.parseInt(usize, room_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.output = .{ .start = room_start, .width = width, .height = height };
                    } else if (mem.eql(u8, key, "input")) {
                        if (f.input) |_| return error.InputAreaAlreadyDefined;

                        var room_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var room_start_tokens = mem.tokenize(val, ",");
                        const room_start_str_a = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const room_start_str_b = room_start_tokens.next() orelse return error.InvalidMetadataValue;
                        room_start.x = std.fmt.parseInt(usize, room_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        room_start.y = std.fmt.parseInt(usize, room_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.input = .{ .start = room_start, .width = width, .height = height };
                    }
                },
                '@' => {
                    var words = mem.tokenize(line, " ");
                    _ = words.next(); // Skip the '@<ident>' bit

                    const identifier = line[1];
                    const feature_type = words.next() orelse return error.MalformedFeatureDefinition;
                    if (feature_type.len != 1) return error.InvalidFeatureType;

                    switch (feature_type[0]) {
                        'P' => {
                            const id = words.next() orelse return error.MalformedFeatureDefinition;
                            f.features[identifier] = Feature{ .Potion = [_:0]u8{0} ** 32 };
                            mem.copy(u8, &f.features[identifier].?.Potion, id);
                        },
                        'p' => {
                            const id = words.next() orelse return error.MalformedFeatureDefinition;
                            f.features[identifier] = Feature{ .Prop = [_:0]u8{0} ** 32 };
                            mem.copy(u8, &f.features[identifier].?.Prop, id);
                        },
                        'm' => {
                            const id = words.next() orelse return error.MalformedFeatureDefinition;
                            f.features[identifier] = Feature{ .Machine = [_:0]u8{0} ** 32 };
                            mem.copy(u8, &f.features[identifier].?.Machine, id);
                        },
                        else => return error.InvalidFeatureType,
                    }
                },
                else => {
                    if (y > f.content.len) return error.FabTooTall;

                    var x: usize = 0;
                    var utf8view = std.unicode.Utf8View.init(line) catch |_| {
                        return error.InvalidUtf8;
                    };
                    var utf8 = utf8view.iterator();
                    while (utf8.nextCodepointSlice()) |encoded_codepoint| : (x += 1) {
                        if (x > f.content[0].len) return error.FabTooWide;

                        const c = std.unicode.utf8Decode(encoded_codepoint) catch |_| {
                            return error.InvalidUtf8;
                        };

                        f.content[y][x] = switch (c) {
                            '#' => .Wall,
                            '+' => .Door,
                            '±' => .LockedDoor,
                            '•' => .Brazier,
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

    pub fn greaterThan(_: void, a: Prefab, b: Prefab) bool {
        return (a.height * a.width) > (b.height * b.width);
    }
};

pub const PrefabArrayList = std.ArrayList(Prefab);

// FIXME: error handling
// FIXME: warn if prefab is zerowidth/zeroheight (prefabs file might not have fit in buffer)
pub fn readPrefabs(alloc: *mem.Allocator, n_fabs: *PrefabArrayList, s_fabs: *PrefabArrayList) void {
    var buf: [8192]u8 = undefined;

    n_fabs.* = PrefabArrayList.init(alloc);
    s_fabs.* = PrefabArrayList.init(alloc);

    const fabs_dir = std.fs.cwd().openDir("prefabs", .{
        .iterate = true,
    }) catch unreachable;

    var fabs_dir_iterator = fabs_dir.iterate();
    while (fabs_dir_iterator.next() catch unreachable) |fab_file| {
        if (fab_file.kind != .File) continue;

        var fab_f = fabs_dir.openFile(fab_file.name, .{
            .read = true,
            .lock = .None,
        }) catch unreachable;
        defer fab_f.close();

        const read = fab_f.readAll(buf[0..]) catch unreachable;

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
            std.log.warn("{}: Couldn't load prefab: {}", .{ fab_file.name, msg });
            continue;
        };
    }

    std.sort.insertionSort(Prefab, s_fabs.items, {}, Prefab.greaterThan);
}

pub const LevelConfig = struct {
    identifier: []const u8,
    prefabs: RPBuf = RPBuf.init(null),
    distances: [2][10]usize,
    prefab_chance: usize,
    max_rooms: usize,

    // Dimensions include the first wall, so a minimum width of 2 guarantee that
    // there will be one empty space in the room, minimum.
    min_room_width: usize = 7,
    min_room_height: usize = 5,
    max_room_width: usize = 20,
    max_room_height: usize = 15,

    level_features: [4]?LevelFeatureFunc = [_]?LevelFeatureFunc{ null, null, null, null },

    patrol_squads: usize,
    mob_options: MCBuf = MCBuf.init(&[_]MobConfig{
        .{ .chance = 12, .template = &mobs.GuardTemplate },
        .{ .chance = 50, .template = &mobs.ExecutionerTemplate },
        .{ .chance = 70, .template = &mobs.WatcherTemplate },
    }),

    no_lights: bool = false,
    material: *const Material = &materials.Concrete,
    light: *const Machine = &machines.Brazier,
    vent: *const Prop = &machines.GasVentProp,
    bars: *const Prop = &machines.IronBarProp,
    props: []const Prop = &machines.STATUES,
    containers: []const Container = &[_]Container{
        machines.Bin,
        machines.Barrel,
        machines.Cabinet,
        machines.Chest,
    },
    utility_items: []const Prop = &[_]Prop{},
    allow_statues: bool = true,

    pub const RPBuf = StackBuffer([]const u8, 4);
    pub const MCBuf = StackBuffer(MobConfig, 3);
    pub const LevelFeatureFunc = fn (usize, Coord, *const Room, *const Prefab, *mem.Allocator) void;

    pub const MobConfig = struct {
        chance: usize, // Ten in <chance>
        template: *const mobs.MobTemplate,
    };
};

pub const Configs = [LEVELS]LevelConfig{
    .{
        .identifier = "ENT",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "ENT_start",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 5, 9, 1, 0, 0, 0, 0, 0, 0, 0 },
        },
        .prefab_chance = 2,
        .max_rooms = 256,

        .patrol_squads = 3,
    },
    .{
        .identifier = "REC",
        .prefabs = LevelConfig.RPBuf.init(null),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 0, 9, 0, 0, 0, 0, 0, 0, 0, 5 },
        },
        .prefab_chance = 100, // No prefabs for REC
        .max_rooms = 2048,
        .min_room_width = 8,
        .min_room_height = 5,
        .max_room_width = 10,
        .max_room_height = 6,

        .patrol_squads = 1,

        .allow_statues = false,
    },
    .{
        .identifier = "TEM",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "TEM_start",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        },
        .prefab_chance = 1,
        .max_rooms = 4096,

        .patrol_squads = 2,

        .no_lights = true,
        .material = &materials.Limestone,
    },
    .{
        .identifier = "LAB",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "LAB_power",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 9, 2, 1, 1, 1, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 100, // No prefabs for LAB
        .max_rooms = 2048,
        .min_room_width = 8,
        .min_room_height = 6,
        .max_room_width = 30,
        .max_room_height = 20,

        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeatureVials,
            levelFeaturePrisoners,
            levelFeatureExperiments,
            levelFeatureOres,
        },

        .patrol_squads = 1,
        .mob_options = LevelConfig.MCBuf.init(&[_]LevelConfig.MobConfig{
            .{ .chance = 21, .template = &mobs.SentinelTemplate },
            .{ .chance = 35, .template = &mobs.WatcherTemplate },
            .{ .chance = 56, .template = &mobs.GuardTemplate },
        }),

        .material = &materials.Dobalene,
        .light = &machines.Lamp,
        .vent = &machines.LabGasVentProp,
        .bars = &machines.TitaniumBarProp,
        .props = &machines.LABSTUFF,
        .containers = &[_]Container{ machines.Chest, machines.LabCabinet },
        .utility_items = &machines.LAB_UTILITY_ITEMS,

        .allow_statues = false,
    },
    .{
        .identifier = "PRI",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "PRI_start",
            "PRI_power",
            "PRI_insurgency",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 2,
        .max_rooms = 512,
        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeaturePrisoners,
            levelFeaturePrisonersMaybe,
            null,
            null,
        },

        .patrol_squads = 6,
    },
    .{
        .identifier = "PRI",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "PRI_start",
            "PRI_power",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 2,
        .max_rooms = 512,
        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeaturePrisoners,
            levelFeaturePrisonersMaybe,
            null,
            null,
        },

        .patrol_squads = 5,
    },
    .{
        .identifier = "SMI",
        .prefabs = LevelConfig.RPBuf.init(null),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 },
        },
        .prefab_chance = 1,
        .max_rooms = 512,

        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            null,
            null,
            null,
            null,
        },

        .patrol_squads = 3,
        .mob_options = LevelConfig.MCBuf.init(&[_]LevelConfig.MobConfig{
            .{ .chance = 21, .template = &mobs.SentinelTemplate },
            .{ .chance = 35, .template = &mobs.WatcherTemplate },
            .{ .chance = 56, .template = &mobs.GuardTemplate },
        }),

        .material = &materials.Limestone,

        .allow_statues = false,
    },
};
