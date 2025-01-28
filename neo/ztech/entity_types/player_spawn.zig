const std = @import("std");
const common = @import("common.zig");
const Transform = @import("../physics/physics.zig").Transform;
const game = @import("../game.zig");
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const global = @import("../global.zig");
const decl_manager = @import("../framework/decl_manager.zig");
const EntityHandle = global.Entities.EntityHandle;
const idlib = @import("../idlib.zig");

const PlayerSpawn = @This();

def: common.EntityDef,
transform: Transform,

pub fn spawn(
    _: EntityHandle,
    spawn_args: *const idlib.Dict,
    allocator: std.mem.Allocator,
) !PlayerSpawn {
    const classname = spawn_args.getString(
        "classname",
    ) orelse return error.EntityDefIsUndefined;
    const decl = try decl_manager.instance.findEntityDef(
        classname,
        allocator,
    ) orelse return error.EntityDefIsUndefined;

    const origin = if (spawn_args.getString("origin")) |origin_str|
        try common.parseVec3f(origin_str)
    else
        Vec3(f32){};

    const rotation = if (spawn_args.getString("rotation")) |rotation_str|
        try common.parseMat3f(rotation_str)
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
