const std = @import("std");
const idlib = @import("../idlib.zig");
const Transform = @import("../physics/physics.zig").Transform;
const Animator = @import("../anim/animator.zig");
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const common = @import("common.zig");
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

const AnimatedHead = @import("animated_head.zig");

const Animated = @This();

transform: Transform,
animator: Animator,
model_def_handle: c_int = -1,
render_entity: RenderEntity,

pub fn spawn(
    _: EntityHandle,
    spawn_args: *const idlib.Dict,
    allocator: std.mem.Allocator,
) !Animated {
    var c_render_entity = RenderEntity{};
    c_render_entity.initFromSpawnArgs(spawn_args);

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

    var animator = Animator.init(allocator);
    if (spawn_args.getString("model")) |model_str| {
        const opt_render_model = try animator.setModel(model_str);
        if (opt_render_model) |render_model| {
            c_render_entity.hModel = render_model;

            if (animator.joints) |joints| {
                c_render_entity.joints = joints.ptr;
                c_render_entity.numJoints = @intCast(joints.len);
            }

            c_render_entity.bounds = CBounds.fromBounds(animator.frame_bounds);

            animator.printAnims();
            animator.cycleAnim(
                Animator.animchannel_all,
                4, // idle
                0,
                0,
            );
        }
    }

    return .{
        .transform = .{ .origin = origin, .axis = rotation },
        .render_entity = c_render_entity,
        .animator = animator,
    };
}
