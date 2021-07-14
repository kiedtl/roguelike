const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const rng = @import("rng.zig");
const mobs = @import("mobs.zig");
const StackBuffer = @import("buffer.zig").StackBuffer;
const items = @import("items.zig");
const machines = @import("machines.zig");
const materials = @import("materials.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

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

fn isTileAvailable(coord: Coord) bool {
    return state.dungeon.at(coord).mob == null and
        state.dungeon.at(coord).surface == null and
        state.dungeon.itemsAt(coord).len == 0;
}

const PlaceMobOptions = struct {
    facing: ?Direction = null,
    phase: OccupationPhase = .Work,
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
    mob.occupation.phase = opts.phase;

    if (template.weapon) |w| mob.inventory.wielded = _createItem(Weapon, w.*);
    if (template.backup_weapon) |w| mob.inventory.backup = _createItem(Weapon, w.*);
    if (template.armor) |a| mob.inventory.armor = _createItem(Armor, a.*);

    if (opts.facing) |dir| mob.facing = dir;
    mob.occupation.work_area.append(opts.work_area orelse coord) catch unreachable;

    state.mobs.append(mob) catch unreachable;
    const ptr = state.mobs.lastPtr().?;
    state.dungeon.at(coord).mob = ptr;
    return ptr;
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

// STYLE: make top level public func, call directly, rename placePlayer
fn _add_player(coord: Coord, alloc: *mem.Allocator) void {
    const echoring = _createItem(Ring, items.EcholocationRing);
    echoring.worn_since = state.ticks;

    const bolts = _createItem(Projectile, items.CrossbowBoltProjectile);
    bolts.count = 10;

    state.player = placeMob(alloc, &mobs.PlayerTemplate, coord, .{ .phase = .SawHostile });
    state.player.inventory.r_rings[0] = echoring;
    state.player.inventory.pack.append(Item{ .Projectile = bolts }) catch unreachable;
}

fn choosePrefab(level: usize, prefabs: *PrefabArrayList) ?Prefab {
    var i: usize = 512;
    while (i > 0) : (i -= 1) {
        // Don't use rng.chooseUnweighted, as we need a pointer to manage the
        // restriction amount should we choose it.
        const p = &prefabs.items[rng.range(usize, 0, prefabs.items.len - 1)];

        if (p.invisible)
            continue; // Can't be used unless specifically called for by name.

        if (!mem.eql(u8, p.name.constSlice()[0..3], Configs[level].identifier))
            continue; // Prefab isn't for this level.

        if (p.restriction) |restriction|
            if (p.used[level] >= restriction)
                continue; // Prefab was used too many times.

        return p.*;
    }

    return null;
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
                .Feature => |feature_id| {
                    const feature = fab.features[feature_id].?;
                    switch (feature) {
                        .Prop => |pid| {
                            const prop = utils.findById(&machines.PROPS, pid).?;
                            _ = _place_prop(rc, &machines.PROPS[prop]);
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
                },
                .LockedDoor => placeDoor(rc, true),
                .Door => placeDoor(rc, false),
                .Brazier => _place_machine(rc, &machines.Brazier),
                .Bars => _ = _place_prop(rc, &machines.IronBarProp),
                else => {},
            }
        }
    }

    for (fab.mobs) |maybe_mob| {
        if (maybe_mob) |mob_f| {
            if (utils.findById(&mobs.MOBS, mob_f.id)) |mob_template| {
                const coord = room.start.add(mob_f.spawn_at);
                const work_area = room.start.add(mob_f.work_at orelse mob_f.spawn_at);

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
        if (parent.prefab) |*f| {
            const con = f.connectorFor(side) orelse return null;
            corridor_coord.x = parent.start.x + con.x;
            corridor_coord.y = parent.start.y + con.y;
            parent_connector_coord = corridor_coord;
            f.useConnector(con) catch unreachable;
        }
        if (child.prefab) |*f| {
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

    var fab: ?Prefab = null;
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
        child = parent.attach(side, fab.?.width, fab.?.height, distance, &fab.?) orelse return;
        child.prefab = fab;

        if (roomIntersects(rooms, &child, parent, null, false) or child.overflowsLimit(&LIMIT))
            return;
    } else {
        if (parent.prefab != null and distance == 0) distance += 1;

        var child_w = rng.rangeClumping(usize, Configs[level].min_room_width, Configs[level].max_room_width, 2);
        var child_h = rng.rangeClumping(usize, Configs[level].min_room_height, Configs[level].max_room_height, 2);
        child = parent.attach(side, child_w, child_h, distance, null) orelse return;

        while (roomIntersects(rooms, &child, parent, null, true) or child.overflowsLimit(&LIMIT)) {
            if (child_w < Configs[level].min_room_width or
                child_h < Configs[level].min_room_height)
                return;

            child_w -= 1;
            child_h -= 1;
            child = parent.attach(side, child_w, child_h, distance, null).?;
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
        _excavate_prefab(&child, &fab.?, allocator, 0, 0);
    } else {
        _excavate_room(&child);
    }

    rooms.append(child) catch unreachable;

    if (child.prefab) |f|
        Prefab.incrementUsedCounter(f.name.constSlice(), level, n_fabs);

    if (child.prefab == null)
        if (choosePrefab(level, s_fabs)) |subroom|
            if (subroom.height < child.height and subroom.width < child.width) {
                const mx = child.width - subroom.width;
                const my = child.height - subroom.height;
                const rx = rng.range(usize, 0, mx);
                const ry = rng.range(usize, 0, my);
                _excavate_prefab(&child, &subroom, allocator, rx, ry);
            };
}

pub fn placeRandomRooms(
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: *mem.Allocator,
) void {
    var rooms = RoomArrayList.init(allocator);

    var first: ?Room = null;

    var required = Configs[level].prefabs.constSlice();
    var reqctr: usize = 0;

    while (reqctr < required.len) {
        const fab_name = required[reqctr];
        const fab = Prefab.findPrefabByName(fab_name, n_fabs) orelse {
            std.log.warn("Cannot find required prefab {}", .{fab_name});
            return;
        };

        const x = rng.range(usize, 1, state.WIDTH - fab.width - 1);
        const y = rng.range(usize, 1, state.HEIGHT - fab.height - 1);

        const room = Room{
            .start = Coord.new2(level, x, y),
            .width = fab.width,
            .height = fab.height,
            .prefab = fab,
        };

        if (roomIntersects(&rooms, &room, null, null, false))
            continue;

        if (first == null) first = room;
        Prefab.incrementUsedCounter(fab.name.constSlice(), level, n_fabs);
        _excavate_prefab(&room, &fab, allocator, 0, 0);
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
        _place_rooms(&rooms, n_fabs, s_fabs, level, allocator);
    }

    state.dungeon.rooms[level] = rooms;
}

pub fn placeItems(level: usize) void {
    for (state.dungeon.rooms[level].items) |room| {
        if (room.prefab) |rfb| if (rfb.noitems) continue;
        if ((room.height * room.width) < 20) continue;

        if (rng.onein(3)) {
            var place = rng.range(usize, 1, 3);
            while (place > 0) {
                const coord = room.randomCoord();
                if (!isTileAvailable(coord))
                    continue;

                switch (rng.range(usize, 0, 1)) {
                    0 => {
                        const potion = rng.chooseUnweighted(Potion, &items.POTIONS);
                        state.potions.append(potion) catch unreachable;
                        state.dungeon.itemsAt(coord).append(
                            Item{ .Potion = state.potions.lastPtr().? },
                        ) catch unreachable;
                    },
                    1 => {
                        var bolt = items.CrossbowBoltProjectile;
                        bolt.count = rng.rangeClumping(usize, 3, 10, 2);
                        state.projectiles.append(bolt) catch unreachable;
                        state.dungeon.itemsAt(coord).append(
                            Item{ .Projectile = state.projectiles.lastPtr().? },
                        ) catch unreachable;
                    },
                    else => unreachable,
                }

                place -= 1;
            }
        }
    }
}

pub fn placeTraps(level: usize) void {
    for (state.dungeon.rooms[level].items) |room| {
        if (room.prefab) |rfb| if (rfb.notraps) continue;

        // Don't place traps in places where it's impossible to avoid
        if (room.height == 1 or room.width == 1) continue;

        if (rng.onein(2)) {
            const trap_coord = room.randomCoord();
            if (state.dungeon.at(trap_coord).surface != null) continue;

            var trap: Machine = undefined;
            if (rng.onein(3)) {
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
                while (num_of_vents > 0) : (num_of_vents -= 1) {
                    const vent = room.randomCoord();
                    if (state.dungeon.hasMachine(vent)) continue;

                    const prop = _place_prop(vent, &machines.GasVentProp);
                    trap.props[num_of_vents] = prop;
                }
            }
            _place_machine(trap_coord, &trap);
        }
    }
}

pub fn placeMobs(level: usize, alloc: *mem.Allocator) void {
    var squads: usize = rng.range(usize, 5, 8);
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
                const guard = placeMob(alloc, &mobs.GuardTemplate, rnd, .{});

                if (patrol_warden) |warden| {
                    warden.squad_members.append(guard) catch unreachable;
                } else {
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

        if (rng.onein(2)) {
            const post_coord = room.randomCoord();
            if (isTileAvailable(post_coord)) {
                _ = placeMob(alloc, &mobs.WatcherTemplate, post_coord, .{
                    .facing = rng.chooseUnweighted(Direction, &DIRECTIONS),
                });
            }
        }

        if (rng.onein(4)) {
            const post_coord = room.randomCoord();
            if (isTileAvailable(post_coord)) {
                _ = placeMob(alloc, &mobs.ExecutionerTemplate, post_coord, .{
                    .facing = rng.chooseUnweighted(Direction, &DIRECTIONS),
                });
            }
        }
    }
}

fn _lightCorridor(room: *const Room) void {
    assert(room.type == .Corridor);
    const room_end = room.end();

    var last_placed: usize = 0;

    if (room.height == 1) {
        var x = room.start.x;
        while (x < room_end.x) : (x += 1) {
            if (x - last_placed > 5) {
                const coord = Coord.new2(room.start.z, x, room_end.y);
                _place_machine(coord, &machines.Brazier);
                last_placed = x;
            }
        }
    } else if (room.width == 1) {
        var y = room.start.y;
        while (y < room_end.y) : (y += 1) {
            if (y - last_placed > 5) {
                const coord = Coord.new2(room.start.z, room_end.x, y);
                _place_machine(coord, &machines.Brazier);
                last_placed = y;
            }
        }
    }
}

pub fn placeRoomFeatures(level: usize, alloc: *mem.Allocator) void {
    for (state.dungeon.rooms[level].items) |room| {
        if (room.prefab) |rfb| if (rfb.nolights) continue;

        // Don't light small rooms.
        if ((room.width * room.height) < 16)
            continue;

        // Treat corridors specially.
        if (room.height == 1 or room.width == 1) {
            _lightCorridor(&room);
            continue;
        }

        const Range = struct { from: Coord, to: Coord };
        const room_end = room.end();

        const ranges = [_]Range{
            .{ .from = Coord.new(room.start.x + 1, room.start.y), .to = Coord.new(room_end.x - 2, room.start.y) }, // top
            .{ .from = Coord.new(room.start.x + 1, room_end.y - 1), .to = Coord.new(room_end.x - 2, room_end.y - 1) }, // bottom
            .{ .from = Coord.new(room.start.x, room.start.y + 1), .to = Coord.new(room.start.x, room_end.y - 2) }, // left
            .{ .from = Coord.new(room_end.x - 1, room.start.y + 1), .to = Coord.new(room_end.x - 1, room_end.y - 2) }, // left
        };

        var lights: usize = 0;
        var statues: usize = 0;

        var tries = rng.range(usize, 0, 100);
        while (tries > 0) : (tries -= 1) {
            const range = rng.chooseUnweighted(Range, &ranges);
            const x = rng.rangeClumping(usize, range.from.x, range.to.x, 3);
            const y = rng.rangeClumping(usize, range.from.y, range.to.y, 2);
            const coord = Coord.new2(room.start.z, x, y);

            if (!isTileAvailable(coord)) continue;

            switch (rng.range(usize, 1, 2)) {
                1 => {
                    if (statues < 1 and state.dungeon.neighboringWalls(coord, true) == 3) {
                        const statue = rng.chooseUnweighted(mobs.MobTemplate, &mobs.STATUES);
                        _ = placeMob(alloc, &statue, coord, .{});
                        statues += 1;
                    }
                },
                2 => {
                    if (lights < 3 and state.dungeon.neighboringWalls(coord, true) == 3) {
                        var brazier = machines.Brazier;
                        brazier.powered_luminescence -= rng.rangeClumping(usize, 0, 30, 2);
                        _place_machine(coord, &brazier);
                        lights += 1;
                    }
                },
                3 => {
                    var chest = machines.Chest;
                    chest.capacity -= rng.rangeClumping(usize, 0, 3, 2);
                    placeContainer(coord, &chest);
                },
                else => unreachable,
            }
        }
    }
}

pub fn placeRandomStairs(level: usize) void {
    if (level == (state.LEVELS - 1)) {
        return;
    }

    var placed: usize = 0;
    while (placed < 5) {
        const room = rng.chooseUnweighted(Room, state.dungeon.rooms[level].items);

        // Don't place stairs in narrow rooms where it's impossible to avoid.
        if (room.width == 1 or room.height == 1) continue;

        const rand = room.randomCoord();
        const above = Coord.new2(level, rand.x, rand.y);
        const below = Coord.new2(level + 1, rand.x, rand.y);

        if (isTileAvailable(above) and
            isTileAvailable(below) and
            state.is_walkable(below, .{ .right_now = true }) and
            state.is_walkable(above, .{ .right_now = true }))
        {
            _place_machine(above, &machines.StairDown);
            _place_machine(below, &machines.StairUp);

            placed += 1;
        }
    }
}

pub fn cellularAutomata(avoid: *const [HEIGHT][WIDTH]bool, level: usize, wall_req: usize, isle_req: usize) void {
    var old: [HEIGHT][WIDTH]TileType = undefined;
    {
        var y: usize = 0;
        while (y < HEIGHT) : (y += 1) {
            var x: usize = 0;
            while (x < WIDTH) : (x += 1)
                old[y][x] = state.dungeon.at(Coord.new2(level, x, y)).type;
        }
    }

    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            if (avoid[y][x]) continue;
            const coord = Coord.new2(level, x, y);

            var neighbor_walls: usize = if (old[coord.y][coord.x] == .Wall) 1 else 0;
            for (&DIRECTIONS) |direction| {
                if (coord.move(direction, state.mapgeometry)) |new| {
                    continue;
                    if (old[new.y][new.x] == .Wall)
                        neighbor_walls += 1;
                }
            }

            if (neighbor_walls >= wall_req) {
                state.dungeon.at(coord).type = .Wall;
            } else if (neighbor_walls <= isle_req) {
                state.dungeon.at(coord).type = .Wall;
            } else {
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

pub fn fillRandom(avoid: *const [HEIGHT][WIDTH]bool, level: usize, floor_chance: usize) void {
    var y: usize = 0;
    while (y < HEIGHT) : (y += 1) {
        var x: usize = 0;
        while (x < WIDTH) : (x += 1) {
            if (avoid[y][x]) continue;
            const coord = Coord.new2(level, x, y);

            const t: TileType = if (rng.range(usize, 0, 100) > floor_chance) .Wall else .Floor;
            state.dungeon.at(coord).type = t;
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

pub fn populateCaves(avoid: *const [HEIGHT][WIDTH]bool, level: usize, alloc: *mem.Allocator) void {
    const map = Room{
        .start = Coord.new2(level, 0, 0),
        .width = WIDTH,
        .height = HEIGHT,
    };

    var placed: usize = 0;
    while (placed < 20) {
        const coord = map.randomCoord();
        if (avoid[coord.y][coord.x]) continue;
        if (!state.is_walkable(coord, .{ .right_now = true })) continue;

        if (rng.onein(3)) {
            _ = placeMob(alloc, &mobs.GoblinTemplate, coord, .{});
        } else {
            _ = placeMob(alloc, &mobs.CaveRatTemplate, coord, .{});
        }

        const mobptr = state.mobs.lastPtr().?;
        state.dungeon.at(coord).mob = mobptr;

        placed += 1;
    }
}

pub const Prefab = struct {
    subroom: bool = false,
    invisible: bool = false,
    restriction: ?usize = null,
    noitems: bool = false,
    noguards: bool = false,
    nolights: bool = false,
    notraps: bool = false,

    name: StackBuffer(u8, MAX_NAME_SIZE) = StackBuffer(u8, MAX_NAME_SIZE).init(null),
    player_position: ?Coord = null,

    height: usize = 0,
    width: usize = 0,
    content: [40][40]FabTile = undefined,
    connections: [80]?Connection = undefined,
    features: [255]?Feature = [_]?Feature{null} ** 255,
    mobs: [40]?FeatureMob = [_]?FeatureMob{null} ** 40,

    used: [LEVELS]usize = [_]usize{0} ** LEVELS,

    pub const MAX_NAME_SIZE = 64;

    pub const FabTile = union(enum) {
        Wall, LockedDoor, Door, Brazier, Floor, Connection, Water, Lava, Bars, Feature: u8, Any
    };

    pub const FeatureMob = struct {
        id: [32:0]u8,
        spawn_at: Coord,
        work_at: ?Coord,
    };

    pub const Feature = union(enum) {
        Machine: [32:0]u8,
        Prop: [32:0]u8,
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

    pub fn parse(from: []const u8) !Prefab {
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
                    }
                },
                '@' => {
                    var words = mem.tokenize(line, " ");
                    _ = words.next(); // Skip the '@<ident>' bit

                    const identifier = line[1];
                    const feature_type = words.next() orelse return error.MalformedFeatureDefinition;
                    if (feature_type.len != 1) return error.InvalidFeatureType;

                    switch (feature_type[0]) {
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
                            '0'...'9', 'a'...'z' => FabTile{ .Feature = @intCast(u8, c) },
                            else => return error.InvalidFabTile,
                        };
                    }

                    if (x > w) w = x;
                    y += 1;
                },
            }
        }

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

        return f;
    }

    pub fn findPrefabByName(name: []const u8, fabs: *const PrefabArrayList) ?Prefab {
        for (fabs.items) |f| if (mem.eql(u8, name, f.name.constSlice())) return f;
        return null;
    }

    pub fn incrementUsedCounter(id: []const u8, level: usize, lst: *PrefabArrayList) void {
        for (lst.items) |*f, i| {
            if (mem.eql(u8, id, f.name.constSlice())) {
                f.used[level] += 1;
                break;
            }
        }
    }
};

pub const PrefabArrayList = std.ArrayList(Prefab);

// FIXME: error handling
pub fn readPrefabs(alloc: *mem.Allocator, n_fabs: *PrefabArrayList, s_fabs: *PrefabArrayList) void {
    var buf: [2048]u8 = undefined;

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

        var f = Prefab.parse(buf[0..read]) catch |e| {
            const msg = switch (e) {
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

        const prefab_name = mem.trimRight(u8, fab_file.name, ".fab");
        f.name = StackBuffer(u8, Prefab.MAX_NAME_SIZE).init(prefab_name);

        if (f.subroom)
            s_fabs.append(f) catch @panic("OOM")
        else
            n_fabs.append(f) catch @panic("OOM");
    }
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

    pub const RPBuf = StackBuffer([]const u8, 4);
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
    },
    .{
        .identifier = "TEM",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "TEM_start",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 0, 7, 6, 5, 2, 2, 1, 0, 0, 0 },
        },
        .prefab_chance = 1,
        .max_rooms = 2048,
    },
    .{
        .identifier = "REC",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{}),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 0, 9, 0, 0, 0, 0, 0, 0, 0, 0 },
        },
        .prefab_chance = 2, // no prefabs for REC
        .max_rooms = 2048,
        .min_room_width = 8,
        .min_room_height = 5,
        .max_room_width = 10,
        .max_room_height = 6,
    },
    .{
        .identifier = "LAB",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "LAB_start",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 0, 7, 6, 5, 2, 2, 1, 0, 0, 0 },
        },
        .prefab_chance = 1,
        .max_rooms = 2048,
    },
    .{
        .identifier = "PRI",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "PRI_start",
            "PRI_power",
            "PRI_cleaning",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 3,
        .max_rooms = 512,
    },
    .{
        .identifier = "PRI",
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "PRI_start",
            "PRI_power",
            "PRI_insurgency",
            "PRI_cleaning",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 3,
        .max_rooms = 512,
    },
};
