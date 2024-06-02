const std = @import("std");

const Vec3f = Vec3(f32);

pub const CVec3 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn fromVec3f(vec: *const Vec3f) CVec3 {
        var result: CVec3 = .{};
        inline for (std.meta.fields(CVec3)) |info| {
            @field(result, info.name) = @field(vec.*, info.name);
        }

        return result;
    }

    pub fn toVec3f(self: *const CVec3) Vec3f {
        var result: Vec3f = .{};
        inline for (std.meta.fields(Vec3f)) |info| {
            @field(result, info.name) = @field(self.*, info.name);
        }

        return result;
    }
};

pub fn Vec3(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T = std.mem.zeroes(T),
        y: T = std.mem.zeroes(T),
        z: T = std.mem.zeroes(T),

        pub fn normalize(a: *const Self) Self {
            const sqr_len = a.x * a.x + a.y * a.y + a.z * a.z;
            const inv_sqr_len = @sqrt(1.0 / sqr_len);

            return .{
                .x = a.x * inv_sqr_len,
                .y = a.y * inv_sqr_len,
                .z = a.z * inv_sqr_len,
            };
        }

        pub fn cross(a: *const Self, b: *const Self) Self {
            return .{
                .x = a.y * b.z - a.z * b.y,
                .y = a.z * b.x - a.x * b.z,
                .z = a.x * b.y - a.y * b.x,
            };
        }

        pub fn dot(a: *const Self, b: *const Self) T {
            return a.x * b.x + a.y * b.y + a.z * b.z;
        }

        pub fn scale(a: *const Self, factor: T) Self {
            return .{
                .x = a.x * factor,
                .y = a.y * factor,
                .z = a.z * factor,
            };
        }

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
