// Naming conventions
//
// - All sprites start with S_
// - Generic sprites (walls, puddles, liquids, etc) prefixed w/ G_
// - Object-specific sprites are prefixd w/ O_
//

pub const Sprite = enum(u21) {
    S_O_StorageA = 0x2780,
    S_O_StorageB = 0x2781,
    S_O_StorageC = 0x2782,
    S_O_StorageD = 0x2783,
    S_O_CrateA = 0x2784,
    S_O_CrateB = 0x2785,
    S_O_CrateC = 0x2786,
    S_O_CrateD = 0x2787,
    S_O_Pot = 0x2788,
    S_O_ChairA = 0x2789,
    S_O_ChairB = 0x278A,
    S_O_TableA = 0x278B,
    S_O_TableB = 0x278C,
    S_O_TableC = 0x278D,
    S_O_TableD = 0x278E,
    S_O_P_Bed = 0x278F,

    S_G_Wall_Finished = 0x2790,
    S_G_Wall_Rough = 0x2791,
    S_G_Wall_Grate = 0x2792,
    S_G_Wall_Window = 0x2793,
    S_G_Wall_Scifish = 0x2794,
    S_G_Wall_Window2 = 0x2795,
    S_G_Wall_Plated = 0x2796,
    S_G_Wall_Ornate = 0x2797,
    S_G_Wall_Grate_Broken = 0x2798,
    S_G_StairsDown = 0x279E,
    S_G_StairsUp = 0x279F,

    S_G_T_Metal = 0x27A0,
    S_G_T_Polished = 0x27A1,
    S_G_T_Ornate = 0x27A2,
    S_G_T_Raw = 0x27A3,

    S_G_P_MiscLabMach = 0x27B0,
    S_O_P_Table = 0x27B1,
    S_O_P_Chair = 0x27B2,
    S_O_P_ControlPanel = 0x27B3,
    S_O_P_SwitchingStation = 0x27B4,
    S_O_P_Stove = 0x27B5,
    S_O_P_Sink = 0x27B6,
    S_O_P_Desk = 0x27B7,
    S_O_P_Toybox = 0x27B8,
    S_O_P_SofaA = 0x27B9,
    S_O_P_SofaB = 0x27BA,
    S_O_P_SofaC = 0x27BB,
    S_O_P_Coffin = 0x27BC,
    S_G_M_Machine = 0x27BF,

    S_G_M_DoorShut = 0x27C0,
    S_G_M_DoorOpen = 0x27C1,
    S_O_M_LabDoorShut = 0x27C2,
    S_O_M_LabDoorOpen = 0x27C3,
    S_O_M_QrtDoorShut = 0x27C4,
    S_O_M_QrtDoorOpen = 0x27C5,
    S_O_M_PriLight = 0x27C6,
    S_O_M_LabLight = 0x27C7,
    S_G_Poster = 0x27CF,
};
