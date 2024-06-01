const std = @import("std");
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const Rotation = @import("../math/rotation.zig");
const ClipModel = @import("clip_model.zig").ClipModel;

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
        clip_model.deinit();
    }
}

inline fn linkClipModel(self: *PhysicsStatic) void {
    if (self.clip_model) |*clip_model| {
        clip_model.linkWithNewTransform(
            0,
            &self.current.origin,
            &self.current.axis,
        );
    }
}
