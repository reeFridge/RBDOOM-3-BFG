const std = @import("std");
const math = @import("math.zig");

const Vec3f = Vec3(f32);

pub const CVec3 = extern struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,

    pub fn fromVec3f(vec: Vec3f) CVec3 {
        var result: CVec3 = .{};
        inline for (std.meta.fields(CVec3)) |info| {
            @field(result, info.name) = @field(vec, info.name);
        }

        return result;
    }

    pub fn toVec3f(self: CVec3) Vec3f {
        var result: Vec3f = .{};
        inline for (std.meta.fields(Vec3f)) |info| {
            @field(result, info.name) = @field(self, info.name);
        }

        return result;
    }
};

pub const CVec6 = extern struct {
    p: [6]f32,

    pub fn toVec6f(self: CVec6) Vec6(f32) {
        return .{
            .v = .{
                .{ .x = self.p[0], .y = self.p[1], .z = self.p[2] },
                .{ .x = self.p[3], .y = self.p[4], .z = self.p[5] },
            },
        };
    }

    pub fn fromVec6f(vec: Vec6(f32)) CVec6 {
        return .{
            .p = .{
                vec.v[0].x, vec.v[0].y, vec.v[0].z,
                vec.v[1].x, vec.v[1].y, vec.v[1].z,
            },
        };
    }
};

pub fn Vec3(comptime T: type) type {
    return struct {
        const Self = @This();

        x: T = std.mem.zeroes(T),
        y: T = std.mem.zeroes(T),
        z: T = std.mem.zeroes(T),

        pub fn fromScalar(s: T) Vec3(T) {
            return .{ .x = s, .y = s, .z = s };
        }

        pub fn slice(self: Self) [3]T {
            return [3]T{ self.x, self.y, self.z };
        }

        pub fn sliceMut(self: *Self) [3]*T {
            return [3]*T{ &self.x, &self.y, &self.z };
        }

        pub fn length_sqr(a: Self) T {
            return a.x * a.x + a.y * a.y + a.z * a.z;
        }

        pub fn normalize(a: Self) Self {
            const sqr_len = a.x * a.x + a.y * a.y + a.z * a.z;
            const inv_sqr_len = math.invSqrt(sqr_len);

            return .{
                .x = a.x * inv_sqr_len,
                .y = a.y * inv_sqr_len,
                .z = a.z * inv_sqr_len,
            };
        }

        pub fn normalizeLen(a: Self) struct { Self, T } {
            const sqr_len = a.x * a.x + a.y * a.y + a.z * a.z;
            const inv_sqr_len = math.invSqrt(sqr_len);

            return .{
                .{
                    .x = a.x * inv_sqr_len,
                    .y = a.y * inv_sqr_len,
                    .z = a.z * inv_sqr_len,
                },
                sqr_len * inv_sqr_len,
            };
        }

        pub fn cross(a: Self, b: Self) Self {
            return .{
                .x = a.y * b.z - a.z * b.y,
                .y = a.z * b.x - a.x * b.z,
                .z = a.x * b.y - a.y * b.x,
            };
        }

        pub fn dot(a: Self, b: Self) T {
            return a.x * b.x + a.y * b.y + a.z * b.z;
        }

        pub fn scale(a: Self, factor: T) Self {
            return .{
                .x = a.x * factor,
                .y = a.y * factor,
                .z = a.z * factor,
            };
        }

        pub fn add(a: Self, b: Self) Self {
            return .{
                .x = a.x + b.x,
                .y = a.y + b.y,
                .z = a.z + b.z,
            };
        }

        pub fn subtract(a: Self, b: Self) Self {
            return .{
                .x = a.x - b.x,
                .y = a.y - b.y,
                .z = a.z - b.z,
            };
        }
    };
}

pub fn Vec6(comptime T: type) type {
    return struct {
        const Self = @This();

        v: [2]Vec3(T),
    };
}
