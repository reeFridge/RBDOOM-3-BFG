const common = @import("common.zig");
const idlib = @import("../idlib.zig");
const nvrhi = @import("nvrhi.zig");
const buffer_object = @import("buffer_object.zig");
const CVec4 = @import("../math/vector.zig").CVec4;
const bit = @import("../math/math.zig").bit;

const BuiltinShader = enum(c_int) {
    BUILTIN_GUI,
    BUILTIN_COLOR,
    BUILTIN_COLOR_SKINNED,
    BUILTIN_VERTEX_COLOR,

    BUILTIN_AMBIENT_LIGHTING_IBL,
    BUILTIN_AMBIENT_LIGHTING_IBL_SKINNED,
    BUILTIN_AMBIENT_LIGHTING_IBL_PBR,
    BUILTIN_AMBIENT_LIGHTING_IBL_PBR_SKINNED,

    BUILTIN_AMBIENT_LIGHTGRID_IBL,
    BUILTIN_AMBIENT_LIGHTGRID_IBL_SKINNED,
    BUILTIN_AMBIENT_LIGHTGRID_IBL_PBR,
    BUILTIN_AMBIENT_LIGHTGRID_IBL_PBR_SKINNED,

    BUILTIN_SMALL_GEOMETRY_BUFFER,
    BUILTIN_SMALL_GEOMETRY_BUFFER_SKINNED,
    BUILTIN_TEXTURED,
    BUILTIN_TEXTURE_VERTEXCOLOR,
    BUILTIN_TEXTURE_VERTEXCOLOR_SRGB,
    BUILTIN_TEXTURE_VERTEXCOLOR_SKINNED,
    BUILTIN_TEXTURE_TEXGEN_VERTEXCOLOR,

    BUILTIN_INTERACTION,
    BUILTIN_INTERACTION_SKINNED,
    BUILTIN_INTERACTION_AMBIENT,
    BUILTIN_INTERACTION_AMBIENT_SKINNED,

    BUILTIN_PBR_INTERACTION,
    BUILTIN_PBR_INTERACTION_SKINNED,
    BUILTIN_PBR_INTERACTION_AMBIENT,
    BUILTIN_PBR_INTERACTION_AMBIENT_SKINNED,

    BUILTIN_INTERACTION_SHADOW_MAPPING_SPOT,
    BUILTIN_INTERACTION_SHADOW_MAPPING_SPOT_SKINNED,
    BUILTIN_INTERACTION_SHADOW_MAPPING_POINT,
    BUILTIN_INTERACTION_SHADOW_MAPPING_POINT_SKINNED,
    BUILTIN_INTERACTION_SHADOW_MAPPING_PARALLEL,
    BUILTIN_INTERACTION_SHADOW_MAPPING_PARALLEL_SKINNED,

    BUILTIN_PBR_INTERACTION_SHADOW_MAPPING_SPOT,
    BUILTIN_PBR_INTERACTION_SHADOW_MAPPING_SPOT_SKINNED,
    BUILTIN_PBR_INTERACTION_SHADOW_MAPPING_POINT,
    BUILTIN_PBR_INTERACTION_SHADOW_MAPPING_POINT_SKINNED,
    BUILTIN_PBR_INTERACTION_SHADOW_MAPPING_PARALLEL,
    BUILTIN_PBR_INTERACTION_SHADOW_MAPPING_PARALLEL_SKINNED,

    BUILTIN_INTERACTION_SHADOW_ATLAS_SPOT,
    BUILTIN_INTERACTION_SHADOW_ATLAS_SPOT_SKINNED,
    BUILTIN_INTERACTION_SHADOW_ATLAS_POINT,
    BUILTIN_INTERACTION_SHADOW_ATLAS_POINT_SKINNED,
    BUILTIN_INTERACTION_SHADOW_ATLAS_PARALLEL,
    BUILTIN_INTERACTION_SHADOW_ATLAS_PARALLEL_SKINNED,

    BUILTIN_PBR_INTERACTION_SHADOW_ATLAS_SPOT,
    BUILTIN_PBR_INTERACTION_SHADOW_ATLAS_SPOT_SKINNED,
    BUILTIN_PBR_INTERACTION_SHADOW_ATLAS_POINT,
    BUILTIN_PBR_INTERACTION_SHADOW_ATLAS_POINT_SKINNED,
    BUILTIN_PBR_INTERACTION_SHADOW_ATLAS_PARALLEL,
    BUILTIN_PBR_INTERACTION_SHADOW_ATLAS_PARALLEL_SKINNED,

    BUILTIN_DEBUG_LIGHTGRID,
    BUILTIN_DEBUG_LIGHTGRID_SKINNED,

    BUILTIN_DEBUG_OCTAHEDRON,
    BUILTIN_DEBUG_OCTAHEDRON_SKINNED,
    BUILTIN_ENVIRONMENT,
    BUILTIN_ENVIRONMENT_SKINNED,
    BUILTIN_BUMPY_ENVIRONMENT,
    BUILTIN_BUMPY_ENVIRONMENT_SKINNED,

    BUILTIN_DEPTH,
    BUILTIN_DEPTH_SKINNED,

    BUILTIN_BLENDLIGHT,
    BUILTIN_BLENDLIGHT_SKINNED,
    BUILTIN_FOG,
    BUILTIN_FOG_SKINNED,
    BUILTIN_SKYBOX,
    BUILTIN_WOBBLESKY,
    BUILTIN_POSTPROCESS,
    BUILTIN_POSTPROCESS_RETRO_2BIT, // CGA, Gameboy, cool for Gamejams
    BUILTIN_POSTPROCESS_RETRO_C64, // Commodore 64
    BUILTIN_POSTPROCESS_RETRO_CPC, // Amstrad 6128
    BUILTIN_POSTPROCESS_RETRO_NES, // NES
    BUILTIN_POSTPROCESS_RETRO_GENESIS, // Sega Genesis / Megadrive
    BUILTIN_POSTPROCESS_RETRO_PSX, // Sony Playstation 1
    BUILTIN_CRT_MATTIAS,
    BUILTIN_CRT_NUPIXIE,
    BUILTIN_CRT_EASYMODE,
    BUILTIN_SCREEN,
    BUILTIN_TONEMAP,
    BUILTIN_BRIGHTPASS,
    BUILTIN_HDR_GLARE_CHROMATIC,
    BUILTIN_HDR_DEBUG,

    BUILTIN_SMAA_EDGE_DETECTION,
    BUILTIN_SMAA_BLENDING_WEIGHT_CALCULATION,
    BUILTIN_SMAA_NEIGHBORHOOD_BLENDING,

    BUILTIN_TAA_MOTION_VECTORS,
    BUILTIN_TAA_RESOLVE,
    BUILTIN_TAA_RESOLVE_MSAA_2X,
    BUILTIN_TAA_RESOLVE_MSAA_4X,
    BUILTIN_TAA_RESOLVE_MSAA_8X,

    BUILTIN_AMBIENT_OCCLUSION,
    BUILTIN_AMBIENT_OCCLUSION_AND_OUTPUT,
    BUILTIN_AMBIENT_OCCLUSION_BLUR,
    BUILTIN_AMBIENT_OCCLUSION_BLUR_AND_OUTPUT,

    BUILTIN_DEEP_GBUFFER_RADIOSITY_SSGI,
    BUILTIN_DEEP_GBUFFER_RADIOSITY_BLUR,
    BUILTIN_DEEP_GBUFFER_RADIOSITY_BLUR_AND_OUTPUT,
    BUILTIN_STEREO_DEGHOST,
    BUILTIN_STEREO_WARP,
    BUILTIN_BINK,
    BUILTIN_BINK_SRGB,
    BUILTIN_BINK_GUI,
    BUILTIN_STEREO_INTERLACE,
    BUILTIN_MOTION_BLUR,

    BUILTIN_DEBUG_SHADOWMAP,

    BUILTIN_BLIT,
    BUILTIN_RECT,
    BUILTIN_TONEMAPPING,
    BUILTIN_TONEMAPPING_TEX_ARRAY,
    BUILTIN_HISTOGRAM_CS,
    BUILTIN_HISTOGRAM_TEX_ARRAY_CS,
    BUILTIN_EXPOSURE_CS,

    MAX_BUILTINS,
};

