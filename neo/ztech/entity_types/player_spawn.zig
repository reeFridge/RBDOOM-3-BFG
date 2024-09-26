const std = @import("std");
const common = @import("common.zig");
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const Transform = @import("../physics/physics.zig").Transform;
const game = @import("../game.zig");
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

const PlayerSpawn = @This();

def: common.EntityDef,
transform: Transform,

pub fn spawn(
    _: EntityHandle,
    _: std.mem.Allocator,
    spawn_args: SpawnArgs,
    _: ?*anyopaque,
) !PlayerSpawn {
    const classname = spawn_args.get("classname") orelse return error.EntityDefIsUndefined;
    const decl = game.c_findEntityDef(classname.ptr) orelse return error.EntityDefIsUndefined;

    const origin = if (spawn_args.get("origin")) |origin_str|
        common.c_parseVector(origin_str.ptr).toVec3f()
    else
        Vec3(f32){};

    const rotation = if (spawn_args.get("rotation")) |rotation_str|
        common.c_parseMatrix(rotation_str.ptr).toMat3f()
    else
        Mat3(f32).identity();

    return .{
        .def = common.EntityDef{ .index = decl.index() },
        .transform = .{
            .axis = rotation,
            .origin = origin,
        },
    };
}
