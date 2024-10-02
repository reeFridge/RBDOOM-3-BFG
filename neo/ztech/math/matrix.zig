const Vec3 = @import("vector.zig").Vec3;
const CVec3 = @import("vector.zig").CVec3;
const Rotation = @import("rotation.zig");
const math = @import("math.zig");
const std = @import("std");

const Mat3f = Mat3(f32);

pub const CMat3 = extern struct {
    mat: [3]CVec3 = [_]CVec3{
        .{ .x = 1 },
        .{ .y = 1 },
        .{ .z = 1 },
    },

    pub fn fromMat3f(mat: Mat3f) CMat3 {
        var result: CMat3 = std.mem.zeroes(CMat3);
        inline for (0..result.mat.len) |i| {
            result.mat[i] = CVec3.fromVec3f(mat.v[i]);
        }

        return result;
    }

    pub fn toMat3f(self: CMat3) Mat3f {
        var result: Mat3f = std.mem.zeroes(Mat3f);
        inline for (0..result.v.len) |i| {
            result.v[i] = self.mat[i].toVec3f();
        }

        return result;
    }
};

extern fn c_mat3Inverse(*const CMat3) callconv(.C) CMat3;

pub fn Mat3(comptime T: type) type {
    return struct {
        const Self = @This();

        v: [3]Vec3(T),

        pub fn eql(a: Self, b: Self) bool {
            return for (a.v, b.v) |av, bv| {
                if (!av.eql(bv)) break false;
            } else true;
        }

        pub fn inverse(self: *Self) Self {
            return c_mat3Inverse(&CMat3.fromMat3f(self.*)).toMat3f();
        }

        pub fn skewSymmetric(src: Vec3(T)) Self {
            return .{
                .v = .{
                    .{ .v = .{ 0, -src.z(), src.y() } },
                    .{ .v = .{ src.z(), 0, -src.x() } },
                    .{ .v = .{ -src.y(), src.x(), 0 } },
                },
            };
        }

        pub fn orthoNormalize(self: Self) Self {
            var ortho = self;
            ortho.v[0] = ortho.v[0].normalize();
            ortho.v[2] = Vec3(T).cross(ortho.v[0], ortho.v[1]);
            ortho.v[2] = ortho.v[2].normalize();
            ortho.v[1] = Vec3(T).cross(ortho.v[2], ortho.v[0]);
            ortho.v[1] = ortho.v[1].normalize();

            return ortho;
        }

        pub fn identity() Self {
            return .{
                .v = .{
                    .{ .v = .{ 1, 0, 0 } },
                    .{ .v = .{ 0, 1, 0 } },
                    .{ .v = .{ 0, 0, 1 } },
                },
            };
        }

        pub fn multiplyScalar(a: Self, s: T) Self {
            return .{
                .v = .{
                    a.v[0].scale(s),
                    a.v[1].scale(s),
                    a.v[2].scale(s),
                },
            };
        }

        pub fn multiplyVec3(self: Self, vec: Vec3(T)) Vec3(T) {
            return .{
                .v = self.v[0].v * vec.xv() +
                    self.v[1].v * vec.yv() +
                    self.v[2].v * vec.zv(),
            };
        }

        pub fn transpose(a: Self) Self {
            return .{
                .v = .{
                    .{ .v = .{ a.v[0].x(), a.v[1].x(), a.v[2].x() } },
                    .{ .v = .{ a.v[0].y(), a.v[1].y(), a.v[2].y() } },
                    .{ .v = .{ a.v[0].z(), a.v[1].z(), a.v[2].z() } },
                },
            };
        }

        pub fn multiply(a: Self, b: Self) Self {
            var result = Self.identity();
            for (0..result.v.len) |row| {
                const sum_x =
                    a.v[row].x() * b.v[0].x() +
                    a.v[row].y() * b.v[1].x() +
                    a.v[row].z() * b.v[2].x();

                result.v[row].v[0] = sum_x;

                const sum_y =
                    a.v[row].x() * b.v[0].y() +
                    a.v[row].y() * b.v[1].y() +
                    a.v[row].z() * b.v[2].y();

                result.v[row].v[1] = sum_y;

                const sum_z =
                    a.v[row].x() * b.v[0].z() +
                    a.v[row].y() * b.v[1].z() +
                    a.v[row].z() * b.v[2].z();

                result.v[row].v[2] = sum_z;
            }

            return result;
        }

        pub fn transposeMultiply(inv: Self, b: Self, dst: *Self) void {
            dst.v[0] = .{ .v = b.v[0].v * inv.v[0].xv() + b.v[1].v * inv.v[1].xv() + b.v[2].v * inv.v[2].xv() };
            dst.v[1] = .{ .v = b.v[0].v * inv.v[0].yv() + b.v[1].v * inv.v[1].yv() + b.v[2].v * inv.v[2].yv() };
            dst.v[2] = .{ .v = b.v[0].v * inv.v[0].zv() + b.v[1].v * inv.v[1].zv() + b.v[2].v * inv.v[2].zv() };
        }

        const next = [3]usize{ 1, 2, 0 };
        pub fn toRotation(self: Self) Rotation {
            var rotation: Rotation = .{};

            const trace = self.v[0].x() + self.v[1].y() + self.v[2].z();
            if (trace > 0.0) {
                const t = trace + 1.0;
                const s = math.invSqrt(t) * 0.5;
                rotation.angle = s * t;
                rotation.vec.v[0] = (self.v[2].y() - self.v[1].z()) * s;
                rotation.vec.v[1] = (self.v[0].z() - self.v[2].x()) * s;
                rotation.vec.v[2] = (self.v[1].x() - self.v[0].y()) * s;
            } else {
                var i: usize = 0;
                if (self.v[1].y() > self.v[0].x()) {
                    i = 1;
                }
                if (self.v[2].z() > self.v[i].v[i]) {
                    i = 2;
                }

                const j: usize = next[i];
                const k: usize = next[j];

                const t = (self.v[i].v[i] - (self.v[j].v[j] + self.v[k].v[k])) + 1.0;
                const s = math.invSqrt(t) * 0.5;
                rotation.angle = (self.v[k].v[j] - self.v[j].v[k]) * s;
                rotation.vec.v[i] = s * t;
                rotation.vec.v[j] = (self.v[j].v[i] + self.v[i].v[j]) * s;
                rotation.vec.v[k] = (self.v[k].v[i] + self.v[i].v[k]) * s;
            }

            rotation.angle = math.acos(rotation.angle);
            const length_sqr = rotation.vec.lengthSqr();
            if ((@abs(rotation.angle) < 1e-10) or (length_sqr < 1e-10)) {
                rotation.vec = .{ .v = .{ 0, 0, 1 } };
                rotation.angle = 0.0;
            } else {
                rotation.vec = rotation.vec.scale(math.invSqrt(length_sqr));
                rotation.angle *= std.math.radiansToDegrees(2.0);
            }

            rotation.origin = .{};
            rotation.axis = self;
            rotation.axis_valid = true;

            return rotation;
        }
    };
}
