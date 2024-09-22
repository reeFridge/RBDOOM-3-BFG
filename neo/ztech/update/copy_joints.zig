const Animator = @import("../anim/animator.zig");
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;
const CopyJoints = @import("../entity_types/animated.zig").CopyJoints;
const Capture = @import("../entity.zig").Capture;
const Game = @import("../game.zig");

pub const Query = struct {
    animator: Animator,
    child_link: ?EntityHandle,
    copy_joints: CopyJoints,
};

pub fn update(list: anytype) void {
    var s = list.slice();

    for (
        s.items(.animator),
        s.items(.copy_joints),
        s.items(.child_link),
    ) |*animator, copy_joints, child_link| {
        const child_handle = child_link orelse continue;
        const child = global.entities.queryByHandle(
            child_handle,
            struct {
                animator: Capture.ref(Animator),
            },
        ) orelse continue;

        for (copy_joints.list.items) |copy_joint| {
            const opt_transform = animator.getJointLocalTransform(copy_joint.from, Game.instance.time) catch @panic("OOM");
            const joint_local_transform = opt_transform orelse continue;

            child.animator.setJointPos(
                copy_joint.to,
                copy_joint.mod,
                joint_local_transform.origin,
            ) catch @panic("OOM");

            child.animator.setJointAxis(
                copy_joint.to,
                copy_joint.mod,
                joint_local_transform.axis,
            ) catch @panic("OOM");
        }
    }
}
