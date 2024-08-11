const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;
const RenderEnvprobeLocal = @import("render_envprobe.zig").RenderEnvprobeLocal;
const PortalArea = @import("render_world.zig").PortalArea;
const RenderView = @import("render_world.zig").RenderView;
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const Image = @import("image.zig").Image;
const CVec3 = @import("../math/vector.zig").CVec3;
const CVec2i = @import("../math/vector.zig").CVec2i;
const CVec4 = @import("../math/vector.zig").CVec4;
const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const VertexCacheHandle = @import("vertex_cache.zig").VertexCacheHandle;
const Material = @import("material.zig").Material;
const Plane = @import("../math/plane.zig").Plane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const FrameBuffer = @import("frame_buffer.zig").FrameBuffer;

// areas have references to hold all the lights and entities in them
pub const AreaReference = extern struct {
    // chain in the area
    areaNext: ?*AreaReference = null,
    areaPrev: ?*AreaReference = null,
    // chain on either the entityDef or lightDef
    ownerNext: ?*AreaReference = null,
    // only one of entity / light / envprobe will be non-NULL
    entity: ?*RenderEntityLocal = null,
    // only one of entity / light / envprobe will be non-NULL
    light: ?*RenderLightLocal = null,
    // only one of entity / light / envprobe will be non-NULL
    envprobe: ?*RenderEnvprobeLocal = null,
    // so owners can find all the areas they are in
    area: ?*PortalArea = null,
};

pub const DeclSkin = opaque {};

pub const DrawSurface = extern struct {
    frontEndGeo: ?*const SurfaceTriangles,
    numIndexes: c_int,
    indexCache: VertexCacheHandle,
    ambientCache: VertexCacheHandle,
    jointCache: VertexCacheHandle,
    space: ?*const ViewEntity,
    material: ?*const Material,
    extraGLState: c_ulonglong,
    sort: f32,
    shaderRegisters: [*c]const f32,
    nextOnLight: ?*DrawSurface,
    linkChain: ?**DrawSurface,
    scissorRect: ScreenRect,
};

pub const ViewEntity = extern struct {
    next: ?*ViewEntity,
    entityDef: ?*RenderEntityLocal,
    scissorRect: ScreenRect,
    isGuiSurface: bool,
    skipMotionBlur: bool,
    weaponDepthHack: bool,
    modelDepthHack: f32,
    modelMatrix: [16]f32,
    modelViewMatrix: [16]f32,
    mvp: RenderMatrix,
    unjitteredMVP: RenderMatrix,
    drawSurfs: [*c]DrawSurface,
    useLightGrid: bool,
    lightGridAtlasImage: ?*Image,
    lightGridAtlasSingleProbeSize: c_int,
    lightGridAtlasBorderSize: c_int,
    lightGridOrigin: CVec3,
    lightGridSize: CVec3,
    lightGridBounds: [3]c_int,
};

pub const ShadowOnlyEntity = extern struct {
    next: ?*ShadowOnlyEntity,
    edef: ?*RenderEntityLocal,
};

pub const InteractionState = enum(u8) {
    INTERACTION_UNCHECKED,
    INTERACTION_NO,
    INTERACTION_YES,
};

pub const ViewLight = extern struct {
    next: ?*ViewLight,
    lightDef: ?*RenderLightLocal,
    scissorRect: ScreenRect,
    removeFromList: bool,
    shadowOnlyViewEntities: [*c]ShadowOnlyEntity,
    entityInteractionState: [*c]InteractionState, // [numEntities]
    globalLightOrigin: CVec3,
    lightProject: [4]Plane,
    fogPlane: Plane,
    baseLightProject: RenderMatrix,
    pointLight: bool,
    parallel: bool,
    lightCenter: CVec3,
    shadowLOD: c_int,
    shadowFadeOut: f32,
    shadowV: [6]RenderMatrix,
    shadowP: [6]RenderMatrix,
    imageSize: CVec2i,
    imageAtlasOffset: [6]CVec2i,
    inverseBaseLightProject: RenderMatrix,
    lightShader: ?*Material,
    shaderRegisters: [*c]const f32,
    falloffImage: ?*Image,
    globalShadows: ?*DrawSurface,
    localInteractions: ?*DrawSurface,
    localShadows: ?*DrawSurface,
    globalInteractions: ?*DrawSurface,
    translucentInteractions: ?*DrawSurface,

    pub fn imageAtlasPlaced(view_light: ViewLight) bool {
        return (view_light.imageSize.x != -1) and (view_light.imageSize.y != -1);
    }
};

