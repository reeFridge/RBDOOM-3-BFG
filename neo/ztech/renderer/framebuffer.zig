const std = @import("std");
const idlib = @import("../idlib.zig");
const nvrhi = @import("nvrhi.zig");
const RenderBackend = @import("render_backend.zig").RenderBackend;
const DeviceManager = @import("../sys/device_manager.zig").DeviceManagerVulkan;
const image_manager = @import("image_manager.zig");
const Allocator = std.mem.Allocator;

var framebuffers: idlib.List(*Framebuffer) = .{};

pub const MAX_SHADOWMAP_RESOLUTIONS = 5;
pub const ENVPROBE_CAPTURE_SIZE = 256;
pub const shadow_map_resolutions: [MAX_SHADOWMAP_RESOLUTIONS]u32 = .{ 1024, 512, 256, 256, 128 };

pub const Framebuffer = extern struct {
    vptr: *anyopaque = undefined,
    fboName: idlib.Str = .{},
    frameBuffer: u32 = 0,
    colorBuffers: [16]u32 = std.mem.zeroes([16]u32),
    colorFormat: c_int = 0,
    depthBuffer: u32 = 0,
    depthFormat: c_int = 0,
    stencilBuffer: u32 = 0,
    stencilFormat: c_int = 0,
    width: u32 = 0,
    height: u32 = 0,
    msaaSamples: bool = false,
    apiObject: nvrhi.FramebufferHandle = .{},

    pub fn create(
        allocator: Allocator,
        device: *nvrhi.IDevice,
        name: []const u8,
        desc: *const nvrhi.FramebufferDesc,
    ) Allocator.Error!*Framebuffer {
        var ptr = try allocator.create(Framebuffer);
        ptr.* = .{};

        try ptr.fboName.assignSlice(name, allocator);

        ptr.apiObject = device.createFramebuffer(desc);
        const framebuffer_info = ptr.apiObject.ptr_.?.getFramebufferInfo();
        ptr.width = framebuffer_info.width;
        ptr.height = framebuffer_info.height;

        _ = try framebuffers.append(ptr, allocator);

        return ptr;
    }

    pub fn deinit(framebuffer: *Framebuffer, allocator: Allocator) void {
        framebuffer.fboName.deinit(allocator);
        _ = framebuffer.apiObject.reset();
    }

    pub fn getApiObject(framebuffer: *Framebuffer) *nvrhi.IFramebuffer {
        return framebuffer.apiObject.ptr_ orelse @panic("apiObject is null");
    }

    pub fn bind(framebuffer: *Framebuffer, backend: *RenderBackend) void {
        if (backend.currentFramebuffer != framebuffer) {
            backend.currentPipeline.ptr_ = null;
        }

        backend.lastFramebuffer = backend.currentFramebuffer;
        backend.currentFramebuffer = framebuffer;
    }
};

pub const GlobalFramebuffers = extern struct {
    const MAX_BLOOM_BUFFERS = 2;
    const MAX_GLOW_BUFFERS = 2;
    const MAX_SSAO_BUFFERS = 2;
    const MAX_HIERARCHICAL_ZBUFFERS = 6; // native resolution + 5 MIP LEVELS

    swapFramebuffers: idlib.List(*Framebuffer),
    shadowAtlasFBO: *Framebuffer,
    shadowFBO: [MAX_SHADOWMAP_RESOLUTIONS][6]*Framebuffer,
    hdrFBO: *Framebuffer,
    ldrFBO: *Framebuffer,
    postProcFBO: *Framebuffer, // HDR16 used by 3D effects like heatHaze
    taaMotionVectorsFBO: *Framebuffer,
    taaResolvedFBO: *Framebuffer,
    envprobeFBO: *Framebuffer,
    bloomRenderFBO: [MAX_BLOOM_BUFFERS]*Framebuffer,
    glowFBO: [MAX_GLOW_BUFFERS]*Framebuffer, // unused
    transparencyFBO: *Framebuffer, // unused
    ambientOcclusionFBO: [MAX_SSAO_BUFFERS]*Framebuffer,
    csDepthFBO: [MAX_HIERARCHICAL_ZBUFFERS]*Framebuffer,
    geometryBufferFBO: *Framebuffer,
    smaaEdgesFBO: *Framebuffer,
    smaaBlendFBO: *Framebuffer,
    guiRenderTargetFBO: *Framebuffer,
    accumFBO: *Framebuffer,
};

pub const global_framebuffers = @extern(*GlobalFramebuffers, .{ .name = "globalFramebuffers" });

extern fn c_framebuffer_init() void;
extern fn c_framebuffer_shutdown() void;
extern fn c_framebuffer_checkFramebuffers() void;
extern fn c_framebuffer_unbind() void;
extern fn c_framebuffer_resizeFramebuffers(bool) void;

