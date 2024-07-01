const Vec3 = @import("vector.zig").Vec3;
const CVec3 = @import("vector.zig").CVec3;
const Rotation = @import("rotation.zig");
const math = @import("math.zig");
const std = @import("std");

const Mat3f = Mat3(f32);

pub const CMat3 = extern struct {
    mat: [3]CVec3 = [_]CVec3{
        .{ .x = 1.0 },
        .{ .y = 1.0 },
        .{ .z = 1.0 },
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

        pub fn inverse(self: *Self) Self {
            return c_mat3Inverse(&CMat3.fromMat3f(self.*)).toMat3f();
        }

        pub fn skewSymmetric(src: Vec3(T)) Self {
            return .{
                .v = .{
                    .{ .x = 0, .y = -src.z, .z = src.y },
                    .{ .x = src.z, .y = 0, .z = -src.x },
                    .{ .x = -src.y, .y = src.x, .z = 0 },
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
                    .{ .x = 1, .y = 0, .z = 0 },
                    .{ .x = 0, .y = 1, .z = 0 },
                    .{ .x = 0, .y = 0, .z = 1 },
                },
            };
        }

        pub fn multiplyScalar(a: Self, s: T) Self {
            return .{
                .v = .{
                    .{ .x = a.v[0].x * s, .y = a.v[1].x * s, .z = a.v[2].x * s },
                    .{ .x = a.v[0].y * s, .y = a.v[1].y * s, .z = a.v[2].y * s },
                    .{ .x = a.v[0].z * s, .y = a.v[1].z * s, .z = a.v[2].z * s },
                },
            };
        }

        pub fn multiplyVec3(self: Self, vec: Vec3(T)) Vec3(T) {
            return .{
                .x = self.v[0].x * vec.x + self.v[1].x * vec.y + self.v[2].x * vec.z,
                .y = self.v[0].y * vec.x + self.v[1].y * vec.y + self.v[2].y * vec.z,
                .z = self.v[0].z * vec.x + self.v[1].z * vec.y + self.v[2].z * vec.z,
            };
        }

        pub fn transpose(a: Self) Self {
            return .{
                .v = .{
                    .{ .x = a.v[0].x, .y = a.v[1].x, .z = a.v[2].x },
                    .{ .x = a.v[0].y, .y = a.v[1].y, .z = a.v[2].y },
                    .{ .x = a.v[0].z, .y = a.v[1].z, .z = a.v[2].z },
                },
            };
        }

        pub fn multiply(a: Self, b: Self) Self {
            var result = Self.identity();
            for (0..result.v.len) |row| {
                const sum_x = a.v[row].x * b.v[0].x +
                    a.v[row].y * b.v[1].x +
                    a.v[row].z * b.v[2].x;

                result.v[row].x = sum_x;

                const sum_y = a.v[row].x * b.v[0].y +
                    a.v[row].y * b.v[1].y +
                    a.v[row].z * b.v[2].y;

                result.v[row].y = sum_y;

                const sum_z = a.v[row].x * b.v[0].z +
                    a.v[row].y * b.v[1].z +
                    a.v[row].z * b.v[2].z;

                result.v[row].z = sum_z;
            }

            return result;
        }

        pub fn transposeMultiply(inv: Self, b: Self, dst: *Self) void {
            dst.v[0].x = inv.v[0].x * b.v[0].x + inv.v[1].x * b.v[1].x + inv.v[2].x * b.v[2].x;
            dst.v[0].y = inv.v[0].x * b.v[0].y + inv.v[1].x * b.v[1].y + inv.v[2].x * b.v[2].y;
            dst.v[0].z = inv.v[0].x * b.v[0].z + inv.v[1].x * b.v[1].z + inv.v[2].x * b.v[2].z;
            dst.v[1].x = inv.v[0].y * b.v[0].x + inv.v[1].y * b.v[1].x + inv.v[2].y * b.v[2].x;
            dst.v[1].y = inv.v[0].y * b.v[0].y + inv.v[1].y * b.v[1].y + inv.v[2].y * b.v[2].y;
            dst.v[1].z = inv.v[0].y * b.v[0].z + inv.v[1].y * b.v[1].z + inv.v[2].y * b.v[2].z;
            dst.v[2].x = inv.v[0].z * b.v[0].x + inv.v[1].z * b.v[1].x + inv.v[2].z * b.v[2].x;
            dst.v[2].y = inv.v[0].z * b.v[0].y + inv.v[1].z * b.v[1].y + inv.v[2].z * b.v[2].y;
            dst.v[2].z = inv.v[0].z * b.v[0].z + inv.v[1].z * b.v[1].z + inv.v[2].z * b.v[2].z;
        }

        const next = [3]usize{ 1, 2, 0 };
        pub fn toRotation(self: Self) Rotation {
            var rotation: Rotation = .{};

            const trace = self.v[0].x + self.v[1].y + self.v[2].z;
            if (trace > 0.0) {
                const t = trace + 1.0;
                const s = math.invSqrt(t) * 0.5;
                rotation.angle = s * t;
                rotation.vec.x = (self.v[2].y - self.v[1].z) * s;
                rotation.vec.y = (self.v[0].z - self.v[2].x) * s;
                rotation.vec.z = (self.v[1].x - self.v[0].y) * s;
            } else {
                var i: usize = 0;
                if (self.v[1].y > self.v[0].x) {
                    i = 1;
                }
                if (self.v[2].z > self.v[i].slice()[i]) {
                    i = 2;
                }

                const j: usize = next[i];
                const k: usize = next[j];

                const t = (self.v[i].slice()[i] - (self.v[j].slice()[j] + self.v[k].slice()[k])) + 1.0;
                const s = math.invSqrt(t) * 0.5;
                rotation.angle = (self.v[k].slice()[j] - self.v[j].slice()[k]) * s;
                const vec_slice = rotation.vec.sliceMut();
                vec_slice[i].* = s * t;
                vec_slice[j].* = (self.v[j].slice()[i] + self.v[i].slice()[j]) * s;
                vec_slice[k].* = (self.v[k].slice()[i] + self.v[i].slice()[k]) * s;
            }

            rotation.angle = math.acos(rotation.angle);
            const length_sqr = rotation.vec.length_sqr();
            if ((@abs(rotation.angle) < 1e-10) or (length_sqr < 1e-10)) {
                rotation.vec = .{ .x = 0.0, .y = 0.0, .z = 1.0 };
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
