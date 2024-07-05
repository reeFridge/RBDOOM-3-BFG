const std = @import("std");

pub fn angleNormalize360(angle: f32) f32 {
    return if ((angle >= 360.0) or (angle < 0.0))
        angle - @floor(angle * (1.0 / 360.0)) * 360.0
    else
        angle;
}

pub fn angleNormalize180(angle_arg: f32) f32 {
    const angle = angleNormalize360(angle_arg);
    return if (angle > 180.0)
        angle - 360.0
    else
        angle;
}

pub fn sincos(a: f32, s: *f32, c: *f32) void {
    s.* = std.math.sin(a);
    c.* = std.math.cos(a);
}

pub inline fn invSqrt(x: f32) f32 {
    return if (x > std.math.floatMin(f32))
        @sqrt(1.0 / x)
    else
        std.math.floatMax(f32);
}

pub inline fn acos(a: f32) f32 {
    if (a <= -1.0) return std.math.pi;
    if (a >= 1.0) return 0.0;

    return std.math.acos(a);
}