pub fn resizeFramebuffers(
    backend: *RenderBackend,
    device_manager: *DeviceManager,
    allocator: Allocator,
    reload_images: bool,
) Allocator.Error!void {
    backend.clearCaches(allocator);

    for (framebuffers.slice()) |framebuffer_ptr| {
        framebuffer_ptr.deinit(allocator);
    }
    framebuffers.clear(allocator);

    const device = device_manager.getDevice();

    if (reload_images) {
        try reloadImages(
            device,
            backend.commandList.ptr_.?,
            allocator,
        );
    }

    const back_buffer_count = device_manager.getBackBufferCount();
    try global_framebuffers.swapFramebuffers.resize(back_buffer_count, allocator);
    try global_framebuffers.swapFramebuffers.setNum(back_buffer_count, allocator);

    const Attachments = nvrhi.FramebufferDesc.ColorAttachments;
    const global_images = image_manager.instance;

    var string_buffer: [256]u8 = undefined;

    for (global_framebuffers.swapFramebuffers.slice(), 0..) |*fb, index| {
        fb.* = try Framebuffer.create(
            allocator,
            device,
            std.fmt.bufPrint(&string_buffer, "_swapChain_{}", .{index}) catch unreachable,
            &.{
                .colorAttachments = Attachments.fromSlice(&.{
                    .{ .texture = device_manager.getBackBuffer(index) },
                }),
            },
        );
    }

    for (0..6) |arr| {
        for (0..MAX_SHADOWMAP_RESOLUTIONS) |mip| {
            const texture = global_images.shadowImage[mip].?.texture.ptr_;
            global_framebuffers.shadowFBO[mip][arr] = try Framebuffer.create(
                allocator,
                device,
                std.fmt.bufPrint(&string_buffer, "_shadowMap_{}_{}", .{ mip, arr }) catch unreachable,
                &.{
                    .depthAttachment = .{
                        .texture = texture,
                        .subresources = .{
                            .baseArraySlice = @intCast(arr),
                            .numArraySlices = 1,
                        },
                    },
                },
            );
        }
    }

    global_framebuffers.shadowAtlasFBO = try Framebuffer.create(
        allocator,
        device,
        "_shadowAtlas",
        &.{
            .depthAttachment = .{
                .texture = global_images.shadowAtlasImage.?.texture.ptr_,
            },
        },
    );

    global_framebuffers.ldrFBO = try Framebuffer.create(
        allocator,
        device,
        "_ldr",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.ldrImage.?.texture.ptr_ },
            }),
            .depthAttachment = .{ .texture = global_images.currentDepthImage.?.texture.ptr_ },
        },
    );

    global_framebuffers.hdrFBO = try Framebuffer.create(
        allocator,
        device,
        "_hdr",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.currentRenderHDRImage.?.texture.ptr_ },
            }),
            .depthAttachment = .{ .texture = global_images.currentDepthImage.?.texture.ptr_ },
        },
    );

    global_framebuffers.postProcFBO = try Framebuffer.create(
        allocator,
        device,
        "_postProc",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.currentRenderImage.?.texture.ptr_ },
            }),
        },
    );

    global_framebuffers.taaMotionVectorsFBO = try Framebuffer.create(
        allocator,
        device,
        "_taaMotionVectors",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.taaMotionVectorsImage.?.texture.ptr_ },
            }),
        },
    );

    global_framebuffers.taaResolvedFBO = try Framebuffer.create(
        allocator,
        device,
        "_taaResolved",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.taaResolvedImage.?.texture.ptr_ },
            }),
        },
    );

    global_framebuffers.envprobeFBO = try Framebuffer.create(
        allocator,
        device,
        "_envprobeRender",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.envprobeHDRImage.?.texture.ptr_ },
            }),
            .depthAttachment = .{ .texture = global_images.envprobeDepthImage.?.texture.ptr_ },
        },
    );

    for (
        &global_framebuffers.ambientOcclusionFBO,
        &global_images.ambientOcclusionImage,
        0..,
    ) |*fb, image_ptr, index| {
        fb.* = try Framebuffer.create(
            allocator,
            device,
            std.fmt.bufPrint(&string_buffer, "_aoRender_{}", .{index}) catch unreachable,
            &.{
                .colorAttachments = Attachments.fromSlice(&.{
                    .{ .texture = image_ptr.?.texture.ptr_ },
                }),
            },
        );
    }

    for (&global_framebuffers.csDepthFBO, 0..) |*fb, i| {
        fb.* = try Framebuffer.create(
            allocator,
            device,
            std.fmt.bufPrint(&string_buffer, "_csz_{}", .{i}) catch unreachable,
            &.{
                .colorAttachments = Attachments.fromSlice(&.{
                    .{
                        .texture = global_images.hierarchicalZBufferImage.?.texture.ptr_,
                        .subresources = .{
                            .baseMipLevel = @intCast(i),
                            .numMipLevels = 1,
                        },
                    },
                }),
            },
        );
    }

    global_framebuffers.geometryBufferFBO = try Framebuffer.create(
        allocator,
        device,
        "_gbuffer",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.gbufferNormalsRoughnessImage.?.texture.ptr_ },
            }),
            .depthAttachment = .{ .texture = global_images.currentDepthImage.?.texture.ptr_ },
        },
    );

    global_framebuffers.smaaEdgesFBO = try Framebuffer.create(
        allocator,
        device,
        "_smaaEdges",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.smaaEdgesImage.?.texture.ptr_ },
            }),
        },
    );

    global_framebuffers.smaaBlendFBO = try Framebuffer.create(
        allocator,
        device,
        "_smaaBlend",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.smaaBlendImage.?.texture.ptr_ },
            }),
        },
    );

    for (
        &global_framebuffers.bloomRenderFBO,
        &global_images.bloomRenderImage,
        0..,
    ) |*fb, image_ptr, i| {
        fb.* = try Framebuffer.create(
            allocator,
            device,
            std.fmt.bufPrint(&string_buffer, "_bloomRender_{}", .{i}) catch unreachable,
            &.{
                .colorAttachments = Attachments.fromSlice(&.{
                    .{ .texture = image_ptr.?.texture.ptr_ },
                }),
            },
        );
    }

    global_framebuffers.geometryBufferFBO = try Framebuffer.create(
        allocator,
        device,
        "_guiEdit",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.guiEdit.?.texture.ptr_ },
            }),
            .depthAttachment = .{ .texture = global_images.guiEditDepthStencilImage.?.texture.ptr_ },
        },
    );

    global_framebuffers.accumFBO = try Framebuffer.create(
        allocator,
        device,
        "_accum",
        &.{
            .colorAttachments = Attachments.fromSlice(&.{
                .{ .texture = global_images.accumImage.?.texture.ptr_ },
            }),
        },
    );

    unbind(backend, device_manager);
}

