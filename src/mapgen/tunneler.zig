const std = @import("std");
const mem = std.mem;
const math = std.math;
// const meta = std.meta;
const assert = std.debug.assert;

const err = @import("../err.zig");
const rng = @import("../rng.zig");
const state = @import("../state.zig");
const types = @import("../types.zig");

const LinkedList = @import("../list.zig").LinkedList;
const StackBuffer = @import("../buffer.zig").StackBuffer;

const Coord = types.Coord;
const Rect = types.Rect;
const Direction = types.Direction;

const mapgen = @import("../mapgen.zig");
const Room = mapgen.Room;
const Prefab = mapgen.Prefab;
const Configs = &mapgen.Configs;

const DIRECTIONS = types.DIRECTIONS;
const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;
const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;
const LIMIT = mapgen.LIMIT;

pub const Ctx = struct {
    level: usize,
    roomies: std.ArrayList(Roomie),
    tunnelers: Tunneler.List,
    extras: std.ArrayList(Roomie),
    junctions: std.ArrayList(Junction),
    opts: TunnelerOptions,

    pub fn doesJunctionContain(self: *Ctx, t: *const Tunneler, coord: Coord) bool {
        const rect = coord.asRect();
        return for (self.junctions.items) |junction| {
            if (junction.t1 == t or junction.t2 == t or junction.rect.intersects(&rect, 0))
                break true;
        } else false;
    }

    pub fn findIntersectingJunction(self: *Ctx, rect: Rect) ?Junction {
        var why_do_i_need_a_ptr = rect;
        return for (self.junctions.items) |junction| {
            if (junction.t1.is_eviscerated or junction.t2.is_eviscerated)
                continue;
            if (junction.rect.intersects(&why_do_i_need_a_ptr, 1))
                break junction;
        } else null;
    }

    pub fn findIntersectingTunnel(self: *Ctx, rect: Rect, ign1: ?*Tunneler, ign2: ?*Tunneler) ?*Tunneler {
        var tunnelers = self.tunnelers.iterator();
        return while (tunnelers.next()) |tunneler| {
            if (ign1) |ign1_| if (tunneler == ign1_) continue;
            if (ign2) |ign2_| if (tunneler == ign2_) continue;
            if (tunneler.rect.intersects(&rect, 1)) break tunneler;
        } else null;
    }

    pub fn killThemAll(self: *Ctx) void {
        var tunnelers = self.tunnelers.iterator();
        while (tunnelers.next()) |tunneler| {
            tunneler.is_dead = true;
            if (!tunneler.is_eviscerated and tunneler.corridorLength() > 0) {
                assert(tunneler.rect.width > 0 and tunneler.rect.height > 0);
                state.rooms[self.level].append(.{ .type = .Corridor, .rect = tunneler.rect }) catch err.wat();

                // // Create receiving staircase
                // const cw = tunneler.corridorWidth();
                // if (tunneler.parent == null) {
                //     const stairloc = switch (tunneler.direction) {
                //         .North => Coord.new2(self.level, tunneler.rect.start.x + cw / 2, tunneler.rect.start.y - 1),
                //         .South => Coord.new2(self.level, tunneler.rect.start.x + cw / 2, tunneler.rect.end().y),
                //         .East => Coord.new2(self.level, tunneler.rect.start.x - 1, tunneler.rect.start.y + cw / 2),
                //         .West => Coord.new2(self.level, tunneler.rect.end().x, tunneler.rect.start.y + cw / 2),
                //         else => unreachable,
                //     };
                //     state.dungeon.at(stairloc).surface = .{ .Stair = null };
                //     state.dungeon.at(stairloc).type = .Floor;
                //     state.dungeon.receive_stairs[self.level].append(stairloc) catch err.wat();
                // }
            }
        }
    }

    // Dragons be here: we're modifying a container while iterating over it.
    //
    pub fn tryAddingRoomies(self: *Ctx, level: usize, cur_gen: usize) void {
        var i: usize = 0;
        while (i < self.roomies.items.len) {
            const roomie = &self.roomies.items[i];
            var room = Room{ .rect = roomie.rect };

            if (roomie.generation > cur_gen or
                self.findIntersectingTunnel(roomie.rect, roomie.parent, null) != null)
            {
                i += 1;
                continue;
            }

            if (roomie.parent.is_eviscerated or
                roomie.parent.child_rooms >= self.opts.max_room_per_tunnel or
                self.findIntersectingJunction(roomie.rect) != null or
                mapgen.isRoomInvalid(&state.rooms[level], &room, null, null, false))
            {
                _ = self.roomies.swapRemove(i);
                continue;
            }

            var prefab: ?*Prefab = null;
            if (rng.percent(Configs[level].prefab_chance)) {
                if (mapgen.choosePrefab(level, &mapgen.n_fabs, .{
                    .t_only = true,
                    .t_orientation = roomie.orientation,
                    .max_h = roomie.rect.height,
                    .max_w = roomie.rect.width,
                })) |fab| {
                    prefab = fab;

                    switch (roomie.orientation) {
                        .North => roomie.rect.start.y += (roomie.rect.height - fab.height),
                        .West => roomie.rect.start.x += (roomie.rect.width - fab.width),
                        .South, .East => {},
                        else => unreachable,
                    }

                    roomie.rect.width = fab.width;
                    roomie.rect.height = fab.height;

                    if (fab.tunneler_inset) switch (roomie.orientation) {
                        .North => roomie.rect.start.y += 1,
                        .South => roomie.rect.start.y -= 1,
                        .East => roomie.rect.start.x -= 1,
                        .West => roomie.rect.start.x += 1,
                        else => unreachable,
                    };

                    room = Room{ .rect = roomie.rect };
                } else if (self.opts.force_prefabs) {
                    i += 1;
                    continue;
                }
            }

            if (prefab) |fab| {
                room.prefab = fab;
                roomie.door = Roomie.getRandomDoorCoord(room, roomie.parent) orelse continue;
                mapgen.excavatePrefab(&room, fab, state.GPA.allocator(), 0, 0);
                fab.incrementRecord(level);
            } else {
                mapgen.excavateRect(&roomie.rect);
            }

            if (prefab == null or !prefab.?.tunneler_inset) {
                mapgen.placeDoor(roomie.door, false);
                room.connections.append(.{ .room = roomie.parent.rect.start, .door = roomie.door }) catch err.wat();
            } else if (prefab.?.tunneler_inset) {
                room.is_extension_room = true;
                room.connections.append(.{ .room = roomie.parent.rect.start, .door = null }) catch err.wat();
            }

            if (prefab == null and rng.percent(Configs[level].subroom_chance)) {
                _ = mapgen.placeSubroom(&room, &Rect{
                    .start = Coord.new(0, 0),
                    .width = room.rect.width,
                    .height = room.rect.height,
                }, state.GPA.allocator(), .{});
            }

            state.rooms[level].append(room) catch err.wat();

            roomie.parent.child_rooms += 1;
            roomie.parent.roomie_last_born_at = math.max(roomie.parent.roomie_last_born_at, roomie.born_at);
            _ = self.roomies.swapRemove(i);
        }
    }

    pub fn tryAddingExtraRooms(self: *Ctx, level: usize) void {
        if (!self.opts.add_extra_rooms)
            return;

        for (self.extras.items) |extra| {
            const parent = extra.parent;

            if (parent.is_eviscerated or extra.born_at > parent.corridorLength())
                continue;

            var new = Room{ .rect = Rect{ .start = extra.rect.start, .width = 0, .height = 0 } };

            while (new.rect.width <= Configs[level].max_room_width and
                !mapgen.isRoomInvalid(&state.rooms[level], &new, null, null, false))
            {
                new.rect.width += 1;
            }
            new.rect.width -|= 1;

            while (new.rect.height <= Configs[level].max_room_height and
                !mapgen.isRoomInvalid(&state.rooms[level], &new, null, null, false))
            {
                new.rect.height += 1;
            }
            new.rect.height -|= 1;

            if (new.rect.width < Configs[level].min_room_width or
                new.rect.height < Configs[level].min_room_height)
            {
                continue;
            }

            const too_far = switch (extra.parent.direction) {
                .North, .South => if (new.rect.start.x < parent.rect.start.x)
                    Coord.new2(level, parent.rect.start.x, new.rect.start.y).distance(new.rect.start) > new.rect.width + 1
                else
                    extra.parent.rect.start.distance(new.rect.start) > parent.rect.width + 1,
                .East, .West => if (new.rect.start.y < parent.rect.start.y)
                    Coord.new2(level, new.rect.start.x, parent.rect.start.y).distance(new.rect.start) > new.rect.height + 1
                else
                    extra.parent.rect.start.distance(new.rect.start) > parent.rect.height + 1,
                else => unreachable,
            };

            if (!too_far) {
                if (Roomie.getRandomDoorCoord(new, parent)) |door| {
                    new.connections.append(.{ .room = parent.rect.start, .door = door }) catch err.wat();
                    if (rng.percent(Configs[level].subroom_chance)) {
                        _ = mapgen.placeSubroom(&new, &Rect{
                            .start = Coord.new(0, 0),
                            .width = new.rect.width,
                            .height = new.rect.height,
                        }, state.GPA.allocator(), .{});
                    }
                    mapgen.excavateRect(&new.rect);
                    mapgen.placeDoor(door, false);
                    state.rooms[level].append(new) catch err.wat();
                }
            }
        }
    }

    // Remove and fill in empty & childless corridors
    pub fn removeChildlessTunnelers(self: *Ctx, require_dead: bool) void {
        var changes_were_made = true;
        while (changes_were_made) {
            changes_were_made = false;

            var tunnelers = self.tunnelers.iterator();
            while (tunnelers.next()) |tunneler| {
                if (!tunneler.is_eviscerated and tunneler.isChildless(require_dead)) {
                    mapgen.fillRect(&tunneler.rect, .Wall);
                    tunneler.rect.height = 0;
                    tunneler.rect.width = 0;
                    for (tunneler.child_corridors.constSlice()) |child| {
                        mapgen.fillRect(&child.rect, .Wall);
                        child.rect.height = 0;
                        child.rect.width = 0;
                        child.is_eviscerated = true;
                    }
                    tunneler.is_eviscerated = true;
                    changes_were_made = true;
                }
            }
        }
    }

    pub fn excavateJunctions(self: *Ctx) void {
        const level = self.tunnelers.first().?.rect.start.z;

        for (self.junctions.items) |junction| {
            const room = Room{ .rect = junction.rect };
            if (junction.t1.is_eviscerated or junction.t2.is_eviscerated or
                //self.findIntersectingTunnel(junction.rect, junction.t1, junction.t2) != null or
                mapgen.isRoomInvalid(&state.rooms[level], &room, null, null, true))
            {
                continue;
            }

            mapgen.excavateRect(&junction.rect);
            // Debug stuff
            // fillRect(&rect, .Lava);
            // var y = junction.rect.start.y;
            // while (y < junction.rect.end().y) : (y += 1) {
            //     var x = junction.rect.start.x;
            //     while (x < junction.rect.end().x) : (x += 1) {
            //         const c = Coord.new2(junction.rect.start.z, x, y);
            //         state.dungeon.at(c).material = &materials.Concrete;
            //     }
            // }

            state.rooms[junction.rect.start.z].append(.{ .type = .Junction, .rect = junction.rect }) catch err.wat();
        }

        self.junctions.clearAndFree();
    }

    pub fn addPlayer(self: *Ctx) void {
        if (self.level == state.PLAYER_STARTING_LEVEL) {
            for (state.rooms[self.level].items) |room| {
                if (room.prefab != null and room.prefab.?.player_position != null) {
                    const player_pos = room.prefab.?.player_position.?;
                    const p = Coord.new2(self.level, room.rect.start.x + player_pos.x, room.rect.start.y + player_pos.y);
                    mapgen.placePlayer(p, state.GPA.allocator());
                    return;
                }
            }
            for (state.rooms[self.level].items) |room| {
                const p = room.rect.randomCoord();
                mapgen.placePlayer(p, state.GPA.allocator());
                return;
            }
            err.bug("Unable to place player anywhere on starting level", .{});
        }
    }
};

