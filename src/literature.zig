// Posters and books

const std = @import("std");
const mem = std.mem;
const meta = std.meta;

const types = @import("types.zig");
const err = @import("err.zig");
const rng = @import("rng.zig");
const mobs = @import("mobs.zig");
const tsv = @import("tsv.zig");
const Mob = types.Mob;
const MobTemplate = mobs.MobTemplate;

const LinkedList = @import("list.zig").LinkedList;
const StackBuffer = @import("buffer.zig").StackBuffer;

pub const Name = struct {
    name: []u8,
    function: Function,
    is_noble: bool,
    flags: StackBuffer(Flag, Flag.NUM),

    pub const Function = enum { Family, Given, Either };

    pub const Flag = enum {
        // Hg: Hill-goblin, Cg: Cave-goblin
        // H: Human (hill-goblin aligned)
        Hg,
        Cg,
        H,

        pub const NUM: usize = meta.fields(@This()).len;
    };

    pub const ArrayList = std.ArrayList(@This());

    pub fn flag(self: *const @This(), f: Flag) bool {
        return mem.containsAtLeast(Flag, self.flags.constSlice(), 1, &[_]Flag{f});
    }

    pub fn deinit(self: *const @This(), alloc: mem.Allocator) void {
        alloc.free(self.name);
    }
};

pub const Poster = struct {
    // linked list stuff
    __next: ?*Poster = null,
    __prev: ?*Poster = null,

    // What level this poster belongs on. E.g., "PRI" "LAB" "VLT"
    level: []u8,

    // Contents.
    text: []u8,

    // Mapgen state, storing number of times this poster has been placed.
    placement_counter: usize = 0,

    pub fn deinit(self: *const Poster, alloc: mem.Allocator) void {
        alloc.free(self.level);
        alloc.free(self.text);
    }
};

pub const PosterList = LinkedList(Poster);

pub var names: Name.ArrayList = undefined;
pub var posters: PosterList = undefined;

pub fn readPosters(alloc: mem.Allocator) void {
    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("posters.tsv", .{
        .read = true,
        .lock = .None,
    }) catch unreachable;

    var rbuf: [8192]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        Poster,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "level", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "text", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
        },
        .{ .level = undefined, .text = undefined },
        rbuf[0..read],
        alloc,
    );

    if (!result.is_ok()) {
        std.log.err(
            "Cannot read props: {} (line {}, field {})",
            .{ result.Err.type, result.Err.context.lineno, result.Err.context.field },
        );
    } else {
        posters = @TypeOf(posters).init(alloc);
        for (result.unwrap().items) |poster| posters.append(poster) catch err.wat();
        std.log.info("Loaded {} posters.", .{result.unwrap().items.len});
        result.unwrap().deinit();
    }
}

pub fn readNames(alloc: mem.Allocator) void {
    names = Name.ArrayList.init(alloc);

    const NameData = struct {
        name: []u8 = undefined,
        function: Name.Function = undefined,
        is_noble: bool = undefined,
        flags: [Name.Flag.NUM]?Name.Flag = undefined,
    };

    const data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    const data_file = data_dir.openFile("names.tsv", .{
        .read = true,
        .lock = .None,
    }) catch unreachable;

    var rbuf: [65535]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        NameData,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "name", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "function", .parse_to = Name.Function, .parse_fn = tsv.parsePrimitive },
            .{ .field_name = "is_noble", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = false },
            .{ .field_name = "flags", .parse_to = ?Name.Flag, .is_array = Name.Flag.NUM, .parse_fn = tsv.parsePrimitive, .optional = true, .default_val = null },
        },
        .{},
        rbuf[0..read],
        alloc,
    );

    if (!result.is_ok()) {
        err.bug(
            "Cannot read names: {} (line {}, field {})",
            .{ result.Err.type, result.Err.context.lineno, result.Err.context.field },
        );
    } else {
        const namedatas = result.unwrap();
        defer namedatas.deinit();

        for (namedatas.items) |namedata| {
            var name = Name{
                .name = namedata.name,
                .function = namedata.function,
                .is_noble = namedata.is_noble,
                .flags = StackBuffer(Name.Flag, Name.Flag.NUM).init(null),
            };

            for (namedata.flags) |maybe_fl| if (maybe_fl) |fl| {
                name.flags.append(fl) catch unreachable;
            };

            names.append(name) catch unreachable;
        }

        std.log.info("Loaded {} names.", .{names.items.len});
    }
}

// Really lazy coding here.
//
// TODO: forbidden names:
// - Tyeburenet Kulbin
// - Zilodothrod Berujdib
// - Zilodothrod Hubsel
// - Ubetalrego Lyehuld
// - Hubodothrod Beruren
// - Rulers of Irthimgilnaz
//   - Leqhyebudib Nath: Lord Magistrate
//   - Myalbaren Dremuldkor: Steward
//   - Leqhyebudib Hubsel: Captain of the Guard
//
pub fn assignName(template: *const MobTemplate, mob: *Mob) void {
    if (template.name_flags.len == 0)
        return; // No names for this one!

    while (true) {
        if (mob.name_given != null and (mob.name_family != null or template.skip_family_name)) {
            break;
        }

        const name = rng.chooseUnweighted(Name, names.items);

        const matches_any_flag = for (template.name_flags) |fl| {
            if (name.flag(fl)) break true;
        } else false;

        if (!matches_any_flag or (name.is_noble and !template.allow_noble_names))
            continue;

        if (mob.name_given == null and (name.function == .Given or name.function == .Either)) {
            mob.name_given = name.name;
            continue;
        }

        if (mob.name_family == null and (name.function == .Family or name.function == .Either)) {
            mob.name_family = name.name;
            continue;
        }
    }
}

pub fn freeNames(alloc: mem.Allocator) void {
    for (names.items) |name| name.deinit(alloc);
    names.deinit();
}
