const alert = @import("alert.zig");
const types = @import("types.zig");
const state = @import("state.zig");
const ui = @import("ui.zig");

const Ctx = types.Ctx;
const LinkedList = @import("list.zig").LinkedList;

pub fn tickFuses(level: usize) void {
    var timer = state.benchmarker.timer("tickFuses");
    defer timer.end();

    var iter = state.fuses.iterator();
    while (iter.next()) |fuse| {
        if (fuse.is_disabled)
            continue; // TODO: actually delete it from the linked list

        switch (fuse.level) {
            .specific => |req_lvl| if (req_lvl != level) continue,
        }

        fuse.tick(level);
    }
}

// Like a machine, but does something each tick while not being visible to the
// player (or needing any "power" or other stimuli.
//
// Created by events, originally for delayed effects, but can be used for many
// other things.
pub const Fuse = struct {
    // linked list stuff
    __next: ?*Fuse = null,
    __prev: ?*Fuse = null,

    level: union(enum) { specific: usize },
    ctx: Ctx = undefined,
    is_disabled: bool = false,

    on_tick: Func,

    pub const Func = enum {
        spawn_hunter_in_100,
    };

    pub const List = LinkedList(Fuse);

    pub fn initFrom(self: Fuse) Fuse {
        var s = self;
        s.ctx = Ctx.init();
        return s;
    }

    pub fn tick(self: *Fuse, level: usize) void {
        const func = switch (self.on_tick) {
            .spawn_hunter_in_100 => spawnHunterIn100,
        };
        (func)(self, level);
    }

    pub fn disable(self: *Fuse) void {
        self.is_disabled = true;
    }
};

fn spawnHunterIn100(self: *Fuse, level: usize) void {
    const CTX_CTR = "ctx_ctr";
    const ctr = self.ctx.get(usize, CTX_CTR, 100);

    if (ctr == 0) {
        alert.spawnAssault(level, state.player, "h") catch {
            self.ctx.set(usize, CTX_CTR, 20);
            return;
        };
        _ = ui.drawTextModal("You feel uneasy.", .{});
        self.disable();
    } else {
        self.ctx.set(usize, CTX_CTR, ctr - 1);
    }
}