pub const Junction = struct {
    rect: Rect,
    t1: *Tunneler,
    t2: *Tunneler,
};

pub const Roomie = struct {
    parent: *Tunneler,
    generation: usize,
    born_at: usize,
    rect: Rect,
    door: Coord,
    orientation: Direction,

    pub fn getRandomDoorCoord(room: Room, parent: *const Tunneler) ?Coord {
        const level = room.rect.start.z;

        const door_x = [_]usize{
            math.max(room.rect.start.x, parent.rect.start.x),
            math.min(room.rect.end().x - 1, parent.rect.end().x - 1),
        };
        const door_y = [_]usize{
            math.max(room.rect.start.y, parent.rect.start.y),
            math.min(room.rect.end().y - 1, parent.rect.end().y - 1),
        };

        switch (parent.direction) {
            .North, .South => {
                if (door_y[1] < door_y[0]) {
                    return null;
                }
                const x = if (room.rect.start.x < parent.rect.start.x) room.rect.end().x else room.rect.start.x - 1;
                const y = rng.range(usize, door_y[0], door_y[1]);
                return Coord.new2(level, x, y);
            },
            .East, .West => {
                if (door_x[1] < door_x[0]) {
                    return null;
                }
                const x = rng.range(usize, door_x[0], door_x[1]);
                const y = if (room.rect.start.y < parent.rect.start.y) room.rect.end().y else room.rect.start.y - 1;
                return Coord.new2(level, x, y);
            },
            else => unreachable,
        }
    }
};

