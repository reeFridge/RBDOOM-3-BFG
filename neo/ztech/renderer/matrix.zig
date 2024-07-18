const CVec3 = @import("../math/vector.zig").CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;

// This is a row-major matrix and transforms are applied with left-multiplication.
pub const RenderMatrix = extern struct {
    extern fn c_renderMatrix_projectedBounds(*CBounds, *const RenderMatrix, *const CBounds, bool) callconv(.C) void;

    m: [16]f32,

    pub fn r(matrix: *RenderMatrix, row: usize) []f32 {
        return matrix.m[row * 4 .. (row * 4) + 4];
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

        out.r(0)[0] = src.r(0)[0] * scale.x;
        out.r(0)[1] = src.r(0)[1] * scale.y;
        out.r(0)[2] = src.r(0)[2] * scale.z;
        out.r(0)[3] = src.r(0)[3] +
            src.r(0)[0] * offset.x +
            src.r(0)[1] * offset.y +
            src.r(0)[2] * offset.z;

        out.r(1)[0] = src.r(1)[0] * scale.x;
        out.r(1)[1] = src.r(1)[1] * scale.y;
        out.r(1)[2] = src.r(1)[2] * scale.z;
        out.r(1)[3] = src.r(1)[3] +
            src.r(1)[0] * offset.x +
            src.r(1)[1] * offset.y +
            src.r(1)[2] * offset.z;

        out.r(2)[0] = src.r(2)[0] * scale.x;
        out.r(2)[1] = src.r(2)[1] * scale.y;
        out.r(2)[2] = src.r(2)[2] * scale.z;
        out.r(2)[3] = src.r(2)[3] +
            src.r(2)[0] * offset.x +
            src.r(2)[1] * offset.y +
            src.r(2)[2] * offset.z;

        out.r(3)[0] = src.r(3)[0] * scale.x;
        out.r(3)[1] = src.r(3)[1] * scale.y;
        out.r(3)[2] = src.r(3)[2] * scale.z;
        out.r(3)[3] = src.r(3)[3] +
            src.r(3)[0] * offset.x +
            src.r(3)[1] * offset.y +
            src.r(3)[2] * offset.z;
    }

    pub fn projectedBounds(
        projected: *CBounds,
        mvp: RenderMatrix,
        bounds: CBounds,
        window_space: bool,
    ) void {
        c_renderMatrix_projectedBounds(projected, &mvp, &bounds, window_space);
    }
};
