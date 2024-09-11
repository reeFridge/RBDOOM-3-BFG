const std = @import("std");
const Transform = @import("../physics/physics.zig").Transform;
const Animator = @import("../anim/animator.zig");
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const common = @import("common.zig");

const Animated = @This();

transform: Transform,
animator: Animator,
model_def_handle: c_int = -1,
render_entity: RenderEntity,

pub fn spawn(
    allocator: std.mem.Allocator,
    spawn_args: SpawnArgs,
    c_dict_ptr: ?*anyopaque,
) !Animated {
    var c_render_entity = RenderEntity{};
    if (c_dict_ptr) |ptr| {
        c_render_entity.initFromSpawnArgs(ptr);
    } else return error.CSpawnArgsIsUndefined;

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

    var animator = Animator.init(allocator);
    if (spawn_args.get("model")) |model_str| {
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