pub const Tunneler = struct {
    rect: Rect,
    direction: Direction,
    is_dead: bool = false,
    is_eviscerated: bool = false,
    is_intersected: bool = false,
    child_corridors: StackBuffer(*Tunneler, 128) = StackBuffer(*Tunneler, 128).init(null),
    child_rooms: usize = 0,
    roomie_last_born_at: usize = 0,
    parent: ?*Self = null,
    generation: usize = 0,
    born_at: usize = 0,
    room_index: usize = 0, // Index in state.rooms[level]. Set in Ctx.killThemAll()

    __prev: ?*Self = null,
    __next: ?*Self = null,

    const Self = @This();
    const AList = std.ArrayList(Self);
    const List = LinkedList(Self);

    pub fn die(self: *Self) void {
        self.is_dead = true;
        // Not done on a per-case basis, because then we'd have to update them
        // if we shrink or destroy a tunnel.
        //
        // state.rooms[self.rect.start.z].append(.{
        //     .type = .Corridor,
        //     .rect = self.rect,
        // }) catch err.wat();
    }

    pub fn advance(self: *Self) void {
        switch (self.direction) {
            .North => {
                self.rect.start.y -= 1;
                self.rect.height += 1;
            },
            .South => {
                self.rect.height += 1;
            },
            .East => {
                self.rect.width += 1;
            },
            .West => {
                self.rect.start.x -= 1;
                self.rect.width += 1;
            },
            else => unreachable,
        }
        mapgen.excavateRect(&self.rect);
    }

    pub fn shrinkTo(self: *Self, new_length: usize) void {
        assert(new_length <= self.corridorLength());

        // debug thing
        mapgen.fillRect(&self.rect, .Wall);

        switch (self.direction) {
            .North => {
                self.rect.start.y += self.rect.height - new_length;
                self.rect.height = new_length;
            },
            .South => {
                self.rect.height = new_length;
            },
            .East => {
                self.rect.width = new_length;
            },
            .West => {
                self.rect.start.x += self.rect.width - new_length;
                self.rect.width = new_length;
            },
            else => unreachable,
        }

        // fillRect(&self.rect, .Water);
        mapgen.excavateRect(&self.rect);

        assert(self.corridorLength() == new_length);
    }

    pub fn createJunction(self: *Self, other: *Self, ctx: *Ctx) void {
        if (!ctx.opts.add_junctions)
            return;

        const level = self.rect.start.z;

        const self_end = switch (self.direction) {
            .North, .West => self.rect.start,
            .East => Coord.new2(level, self.rect.end().x - other.corridorWidth(), self.rect.start.y),
            .South => Coord.new2(level, self.rect.start.x, self.rect.end().y - other.corridorWidth()),
            else => unreachable,
        };
        const height = if (self.direction == .North or self.direction == .South) other.corridorWidth() else self.corridorWidth();
        const width = if (self.direction == .North or self.direction == .South) self.corridorWidth() else other.corridorWidth();

        const rect = Rect{
            .width = width + 2,
            .height = height + 2,
            .start = Coord.new2(
                self.rect.start.z,
                self_end.x - 1,
                self_end.y - 1,
            ),
        };

        // const room = Room{ .rect = rect };
        //if (!isRoomInvalid(&state.rooms[self.rect.start.z], &room, null, null, false)) {
        ctx.junctions.append(.{ .rect = rect, .t1 = self, .t2 = other }) catch err.wat();
        //}
    }

    pub fn isChildless(self: *const Self, require_dead: bool) bool {
        if (self.child_rooms > 0)
            return false;
        if (require_dead and !self.is_dead)
            return false;
        for (self.child_corridors.constSlice()) |child_corridor|
            if (!child_corridor.isChildless(require_dead))
                return false;
        return true;
    }

    pub const CanIntersect = enum { No, Yes, YesIntersect };
    pub fn canAdvance(self: *const Self, ctx: *Ctx) CanIntersect {
        if (self.rect.overflowsLimit(&LIMIT))
            return .No;

        var yes: CanIntersect = .Yes;

        if (self.direction == .East or self.direction == .West) {
            assert(self.rect.height > 0);
            const edgex = if (self.direction == .East) self.rect.end().x - 1 else self.rect.start.x;
            var y: usize = 0;
            while (y < self.rect.height) : (y += 1) {
                const newedge = Coord.new2(self.rect.start.z, edgex, self.rect.start.y + y);
                if (newedge.move(self.direction, state.mapgeometry)) |advanced| {
                    if (state.dungeon.at(advanced).type != .Wall and !ctx.doesJunctionContain(self, advanced))
                        return .No;
                    if (advanced.move(self.direction, state.mapgeometry)) |advanced2| {
                        if (state.dungeon.at(advanced2).type != .Wall) {
                            const intersector = ctx.findIntersectingTunnel(advanced2.asRect(), null, null);
                            const intersect_is_ok =
                                rng.percent(ctx.opts.intersect_chance) and
                                self.corridorLength() >= self.corridorWidth() and
                                intersector != null and !intersector.?.isParallelTo(self) and
                                (ctx.opts.intersect_with_childless or intersector.?.child_rooms > 0);
                            if (!intersect_is_ok) {
                                return .No;
                            } else yes = .YesIntersect;
                        }
                    } else return .No;
                } else return .No;

                const edgex2 = if (self.direction == .East) self.rect.end().x else self.rect.start.x -| 1;
                const sideedge1 = Coord.new2(self.rect.start.z, edgex2, self.rect.start.y -| 1);
                const sideedge2 = Coord.new2(self.rect.start.z, edgex2, self.rect.end().y);
                if (state.dungeon.at(sideedge1).type != .Wall or state.dungeon.at(sideedge2).type != .Wall) {
                    return .No;
                }
            }
        } else if (self.direction == .North or self.direction == .South) {
            assert(self.rect.width > 0);
            const edgey = if (self.direction == .South) self.rect.end().y - 1 else self.rect.start.y;
            var x: usize = 0;
            while (x < self.rect.width) : (x += 1) {
                const newedge = Coord.new2(self.rect.start.z, self.rect.start.x + x, edgey);
                if (newedge.move(self.direction, state.mapgeometry)) |advanced| {
                    if (state.dungeon.at(advanced).type != .Wall and !ctx.doesJunctionContain(self, advanced))
                        return .No;
                    if (advanced.move(self.direction, state.mapgeometry)) |advanced2| {
                        if (state.dungeon.at(advanced2).type != .Wall) {
                            const intersector = ctx.findIntersectingTunnel(advanced2.asRect(), null, null);
                            const intersect_is_ok =
                                rng.percent(ctx.opts.intersect_chance) and
                                self.corridorLength() >= self.corridorWidth() and
                                intersector != null and !intersector.?.isParallelTo(self) and
                                (ctx.opts.intersect_with_childless or intersector.?.child_rooms > 0);
                            if (!intersect_is_ok) {
                                return .No;
                            } else yes = .YesIntersect;
                        }
                    } else return .No;
                } else return .No;

                const edgey2 = if (self.direction == .South) self.rect.end().y else self.rect.start.y -| 1;
                const sideedge1 = Coord.new2(self.rect.start.z, self.rect.start.x -| 1, edgey2);
                const sideedge2 = Coord.new2(self.rect.start.z, self.rect.end().x, edgey2);
                if (state.dungeon.at(sideedge1).type != .Wall or state.dungeon.at(sideedge2).type != .Wall) {
                    return .No;
                }
            }
        } else unreachable;

        if (self.corridorLength() > 0) {
            var tunnelers = ctx.tunnelers.iterator();
            while (tunnelers.next()) |tunneler| {
                if (self == tunneler or tunneler.is_eviscerated or
                    tunneler.corridorLength() == 0 or
                    tunneler.rect.intersects(&self.rect, 1))
                {
                    continue;
                }

                if (self.isParallelTo(tunneler) and self.axisOverlaps(tunneler) and
                    self.minimumDistanceBetween(tunneler) < ctx.opts.min_tunneler_distance)
                {
                    return .No;
                }
            }
        }

        return yes;
    }

    pub fn getPotentialChildren(self: *Self, ctx: *const Ctx) [2]Tunneler {
        var res: [2]Tunneler = undefined;
        const level = self.rect.start.z;

        const newdirecs = switch (self.direction) {
            .East, .West => &[_]Direction{ .North, .South },
            .North, .South => &[_]Direction{ .East, .West },
            else => unreachable,
        };
        for (newdirecs) |newdirec, i| {
            var cor_width: usize = self.corridorWidth();
            if (rng.percent(ctx.opts.grow_chance) and cor_width < ctx.opts.max_width) {
                cor_width += 1;
            } else if (rng.percent(ctx.opts.shrink_chance) and cor_width > 1) {
                cor_width -= 1;
            }

            const newstart = switch (self.direction) {
                .East => switch (newdirec) {
                    .North => Coord.new2(level, self.rect.end().x -| cor_width, self.rect.start.y),
                    .South => Coord.new2(level, self.rect.end().x -| cor_width, self.rect.end().y),
                    else => unreachable,
                },
                .West => switch (newdirec) {
                    .North => Coord.new2(level, self.rect.start.x, self.rect.start.y),
                    .South => Coord.new2(level, self.rect.start.x, self.rect.end().y),
                    else => unreachable,
                },
                .North => switch (newdirec) {
                    .East => Coord.new2(level, self.rect.end().x, self.rect.start.y),
                    .West => Coord.new2(level, self.rect.start.x, self.rect.start.y),
                    else => unreachable,
                },
                .South => switch (newdirec) {
                    .East => Coord.new2(level, self.rect.end().x, self.rect.end().y -| cor_width),
                    .West => Coord.new2(level, self.rect.start.x, self.rect.end().y -| cor_width),
                    else => unreachable,
                },
                else => unreachable,
            };
            const newdim = switch (newdirec) {
                .North, .South => &[_]usize{ cor_width, 0 },
                .East, .West => &[_]usize{ 0, cor_width },
                else => unreachable,
            };
            res[i] = .{
                .rect = .{ .start = newstart, .width = newdim[0], .height = newdim[1] },
                .direction = newdirec,
                .parent = self,
                .generation = self.generation + 1,
                .born_at = self.corridorLength(),
            };
        }
        return res;
    }

    pub fn getPotentialRooms(self: *Self, ctx: *Ctx) [2]?Roomie {
        _ = ctx;

        var res = [2]?Roomie{ null, null };

        const level = self.rect.start.z;

        for (res) |_, i| {
            var rectw = rng.range(usize, Configs[level].min_room_width, Configs[level].max_room_width);
            var recth = rng.range(usize, Configs[level].min_room_height, Configs[level].max_room_height);

            if (rng.onein(5)) {
                rectw = Configs[level].min_room_width;
                recth = Configs[level].min_room_height;
            }

            const start_coords = switch (self.direction) {
                .East => &[_]Coord{
                    Coord.new2(level, self.rect.end().x -| rectw, self.rect.start.y -| recth -| 1),
                    Coord.new2(level, self.rect.end().x -| rectw, self.rect.end().y + 1),
                },
                .West => &[_]Coord{
                    Coord.new2(level, self.rect.start.x -| (rectw - 1), self.rect.start.y -| recth -| 1),
                    Coord.new2(level, self.rect.start.x -| (rectw - 1), self.rect.end().y + 1),
                },
                .North => &[_]Coord{
                    Coord.new2(level, self.rect.end().x + 1, self.rect.start.y -| (recth - 1)),
                    Coord.new2(level, self.rect.start.x -| (rectw + 1), self.rect.start.y -| (recth - 1)),
                },
                .South => &[_]Coord{
                    Coord.new2(level, self.rect.end().x + 1, self.rect.end().y -| recth),
                    Coord.new2(level, self.rect.start.x -| (rectw + 1), self.rect.end().y -| recth),
                },
                else => unreachable,
            };
            const orientation = switch (self.direction) {
                .East, .West => [_]Direction{ .North, .South },
                .North, .South => [_]Direction{ .East, .West },
                else => unreachable,
            }[i];

            const rect = Rect{ .start = start_coords[i], .width = rectw, .height = recth };
            res[i] = .{
                .parent = self,
                .generation = self.generation + 1,
                .born_at = self.corridorLength(),
                .rect = rect,
                .door = Roomie.getRandomDoorCoord(Room{ .rect = rect }, self).?,
                .orientation = orientation,
            };
        }
        return res;
    }

    pub fn getLastBranch(self: *const Self) usize {
        var farthest: usize = self.roomie_last_born_at;
        for (self.child_corridors.constSlice()) |child| {
            if (!child.is_eviscerated) {
                farthest = math.max(child.born_at, farthest);
            }
        }
        return farthest;
    }

    pub fn corridorWidth(self: *const Self) usize {
        return switch (self.direction) {
            .North, .South => self.rect.width,
            .East, .West => self.rect.height,
            else => unreachable,
        };
    }

    pub fn corridorLength(self: *const Self) usize {
        return switch (self.direction) {
            .North, .South => self.rect.height,
            .East, .West => self.rect.width,
            else => unreachable,
        };
    }

    pub fn isParallelTo(self: *const Self, other: *const Self) bool {
        return switch (self.direction) {
            .North, .South => other.direction == .North or other.direction == .South,
            .East, .West => other.direction == .East or other.direction == .West,
            else => unreachable,
        };
    }

    // Given two parallel tunnels, check if their length intersects in a single axis.
    //
    // (Not to be confused with checking if the tunnels intersect.)
    //
    pub fn axisOverlaps(self: *const Self, other: *const Self) bool {
        assert(self.isParallelTo(other));

        const a_begin = if (self.direction == .North or self.direction == .South) self.rect.start.y else self.rect.start.x;
        const a_end = a_begin + self.corridorLength();
        const b_begin = if (other.direction == .North or other.direction == .South) other.rect.start.y else other.rect.start.x;
        const b_end = b_begin + other.corridorLength();

        return math.max(a_begin, b_begin) <= math.min(a_end, b_end);
    }

    pub fn minimumDistanceBetween(self: *const Self, other: *const Self) usize {
        assert(self.isParallelTo(other) and !self.rect.intersects(&other.rect, 1));

        const a_begin = if (self.direction == .North or self.direction == .South) self.rect.start.x else self.rect.start.y;
        const a_end = if (self.direction == .North or self.direction == .South) self.rect.end().x - 1 else self.rect.end().y - 1;
        const b_begin = if (other.direction == .North or other.direction == .South) other.rect.start.x else other.rect.start.y;
        const b_end = if (other.direction == .North or other.direction == .South) other.rect.end().x - 1 else other.rect.end().y - 1;

        return if (b_begin < a_begin) a_begin - b_end else b_begin - a_end;
    }
};

