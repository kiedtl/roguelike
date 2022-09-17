// Naming conventions
//
// - All sprites start with S_
// - Generic sprites (walls, puddles, liquids, etc) prefixed w/ G_
//

pub const Sprite = enum(u21) {
    S_G_Wall_Finished = 0x2600,
    S_G_Wall_Rough = 0x2601,
    S_G_Wall_Scifish = 0x2602,
    S_G_Wall_Window = 0x2603,

    S_G_T_Metal = 0x2610,
};
