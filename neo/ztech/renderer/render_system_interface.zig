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

// TODO:
// * DrawStretchPic - Font rendering depends on it!

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

export fn ztech_renderSystem_initBackend(
    command_list_ptr: *?*nvrhi.ICommandList,
) callconv(.C) void {
    RenderSystem.instance.initBackend();
    const instance = &RenderSystem.instance;

    command_list_ptr.* = instance.command_list.commandList_ptr().?;
}

export fn ztech_renderSystem_init(
    view_count: *c_int,
    gui_model_ptr: **GuiModel,
    front_end_job_list: **ParallelJobList,
    envprobe_job_list: **ParallelJobList,
    default_material: *?*const Material,
    default_point_light: *?*const Material,
    default_projected_light: *?*const Material,
    white_material: *?*const Material,
    char_set_material: *?*const Material,
    imgui_material: *?*const Material,
    tr_gui_model_ptr: **GuiModel,
) callconv(.C) void {
    RenderSystem.instance.init(global.gpa.allocator()) catch unreachable;

    ztech_renderSystem_init_syncState(
        view_count,
        gui_model_ptr,
        front_end_job_list,
        envprobe_job_list,
        default_material,
        default_point_light,
        default_projected_light,
        white_material,
        char_set_material,
        imgui_material,
        tr_gui_model_ptr,
    );

    RenderModelManager.instance.init();
}

export fn ztech_renderSystem_deinit(
    command_list_ptr: *?*nvrhi.ICommandList,
) callconv(.C) void {
    RenderSystem.instance.deinit(global.gpa.allocator());

    command_list_ptr.* = null; // avoid double free
}

export fn ztech_renderSystem_getCroppedViewport(out: *ScreenRect) callconv(.C) void {
    out.* = RenderSystem.instance.getCroppedViewport();
}

export fn ztech_renderSystem_getFrameCount() callconv(.C) c_int {
    return @intCast(RenderSystem.instance.frame_count);
}

export fn ztech_renderSystem_init_syncState(
    view_count: *c_int,
    gui_model_ptr: **GuiModel,
    front_end_job_list: **ParallelJobList,
    envprobe_job_list: **ParallelJobList,
    default_material: *?*const Material,
    default_point_light: *?*const Material,
    default_projected_light: *?*const Material,
    white_material: *?*const Material,
    char_set_material: *?*const Material,
    imgui_material: *?*const Material,
    tr_gui_model_ptr: **GuiModel,
) callconv(.C) void {
    const instance = &RenderSystem.instance;

    view_count.* = @intCast(instance.view_count);
    gui_model_ptr.* = instance.gui_model;
    tr_gui_model_ptr.* = instance.gui_model;

    front_end_job_list.* = instance.front_end_job_list;
    envprobe_job_list.* = instance.envprobe_job_list;

    default_material.* = instance.default_material;
    default_point_light.* = instance.default_point_light;
    default_projected_light.* = instance.default_projected_light;
    white_material.* = instance.white_material;
    char_set_material.* = instance.char_set_material;
    imgui_material.* = instance.imgui_material;
}
