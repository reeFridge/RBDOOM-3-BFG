//! @exportCVars
const std = @import("std");
const material = @import("material.zig");
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
const globalPointToLocal = @import("interaction.zig").globalPointToLocal;

const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;
const CFlags = cvar.CVarFlags;

const r_offset_factor = 0;
const r_offset_units = -600;
pub var r_vk_upload_buffer_size_mb = CVar.init(
    "r_vkUploadBufferSizeMB",
    "64",
    CFlags.integer | CFlags.init | CFlags.new,
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

const TriIndex = @import("../sys/types.zig").TriIndex;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const BindingLayoutType = @import("common.zig").BindingLayoutType;
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
    binding_sets: idlib.List(nvrhi.BindingSetHandle),
    hash: idlib.HashIndex,
    mutex: idlib.SysMutex,

    fn init(binding_cache: *BindingCache, device: *nvrhi.IDevice) void {
        binding_cache.hash = .{};
        binding_cache.device = device;
    }

    fn clear(binding_cache: *BindingCache, allocator: Allocator) void {
        _ = binding_cache.mutex.lockBlocking();
        defer binding_cache.mutex.unlock();

        for (binding_cache.binding_sets.slice()) |*binding_set| {
            _ = binding_set.reset();
        }

        binding_cache.binding_sets.clear(allocator);
        binding_cache.hash.clear();
    }

    pub fn getOrCreateBindingSet(
        binding_cache: *BindingCache,
        desc: *const nvrhi.BindingSetDesc,
        layout: *nvrhi.IBindingLayout,
        allocator: Allocator,
    ) Allocator.Error!nvrhi.BindingSetHandle {
        var hash: usize = 0;
        desc.hashCombine(&hash);
        nvrhi.hashCombine_ptr(&hash, @ptrCast(layout));

        const hash_u16: u16 = @truncate(hash);

        var result: nvrhi.BindingSetHandle = .{};
        {
            _ = binding_cache.mutex.lockBlocking();
            defer binding_cache.mutex.unlock();

            const binding_sets = binding_cache.binding_sets.constSlice();
            var i = binding_cache.hash.first(hash_u16);
            while (i != -1) : (i = binding_cache.hash.next(@intCast(i))) {
                const binding_set = binding_sets[@intCast(i)].ptr_.?;
                if (binding_set.getDesc().eql(desc)) {
                    result = nvrhi.BindingSetHandle.init(binding_set);
                    break;
                }
            }
        }

        if (result.ptr_ == null) {
            _ = binding_cache.mutex.lockBlocking();
            defer binding_cache.mutex.unlock();

            const device = binding_cache.device orelse @panic("device is not set");
            result = device.createBindingSet(desc, layout);

            const entry_index = try binding_cache.binding_sets.append(result, allocator);
            try binding_cache.hash.add(
                hash_u16,
                @intCast(entry_index),
                allocator,
            );
        }

        return result;
    }
};

