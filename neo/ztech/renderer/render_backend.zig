const BackendCounters = extern struct {
    c_surfaces: c_int,
    c_shaders: c_int,
    c_drawElements: c_int,
    c_drawIndexes: c_int,
    c_shadowAtlasUsage: c_int, // allocated pixels in the atlas
    c_shadowViews: c_int,
    c_shadowElements: c_int,
    c_shadowIndexes: c_int,
    c_copyFrameBuffer: c_int,
    c_overDraw: f32,
    cpuTotalMicroSec: c_ulonglong, // total microseconds for backend run
    cpuShadowMicroSec: c_ulonglong,
    gpuBeginDrawingMicroSec: c_ulonglong,
    gpuDepthMicroSec: c_ulonglong,
    gpuGeometryMicroSec: c_ulonglong,
    gpuScreenSpaceAmbientOcclusionMicroSec: c_ulonglong,
    gpuScreenSpaceReflectionsMicroSec: c_ulonglong,
    gpuAmbientPassMicroSec: c_ulonglong,
    gpuShadowAtlasPassMicroSec: c_ulonglong,
    gpuInteractionsMicroSec: c_ulonglong,
    gpuShaderPassMicroSec: c_ulonglong,
    gpuFogAllLightsMicroSec: c_ulonglong,
    gpuBloomMicroSec: c_ulonglong,
    gpuShaderPassPostMicroSec: c_ulonglong,
    gpuMotionVectorsMicroSec: c_ulonglong,
    gpuTemporalAntiAliasingMicroSec: c_ulonglong,
    gpuToneMapPassMicroSec: c_ulonglong,
    gpuPostProcessingMicroSec: c_ulonglong,
    gpuDrawGuiMicroSec: c_ulonglong,
    gpuCrtPostProcessingMicroSec: c_ulonglong,
    gpuMicroSec: c_ulonglong,
};

const DrawSurface = @import("common.zig").DrawSurface;
const ViewDef = @import("common.zig").ViewDef;
const ViewEntity = @import("common.zig").ViewEntity;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const CVec2 = @import("../math/vector.zig").CVec2;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const nvrhi = @import("nvrhi.zig");
const Pass = @import("render_pass.zig");

fn idList(T: type) type {
    return extern struct {
        num: c_int,
        size: c_int,
        granularity: c_int,
        list: ?*T,
        memTag: u8,
    };
}

fn idStaticList(T: type, size: usize) type {
    return extern struct {
        num: c_int,
        list: [size]T,
    };
}

const TileMap = extern struct {
    const TileNode = extern struct {
        position: CVec2,
        childIndices: [4]c_int,
        level: c_uint,
        minLevel: c_uint,
    };
    mapSize: f32,
    log2MapSize: c_uint,
    minAbsTileSize: f32,
    maxAbsTileSize: f32,
    numLevels: c_uint,
    numNodes: c_uint,
    nodeIndex: c_uint,
    tileNodeList: idList(TileNode),
    foundNode: ?*TileNode,
};

const idSysMutex = extern struct {
    const MutexHandle = @import("std").c.pthread_mutex_t;
    handle: MutexHandle,
};

const idHashIndex = extern struct {
    hashSize: c_int,
    hash: ?*c_int,
    indexSize: c_int,
    indexChain: ?*c_int,
    granularity: c_int,
    hashMask: c_int,
    lookupMask: c_int,
};

const BindingCache = extern struct {
    device: ?*nvrhi.IDevice,
    bindingSets: idList(nvrhi.BindingSetHandle),
    bindingHash: idHashIndex,
    mutex: idSysMutex,
};

const SamplerCache = extern struct {
    device: ?*nvrhi.IDevice,
    samplers: idList(nvrhi.SamplerHandle),
    samplerHash: idHashIndex,
    mutex: idSysMutex,
};

const PipelineCache = extern struct {
    device: nvrhi.DeviceHandle,
    pipelineHash: idHashIndex,
    pipelines: idList(anyopaque),
};

