const std = @import("std");
const mem = std.mem;
const assert = std.debug.assert;
const math = std.math;
const meta = std.meta;

const ai = @import("../ai.zig");
const alert = @import("../alert.zig");
const astar = @import("../astar.zig");
const buffer = @import("../buffer.zig");
const colors = @import("../colors.zig");
const combat = @import("../combat.zig");
const dijkstra = @import("../dijkstra.zig");
const err = @import("../err.zig");
const fov = @import("../fov.zig");
const items = @import("../items.zig");
const mapgen = @import("../mapgen.zig");
const mobs = @import("../mobs.zig");
const rng = @import("../rng.zig");
const spells = @import("../spells.zig");
const state = @import("../state.zig");
const surfaces = @import("../surfaces.zig");
const tasks = @import("../tasks.zig");
const types = @import("../types.zig");
const ui = @import("../ui.zig");
const utils = @import("../utils.zig");

const tryRest = ai.tryRest;
const AIJob = types.AIJob;
const Dungeon = types.Dungeon;
const Mob = types.Mob;
const EnemyRecord = types.EnemyRecord;
const SuspiciousTileRecord = types.SuspiciousTileRecord;
const Coord = types.Coord;
const CoordArrayList = types.CoordArrayList;
const Direction = types.Direction;
const Status = types.Status;

const StackBuffer = buffer.StackBuffer;
const SpellOptions = spells.SpellOptions;

const CARDINAL_DIRECTIONS = types.CARDINAL_DIRECTIONS;
const DIAGONAL_DIRECTIONS = types.DIAGONAL_DIRECTIONS;
const DIRECTIONS = types.DIRECTIONS;

const LEVELS = state.LEVELS;
const HEIGHT = state.HEIGHT;
const WIDTH = state.WIDTH;

fn findDustlingCaptain(mob: *Mob) ?*Mob {
    return utils.getSpecificMobInRoom(mob.coord, "vapour_mage");
}

// Stay still in one place and be puppeted by Dustling captain. Cancel job if
// leader wandered away.
//
// Only for dustlings.
pub fn _Job_CAV_BePuppeted(mob: *Mob, _: *AIJob) AIJob.JStatus {
    assert(mem.eql(u8, mob.id, "dustling"));

    tryRest(mob);

    if (mob.squad == null or
        mob.squad.?.leader == null or
        !mem.eql(u8, mob.squad.?.leader.?.id, "vapour_mage") or
        mob.distance(mob.squad.?.leader.?) > 7)
    {
        return .Complete;
    }

    return .Ongoing;
}

// Systematically move members (yes, the captain is forcing members to take
// actions... kind bad), and make them hit the combat dummy (yes, again, the
// captain is forcibly calling member.attack() even though it's not their
// turn).
//
// Why is this bad? Well imagine a dustling has been driven insane and the
// captain somehow doesn't notice the new hostile, and this insane dustling is
// taking part of the combat drill with the rest...
//
pub fn _Job_CAV_OrganizeDrill(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const squad = mob.squad orelse {
        // ???
        mob.newJob(.WRK_LeaveFloor); // Leave in shame
        return .Complete;
    };

    const dummy = utils.getSpecificMobInRoom(mob.coord, "combat_dummy") orelse
        return .Complete;

    if (mob.distance(dummy) > 2) {
        mob.tryMoveTo(dummy.coord);
    } else {
        tryRest(mob);
    }

    // Check position of dustlings
    check_loop: while (true) {
        const spot = for (&CARDINAL_DIRECTIONS) |d| {
            if (dummy.coord.move(d, state.mapgeometry)) |spot| {
                if (state.is_walkable(spot, .{ .right_now = true })) {
                    assert(state.dungeon.at(spot).mob == null);
                    break spot;
                }
            }
        } else break;

        for (squad.members.constSlice()) |member| {
            if (mem.eql(u8, member.id, "dustling")) // Should always be true, but just in case
                if (member.coord.distanceManhattan(dummy.coord) > 1 and
                    member.coord.distance(spot) > 0)
                {
                    if (member.hasJob(.CAV_BePuppeted) == null)
                        member.newJob(.CAV_BePuppeted);
                    member.tryMoveTo(spot);
                    continue :check_loop;
                };
        }

        // All the dustlings are in place.
        break;
    }

    // Now attacc
    for (squad.members.constSlice()) |member| {
        if (dummy.HP == 1)
            break;
        if (member.distance(dummy) > 1)
            continue;
        member.fight(dummy, .{ .loudness = .Silent });
    }

    return job.checkTurnsLeft(28);
}

