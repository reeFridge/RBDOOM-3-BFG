const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const MAX_GLOBAL_SHADER_PARMS: usize = 12;

pub const RenderView = extern struct {
    viewID: c_int,
    fov_x: f32,
    fov_y: f32,
    vieworg: CVec3,
    vieworg_weapon: CVec3,
    viewaxis: CMat3,
    cramZNear: bool,
    flipProjection: bool,
    forceUpdate: bool,
    time: [2]c_int,
    shaderParms: [MAX_GLOBAL_SHADER_PARMS]f32,
    globalMaterial: ?*const anyopaque,
    viewEyeBuffer: c_int,
    stereoScreenSeparation: f32,
    rdflags: c_int,
};
