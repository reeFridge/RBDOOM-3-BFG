const Vec3 = @import("vector.zig").Vec3;

pub const Plane = extern struct {
    a: f32,
    b: f32,
    c: f32,
    d: f32,

    pub fn fromSlice(slice: []f32) Plane {
        return .{
            .a = slice[0],
            .b = slice[1],
            .c = slice[2],
            .d = slice[3],
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