const RenderParam = enum(c_int) {
    // For backwards compatibility, do not change the order of the first 17 items
    SCREENCORRECTIONFACTOR = 0,
    WINDOWCOORD,
    DIFFUSEMODIFIER,
    SPECULARMODIFIER,

    LOCALLIGHTORIGIN,
    LOCALVIEWORIGIN,

    LIGHTPROJECTION_S,
    LIGHTPROJECTION_T,
    LIGHTPROJECTION_Q,
    LIGHTFALLOFF_S,

    BUMPMATRIX_S,
    BUMPMATRIX_T,

    DIFFUSEMATRIX_S,
    DIFFUSEMATRIX_T,

    SPECULARMATRIX_S,
    SPECULARMATRIX_T,

    VERTEXCOLOR_MODULATE,
    VERTEXCOLOR_ADD,

    COLOR,
    VIEWORIGIN,
    GLOBALEYEPOS,

    MVPMATRIX_X,
    MVPMATRIX_Y,
    MVPMATRIX_Z,
    MVPMATRIX_W,

    MODELMATRIX_X,
    MODELMATRIX_Y,
    MODELMATRIX_Z,
    MODELMATRIX_W,

    PROJMATRIX_X,
    PROJMATRIX_Y,
    PROJMATRIX_Z,
    PROJMATRIX_W,

    MODELVIEWMATRIX_X,
    MODELVIEWMATRIX_Y,
    MODELVIEWMATRIX_Z,
    MODELVIEWMATRIX_W,

    TEXTUREMATRIX_S,
    TEXTUREMATRIX_T,

    TEXGEN_0_S,
    TEXGEN_0_T,
    TEXGEN_0_Q,
    TEXGEN_0_ENABLED,

    TEXGEN_1_S,
    TEXGEN_1_T,
    TEXGEN_1_Q,
    TEXGEN_1_ENABLED,

    WOBBLESKY_X,
    WOBBLESKY_Y,
    WOBBLESKY_Z,

    OVERBRIGHT,
    ENABLE_SKINNING,
    ALPHA_TEST,

    AMBIENT_COLOR,

    GLOBALLIGHTORIGIN,
    JITTERTEXSCALE,
    JITTERTEXOFFSET,

    PSX_DISTORTIONS,

    CASCADEDISTANCES,

    SHADOW_MATRIX_0_X, // rpShadowMatrices[6 * 4]
    SHADOW_MATRIX_0_Y,
    SHADOW_MATRIX_0_Z,
    SHADOW_MATRIX_0_W,

    SHADOW_MATRIX_1_X,
    SHADOW_MATRIX_1_Y,
    SHADOW_MATRIX_1_Z,
    SHADOW_MATRIX_1_W,

    SHADOW_MATRIX_2_X,
    SHADOW_MATRIX_2_Y,
    SHADOW_MATRIX_2_Z,
    SHADOW_MATRIX_2_W,

    SHADOW_MATRIX_3_X,
    SHADOW_MATRIX_3_Y,
    SHADOW_MATRIX_3_Z,
    SHADOW_MATRIX_3_W,

    SHADOW_MATRIX_4_X,
    SHADOW_MATRIX_4_Y,
    SHADOW_MATRIX_4_Z,
    SHADOW_MATRIX_4_W,

    SHADOW_MATRIX_5_X,
    SHADOW_MATRIX_5_Y,
    SHADOW_MATRIX_5_Z,
    SHADOW_MATRIX_5_W,

    SHADOW_ATLAS_OFFSET_0, // rpShadowAtlasOffsets[6]
    SHADOW_ATLAS_OFFSET_1,
    SHADOW_ATLAS_OFFSET_2,
    SHADOW_ATLAS_OFFSET_3,
    SHADOW_ATLAS_OFFSET_4,
    SHADOW_ATLAS_OFFSET_5,

    USER0,
    USER1,
    USER2,
    USER3,
    USER4,
    USER5,
    USER6,
    USER7,

    TOTAL,
};

