const std = @import("std");
const Transform = @import("../physics/physics.zig").Transform;
const JointMat = @import("../anim/animator.zig").JointMat;
const global = @import("../global.zig");
const Capture = @import("../entity.zig").Capture;
const EntityHandle = global.Entities.EntityHandle;

pub const Query = struct {
    transform: Transform,
    local_transform: Transform,
    parent_link: ?EntityHandle,
    bind_joint_ptr: ?*const JointMat,
};

pub fn update(list: anytype) void {
    var s = list.slice();

    for (
        s.items(.local_transform),
        s.items(.transform),
        s.items(.bind_joint_ptr),
        s.items(.parent_link),
    ) |local_transform, *transform, bind_joint_ptr, opt_parent_link| {
        const bind_joint = bind_joint_ptr orelse continue;
        const parent_link = opt_parent_link orelse continue;

        if (global.entities.queryByHandle(
            parent_link,
            struct { transform: Capture.value(Transform) },
        )) |result| {
            const joint_offset = bind_joint.toVec3().toVec3f();
            const joint_axis = bind_joint.toMat3().toMat3f();

            const parent_transform = result.transform;
            const master_axis = joint_axis.multiply(parent_transform.axis);
            const parent_offset = parent_transform.axis.multiplyVec3(joint_offset);
            const master_origin = parent_transform.origin.add(parent_offset);

            transform.origin = master_origin.add(
                master_axis.multiplyVec3(local_transform.origin),
            );
            transform.axis = local_transform.axis.multiply(master_axis);
        }
    }
}
