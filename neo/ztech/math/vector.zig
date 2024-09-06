const std = @import("std");
const math = @import("math.zig");

pub const CVec2i = extern struct {
    x: c_int = 0,
    y: c_int = 0,
};

const Vec3f = Vec3(f32);
const Vec6f = Vec6(f32);
const Vec4f = Vec4(f32);
const Vec2f = Vec2(f32);

pub const CVec2 = extern struct {
    x: f32 = 0,
    y: f32 = 0,

    pub fn fromVec2f(vec: Vec3f) CVec2 {
        return .{ .x = vec.v[0], .y = vec.v[1] };
    }

    pub fn toVec2f(cvec: CVec2) Vec2f {
        return .{ .v = .{ cvec.x, cvec.y } };
    }
};

pub const CVec3 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,

    pub fn fromVec3f(vec: Vec3f) CVec3 {
        return .{ .x = vec.v[0], .y = vec.v[1], .z = vec.v[2] };
    }

    pub fn toVec3f(cvec: CVec3) Vec3f {
        return .{ .v = .{ cvec.x, cvec.y, cvec.z } };
    }
};

pub const CVec4 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    w: f32 = 0,

    pub fn fromVec4f(vec: Vec4f) CVec4 {
        return .{ .x = vec.v[0], .y = vec.v[1], .z = vec.v[2], .w = vec.v[3] };
    }

    pub fn toVec4f(cvec: CVec4) Vec4f {
        return .{ .v = .{ cvec.x, cvec.y, cvec.z, cvec.w } };
    }
};

pub const CVec6 = extern struct {
    p: [6]f32 = [_]f32{0} ** 6,

    pub fn toVec6f(cvec: CVec6) Vec6f {
        return .{ .v = cvec.p };
    }

    pub fn fromVec6f(vec: Vec6(f32)) CVec6 {
        return .{ .p = vec.v };
    }
};

pub fn Vec3(comptime T: type) type {
    return struct {
        const Self = @This();
        const V = @Vector(3, T);

        v: V = @splat(std.mem.zeroes(T)),

        pub fn neg(a: Self) T {
            return .{ .v = -a.v };
        }

        pub inline fn x(a: Self) T {
            return a.v[0];
        }

        pub inline fn xv(a: Self) V {
            return @splat(a.x());
        }

        pub inline fn y(a: Self) T {
            return a.v[1];
        }

        pub inline fn yv(a: Self) V {
            return @splat(a.y());
        }

        pub inline fn z(a: Self) T {
            return a.v[2];
        }

        pub inline fn zv(a: Self) V {
            return @splat(a.z());
        }

        pub inline fn eql(a: Self, b: Self) bool {
            return @reduce(.And, a.v == b.v);
        }

        pub fn fromScalar(s: T) Vec3(T) {
            return .{ .v = @splat(s) };
        }

        pub inline fn length_sqr(a: Self) T {
            return @reduce(.Add, (a.v * a.v));
        }

        pub fn normalize(a: Self) Self {
            const sqr_len = a.length_sqr();
            const inv_sqr_len = math.invSqrt(sqr_len);

            return .{
                .v = a.v * @as(V, @splat(inv_sqr_len)),
            };
        }

        pub fn normalizeLen(a: Self) struct { Self, T } {
            const sqr_len = a.length_sqr();
            const inv_sqr_len = math.invSqrt(sqr_len);

            return .{
                .{
                    .v = a.v * @as(V, @splat(inv_sqr_len)),
                },
                sqr_len * inv_sqr_len,
            };
        }

        pub fn cross(a: Self, b: Self) Self {
            const av1 = V{ a.y(), a.z(), a.x() };
            const av2 = V{ a.z(), a.x(), a.y() };
            const bv1 = V{ b.y(), b.z(), b.x() };
            const bv2 = V{ b.z(), b.x(), b.y() };

            return .{
                .v = av1 * bv2 - av2 * bv1,
            };
        }

        pub inline fn dot(a: Self, b: Self) T {
            return @reduce(.Add, (a.v * b.v));
        }

        pub fn scale(a: Self, factor: T) Self {
            return .{
                .v = a.v * @as(V, @splat(factor)),
            };
        }

        pub fn add(a: Self, b: Self) Self {
            return .{
                .v = a.v + b.v,
            };
        }

        pub fn subtract(a: Self, b: Self) Self {
            return .{
                .v = a.v - b.v,
            };
        }

        pub fn fixDegenerateNormal(a: *Self) bool {
            if (a.x() == 0.0) {
                if (a.y() == 0.0) {
                    if (a.z() > 0.0) {
                        if (a.z() != 1.0) {
                            a.v[2] = 1.0;
                            return true;
                        }
                    } else {
                        if (a.z() != -1.0) {
                            a.v[2] = -1.0;
                            return true;
                        }
                    }
                    return false;
                } else if (a.z() == 0.0) {
                    if (a.y() > 0.0) {
                        if (a.y() != 1.0) {
                            a.v[1] = 1.0;
                            return true;
                        }
                    } else {
                        if (a.y() != -1.0) {
                            a.v[1] = -1.0;
                            return true;
                        }
                    }
                    return false;
                }
            } else if (a.y() == 0.0) {
                if (a.z() == 0.0) {
                    if (a.x() > 0.0) {
                        if (a.x() != 1.0) {
                            a.v[0] = 1.0;
                            return true;
                        }
                    } else {
                        if (a.x() != -1.0) {
                            a.v[0] = -1.0;
                            return true;
                        }
                    }
                    return false;
                }
            }
            if (@abs(a.x()) == 1.0) {
                if (a.y() != 0.0 or a.z() != 0.0) {
                    a.v[2] = 0.0;
                    a.v[1] = a.z();
                    return true;
                }
                return false;
            } else if (@abs(a.y()) == 1.0) {
                if (a.x() != 0.0 or a.z() != 0.0) {
                    a.v[2] = 0.0;
                    a.v[0] = a.z();
                    return true;
                }
                return false;
            } else if (@abs(a.z()) == 1.0) {
                if (a.x() != 0.0 or a.y() != 0.0) {
                    a.v[1] = 0.0;
                    a.v[0] = a.y();
                    return true;
                }
                return false;
            }
            return false;
        }
    };
}

pub fn Vec6(comptime T: type) type {
    return struct {
        const Self = @This();
        const V = @Vector(6, T);

        v: V = @splat(std.mem.zeroes(T)),
    };
}

pub fn Vec4(comptime T: type) type {
    return struct {
        const Self = @This();
        const V = @Vector(4, T);

        v: V = @splat(std.mem.zeroes(T)),

        pub inline fn x(a: Self) T {
            return a.v[0];
        }

        pub inline fn y(a: Self) T {
            return a.v[1];
        }

        pub inline fn z(a: Self) T {
            return a.v[2];
        }

        pub inline fn w(a: Self) T {
            return a.v[3];
        }
    };
}

pub fn Vec2(comptime T: type) type {
    return struct {
        const Self = @This();
        const V = @Vector(2, T);

        v: V = @splat(std.mem.zeroes(T)),
    };
}
