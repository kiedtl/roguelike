const std = @import("std");
const heap = std.heap;
const mem = std.mem;
const math = std.math;
const meta = std.meta;
const assert = std.debug.assert;

const astar = @import("astar.zig");
const rng = @import("rng.zig");
const mobs = @import("mobs.zig");
const StackBuffer = @import("buffer.zig").StackBuffer;
const items = @import("items.zig");
const surfaces = @import("surfaces.zig");
const literature = @import("literature.zig");
const materials = @import("materials.zig");
const utils = @import("utils.zig");
const state = @import("state.zig");
usingnamespace @import("types.zig");

const ItemTemplate = items.ItemTemplate;
const Evocable = items.Evocable;
const EvocableList = items.EvocableList;
const Poster = literature.Poster;

const CONNECTIONS_MAX = 5;

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

const VALID_DOOR_PLACEMENT_PATTERNS = [_][]const u8{
    // ?.?
    // #.#
    // ?.?
    "?.?#.#?.?",

    // ?#?
    // ...
    // ?#?
    "?#?...?#?",
};

const VALID_LIGHT_PLACEMENT_PATTERNS = [_][]const u8{
    // ???
    // ###
    // ???
    "???###???",

    // ?#?
    // ?#?
    // ?#?
    "?#??#??#?",
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
        const i = rng.range(usize, 0, literature.posters.items.len - 1);
        const p = &literature.posters.items[i];

        if (p.placement_counter > 0 or !mem.eql(u8, state.levelinfo[level].id, p.level))
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

    for (template.evocables) |evocable_template| {
        var evocable = _createItem(Evocable, evocable_template);
        evocable.charges = evocable.max_charges;
        mob.inventory.pack.append(Item{ .Evocable = evocable }) catch unreachable;
    }

    for (template.statuses) |status_info| {
        mob.addStatus(status_info.status, status_info.power, status_info.duration, status_info.permanent);
    }

    state.mobs.append(mob) catch unreachable;
    const ptr = state.mobs.last().?;
    state.dungeon.at(coord).mob = ptr;
    return ptr;
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
    } else unreachable;
}

fn randomWallCoord(rect: *const Rect, i: ?usize) Coord {
    const Range = struct { from: Coord, to: Coord };
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

fn _createItem(comptime T: type, item: T) *T {
    comptime const list = switch (T) {
        Potion => &state.potions,
        Ring => &state.rings,
        Armor => &state.armors,
        Weapon => &state.weapons,
        Projectile => &state.projectiles,
        Evocable => &state.evocables,
        else => @compileError("uh wat"),
    };
    return list.appendAndReturn(item) catch @panic("OOM");
}

fn _createItemFromTemplate(template: ItemTemplate) Item {
    return switch (template.i) {
        .W => |i| Item{ .Weapon = _createItem(Weapon, i) },
        .A => |i| Item{ .Armor = _createItem(Armor, i) },
        .P => |i| Item{ .Potion = _createItem(Potion, i) },
        .E => |i| Item{ .Evocable = _createItem(Evocable, i) },
        //else => @panic("TODO"),
    };
}

fn _chooseLootItem(item_weights: []usize, value_range: MinMax(usize)) ItemTemplate {
    while (true) {
        const item_info = rng.choose(
            @TypeOf(items.ITEM_DROPS[0]),
            &items.ITEM_DROPS,
            item_weights,
        ) catch unreachable;

        if (!value_range.contains(item_info.w))
            continue;

        return item_info;
    }
}

fn placeProp(coord: Coord, prop_template: *const Prop) *Prop {
    var prop = prop_template.*;
    prop.coord = coord;
    state.props.append(prop) catch unreachable;
    const propptr = state.props.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Prop = propptr };
    return state.props.last().?;
}

fn placeContainer(coord: Coord, template: *const Container) void {
    var container = template.*;
    container.coord = coord;
    state.containers.append(container) catch unreachable;
    const ptr = state.containers.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Container = ptr };
}

fn _place_machine(coord: Coord, machine_template: *const Machine) void {
    var machine = machine_template.*;
    machine.coord = coord;
    state.machines.append(machine) catch unreachable;
    const machineptr = state.machines.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = machineptr };
}

fn placeDoor(coord: Coord, locked: bool) void {
    var door = if (locked) surfaces.LockedDoor else Configs[coord.z].door.*;
    door.coord = coord;
    state.machines.append(door) catch unreachable;
    const doorptr = state.machines.last().?;
    state.dungeon.at(coord).surface = SurfaceItem{ .Machine = doorptr };
    state.dungeon.at(coord).type = .Floor;
}

