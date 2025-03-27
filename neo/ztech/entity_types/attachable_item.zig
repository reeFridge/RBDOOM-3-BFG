const std = @import("std");
const Transform = @import("../physics/physics.zig").Transform;
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const idlib = @import("../idlib.zig");
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
    spawn_args: *const idlib.Dict,
    _: std.mem.Allocator,
) !AttachableItem {
    var render_entity = RenderEntity{};
    render_entity.initFromSpawnArgs(spawn_args);

    const transform: Transform = transform: {
        const origin = if (spawn_args.getString("origin")) |origin_str|
            try common.parseVec3f(origin_str)
        else
            Vec3(f32){};

        const rotation = if (spawn_args.getString("rotation")) |rotation_str|
            try common.parseMat3f(rotation_str)
        else if (spawn_args.getString("angles")) |angles_str|
            (try common.parseAngles(angles_str)).toMat3()
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
