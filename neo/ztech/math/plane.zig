const Vec3 = @import("vector.zig").Vec3;

pub const Plane = extern struct {
    a: f32 = 0,
    b: f32 = 0,
    c: f32 = 0,
    d: f32 = 0,

    pub fn slice(plane: *Plane) []f32 {
        const as_array_ptr: *[4]f32 = @ptrCast(plane);
        return &as_array_ptr.*;
    }

    pub fn constSlice(plane: *const Plane) []const f32 {
        const as_array_ptr: *const [4]f32 = @ptrCast(plane);
        return &as_array_ptr.*;
    }

    pub fn fromPoints(
        plane: *Plane,
        p1: Vec3(f32),
        p2: Vec3(f32),
        p3: Vec3(f32),
        fix_degenerate: bool,
    ) error{DegenerateNormal}!void {
        plane.setNormal(p1.subtract(p2).cross(p3.subtract(p2)));
        if (plane.normalize(fix_degenerate) == 0) {
            return error.DegenerateNormal;
        }

        plane.d = -plane.normal().dot(p2);
    }

    pub fn fromSlice(in_slice: []f32) Plane {
        return .{
            .a = in_slice[0],
            .b = in_slice[1],
            .c = in_slice[2],
            .d = in_slice[3],
        };
    }

    pub fn fitThroughPoint(p: *Plane, point: Vec3(f32)) void {
        p.d = -(p.normal().dot(point));
    }

    pub fn normalize(p: *Plane, fix_degenerate: bool) f32 {
        var n, const len = normal(p.*).normalizeLen();

        if (fix_degenerate) {
            _ = n.fixDegenerateNormal();
        }

        p.setNormal(n);

        return len;
    }

    pub fn normal(p: Plane) Vec3(f32) {
        return .{ .v = .{ p.a, p.b, p.c } };
    }

    pub fn setNormal(p: *Plane, normal_vec: Vec3(f32)) void {
        p.a = normal_vec.x();
        p.b = normal_vec.y();
        p.c = normal_vec.z();
    }

    pub fn side(p: Plane, v: Vec3(f32)) Side {
        const dist = p.distance(v);
        const epsilon: f32 = 0.1;

        return if (dist > epsilon)
            .front
        else if (dist < -epsilon)
            .back
        else
            .on;
    }

    pub fn distance(p: Plane, v: Vec3(f32)) f32 {
        return p.a * v.x() + p.b * v.y() + p.c * v.z() + p.d;
    }

    pub fn flip(p: Plane) Plane {
        return .{
            .a = -p.a,
            .b = -p.b,
            .c = -p.c,
            .d = -p.d,
        };
    }
};

pub const Side = enum(c_int) {
    front,
    back,
    on,
    cross,
};