const BindingLayoutType = struct {
    pub const BINDING_LAYOUT_DEFAULT: c_int = 0;
    pub const BINDING_LAYOUT_DEFAULT_SKINNED: c_int = 1;
    pub const BINDING_LAYOUT_CONSTANT_BUFFER_ONLY: c_int = 2;
    pub const BINDING_LAYOUT_CONSTANT_BUFFER_ONLY_SKINNED: c_int = 3;
    pub const BINDING_LAYOUT_AMBIENT_LIGHTING_IBL: c_int = 4;
    pub const BINDING_LAYOUT_AMBIENT_LIGHTING_IBL_SKINNED: c_int = 5;
    pub const BINDING_LAYOUT_DRAW_INTERACTION: c_int = 6;
    pub const BINDING_LAYOUT_DRAW_INTERACTION_SKINNED: c_int = 7;
    pub const BINDING_LAYOUT_DRAW_INTERACTION_SM: c_int = 8;
    pub const BINDING_LAYOUT_DRAW_INTERACTION_SM_SKINNED: c_int = 9;
    pub const BINDING_LAYOUT_FOG: c_int = 10;
    pub const BINDING_LAYOUT_FOG_SKINNED: c_int = 11;
    pub const BINDING_LAYOUT_BLENDLIGHT: c_int = 12;
    pub const BINDING_LAYOUT_BLENDLIGHT_SKINNED: c_int = 13;
    pub const BINDING_LAYOUT_NORMAL_CUBE: c_int = 14;
    pub const BINDING_LAYOUT_NORMAL_CUBE_SKINNED: c_int = 15;
    pub const BINDING_LAYOUT_POST_PROCESS_INGAME: c_int = 16;
    pub const BINDING_LAYOUT_POST_PROCESS_FINAL: c_int = 17;
    pub const BINDING_LAYOUT_BLIT: c_int = 18;
    pub const BINDING_LAYOUT_DRAW_AO: c_int = 19;
    pub const BINDING_LAYOUT_DRAW_AO1: c_int = 20;
    pub const BINDING_LAYOUT_BINK_VIDEO: c_int = 21;
    pub const BINDING_LAYOUT_TAA_MOTION_VECTORS: c_int = 22;
    pub const BINDING_LAYOUT_TAA_RESOLVE: c_int = 23;
    pub const BINDING_LAYOUT_TONEMAP: c_int = 24;
    pub const BINDING_LAYOUT_HISTOGRAM: c_int = 25;
    pub const BINDING_LAYOUT_EXPOSURE: c_int = 26;
    pub const NUM_BINDING_LAYOUTS: c_int = 27;
};

pub const RenderBackend = extern struct {
    pc: BackendCounters,
    unitSquareSurface: DrawSurface,
    zeroOneCubeSurface: DrawSurface,
    zeroOneSphereSurface: DrawSurface,
    testImageSurface: DrawSurface,
    slopeScaleBias: f32,
    depthBias: f32,
    glStateBits: c_ulonglong,
    viewDef: ?*const ViewDef,
    currentSpace: ?*const ViewEntity,
    currentScissor: ScreenRect,
    currentRenderCopied: bool,
    prevMVP: [2]RenderMatrix,
    prevViewsValid: bool,
    hdrAverageLuminance: f32,
    hdrMaxLuminance: f32,
    hdrTime: f32,
    hdrKey: f32,
    // quad-tree for managing tiles within tiled shadow map
    tileMap: TileMap,
    stateViewport: ScreenRect,
    stateScissor: ScreenRect,
    currentViewport: ScreenRect,
    currentVertexBuffer: nvrhi.BufferHandle,
    currentVertexOffset: c_uint,
    currentIndexBuffer: nvrhi.BufferHandle,
    currentIndexOffset: c_uint,
    currentBindingLayout: nvrhi.BindingLayoutHandle,
    currentJointBuffer: ?*nvrhi.IBuffer,
    currentJointOffset: c_uint,
    currentPipeline: nvrhi.GraphicsPipelineHandle,
    currentBindingSets: idStaticList(nvrhi.BindingSetHandle, nvrhi.c_MaxBindingLayouts),
    pendingBindingSetDescs: idStaticList(
        idStaticList(nvrhi.BindingSetDesc, nvrhi.c_MaxBindingLayouts),
        BindingLayoutType.NUM_BINDING_LAYOUTS,
    ),
    currentFramebuffer: *Framebuffer,
    lastFramebuffer: *Framebuffer,
    commandList: nvrhi.CommandListHandle,
    commonPasses: Pass.CommonRenderPasses,
    ssaoPass: ?*Pass.SsaoPass,
    hiZGenPass: ?*Pass.MipMapGenPass,
    toneMapPass: ?*Pass.TonemapPass,
    taaPass: ?*Pass.TemporalAntiAliasingPass,
    bindingCache: BindingCache,
    samplerCache: SamplerCache,
    pipelineCache: PipelineCache,
    inputLayout: nvrhi.InputLayoutHandle,
    vertexShader: nvrhi.ShaderHandle,
    pixelShader: nvrhi.ShaderHandle,
    prevBindingLayoutType: c_int,

    extern fn c_renderBackend_shutdown(*RenderBackend) callconv(.C) void;
    extern fn c_renderBackend_init(*RenderBackend) callconv(.C) void;
    extern fn c_renderBackend_checkCVars(*RenderBackend) callconv(.C) void;

    pub fn shutdown(backend: *RenderBackend) void {
        c_renderBackend_shutdown(backend);
    }

    pub fn init(backend: *RenderBackend) void {
        c_renderBackend_init(backend);
    }

    pub fn GL_BlockingSwapBuffers(_: *RenderBackend) void {}

    pub fn checkCVars(backend: *RenderBackend) void {
        c_renderBackend_checkCVars(backend);
    }
};
