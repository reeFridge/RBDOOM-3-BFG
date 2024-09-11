const CMat3 = @import("matrix.zig").CMat3;

pub const Quat = extern struct {
    x: f32,
    y: f32,
    z: f32,
    w: f32,

    extern fn c_quat_slerp(*Quat, Quat, Quat, f32) void;

    pub fn toMat3(q: Quat) CMat3 {
        const x2 = q.x + q.x;
        const y2 = q.y + q.y;
        const z2 = q.z + q.z;

        const xx = q.x * x2;
        const xy = q.x * y2;
        const xz = q.x * z2;

        const yy = q.y * y2;
        const yz = q.y * z2;
        const zz = q.z * z2;

        const wx = q.w * x2;
        const wy = q.w * y2;
        const wz = q.w * z2;

        var mat: CMat3 = .{};
        mat.mat[0] = .{
            .x = 1.0 - (yy + zz),
            .y = xy - wz,
            .z = xz + wy,
        };

        mat.mat[1] = .{
            .x = xy + wz,
            .y = 1.0 - (xx + zz),
            .z = yz - wx,
        };

        mat.mat[2] = .{
            .x = xz - wy,
            .y = yz + wx,
            .z = 1.0 - (xx + yy),
        };

        return mat;
    }

    pub fn slerp(
        q: *Quat,
        from: Quat,
        to: Quat,
        t: f32,
    ) void {
        c_quat_slerp(q, from, to, t);
    }
};
