const std = @import("std");
const Transform = @import("../physics/physics.zig").Transform;
const Animator = @import("../anim/animator.zig");
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const findEntryMatchedPrefix = @import("../entity.zig").findEntryMatchedPrefix;
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const JointHandle = @import("../anim/animator.zig").JointHandle;
const common = @import("common.zig");
const global = @import("../global.zig");
const Capture = @import("../entity.zig").Capture;
const EntityHandle = global.Entities.EntityHandle;
const JointModTransform = Animator.JointMod.JointModTransform;

const AnimatedHead = @import("animated_head.zig");

const Animated = @This();

transform: Transform,
animator: Animator,
model_def_handle: c_int = -1,
render_entity: RenderEntity,
child_link: ?EntityHandle,
copy_joints: CopyJoints,

const CopyJoint = struct {
    mod: JointModTransform,
    from: JointHandle,
    to: JointHandle,
};

pub const CopyJoints = struct {
    list: std.ArrayList(CopyJoint),

    pub fn component_deinit(copy_joints: *CopyJoints) void {
        copy_joints.list.deinit();
    }
};

pub fn spawn(
    allocator: std.mem.Allocator,
    spawn_args: SpawnArgs,
    c_dict_ptr: ?*anyopaque,
) !EntityHandle {
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

    var copy_joints = std.ArrayList(CopyJoint).init(allocator);
    const opt_head_handle = if (spawn_args.get("def_head")) |head_model_str| head_handle: {
        const head_joint_str = spawn_args.get("head_joint") orelse
            break :head_handle null;
        const head_joint = animator.getJointHandle(head_joint_str) orelse
            break :head_handle null;

        const head = try createHead(
            allocator,
            head_model_str,
            head_joint,
            .{ .origin = origin, .axis = rotation },
            &animator,
        );

        try copyJoints(&animator, &head.animator, &copy_joints, spawn_args);

        break :head_handle try global.entities.register(head);
    } else null;

    const handle = try global.entities.register(Animated{
        .copy_joints = .{ .list = copy_joints },
        .child_link = opt_head_handle,
        .transform = .{ .origin = origin, .axis = rotation },
        .render_entity = c_render_entity,
        .animator = animator,
    });

    const head_handle = opt_head_handle orelse return handle;

    if (global.entities.queryByHandle(
        head_handle,
        struct { parent_link: Capture.ref(?EntityHandle) },
    )) |result| {
        result.parent_link.* = handle;
    }

    return handle;
}

fn createHead(
    allocator: std.mem.Allocator,
    head_model_str: []const u8,
    head_joint: JointHandle,
    parent_transform: Transform,
    parent_animator: *Animator,
) !AnimatedHead {
    var head_animator = Animator.init(allocator);
    const render_model = try head_animator.setModel(head_model_str) orelse @panic("No head model");

    var head_render_entity = RenderEntity{};

    head_render_entity.hModel = render_model;

    if (head_animator.joints) |joints| {
        head_render_entity.joints = joints.ptr;
        head_render_entity.numJoints = @intCast(joints.len);
    }

    head_render_entity.bounds = CBounds.fromBounds(head_animator.frame_bounds);

    head_animator.printAnims();
    head_animator.cycleAnim(
        Animator.animchannel_all,
        3, // idle
        0,
        0,
    );

    const head_transform = parent_transform;
    var head_local_transform = head_transform;
    const opt_joint_transform = try parent_animator.getJointTransform(head_joint, 0);
    if (opt_joint_transform) |joint_transform| {
        head_local_transform.axis = joint_transform.axis.transpose();
    }

    return .{
        .parent_link = null,
        .transform = head_transform,
        .local_transform = head_local_transform,
        .render_entity = head_render_entity,
        .animator = head_animator,
        .bind_joint_ptr = if (parent_animator.joints) |joints|
            &joints[@intCast(head_joint)]
        else
            null,
    };
}

fn copyJoints(
    animator: *const Animator,
    head_animator: *const Animator,
    copy_joints: *std.ArrayList(CopyJoint),
    spawn_args: SpawnArgs,
) !void {
    var opt_last_index: ?usize = null;
    const copy_joint_prefix = "copy_joint";
    while (findEntryMatchedPrefix(
        &spawn_args,
        copy_joint_prefix,
        &opt_last_index,
    )) |entry| {
        var copy_joint = CopyJoint{
            .mod = .local_override,
            .from = -1,
            .to = -1,
        };

        const from_joint_name = entry.key_ptr.*[copy_joint_prefix.len + 1 ..];
        if (animator.getJointHandle(from_joint_name)) |copy_from| {
            copy_joint.from = copy_from;
        } else continue;

        if (head_animator.getJointHandle(entry.value_ptr.*)) |copy_to| {
            copy_joint.to = copy_to;
        } else continue;

        std.debug.print("copy_joint entry = from: {s} to: {s}\n", .{ from_joint_name, entry.value_ptr.* });
        try copy_joints.append(copy_joint);
    }
}
