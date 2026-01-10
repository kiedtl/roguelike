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

    pub fn interned_string(self: *const @This()) []const u8 {
        return self.name;
    }
};

pub const Poster = struct {
    level: []const u8, // What level this poster belongs on. E.g., "PRI" "LAB" "VLT"
    id: []const u8, // Id. Currently not used for anything
    text: []const u8, // Contents.

    // Mapgen state, storing number of times this poster has been placed.
    placement_counter: usize = 0,

    // Not const pointer because we store mapgen data here (FIXME)
    pub const ArrayList = std.ArrayList(*Poster);

    pub fn new(alloc: mem.Allocator, id: []const u8, level: []const u8, text: []const u8) !*Poster {
        const p = try alloc.create(Poster);
        p.* = .{ .id = id, .level = level, .text = text };
        return p;
    }

    pub fn deinit(self: *const Poster, alloc: mem.Allocator) void {
        alloc.free(self.id);
        alloc.free(self.level);
        alloc.free(self.text);
    }
};

pub var names: Name.ArrayList = undefined;
pub var posters: Poster.ArrayList = undefined;

pub fn readPosters(alloc: mem.Allocator) void {
    var data_dir = std.fs.cwd().openDir("data", .{}) catch unreachable;
    defer data_dir.close();

    const data_file = data_dir.openFile("posters.tsv", .{}) catch unreachable;
    defer data_file.close();

    const read = data_file.readToEndAlloc(alloc, 0xFFFF * 0xFF) catch err.oom();
    defer alloc.free(read);

    const result = tsv.parse(
        struct { id: []u8, level: []u8, text: []u8 },
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "id", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "level", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "text", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
        },
        undefined,
        read,
        alloc,
    );

    if (result.get()) |poster_list| {
        posters = @TypeOf(posters).init(alloc);
        for (poster_list.items) |poster| {
            posters.append(
                Poster.new(alloc, poster.id, poster.level, poster.text) catch err.oom(),
            ) catch err.oom();
        }
        std.log.info("Loaded {} posters.", .{poster_list.items.len});
        poster_list.deinit();
    } else {
        std.log.err(
            "Cannot read props: {} (line {}, field {})",
            .{ result.Err.type, result.Err.context.lineno, result.Err.context.field },
        );
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
    const data_file = data_dir.openFile("names.tsv", .{}) catch unreachable;

    var rbuf: [65535]u8 = undefined;
    const read = data_file.readAll(rbuf[0..]) catch unreachable;

    const result = tsv.parse(
        NameData,
        &[_]tsv.TSVSchemaItem{
            .{ .field_name = "name", .parse_to = []u8, .parse_fn = tsv.parseUtf8String },
            .{ .field_name = "function", .parse_to = Name.Function, .parse_fn = tsv.parsePrimitive },
            .{ .field_name = "is_noble", .parse_to = bool, .parse_fn = tsv.parsePrimitive, .optional = true },
            .{ .field_name = "flags", .parse_to = ?Name.Flag, .is_array = Name.Flag.NUM, .parse_fn = tsv.parsePrimitive, .optional = true },
        },
        .{
            .is_noble = false,
            .flags = [_]?Name.Flag{null} ** Name.Flag.NUM,
        },
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
