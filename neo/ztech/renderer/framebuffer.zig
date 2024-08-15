pub const Framebuffer = opaque {};

extern fn c_framebuffer_init() callconv(.C) void;
extern fn c_framebuffer_shutdown() callconv(.C) void;
extern fn c_framebuffer_checkFramebuffers() callconv(.C) void;

pub fn init() void {
    c_framebuffer_init();
}

pub fn shutdown() void {
    c_framebuffer_shutdown();
}

pub fn checkFramebuffers() void {
    c_framebuffer_checkFramebuffers();
}
