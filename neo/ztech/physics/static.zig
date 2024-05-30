const std = @import("std");
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const Rotation = @import("../math/rotation.zig");
const render_entity = @import("../render_entity.zig");
const CMat3 = render_entity.CMat3;
const CVec3 = render_entity.CVec3;
const CBounds = render_entity.CBounds;

extern fn c_linkClipModel(*anyopaque, CVec3, CMat3) callconv(.C) void;
extern fn c_deinitClipModel(*anyopaque) callconv(.C) void;
extern fn c_checkClipModelPath([*c]const u8) callconv(.C) bool;
extern fn c_initClipModel(*anyopaque, [*c]const u8) callconv(.C) void;

pub const ClipModel = extern struct {
    external: bool = true,
    enabled: bool = true,
    entity: ?*anyopaque = null,
    id: c_int = 0,
    owner: ?*anyopaque = null,
    origin: CVec3 = .{},
    axis: CMat3 = .{},
    bounds: CBounds = .{},
    absBounds: CBounds = .{},
    material: ?*anyopaque = null,
    contents: c_int = 256, // CONTENTS_BODY = BIT(8)
    collisionModelHandle: c_int = 0,
    renderModelHandle: c_int = -1,
    traceModelIndex: c_int = -1,
    clipLinks: ?*anyopaque = null,
    touchCount: c_int = -1,

    pub fn fromModel(model_path: []const u8) ?ClipModel {
        if (!c_checkClipModelPath(model_path.ptr)) return null;

        var clip_model = ClipModel{};
        c_initClipModel(&clip_model, model_path.ptr);

        return clip_model;
    }
};

const PhysicsStatic = @This();

pub const State = struct {
    origin: Vec3(f32) = .{},
    axis: Mat3(f32) = Mat3(f32).identity(),
    local_origin: Vec3(f32) = .{},
    local_axis: Mat3(f32) = Mat3(f32).identity(),
};

current: State = .{},
clip_model: ?ClipModel = null,

pub fn translate(self: *PhysicsStatic, translation: *const Vec3(f32)) void {
    self.current.origin = self.current.origin.add(translation);
    self.current.local_origin = self.current.local_origin.add(translation);

    self.linkClipModel();
}

pub fn rotate(self: *PhysicsStatic, rotation: *Rotation) void {
    self.current.origin = rotation.rotateVec3(&self.current.origin);
    self.current.axis = self.current.axis.multiply(rotation.toMat3());
    self.current.local_origin = self.current.origin;
    self.current.local_axis = self.current.axis;

    self.linkClipModel();
}

pub fn component_init(self: *PhysicsStatic) void {
    self.linkClipModel();
}

pub fn component_deinit(self: *PhysicsStatic) void {
    if (self.clip_model) |*clip_model| {
        c_deinitClipModel(clip_model);
    }
}

inline fn linkClipModel(self: *PhysicsStatic) void {
    if (self.clip_model) |*clip_model| {
        c_linkClipModel(clip_model, CVec3.fromVec3f(&self.current.origin), CMat3.fromMat3f(&self.current.axis));
    }
}
