usingnamespace @import("types.zig");

pub const HEIGHT = 40;
pub const WIDTH = 100;
pub var dungeon = [_][WIDTH]Tile{[_]Tile{Tile{
    .type = .Wall,
    .mob = null,
}} ** WIDTH} ** HEIGHT;
