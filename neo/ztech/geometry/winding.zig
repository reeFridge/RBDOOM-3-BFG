const std = @import("std");
const CVec3 = @import("../math/vector.zig").CVec3;
const Plane = @import("../math/plane.zig").Plane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Allocator = std.mem.Allocator;

const CVec5 = extern struct {
    x: f32 = 0,
    y: f32 = 0,
    z: f32 = 0,
    s: f32 = 0,
    t: f32 = 0,

    pub fn toVec3(vec: CVec5) CVec3 {
        return .{ .x = vec.x, .y = vec.y, .z = vec.z };
    }
};

pub const Winding = extern struct {
    vptr: *anyopaque = undefined,
    num_points: u32 = 0,
    points: ?[*]CVec5 = null,
    alloced_size: u32 = 0,

    extern fn c_winding_getPlane(*const Winding, *Plane) void;
    extern fn c_winding_getBounds(*const Winding, *CBounds) void;

    pub fn setNumPoints(
        winding: *Winding,
        num: u32,
        allocator: Allocator,
    ) Allocator.Error!void {
        try winding.ensureAlloced(num, allocator);
        winding.num_points = num;
    }

    pub fn getVec3Point(w: Winding, index: usize) CVec3 {
        return w.points.?[index].toVec3();
    }

    pub fn copyFrom(
        winding: *Winding,
        other: *const Winding,
        allocator: Allocator,
    ) Allocator.Error!void {
        try winding.ensureAlloced(other.num_points, false, allocator);

        @memcpy(
            winding.points.?[0..other.num_points],
            other.points.?[0..other.num_points],
        );
        winding.num_points = other.num_points;
    }

    pub fn create(allocator: Allocator) Allocator.Error!*Winding {
        const winding = try allocator.create(Winding);
        winding.* = .{};
        return winding;
    }

    pub fn createAndAllocPoints(
        num_points: u32,
        allocator: Allocator,
    ) Allocator.Error!*Winding {
        const winding = try allocator.create(Winding);
        winding.* = .{};
        errdefer allocator.destroy(winding);
        try winding.ensureAlloced(num_points, false, allocator);

        return winding;
    }

    pub fn ensureAlloced(
        winding: *Winding,
        num: u32,
        keep: bool,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (num > winding.alloced_size) {
            try winding.reallocate(num, keep, allocator);
        }
    }

    pub fn reallocate(
        winding: *Winding,
        num: u32,
        keep: bool,
        allocator: Allocator,
    ) Allocator.Error!void {
        const adjusted_num = (num + 3) & ~@as(u32, 3); // align up to multiple of 4 (-1)
        const points = try allocator.alloc(CVec5, adjusted_num);
        @memset(points, CVec5{});
        if (winding.points) |points_ptr| {
            if (keep) {
                @memcpy(
                    points[0..winding.num_points],
                    points_ptr[0..winding.num_points],
                );
            }

            allocator.free(points_ptr[0..winding.alloced_size]);
        }

        winding.points = points.ptr;
        winding.alloced_size = adjusted_num;
    }

    pub fn destroy(winding: *Winding, allocator: Allocator) void {
        if (winding.points) |points_ptr| {
            allocator.free(points_ptr[0..winding.alloced_size]);
            winding.points = null;
            winding.alloced_size = 0;
        }

        allocator.destroy(winding);
    }

    pub fn reverse(
        winding: *const Winding,
        allocator: Allocator,
    ) Allocator.Error!*Winding {
        var reversed = try createAndAllocPoints(winding.num_points, allocator);
        reversed.num_points = winding.num_points;

        for (0..reversed.num_points) |i| {
            reversed.points.?[reversed.num_points - i - 1] = winding.points.?[i];
        }

        return reversed;
    }

    pub fn getPlane(winding: *const Winding) Plane {
        var plane = std.mem.zeroes(Plane);
        c_winding_getPlane(winding, &plane);
        return plane;
    }

    pub fn getBounds(winding: *const Winding) CBounds {
        var bounds = std.mem.zeroes(CBounds);
        c_winding_getBounds(winding, &bounds);
        return bounds;
    }
};

const max_points_on_winding: usize = 64;

pub const CFixedWinding = extern struct {
    extern fn c_fixedWinding_create() callconv(.C) CFixedWinding;
    extern fn c_fixedWinding_clipInPlace(*CFixedWinding, *const Plane, f32, bool) callconv(.C) bool;

    vptr: *anyopaque,
    num_points: u32,
    points: [*]CVec5,
    alloced_size: u32,
    data: [max_points_on_winding]CVec5,

    fn create() CFixedWinding {
        return c_fixedWinding_create();
    }

    pub fn fromWinding(winding: Winding) CFixedWinding {
        var fixed_winding = create();
        for (winding.points.?[0..winding.num_points], 0..) |point, i| {
            fixed_winding.points[i] = point;
        }
        fixed_winding.num_points = winding.num_points;

        return fixed_winding;
    }

    pub fn clipInPlace(winding: *CFixedWinding, plane: Plane, epsilon: f32, keep_on: bool) bool {
        return c_fixedWinding_clipInPlace(winding, &plane, epsilon, keep_on);
    }
};
