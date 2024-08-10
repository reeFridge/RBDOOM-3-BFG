const CVec3 = @import("../math/vector.zig").CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;
const PlaneSide = @import("../math/plane.zig").Side;
const Plane = @import("../math/plane.zig").Plane;

pub const CBounds = extern struct {
    b: [2]CVec3 = [_]CVec3{ .{}, .{} },

    pub fn toBounds(c_bounds: CBounds) Bounds {
        return .{
            .min = c_bounds.b[0].toVec3f(),
            .max = c_bounds.b[1].toVec3f(),
        };
    }

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

pub const zero: Bounds = .{
    .min = Vec3(f32).fromScalar(0),
    .max = Vec3(f32).fromScalar(0),
};

pub const zero_one_cube: Bounds = .{
    .min = Vec3(f32).fromScalar(0),
    .max = Vec3(f32).fromScalar(1),
};

pub const unit_cube: Bounds = .{
    .min = Vec3(f32).fromScalar(-1),
    .max = Vec3(f32).fromScalar(1),
};

pub fn eql(a: Bounds, b: Bounds) bool {
    return a.min.eql(b.min) and a.max.eql(b.max);
}

pub fn planeDistance(bounds: Bounds, plane: Plane) f32 {
    const center = bounds.min.add(bounds.max).scale(0.5);
    const normal = Vec3(f32){ .v = .{ plane.a, plane.b, plane.c } };

    const d1 = plane.distance(center);
    const d2 =
        @abs((bounds.max.x() - center.x()) * normal.x()) +
        @abs((bounds.max.y() - center.y()) * normal.y()) +
        @abs((bounds.max.z() - center.z()) * normal.z());

    const epsilon: f32 = 0.0;
    if (d1 - d2 > epsilon) return d1 - d2;
    if (d1 + d2 < -epsilon) return d1 + d2;
    return 0;
}

pub fn planeSide(bounds: Bounds, plane: Plane) PlaneSide {
    const center = bounds.min.add(bounds.max).scale(0.5);
    const normal = Vec3(f32){ .v = .{ plane.a, plane.b, plane.c } };

    const d1 = plane.distance(center);
    const d2 =
        @abs((bounds.max.x() - center.x()) * normal.x()) +
        @abs((bounds.max.y() - center.y()) * normal.y()) +
        @abs((bounds.max.z() - center.z()) * normal.z());

    const epsilon: f32 = 0.1;
    if (d1 - d2 > epsilon) return .front;
    if (d1 + d2 < -epsilon) return .back;
    return .cross;
}

pub fn fromVec3(vec: Vec3(f32)) Bounds {
    return .{
        .min = vec,
        .max = vec,
    };
}

// returns true if bounds are inside out
pub fn isCleared(bounds: Bounds) bool {
    return bounds.min.x() > bounds.max.x();
}
