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
const JointMat = @import("../anim/animator.zig").JointMat;
const common = @import("common.zig");
const global = @import("../global.zig");
const Capture = @import("../entity.zig").Capture;
const EntityHandle = global.Entities.EntityHandle;
const JointModTransform = Animator.JointMod.JointModTransform;
const DeclManager = @import("../framework/decl_manager.zig");
const DeclEntityDef = @import("../game.zig").DeclEntityDef;
const CopySpawnArgs = @import("../lib.zig").CopySpawnArgs;
const Game = @import("../game.zig");

const AnimatedHead = @import("animated_head.zig");
const AnimatedWithHead = @This();

transform: Transform,
animator: Animator,
model_def_handle: c_int = -1,
render_entity: RenderEntity,
copy_joints: CopyJoints,
attachments: Attachments,

const Attachments = struct {
    list: std.ArrayList(EntityHandle),

    pub fn component_deinit(attachments: *Attachments) void {
        attachments.list.deinit();
    }
};

const CopyJoint = struct {
    mod: JointModTransform,
    from: JointHandle,
    to: JointHandle,
};

pub const CopyJoints = struct {
    child_link: ?EntityHandle,
    list: std.ArrayList(CopyJoint),

    pub fn component_deinit(copy_joints: *CopyJoints) void {
        copy_joints.list.deinit();
        copy_joints.child_link = null;
    }
};

pub fn spawn(
    handle: EntityHandle,
    allocator: std.mem.Allocator,
    spawn_args: SpawnArgs,
    c_dict_ptr: ?*anyopaque,
) !AnimatedWithHead {
    var c_render_entity = RenderEntity{};
    if (c_dict_ptr) |ptr| {
        c_render_entity.initFromSpawnArgs(ptr);
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
        }
    } else return error.ModelIsUndefined;

    // the animation used to be set to the IK_ANIM at this point, but that was fixed, resulting in
    // attachments not binding correctly, so we're stuck setting the IK_ANIM before attaching things.
    animator.clearAllAnims(Game.instance.time, 0);
    animator.setFrame(
        Animator.animchannel_all,
        animator.getAnim(Animator.ik_anim),
        0,
        0,
        0,
    );
    // force update joint transforms
    _ = try animator.createFrame(Game.instance.time, true);

    var attachments = std.ArrayList(EntityHandle).init(allocator);
    var opt_last_index: ?usize = null;
    while (findEntryMatchedPrefix(
        &spawn_args,
        "def_attach",
        &opt_last_index,
    )) |entry| {
        const def_name = entry.value_ptr.*;
        const decl = DeclManager.instance.findType(.DECL_ENTITYDEF, def_name, false) orelse continue;
        const decl_entity: *DeclEntityDef = @ptrCast(@alignCast(decl));
        var attach_spawn_args = SpawnArgs.init(allocator);
        defer attach_spawn_args.deinit();
        CopySpawnArgs.init(&decl_entity.dict, &attach_spawn_args);
        CopySpawnArgs.copy();

        const joint_str = attach_spawn_args.get("joint") orelse continue;
        const attach_joint = animator.getJointHandle(joint_str) orelse continue;

        const type_name = attach_spawn_args.get("spawnexternal") orelse continue;
        const attach_handle = global.entities.spawn(type_name, attach_spawn_args, &decl_entity.dict) catch {
            std.debug.print("[ztech] attachment {{{s}}} spawn error\n", .{type_name});
            continue;
        };

        const attach_ent = global.entities.queryByHandle(
            attach_handle,
            struct {
                bind_joint_ptr: Capture.ref(?*const JointMat),
                parent_link: Capture.ref(?EntityHandle),
                local_transform: Capture.ref(Transform),
            },
        ).?;
        attach_ent.bind_joint_ptr.* = if (animator.joints) |joints| &joints[@intCast(attach_joint)] else null;
        attach_ent.parent_link.* = handle;

        if (animator.getJointTransform(attach_joint)) |joint_transform| {
            const joint_world_transform = Transform{
                .origin = transform.origin.add(transform.axis.multiplyVec3(joint_transform.origin)),
                .axis = joint_transform.axis.multiply(transform.axis),
            };

            const angle_offset = attach_ent.local_transform.axis;
            const origin_offset = attach_ent.local_transform.origin;

            const attach_origin = joint_world_transform.origin.add(
                transform.axis.multiplyVec3(origin_offset),
            );
            const attach_axis = angle_offset.multiply(joint_world_transform.axis);

            const master_origin = transform.origin.add(transform.axis.multiplyVec3(joint_transform.origin));
            const master_axis = joint_transform.axis.multiply(transform.axis);

            attach_ent.local_transform.origin = master_axis
                .transpose()
                .multiplyVec3(attach_origin.subtract(master_origin));
            attach_ent.local_transform.axis = attach_axis.multiply(master_axis.transpose());
        }

        try attachments.append(attach_handle);
    }

    var copy_joints = std.ArrayList(CopyJoint).init(allocator);
    const opt_head_handle = if (spawn_args.get("def_head")) |head_model_str| head_handle: {
        const head_joint_str = spawn_args.get("head_joint") orelse
            break :head_handle null;
        const head_joint = animator.getJointHandle(head_joint_str) orelse
            break :head_handle null;

        const head = try createHead(
            handle,
            allocator,
            head_model_str,
            head_joint,
            transform,
            &animator,
        );

        try copyJoints(&animator, &head.animator, &copy_joints, spawn_args);

        break :head_handle try global.entities.register(head);
    } else null;

    animator.clearAllAnims(Game.instance.time, 0);
    animator.cycleAnim(
        Animator.animchannel_all,
        4, // idle
        Game.instance.time,
        0,
    );

    return .{
        .copy_joints = .{
            .list = copy_joints,
            .child_link = opt_head_handle,
        },
        .transform = transform,
        .render_entity = c_render_entity,
        .animator = animator,
        .attachments = .{
            .list = attachments,
        },
    };
}

fn createHead(
    parent_handle: EntityHandle,
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
    var head_local_transform = Transform{};
    if (parent_animator.getJointTransform(head_joint)) |joint_transform| {
        head_local_transform.axis = joint_transform.axis.transpose();
    }

    return .{
        .parent_link = parent_handle,
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
