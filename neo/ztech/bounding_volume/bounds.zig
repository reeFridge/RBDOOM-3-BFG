const CVec3 = @import("../math/vector.zig").CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;

pub const CBounds = extern struct {
    b: [2]CVec3 = [_]CVec3{ .{}, .{} },

    pub fn fromBounds(bounds: Bounds) CBounds {
        return .{
            .b = .{
                CVec3.fromVec3f(bounds.min),
                CVec3.fromVec3f(bounds.max),
            },
        };
    }
};

min: Vec3(f32),
max: Vec3(f32),

const Bounds = @This();

pub fn fromVec3(vec: Vec3(f32)) Bounds {
    return .{
        .min = vec,
        .max = vec,
    };
}
