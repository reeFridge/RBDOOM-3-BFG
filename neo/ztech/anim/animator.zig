const std = @import("std");
const CMat3 = @import("../math/matrix.zig").CMat3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;
const Quat = @import("../math/quat.zig").Quat;
const Bounds = @import("../bounding_volume/bounds.zig");
const idList = @import("../idlib.zig").idList;
const RenderModel = @import("../renderer/model.zig").RenderModel;
const DeclManager = @import("../framework/decl_manager.zig");
const Transform = @import("../physics/physics.zig").Transform;

const num_anim_channels: usize = 5;
const max_anims_per_channel: usize = 3;
const max_synced_anims: usize = 3;

pub const animchannel_all: usize = 0;

const AnimBlend = extern struct {
    modelDef: ?*const DeclModelDef,
    starttime: c_int,
    endtime: c_int,
    timeOffset: c_int,
    rate: f32,
    blendStartTime: c_int,
    blendDuration: c_int,
    blendStartValue: f32,
    blendEndValue: f32,
    animWeights: [max_synced_anims]f32,
    cycle: c_short,
    frame: c_short,
    animNum: c_short,
    allowMove: bool,
    allowFrameCommands: bool,

    extern fn c_animBlend_blendAnim(
        *AnimBlend,
        c_int,
        c_int,
        c_int,
        [*]JointQuat,
        *f32,
        bool,
        bool,
        bool,
    ) bool;

    extern fn c_animBlend_playAnim(
        *AnimBlend,
        *const DeclModelDef,
        c_int,
        c_int,
        c_int,
    ) void;

    extern fn c_animBlend_cycleAnim(
        *AnimBlend,
        *const DeclModelDef,
        c_int,
        c_int,
        c_int,
    ) void;

    pub fn getWeight(blend: *const AnimBlend, current_time: usize) f32 {
        const time_delta: i64 = @as(i64, @intCast(current_time)) - @as(i64, @intCast(blend.blendStartTime));

        return if (time_delta <= 0) blend.blendStartValue else if (time_delta >= blend.blendDuration) blend.blendEndValue else weight: {
            const time_delta_f: f32 = @floatFromInt(time_delta);
            const blend_duration_f: f32 = @floatFromInt(blend.blendDuration);
            const fraction = time_delta_f / blend_duration_f;
            break :weight blend.blendStartValue + (blend.blendEndValue - blend.blendStartValue) * fraction;
        };
    }

    pub fn clear(blend: *AnimBlend, current_time: usize, clear_time: usize) void {
        if (clear_time == 0) {
            blend.reset(blend.modelDef);
        } else {
            blend.setWeight(0, current_time, clear_time);
        }
    }

    pub fn setWeight(blend: *AnimBlend, weight: f32, current_time: usize, blend_time: usize) void {
        blend.blendStartValue = blend.getWeight(current_time);
        blend.blendEndValue = weight;
        blend.blendStartTime = @intCast(current_time - 1);
        blend.blendDuration = @intCast(blend_time);

        if (weight <= 0) {
            blend.endtime = @intCast(current_time + blend_time);
        }
    }

    pub fn reset(blend: *AnimBlend, model_def: ?*const DeclModelDef) void {
        blend.modelDef = model_def;
        blend.cycle = 1;
        blend.starttime = 0;
        blend.endtime = 0;
        blend.timeOffset = 0;
        blend.rate = 1;
        blend.frame = 0;
        blend.allowMove = true;
        blend.allowFrameCommands = true;
        blend.animNum = 0;

        blend.animWeights = std.mem.zeroes([max_synced_anims]f32);

        blend.blendStartValue = 0;
        blend.blendEndValue = 0;
        blend.blendStartTime = 0;
        blend.blendDuration = 0;
    }

    pub fn blendAnim(
        blend: *AnimBlend,
        current_time: usize,
        channel: usize,
        num_joints: usize,
        blend_frame: []JointQuat,
        blend_weight: *f32,
        remove_origin_offset: bool,
        override_blend: bool,
        print_info: bool,
    ) bool {
        return c_animBlend_blendAnim(
            blend,
            @intCast(current_time),
            @intCast(channel),
            @intCast(num_joints),
            blend_frame.ptr,
            blend_weight,
            remove_origin_offset,
            override_blend,
            print_info,
        );
    }

    pub fn playAnim(
        blend: *AnimBlend,
        model_def: *const DeclModelDef,
        anim_num: usize,
        current_time: usize,
        blend_time: usize,
    ) void {
        c_animBlend_playAnim(
            blend,
            model_def,
            @intCast(anim_num),
            @intCast(current_time),
            @intCast(blend_time),
        );
    }

    pub fn cycleAnim(
        blend: *AnimBlend,
        model_def: *const DeclModelDef,
        anim_num: usize,
        current_time: usize,
        blend_time: usize,
    ) void {
        c_animBlend_cycleAnim(
            blend,
            model_def,
            @intCast(anim_num),
            @intCast(current_time),
            @intCast(blend_time),
        );
    }
};

