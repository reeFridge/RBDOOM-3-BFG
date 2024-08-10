const CVec3 = @import("../math/vector.zig").CVec3;
const Plane = @import("../math/plane.zig").Plane;

const CVec5 = extern struct {
    x: f32,
    y: f32,
    z: f32,
    s: f32,
    t: f32,

    pub fn toVec3(vec: CVec5) CVec3 {
        return .{ .x = vec.x, .y = vec.y, .z = vec.z };
    }
};

pub const CWinding = extern struct {
    vptr: *anyopaque,
    numPoints: c_int,
    p: [*]CVec5,
    allocedSize: c_int,

    pub fn getVec3Point(w: CWinding, index: usize) CVec3 {
        return w.p[index].toVec3();
    }
};

const MAX_POINTS_ON_WINDING: usize = 64;

pub const CFixedWinding = extern struct {
    extern fn c_fixedWinding_create() callconv(.C) CFixedWinding;
    extern fn c_fixedWinding_clipInPlace(*CFixedWinding, *const Plane, f32, bool) callconv(.C) bool;

    vptr: *anyopaque,
    numPoints: c_int,
    p: [*]CVec5,
    allocedSize: c_int,
    data: [MAX_POINTS_ON_WINDING]CVec5,

    fn create() CFixedWinding {
        return c_fixedWinding_create();
    }

    pub fn fromWinding(winding: CWinding) CFixedWinding {
        var fixed_winding = create();
        for (winding.p[0..@intCast(winding.numPoints)], 0..) |point, i| {
            fixed_winding.p[i] = point;
        }
        fixed_winding.numPoints = winding.numPoints;

        return fixed_winding;
    }

    pub fn clipInPlace(winding: *CFixedWinding, plane: Plane, epsilon: f32, keep_on: bool) bool {
        return c_fixedWinding_clipInPlace(winding, &plane, epsilon, keep_on);
    }
};