fn _add_player(coord: Coord, alloc: *mem.Allocator) void {
    const echoring = _createItem(Ring, items.EcholocationRing);
    echoring.worn_since = state.ticks;

    state.player = placeMob(alloc, &mobs.PlayerTemplate, coord, .{ .phase = .Hunt });
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
        preferred_x = utils.saturating_sub(parent_con_abs.x, child_con.x);
        preferred_y = utils.saturating_sub(parent_con_abs.y, child_con.y);
    } else if (parent.prefab) |pafab| {
        const con = pafab.connectorFor(d) orelse return null;
        preferred_x = parent.rect.start.x + con.x;
        preferred_y = parent.rect.start.y + con.y;
    } else if (fab) |chfab| {
        const con = chfab.connectorFor(d.opposite()) orelse return null;
        preferred_x = utils.saturating_sub(parent.rect.start.x, con.x);
        preferred_y = utils.saturating_sub(parent.rect.start.y, con.y);
    }

    return switch (d) {
        .North => Rect{
            .start = Coord.new2(parent.rect.start.z, preferred_x, utils.saturating_sub(parent.rect.start.y, height + distance)),
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
            .start = Coord.new2(parent.rect.start.z, utils.saturating_sub(parent.rect.start.x, width + distance), preferred_y),
            .width = width,
            .height = height,
        },
        else => @panic("unimplemented"),
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

fn roomIntersects(
    rooms: *const Room.ArrayList,
    room: *const Room,
    ignore: ?*const Room,
    ignore2: ?*const Room,
    ign_c: bool,
) bool {
    return if (findIntersectingRoom(rooms, room, ignore, ignore2, ign_c)) |r| true else false;
}

fn excavatePrefab(
    room: *const Room,
    fab: *const Prefab,
    allocator: *mem.Allocator,
    startx: usize,
    starty: usize,
) void {
    // Generate loot items.
    //
    var loot_item1: ItemTemplate = undefined;
    var loot_item2: ItemTemplate = undefined;
    var rare_loot_item: ItemTemplate = undefined;
    {
        // FIXME: generate this once at comptime.
        var item_weights: [items.ITEM_DROPS.len]usize = undefined;
        for (items.ITEM_DROPS) |item, i| item_weights[i] = item.w;

        loot_item1 = _chooseLootItem(&item_weights, minmax(usize, 30, 100));
        loot_item2 = _chooseLootItem(&item_weights, minmax(usize, 30, 100));
        rare_loot_item = _chooseLootItem(&item_weights, minmax(usize, 0, 40));
    }

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
                .Floor,
                .Loot1,
                .Loot2,
                .RareLoot,
                => .Floor,
                .Water => .Water,
                .Lava => .Lava,
            };
            if (tt) |_tt| state.dungeon.at(rc).type = _tt;

            switch (fab.content[y][x]) {
                .Window => state.dungeon.at(rc).material = &materials.Glass,
                .LevelFeature => |l| (Configs[room.rect.start.z].level_features[l].?)(l, rc, room, fab, allocator),
                .Feature => |feature_id| {
                    if (fab.features[feature_id]) |feature| {
                        switch (feature) {
                            .Potion => |pid| {
                                if (utils.findById(&items.POTIONS, pid)) |potion_i| {
                                    const potion_o = _createItem(Potion, items.POTIONS[potion_i]);
                                    state.dungeon.itemsAt(rc).append(Item{ .Potion = potion_o }) catch unreachable;
                                } else {
                                    std.log.err(
                                        "{}: Couldn't load potion {}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(pid) },
                                    );
                                }
                            },
                            .Prop => |pid| {
                                if (utils.findById(surfaces.props.items, pid)) |prop| {
                                    _ = placeProp(rc, &surfaces.props.items[prop]);
                                } else {
                                    std.log.err(
                                        "{}: Couldn't load prop {}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(pid) },
                                    );
                                }
                            },
                            .Machine => |mid| {
                                if (utils.findById(&surfaces.MACHINES, mid.id)) |mach| {
                                    _place_machine(rc, &surfaces.MACHINES[mach]);
                                    const machine = state.dungeon.at(rc).surface.?.Machine;
                                    for (mid.points.constSlice()) |point, i| {
                                        const adj_point = Coord.new2(
                                            room.rect.start.z,
                                            point.x + room.rect.start.x + startx,
                                            point.y + room.rect.start.y + starty,
                                        );
                                        machine.areas.append(adj_point) catch unreachable;
                                    }
                                } else {
                                    std.log.err(
                                        "{}: Couldn't load machine {}, skipping.",
                                        .{ fab.name.constSlice(), utils.used(mid.id) },
                                    );
                                }
                            },
                        }
                    } else {
                        std.log.err(
                            "{}: Feature '{c}' not present, skipping.",
                            .{ fab.name.constSlice(), feature_id },
                        );
                    }
                },
                .LockedDoor => placeDoor(rc, true),
                .Door => placeDoor(rc, false),
                .Brazier => _place_machine(rc, Configs[room.rect.start.z].light),
                .Bars => {
                    const p_ind = utils.findById(surfaces.props.items, Configs[room.rect.start.z].bars);
                    _ = placeProp(rc, &surfaces.props.items[p_ind.?]);
                },
                .Loot1 => state.dungeon.itemsAt(rc).append(_createItemFromTemplate(loot_item1)) catch unreachable,
                .Loot2 => state.dungeon.itemsAt(rc).append(_createItemFromTemplate(loot_item2)) catch unreachable,
                .RareLoot => state.dungeon.itemsAt(rc).append(_createItemFromTemplate(rare_loot_item)) catch unreachable,
                else => {},
            }
        }
    }

    for (fab.mobs) |maybe_mob| {
        if (maybe_mob) |mob_f| {
            if (utils.findById(&mobs.MOBS, mob_f.id)) |mob_template| {
                const coord = Coord.new2(
                    room.rect.start.z,
                    mob_f.spawn_at.x + room.rect.start.x + startx,
                    mob_f.spawn_at.y + room.rect.start.y + starty,
                );

                if (state.dungeon.at(coord).type == .Wall) {
                    std.log.err(
                        "{}: Tried to place mob in wall. (this is a bug.)",
                        .{fab.name.constSlice()},
                    );
                    continue;
                }

                const work_area = Coord.new2(
                    room.rect.start.z,
                    (mob_f.work_at orelse mob_f.spawn_at).x + room.rect.start.x + startx,
                    (mob_f.work_at orelse mob_f.spawn_at).y + room.rect.start.y + starty,
                );

                _ = placeMob(allocator, &mobs.MOBS[mob_template], coord, .{
                    .work_area = work_area,
                });
            } else {
                std.log.err(
                    "{}: Couldn't load mob {}, skipping.",
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
            std.log.err("{}: Couldn't infer type for stockpile! (skipping)", .{fab.name.constSlice()});
        } else {
            state.stockpiles[room.rect.start.z].append(stckpl) catch unreachable;
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
        }) catch unreachable;
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
            std.log.err("{}: Couldn't infer type for input area! (skipping)", .{fab.name.constSlice()});
        } else {
            state.inputs[room.rect.start.z].append(input_stckpl) catch unreachable;
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
pub fn resetLevel(level: usize) void {
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
    alloc: *mem.Allocator,
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
            unreachable;
        }

        pub fn _isWalkable(coord: Coord, opts: state.IsWalkableOptions) bool {
            return state.dungeon.at(coord).type != .Wall;
        }
    };

    const rooms = state.rooms[level].items;
    const base_room = b: while (true) {
        const r = rng.chooseUnweighted(Room, rooms);
        if (r.type != .Corridor) break :b r;
    } else unreachable;
    const point = _f._getWalkablePoint(&base_room.rect);

    // Ensure that all required prefabs were used.
    for (Configs[level].prefabs.constSlice()) |required_fab| {
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

        if (astar.path(point, otherpoint, state.mapgeometry, _f._isWalkable, .{}, alloc)) |p| {
            p.deinit();
        } else {
            return false;
        }
    }

    return true;
}