const JointQuat = extern struct {
    q: Quat,
    t: CVec3,
    w: f32,
};

pub const JointMat = extern struct {
    mat: [3 * 4]f32,

    pub fn toMat3(j: JointMat) CMat3 {
        return .{ .mat = .{
            .{ .x = j.mat[0 * 4 + 0], .y = j.mat[1 * 4 + 0], .z = j.mat[2 * 4 + 0] },
            .{ .x = j.mat[0 * 4 + 1], .y = j.mat[1 * 4 + 1], .z = j.mat[2 * 4 + 1] },
            .{ .x = j.mat[0 * 4 + 2], .y = j.mat[1 * 4 + 2], .z = j.mat[2 * 4 + 2] },
        } };
    }

    pub fn setRotation(j: *JointMat, m: CMat3) void {
        // NOTE: CMat3 is transposed because it is column-major
        j.mat[0 * 4 + 0] = m.mat[0].x;
        j.mat[0 * 4 + 1] = m.mat[1].x;
        j.mat[0 * 4 + 2] = m.mat[2].x;
        j.mat[1 * 4 + 0] = m.mat[0].y;
        j.mat[1 * 4 + 1] = m.mat[1].y;
        j.mat[1 * 4 + 2] = m.mat[2].y;
        j.mat[2 * 4 + 0] = m.mat[0].z;
        j.mat[2 * 4 + 1] = m.mat[1].z;
        j.mat[2 * 4 + 2] = m.mat[2].z;
    }

    pub fn toVec3(j: JointMat) CVec3 {
        return .{
            .x = j.mat[0 * 4 + 3],
            .y = j.mat[1 * 4 + 3],
            .z = j.mat[2 * 4 + 3],
        };
    }

    pub fn setTranslation(j: *JointMat, t: CVec3) void {
        j.mat[0 * 4 + 3] = t.x;
        j.mat[1 * 4 + 3] = t.y;
        j.mat[2 * 4 + 3] = t.z;
    }

    pub fn divideJoint(j: *JointMat, a: JointMat) void {
        var tmp = std.mem.zeroes([3]f32);

        j.mat[0 * 4 + 3] -= a.mat[0 * 4 + 3];
        j.mat[1 * 4 + 3] -= a.mat[1 * 4 + 3];
        j.mat[2 * 4 + 3] -= a.mat[2 * 4 + 3];

        tmp[0] =
            j.mat[0 * 4 + 0] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 0] * a.mat[1 * 4 + 0] +
            j.mat[2 * 4 + 0] * a.mat[2 * 4 + 0];
        tmp[1] =
            j.mat[0 * 4 + 0] * a.mat[0 * 4 + 1] +
            j.mat[1 * 4 + 0] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 0] * a.mat[2 * 4 + 1];
        tmp[2] =
            j.mat[0 * 4 + 0] * a.mat[0 * 4 + 2] +
            j.mat[1 * 4 + 0] * a.mat[1 * 4 + 2] +
            j.mat[2 * 4 + 0] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 0] = tmp[0];
        j.mat[1 * 4 + 0] = tmp[1];
        j.mat[2 * 4 + 0] = tmp[2];

        tmp[0] =
            j.mat[0 * 4 + 1] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 1] * a.mat[1 * 4 + 0] +
            j.mat[2 * 4 + 1] * a.mat[2 * 4 + 0];
        tmp[1] =
            j.mat[0 * 4 + 1] * a.mat[0 * 4 + 1] +
            j.mat[1 * 4 + 1] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 1] * a.mat[2 * 4 + 1];
        tmp[2] =
            j.mat[0 * 4 + 1] * a.mat[0 * 4 + 2] +
            j.mat[1 * 4 + 1] * a.mat[1 * 4 + 2] +
            j.mat[2 * 4 + 1] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 1] = tmp[0];
        j.mat[1 * 4 + 1] = tmp[1];
        j.mat[2 * 4 + 1] = tmp[2];

        tmp[0] =
            j.mat[0 * 4 + 2] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 2] * a.mat[1 * 4 + 0] +
            j.mat[2 * 4 + 2] * a.mat[2 * 4 + 0];
        tmp[1] =
            j.mat[0 * 4 + 2] * a.mat[0 * 4 + 1] +
            j.mat[1 * 4 + 2] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 2] * a.mat[2 * 4 + 1];
        tmp[2] =
            j.mat[0 * 4 + 2] * a.mat[0 * 4 + 2] +
            j.mat[1 * 4 + 2] * a.mat[1 * 4 + 2] +
            j.mat[2 * 4 + 2] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 2] = tmp[0];
        j.mat[1 * 4 + 2] = tmp[1];
        j.mat[2 * 4 + 2] = tmp[2];

        tmp[0] =
            j.mat[0 * 4 + 3] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 3] * a.mat[1 * 4 + 0] +
            j.mat[2 * 4 + 3] * a.mat[2 * 4 + 0];
        tmp[1] =
            j.mat[0 * 4 + 3] * a.mat[0 * 4 + 1] +
            j.mat[1 * 4 + 3] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 3] * a.mat[2 * 4 + 1];
        tmp[2] =
            j.mat[0 * 4 + 3] * a.mat[0 * 4 + 2] +
            j.mat[1 * 4 + 3] * a.mat[1 * 4 + 2] +
            j.mat[2 * 4 + 3] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 3] = tmp[0];
        j.mat[1 * 4 + 3] = tmp[1];
        j.mat[2 * 4 + 3] = tmp[2];
    }

    pub fn multiplyJoint(j: *JointMat, a: JointMat) void {
        var tmp = std.mem.zeroes([3]f32);

        tmp[0] =
            j.mat[0 * 4 + 0] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 0] * a.mat[0 * 4 + 1] +
            j.mat[2 * 4 + 0] * a.mat[0 * 4 + 2];
        tmp[1] =
            j.mat[0 * 4 + 0] * a.mat[1 * 4 + 0] +
            j.mat[1 * 4 + 0] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 0] * a.mat[1 * 4 + 2];
        tmp[2] =
            j.mat[0 * 4 + 0] * a.mat[2 * 4 + 0] +
            j.mat[1 * 4 + 0] * a.mat[2 * 4 + 1] +
            j.mat[2 * 4 + 0] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 0] = tmp[0];
        j.mat[1 * 4 + 0] = tmp[1];
        j.mat[2 * 4 + 0] = tmp[2];

        tmp[0] =
            j.mat[0 * 4 + 1] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 1] * a.mat[0 * 4 + 1] +
            j.mat[2 * 4 + 1] * a.mat[0 * 4 + 2];
        tmp[1] =
            j.mat[0 * 4 + 1] * a.mat[1 * 4 + 0] +
            j.mat[1 * 4 + 1] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 1] * a.mat[1 * 4 + 2];
        tmp[2] =
            j.mat[0 * 4 + 1] * a.mat[2 * 4 + 0] +
            j.mat[1 * 4 + 1] * a.mat[2 * 4 + 1] +
            j.mat[2 * 4 + 1] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 1] = tmp[0];
        j.mat[1 * 4 + 1] = tmp[1];
        j.mat[2 * 4 + 1] = tmp[2];

        tmp[0] =
            j.mat[0 * 4 + 2] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 2] * a.mat[0 * 4 + 1] +
            j.mat[2 * 4 + 2] * a.mat[0 * 4 + 2];
        tmp[1] =
            j.mat[0 * 4 + 2] * a.mat[1 * 4 + 0] +
            j.mat[1 * 4 + 2] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 2] * a.mat[1 * 4 + 2];
        tmp[2] =
            j.mat[0 * 4 + 2] * a.mat[2 * 4 + 0] +
            j.mat[1 * 4 + 2] * a.mat[2 * 4 + 1] +
            j.mat[2 * 4 + 2] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 2] = tmp[0];
        j.mat[1 * 4 + 2] = tmp[1];
        j.mat[2 * 4 + 2] = tmp[2];

        tmp[0] =
            j.mat[0 * 4 + 3] * a.mat[0 * 4 + 0] +
            j.mat[1 * 4 + 3] * a.mat[0 * 4 + 1] +
            j.mat[2 * 4 + 3] * a.mat[0 * 4 + 2];
        tmp[1] =
            j.mat[0 * 4 + 3] * a.mat[1 * 4 + 0] +
            j.mat[1 * 4 + 3] * a.mat[1 * 4 + 1] +
            j.mat[2 * 4 + 3] * a.mat[1 * 4 + 2];
        tmp[2] =
            j.mat[0 * 4 + 3] * a.mat[2 * 4 + 0] +
            j.mat[1 * 4 + 3] * a.mat[2 * 4 + 1] +
            j.mat[2 * 4 + 3] * a.mat[2 * 4 + 2];

        j.mat[0 * 4 + 3] = tmp[0];
        j.mat[1 * 4 + 3] = tmp[1];
        j.mat[2 * 4 + 3] = tmp[2];

        j.mat[0 * 4 + 3] += a.mat[0 * 4 + 3];
        j.mat[1 * 4 + 3] += a.mat[1 * 4 + 3];
        j.mat[2 * 4 + 3] += a.mat[2 * 4 + 3];
    }
};

