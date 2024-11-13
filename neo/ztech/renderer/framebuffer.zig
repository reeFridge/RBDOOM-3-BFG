const idlib = @import("../idlib.zig");
const idList = idlib.idList;
const nvrhi = @import("nvrhi.zig");

pub const Framebuffer = extern struct {
    vptr: *anyopaque,
    fboName: idlib.idStr,
    frameBuffer: u32,
    colorBuffers: [16]u32,
    colorFormat: c_int,
    depthBuffer: u32,
    depthFormat: c_int,
    stencilBuffer: u32,
    stencilFormat: c_int,
    width: c_int,
    height: c_int,
    msaaSamples: bool,
    apiObject: nvrhi.FramebufferHandle,

    pub fn getApiObject(framebuffer: *Framebuffer) *nvrhi.IFramebuffer {
        return framebuffer.apiObject.ptr_ orelse @panic("apiObject is null");
    }
};

pub const GlobalFramebuffers = extern struct {
    pub const MAX_SHADOWMAP_RESOLUTIONS = 5;
    const MAX_BLOOM_BUFFERS = 2;
    const MAX_GLOW_BUFFERS = 2;
    const MAX_SSAO_BUFFERS = 2;
    const MAX_HIERARCHICAL_ZBUFFERS = 6; // native resolution + 5 MIP LEVELS

    swapFramebuffers: idList(*Framebuffer),
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

pub fn resizeFramebuffers(reload_images: bool) void {
    c_framebuffer_resizeFramebuffers(reload_images);
}

pub fn init() void {
    c_framebuffer_init();
}

pub fn shutdown() void {
    c_framebuffer_shutdown();
}

pub fn checkFramebuffers() void {
    c_framebuffer_checkFramebuffers();
}

pub fn unbind() void {
    c_framebuffer_unbind();
}
