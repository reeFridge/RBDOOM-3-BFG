const std = @import("std");
const Mat3 = @import("matrix.zig").Mat3;

fn sincos(a: f32, s: *f32, c: *f32) void {
    s.* = std.math.sin(a);
    c.* = std.math.cos(a);
}

const Angles = @This();

pitch: f32 = 0,
yaw: f32 = 0,
roll: f32 = 0,

pub fn toMat3(self: Angles) Mat3(f32) {
    var sr: f32 = 0.0;
    var sp: f32 = 0.0;
    var sy: f32 = 0.0;
    var cr: f32 = 0.0;
    var cp: f32 = 0.0;
    var cy: f32 = 0.0;

    sincos(std.math.degreesToRadians(self.yaw), &sy, &cy);
    sincos(std.math.degreesToRadians(self.pitch), &sp, &cp);
    sincos(std.math.degreesToRadians(self.roll), &sr, &cr);

    var mat = Mat3(f32).identity();
    mat.v[0] = .{
        .x = cp * cy,
        .y = cp * sy,
        .z = -sp,
    };
    mat.v[1] = .{
        .x = sr * sp * cy + cr * -sy,
        .y = sr * sp * sy + cr * cy,
        .z = sr * cp,
    };
    mat.v[2] = .{
        .x = cr * sp * cy + -sr * -sy,
        .y = cr * sp * sy + -sr * cy,
        .z = cr * cp,
    };

    return mat;
}