pub fn _Job_CAV_FindJob(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const CTX_TARGET = "ctx_find_job_target_engineer";
    const maybe_target = job.ctx.getOrNone(*Mob, CTX_TARGET);

    const _S = struct {
        pub fn mobIsAdvertising(m: *Mob) bool {
            return mem.eql(u8, m.id, "engineer") and
                m.newestJob() != null and
                m.newestJob().?.job == .CAV_Advertise;
        }
    };

    if (maybe_target == null or !_S.mobIsAdvertising(maybe_target.?)) {
        var iter = state.mobs.iterator();
        const new_target = while (iter.next()) |mapmob| {
            if (mapmob.coord.z == mob.coord.z and !mapmob.is_dead and
                _S.mobIsAdvertising(mapmob))
            {
                break mapmob;
            }
        } else {
            ai.patrolWork(mob, state.gpa.allocator());
            return .Ongoing;
        };
        job.ctx.set(*Mob, CTX_TARGET, new_target);
    }

    const target = job.ctx.getOrNone(*Mob, CTX_TARGET).?;
    mob.tryMoveTo(target.coord);
    return .Ongoing;
}

pub fn _Job_CAV_Advertise(mob: *Mob, job: *AIJob) AIJob.JStatus {
    const jobkind = job.ctx.getOrNone(AIJob.Type, AIJob.CTX_ADVERTISE_KIND).?;

    // Return to work area
    const workplace = mob.ai.work_area.items[0];
    if (!mob.coord.eq(workplace)) {
        mob.tryMoveTo(workplace);
        return .Ongoing;
    }

    tryRest(mob);

    const room_ind = utils.getRoomFromCoord(mob.coord.z, mob.coord) orelse {
        mob.newJob(.WRK_LeaveFloor);
        tryRest(mob);
        return .Complete;
    };
    const room = state.rooms[mob.coord.z].items[room_ind];

    // lol at indentation
    // ifififififififififififi
    var found_someone = false;
    var iter = room.rect.iter();
    while (iter.next()) |roomcoord|
        if (state.dungeon.at(roomcoord).mob) |guest|
            if (mem.eql(u8, guest.id, "vapour_mage"))
                if (guest.newestJob()) |guest_job|
                    if (guest_job.job == .CAV_FindJob) {
                        var old_job = guest.jobs.pop() catch err.wat();
                        old_job.deinit();
                        guest.newJob(jobkind);
                        found_someone = true;
                    };

    return if (found_someone) .Complete else .Ongoing;
}

// Expects work area to be station place.
pub fn _Job_CAV_RunDrillRoom(mob: *Mob, _: *AIJob) AIJob.JStatus {
    // Return to work area
    const workplace = mob.ai.work_area.items[0];
    if (!mob.coord.eq(workplace)) {
        mob.tryMoveTo(workplace);
        return .Ongoing;
    }

    const customer = findDustlingCaptain(mob) orelse {
        // If no vapor mage, then start advertising
        mob.newJob(.CAV_Advertise);
        mob.newestJob().?.ctx.set(AIJob.Type, AIJob.CTX_ADVERTISE_KIND, .CAV_OrganizeDrill);
        tryRest(mob);
        return .Ongoing;
    };

    const dummy = utils.getSpecificMobInRoom(mob.coord, "combat_dummy") orelse {
        // Our combat dummy disappeared...?
        mob.newJob(.WRK_LeaveFloor);
        tryRest(mob);
        return .Complete;
    };

    if (rng.onein(4)) {
        const lookatme = if (rng.boolean()) customer else dummy;
        mob.facing = mob.coord.closestDirectionTo(lookatme.coord, state.mapgeometry);
    }

    var did_something = false;

    if (dummy.HP <= 2) {
        const origcoord = mob.coord;
        for (&DIRECTIONS) |d| if (mob.coord.move(d, state.mapgeometry)) |neighbor| {
            if (state.dungeon.machineAt(neighbor)) |machine|
                if (machine.power == 0 and mem.eql(u8, machine.id, "combat_dummy_repair_lever")) {
                    // TODO: refactor and deduplicate this (with ai.zig's
                    // BusyWork job implementation)
                    did_something = mob.moveInDirection(d);
                    err.ensure(did_something, "{cf}: Powering lever failed", .{mob}) catch {};
                    err.ensure(mob.coord.eq(origcoord), "{cf}: Attempt to power lever caused movement", .{mob}) catch {};
                    break;
                };
        };
    }

    if (!did_something)
        tryRest(mob);

    return .Ongoing;
}

pub fn vapourMageWork(mob: *Mob, _: mem.Allocator) void {
    mob.newJob(.CAV_FindJob);
    tryRest(mob);
}
