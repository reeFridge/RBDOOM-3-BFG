const CVec4 = @import("../math/vector.zig").CVec4;
const CMat3 = @import("../math/matrix.zig").CMat3;
const GuiModel = @import("gui_model.zig").GuiModel;
const ParallelJobList = @import("parallel_job_list.zig").ParallelJobList;
const RenderSystem = @import("render_system.zig");
const global = @import("../global.zig");
const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const Material = @import("material.zig").Material;
const RenderModelManager = @import("render_model_manager.zig");
const Framebuffer = @import("framebuffer.zig");
const FrameData = @import("frame_data.zig");
const nvrhi = @import("nvrhi.zig");
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const RenderWorldOpaque = @import("render_world_interface.zig").RenderWorldOpaque;
const RenderWorld = @import("render_world.zig");

export fn ztech_renderSystem_getGuiRecursionLevel() usize {
    return RenderSystem.instance.gui_recursion_level;
}

export fn ztech_renderSystem_incGuiRecursionLevel() void {
    RenderSystem.instance.gui_recursion_level += 1;
}

export fn ztech_renderSystem_decGuiRecursionLevel() void {
    RenderSystem.instance.gui_recursion_level -= 1;
}

export fn ztech_renderSystem_drawStretchPicture(
    top_left: *const CVec4,
    top_right: *const CVec4,
    bottom_right: *const CVec4,
    bottom_left: *const CVec4,
    opt_material: ?*const Material,
    z: f32,
) callconv(.C) void {
    RenderSystem.instance.drawStretchPicture(
        top_left.toVec4f(),
        top_right.toVec4f(),
        bottom_right.toVec4f(),
        bottom_left.toVec4f(),
        opt_material,
        z,
    );
}

export fn ztech_renderSystem_setColor(color: CVec4) callconv(.C) void {
    RenderSystem.instance.setColor(color.toVec4f());
}

export fn ztech_renderSystem_renderCommandBuffers(cmd_head: ?*FrameData.EmptyCommand) callconv(.C) void {
    RenderSystem.instance.renderCommandBuffers(cmd_head);
}

export fn ztech_renderSystem_isInitialized() callconv(.C) bool {
    return RenderSystem.instance.initialized;
}

export fn ztech_renderSystem_setBackendInitialized() callconv(.C) void {
    RenderSystem.instance.backend_initialized = true;
}

export fn ztech_renderSystem_getWidth() callconv(.C) c_int {
    return RenderSystem.instance.getWidth();
}

export fn ztech_renderSystem_getHeight() callconv(.C) c_int {
    return RenderSystem.instance.getWidth();
}

export fn ztech_renderSystem_isBackendInitialized() callconv(.C) bool {
    return RenderSystem.instance.backend_initialized;
}

export fn ztech_renderSystem_setReadyToPresent() callconv(.C) void {
    RenderSystem.instance.omit_swap_buffers = false;
}

export fn ztech_renderSystem_invalidateSwapBuffers() callconv(.C) void {
    RenderSystem.instance.omit_swap_buffers = true;
}

export fn ztech_renderSystem_swapCommandBuffers() callconv(.C) ?*FrameData.EmptyCommand {
    return RenderSystem.instance.swapCommandBuffers();
}

export fn ztech_renderSystem_finishRendering() callconv(.C) void {
    RenderSystem.instance.finishRendering();
}

export fn ztech_renderSystem_getShaderTime() callconv(.C) f32 {
    return RenderSystem.instance.frame_shader_time;
}

export fn ztech_renderSystem_finishCommandBuffers() callconv(.C) ?*FrameData.EmptyCommand {
    return RenderSystem.instance.finishCommandBuffers();
}

export fn ztech_renderSystem_initBackend() callconv(.C) void {
    RenderSystem.instance.initBackend(global.gpa.allocator()) catch unreachable;
}

export fn ztech_renderSystem_init() callconv(.C) void {
    RenderSystem.instance.init(global.gpa.allocator()) catch unreachable;
}

export fn ztech_renderSystem_deinit() callconv(.C) void {
    RenderSystem.instance.deinit(global.gpa.allocator());
}

export fn ztech_renderSystem_getCroppedViewport(out: *ScreenRect) callconv(.C) void {
    out.* = RenderSystem.instance.getCroppedViewport();
}

export fn ztech_renderSystem_getFrameCount() callconv(.C) c_int {
    return @intCast(RenderSystem.instance.frame_count);
}

export fn ztech_renderSystem_createRenderWorld() callconv(.C) *RenderWorldOpaque {
    const allocator = global.gpa.allocator();

    const render_world = RenderSystem.instance.createRenderWorld(allocator) catch
        @panic("Fails to create RenderWorld");

    return @ptrCast(render_world);
}

export fn ztech_renderSystem_destroyRenderWorld(rw: *RenderWorldOpaque) callconv(.C) void {
    const render_world: *RenderWorld = @ptrCast(@alignCast(rw));
    const allocator = global.gpa.allocator();

    RenderSystem.instance.destroyRenderWorld(allocator, render_world);
}
