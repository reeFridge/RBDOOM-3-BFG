const std = @import("std");
const Angles = @import("../math/angles.zig");
const Mat3 = @import("../math/matrix.zig").Mat3;
const Vec3 = @import("../math/vector.zig").Vec3;
const game = @import("../game.zig");
const decl_manager = @import("../framework/decl_manager.zig");
const global = @import("../global.zig");
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CAngles = @import("../math/angles.zig").CAngles;

pub const EntityDef = struct {
    index: usize,

    pub fn name(self: EntityDef) []const u8 {
        const decl = decl_manager.instance.declByIndex(
            .entitydef,
            @intCast(self.index),
            false,
            global.gpa.allocator(),
        ) catch @panic("declByIndex fails");

        return decl.base.?.name.constSlice();
    }
};

pub const Name = []const u8;

pub const SpawnError = error{
    ClipModelIsUndefined,
    CSpawnArgsIsUndefined,
    EntityDefIsUndefined,
};

pub fn parseVec3f(str: []const u8) std.fmt.ParseFloatError!Vec3(f32) {
    var iterator = std.mem.splitSequence(u8, str, " ");

    var vec3 = Vec3(f32){};
    var i: u32 = 0;
    while (iterator.next()) |float_literal| : (i += 1) {
        vec3.v[i] = try std.fmt.parseFloat(f32, float_literal);
    }

    return vec3;
}

pub fn parseAngles(str: []const u8) std.fmt.ParseFloatError!Angles {
    const vec3 = try parseVec3f(str);

    return .{ .pitch = vec3.v[0], .yaw = vec3.v[1], .roll = vec3.v[2] };
}

pub fn parseMat3f(str: []const u8) std.fmt.ParseFloatError!Mat3(f32) {
    var iterator = std.mem.splitSequence(u8, str, " ");

    var mat3 = Mat3(f32).identity();
    var i: u32 = 0;
    while (iterator.next()) |float_literal| : (i += 1) {
        const float = try std.fmt.parseFloat(f32, float_literal);

        if (i <= 2) {
            mat3.v[0].v[i % 3] = float;
        } else if (i <= 5) {
            mat3.v[1].v[i % 3] = float;
        } else if (i <= 8) {
            mat3.v[2].v[i % 3] = float;
        }
    }

    return mat3;
}
