const nvrhi = @import("nvrhi.zig");

pub const RenderProgManager = opaque {
    extern fn c_renderProgManager_init(*RenderProgManager, *nvrhi.IDevice) callconv(.C) void;
    extern fn c_renderProgManager_shutdown(*RenderProgManager) callconv(.C) void;
    extern fn c_renderProgManager_unbind(*RenderProgManager) callconv(.C) void;

    pub fn unbind(prog_manager: *RenderProgManager) void {
        c_renderProgManager_unbind(prog_manager);
    }

    pub fn init(prog_manager: *RenderProgManager, device: *nvrhi.IDevice) void {
        c_renderProgManager_init(prog_manager, device);
    }

    pub fn shutdown(prog_manager: *RenderProgManager) void {
        c_renderProgManager_shutdown(prog_manager);
    }
};

pub const instance = @extern(*RenderProgManager, .{ .name = "renderProgManager" });
