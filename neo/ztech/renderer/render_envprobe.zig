const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CPlane = @import("../math/plane.zig").CPlane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const render_entity = @import("render_entity.zig");

pub const RenderEnvironmentProbe = extern struct {
    origin: CVec3,
    shaderParms: [render_entity.MAX_ENTITY_SHADER_PARMS]f32,

    // if non-zero, the environment probe will not show up in the specific view,
    // which may be used if we want to have slightly different muzzle
    // flash lights for the player and other views
    suppressEnvprobeInViewID: c_int,
    // if non-zero, the environment probe will only show up in the specific view
    // which can allow player gun gui lights and such to not effect everyone
    allowEnvprobeInViewID: c_int,
};

const RenderMatrix = @import("matrix.zig").RenderMatrix;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;

pub const RenderEnvprobeLocal = extern struct {
    // specification
    parms: RenderEnvironmentProbe,
    // the envprobe has changed its position since it was
    // first added, so the preenvprobe model is not valid
    envprobeHasMoved: bool,
    world: *anyopaque, // RenderWorld
    // in world envprobeDefs
    index: c_int,
    // if not -1, we may be able to cull all the light's
    // interactions if !viewDef->connectedAreas[areaNum]
    areaNum: c_int,
    // to determine if it is constantly changing,
    // and should go in the dynamic frame memory, or kept
    // in the cached memory
    lastModifiedFrameNum: c_int,
    // for demo writing
    archived: bool,

    // derived information
    // transforms the zero-to-one cube to exactly cover the light in world space
    inverseBaseLightProject: RenderMatrix,
    globalProbeBounds: CBounds,
    // each area the light is present in will have a envprobeRef
    references: ?*AreaReference,
    // cubemap image used for diffuse IBL by backend
    irradianceImage: ?*anyopaque, // idImage
    // cubemap image used for specular IBL by backend
    radianceImage: ?*anyopaque, // idImage
    // if == tr.viewCount, the envprobe is on the viewDef->viewEnvprobes list
    viewCount: c_int,
    viewEnvprobe: ?*anyopaque, // viewEnvprobe_t
};
