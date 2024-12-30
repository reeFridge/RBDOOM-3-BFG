//! @exportCVars
const std = @import("std");
const Vec2 = @import("../math/vector.zig").Vec2;
const Image = @import("image.zig");
const RenderSystem = @import("render_system.zig");
const device_manager = @import("../sys/device_manager.zig");
const vertex_cache = @import("vertex_cache.zig");
const ImmediateMode = @import("immediate_mode.zig");
const render_log = @import("render_log.zig");
const render_prog_manager = @import("render_prog_manager.zig");
const RenderProgManager = render_prog_manager.RenderProgManager;
const ResolutionScale = @import("resolution_scale.zig");
const Common = @import("../framework/common.zig");
const image_manager = @import("image_manager.zig");
const vulkan_impl = @import("../sys/sdl/vulkan.zig");
const vulkan = @import("vulkan");
const gl_state = @import("gl_state.zig");
const Allocator = std.mem.Allocator;
const DeviceManager = device_manager.DeviceManagerVulkan;

const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;
const CFlags = cvar.CVarFlags;

pub var r_vk_upload_buffer_size_mb = CVar.init(
    "r_vkUploadBufferSizeMB",
    "64",
    CFlags.CVAR_INTEGER | CFlags.CVAR_INIT | CFlags.CVAR_NEW,
    "Size of gpu upload buffer (Vulkan only)",
);

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
const framebuffer = @import("framebuffer.zig");
const Framebuffer = framebuffer.Framebuffer;
const global_framebuffers = framebuffer.global_framebuffers;
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
    tileNodeList: idlib.List(TileNode),
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

pub const BindingCache = extern struct {
    device: ?*nvrhi.IDevice,
    bindingSets: idlib.List(nvrhi.BindingSetHandle),
    bindingHash: idlib.HashIndex,
    mutex: idlib.SysMutex,

    fn init(binding_cache: *BindingCache, device: *nvrhi.IDevice) void {
        binding_cache.device = device;
    }

    fn clear(binding_cache: *BindingCache, allocator: Allocator) void {
        _ = binding_cache.mutex.lockBlocking();
        defer binding_cache.mutex.unlock();

        for (binding_cache.bindingSets.slice()) |*binding_set| {
            _ = binding_set.reset();
        }

        binding_cache.bindingSets.clear(allocator);
        binding_cache.bindingHash.clear();
    }

    pub fn getOrCreateBindingSet(
        binding_cache: *BindingCache,
        desc: *const nvrhi.BindingSetDesc,
        layout: *nvrhi.IBindingLayout,
        allocator: Allocator,
    ) Allocator.Error!nvrhi.BindingSetHandle {
        var hash: usize = 0;
        desc.hashCombine(&hash);
        nvrhi.hashCombinePtr(&hash, @ptrCast(layout));

        const hash_u16: u16 = @truncate(hash);

        var result: nvrhi.BindingSetHandle = .{};
        {
            _ = binding_cache.mutex.lockBlocking();
            defer binding_cache.mutex.unlock();

            const binding_sets = binding_cache.bindingSets.constSlice();
            var i = binding_cache.bindingHash.first(hash_u16);
            while (i != -1) : (i = binding_cache.bindingHash.next(@intCast(i))) {
                const binding_set = binding_sets[@intCast(i)].ptr_.?;
                if (binding_set.getDesc().eql(desc)) {
                    result = .{ .ptr_ = binding_set };
                    break;
                }
            }
        }

        if (result.ptr_ == null) {
            _ = binding_cache.mutex.lockBlocking();
            defer binding_cache.mutex.unlock();

            const device = binding_cache.device orelse @panic("device is not set");
            result = device.createBindingSet(desc, layout);

            const entry_index = try binding_cache.bindingSets.append(result, allocator);
            try binding_cache.bindingHash.add(
                hash_u16,
                @intCast(entry_index),
                allocator,
            );
        }

        return result;
    }
};

