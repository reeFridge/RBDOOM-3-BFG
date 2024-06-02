const Vec3 = @import("vector.zig").Vec3;
const CVec3 = @import("vector.zig").CVec3;
const std = @import("std");

const Mat3f = Mat3(f32);

pub const CMat3 = extern struct {
    mat: [3]CVec3 = [_]CVec3{
        .{ .x = 1.0 },
        .{ .y = 1.0 },
        .{ .z = 1.0 },
    },

    pub fn fromMat3f(mat: *const Mat3f) CMat3 {
        var result: CMat3 = std.mem.zeroes(CMat3);
        inline for (0..result.mat.len) |i| {
            result.mat[i] = CVec3.fromVec3f(&mat.v[i]);
        }

        return result;
    }

    pub fn toMat3f(self: *const CMat3) Mat3f {
        var result: Mat3f = std.mem.zeroes(Mat3f);
        inline for (0..result.v.len) |i| {
            result.v[i] = self.mat[i].toVec3f();
        }

        return result;
    }
};

pub fn Mat3(comptime T: type) type {
    return struct {
        const Self = @This();

        v: [3]Vec3(T),

        pub fn skewSymmetric(src: *const Vec3(T)) Self {
            return .{
                .v = .{
                    .{ .x = 0, .y = -src.z, .z = src.y },
                    .{ .x = src.z, .y = 0, .z = -src.x },
                    .{ .x = -src.y, .y = src.x, .z = 0 },
                },
            };
        }

        pub fn orthoNormalize(self: *const Self) Self {
            var ortho = self.*;
            ortho.v[0] = ortho.v[0].normalize();
            ortho.v[2] = Vec3(T).cross(&ortho.v[0], &ortho.v[1]);
            ortho.v[2] = ortho.v[2].normalize();
            ortho.v[1] = Vec3(T).cross(&ortho.v[2], &ortho.v[0]);
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

        pub fn multiplyVec3(self: *const Self, vec: *const Vec3(T)) Vec3(T) {
            return .{
                .x = self.v[0].x * vec.x + self.v[1].x * vec.y + self.v[2].x * vec.z,
                .y = self.v[0].y * vec.x + self.v[1].y * vec.y + self.v[2].y * vec.z,
                .z = self.v[0].z * vec.x + self.v[1].z * vec.y + self.v[2].z * vec.z,
            };
        }

        pub fn transpose(a: *const Self) Self {
            return .{
                .v = .{
                    .{ .x = a.v[0].x, .y = a.v[1].x, .z = a.v[2].x },
                    .{ .x = a.v[0].y, .y = a.v[1].y, .z = a.v[2].y },
                    .{ .x = a.v[0].z, .y = a.v[1].z, .z = a.v[2].z },
                },
            };
        }

        pub fn multiply(a: *const Self, b: *const Self) Self {
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

        pub fn transposeMultiply(inv: *const Self, b: *const Self, dst: *Self) void {
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
    };
}
