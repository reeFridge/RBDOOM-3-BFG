const std = @import("std");

pub fn Vec3(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T = std.mem.zeroes(T),
        y: T = std.mem.zeroes(T),
        z: T = std.mem.zeroes(T),

        pub fn add(a: *const Self, b: *const Self) Self {
            return .{
                .x = a.x + b.x,
                .y = a.y + b.y,
                .z = a.z + b.z,
            };
        }

        pub fn subtract(a: *const Self, b: *const Self) Self {
            return .{
                .x = a.x - b.x,
                .y = a.y - b.y,
                .z = a.z - b.z,
            };
        }
    };
}
