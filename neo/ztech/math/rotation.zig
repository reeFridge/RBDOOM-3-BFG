const Vec3 = @import("vector.zig").Vec3;
const Mat3 = @import("matrix.zig").Mat3;
const std = @import("std");

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

pub fn rotateVec3(self: *Rotation, v: *const Vec3(f32)) Vec3(f32) {
    if (!self.axis_valid) {
        _ = self.toMat3();
    }

    const Vec3f = Vec3(f32);

    return Vec3f.add(&self.origin, &self.axis.multiplyVec3(&Vec3f.subtract(v, &self.origin)));
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

    const a: f32 = self.angle * ((std.math.pi / 180.0) * 0.5);
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

    self.axis.rows[0].x = 1.0 - (yy + zz);
    self.axis.rows[0].y = xy - wz;
    self.axis.rows[0].z = xz + wy;

    self.axis.rows[1].x = xy + wz;
    self.axis.rows[1].y = 1.0 - (xx + zz);
    self.axis.rows[1].z = yz - wx;

    self.axis.rows[2].x = xz - wy;
    self.axis.rows[2].y = yz + wx;
    self.axis.rows[2].z = 1.0 - (xx + yy);

    self.axis_valid = true;

    return &self.axis;
}