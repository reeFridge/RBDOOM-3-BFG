const std = @import("std");

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
