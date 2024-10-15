const idlib = @import("../idlib.zig");
const cmd = @import("cmd_system.zig");

pub const CVar = extern struct {
    vptr: *anyopaque,
    name: [*:0]const u8,
    value: [*:0]const u8,
    description: [*:0]const u8,
    flats: c_int,
    valueMin: f32,
    valueMax: f32,
    valueStrings: ?[*][*:0]const u8,
    valueCompletion: *const cmd.ArgCompletionFn,
    integerValue: c_int,
    floatValue: f32,
    internalVar: *CVar,
    next: ?*CVar,
    nameString: idlib.idStr,
    resetString: idlib.idStr,
    valueString: idlib.idStr,
};

pub const CVarSystem = extern struct {
    vptr: *anyopaque,
    initialized: bool,
    cvars: idlib.idList(*CVar),
    cvarHash: idlib.idHashIndex,
    modifiedFlags: c_int,
};

pub const instance = @extern(*CVarSystem, .{ .name = "localCVarSystem" });
