const std = @import("std");
const Transform = @import("../physics/physics.zig").Transform;
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const common = @import("common.zig");
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const JointMat = @import("../anim/animator.zig").JointMat;

const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

transform: Transform,
local_transform: Transform,
render_entity: RenderEntity,
model_def_handle: c_int = -1,
bind_joint_ptr: ?*const JointMat,
parent_link: ?EntityHandle,

const AttachableItem = @This();

pub fn spawn(
    _: EntityHandle,
    _: std.mem.Allocator,
    spawn_args: SpawnArgs,
    c_dict_ptr: ?*anyopaque,
) !AttachableItem {
    var render_entity = RenderEntity{};
    if (c_dict_ptr) |ptr| {
        render_entity.initFromSpawnArgs(ptr);
    } else return error.CSpawnArgsIsUndefined;

    const transform = transform: {
        const origin = if (spawn_args.get("origin")) |origin_str|
            common.c_parseVector(origin_str.ptr).toVec3f()
        else
            Vec3(f32){};

        const rotation = if (spawn_args.get("rotation")) |rotation_str|
            common.c_parseMatrix(rotation_str.ptr).toMat3f()
        else if (spawn_args.get("angles")) |angles_str|
            common.c_parseAngles(angles_str.ptr).toAngles().toMat3()
        else
            Mat3(f32).identity();

        break :transform .{ .origin = origin, .axis = rotation };
    };

    return .{
        .transform = .{},
        .local_transform = transform,
        .render_entity = render_entity,
        .bind_joint_ptr = null,
        .parent_link = null,
    };
}
