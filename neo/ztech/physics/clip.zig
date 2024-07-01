const TraceResult = @import("collision_model.zig").TraceResult;
const Vec3 = @import("../math/vector.zig").Vec3;
const CVec6 = @import("../math/vector.zig").CVec6;
const Vec6 = @import("../math/vector.zig").Vec6;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const Rotation = @import("../math/rotation.zig");
const CRotation = Rotation.CRotation;
const ClipModel = @import("clip_model.zig").ClipModel;
const ContactInfo = @import("collision_model.zig").ContactInfo;

extern fn c_clipMotion(
    results: *TraceResult,
    start: *const CVec3,
    end: *const CVec3,
    rotation: *const CRotation,
    mdl: *const ClipModel,
    trmAxis: *const CMat3,
    contentMask: c_int,
    passEntity: ?*anyopaque,
) callconv(.C) bool;

pub fn motion(
    result: *TraceResult,
    start_position: Vec3(f32),
    end_position: Vec3(f32),
    rotation: Rotation,
    clip_model: *const ClipModel,
    trace_model_axis: Mat3(f32),
    content_mask: i32,
) bool {
    return c_clipMotion(
        result,
        &CVec3.fromVec3f(start_position),
        &CVec3.fromVec3f(end_position),
        &CRotation.fromRotation(rotation),
        clip_model,
        &CMat3.fromMat3f(trace_model_axis),
        content_mask,
        null,
    );
}

extern fn c_clipContacts(
    [*]ContactInfo,
    c_int,
    *const CVec3,
    *const CVec6,
    f32,
    *const ClipModel,
    *const CMat3,
    c_int,
    ?*anyopaque,
) callconv(.C) usize;

pub fn contacts(
    out: [*]ContactInfo,
    max_contacts: usize,
    start: Vec3(f32),
    dir: Vec6(f32),
    depth: f32,
    clip_model: *const ClipModel,
    trace_model_axis: Mat3(f32),
    content_mask: i32,
) usize {
    return c_clipContacts(
        out,
        @intCast(max_contacts),
        &CVec3.fromVec3f(start),
        &CVec6.fromVec6f(dir),
        depth,
        clip_model,
        &CMat3.fromMat3f(trace_model_axis),
        content_mask,
        null,
    );
}