pub const ViewEnvprobe = extern struct {
    next: ?*ViewEnvprobe,
    envprobeDef: ?*RenderEnvprobeLocal,
    scissorRect: ScreenRect,
    removeFromList: bool,
    globalOrigin: CVec3,
    globalProbeBounds: CBounds,
    inverseBaseProbeProject: RenderMatrix,
    irradianceImage: ?*Image,
    radianceImage: ?*Image,
};

pub const FRUSTUM_PLANES: usize = 6;
pub const MAX_FRUSTUMS: usize = 6;
pub const Frustum = [FRUSTUM_PLANES]Plane;

pub const MAX_CLIP_PLANES: usize = 1;
pub const ViewDef = extern struct {
    renderView: RenderView,
    projectionMatrix: [16]f32,
    projectionRenderMatrix: RenderMatrix,
    unjitteredProjectionMatrix: [16]f32,
    unjitteredProjectionRenderMatrix: RenderMatrix,
    unprojectionToCameraMatrix: [16]f32,
    unprojectionToCameraRenderMatrix: RenderMatrix,
    unprojectionToWorldMatrix: [16]f32,
    unprojectionToWorldRenderMatrix: RenderMatrix,
    worldSpace: ViewEntity,
    renderWorld: ?*anyopaque,
    initialViewAreaOrigin: CVec3,
    isSubview: bool,
    isMirror: bool,
    isXraySubview: bool,
    isEditor: bool,
    is2Dgui: bool,
    isObliqueProjection: bool,
    numClipPlanes: c_int,
    clipPlanes: [MAX_CLIP_PLANES]Plane,
    viewport: ScreenRect,
    scissor: ScreenRect,
    superView: ?*ViewDef,
    subviewSurface: ?*const DrawSurface,
    drawSurfs: ?[*]*DrawSurface,
    numDrawSurfs: c_int,
    maxDrawSurfs: c_int,
    viewLights: ?*ViewLight,
    viewEntitys: ?*ViewEntity,
    frustums: [MAX_FRUSTUMS]Frustum,
    frustumSplitDistances: [MAX_FRUSTUMS]f32,
    frustumMVPs: [MAX_FRUSTUMS]RenderMatrix,
    areaNum: c_int,
    connectedAreas: ?[*]bool,
    viewEnvprobes: ?*ViewEnvprobe,
    globalProbeBounds: CBounds,
    inverseBaseEnvProbeProject: RenderMatrix,
    irradianceImage: ?*Image,
    radianceImages: [3]*Image,
    radianceImageBlends: CVec4,
    targetRender: ?*FrameBuffer,
};

const HalfFloat = c_ushort;

const idStr = extern struct {
    const STR_ALLOC_BASE: usize = 20;

    len: c_int,
    data: [*c]u8,
    allocedAndFlag: c_int,
    baseBuffer: [STR_ALLOC_BASE]u8,
};

pub const CalcEnvprobeParams = extern struct {
    radiance: [6]*u8,
    freeRadiance: c_int,
    samples: c_int,
    outWidth: c_int,
    outHeight: c_int,
    printProgress: bool,
    printWidth: c_int,
    printHeight: c_int,
    filename: idStr,
    outBuffer: *HalfFloat,
    time: c_int,
};

pub const CalcLightGridPointParams = extern struct {
    radiance: [6]*u8,
    gridCoord: [3]c_int,
    outWidth: c_int,
    outHeight: c_int,
    outBuffer: *HalfFloat,
    time: c_int,
};