const SamplerCache = extern struct {
    device: ?*nvrhi.IDevice,
    samplers: idlib.List(nvrhi.SamplerHandle),
    samplerHash: idlib.HashIndex,
    mutex: idlib.SysMutex,

    fn init(sampler_cache: *SamplerCache, device: *nvrhi.IDevice) void {
        sampler_cache.device = device;
    }

    fn clear(sampler_cache: *SamplerCache, allocator: Allocator) void {
        _ = sampler_cache.mutex.lockBlocking();
        defer sampler_cache.mutex.unlock();

        sampler_cache.samplers.clear(allocator);
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
    pipelineHash: idlib.HashIndex,
    pipelines: idlib.List(CppStdPair(PipelineKey, nvrhi.GraphicsPipelineHandle)),

    fn init(pipeline_cache: *PipelineCache, device: *nvrhi.IDevice) void {
        pipeline_cache.device = nvrhi.DeviceHandle.init(device);
    }

    fn shutdown(pipeline_cache: *PipelineCache) void {
        pipeline_cache.device.deinit();
    }

    fn clear(pipeline_cache: *PipelineCache, allocator: Allocator) void {
        pipeline_cache.pipelineHash.clear();
        pipeline_cache.pipelines.clear(allocator);
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

const NvrhiContext = extern struct {
    const MAX_IMAGE_PARMS = 16;

    currentImageParm: c_int = 0,
    imageParms: [MAX_IMAGE_PARMS]?*Image.Image,
    scissor: ScreenRect,
};

const nvrhi_context = @extern(*NvrhiContext, .{ .name = "context" });
const prev_nvrhi_context = @extern(*NvrhiContext, .{ .name = "prevContext" });

pub const RenderBackend = extern struct {
    pc: BackendCounters,
    unitSquareSurface: DrawSurface,
    zeroOneCubeSurface: DrawSurface,
    zeroOneSphereSurface: DrawSurface,
    testImageSurface: DrawSurface,
    slopeScaleBias: f32,
    depthBias: f32,
    glStateBits: c_ulonglong,
    view_def: ?*const ViewDef,
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
    currentBindingSets: idlib.StaticList(nvrhi.BindingSetHandle, nvrhi.c_MaxBindingLayouts),
    pendingBindingSetDescs: idlib.StaticList(
        idlib.StaticList(nvrhi.BindingSetDesc, nvrhi.c_MaxBindingLayouts),
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

    extern fn c_renderBackend_clearContext() void;
    extern fn c_renderBackend_checkCVars(*RenderBackend) void;
    extern fn c_renderBackend_stereoRenderExecuteBackEndCommands(
        *RenderBackend,
        *FrameData.EmptyCommand,
    ) void;
    extern fn c_renderBackend_constructInPlace(*RenderBackend) void;
    extern fn c_renderBackend_drawView(*RenderBackend, *anyopaque, c_int) void;
    extern fn c_renderBackend_setBuffer(*RenderBackend, *anyopaque) void;
    extern fn c_renderBackend_copyRender(*RenderBackend, *anyopaque) void;
    extern fn c_renderBackend_postProcess(*RenderBackend, *anyopaque) void;
    extern fn c_renderBackend_crtPostProcess(*RenderBackend) void;
    extern fn VKimp_Shutdown(bool) void;
    extern fn Sys_InitInput() void;

    pub fn getCurrentPixelOffset(backend: *RenderBackend) Vec2(f32) {
        return if (backend.taaPass) |taa|
            taa.getCurrentPixelOffset()
        else
            Vec2(f32){};
    }

    pub fn shutdown(backend: *RenderBackend, allocator: Allocator) void {
        backend.clearCaches(allocator);
        backend.pipelineCache.shutdown();
        backend.commonPasses.shutdown();

        for (backend.currentBindingSets.slice()) |*binding_set| {
            _ = binding_set.reset();
        }

        render_prog_manager.instance.shutdown();
        render_log.instance.shutdown();
        _ = backend.commandList.reset();
        ImmediateMode.shutdown();
        VKimp_Shutdown(true);

        device_manager.deinit();
    }

    pub fn clearCaches(backend: *RenderBackend, allocator: Allocator) void {
        backend.pipelineCache.clear(allocator);
        backend.bindingCache.clear(allocator);
        backend.samplerCache.clear(allocator);

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

    pub const InitError = Allocator.Error ||
        RenderProgManager.LoadShaderError ||
        device_manager.DeviceManagerVulkan.CreateError;
    pub fn init(
        backend: *RenderBackend,
        allocator: Allocator,
    ) InitError!void {
        if (RenderSystem.instance.backend_initialized)
            @panic("RenderBackend already initialized");

        // TODO: Remove
        c_renderBackend_constructInPlace(backend);

        const api = nvrhi.GraphicsAPI.VULKAN;

        try device_manager.init(api);
        vulkan_impl.beforeInit();
        try RenderSystem.updateDisplayMode(true, allocator);
        Sys_InitInput();

        c_renderBackend_clearContext();

        const device_manager_instance = device_manager.instance();
        const device = device_manager_instance.getDevice();
        try render_prog_manager.instance.init(device, allocator);
        render_log.instance.init(device);

        const MAX_TILE_RES: usize = 1024; // shadowMapResolutions[0]
        const NUM_QUAD_TREE_LEVELS: usize = 8;
        const r_shadowMapAtlasSize = 8192;
        backend.tileMap.init(r_shadowMapAtlasSize, MAX_TILE_RES, NUM_QUAD_TREE_LEVELS);

        backend.bindingCache.init(device);
        backend.samplerCache.init(device);
        backend.pipelineCache.init(device);
        try backend.commonPasses.init(device, render_prog_manager.instance, allocator);
        backend.hiZGenPass = null;
        backend.ssaoPass = null;
        backend.toneMapPass = null;
        backend.taaPass = null;

        RenderSystem.instance.backend_initialized = true;

        const command_list_ptr = if (backend.commandList.ptr_) |ptr|
            ptr
        else command_list: {
            const mb: u32 = @intCast(r_vk_upload_buffer_size_mb.integer_value);
            const handle = device.createCommandList(.{
                // if api == VULKAN
                .uploadChunkSize = mb * 1024 * 1024,
            });
            backend.commandList = handle;

            break :command_list handle.ptr_ orelse @panic("Fails to create command-list!");
        };

        command_list_ptr.open();
        vertex_cache.instance.init(
            @intCast(RenderSystem.gl_config.uniformBufferOffsetAlignment),
            command_list_ptr,
            device_manager.vma_allocator,
            device,
            device_manager_instance.isDeviceExtensionEnabled(
                vulkan.extensions.khr_buffer_device_address.name,
            ),
        );
        command_list_ptr.close();
        device.executeCommandList(command_list_ptr);
        // TODO: ImmediateMode.init(command_list_ptr);

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

    pub const SwapBuffersError = DeviceManager.PresentError;
    pub fn swapBuffersBlocking(_: *RenderBackend) DeviceManager.PresentError!void {
        const device_manager_instance = device_manager.instance();
        try device_manager_instance.present();
        device_manager_instance.getDevice().runGarbageCollection();
        render_log.instance.endFrame();

        // if api == VULKAN
        // invalidate swap buffers
        RenderSystem.instance.omit_swap_buffers = true;
    }

    pub fn checkCVars(backend: *RenderBackend) void {
        c_renderBackend_checkCVars(backend);
    }

    pub const ExecuteCommandsError =
        DeviceManager.UpdateWindowSizeError ||
        DeviceManager.BeginFrameError;
    pub fn executeBackendCommands(
        backend: *RenderBackend,
        cmd_head: *FrameData.EmptyCommand,
        allocator: Allocator,
    ) ExecuteCommandsError!void {
        ResolutionScale.instance.setCurrentGPUFrameTime(
            @intCast(Common.instance.getRendererGPUMicroseconds()),
        );
        try backend.resizeImages(allocator);

        if (cmd_head.commandId == .RC_NOP and cmd_head.next == null) return;

        if (RenderSystem.gl_config.stereo3Dmode != .OFF) {
            backend.stereoRenderExecuteBackendCommands(cmd_head);
            return;
        }

        try backend.glStartFrame();
        const global_images = image_manager.instance;

        const texture_id = global_images.hierarchicalZBufferImage.?.getTextureID();

        // RB: we need to load all images left before rendering
        // this can be expensive here because of the runtime image compression
        // image_manager.instance.loadDeferredImages(backend.commandList.ptr_);
        const device_manager_instance = device_manager.instance();
        _ = device_manager_instance.getDevice();

        if (backend.ssaoPass == null) {
            //backend.ssaoPass = Pass.SsaoPass.create(
            //    device,
            //    &backend.commonPasses,
            //    global_images.currentDepthImage.?.getTexturePtr(),
            //    global_images.gbufferNormalsRoughnessImage.?.getTexturePtr(),
            //    global_images.ambientOcclusionImage[0].?.getTexturePtr(),
            //);
        }

        if (texture_id != global_images.hierarchicalZBufferImage.?.getTextureID() or
            backend.hiZGenPass == null)
        {
            //if (backend.hiZGenPass) |pass| {
            //    pass.destroy();
            //}

            //backend.hiZGenPass = Pass.MipMapGenPass.create(
            //    device,
            //    global_images.hierarchicalZBufferImage.?.getTexturePtr(),
            //    .MODE_MAX,
            //);
        }

        if (backend.toneMapPass == null) {
            //const pass = Pass.TonemapPass.create();
            //pass.init(
            //    device,
            //    &backend.commonPasses,
            //    .{},
            //    global_framebuffers.ldrFBO.getApiObject(),
            //);
            //backend.toneMapPass = pass;
        }

        if (backend.taaPass == null) {
            //const pass = Pass.TemporalAntiAliasingPass.create();
            //pass.init(
            //    device,
            //    &backend.commonPasses,
            //    null,
            //    .{
            //        .sourceDepth = global_images.currentDepthImage.?.getTexturePtr(),
            //        .motionVectors = global_images.taaMotionVectorsImage.?.getTexturePtr(),
            //        .unresolvedColor = global_images.currentRenderHDRImage.?.getTexturePtr(),
            //        .resolvedColor = global_images.taaResolvedImage.?.getTexturePtr(),
            //        .feedback1 = global_images.taaFeedback1Image.?.getTexturePtr(),
            //        .feedback2 = global_images.taaFeedback2Image.?.getTexturePtr(),
            //        .motionVectorStencilMask = 0, //0x01,
            //        .useCatmullRomFilter = true,
            //    },
            //);
            //backend.taaPass = pass;
        }

        backend.glSetDefaultState();

        const timerQueryAvailable = RenderSystem.gl_config.timerQueryAvailable;
        var draw_view_3d = false;
        var opt_cmd: ?*FrameData.EmptyCommand = cmd_head;
        while (opt_cmd) |cmd| : (opt_cmd = @ptrCast(@alignCast(cmd.next))) {
            switch (cmd.commandId) {
                .RC_NOP => {},
                .RC_DRAW_VIEW_GUI => {
                    if (draw_view_3d) {
                        render_log.instance.openMainBlock(render_log.MRB_DRAW_GUI);
                        defer render_log.instance.closeMainBlock(render_log.MRB_DRAW_GUI);
                        render_log.instance.openBlock("Render_DrawViewGUI", .{});
                        defer render_log.instance.closeBlock();
                        RenderSystem.gl_config.timerQueryAvailable = false;
                        defer RenderSystem.gl_config.timerQueryAvailable = timerQueryAvailable;

                        try backend.drawView(@ptrCast(cmd), 0, allocator);
                    } else {
                        try backend.drawView(@ptrCast(cmd), 0, allocator);
                    }
                },
                .RC_DRAW_VIEW_3D => {
                    draw_view_3d = true;
                    try backend.drawView(@ptrCast(cmd), 0, allocator);
                },
                .RC_SET_BUFFER => {
                    backend.setBuffer(@ptrCast(cmd));
                },
                .RC_COPY_RENDER => {
                    backend.copyRender(@ptrCast(cmd));
                },
                .RC_POST_PROCESS => {
                    backend.postProcess(@ptrCast(cmd));
                },
                .RC_CRT_POST_PROCESS => {
                    backend.crtPostProcess();
                },
            }
        }

        backend.glEndFrame();
    }

    fn drawView(
        backend: *RenderBackend,
        cmd: *FrameData.DrawSurfacesCommand,
        stereo_eye: i32,
        allocator: Allocator,
    ) Allocator.Error!void {
        const view_def = cmd.viewDef orelse return;
        backend.view_def = view_def;

        if (view_def.numDrawSurfs == 0) {
            const RDF_IRRADIANCE: c_int = 4;
            if ((view_def.renderView.rdflags & RDF_IRRADIANCE) != 0) {
                @panic("not implemented");
            }

            return;
        }

        const r_skip_render = false;
        if (r_skip_render and view_def.viewEntitys != null) return;

        if (view_def.viewEntitys != null) {
            backend.drawView3d(view_def, stereo_eye);
        } else {
            try backend.drawViewGui(view_def, stereo_eye, allocator);
        }
    }

    fn drawView3d(backend: *RenderBackend, view_def: *ViewDef, stereo_eye: i32) void {
        _ = backend;
        _ = view_def;
        _ = stereo_eye;

        @panic("not implemented");
    }

    fn drawViewGui(
        backend: *RenderBackend,
        view_def: *ViewDef,
        _: i32,
        allocator: Allocator,
    ) Allocator.Error!void {
        const command_list = backend.commandList.ptr_ orelse @panic("command_list not set");

        // resetViewportAndScissorToDefaultCamera
        {
            // set the window clipping
            const x: f32 = @floatFromInt(view_def.viewport.x1);
            const y: f32 = @floatFromInt(view_def.viewport.y1);
            const w: f32 = @floatFromInt(view_def.viewport.x2 + 1 - view_def.viewport.x1);
            const h: f32 = @floatFromInt(view_def.viewport.y2 + 1 - view_def.viewport.y1);
            backend.currentViewport.clear();
            backend.currentViewport.addPoint(x, y);
            backend.currentViewport.addPoint(x + w, y + h);
        }

        {
            // the scissor may be smaller than the viewport for subviews
            const x: u32 = @intCast(backend.view_def.?.viewport.x1 + view_def.scissor.x1);
            const y: u32 = @intCast(backend.view_def.?.viewport.y2 - view_def.scissor.y2);
            const w: u32 = @intCast(view_def.scissor.x2 + 1 - view_def.scissor.x1);
            const h: u32 = @intCast(view_def.scissor.y2 + 1 - view_def.scissor.y1);
            backend.glScissor(x, y, w, h);

            backend.currentScissor = backend.view_def.?.scissor;
        }

        backend.glSetState(gl_state.GLS_DEFAULT | gl_state.GLS_CULL_FRONTSIDED);

        framebuffer.global_framebuffers.ldrFBO.bind(backend);

        const clear_color = false;
        backend.glClear(
            clear_color,
            true,
            true,
            gl_state.STENCIL_SHADOW_TEST_VALUE,
            false,
        );

        // set common shader vars
        {
            render_prog_manager.instance.setUniformValue(
                .globaleyepos,
                &.{
                    view_def.renderView.view_origin.x,
                    view_def.renderView.view_origin.y,
                    view_def.renderView.view_origin.z,
                    1,
                },
            );

            const overbright = 3 * 0.5;
            render_prog_manager.instance.setUniformValue(
                .overbright,
                &.{
                    overbright,
                    overbright,
                    overbright,
                    overbright,
                },
            );

            render_prog_manager.instance.setUniformValue(
                .psx_distortions,
                &.{ 0, 0, 0, 0 },
            );

            const projection_matrix: *RenderMatrix = @ptrCast(&view_def.projectionMatrix);
            const proj_transpose_matrix = projection_matrix.transpose().m;

            for (0..4) |i| {
                var param_index: u32 = @intFromEnum(render_prog_manager.RenderParam.projmatrix_x);
                param_index += @intCast(i);
                render_prog_manager.instance.setUniformValue(
                    @enumFromInt(param_index),
                    @ptrCast((proj_transpose_matrix[i * 4 ..][0..4]).ptr),
                );
            }
        }

        // const draw_surfs = &view_def.drawSurfs[0];
        // const num_draw_surfs = view_def.numDrawSurfs;
        // const processed = backend.drawShaderPasses(
        //     draw_surfs,
        //     num_draw_surfs,
        //     guiScreenOffset,
        //     stereoEye,
        // );

        // copy LDR result to swapchain image
        {
            const current_framebuffer_index = device_manager.instance().getCurrentBackBufferIndex();
            const swap_framebuffers = framebuffer.global_framebuffers.swap_framebuffers.constSlice();
            const blit_params: Pass.BlitParameters = .{
                .source_texture = image_manager.instance.ldrImage.?.texture.ptr_,
                .target_framebuffer = swap_framebuffers[current_framebuffer_index].getApiObject(),
                .target_viewport = nvrhi.Viewport.fromWidthHeight(
                    @floatFromInt(RenderSystem.instance.getWidth()),
                    @floatFromInt(RenderSystem.instance.getHeight()),
                ),
            };

            try backend.commonPasses.blitTexture(
                command_list,
                blit_params,
                &backend.bindingCache,
                allocator,
            );
        }
    }

    fn glClear(
        backend: *RenderBackend,
        color: bool,
        depth: bool,
        stencil: bool,
        stencil_value: u8,
        clear_hdr: bool,
    ) void {
        const current_fb = backend.currentFramebuffer.getApiObject();
        const command_list = backend.commandList.ptr_ orelse @panic("command_list not set");

        if (color) {
            nvrhi.utils.clearColorAttachment(command_list, current_fb, 0, .{});
        }

        if (clear_hdr) {
            const hdr_fb = framebuffer.global_framebuffers.hdrFBO.getApiObject();
            nvrhi.utils.clearColorAttachment(command_list, hdr_fb, 0, .{});
        }

        if (depth or stencil) {
            const depth_attachment = &current_fb.getDesc().depthAttachment;
            if (depth_attachment.texture) |texture| {
                command_list.clearDepthStencilTexture(
                    texture,
                    nvrhi.AllSubresources,
                    depth,
                    1.0,
                    stencil,
                    stencil_value,
                );
            }
        }
    }

    fn setBuffer(backend: *RenderBackend, _: *anyopaque) void {
        // TODO: render_log
        backend.currentScissor.clear();
        backend.currentScissor.addPoint(0, 0);
        backend.currentScissor.addPoint(
            @floatFromInt(RenderSystem.instance.getWidth()),
            @floatFromInt(RenderSystem.instance.getHeight()),
        );
    }

    fn copyRender(backend: *RenderBackend, data: *anyopaque) void {
        c_renderBackend_copyRender(backend, data);
    }

    fn postProcess(backend: *RenderBackend, data: *anyopaque) void {
        c_renderBackend_postProcess(backend, data);
    }

    fn crtPostProcess(backend: *RenderBackend) void {
        c_renderBackend_crtPostProcess(backend);
    }

    fn stereoRenderExecuteBackendCommands(
        backend: *RenderBackend,
        cmds: *FrameData.EmptyCommand,
    ) void {
        c_renderBackend_stereoRenderExecuteBackEndCommands(backend, cmds);
    }

    fn glSetDefaultState(backend: *RenderBackend) void {
        const GLS_DEFAULT: u64 = 0;
        backend.glStateBits = 0;
        backend.glSetState(GLS_DEFAULT);
        backend.glScissor(
            0,
            0,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
        );

        render_prog_manager.instance.unbind();
        framebuffer.unbind(backend, device_manager.instance());
        render_log.instance.closeBlock();
    }

    fn glScissor(
        _: *RenderBackend,
        x: u32,
        y: u32,
        w: u32,
        h: u32,
    ) void {
        nvrhi_context.scissor.clear();
        nvrhi_context.scissor.addPoint(@floatFromInt(x), @floatFromInt(y));
        nvrhi_context.scissor.addPoint(@floatFromInt(x + w), @floatFromInt(y + h));
    }

    fn glSetState(backend: *RenderBackend, state_bits: u64) void {
        backend.glStateBits = state_bits | (backend.glStateBits & gl_state.GLS_KEEP);
        if (backend.view_def) |view_def| {
            if (view_def.isMirror) {
                backend.glStateBits |= gl_state.GLS_MIRROR_VIEW;
            }
        }

        // the rest of this is handled by
        // PipelineCache::GetOrCreatePipeline and GetRenderState similar to Vulkan
    }

    fn glStartFrame(backend: *RenderBackend) DeviceManager.BeginFrameError!void {
        render_log.instance.fetchGPUTimers(
            &backend.pc,
            device_manager.instance().getDevice(),
        );

        try device_manager.instance().beginFrame();
        Image.emptyGarbage();

        const command_list = backend.commandList.ptr_ orelse @panic("Not initialized");
        command_list.open();

        render_log.instance.startFrame(command_list);
        render_log.instance.openMainBlock(render_log.MRB_GPU_TIME);
    }

    fn glEndFrame(backend: *RenderBackend) void {
        // for VULKAN only
        // ready to present
        RenderSystem.instance.omit_swap_buffers = false;
        render_log.instance.closeMainBlock(render_log.MRB_GPU_TIME);

        const command_list = backend.commandList.ptr_ orelse @panic("Not initialized");
        command_list.close();

        device_manager.instance().endFrame();
        device_manager.instance().getDevice().executeCommandList(command_list);
        if (backend.taaPass) |taaPass| taaPass.advanceFrame();
    }

    fn resizeImages(
        _: *RenderBackend,
        allocator: Allocator,
    ) DeviceManager.UpdateWindowSizeError!void {
        try device_manager.instance().updateWindowSize(.{
            .width = @intCast(RenderSystem.gl_config.nativeScreenWidth),
            .height = @intCast(RenderSystem.gl_config.nativeScreenHeight),
            .multi_samples = @intCast(RenderSystem.gl_config.multisamples),
        }, allocator);
    }
};
