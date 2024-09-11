const game = @import("../game.zig");
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CAngles = @import("../math/angles.zig").CAngles;

pub const EntityDef = struct {
    index: usize,

    pub fn name(self: EntityDef) []const u8 {
        return if (game.c_declByIndex(@intCast(self.index))) |decl|
            decl.name()
        else
            "*unknown*";
    }
};

pub const Name = []const u8;

pub const SpawnError = error{
    ClipModelIsUndefined,
    CSpawnArgsIsUndefined,
    EntityDefIsUndefined,
};

pub extern fn c_parseMatrix([*c]const u8) callconv(.C) CMat3;
pub extern fn c_parseAngles([*c]const u8) callconv(.C) CAngles;
pub extern fn c_parseVector([*c]const u8) callconv(.C) CVec3;
