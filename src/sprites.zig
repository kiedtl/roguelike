// Naming conventions
//
// - All sprites start with S_
// - Generic sprites (walls, puddles, liquids, etc) prefixed w/ G_
//

pub const Sprite = enum(u21) {
    S_G_Wall_Finished = 0x2600,
    S_G_Wall_Rough = 0x2601,
};