pub const TunnelerOptions = struct {
    max_iters: usize = 700,

    // Maximum tunnel length before the algorithm tries to force it to change
    // directions.
    max_length: usize = WIDTH, //WIDTH / 3,

    // Maximum tunnel width. If the tunnel is this size, it won't grow farther.
    max_width: usize = 6,

    min_tunneler_distance: usize = 2,

    // Chance (percentage) to change direction.
    turn_chance: usize = 8,
    branch_chance: usize = 6,

    room_tries: usize = 14,

    shrink_chance: usize = 50,
    grow_chance: usize = 50,

    intersect_chance: usize = 80,
    intersect_with_childless: bool = false,

    add_extra_rooms: bool = true,
    remove_childless: bool = true,
    shrink_corridors: bool = true,
    add_junctions: bool = true,

    force_prefabs: bool = false,

    max_room_per_tunnel: usize = 99,

    initial_tunnelers: []const InitialTunneler = &[_]InitialTunneler{
        // .{ .start = Coord.new(1, 1), .width = 0, .height = 3, .direction = .East },

        // .{ .start = Coord.new((WIDTH / 2) + 1, HEIGHT / 2), .width = 0, .height = 3, .direction = .East },
        // .{ .start = Coord.new((WIDTH / 2) - 1, HEIGHT / 2), .width = 0, .height = 3, .direction = .West },
        // .{ .start = Coord.new(WIDTH / 2, (HEIGHT / 2) + 1), .width = 3, .height = 0, .direction = .South },
        // .{ .start = Coord.new(WIDTH / 2, (HEIGHT / 2) - 1), .width = 3, .height = 0, .direction = .North },

        // .{ .start = Coord.new(1, 1), .width = 0, .height = 3, .direction = .East },
        // .{ .start = Coord.new(WIDTH - 1, HEIGHT - 4), .width = 0, .height = 3, .direction = .West },
        // .{ .start = Coord.new(1, HEIGHT - 1), .width = 3, .height = 0, .direction = .North },
        // .{ .start = Coord.new(WIDTH - 4, 1), .width = 3, .height = 0, .direction = .South },

        .{ .start = Coord.new(1, HEIGHT / 2), .width = 0, .height = 3, .direction = .East },
    },

    pub const InitialTunneler = struct { start: Coord, height: usize, width: usize, direction: Direction };
};

