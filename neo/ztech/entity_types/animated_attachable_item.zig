const std = @import("std");
const idlib = @import("../idlib.zig");
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Transform = @import("../physics/physics.zig").Transform;
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const common = @import("common.zig");
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const JointMat = @import("../anim/animator.zig").JointMat;
const Animator = @import("../anim/animator.zig");

const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

animator: Animator,
transform: Transform,
local_transform: Transform,
render_entity: RenderEntity,
model_def_handle: c_int = -1,
bind_joint_ptr: ?*const JointMat,
parent_link: ?EntityHandle,

const AnimatedAttachableItem = @This();

pub fn spawn(
    _: EntityHandle,
    spawn_args: *const idlib.Dict,
    allocator: std.mem.Allocator,
) !AnimatedAttachableItem {
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

    var animator = Animator.init(allocator);
    if (spawn_args.getString("model")) |model_str| {
        const opt_render_model = try animator.setModel(model_str);
        if (opt_render_model) |render_model| {
            render_entity.hModel = render_model;

            if (animator.joints) |joints| {
                render_entity.joints = joints.ptr;
                render_entity.numJoints = @intCast(joints.len);
            }

            render_entity.bounds = CBounds.fromBounds(animator.frame_bounds);
        }
    }

    return .{
        .animator = animator,
        .transform = .{},
        .local_transform = transform,
        .render_entity = render_entity,
        .bind_joint_ptr = null,
        .parent_link = null,
    };
}
