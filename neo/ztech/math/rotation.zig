const CVec3 = @import("vector.zig").CVec3;
const CMat3 = @import("matrix.zig").CMat3;
const Vec3 = @import("vector.zig").Vec3;
const Mat3 = @import("matrix.zig").Mat3;
const std = @import("std");

pub const CRotation = extern struct {
    origin: CVec3,
    vec: CVec3,
    angle: f32,
    axis: CMat3,
    axisValid: bool,

    pub fn fromRotation(rotation: Rotation) CRotation {
        return .{
            .origin = CVec3.fromVec3f(rotation.origin),
            .vec = CVec3.fromVec3f(rotation.vec),
            .angle = rotation.angle,
            .axisValid = rotation.axis_valid,
            .axis = CMat3.fromMat3f(rotation.axis),
        };
    }

    pub fn toRotation(rotation: CRotation) Rotation {
        return .{
            .origin = rotation.origin.toVec3f(),
            .vec = rotation.vec.toVec3f(),
            .angle = rotation.angle,
            .axis_valid = rotation.axisValid,
            .axis = rotation.axis.toMat3f(),
        };
    }
};

const Rotation = @This();

// origin of rotation
origin: Vec3(f32) = .{},
// normalized vector to rotate around
vec: Vec3(f32) = .{},
// angle of rotation in degrees
angle: f32 = 0.0,
// rotation axis
axis: Mat3(f32) = Mat3(f32).identity(),
// true if rotation axis is valid
axis_valid: bool = false,

pub fn create(
    rotation_origin: Vec3(f32),
    rotation_vec: Vec3(f32),
    rotation_angle: f32,
) Rotation {
    return .{
        .origin = rotation_origin,
        .vec = rotation_vec,
        .angle = rotation_angle,
    };
}

pub fn rotateVec3(self: *Rotation, v: Vec3(f32)) Vec3(f32) {
    if (!self.axis_valid) {
        _ = self.toMat3();
    }

    const Vec3f = Vec3(f32);

    return self.origin.add(self.axis.multiplyVec3(Vec3f.subtract(v, self.origin)));
}

pub fn scale(self: *Rotation, s: f32) void {
    self.angle *= s;
    self.axis_valid = false;
}

pub fn normalize180(self: *Rotation) void {
    self.angle -= @floor(self.angle / 360.0) * 360.0;
    if (self.angle > 180.0) {
        self.angle -= 360.0;
    } else if (self.angle < -180.0) {
        self.angle += 360.0;
    }
}

pub fn toMat3(self: *Rotation) *const Mat3(f32) {
    if (self.axis_valid) return &self.axis;

    const a: f32 = self.angle * std.math.degreesToRadians(0.5);
    const s: f32 = std.math.sin(a);
    const c: f32 = std.math.cos(a);

    const x = self.vec.x * s;
    const y = self.vec.y * s;
    const z = self.vec.z * s;

    const x2 = x + x;
    const y2 = y + y;
    const z2 = z + z;

    const xx = x * x2;
    const xy = x * y2;
    const xz = x * z2;

    const yy = y * y2;
    const yz = y * z2;
    const zz = z * z2;

    const wx = c * x2;
    const wy = c * y2;
    const wz = c * z2;

    self.axis.v[0].x = 1.0 - (yy + zz);
    self.axis.v[0].y = xy - wz;
    self.axis.v[0].z = xz + wy;

    self.axis.v[1].x = xy + wz;
    self.axis.v[1].y = 1.0 - (xx + zz);
    self.axis.v[1].z = yz - wx;

    self.axis.v[2].x = xz - wy;
    self.axis.v[2].y = yz + wx;
    self.axis.v[2].z = 1.0 - (xx + yy);

    self.axis_valid = true;

    return &self.axis;
}
