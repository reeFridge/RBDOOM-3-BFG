const Vec3 = @import("vector.zig").Vec3;
const std = @import("std");

pub fn Mat3(comptime T: type) type {
    return struct {
        const Self = @This();

        rows: [3]Vec3(T),

        pub fn skewSymmetric(src: *const Vec3(T)) Self {
            return .{
                .rows = .{
                    .{ .x = 0, .y = -src.z, .z = src.y },
                    .{ .x = src.z, .y = 0, .z = -src.x },
                    .{ .x = -src.y, .y = src.x, .z = 0 },
                },
            };
        }

        pub fn orthoNormalize(self: *const Self) Self {
            var ortho = self.*;
            ortho.rows[0] = ortho.rows[0].normalize();
            ortho.rows[2] = Vec3(T).cross(&ortho.rows[0], &ortho.rows[1]);
            ortho.rows[2] = ortho.rows[2].normalize();
            ortho.rows[1] = Vec3(T).cross(&ortho.rows[2], &ortho.rows[0]);
            ortho.rows[1] = ortho.rows[1].normalize();

            return ortho;
        }

        pub fn identity() Self {
            return .{
                .rows = .{
                    .{ .x = 1, .y = 0, .z = 0 },
                    .{ .x = 0, .y = 1, .z = 0 },
                    .{ .x = 0, .y = 0, .z = 1 },
                },
            };
        }

        pub fn multiplyVec3(self: *const Self, vec: *const Vec3(T)) Vec3(T) {
            return .{
                .x = self.rows[0].x * vec.x + self.rows[1].x * vec.y + self.rows[2].x * vec.z,
                .y = self.rows[0].y * vec.x + self.rows[1].y * vec.y + self.rows[2].y * vec.z,
                .z = self.rows[0].z * vec.x + self.rows[1].z * vec.y + self.rows[2].z * vec.z,
            };
        }

        pub fn transpose(a: *const Self) Self {
            return .{
                .rows = .{
                    .{ .x = a.rows[0].x, .y = a.rows[1].x, .z = a.rows[2].x },
                    .{ .x = a.rows[0].y, .y = a.rows[1].y, .z = a.rows[2].y },
                    .{ .x = a.rows[0].z, .y = a.rows[1].z, .z = a.rows[2].z },
                },
            };
        }

        pub fn multiply(a: *const Self, b: *const Self) Self {
            var result = Self.identity();
            for (0..result.rows.len) |row| {
                const sum_x = a.rows[row].x * b.rows[0].x +
                    a.rows[row].y * b.rows[1].x +
                    a.rows[row].z * b.rows[2].x;

                result.rows[row].x = sum_x;

                const sum_y = a.rows[row].x * b.rows[0].y +
                    a.rows[row].y * b.rows[1].y +
                    a.rows[row].z * b.rows[2].y;

                result.rows[row].y = sum_y;

                const sum_z = a.rows[row].x * b.rows[0].z +
                    a.rows[row].y * b.rows[1].z +
                    a.rows[row].z * b.rows[2].z;

                result.rows[row].z = sum_z;
            }

            return result;
        }
    };
}