const JointInfo = extern struct {
    num: JointHandle,
    parentNum: JointHandle,
    channel: c_int,
};

const DeclModelDef = opaque {
    extern fn c_declModelDef_getDefaultPose(*const DeclModelDef, *usize) ?[*]const JointQuat;
    extern fn c_declModelDef_getJointsList(*const DeclModelDef) *idList(JointInfo);
    extern fn c_declModelDef_getVisualOffset(*const DeclModelDef) CVec3;
    extern fn c_declModelDef_jointParents(*const DeclModelDef, *usize) [*]const c_int;
    extern fn c_declModelDef_modelHandle(*const DeclModelDef) ?*RenderModel;
    extern fn c_declModelDef_touch(*const DeclModelDef) void;
    extern fn c_declModelDef_hasAnim(*const DeclModelDef, c_int) bool;

    pub fn hasAnim(def: *const DeclModelDef, index: usize) bool {
        return c_declModelDef_hasAnim(def, @intCast(index));
    }

    pub fn modelHandle(def: *const DeclModelDef) ?*RenderModel {
        return c_declModelDef_modelHandle(def);
    }

    pub fn touch(def: *const DeclModelDef) void {
        c_declModelDef_touch(def);
    }

    pub fn getDefaultPose(def: *const DeclModelDef) ?[]const JointQuat {
        var joints_len: usize = 0;
        const opt_ptr = c_declModelDef_getDefaultPose(def, &joints_len);

        return if (opt_ptr) |ptr| ptr[0..joints_len] else null;
    }

    pub fn joints(def: *const DeclModelDef) *idList(JointInfo) {
        return c_declModelDef_getJointsList(def);
    }

    pub fn getVisualOffset(def: *const DeclModelDef) CVec3 {
        return c_declModelDef_getVisualOffset(def);
    }

    pub fn jointParents(def: *const DeclModelDef) []const c_int {
        var len: usize = 0;

        return c_declModelDef_jointParents(def, &len)[0..len];
    }
};

