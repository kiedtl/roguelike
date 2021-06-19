usingnamespace @import("types.zig");

pub const PurpleFungus = Sob{
    .id = "purple_fungus_sob",
    .species = "fungus",
    .tile = '"',
    .walkable = true,
    .ai_func = aiPurpleFungus,
};

pub fn aiPurpleFungus(_: *Sob) void {}