pub const SamplerCache = extern struct {
    device: ?*nvrhi.IDevice,
    samplers: idlib.List(nvrhi.SamplerHandle),
    hash: idlib.HashIndex,
    mutex: idlib.SysMutex,

    fn init(sampler_cache: *SamplerCache, device: *nvrhi.IDevice) void {
        sampler_cache.hash = .{};
        sampler_cache.device = device;
    }

    fn clear(sampler_cache: *SamplerCache, allocator: Allocator) void {
        _ = sampler_cache.mutex.lockBlocking();
        defer sampler_cache.mutex.unlock();

        sampler_cache.samplers.clear(allocator);
        sampler_cache.hash.clear();
    }

    pub fn getOrCreateSampler(
        sampler_cache: *SamplerCache,
        desc: *const nvrhi.SamplerDesc,
        allocator: Allocator,
    ) Allocator.Error!nvrhi.SamplerHandle {
        var hash: usize = 0;
        desc.hashCombine(&hash);

        const hash_u16: u16 = @truncate(hash);

        var result: nvrhi.SamplerHandle = .{};
        {
            _ = sampler_cache.mutex.lockBlocking();
            defer sampler_cache.mutex.unlock();

            const samplers = sampler_cache.samplers.constSlice();
            var i = sampler_cache.hash.first(hash_u16);
            while (i != -1) : (i = sampler_cache.hash.next(@intCast(i))) {
                const sampler = samplers[@intCast(i)].ptr_.?;
                if (std.meta.eql(sampler.getDesc().*, desc.*)) {
                    result = nvrhi.SamplerHandle.init(sampler);
                    break;
                }
            }
        }

        if (result.ptr_ == null) {
            _ = sampler_cache.mutex.lockBlocking();
            defer sampler_cache.mutex.unlock();

            const device = sampler_cache.device orelse @panic("device is not set");
            result = device.createSampler(desc);

            const entry_index = try sampler_cache.samplers.append(result, allocator);
            try sampler_cache.hash.add(
                hash_u16,
                @intCast(entry_index),
                allocator,
            );
        }

        return result;
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
        depth_bias: c_int,
        slope_bias: f32,
        framebuffer: ?*Framebuffer,
    };

    device: nvrhi.DeviceHandle,
    hash: idlib.HashIndex,
    pipelines: idlib.List(CppStdPair(PipelineKey, nvrhi.GraphicsPipelineHandle)),

    fn init(pipeline_cache: *PipelineCache, device: *nvrhi.IDevice) void {
        pipeline_cache.hash = .{};
        pipeline_cache.device = nvrhi.DeviceHandle.init(device);
    }

    fn shutdown(pipeline_cache: *PipelineCache) void {
        pipeline_cache.device.deinit();
    }

    fn clear(pipeline_cache: *PipelineCache, allocator: Allocator) void {
        pipeline_cache.hash.clear();
        pipeline_cache.pipelines.clear(allocator);
    }

    pub fn getOrCreatePipeline(
        pipeline_cache: *PipelineCache,
        key: *const PipelineKey,
        prog_manager: *const RenderProgManager,
        allocator: Allocator,
    ) Allocator.Error!nvrhi.GraphicsPipelineHandle {
        var hash: usize = 0;
        nvrhi.hashCombine_u64(&hash, key.state);
        nvrhi.hashCombine_int(&hash, key.program);
        nvrhi.hashCombine_ptr(&hash, @ptrCast(key.framebuffer));
        nvrhi.hashCombine_int(&hash, key.depth_bias);
        nvrhi.hashCombine_float(&hash, key.slope_bias);

        const hash_u16: u16 = @truncate(hash);

        const pipelines = pipeline_cache.pipelines.constSlice();
        var i = pipeline_cache.hash.first(hash_u16);
        while (i != -1) : (i = pipeline_cache.hash.next(@intCast(i))) {
            if (std.meta.eql(pipelines[@intCast(i)].first, key.*)) {
                return nvrhi.GraphicsPipelineHandle.init(
                    pipelines[@intCast(i)].second.ptr_,
                );
            }
        }

        var program_info = prog_manager.getProgramInfo(@intCast(key.program));
        var pipeline_desc = nvrhi.GraphicsPipelineDesc{
            .VS = program_info.vertex_shader,
            .PS = program_info.pixel_shader,
            .inputLayout = program_info.input_layout,
            .primType = .TriangleList,
            .renderState = .{
                .rasterState = .{
                    .scissorEnable = true,
                },
                .depthStencilState = .{
                    .depthTestEnable = true,
                    .depthWriteEnable = true,
                },
                .blendState = .{},
            },
        };

        for (program_info.binding_layouts.constSlice()) |binding_layout| {
            pipeline_desc.bindingLayouts.pushBack(binding_layout);
        }

        for (&pipeline_desc.renderState.blendState.targets) |*target| {
            target.blendEnable = true;
        }

        getRenderState(key.state, key.*, &pipeline_desc.renderState);

        const device = pipeline_cache.device.ptr_ orelse @panic("device is not set");
        const pipeline = device.createGraphicsPipeline(
            &pipeline_desc,
            key.framebuffer.?.getApiObject(),
        );

        const entry_index = try pipeline_cache.pipelines.append(
            .{ .first = key.*, .second = pipeline },
            allocator,
        );
        try pipeline_cache.hash.add(
            hash_u16,
            @intCast(entry_index),
            allocator,
        );

        return pipeline;
    }

    extern fn c_getRenderState(u64, PipelineKey, *nvrhi.RenderState) void;
    fn getRenderState(state_bits: u64, key: PipelineKey, render_state: *nvrhi.RenderState) void {
        c_getRenderState(state_bits, key, render_state);
    }
};

const NvrhiContext = extern struct {
    const MAX_IMAGE_PARAMS = 16;

    current_image_param: c_int = 0,
    image_params: [MAX_IMAGE_PARAMS]?*Image.Image,
    scissor: ScreenRect,

    pub fn eql(ctx: *const NvrhiContext, other: *const NvrhiContext) bool {
        if (ctx == other) return true;
        if (ctx.current_image_param != other.current_image_param) return false;
        if (std.meta.eql(ctx.scissor, other.scissor)) return false;

        for (&ctx.image_params, &other.image_params) |ctx_img, other_img| {
            if (ctx_img != other_img) return false;
        }

        return true;
    }
};

const nvrhi_context = @extern(*NvrhiContext, .{ .name = "context" });
const prev_nvrhi_context = @extern(*NvrhiContext, .{ .name = "prevContext" });