pub const JointHandle = c_int;

pub const JointMod = extern struct {
    pub const JointModTransform = enum(c_int) {
        none,
        local,
        local_override,
        world,
        world_override,
    };

    jointnum: JointHandle,
    mat: CMat3,
    pos: CVec3,
    transform_pos: JointModTransform,
    transform_axis: JointModTransform,
};

allocator: std.mem.Allocator,
channels: [num_anim_channels][max_anims_per_channel]AnimBlend,
last_transform_time: usize = 0,
model_def: ?*const DeclModelDef = null,
joint_mods: std.ArrayList(*JointMod),
joints: ?[]align(16) JointMat = null,
af_pose_joint_frame: std.ArrayList(JointQuat),
af_pose_joints: std.ArrayList(usize),
af_pose_blend_weight: f32 = 0,
remove_origin_offset: bool = false,
frame_bounds: Bounds = Bounds.cleared,

const Animator = @This();

pub fn component_deinit(animator: *Animator) void {
    animator.deinit();
}

pub fn init(allocator: std.mem.Allocator) Animator {
    return .{
        .af_pose_blend_weight = 1,
        .allocator = allocator,
        .joint_mods = std.ArrayList(*JointMod).init(allocator),
        .af_pose_joint_frame = std.ArrayList(JointQuat).init(allocator),
        .af_pose_joints = std.ArrayList(usize).init(allocator),
        .channels = std.mem.zeroes([num_anim_channels][max_anims_per_channel]AnimBlend),
    };
}

