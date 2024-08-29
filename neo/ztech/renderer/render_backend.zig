const std = @import("std");
const Image = @import("image.zig");
const RenderSystem = @import("render_system.zig");
const DeviceManager = @import("../sys/device_manager.zig");
const VertexCache = @import("vertex_cache.zig");
const ImmediateMode = @import("immediate_mode.zig");
const RenderLog = @import("render_log.zig");
const RenderProgManager = @import("render_prog_manager.zig");
const ResolutionScale = @import("resolution_scale.zig");
const Common = @import("../framework/common.zig");
const ImageManager = @import("image_manager.zig");

pub const BackendCounters = extern struct {
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
const RenderMatrixIdentity = @import("matrix.zig").identity;
const CVec2 = @import("../math/vector.zig").CVec2;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const global_framebuffers = @import("framebuffer.zig").global_framebuffers;
const nvrhi = @import("nvrhi.zig");
const Pass = @import("render_pass.zig");
const FrameData = @import("frame_data.zig");
const idlib = @import("../idlib.zig");

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
    tileNodeList: idlib.idList(TileNode),
    foundNode: ?*TileNode,

    extern fn c_tileMap_init(*TileMap, c_uint, c_uint, c_uint) callconv(.C) void;

    fn init(tile_map: *TileMap, map_size: usize, max_abs_tile_size: usize, num_levels: usize) void {
        c_tileMap_init(
            tile_map,
            @intCast(map_size),
            @intCast(max_abs_tile_size),
            @intCast(num_levels),
        );
    }
};

const BindingCache = extern struct {
    device: ?*nvrhi.IDevice,
    bindingSets: idlib.idList(nvrhi.BindingSetHandle),
    bindingHash: idlib.idHashIndex,
    mutex: idlib.idSysMutex,

    fn init(binding_cache: *BindingCache, device: *nvrhi.IDevice) void {
        binding_cache.device = device;
    }

    fn clear(binding_cache: *BindingCache) void {
        _ = binding_cache.mutex.lockBlocking();
        defer binding_cache.mutex.unlock();

        for (binding_cache.bindingSets.slice()) |*binding_set| {
            _ = binding_set.reset();
        }

        binding_cache.bindingSets.clear();
        binding_cache.bindingHash.clear();
    }
};

const SamplerCache = extern struct {
    device: ?*nvrhi.IDevice,
    samplers: idlib.idList(nvrhi.SamplerHandle),
    samplerHash: idlib.idHashIndex,
    mutex: idlib.idSysMutex,

    fn init(sampler_cache: *SamplerCache, device: *nvrhi.IDevice) void {
        sampler_cache.device = device;
    }

    fn clear(sampler_cache: *SamplerCache) void {
        _ = sampler_cache.mutex.lockBlocking();
        defer sampler_cache.mutex.unlock();

        sampler_cache.samplers.clear();
        sampler_cache.samplerHash.clear();
    }
};

fn CppStdPair(First: type, Second: type) type {
    return extern struct {
        first: First,
        second: Second,
    };
}

