const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const material = @import("material.zig");
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;

pub const RenderLight = extern struct {
    axis: CMat3,
    origin: CVec3,
    suppressLightInViewID: c_int,
    allowLightInViewID: c_int,
    forceShadows: bool,
    noShadows: bool,
    noSpecular: bool,
    pointLight: bool,
    parallel: bool,
    lightRadius: CVec3,
    lightCenter: CVec3,
    target: CVec3,
    right: CVec3,
    up: CVec3,
    start: CVec3,
    end: CVec3,
    lightId: c_int,
    shader: ?*anyopaque,
    shaderParms: [material.MAX_GLOBAL_SHADER_PARMS]f32,
    referenceSound: ?*anyopaque,

    extern fn c_parseSpawnArgsToRenderLight(*anyopaque, *RenderLight) callconv(.C) void;
    pub fn initFromSpawnArgs(self: *RenderLight, dict: *anyopaque) void {
        c_parseSpawnArgsToRenderLight(dict, self);
    }
};

const RenderWorld = @import("render_world.zig");
const CPlane = @import("../math/plane.zig").CPlane;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;
const DoublePortal = @import("render_world.zig").DoublePortal;

pub const RenderLightLocal = extern struct {
    // specification
    parms: RenderLight,
    // the light has changed its position since it was
    // first added, so the prelight model is not valid
    lightHasMoved: bool,
    world: *anyopaque, // RenderWorld
    // in world lightDefs
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
    // old style light projection where Z and W are flipped and projected lights lightProject[3] is divided by ( zNear + zFar )
    lightProject: [4]CPlane,
    // global xyz1 to projected light strq
    baseLightProject: RenderMatrix,
    // transforms the zero-to-one cube to exactly cover the light in world space
    inverseBaseLightProject: RenderMatrix,
    // guaranteed to be valid, even if parms.shader isn't
    lightShader: *const anyopaque, // idMaterial
    falloffImage: ?*anyopaque, // idImage
    // accounting for lightCenter and parallel
    globalLightOrigin: CVec3,
    globalLightBounds: CBounds,
    // if == tr.viewCount, the light is on the viewDef->viewLights list
    viewCount: c_int,
    viewLight: ?*anyopaque, // viewLight_t
    // each area the light is present in will have a lightRef
    references: ?*AreaReference,
    // doubly linked list
    firstInteraction: ?*Interaction,
    lastInteraction: ?*Interaction,
    foggedPortals: ?*DoublePortal,
};