fn freeData(animator: *Animator) void {
    animator.resetChannels();
    for (animator.joint_mods.items) |ptr| {
        animator.allocator.destroy(ptr);
    }
    animator.joint_mods.clearAndFree();

    if (animator.joints) |joints| {
        animator.allocator.free(joints);
        animator.joints = null;
    }

    animator.model_def = null;
}

pub fn setModel(animator: *Animator, model_name: []const u8) error{OutOfMemory}!?*RenderModel {
    animator.freeData();

    const decl = DeclManager.instance.findType(
        .DECL_MODELDEF,
        model_name,
        false,
    ) orelse return null;
    const model_decl: *DeclModelDef = @ptrCast(decl);
    const render_model: *RenderModel = model_decl.modelHandle() orelse return null;

    animator.model_def = model_decl;

    model_decl.touch();
    try animator.setupJoints(model_decl);
    animator.frame_bounds = render_model.bounds().toBounds();
    render_model.reset();

    for (0..num_anim_channels) |i| {
        for (0..max_anims_per_channel) |j| {
            animator.channels[i][j].reset(model_decl);
        }
    }

    return render_model;
}

inline fn setupJoints(
    animator: *Animator,
    model_def: *const DeclModelDef,
) error{OutOfMemory}!void {
    const num_joints: usize = @intCast(model_def.joints().num);
    if (num_joints == 0) @panic("model has no joints!");

    const pose = model_def.getDefaultPose() orelse @panic("no default pose");

    const list = try animator.allocator.alignedAlloc(JointMat, 16, num_joints);
    convertJointQuatsToJointMats(list, pose);

    if (animator.remove_origin_offset) {
        list[0].setTranslation(model_def.getVisualOffset());
    } else {
        const pose_translation = pose[0].t.toVec3f();
        const offset = model_def.getVisualOffset().toVec3f();
        list[0].setTranslation(CVec3.fromVec3f(pose_translation.add(offset)));
    }

    const joint_parent = model_def.jointParents();
    transformJoints(list, joint_parent, 1, num_joints - 1);

    animator.joints = list;
}

pub fn resetChannels(animator: *Animator) void {
    for (0..num_anim_channels) |i| {
        for (0..max_anims_per_channel) |j| {
            animator.channels[i][j].reset(null);
        }
    }
}

pub fn deinit(animator: *Animator) void {
    animator.freeData();

    animator.joint_mods.deinit();
    animator.af_pose_joint_frame.deinit();
    animator.af_pose_joints.deinit();
}

pub fn playAnim(
    animator: *Animator,
    channel_num: usize,
    anim_num: usize,
    current_time: usize,
    blend_time: usize,
) void {
    const model_def = animator.model_def orelse return;
    const has_anim = model_def.hasAnim(anim_num);
    if (!has_anim) return;

    animator.pushAnims(
        model_def,
        channel_num,
        current_time,
        blend_time,
    );
    animator.channels[channel_num][0].playAnim(
        model_def,
        anim_num,
        current_time,
        blend_time,
    );
}

pub fn cycleAnim(
    animator: *Animator,
    channel_num: usize,
    anim_num: usize,
    current_time: usize,
    blend_time: usize,
) void {
    const model_def = animator.model_def orelse return;
    const has_anim = model_def.hasAnim(anim_num);
    if (!has_anim) return;

    animator.pushAnims(
        model_def,
        channel_num,
        current_time,
        blend_time,
    );
    animator.channels[channel_num][0].cycleAnim(
        model_def,
        anim_num,
        current_time,
        blend_time,
    );
}

pub fn pushAnims(
    animator: *Animator,
    model_def: *const DeclModelDef,
    channel_num: usize,
    current_time: usize,
    blend_time: usize,
) void {
    const channel = &animator.channels[channel_num];
    if (channel[0].getWeight(current_time) == 0 or
        @as(usize, @intCast(channel[0].starttime)) == current_time) return;

    var i = max_anims_per_channel;
    while (i > 0) : (i -= 1) {
        channel[i] = channel[i - 1];
    }

    channel[0].reset(model_def);
    channel[1].clear(current_time, blend_time);
}