const PipelineCache = extern struct {
    const PipelineKey = extern struct {
        state: u64,
        program: c_int,
        depthBias: c_int,
        slopeBias: f32,
        framebuffer: ?*Framebuffer,
    };

    device: nvrhi.DeviceHandle,
    pipelineHash: idlib.idHashIndex,
    pipelines: idlib.idList(CppStdPair(PipelineKey, nvrhi.GraphicsPipelineHandle)),

    extern fn c_pipelineCache_clear(*PipelineCache) callconv(.C) void;

    fn init(pipeline_cache: *PipelineCache, device: *nvrhi.IDevice) void {
        pipeline_cache.device = nvrhi.DeviceHandle.init(device);
    }

    fn shutdown(pipeline_cache: *PipelineCache) void {
        pipeline_cache.device.deinit();
    }

    fn clear(pipeline_cache: *PipelineCache) void {
        c_pipelineCache_clear(pipeline_cache);
    }
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
    pub const BINDING_LAYOUT_POST_PROCESS_FINAL2: c_int = 18;
    pub const BINDING_LAYOUT_POST_PROCESS_CRT: c_int = 19;
    pub const BINDING_LAYOUT_BLIT: c_int = 20;
    pub const BINDING_LAYOUT_DRAW_AO: c_int = 21;
    pub const BINDING_LAYOUT_DRAW_AO1: c_int = 22;
    pub const BINDING_LAYOUT_BINK_VIDEO: c_int = 23;
    pub const BINDING_LAYOUT_TAA_MOTION_VECTORS: c_int = 24;
    pub const BINDING_LAYOUT_TAA_RESOLVE: c_int = 25;
    pub const BINDING_LAYOUT_TONEMAP: c_int = 26;
    pub const BINDING_LAYOUT_HISTOGRAM: c_int = 27;
    pub const BINDING_LAYOUT_EXPOSURE: c_int = 28;
    pub const NUM_BINDING_LAYOUTS: c_int = 29;
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
    currentBindingSets: idlib.idStaticList(nvrhi.BindingSetHandle, nvrhi.c_MaxBindingLayouts),
    pendingBindingSetDescs: idlib.idStaticList(
        idlib.idStaticList(nvrhi.BindingSetDesc, nvrhi.c_MaxBindingLayouts),
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

    extern fn c_renderBackend_clearContext() callconv(.C) void;
    extern fn c_renderBackend_checkCVars(*RenderBackend) callconv(.C) void;
    extern fn c_renderBackend_executeBackendCommands(*RenderBackend, ?*FrameData.EmptyCommand) callconv(.C) void;
    extern fn c_renderBackend_constructInPlace(*RenderBackend) callconv(.C) void;

    extern fn VKimp_PreInit() callconv(.C) void;
    extern fn VKimp_Shutdown(bool) callconv(.C) void;
    extern fn R_SetNewMode(bool) callconv(.C) void;
    extern fn Sys_InitInput() callconv(.C) void;

    pub fn shutdown(backend: *RenderBackend) void {
        backend.clearCaches();
        backend.pipelineCache.shutdown();
        backend.commonPasses.shutdown();

        for (backend.currentBindingSets.slice()) |*binding_set| {
            _ = binding_set.reset();
        }

        RenderProgManager.instance.shutdown();
        RenderLog.instance.shutdown();
        _ = backend.commandList.reset();
        ImmediateMode.shutdown();
        VKimp_Shutdown(true);

        DeviceManager.deinit();
    }

    pub fn clearCaches(backend: *RenderBackend) void {
        backend.pipelineCache.clear();
        backend.bindingCache.clear();
        backend.samplerCache.clear();

        if (backend.hiZGenPass) |hiZGenPass| {
            hiZGenPass.destroy();
            backend.hiZGenPass = null;
        }

        if (backend.ssaoPass) |ssaoPass| {
            ssaoPass.destroy();
            backend.ssaoPass = null;
        }

        if (backend.toneMapPass) |toneMapPass| {
            toneMapPass.destroy();
            backend.toneMapPass = null;
        }

        if (backend.taaPass) |taaPass| {
            taaPass.destroy();
            backend.taaPass = null;
        }

        backend.currentVertexBuffer.deinit();
        backend.currentIndexBuffer.deinit();
        backend.currentJointBuffer = null;
        backend.currentIndexOffset = std.math.maxInt(c_uint);
        backend.currentVertexOffset = std.math.maxInt(c_uint);
        backend.currentBindingLayout.deinit();
        backend.currentPipeline.deinit();
    }

    pub fn init(backend: *RenderBackend, allocator: std.mem.Allocator) error{OutOfMemory}!void {
        if (RenderSystem.instance.backend_initialized) @panic("RenderBackend already initialized");

        // TODO: Remove
        c_renderBackend_constructInPlace(backend);

        const api = nvrhi.GraphicsAPI.VULKAN;

        DeviceManager.init(api);
        VKimp_PreInit();
        R_SetNewMode(true);
        Sys_InitInput();

        c_renderBackend_clearContext();

        const device = DeviceManager.instance().getDevice();
        RenderProgManager.instance.init(device);
        RenderLog.instance.init();

        const MAX_TILE_RES: usize = 1024; // shadowMapResolutions[0]
        const NUM_QUAD_TREE_LEVELS: usize = 8;
        const r_shadowMapAtlasSize = 8192;
        backend.tileMap.init(r_shadowMapAtlasSize, MAX_TILE_RES, NUM_QUAD_TREE_LEVELS);

        backend.bindingCache.init(device);
        backend.samplerCache.init(device);
        backend.pipelineCache.init(device);
        backend.commonPasses.init(device);
        backend.hiZGenPass = null;
        backend.ssaoPass = null;
        backend.toneMapPass = null;
        backend.taaPass = null;

        RenderSystem.instance.backend_initialized = true;

        const command_list_ptr = if (backend.commandList.ptr_) |ptr|
            ptr
        else command_list: {
            const r_vkUploadBufferSizeMB = 64;
            const handle = device.createCommandList(.{
                // if api == VULKAN
                .uploadChunkSize = r_vkUploadBufferSizeMB * 1024 * 1024,
            });
            backend.commandList = handle;

            break :command_list handle.ptr_ orelse @panic("Fails to create command-list!");
        };

        command_list_ptr.open();
        VertexCache.instance.init(
            @intCast(RenderSystem.glConfig.uniformBufferOffsetAlignment),
            command_list_ptr,
        );
        command_list_ptr.close();
        device.executeCommandList(command_list_ptr);
        ImmediateMode.init(command_list_ptr);

        try FrameData.init(allocator);
        backend.slopeScaleBias = 0;
        backend.depthBias = 0;

        backend.currentBindingSets.setNum(backend.currentBindingSets.max());
        backend.pendingBindingSetDescs.setNum(backend.pendingBindingSetDescs.max());

        backend.prevMVP[0] = RenderMatrixIdentity;
        backend.prevMVP[1] = RenderMatrixIdentity;
        backend.prevViewsValid = false;

        backend.currentVertexBuffer = .{};
        backend.currentIndexBuffer = .{};
        backend.currentJointBuffer = null;
        backend.currentVertexOffset = 0;
        backend.currentIndexOffset = 0;
        backend.currentJointOffset = 0;
        backend.prevBindingLayoutType = -1;

        device.waitForIdle();
        device.runGarbageCollection();
    }

    pub fn swapBuffersBlocking(_: *RenderBackend) void {
        const device_manager = DeviceManager.instance();
        device_manager.present();
        device_manager.getDevice().runGarbageCollection();
        RenderLog.instance.endFrame();

        // if api == VULKAN
        // invalidate swap buffers
        RenderSystem.instance.omit_swap_buffers = true;
    }

    pub fn checkCVars(backend: *RenderBackend) void {
        c_renderBackend_checkCVars(backend);
    }

    pub fn executeBackendCommands(backend: *RenderBackend, cmd_head: *FrameData.EmptyCommand) void {
        ResolutionScale.instance.setCurrentGPUFrameTime(@intCast(Common.instance.getRendererGPUMicroseconds()));
        backend.resizeImages();

        if (cmd_head.commandId == .RC_NOP and cmd_head.next == null) return;

        if (RenderSystem.glConfig.stereo3Dmode != RenderSystem.STEREO3D_OFF) {
            backend.stereoRenderExecuteBackendCommands(cmd_head);
            return;
        }

        backend.startFrame();

        const texture_id = ImageManager.instance.hierarchicalZbufferImage.?.getTextureID();

        // RB: we need to load all images left before rendering
        // this can be expensive here because of the runtime image compression
        // ImageManager.instance.loadDeferredImages(backend.commandList.ptr_);
        const device_manager = DeviceManager.instance();

        if (backend.ssaoPass == null) {
            backend.ssaoPass = Pass.SsaoPass.create(
                device_manager.getDevice(),
                &backend.commonPasses,
                ImageManager.instance.currentDepthImage.?.getTexturePtr(),
                ImageManager.instance.gbufferNormalsRoughnessImage.?.getTexturePtr(),
                ImageManager.instance.ambientOcclusionImage[0].?.getTexturePtr(),
            );
        }

        if (texture_id != ImageManager.instance.hierarchicalZbufferImage.?.getTextureID() or
            backend.hiZGenPass == null)
        {
            if (backend.hiZGenPass) |pass| {
                pass.destroy();
            }

            backend.hiZGenPass = Pass.MipMapGenPass.create(
                device_manager.getDevice(),
                ImageManager.instance.hierarchicalZbufferImage.?.getTexturePtr(),
                .MODE_MAX,
            );
        }

        if (backend.toneMapPass == null) {
            const pass = Pass.TonemapPass.create();
            pass.init(
                device_manager.getDevice(),
                &backend.commonPasses,
                .{},
                global_framebuffers.ldrFBO.getApiObject(),
            );
            backend.toneMapPass = pass;
        }

        if (backend.taaPass == null) {
            const pass = Pass.TemporalAntiAliasingPass.create();
            pass.init(
                device_manager.getDevice(),
                &backend.commonPasses,
                null,
                .{
                    .sourceDepth = ImageManager.instance.currentDepthImage.?.getTexturePtr(),
                    .motionVectors = ImageManager.instance.taaMotionVectorsImage.?.getTexturePtr(),
                    .unresolvedColor = ImageManager.instance.currentRenderHDRImage.?.getTexturePtr(),
                    .resolvedColor = ImageManager.instance.taaResolvedImage.?.getTexturePtr(),
                    .feedback1 = ImageManager.instance.taaFeedback1Image.?.getTexturePtr(),
                    .feedback2 = ImageManager.instance.taaFeedback2Image.?.getTexturePtr(),
                    .motionVectorStencilMask = 0, //0x01,
                    .useCatmullRomFilter = true,
                },
            );
            backend.taaPass = pass;
        }

        c_renderBackend_executeBackendCommands(backend, cmd_head);
    }

    fn stereoRenderExecuteBackendCommands(_: *RenderBackend, _: *FrameData.EmptyCommand) void {
        // TODO: implement
    }

    fn startFrame(backend: *RenderBackend) void {
        RenderLog.instance.fetchGPUTimers(&backend.pc);

        DeviceManager.instance().beginFrame();
        Image.emptyGarbage();

        const command_list = backend.commandList.ptr_ orelse @panic("Not initialized");
        command_list.open();

        RenderLog.instance.startFrame(command_list);
        RenderLog.instance.openMainBlock(RenderLog.MRB_GPU_TIME);
    }

    fn resizeImages(_: *RenderBackend) void {
        DeviceManager.instance().updateWindowSize(.{
            .width = RenderSystem.glConfig.nativeScreenWidth,
            .height = RenderSystem.glConfig.nativeScreenHeight,
            .multiSamples = RenderSystem.glConfig.multisamples,
        });
    }
};