const RenderProg = extern struct {
    name: idlib.idStr,
    vertexShaderIndex: c_int,
    fragmentShaderIndex: c_int,
    computeShaderIndex: c_int,
    builtin: bool,
    usesJoints: bool,
    vertexLayout: common.VertexLayoutType,
    bindingLayoutType: common.BindingLayoutType,
    inputLayout: nvrhi.InputLayoutHandle,
    bindingLayouts: idlib.idStaticList(
        nvrhi.BindingLayoutHandle,
        nvrhi.c_MaxBindingLayouts,
    ),
};

const ShaderMacro = extern struct {
    name: idlib.idStr,
    definition: idlib.idStr,
};

const Shader = extern struct {
    const StageType = c_int;
    const Stage = struct {
        pub const vertex: StageType = bit(0);
        pub const fragment: StageType = bit(1);
        pub const compute: StageType = bit(2);
        pub const default: StageType = vertex | fragment;
    };

    name: idlib.idStr,
    nameOutSuffix: idlib.idStr,
    shaderFeatures: u32,
    builtin: bool,
    macros: idlib.idList(ShaderMacro),
    handle: nvrhi.ShaderHandle,
    stage: StageType,
};

pub const RenderProgManager = extern struct {
    const VertexAttribDescList = idlib.idList(nvrhi.VertexAttributeDesc);
    const NUM_VERTEX_LAYOUTS: usize = @intCast(@intFromEnum(common.VertexLayoutType.NUM_VERTEX_LAYOUTS));
    const NUM_BINDING_LAYOUTS: usize = @intCast(@intFromEnum(common.BindingLayoutType.NUM_BINDING_LAYOUTS));
    const MAX_BUILTINS: usize = @intCast(@intFromEnum(BuiltinShader.MAX_BUILTINS));
    const MAX_UNIFORMS: usize = @intCast(@intFromEnum(RenderParam.TOTAL));

    vptr: *anyopaque,
    renderParmUbo: buffer_object.UniformBuffer,
    bindingParmUbo: [NUM_BINDING_LAYOUTS]buffer_object.UniformBuffer,
    mappedRenderParms: [NUM_BINDING_LAYOUTS]?*CVec4,
    builtinShaders: [MAX_BUILTINS]c_int,
    currentIndex: c_int,
    renderProgs: idlib.idList(RenderProg),
    shaders: idlib.idList(Shader),
    uniforms: idlib.idStaticList(CVec4, MAX_UNIFORMS),
    uniformsChanged: bool,
    device: *nvrhi.IDevice,
    vertexLayoutDescs: idlib.idStaticList(
        VertexAttribDescList,
        NUM_VERTEX_LAYOUTS,
    ),
    bindingLayouts: idlib.idStaticList(
        idlib.idStaticList(nvrhi.BindingLayoutHandle, nvrhi.c_MaxBindingLayouts),
        NUM_BINDING_LAYOUTS,
    ),
    constantBuffer: nvrhi.BufferHandle,

    extern fn c_renderProgManager_init(*RenderProgManager, *nvrhi.IDevice) callconv(.C) void;
    extern fn c_renderProgManager_shutdown(*RenderProgManager) callconv(.C) void;
    extern fn c_renderProgManager_unbind(*RenderProgManager) callconv(.C) void;

    pub fn unbind(prog_manager: *RenderProgManager) void {
        c_renderProgManager_unbind(prog_manager);
    }

    pub fn init(prog_manager: *RenderProgManager, device: *nvrhi.IDevice) void {
        // TODO rewrite
        c_renderProgManager_init(prog_manager, device);
    }

    pub fn shutdown(prog_manager: *RenderProgManager) void {
        c_renderProgManager_shutdown(prog_manager);
    }
};

pub const instance = @extern(*RenderProgManager, .{ .name = "renderProgManager" });