extern fn c_animator_printAnims(*const DeclModelDef) void;
pub fn printAnims(animator: *const Animator) void {
    if (animator.model_def) |model_def| {
        c_animator_printAnims(model_def);
    }
}

pub fn getJointHandle(animator: *const Animator, joint_name: []const u8) ?JointHandle {
    const model_def = animator.model_def orelse return null;
    const render_model: *RenderModel = model_def.modelHandle() orelse return null;

    return render_model.getJointHandle(joint_name);
}

pub fn setJointPos(
    animator: *Animator,
    joint_handle: JointHandle,
    transform_type: JointMod.JointModTransform,
    pos: Vec3(f32),
) error{OutOfMemory}!void {
    const model_def = animator.model_def orelse return;
    if (joint_handle >= model_def.joints().num) {
        return;
    }

    var opt_joint_mod: ?*JointMod = null;
    var i: usize = 0;
    for (animator.joint_mods.items) |joint_mod_ptr| {
        if (joint_mod_ptr.jointnum == joint_handle) {
            opt_joint_mod = joint_mod_ptr;
            break;
        } else if (joint_mod_ptr.jointnum > joint_handle) {
            break;
        }

        i += 1;
    }

    var joint_mod = opt_joint_mod orelse joint_mod: {
        var mod = try animator.allocator.create(JointMod);
        errdefer animator.allocator.destroy(mod);
        mod.jointnum = joint_handle;
        mod.mat = CMat3{};
        mod.transform_axis = .none;

        try animator.joint_mods.resize(animator.joint_mods.items.len);
        try animator.joint_mods.insert(i, mod);

        break :joint_mod mod;
    };

    joint_mod.pos = CVec3.fromVec3f(pos);
    joint_mod.transform_pos = transform_type;
}

pub fn setJointAxis(
    animator: *Animator,
    joint_handle: JointHandle,
    transform_type: JointMod.JointModTransform,
    axis: Mat3(f32),
) error{OutOfMemory}!void {
    const model_def = animator.model_def orelse return;
    if (joint_handle >= model_def.joints().num) {
        return;
    }

    var opt_joint_mod: ?*JointMod = null;
    var i: usize = 0;
    for (animator.joint_mods.items) |joint_mod_ptr| {
        if (joint_mod_ptr.jointnum == joint_handle) {
            opt_joint_mod = joint_mod_ptr;
            break;
        } else if (joint_mod_ptr.jointnum > joint_handle) {
            break;
        }

        i += 1;
    }

    var joint_mod = opt_joint_mod orelse joint_mod: {
        var mod = try animator.allocator.create(JointMod);
        errdefer animator.allocator.destroy(mod);
        mod.jointnum = joint_handle;
        mod.pos = CVec3{};
        mod.transform_pos = .none;

        try animator.joint_mods.resize(animator.joint_mods.items.len);
        try animator.joint_mods.insert(i, mod);

        break :joint_mod mod;
    };

    joint_mod.mat = CMat3.fromMat3f(axis);
    joint_mod.transform_axis = transform_type;
}

pub fn getJointLocalTransform(
    animator: *Animator,
    joint_handle: JointHandle,
    current_time: usize,
) error{OutOfMemory}!?Transform {
    const model_def = animator.model_def orelse return null;
    if (joint_handle >= model_def.joints().num) {
        return null;
    }

    _ = try animator.createFrame(current_time);
    const joints = animator.joints orelse return null;

    var transform = Transform{};
    // @fridge TODO
    // RB: long neck GCC compiler bug workaround from dhewm3 ...
    if (joint_handle == 0) {
        transform.origin = joints[@intCast(joint_handle)].toVec3().toVec3f();
        transform.axis = joints[@intCast(joint_handle)].toMat3().toMat3f();

        return transform;
    }

    var m = joints[@intCast(joint_handle)];
    const model_joints = model_def.joints().slice();
    const parent_handle = model_joints[@intCast(joint_handle)].parentNum;
    m.divideJoint(joints[@intCast(parent_handle)]);
    transform.origin = m.toVec3().toVec3f();
    transform.axis = m.toMat3().toMat3f();

    return transform;
}

