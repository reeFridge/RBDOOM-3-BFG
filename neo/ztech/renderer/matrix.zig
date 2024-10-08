const std = @import("std");
const CVec3 = @import("../math/vector.zig").CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const Plane = @import("../math/plane.zig").Plane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Bounds = @import("../bounding_volume/bounds.zig");

pub const identity: RenderMatrix = .{
    .m = .{
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    },
};

// This is a row-major matrix and transforms are applied with left-multiplication.
pub const RenderMatrix = extern struct {
    extern fn c_renderMatrix_projectedBounds(*CBounds, *const RenderMatrix, *const CBounds, bool) void;
    extern fn c_renderMatrix_projectedNearClippedBounds(*CBounds, *const RenderMatrix, *const CBounds, bool) void;
    extern fn c_renderMatrix_projectedFullyClippedBounds(*CBounds, *const RenderMatrix, *const CBounds, bool) void;
    extern fn c_renderMatrix_getFrustumCorners(*FrustumCorners, *const RenderMatrix, *const CBounds) void;
    extern fn c_renderMatrix_cullFrustumCornersToPlane(*const FrustumCorners, *const Plane) c_int;
    extern fn c_renderMatrix_cullPointToMVP(*const RenderMatrix, *const CVec3, bool) bool;
    extern fn c_renderMatrix_cullBoundsToMVP(*const RenderMatrix, *const CBounds, bool) bool;
    extern fn c_renderMatrix_getFrustumPlanes([*]Plane, *const RenderMatrix, bool, bool) void;

    m: [16]f32,

    pub fn r(matrix: *RenderMatrix, row: usize) []f32 {
        return matrix.m[row * 4 .. (row * 4) + 4];
    }

    pub fn applyModelDepthHack(src: *RenderMatrix, value: f32) void {
        // offset projected z
        src.m[2 * 4 + 3] -= value;
    }

    pub fn applyDepthHack(src: *RenderMatrix) void {
        // scale projected z by 25%
        src.m[2 * 4 + 0] *= 0.25;
        src.m[2 * 4 + 1] *= 0.25;
        src.m[2 * 4 + 2] *= 0.25;
        src.m[2 * 4 + 3] *= 0.25;
    }

    pub fn multiply(a: RenderMatrix, b: RenderMatrix) RenderMatrix {
        var out = std.mem.zeroes(RenderMatrix);

        inline for (0..4) |i| {
            inline for (0..4) |j| {
                out.m[i * 4 + j] =
                    a.m[i * 4 + 0] * b.m[0 * 4 + j] +
                    a.m[i * 4 + 1] * b.m[1 * 4 + j] +
                    a.m[i * 4 + 2] * b.m[2 * 4 + j] +
                    a.m[i * 4 + 3] * b.m[3 * 4 + j];
            }
        }

        return out;
    }

    pub fn transpose(src: RenderMatrix) RenderMatrix {
        var out = std.mem.zeroes(RenderMatrix);

        out.m[0] = src.m[0];
        out.m[1] = src.m[4];
        out.m[2] = src.m[8];
        out.m[3] = src.m[12];
        out.m[4] = src.m[1];
        out.m[5] = src.m[5];
        out.m[6] = src.m[9];
        out.m[7] = src.m[13];
        out.m[8] = src.m[2];
        out.m[9] = src.m[6];
        out.m[10] = src.m[10];
        out.m[11] = src.m[14];
        out.m[12] = src.m[3];
        out.m[13] = src.m[7];
        out.m[14] = src.m[11];
        out.m[15] = src.m[15];

        return out;
    }

    pub fn cullBoundsToMVP(mvp: RenderMatrix, bounds: Bounds, zero_to_one: bool) bool {
        return c_renderMatrix_cullBoundsToMVP(&mvp, &CBounds.fromBounds(bounds), zero_to_one);
    }

    pub fn cullPointToMVP(mvp: RenderMatrix, point: CVec3, zero_to_one: bool) bool {
        return c_renderMatrix_cullPointToMVP(&mvp, &point, zero_to_one);
    }

    pub fn createFromOriginAxis(origin: CVec3, axis: CMat3, out: *RenderMatrix) void {
        out.r(0)[0] = axis.mat[0].x;
        out.r(0)[1] = axis.mat[1].x;
        out.r(0)[2] = axis.mat[2].x;
        out.r(0)[3] = origin.x;

        out.r(1)[0] = axis.mat[0].y;
        out.r(1)[1] = axis.mat[1].y;
        out.r(1)[2] = axis.mat[2].y;
        out.r(1)[3] = origin.y;

        out.r(2)[0] = axis.mat[0].z;
        out.r(2)[1] = axis.mat[1].z;
        out.r(2)[2] = axis.mat[2].z;
        out.r(2)[3] = origin.z;

        out.r(3)[0] = 0.0;
        out.r(3)[1] = 0.0;
        out.r(3)[2] = 0.0;
        out.r(3)[3] = 1.0;
    }

    pub fn offsetScaleForBounds(src_in: RenderMatrix, bounds: CBounds, out: *RenderMatrix) void {
        // RenderMatrix.r needs mutable arg
        // (hope it will be eliminated while compilation)
        var src = src_in;

        const offset = Vec3(f32)
            .add(bounds.b[1].toVec3f(), bounds.b[0].toVec3f())
            .scale(0.5);
        const scale = Vec3(f32)
            .subtract(bounds.b[1].toVec3f(), bounds.b[0].toVec3f())
            .scale(0.5);

        out.r(0)[0] = src.r(0)[0] * scale.x();
        out.r(0)[1] = src.r(0)[1] * scale.y();
        out.r(0)[2] = src.r(0)[2] * scale.z();
        out.r(0)[3] = src.r(0)[3] +
            src.r(0)[0] * offset.x() +
            src.r(0)[1] * offset.y() +
            src.r(0)[2] * offset.z();

        out.r(1)[0] = src.r(1)[0] * scale.x();
        out.r(1)[1] = src.r(1)[1] * scale.y();
        out.r(1)[2] = src.r(1)[2] * scale.z();
        out.r(1)[3] = src.r(1)[3] +
            src.r(1)[0] * offset.x() +
            src.r(1)[1] * offset.y() +
            src.r(1)[2] * offset.z();

        out.r(2)[0] = src.r(2)[0] * scale.x();
        out.r(2)[1] = src.r(2)[1] * scale.y();
        out.r(2)[2] = src.r(2)[2] * scale.z();
        out.r(2)[3] = src.r(2)[3] +
            src.r(2)[0] * offset.x() +
            src.r(2)[1] * offset.y() +
            src.r(2)[2] * offset.z();

        out.r(3)[0] = src.r(3)[0] * scale.x();
        out.r(3)[1] = src.r(3)[1] * scale.y();
        out.r(3)[2] = src.r(3)[2] * scale.z();
        out.r(3)[3] = src.r(3)[3] +
            src.r(3)[0] * offset.x() +
            src.r(3)[1] * offset.y() +
            src.r(3)[2] * offset.z();
    }

    pub fn projectedBounds(
        projected: *CBounds,
        mvp: RenderMatrix,
        bounds: CBounds,
        window_space: bool,
    ) void {
        c_renderMatrix_projectedBounds(projected, &mvp, &bounds, window_space);
    }

    pub fn projectedNearClippedBounds(
        projected: *CBounds,
        mvp: RenderMatrix,
        bounds: CBounds,
        window_space: bool,
    ) void {
        c_renderMatrix_projectedNearClippedBounds(projected, &mvp, &bounds, window_space);
    }

    pub fn projectedFullyClippedBounds(
        projected: *CBounds,
        mvp: RenderMatrix,
        bounds: CBounds,
        window_space: bool,
    ) void {
        c_renderMatrix_projectedFullyClippedBounds(projected, &mvp, &bounds, window_space);
    }

    pub fn getFrustumPlanes(frustum: RenderMatrix, zero_to_one: bool, normalize: bool) [6]Plane {
        var planes = std.mem.zeroes([6]Plane);
        const planes_slice = &planes;
        c_renderMatrix_getFrustumPlanes(planes_slice.ptr, &frustum, zero_to_one, normalize);

        return planes;
    }

    pub fn getFrustumCorners(frustumTransform: RenderMatrix, frustumBounds: CBounds) FrustumCorners {
        var corners = std.mem.zeroes(FrustumCorners);
        c_renderMatrix_getFrustumCorners(&corners, &frustumTransform, &frustumBounds);

        return corners;
    }

    pub fn cullFrustumCornersToPlane(corners: FrustumCorners, plane: Plane) c_int {
        return c_renderMatrix_cullFrustumCornersToPlane(&corners, &plane);
    }
};

pub const FrustumCull = struct {
    pub const FRONT: c_int = 1;
    pub const BACK: c_int = 2;
    pub const CROSS: c_int = 3;
};

pub const FrustumCorners = extern struct {
    pub const NUM: usize = 8;

    x: [NUM]f32,
    y: [NUM]f32,
    z: [NUM]f32,
};

pub fn multiplySlice(a: []const f32, b: []const f32, out: []f32) void {
    inline for (0..4) |i| {
        inline for (0..4) |j| {
            out[i * 4 + j] =
                a[i * 4 + 0] * b[0 * 4 + j] +
                a[i * 4 + 1] * b[1 * 4 + j] +
                a[i * 4 + 2] * b[2 * 4 + j] +
                a[i * 4 + 3] * b[3 * 4 + j];
        }
    }
}
