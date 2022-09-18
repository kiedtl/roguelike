// Naming conventions
//
// - All sprites start with S_
// - Generic sprites (walls, puddles, liquids, etc) prefixed w/ G_
// - Object-specific sprites are prefixd w/ O_
//

pub const Sprite = enum(u21) {
    S_G_Wall_Finished = 0x2790,
    S_G_Wall_Rough = 0x2791,
    S_G_Wall_Scifish = 0x2792,
    S_G_Wall_Window = 0x2793,

    S_G_T_Metal = 0x27A0,

    S_O_M_PriDoorShut = 0x27C0,
    S_O_M_PriDoorOpen = 0x27C1,
    S_O_M_LabDoorShut = 0x27C2,
    S_O_M_LabDoorOpen = 0x27C3,
    S_O_M_QrtDoorShut = 0x27C4,
    S_O_M_QrtDoorOpen = 0x27C5,

    S_O_M_PriLight = 0x27C6,
    S_O_M_LabLight = 0x27C7,
};