/// Transform relative to master
pub fn getJointTransform(
    animator: *Animator,
    joint_handle: JointHandle,
    current_time: usize,
) error{OutOfMemory}!?Transform {
    const model_def = animator.model_def orelse return null;
    if (joint_handle >= model_def.joints().num) {
        return null;
    }

    _ = try animator.createFrame(current_time);
    const joints = animator.joints orelse return null;

    var transform = Transform{};
    transform.origin = joints[@intCast(joint_handle)].toVec3().toVec3f();
    transform.axis = joints[@intCast(joint_handle)].toMat3().toMat3f();

    return transform;
}

pub fn createFrame(
    animator: *Animator,
    current_time: usize,
) error{OutOfMemory}!bool {
    const model_def = animator.model_def orelse return false;

    if (animator.last_transform_time == current_time) return false;

    animator.last_transform_time = current_time;

    // init the joint buffer
    const opt_default_pose = if (animator.af_pose_joints.items.len > 0)
        animator.af_pose_joint_frame.items
    else
        model_def.getDefaultPose();

    const default_pose = opt_default_pose orelse return false;

    const num_joints: usize = @intCast(model_def.joints().num);
    const joint_frame = try animator.allocator.alloc(JointQuat, num_joints);
    defer animator.allocator.free(joint_frame);
    @memcpy(joint_frame, default_pose);

    var has_anim = false;
    var base_blend: f32 = 0;

    for (&animator.channels[animchannel_all]) |*blend| {
        if (blend.blendAnim(
            current_time,
            animchannel_all,
            num_joints,
            joint_frame,
            &base_blend,
            animator.remove_origin_offset,
            false,
            false,
        )) {
            has_anim = true;
            if (base_blend >= 1) break;
        }
    }

    if (animator.blendAfPose(joint_frame)) {
        has_anim = true;
    }

    if (!has_anim and animator.joint_mods.items.len == 0) return false;

    const joints = animator.joints orelse return false;
    convertJointQuatsToJointMats(joints, joint_frame);

    var start_joint_mod: usize = 0;
    if (animator.joint_mods.items.len > 0 and
        animator.joint_mods.items[0].jointnum == 0)
    {
        start_joint_mod = 1;
        const joint_mod: *const JointMod = animator.joint_mods.items[0];

        switch (joint_mod.transform_axis) {
            .local => {
                const joint_rotation = joints[0].toMat3().toMat3f();
                const mod_rotation = joint_mod.mat.toMat3f();
                joints[0].setRotation(
                    CMat3.fromMat3f(mod_rotation.multiply(joint_rotation)),
                );
            },
            .world => {
                const joint_rotation = joints[0].toMat3().toMat3f();
                const mod_rotation = joint_mod.mat.toMat3f();
                joints[0].setRotation(
                    CMat3.fromMat3f(joint_rotation.multiply(mod_rotation)),
                );
            },
            .local_override, .world_override => {
                joints[0].setRotation(joint_mod.mat);
            },
            .none => {},
        }

        switch (joint_mod.transform_pos) {
            .local => {
                const mod_pos = joint_mod.pos.toVec3f();
                const joint_pos = joints[0].toVec3().toVec3f();
                joints[0].setTranslation(CVec3.fromVec3f(joint_pos.add(mod_pos)));
            },
            .local_override, .world, .world_override => {
                joints[0].setTranslation(joint_mod.pos);
            },
            .none => {},
        }
    }

    const visual_offset = model_def.getVisualOffset().toVec3f();
    joints[0].setTranslation(
        CVec3.fromVec3f(joints[0].toVec3().toVec3f().add(visual_offset)),
    );

    const joint_parent = model_def.jointParents();

    var i: usize = 1;
    for (animator.joint_mods.items[start_joint_mod..]) |joint_mod| {
        transformJoints(joints, joint_parent, i, @intCast(joint_mod.jointnum - 1));
        i = @intCast(joint_mod.jointnum);

        const parent_num: usize = @intCast(joint_parent[i]);

        switch (joint_mod.transform_axis) {
            .none => {
                const joint_rotation = joints[i].toMat3().toMat3f();
                const parent_joint_rotation = joints[parent_num].toMat3().toMat3f();
                joints[i].setRotation(CMat3.fromMat3f(
                    joint_rotation.multiply(parent_joint_rotation),
                ));
            },
            .local => {
                const joint_rotation = joints[i].toMat3().toMat3f();
                const parent_joint_rotation = joints[parent_num].toMat3().toMat3f();
                const mod_rotation = joint_mod.mat.toMat3f();
                joints[i].setRotation(CMat3.fromMat3f(
                    mod_rotation.multiply(
                        joint_rotation.multiply(parent_joint_rotation),
                    ),
                ));
            },
            .local_override => {
                const mod_rotation = joint_mod.mat.toMat3f();
                const parent_joint_rotation = joints[parent_num].toMat3().toMat3f();
                joints[i].setRotation(CMat3.fromMat3f(
                    mod_rotation.multiply(parent_joint_rotation),
                ));
            },
            .world => {
                const joint_rotation = joints[i].toMat3().toMat3f();
                const parent_joint_rotation = joints[parent_num].toMat3().toMat3f();
                const mod_rotation = joint_mod.mat.toMat3f();
                joints[i].setRotation(CMat3.fromMat3f(
                    joint_rotation.multiply(parent_joint_rotation)
                        .multiply(mod_rotation),
                ));
            },
            .world_override => {
                joints[i].setRotation(joint_mod.mat);
            },
        }

        switch (joint_mod.transform_pos) {
            .none => {
                const joint_pos = joints[i].toVec3().toVec3f();
                const parent_joint_pos = joints[parent_num].toVec3().toVec3f();
                joints[i].setTranslation(CVec3.fromVec3f(
                    joint_pos.add(parent_joint_pos),
                ));
            },
            .local => {
                const joint_pos = joints[i].toVec3().toVec3f();
                const parent_joint_pos = joints[parent_num].toVec3().toVec3f();
                const mod_pos = joint_mod.pos.toVec3f();
                const parent_rotation = joints[parent_num].toMat3().toMat3f();
                joints[i].setTranslation(CVec3.fromVec3f(
                    parent_joint_pos.add(
                        parent_rotation.multiplyVec3(joint_pos.add(mod_pos)),
                    ),
                ));
            },
            .local_override => {
                const parent_joint_pos = joints[parent_num].toVec3().toVec3f();
                const mod_pos = joint_mod.pos.toVec3f();
                const parent_rotation = joints[parent_num].toMat3().toMat3f();
                joints[i].setTranslation(CVec3.fromVec3f(
                    parent_joint_pos.add(
                        parent_rotation.multiplyVec3(mod_pos),
                    ),
                ));
            },
            .world => {
                const joint_pos = joints[i].toVec3().toVec3f();
                const parent_joint_pos = joints[parent_num].toVec3().toVec3f();
                const mod_pos = joint_mod.pos.toVec3f();
                const parent_rotation = joints[parent_num].toMat3().toMat3f();
                joints[i].setTranslation(CVec3.fromVec3f(
                    parent_joint_pos
                        .add(parent_rotation.multiplyVec3(joint_pos))
                        .add(mod_pos),
                ));
            },
            .world_override => {
                joints[i].setTranslation(joint_mod.pos);
            },
        }

        i += 1;
    }

    transformJoints(joints, joint_parent, i, num_joints - 1);

    return true;
}