pub fn placeMoarCorridors(level: usize, alloc: *mem.Allocator) void {
    var newrooms = Room.ArrayList.init(alloc);
    defer newrooms.deinit();

    const rooms = &state.rooms[level];

    var i: usize = 0;
    while (i < rooms.items.len) : (i += 1) {
        const parent = &rooms.items[i];

        child_search: for (rooms.items) |*child, child_i| {
            if (parent.connections > CONNECTIONS_MAX) break;
            if (child.connections > CONNECTIONS_MAX) continue;

            if (child.type == .Corridor) continue;

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

                if (roomIntersects(rooms, &corridor.room, parent, child, false) or
                    roomIntersects(&newrooms, &corridor.room, parent, child, false))
                {
                    continue;
                }

                parent.connections += 1;
                child.connections += 1;

                excavateRect(&corridor.room.rect);
                corridor.markConnectorsAsUsed(parent, child) catch unreachable;
                newrooms.append(corridor.room) catch unreachable;

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

    for (newrooms.items) |new| rooms.append(new) catch unreachable;
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
        else => unreachable,
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
            else => unreachable,
        },
        .fab_connectors = fab_connectors,
    };
}

const SubroomPlacementOptions = struct {
    loot: bool = false
};

fn placeSubroom(s_fabs: *PrefabArrayList, parent: *Room, area: *const Rect, alloc: *mem.Allocator, opts: SubroomPlacementOptions) void {
    for (s_fabs.items) |*subroom| {
        if (!prefabIsValid(parent.rect.start.z, subroom)) {
            continue;
        }

        // Don't allow loot subrooms unless opts.loot==true, and in that case
        // only take loot subrooms.
        if (opts.loot != subroom.is_loot) {
            continue;
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
    allocator: *mem.Allocator,
) void {
    const parent_i = rng.range(usize, 0, rooms.items.len - 1);
    var parent = &rooms.items[parent_i];

    if (parent.connections > CONNECTIONS_MAX) {
        return;
    }

    var fab: ?*Prefab = null;
    var distance = rng.choose(usize, &Configs[level].distances[0], &Configs[level].distances[1]) catch unreachable;
    var child: Room = undefined;
    var side = rng.chooseUnweighted(Direction, &CARDINAL_DIRECTIONS);

    if (rng.onein(Configs[level].prefab_chance)) {
        if (distance == 0) distance += 1;

        fab = choosePrefab(level, n_fabs) orelse return;
        var childrect = attachRect(parent, side, fab.?.width, fab.?.height, distance, fab) orelse return;

        if (roomIntersects(rooms, &Room{ .rect = childrect }, parent, null, false) or
            childrect.overflowsLimit(&LIMIT))
        {
            if (Configs[level].shrink_corridors_to_fit) {
                while (roomIntersects(rooms, &Room{ .rect = childrect }, parent, null, true) or
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
        while (roomIntersects(rooms, &Room{ .rect = childrect }, parent, null, true) or
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
            if (roomIntersects(rooms, &maybe_corridor.room, parent, null, true)) {
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
        cor.markConnectorsAsUsed(parent, &child) catch unreachable;

        // XXX: atchung, don't access <parent> var after this, as appending this
        // may have invalidated that pointer.
        //
        // FIXME: can't we append this along with the child at the end of this
        // function?
        rooms.append(cor.room) catch unreachable;

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
        if (rng.onein(2)) {
            placeSubroom(s_fabs, &child, &Rect{
                .start = Coord.new(0, 0),
                .width = child.rect.width,
                .height = child.rect.height,
            }, allocator, .{
                .loot = rng.onein(3),
            });
        }
    } else if (child.prefab.?.subroom_areas.len > 0) {
        for (child.prefab.?.subroom_areas.constSlice()) |subroom_area| {
            placeSubroom(s_fabs, &child, &subroom_area, allocator, .{
                .loot = rng.onein(5),
            });
        }
    }

    // Use parent's index, as we appended the corridor earlier and that may
    // have invalidated parent's pointer
    child.connections += 1;
    rooms.items[parent_i].connections += 1;

    rooms.append(child) catch unreachable;
}

pub fn placeRandomRooms(
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: *mem.Allocator,
) void {
    var first: ?Room = null;
    const rooms = &state.rooms[level];

    var required = Configs[level].prefabs.constSlice();
    var reqctr: usize = 0;

    while (reqctr < required.len) {
        const fab_name = required[reqctr];
        const fab = Prefab.findPrefabByName(fab_name, n_fabs) orelse {
            std.log.err("Cannot find required prefab {}", .{fab_name});
            return;
        };

        const x = rng.rangeClumping(usize, 1, state.WIDTH - fab.width - 1, 2);
        const y = rng.rangeClumping(usize, 1, state.HEIGHT - fab.height - 1, 2);

        const room = Room{
            .rect = Rect{
                .start = Coord.new2(level, x, y),
                .width = fab.width,
                .height = fab.height,
            },
            .prefab = fab,
        };

        if (roomIntersects(rooms, &room, null, null, false))
            continue;

        if (first == null) first = room;
        fab.used[level] += 1;
        excavatePrefab(&room, fab, allocator, 0, 0);
        rooms.append(room) catch unreachable;

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
        rooms.append(first.?) catch unreachable;
    }

    if (level == PLAYER_STARTING_LEVEL) {
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
    n_fabs: *PrefabArrayList,
    s_fabs: *PrefabArrayList,
    level: usize,
    allocator: *mem.Allocator,
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

        pub fn freeRecursively(self: *Self, alloc: *mem.Allocator) void {
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
            alloc: *mem.Allocator,
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
    grandma_node.splitTree(&failed, &leaves, level, allocator) catch unreachable;
    defer grandma_node.freeRecursively(allocator);

    for (failed.items) |container_node| {
        assert(container_node.group == .Failed);
        var room = Room{ .rect = container_node.rect };
        room.type = .Sideroom;
        container_node.index = rooms.items.len;
        excavateRect(&room.rect);
        rooms.append(room) catch unreachable;
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

        placeSubroom(s_fabs, &room, &Rect{
            .start = Coord.new(0, 0),
            .width = room.rect.width,
            .height = room.rect.height,
        }, allocator, .{ .loot = rng.onein(3) });

        container_node.index = rooms.items.len;
        rooms.append(room) catch unreachable;
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

        fn tryNodeConnection(maplevel: usize, parent: Rect, child: Rect, roomlist: *Room.ArrayList) ?Corridor {
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
                // if (roomIntersects(roomlist, &corridor.room, parent, child, false))
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
                return tryNodeConnection(maplevel, parent.*, child, roomlist);
            }

            if (child_tree.childs[0]) |child|
                if (tryRecursiveNodeConnection(maplevel, parent, child, roomlist)) |c|
                    return c;

            if (child_tree.childs[1]) |child|
                if (tryRecursiveNodeConnection(maplevel, parent, child, roomlist)) |c|
                    return c;

            return null;
        }

        pub fn addCorridors(maplevel: usize, node: *Node, roomlist: *Room.ArrayList) void {
            const childs = node.childs;

            if (childs[0] != null and childs[1] != null) {
                var child1 = &roomlist.items[getRectFromNode(childs[0].?).?].rect;

                if (tryRecursiveNodeConnection(maplevel, child1, childs[1].?, roomlist)) |corridor| {
                    corridor.parent.connections += 1;
                    corridor.child.connections += 1;

                    excavateRect(&corridor.room.rect);
                    roomlist.append(corridor.room) catch unreachable;

                    if (rng.tenin(Configs[maplevel].door_chance)) {
                        if (utils.findPatternMatch(
                            corridor.room.rect.start,
                            &VALID_DOOR_PLACEMENT_PATTERNS,
                        ) != null) {
                            placeDoor(corridor.room.rect.start, false);
                        }
                    }
                }
            }

            if (childs[0]) |child| addCorridors(maplevel, child, roomlist);
            if (childs[1]) |child| addCorridors(maplevel, child, roomlist);
        }
    };

    S.addCorridors(level, &grandma_node, rooms);
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

                    container.items.append(Item{ .Prop = item }) catch unreachable;
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

        const max_items = rng.range(usize, 1, 3);
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

            const t = _chooseLootItem(&item_weights, minmax(usize, 0, 100));
            const item = _createItemFromTemplate(t);
            state.dungeon.itemsAt(item_coord).append(item) catch unreachable;
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

        if (rng.onein(2)) continue;

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

        var trap: Machine = undefined;
        if (rng.onein(4)) {
            trap = surfaces.AlarmTrap;
        } else {
            trap = if (rng.onein(3)) surfaces.PoisonGasTrap else surfaces.ParalysisGasTrap;
            trap = switch (rng.range(usize, 0, 4)) {
                0, 1 => surfaces.ConfusionGasTrap,
                2, 3 => surfaces.ParalysisGasTrap,
                4 => surfaces.PoisonGasTrap,
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
                const p_ind = utils.findById(surfaces.props.items, Configs[room.start.z].vent);
                const prop = placeProp(vent, &surfaces.props.items[p_ind.?]);
                trap.props[num_of_vents] = prop;
                num_of_vents -= 1;
            }
        }
        _place_machine(trap_coord, &trap);
    }
}

pub fn placeMobs(level: usize, alloc: *mem.Allocator) void {
    var squads: usize = Configs[level].patrol_squads;

    while (squads > 0) {
        const room = rng.chooseUnweighted(Room, state.rooms[level].items);

        if (room.prefab) |rfb| if (rfb.noguards) continue;
        if (room.type == .Corridor) continue;

        var patrol_warden: ?*Mob = null;
        const patrol_units = rng.range(usize, 3, 4);

        var placed_units: usize = 0;
        var y: usize = room.rect.start.y;
        while (y < room.rect.end().y and placed_units < patrol_units) : (y += 1) {
            var x: usize = room.rect.start.x;
            while (x < room.rect.end().x and placed_units < patrol_units) : (x += 1) {
                const coord = Coord.new2(level, x, y);
                if (!isTileAvailable(coord)) continue;

                const guard = placeMob(alloc, &mobs.PatrolTemplate, coord, .{});
                if (patrol_warden) |warden| {
                    warden.squad_members.append(guard) catch unreachable;
                } else {
                    guard.base_strength += 2;
                    patrol_warden = guard;
                }

                placed_units += 1;
            }
        }

        if (placed_units > 0) squads -= 1;
    }

    for (state.rooms[level].items) |room| {
        if (room.prefab) |rfb| if (rfb.noguards) continue;
        if (room.type == .Corridor) continue;
        if (room.rect.height * room.rect.width < 25) continue;

        for (Configs[level].mob_options.data) |mob| {
            if (rng.tenin(mob.chance)) {
                var tries: usize = 100;
                while (tries > 0) : (tries -= 1) {
                    const post_coord = room.rect.randomCoord();
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
    if (Configs[room.rect.start.z].no_lights) return;
    if (room.prefab) |rfb| if (rfb.nolights) return;

    var lights: usize = 0;
    var lights_needed = rng.rangeClumping(usize, 0, 4, 2);
    var light_tries: usize = rng.range(usize, 0, 50);
    while (light_tries > 0 and lights < lights_needed) : (light_tries -= 1) {
        const coord = randomWallCoord(&room.rect, light_tries);

        if (state.dungeon.at(coord).type != .Wall or
            state.dungeon.at(coord).surface != null or
            utils.findPatternMatch(coord, &VALID_LIGHT_PLACEMENT_PATTERNS) == null or
            state.dungeon.neighboringMachines(coord) > 0)
            continue; // invalid coord

        var brazier = Configs[room.rect.start.z].light.*;

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
    for (state.rooms[level].items) |room| {
        const rect = room.rect;

        // Don't fill small rooms or corridors.
        if ((rect.width * rect.height) < 16 or
            room.type == .Corridor or
            room.type == .Sideroom)
        {
            continue;
        }

        placeLights(&room);

        if (room.prefab != null or room.has_subroom) continue;
        if (rng.tenin(25)) continue;

        const Range = struct { from: Coord, to: Coord };
        const rect_end = rect.end();

        const ranges = [_]Range{
            .{ .from = Coord.new(rect.start.x + 1, rect.start.y), .to = Coord.new(rect_end.x - 2, rect.start.y) }, // top
            .{ .from = Coord.new(rect.start.x + 1, rect_end.y - 1), .to = Coord.new(rect_end.x - 2, rect_end.y - 1) }, // bottom
            .{ .from = Coord.new(rect.start.x, rect.start.y + 1), .to = Coord.new(rect.start.x, rect_end.y - 2) }, // left
            .{ .from = Coord.new(rect_end.x - 1, rect.start.y + 1), .to = Coord.new(rect_end.x - 1, rect_end.y - 2) }, // left
        };

        var statues: usize = 0;
        var props: usize = 0;
        var capacity: usize = 0;
        var levers: usize = 0;
        var posters: usize = 0;

        var tries = math.sqrt(rect.width * rect.height) * 5;
        while (tries > 0) : (tries -= 1) {
            const range = ranges[tries % ranges.len];
            const x = rng.range(usize, range.from.x, range.to.x);
            const y = rng.range(usize, range.from.y, range.to.y);
            const coord = Coord.new2(rect.start.z, x, y);

            if (!isTileAvailable(coord) or
                utils.findPatternMatch(coord, &VALID_FEATURE_TILE_PATTERNS) == null)
                continue;

            switch (rng.range(usize, 1, 4)) {
                1 => {
                    if (Configs[level].allow_statues and statues < 3 and rng.onein(3)) {
                        const statue = rng.chooseUnweighted(mobs.MobTemplate, &mobs.STATUES);
                        _ = placeMob(alloc, &statue, coord, .{});
                        statues += 1;
                    } else if (props < 3) {
                        const prop = rng.chooseUnweighted(Prop, Configs[level].props.*);
                        _ = placeProp(coord, &prop);
                        props += 1;
                    }
                },
                2 => {
                    if (capacity < (math.sqrt(rect.width * rect.height) * 4)) {
                        var cont = rng.chooseUnweighted(Container, Configs[level].containers);
                        placeContainer(coord, &cont);
                        capacity += cont.capacity;
                    }
                },
                3 => {
                    if (levers < 1 and room.has_subroom) {
                        _place_machine(coord, &surfaces.RestrictedMachinesOpenLever);
                        levers += 1;
                    }
                },
                4 => {
                    if ((rect.width * rect.height) > 25 and posters < 2) {
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
    const stair_dst = &surfaces.props.items[utils.findById(surfaces.props.items, "stair_dst").?];

    if (level == 0) return;

    const rooms = state.rooms[level].items;

    var room_i: usize = 0;
    var placed: usize = 0;

    while (placed < 3 and room_i < rooms.len) : (room_i += 1) {
        const room = &rooms[room_i];

        // Don't place stairs in narrow rooms where it's impossible to avoid.
        if (room.rect.width == 1 or room.rect.height == 1) continue;

        var tries: usize = 5;
        tries: while (tries > 0) : (tries -= 1) {
            const rand = room.rect.randomCoord();
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
                _place_machine(current, &surfaces.StairUp);
                _ = placeProp(above, stair_dst);

                placed += 1;
                break :tries;
            }
        }
    }
}

pub fn placeBlobs(level: usize) void {
    var grid: [WIDTH][HEIGHT]usize = undefined;
    const blob_configs = Configs[level].blobs;
    for (blob_configs) |cfg| {
        var i: usize = rng.range(usize, cfg.number.min, cfg.number.max);
        while (i > 0) : (i -= 1) {
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

            const start_y = rng.range(usize, 1, HEIGHT - blob.height - 1);
            const start_x = rng.range(usize, 1, WIDTH - blob.width - 1);
            const start = Coord.new2(level, start_x, start_y);

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
                    const coord = Coord.new2(level, map_x, map_y).add(start);
                    if (grid[blob_x][blob_y] != 0)
                        state.dungeon.at(coord).type = cfg.type;
                }
            }
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

fn levelFeaturePrisonersMaybe(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    if (rng.onein(2)) levelFeaturePrisoners(c, coord, room, prefab, alloc);
}

fn levelFeaturePrisoners(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const prisoner_t = rng.chooseUnweighted(mobs.MobTemplate, &mobs.PRISONERS);
    const prisoner = placeMob(alloc, &prisoner_t, coord, .{});
    prisoner.prisoner_status = Prisoner{ .of = .Necromancer };

    for (&CARDINAL_DIRECTIONS) |direction|
        if (coord.move(direction, state.mapgeometry)) |neighbor| {
            //if (direction == .North) unreachable;
            if (state.dungeon.at(neighbor).surface) |surface| {
                if (meta.activeTag(surface) == .Prop and surface.Prop.holder) {
                    prisoner.prisoner_status.?.held_by = .{ .Prop = surface.Prop };
                    break;
                }
            }
        };
}

fn levelFeaturePotions(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const potion = rng.chooseUnweighted(Potion, &items.POTIONS);
    state.potions.append(potion) catch unreachable;
    state.dungeon.itemsAt(coord).append(
        Item{ .Potion = state.potions.last().? },
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
        placeContainer(coord, &surfaces.VOreCrate);
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

// Randomly place an iron ore. Randomly, create a container and
// fill it up halfway; otherwise, place only one item on the ground.
fn levelFeatureIronOres(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const ores = [_]Material{materials.Hematite};
    var using_container: ?*Container = null;

    if ((room.rect.start.x % 2) == 0) {
        placeContainer(coord, &surfaces.VOreCrate);
        using_container = state.dungeon.at(coord).surface.?.Container;
    }

    var placed: usize = if (using_container == null) 2 else rng.rangeClumping(usize, 3, 8, 2);
    while (placed > 0) : (placed -= 1) {
        const mat = &ores[rng.range(usize, 0, ores.len - 1)];

        const item = Item{ .Boulder = mat };
        if (using_container) |container| {
            container.items.append(item) catch unreachable;
            if (placed == 0) break;
        } else {
            state.dungeon.itemsAt(coord).append(item) catch unreachable;
        }
    }
}

// Randomly place an metal ingot.
fn levelFeatureMetals(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const metals = [_]*const Material{&materials.Iron};
    const mat = rng.chooseUnweighted(*const Material, metals[0..]);
    state.dungeon.itemsAt(coord).append(Item{ .Boulder = mat }) catch unreachable;
}

// Randomly place a random metal prop.
fn levelFeatureMetalProducts(c: usize, coord: Coord, room: *const Room, prefab: *const Prefab, alloc: *mem.Allocator) void {
    const prop_ids = [_][]const u8{"chain"};
    const prop_id = prop_ids[rng.range(usize, 0, prop_ids.len - 1)];
    const prop_idx = utils.findById(surfaces.props.items, prop_id).?;
    state.dungeon.itemsAt(coord).append(
        Item{ .Prop = &surfaces.props.items[prop_idx] },
    ) catch unreachable;
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

    connections: usize = 0,

    pub const RoomType = enum { Corridor, Room, Sideroom };

    pub const ArrayList = std.ArrayList(Room);
};

pub const Prefab = struct {
    subroom: bool = false,
    invisible: bool = false,
    restriction: usize = 1,
    priority: usize = 0,
    is_loot: bool = false, // Is this a loot prefab?
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
    prisons: StackBuffer(Rect, 8) = StackBuffer(Rect, 8).init(null),
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
        Floor,
        Connection,
        Water,
        Lava,
        Bars,
        Feature: u8,
        LevelFeature: usize,
        Loot1,
        Loot2,
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
                    } else if (mem.eql(u8, key, "priority")) {
                        if (val.len == 0) return error.ExpectedMetadataValue;
                        f.priority = std.fmt.parseInt(usize, val, 0) catch |_| return error.InvalidMetadataValue;
                    } else if (mem.eql(u8, key, "noguards")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.noguards = true;
                    } else if (mem.eql(u8, key, "nolights")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.nolights = true;
                    } else if (mem.eql(u8, key, "notraps")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.notraps = true;
                    } else if (mem.eql(u8, key, "is_loot")) {
                        if (val.len != 0) return error.UnexpectedMetadataValue;
                        f.is_loot = true;
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
                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.prisons.append(.{ .start = rect_start, .width = width, .height = height }) catch |_| return error.TooManyPrisons;
                    } else if (mem.eql(u8, key, "subroom_area")) {
                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.subroom_areas.append(.{ .start = rect_start, .width = width, .height = height }) catch |_| return error.TooManySubrooms;
                    } else if (mem.eql(u8, key, "stockpile")) {
                        if (f.stockpile) |_| return error.StockpileAlreadyDefined;

                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.stockpile = .{ .start = rect_start, .width = width, .height = height };
                    } else if (mem.eql(u8, key, "output")) {
                        if (f.output) |_| return error.OutputAreaAlreadyDefined;

                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.output = .{ .start = rect_start, .width = width, .height = height };
                    } else if (mem.eql(u8, key, "input")) {
                        if (f.input) |_| return error.InputAreaAlreadyDefined;

                        var rect_start = Coord.new(0, 0);
                        var width: usize = 0;
                        var height: usize = 0;

                        var rect_start_tokens = mem.tokenize(val, ",");
                        const rect_start_str_a = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        const rect_start_str_b = rect_start_tokens.next() orelse return error.InvalidMetadataValue;
                        rect_start.x = std.fmt.parseInt(usize, rect_start_str_a, 0) catch |_| return error.InvalidMetadataValue;
                        rect_start.y = std.fmt.parseInt(usize, rect_start_str_b, 0) catch |_| return error.InvalidMetadataValue;

                        const width_str = words.next() orelse return error.ExpectedMetadataValue;
                        const height_str = words.next() orelse return error.ExpectedMetadataValue;
                        width = std.fmt.parseInt(usize, width_str, 0) catch |_| return error.InvalidMetadataValue;
                        height = std.fmt.parseInt(usize, height_str, 0) catch |_| return error.InvalidMetadataValue;

                        f.input = .{ .start = rect_start, .width = width, .height = height };
                    }
                },
                '@' => {
                    var words = mem.tokenize(line, " ");
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
                                var coord_tokens = mem.tokenize(word, ",");
                                const coord_str_a = coord_tokens.next() orelse return error.InvalidMetadataValue;
                                const coord_str_b = coord_tokens.next() orelse return error.InvalidMetadataValue;
                                coord.x = std.fmt.parseInt(usize, coord_str_a, 0) catch |_| return error.InvalidMetadataValue;
                                coord.y = std.fmt.parseInt(usize, coord_str_b, 0) catch |_| return error.InvalidMetadataValue;
                                points.append(coord) catch unreachable;
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
                            '&' => .Window,
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
                            'L' => .Loot1,
                            'X' => .Loot2,
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
        return (a.priority > b.priority) or (a.height * a.width) > (b.height * b.width);
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
            std.log.info("{}: Couldn't load prefab: {}", .{ fab_file.name, msg });
            continue;
        };
    }

    std.sort.insertionSort(Prefab, s_fabs.items, {}, Prefab.lesserThan);
}

pub const LevelConfig = struct {
    prefabs: RPBuf = RPBuf.init(null),
    distances: [2][10]usize = [2][10]usize{
        .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
    },
    shrink_corridors_to_fit: bool = true,
    prefab_chance: usize,

    mapgen_func: fn (*PrefabArrayList, *PrefabArrayList, usize, *mem.Allocator) void = placeRandomRooms,

    // Determines the number of iterations used by the mapgen algorithm.
    //
    // On placeRandomRooms: try mapgen_iters times to place a rooms randomly.
    // On placeBSPRooms:    try mapgen_iters times to split a BSP node.
    mapgen_iters: usize,

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
    tiletype: TileType = .Wall,
    material: *const Material = &materials.Concrete,
    light: *const Machine = &surfaces.Brazier,
    door: *const Machine = &surfaces.NormalDoor,
    vent: []const u8 = "gas_vent",
    bars: []const u8 = "iron_bars",
    props: *[]const Prop = &surfaces.statue_props.items,
    containers: []const Container = &[_]Container{
        surfaces.Bin,
        surfaces.Barrel,
        surfaces.Cabinet,
        //surfaces.Chest,
    },
    utility_items: *[]const Prop = &surfaces.prison_item_props.items,
    allow_statues: bool = true,
    door_chance: usize = 30,
    allow_corridors: bool = true,

    blobs: []const BlobConfig = &[_]BlobConfig{},

    pub const RPBuf = StackBuffer([]const u8, 8);
    pub const MCBuf = StackBuffer(MobConfig, 3);
    pub const LevelFeatureFunc = fn (usize, Coord, *const Room, *const Prefab, *mem.Allocator) void;

    pub const MobConfig = struct {
        chance: usize, // Ten in <chance>
        template: *const mobs.MobTemplate,
    };

    pub const BlobConfig = struct {
        number: MinMax(usize),
        type: TileType,
        min_blob_width: MinMax(usize),
        min_blob_height: MinMax(usize),
        max_blob_width: MinMax(usize),
        max_blob_height: MinMax(usize),
        ca_rounds: usize,
        ca_percent_seeded: usize,
        ca_birth_params: *const [9]u8,
        ca_survival_params: *const [9]u8,
    };
};

pub const Configs = [LEVELS]LevelConfig{
    .{
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "ENT_start",
            "PRI_power",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 5, 9, 1, 0, 0, 0, 0, 0, 0, 0 },
        },
        .prefab_chance = 2,
        .mapgen_iters = 1049,

        .patrol_squads = 2,

        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeaturePrisoners,
            levelFeaturePrisonersMaybe,
            null,
            null,
        },
    },
    .{
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "VLT_power",
        }),
        .prefab_chance = 1000, // No prefabs for VLT
        .mapgen_func = placeBSPRooms,
        .mapgen_iters = 2048,
        .min_room_width = 8,
        .min_room_height = 5,
        .max_room_width = 10,
        .max_room_height = 6,

        .patrol_squads = 2,
        .mob_options = LevelConfig.MCBuf.init(&[_]LevelConfig.MobConfig{
            .{ .chance = 15, .template = &mobs.GuardTemplate },
            .{ .chance = 30, .template = &mobs.WatcherTemplate },
            .{ .chance = 55, .template = &mobs.WardenTemplate },
        }),

        .allow_statues = false,
        .door_chance = 10,
        .door = &surfaces.VaultDoor,

        .props = &surfaces.vault_props.items,
        //.containers = &[_]Container{surfaces.Chest},
    },
    .{
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "PRI_power",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 2,
        .mapgen_iters = 2048,
        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeaturePrisoners,
            levelFeaturePrisonersMaybe,
            null,
            null,
        },

        .patrol_squads = 1,

        .blobs = &[_]LevelConfig.BlobConfig{
            .{
                .number = MinMax(usize){ .min = 6, .max = 9 },
                .type = .Floor,
                .min_blob_width = MinMax(usize){ .min = 6, .max = 8 },
                .min_blob_height = MinMax(usize){ .min = 6, .max = 8 },
                .max_blob_width = MinMax(usize){ .min = 16, .max = 19 },
                .max_blob_height = MinMax(usize){ .min = 16, .max = 19 },
                .ca_rounds = 5,
                .ca_percent_seeded = 55,
                .ca_birth_params = "ffffffttt",
                .ca_survival_params = "ffffttttt",
            },
        },
    },
    .{
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "LAB_power",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 9, 2, 1, 1, 1, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 100, // No prefabs for LAB
        .mapgen_iters = 2048,
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

        .door_chance = 10,
        .material = &materials.Dobalene,
        .light = &surfaces.Lamp,
        .vent = "lab_gas_vent",
        .bars = "titanium_bars",
        .door = &surfaces.LabDoor,
        .props = &surfaces.laboratory_props.items,
        //.containers = &[_]Container{ surfaces.Chest, surfaces.LabCabinet },
        .containers = &[_]Container{surfaces.LabCabinet},
        .utility_items = &surfaces.laboratory_item_props.items,

        .allow_statues = false,
    },
    .{
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "PRI_power",
            "PRI_insurgency",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 3, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 2,
        .mapgen_iters = 512,
        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeaturePrisoners,
            levelFeaturePrisonersMaybe,
            null,
            null,
        },

        .patrol_squads = 2,
    },
    .{
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "PRI_start",
            "PRI_power",
        }),
        .distances = [2][10]usize{
            .{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
            .{ 5, 9, 4, 3, 2, 1, 0, 0, 0, 0 },
        },
        .prefab_chance = 2,
        .mapgen_iters = 512,
        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeaturePrisoners,
            levelFeaturePrisonersMaybe,
            null,
            null,
        },

        .patrol_squads = 2,
    },
    .{
        .prefabs = LevelConfig.RPBuf.init(&[_][]const u8{
            "SMI_chain_press",
            "SMI_blast_furnace",
            "SMI_stockpiles",
            "SMI_power",
            "SMI_elevator",
        }),
        .distances = [2][10]usize{
            .{ 5, 6, 7, 8, 9, 10, 11, 12, 13, 14 },
            .{ 1, 1, 2, 3, 4, 5, 6, 7, 8, 9 },
        },
        .shrink_corridors_to_fit = false,
        .prefab_chance = 1,
        .mapgen_iters = 1049,

        .level_features = [_]?LevelConfig.LevelFeatureFunc{
            levelFeatureIronOres,
            levelFeatureMetals,
            levelFeatureMetalProducts,
            null,
        },

        .patrol_squads = 3,
        .mob_options = LevelConfig.MCBuf.init(&[_]LevelConfig.MobConfig{
            .{ .chance = 10, .template = &mobs.WatcherTemplate },
            .{ .chance = 30, .template = &mobs.HaulerTemplate },
            .{ .chance = 56, .template = &mobs.GuardTemplate },
        }),

        .material = &materials.Basalt,
        .tiletype = .Floor,

        .allow_statues = false,
        .door_chance = 0,
        .allow_corridors = false,

        .blobs = &[_]LevelConfig.BlobConfig{
            .{
                .number = MinMax(usize){ .min = 6, .max = 8 },
                .type = .Wall,
                .min_blob_width = MinMax(usize){ .min = 7, .max = 8 },
                .min_blob_height = MinMax(usize){ .min = 7, .max = 8 },
                .max_blob_width = MinMax(usize){ .min = 10, .max = 15 },
                .max_blob_height = MinMax(usize){ .min = 9, .max = 15 },
                .ca_rounds = 5,
                .ca_percent_seeded = 55,
                .ca_birth_params = "ffffffttt",
                .ca_survival_params = "ffffttttt",
            },
            .{
                .number = MinMax(usize){ .min = 5, .max = 7 },
                .type = .Lava,
                .min_blob_width = MinMax(usize){ .min = 6, .max = 8 },
                .min_blob_height = MinMax(usize){ .min = 6, .max = 8 },
                .max_blob_width = MinMax(usize){ .min = 10, .max = 14 },
                .max_blob_height = MinMax(usize){ .min = 9, .max = 14 },
                .ca_rounds = 5,
                .ca_percent_seeded = 55,
                .ca_birth_params = "ffffftttt",
                .ca_survival_params = "ffffttttt",
            },
        },
    },
};