// TODO:
// x Remove dead ends, i.e. reduce corridor length to it's last branch/junction
// x Add junction points
//   x When a corridor turns or branches
//   - At a meeting area for corridors
//   - In front of some rooms
// - Prevent diagonal shortcuts
// x Make corridors change widths as they branch out or change direction
// - Integrate additional-corridors-between-rooms thing
// - Ensure there are looping connections between multiple tunnelers
// - Add doorways randomly to rooms, not the way it currently is
pub fn placeTunneledRooms(level: usize, allocator: mem.Allocator) void {
    var ctx = Ctx{
        .level = level,
        .tunnelers = Tunneler.List.init(allocator),
        .roomies = std.ArrayList(Roomie).init(allocator),
        .extras = std.ArrayList(Roomie).init(allocator),
        .junctions = std.ArrayList(Junction).init(allocator),
        .opts = Configs[level].tunneler_opts,
    };
    for (ctx.opts.initial_tunnelers) |initial| {
        ctx.tunnelers.append(Tunneler{
            .rect = Rect{ .start = Coord.new2(level, initial.start.x, initial.start.y), .width = initial.width, .height = initial.height },
            .direction = initial.direction,
        }) catch err.wat();
    }

    defer ctx.tunnelers.deinit();
    defer ctx.roomies.deinit();
    defer ctx.extras.deinit();
    defer ctx.junctions.deinit();

    var new_tuns = Tunneler.AList.init(allocator);
    defer new_tuns.deinit();

    var cur_gen: usize = 0;

    var tries: usize = 0;
    while (tries < ctx.opts.max_iters) : (tries += 1) {
        mapgen.captureFrame(level);

        var is_any_active: bool = false;
        var is_cur_gen_active: bool = false;

        var tunnelers = ctx.tunnelers.iterator();
        while (tunnelers.next()) |tunneler| if (!tunneler.is_dead) {
            if (tunneler.generation != cur_gen) {
                is_any_active = true;
                continue;
            }

            const can = tunneler.canAdvance(&ctx);
            if (can != .No) {
                tunneler.advance();
                if (can == .YesIntersect)
                    tunneler.is_intersected = true;
                is_any_active = true;
                is_cur_gen_active = true;
            } else {
                tunneler.die();
            }

            const children = tunneler.getPotentialChildren(&ctx);
            const tlength = tunneler.corridorLength();
            const twidth = tunneler.corridorWidth();
            for (children) |child| {
                if (!tunneler.is_dead and tlength > twidth * 3 and
                    child.canAdvance(&ctx) != .No and
                    (tlength > ctx.opts.max_length or rng.percent(ctx.opts.turn_chance)))
                {
                    var new = child;
                    new.generation = tunneler.generation;
                    new_tuns.append(new) catch err.wat();
                    tunneler.die();
                } else if (tunneler.is_dead or rng.percent(ctx.opts.branch_chance)) {
                    new_tuns.append(child) catch err.wat();
                }
            }

            if (tunneler.child_rooms < ctx.opts.max_room_per_tunnel and
                tunneler.corridorLength() > tunneler.corridorWidth())
            {
                var room_tries: usize = ctx.opts.room_tries;
                while (room_tries > 0) : (room_tries -= 1) {
                    const rooms = tunneler.getPotentialRooms(&ctx);
                    for (rooms) |maybe_room| if (maybe_room) |room| {
                        ctx.roomies.append(room) catch err.wat();
                        ctx.extras.append(room) catch err.wat();
                    };
                }
            }
        };

        for (new_tuns.items) |new_tun| {
            const can = new_tun.canAdvance(&ctx);
            if (can != .No) {
                assert(can != .YesIntersect);

                is_any_active = true;
                const new_tun_ptr = ctx.tunnelers.appendAndReturn(new_tun) catch err.wat();
                new_tun.parent.?.child_corridors.append(new_tun_ptr) catch err.wat();

                new_tun.parent.?.createJunction(new_tun_ptr, &ctx);
            }
        }
        new_tuns.clearAndFree();

        ctx.tryAddingRoomies(level, cur_gen);

        if (!is_cur_gen_active) {
            cur_gen += 1;
            if (ctx.opts.remove_childless)
                ctx.removeChildlessTunnelers(true);
        }

        if (!is_any_active)
            break;
    }

    if (ctx.opts.remove_childless)
        ctx.removeChildlessTunnelers(false);
    mapgen.captureFrame(level);

    // Fill in corridors that stick out past their last branch
    if (ctx.opts.shrink_corridors) {
        var tunnelers = ctx.tunnelers.iterator();
        while (tunnelers.next()) |tunneler| {
            if (!tunneler.is_eviscerated and !tunneler.is_intersected) {
                tunneler.shrinkTo(tunneler.getLastBranch());
            }
        }
    }

    ctx.killThemAll();
    mapgen.captureFrame(level);
    ctx.excavateJunctions();
    mapgen.captureFrame(level);
    ctx.tryAddingRoomies(level, 9999999);
    mapgen.captureFrame(level);
    ctx.tryAddingExtraRooms(level);
    mapgen.captureFrame(level);

    // Removed because for the time being we want the placeRandomRooms
    // algorithm to place the player
    //
    // ctx.addPlayer();
}