fn blendAfPose(animator: *Animator, blend_frame: []JointQuat) bool {
    if (animator.af_pose_joints.items.len == 0) return false;

    blendJoints(
        blend_frame,
        animator.af_pose_joint_frame.items,
        animator.af_pose_blend_weight,
        animator.af_pose_joints.items,
    );

    return true;
}

fn transformJoints(
    joint_mats: []JointMat,
    parents: []const c_int,
    first: usize,
    last: usize,
) void {
    var i = first;
    while (i <= last) : (i += 1) {
        std.debug.assert(parents[i] < i);
        joint_mats[i].multiplyJoint(joint_mats[@intCast(parents[i])]);
    }
}

fn convertJointQuatsToJointMats(
    joint_mats: []JointMat,
    joint_quats: []const JointQuat,
) void {
    for (joint_mats, joint_quats) |*mat, *quat| {
        mat.setRotation(quat.q.toMat3());
        mat.setTranslation(quat.t);
    }
}

fn blendJoints(
    joints: []JointQuat,
    blend_joints: []const JointQuat,
    lerp: f32,
    indexes: []const usize,
) void {
    for (indexes) |i| {
        joints[i].q.slerp(
            joints[i].q,
            blend_joints[i].q,
            lerp,
        );
        joints[i].t.lerp(
            joints[i].t,
            blend_joints[i].t,
            lerp,
        );
        joints[i].w = 0;
    }
}
