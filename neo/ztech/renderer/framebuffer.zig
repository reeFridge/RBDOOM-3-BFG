const idList = @import("../idlib.zig").idList;
const nvrhi = @import("nvrhi.zig");

pub const Framebuffer = opaque {
    extern fn c_framebuffer_getApiObject(*Framebuffer) callconv(.C) *nvrhi.IFramebuffer;

    pub fn getApiObject(framebuffer: *Framebuffer) *nvrhi.IFramebuffer {
        return c_framebuffer_getApiObject(framebuffer);
    }
};

pub const GlobalFramebuffers = extern struct {
    const MAX_SHADOWMAP_RESOLUTIONS = 5;
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

extern fn c_framebuffer_init() callconv(.C) void;
extern fn c_framebuffer_shutdown() callconv(.C) void;
extern fn c_framebuffer_checkFramebuffers() callconv(.C) void;
extern fn c_framebuffer_unbind() callconv(.C) void;

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