pub const RenderBackend = extern struct {
    pc: BackendCounters,
    unitSquareSurface: DrawSurface,
    zeroOneCubeSurface: DrawSurface,
    zeroOneSphereSurface: DrawSurface,
    testImageSurface: DrawSurface,
    slope_scale_bias: f32,
    depth_bias: f32,
    gl_state_bits: u64,
    view_def: ?*const ViewDef,
    current_space: ?*const ViewEntity,
    current_scissor: ScreenRect,
    currentRenderCopied: bool,
    prevMVP: [2]RenderMatrix,
    prevViewsValid: bool,
    hdrAverageLuminance: f32,
    hdrMaxLuminance: f32,
    hdrTime: f32,
    hdrKey: f32,
    // quad-tree for managing tiles within tiled shadow map
    tileMap: TileMap,
    state_viewport: ScreenRect,
    state_scissor: ScreenRect,
    current_viewport: ScreenRect,
    current_vertex_buffer: nvrhi.BufferHandle,
    current_vertex_offset: u32,
    current_index_buffer: nvrhi.BufferHandle,
    current_index_offset: u32,
    current_binding_layout: nvrhi.BindingLayoutHandle,
    current_joint_buffer: ?*nvrhi.IBuffer,
    current_joint_offset: u32,
    current_pipeline: nvrhi.GraphicsPipelineHandle,
    current_binding_sets: idlib.StaticList(nvrhi.BindingSetHandle, nvrhi.c_MaxBindingLayouts),
    pending_binding_sets: idlib.StaticList(
        idlib.StaticList(nvrhi.BindingSetDesc, nvrhi.c_MaxBindingLayouts),
        BindingLayoutType.num,
    ),
    current_framebuffer: *Framebuffer,
    last_framebuffer: *Framebuffer,
    command_list: nvrhi.CommandListHandle,
    common_passes: Pass.CommonRenderPasses,
    ssaoPass: ?*Pass.SsaoPass,
    hiZGenPass: ?*Pass.MipMapGenPass,
    toneMapPass: ?*Pass.TonemapPass,
    taaPass: ?*Pass.TemporalAntiAliasingPass,
    binding_cache: BindingCache,
    sampler_cache: SamplerCache,
    pipeline_cache: PipelineCache,
    inputLayout: nvrhi.InputLayoutHandle,
    vertexShader: nvrhi.ShaderHandle,
    pixelShader: nvrhi.ShaderHandle,
    prev_binding_layout_type: c_int,

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
        backend.pipeline_cache.shutdown();
        backend.common_passes.shutdown();

        for (backend.current_binding_sets.slice()) |*binding_set| {
            _ = binding_set.reset();
        }

        render_prog_manager.instance.shutdown();
        render_log.instance.shutdown();
        _ = backend.command_list.reset();
        ImmediateMode.shutdown();
        VKimp_Shutdown(true);

        device_manager.deinit();
    }

    pub fn clearCaches(backend: *RenderBackend, allocator: Allocator) void {
        backend.pipeline_cache.clear(allocator);
        backend.binding_cache.clear(allocator);
        backend.sampler_cache.clear(allocator);

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

        backend.current_vertex_buffer.deinit();
        backend.current_index_buffer.deinit();
        backend.current_joint_buffer = null;
        backend.current_index_offset = std.math.maxInt(c_uint);
        backend.current_vertex_offset = std.math.maxInt(c_uint);
        backend.current_binding_layout.deinit();
        backend.current_pipeline.deinit();
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

        backend.binding_cache.init(device);
        backend.sampler_cache.init(device);
        backend.pipeline_cache.init(device);
        try backend.common_passes.init(device, render_prog_manager.instance, allocator);
        backend.hiZGenPass = null;
        backend.ssaoPass = null;
        backend.toneMapPass = null;
        backend.taaPass = null;

        RenderSystem.instance.backend_initialized = true;

        const command_list_ptr = if (backend.command_list.ptr_) |ptr|
            ptr
        else command_list: {
            const mb: u32 = @intCast(r_vk_upload_buffer_size_mb.integer_value);
            const handle = device.createCommandList(.{
                // if api == VULKAN
                .uploadChunkSize = mb * 1024 * 1024,
            });
            backend.command_list = handle;

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
        backend.slope_scale_bias = 0;
        backend.depth_bias = 0;

        backend.current_binding_sets.setNum(backend.current_binding_sets.max());
        backend.pending_binding_sets.setNum(backend.pending_binding_sets.max());

        backend.prevMVP[0] = RenderMatrixIdentity;
        backend.prevMVP[1] = RenderMatrixIdentity;
        backend.prevViewsValid = false;

        backend.current_vertex_buffer = .{};
        backend.current_index_buffer = .{};
        backend.current_joint_buffer = null;
        backend.current_vertex_offset = 0;
        backend.current_index_offset = 0;
        backend.current_joint_offset = 0;
        backend.prev_binding_layout_type = -1;

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

        if (cmd_head.command_id == .nop and cmd_head.next == null) return;

        if (RenderSystem.gl_config.stereo3Dmode != .OFF) {
            backend.stereoRenderExecuteBackendCommands(cmd_head);
            return;
        }

        try backend.glStartFrame();
        const global_images = image_manager.instance;

        const texture_id = global_images.hierarchicalZBufferImage.?.getTextureID();

        // RB: we need to load all images left before rendering
        // this can be expensive here because of the runtime image compression
        // image_manager.instance.loadDeferredImages(backend.command_list.ptr_);
        const device_manager_instance = device_manager.instance();
        _ = device_manager_instance.getDevice();

        if (backend.ssaoPass == null) {
            //backend.ssaoPass = Pass.SsaoPass.create(
            //    device,
            //    &backend.common_passes,
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
            //    .max,
            //);
        }

        if (backend.toneMapPass == null) {
            //const pass = Pass.TonemapPass.create();
            //pass.init(
            //    device,
            //    &backend.common_passes,
            //    .{},
            //    global_framebuffers.ldrFBO.getApiObject(),
            //);
            //backend.toneMapPass = pass;
        }

        if (backend.taaPass == null) {
            //const pass = Pass.TemporalAntiAliasingPass.create();
            //pass.init(
            //    device,
            //    &backend.common_passes,
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
            switch (cmd.command_id) {
                .nop => {},
                .draw_view_gui => {
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
                .draw_view_3d => {
                    draw_view_3d = true;
                    try backend.drawView(@ptrCast(cmd), 0, allocator);
                },
                .set_buffer => {
                    backend.setBuffer(@ptrCast(cmd));
                },
                .copy_render => {
                    backend.copyRender(@ptrCast(cmd));
                },
                .post_process => {
                    backend.postProcess(@ptrCast(cmd));
                },
                .crt_post_process => {
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
        const view_def = cmd.view_def orelse return;
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

        // common
        {
            backend.resetViewportAndScissorToDefaultCamera(view_def);
            setCommonShaderVars(view_def);
        }

        if (view_def.viewEntitys != null) {
            try backend.drawView3d(view_def, stereo_eye, allocator);
        } else {
            try backend.drawViewGui(view_def, stereo_eye, allocator);
        }
    }

    fn resetViewportAndScissorToDefaultCamera(backend: *RenderBackend, view_def: *const ViewDef) void {
        {
            // set the window clipping
            const x: f32 = @floatFromInt(view_def.viewport.x1);
            const y: f32 = @floatFromInt(view_def.viewport.y1);
            const w: f32 = @floatFromInt(view_def.viewport.x2 + 1 - view_def.viewport.x1);
            const h: f32 = @floatFromInt(view_def.viewport.y2 + 1 - view_def.viewport.y1);
            backend.current_viewport.clear();
            backend.current_viewport.addPoint(x, y);
            backend.current_viewport.addPoint(x + w, y + h);
        }

        {
            // the scissor may be smaller than the viewport for subviews
            const x: u32 = @intCast(backend.view_def.?.viewport.x1 + view_def.scissor.x1);
            const y: u32 = @intCast(backend.view_def.?.viewport.y2 - view_def.scissor.y2);
            const w: u32 = @intCast(view_def.scissor.x2 + 1 - view_def.scissor.x1);
            const h: u32 = @intCast(view_def.scissor.y2 + 1 - view_def.scissor.y1);
            backend.glScissor(x, y, w, h);

            backend.current_scissor = backend.view_def.?.scissor;
        }
    }

    fn setCommonShaderVars(view_def: *ViewDef) void {
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
        render_prog_manager.instance.setUniformValues(
            .projmatrix_x,
            4,
            &projection_matrix.transpose().m,
        );
    }

    fn drawView3d(
        backend: *RenderBackend,
        view_def: *ViewDef,
        stereo_eye: i32,
        allocator: Allocator,
    ) Allocator.Error!void {
        _ = backend;
        _ = view_def;
        _ = stereo_eye;
        _ = allocator;

        // fillDepthBufferFast
        // ambientPass
        // ssao
        // ambientPass
        // shadowAtlasPass
        // drawInteractions
        // drawShaderPasses
        // fogAllLights
        // postProcess -> drawShaderPasses
        // motionVectors
        // temporalAAPass or msaa
        // blitTexture
        @panic("not implemented");
    }

    fn drawViewGui(
        backend: *RenderBackend,
        view_def: *ViewDef,
        _: i32,
        allocator: Allocator,
    ) Allocator.Error!void {
        const command_list = backend.command_list.ptr_ orelse @panic("command_list not set");

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

        try backend.drawShaderPasses(
            command_list,
            view_def.drawSurfs.?[0..view_def.numDrawSurfs],
            allocator,
        );

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

            try backend.common_passes.blitTexture(
                command_list,
                blit_params,
                &backend.binding_cache,
                allocator,
            );
        }
    }

    const zero: [4]f32 = .{ 0, 0, 0, 0 };
    const one: [4]f32 = .{ 1, 1, 1, 1 };
    const neg_one: [4]f32 = .{ -1, -1, -1, -1 };

    fn drawShaderPasses(
        backend: *RenderBackend,
        command_list: *nvrhi.ICommandList,
        draw_surfaces: []*const DrawSurface,
        allocator: Allocator,
    ) Allocator.Error!void {
        const prog_manager = render_prog_manager.instance;

        // select texture
        nvrhi_context.current_image_param = 0;
        defer {
            prog_manager.setUniformValue(.color, &one);
            backend.glSetState(gl_state.GLS_DEFAULT);
            nvrhi_context.current_image_param = 0;
        }

        for (draw_surfaces) |draw_surface| {
            const cull_mode = gl_state.GLS_CULL_TWOSIDED;
            const surface_gl_state = draw_surface.extraGLState | cull_mode;
            const shader = draw_surface.material orelse continue;
            const regs = draw_surface.shaderRegisters;

            const current_space = if (draw_surface.space != backend.current_space) current_space: {
                backend.current_space = draw_surface.space;

                const space = backend.current_space.?;

                // set eye position in local space
                {
                    const local_view_origin = globalPointToLocal(
                        &space.modelMatrix,
                        backend.view_def.?.renderView.view_origin.toVec3f(),
                    );
                    prog_manager.setUniformValue(.localvieworigin, &.{
                        local_view_origin.v[0],
                        local_view_origin.v[1],
                        local_view_origin.v[2],
                        1,
                    });
                }

                // set model-view-porjection matrix
                prog_manager.setUniformValues(.mvpmatrix_x, 4, &space.mvp.m);

                // set model matrix
                {
                    const model_matrix: *const RenderMatrix = @ptrCast(&space.modelMatrix);
                    prog_manager.setUniformValues(
                        .modelmatrix_x,
                        4,
                        &model_matrix.transpose().m,
                    );
                }

                // set model-view matrix
                {
                    const model_view_matrix: *const RenderMatrix = @ptrCast(&space.modelViewMatrix);
                    prog_manager.setUniformValues(
                        .modelviewmatrix_x,
                        4,
                        &model_view_matrix.transpose().m,
                    );
                }

                break :current_space space;
            } else backend.current_space.?;

            for (shader.getStages()) |stage| {
                var stage_gl_state = surface_gl_state;
                if ((surface_gl_state & gl_state.GLS_OVERRIDE) == 0) {
                    stage_gl_state |= stage.draw_state_bits;
                }

                if (stage.new_stage) |new_stage| {
                    prog_manager.bindProgramIndex(
                        @intCast(new_stage.program),
                    );
                    defer {
                        nvrhi_context.current_image_param = 0;
                        prog_manager.unbind();
                    }

                    for (new_stage.fragment_program_images[0..new_stage.num_fragment_program_images], 0..) |opt_image, texture_index| {
                        if (opt_image) |image| {
                            nvrhi_context.current_image_param = @intCast(texture_index);
                            try setCurrentImage(image, command_list, allocator);
                        }
                    }

                    try backend.drawElements(command_list, draw_surface, allocator);
                } else {
                    const color: [4]f32 = .{
                        regs[stage.color.registers[0]],
                        regs[stage.color.registers[1]],
                        regs[stage.color.registers[2]],
                        regs[stage.color.registers[3]],
                    };

                    prog_manager.setUniformValue(.color, &color);
                    var stage_vertex_color = stage.vertex_color;

                    if (current_space.isGuiSurface) {
                        stage_vertex_color = .modulate;
                    }

                    prog_manager.bindProgramBuiltin(
                        .TEXTURE_VERTEXCOLOR_SRGB,
                    );

                    switch (stage_vertex_color) {
                        .ignore => {
                            prog_manager.setUniformValue(.vertexcolor_modulate, &zero);
                            prog_manager.setUniformValue(.vertexcolor_add, &one);
                        },
                        .modulate => {
                            prog_manager.setUniformValue(.vertexcolor_modulate, &one);
                            prog_manager.setUniformValue(.vertexcolor_add, &zero);
                        },
                        .inverse_modulate => {
                            prog_manager.setUniformValue(.vertexcolor_modulate, &neg_one);
                            prog_manager.setUniformValue(.vertexcolor_add, &one);
                        },
                    }

                    try bindVariableStageImage(&stage.texture, command_list, allocator);

                    if (stage.private_polygon_offset != 0) {
                        backend.slope_scale_bias = r_offset_factor;
                        backend.depth_bias = r_offset_units * stage.private_polygon_offset;
                        stage_gl_state |= gl_state.GLS_POLYGON_OFFSET;
                    }

                    backend.glSetState(stage_gl_state);

                    // TODO: texgen
                    {
                        const use_tex_gen_param: [4]f32 = .{ 0, 0, 0, 0 };
                        const tex_s: [4]f32 = .{ 1, 0, 0, 0 };
                        const tex_t: [4]f32 = .{ 0, 1, 0, 0 };

                        prog_manager.setUniformValue(.texturematrix_s, &tex_s);
                        prog_manager.setUniformValue(.texturematrix_t, &tex_t);
                        prog_manager.setUniformValue(.texgen_0_enabled, &use_tex_gen_param);
                    }

                    try backend.drawElements(command_list, draw_surface, allocator);

                    // reset polygon offset
                    if (stage.private_polygon_offset != 0) {
                        backend.slope_scale_bias = r_offset_factor;
                        backend.depth_bias = r_offset_units * shader.polygon_offset;
                    }
                }
            }
        }
    }

    fn bindVariableStageImage(
        texture_stage: *const material.TextureStage,
        command_list: *nvrhi.ICommandList,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (texture_stage.cinematic) |_| {
            @panic("not implemented");
        } else {
            if (texture_stage.image) |image| {
                try setCurrentImage(image, command_list, allocator);
            }
        }
    }

    fn drawElements(
        backend: *RenderBackend,
        command_list: *nvrhi.ICommandList,
        surface: *const DrawSurface,
        allocator: Allocator,
    ) Allocator.Error!void {
        const use_state_caching = true;
        var change_state = false;

        // set vertex_buffer
        {
            const vertex_buffer_handle = surface.ambientCache;
            const vertex_buffer = if (vertex_buffer_handle.static)
                &vertex_cache.instance.static_data.vertex_buffer
            else vertex_buffer: {
                const frame_num = vertex_buffer_handle.frame;
                if (frame_num != ((vertex_cache.instance.current_frame - 1) & vertex_cache.frame_mask)) {
                    @panic("[VERTEX_CACHE] vertex_buffer is null");
                }

                break :vertex_buffer &vertex_cache.instance.frame_data[vertex_cache.instance.draw_list_num].vertex_buffer;
            };

            if (backend.current_vertex_offset != vertex_buffer_handle.offset) {
                backend.current_vertex_offset = vertex_buffer_handle.offset;
            }

            if (backend.current_vertex_buffer.ptr_ != vertex_buffer.getApiObject() or
                !use_state_caching)
            {
                backend.current_vertex_buffer.ptr_ = vertex_buffer.getApiObject();
                change_state = true;
            }
        }

        // set index_buffer
        {
            const index_buffer_handle = surface.indexCache;
            const index_buffer = if (index_buffer_handle.static)
                &vertex_cache.instance.static_data.index_buffer
            else index_buffer: {
                const frame_num = index_buffer_handle.frame;
                if (frame_num != ((vertex_cache.instance.current_frame - 1) & vertex_cache.frame_mask)) {
                    @panic("[VERTEX_CACHE] index_buffer is null");
                }

                break :index_buffer &vertex_cache.instance.frame_data[vertex_cache.instance.draw_list_num].index_buffer;
            };

            if (backend.current_index_offset != index_buffer_handle.offset) {
                backend.current_index_offset = index_buffer_handle.offset;
            }

            if (backend.current_index_buffer.ptr_ != index_buffer.getApiObject() or
                !use_state_caching)
            {
                backend.current_index_buffer.ptr_ = index_buffer.getApiObject();
                change_state = true;
            }
        }

        // set joint_buffer
        {
            const joint_buffer_handle = surface.jointCache;
            backend.current_joint_buffer = null;
            backend.current_joint_offset = 0;

            if (joint_buffer_handle.isDefined()) {
                const joint_buffer = if (joint_buffer_handle.static)
                    &vertex_cache.instance.static_data.joint_buffer
                else joint_buffer: {
                    const frame_num = joint_buffer_handle.frame;
                    if (frame_num != ((vertex_cache.instance.current_frame - 1) & vertex_cache.frame_mask)) {
                        @panic("[VERTEX_CACHE] joint_buffer is null");
                    }

                    break :joint_buffer &vertex_cache.instance.frame_data[vertex_cache.instance.draw_list_num].joint_buffer;
                };

                if (backend.current_joint_buffer != joint_buffer.getApiObject() or
                    backend.current_joint_offset != joint_buffer_handle.offset)
                {
                    change_state = true;
                }

                backend.current_joint_buffer = joint_buffer.getApiObject();
                backend.current_joint_offset = joint_buffer_handle.offset;
            }
        }

        const prog_manager = render_prog_manager.instance;
        const program = prog_manager.getCurrentProgram() orelse @panic("no current program");
        const binding_layout_type = program.binding_layout_type;
        const layouts = prog_manager.bindingLayouts.constSlice()[binding_layout_type.toIndex()].constSlice();

        if (change_state or
            @intFromEnum(binding_layout_type) != backend.prev_binding_layout_type or
            !nvrhi_context.eql(prev_nvrhi_context))
        {
            try backend.setupPendingBindingLayout(
                prog_manager,
                binding_layout_type,
                allocator,
            );

            for (layouts, 0..) |*layout, i| {
                const current_binding_set = &backend.current_binding_sets.slice()[i];
                const pending_binding_set_descs = backend.pending_binding_sets.constSlice();
                const binding_set_desc = &pending_binding_set_descs[binding_layout_type.toIndex()].constSlice()[i];
                if (current_binding_set.ptr_ == null or
                    !current_binding_set.ptr_.?.getDesc().eql(binding_set_desc))
                {
                    current_binding_set.* = try backend.binding_cache.getOrCreateBindingSet(
                        binding_set_desc,
                        layout.ptr_.?,
                        allocator,
                    );

                    change_state = true;
                }
            }
        }

        var pipeline = pipeline: {
            const key = PipelineCache.PipelineKey{
                .state = backend.gl_state_bits,
                .program = prog_manager.currentIndex,
                .depth_bias = @intFromFloat(backend.depth_bias),
                .slope_bias = backend.slope_scale_bias,
                .framebuffer = backend.current_framebuffer,
            };

            const pipeline = try backend.pipeline_cache.getOrCreatePipeline(
                &key,
                prog_manager,
                allocator,
            );

            if (backend.current_pipeline.ptr_ != pipeline.ptr_) {
                backend.current_pipeline = nvrhi.GraphicsPipelineHandle.init(pipeline.ptr_);
                change_state = true;
            }

            break :pipeline pipeline;
        };
        defer pipeline.deinit();

        if (!std.meta.eql(backend.current_viewport, backend.state_viewport)) {
            backend.state_viewport = backend.current_viewport;
            change_state = true;
        }

        if (!std.meta.eql(nvrhi_context.scissor, backend.state_scissor)) {
            backend.state_scissor = nvrhi_context.scissor;
        }

        if (prog_manager.commitConstantBuffer(
            command_list,
            @intFromEnum(binding_layout_type) != backend.prev_binding_layout_type,
        )) {
            const api = nvrhi.GraphicsAPI.VULKAN;
            if (api == .VULKAN) {
                change_state = true;
            }
        }

        if (change_state) {
            const VertexBuffers = std.meta.FieldType(
                nvrhi.GraphicsState,
                .vertexBuffers,
            );
            var state: nvrhi.GraphicsState = .{
                .pipeline = pipeline.ptr_.?,
                .framebuffer = backend.current_framebuffer.getApiObject(),
                .indexBuffer = .{
                    .buffer = backend.current_index_buffer.ptr_,
                    .format = .R16_UINT,
                    .offset = 0,
                },
                .vertexBuffers = VertexBuffers.fromSlice(&.{
                    .{
                        .buffer = backend.current_vertex_buffer.ptr_,
                        .slot = 0,
                        .offset = 0,
                    },
                }),
            };

            for (layouts, 0..) |_, i| {
                const current_binding_set = backend.current_binding_sets.slice()[i];
                state.bindings.pushBack(current_binding_set.ptr_.?);
            }

            const viewport = nvrhi.Viewport{
                .minX = @floatFromInt(backend.current_viewport.x1),
                .maxX = @floatFromInt(backend.current_viewport.x2),
                .minY = @floatFromInt(backend.current_viewport.y1),
                .maxY = @floatFromInt(backend.current_viewport.y2),
                .minZ = 0,
                .maxZ = 1,
            };

            state.viewport.viewports.pushBack(viewport);

            if (!nvrhi_context.scissor.isEmpty()) {
                state.viewport.scissorRects.pushBack(.{
                    .minX = nvrhi_context.scissor.x1,
                    .maxX = nvrhi_context.scissor.x2,
                    .minY = nvrhi_context.scissor.y1,
                    .maxY = nvrhi_context.scissor.y2,
                });
            } else {
                state.viewport.scissorRects.pushBack(
                    nvrhi.Rect.fromViewport(&viewport),
                );
            }

            command_list.setGraphicsState(&state);
        }

        command_list.drawIndexed(&.{
            .startVertexLocation = backend.current_vertex_offset / @sizeOf(DrawVertex),
            .startIndexLocation = backend.current_index_offset / @sizeOf(TriIndex),
            .vertexCount = surface.numIndexes,
        });

        prev_nvrhi_context.* = nvrhi_context.*;
        backend.prev_binding_layout_type = @intFromEnum(binding_layout_type);
    }

    fn setupPendingBindingLayout(
        backend: *RenderBackend,
        prog_manager: *RenderProgManager,
        layout_type: BindingLayoutType,
        allocator: Allocator,
    ) Allocator.Error!void {
        const pending_binding_set_descs = backend.pending_binding_sets.slice();

        if (pending_binding_set_descs[layout_type.toIndex()].num == 0) {
            pending_binding_set_descs[layout_type.toIndex()].setNum(nvrhi.c_MaxBindingLayouts);
        }

        const descs = pending_binding_set_descs[layout_type.toIndex()].slice();
        const Bindings = std.meta.FieldType(
            nvrhi.BindingSetDesc,
            .bindings,
        );

        const constant_buffer = prog_manager.constant_buffer.ptr_;
        const range = nvrhi.EntireBuffer;

        switch (layout_type) {
            .DEFAULT => {
                if (descs[0].bindings.current_size == 0) {
                    descs[0].bindings = Bindings.fromSlice(&.{
                        nvrhi.BindingSetItem.createConstantBuffer(
                            0,
                            constant_buffer,
                            range,
                        ),
                    });
                } else {
                    const bindings = descs[0].bindings.slice();
                    bindings[0].resourceHandle = @ptrCast(constant_buffer);
                    bindings[0].unnamed_0.range = range;
                }

                if (descs[1].bindings.current_size == 0) {
                    descs[1].bindings = Bindings.fromSlice(&.{
                        nvrhi.BindingSetItem.createTextureSrv(
                            0,
                            nvrhi_context.image_params[0].?.texture.ptr_.?,
                            .UNKNOWN,
                            nvrhi.AllSubresources,
                            .Unknown,
                        ),
                    });
                } else {
                    const bindings = descs[1].bindings.slice();
                    bindings[0].resourceHandle = @ptrCast(nvrhi_context.image_params[0].?.texture.ptr_);
                }

                if (descs[2].bindings.current_size == 0) {
                    descs[2].bindings = Bindings.fromSlice(&.{
                        nvrhi.BindingSetItem.createSampler(
                            0,
                            try nvrhi_context.image_params[0].?.getSampler(
                                &backend.sampler_cache,
                                allocator,
                            ),
                        ),
                    });
                } else {
                    const bindings = descs[2].bindings.slice();
                    bindings[0].resourceHandle = @ptrCast(try nvrhi_context.image_params[0].?.getSampler(
                        &backend.sampler_cache,
                        allocator,
                    ));
                }
            },
            .POST_PROCESS_INGAME => {
                if (descs[0].bindings.current_size == 0) {
                    descs[0].bindings = Bindings.fromSlice(&.{
                        nvrhi.BindingSetItem.createConstantBuffer(
                            0,
                            constant_buffer,
                            range,
                        ),
                        nvrhi.BindingSetItem.createTextureSrv(
                            0,
                            nvrhi_context.image_params[0].?.texture.ptr_.?,
                            .UNKNOWN,
                            nvrhi.AllSubresources,
                            .Unknown,
                        ),
                        nvrhi.BindingSetItem.createTextureSrv(
                            1,
                            nvrhi_context.image_params[1].?.texture.ptr_.?,
                            .UNKNOWN,
                            nvrhi.AllSubresources,
                            .Unknown,
                        ),
                        nvrhi.BindingSetItem.createTextureSrv(
                            2,
                            nvrhi_context.image_params[2].?.texture.ptr_.?,
                            .UNKNOWN,
                            nvrhi.AllSubresources,
                            .Unknown,
                        ),
                    });
                } else {
                    const bindings = descs[0].bindings.slice();
                    bindings[0].resourceHandle = @ptrCast(constant_buffer);
                    bindings[0].unnamed_0.range = range;
                    bindings[1].resourceHandle = @ptrCast(nvrhi_context.image_params[0].?.texture.ptr_);
                    bindings[2].resourceHandle = @ptrCast(nvrhi_context.image_params[1].?.texture.ptr_);
                    bindings[3].resourceHandle = @ptrCast(nvrhi_context.image_params[2].?.texture.ptr_);
                }

                if (descs[1].bindings.current_size == 0) {
                    descs[1].bindings = Bindings.fromSlice(&.{
                        nvrhi.BindingSetItem.createSampler(
                            0,
                            backend.common_passes.linear_clamp_sampler.ptr_.?,
                        ),
                    });
                } else {
                    const bindings = descs[1].bindings.slice();
                    bindings[0].resourceHandle = @ptrCast(backend.common_passes.linear_clamp_sampler.ptr_);
                }
            },
            else => @panic("not implemented"),
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
        const current_fb = backend.current_framebuffer.getApiObject();
        const command_list = backend.command_list.ptr_ orelse @panic("command_list not set");

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
        backend.current_scissor.clear();
        backend.current_scissor.addPoint(0, 0);
        backend.current_scissor.addPoint(
            @floatFromInt(RenderSystem.instance.getWidth()),
            @floatFromInt(RenderSystem.instance.getHeight()),
        );
    }

    fn copyRender(backend: *RenderBackend, data: *anyopaque) void {
        const skip_copy_render = true;
        if (skip_copy_render) return;

        c_renderBackend_copyRender(backend, data);
    }

    fn postProcess(backend: *RenderBackend, data: *anyopaque) void {
        const skip_post_process = true;
        if (skip_post_process) return;

        c_renderBackend_postProcess(backend, data);
    }

    fn crtPostProcess(backend: *RenderBackend) void {
        const skip_post_process = true;
        if (skip_post_process) return;

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
        backend.gl_state_bits = 0;
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
        backend.gl_state_bits = state_bits | (backend.gl_state_bits & gl_state.GLS_KEEP);
        if (backend.view_def) |view_def| {
            if (view_def.isMirror) {
                backend.gl_state_bits |= gl_state.GLS_MIRROR_VIEW;
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

        const command_list = backend.command_list.ptr_ orelse @panic("Not initialized");
        command_list.open();

        render_log.instance.startFrame(command_list);
        render_log.instance.openMainBlock(render_log.MRB_GPU_TIME);
    }

    fn glEndFrame(backend: *RenderBackend) void {
        // for VULKAN only
        // ready to present
        RenderSystem.instance.omit_swap_buffers = false;
        render_log.instance.closeMainBlock(render_log.MRB_GPU_TIME);

        const command_list = backend.command_list.ptr_ orelse @panic("Not initialized");
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

    fn setCurrentImage(
        image: *Image.Image,
        command_list: *nvrhi.ICommandList,
        allocator: Allocator,
    ) Image.Image.ActuallyLoadImageError!void {
        if (!image.is_loaded and !image.defaulted) {
            try image.actuallyLoadImageOrDefault(command_list, allocator);
        }

        nvrhi_context.image_params[@intCast(nvrhi_context.current_image_param)] = image;
    }
};
