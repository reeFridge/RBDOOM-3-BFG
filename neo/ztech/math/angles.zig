const std = @import("std");
const Mat3 = @import("matrix.zig").Mat3;
const math = @import("math.zig");

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

    math.sincos(std.math.degreesToRadians(self.yaw), &sy, &cy);
    math.sincos(std.math.degreesToRadians(self.pitch), &sp, &cp);
    math.sincos(std.math.degreesToRadians(self.roll), &sr, &cr);

    var mat = Mat3(f32).identity();
    mat.v[0] = .{ .v = .{
        cp * cy,
        cp * sy,
        -sp,
    } };
    mat.v[1] = .{ .v = .{
        sr * sp * cy + cr * -sy,
        sr * sp * sy + cr * cy,
        sr * cp,
    } };
    mat.v[2] = .{ .v = .{
        cr * sp * cy + -sr * -sy,
        cr * sp * sy + -sr * cy,
        cr * cp,
    } };

    return mat;
}