pub fn init(
    backend: *RenderBackend,
    device_manager: *DeviceManager,
    allocator: Allocator,
) Allocator.Error!void {
    try resizeFramebuffers(backend, device_manager, allocator, true);
}

fn reloadImages(
    device: *nvrhi.IDevice,
    command_list: *nvrhi.ICommandList,
    allocator: Allocator,
) Allocator.Error!void {
    const global_images = image_manager.instance;

    command_list.open();

    try global_images.ldrImage.?.reload(false, command_list, allocator);
    try global_images.currentRenderImage.?.reload(false, command_list, allocator);
    try global_images.currentDepthImage.?.reload(false, command_list, allocator);
    try global_images.currentRenderHDRImage.?.reload(false, command_list, allocator);

    for (&global_images.ambientOcclusionImage) |image_ptr| {
        try image_ptr.?.reload(false, command_list, allocator);
    }

    try global_images.hierarchicalZBufferImage.?.reload(false, command_list, allocator);
    try global_images.gbufferNormalsRoughnessImage.?.reload(false, command_list, allocator);
    try global_images.taaMotionVectorsImage.?.reload(false, command_list, allocator);
    try global_images.taaResolvedImage.?.reload(false, command_list, allocator);
    try global_images.envprobeHDRImage.?.reload(false, command_list, allocator);
    try global_images.envprobeDepthImage.?.reload(false, command_list, allocator);
    try global_images.taaFeedback1Image.?.reload(false, command_list, allocator);
    try global_images.taaFeedback2Image.?.reload(false, command_list, allocator);
    try global_images.smaaEdgesImage.?.reload(false, command_list, allocator);
    try global_images.smaaBlendImage.?.reload(false, command_list, allocator);
    try global_images.shadowAtlasImage.?.reload(false, command_list, allocator);

    for (&global_images.shadowImage) |image_ptr| {
        try image_ptr.?.reload(false, command_list, allocator);
    }

    for (&global_images.bloomRenderImage) |image_ptr| {
        try image_ptr.?.reload(false, command_list, allocator);
    }

    try global_images.guiEdit.?.reload(false, command_list, allocator);
    try global_images.guiEditDepthStencilImage.?.reload(false, command_list, allocator);
    try global_images.accumImage.?.reload(false, command_list, allocator);

    command_list.close();
    device.executeCommandList(command_list);
}

pub fn shutdown(allocator: Allocator) void {
    for (framebuffers.slice()) |framebuffer_ptr| {
        framebuffer_ptr.deinit(allocator);
    }
    framebuffers.clear(allocator);
}

pub fn unbind(backend: *RenderBackend, device_manager: *const DeviceManager) void {
    const swap = global_framebuffers.swapFramebuffers.slice();
    swap[device_manager.getCurrentBackBufferIndex()].bind(backend);
}
