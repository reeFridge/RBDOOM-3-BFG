const Vec3 = @import("vector.zig").Vec3;
const std = @import("std");

pub fn Mat3(comptime T: type) type {
    return struct {
        const Self = @This();

        rows: [3]Vec3(T),

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
