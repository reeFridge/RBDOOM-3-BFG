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
const nvrhi = @import("nvrhi.zig");

export fn ztech_renderSystem_initBackend(
    command_list_ptr: *?*nvrhi.ICommandList,
) callconv(.C) void {
    RenderSystem.instance.initBackend();
    const instance = &RenderSystem.instance;

    command_list_ptr.* = instance.command_list.commandList_ptr().?;
}

export fn ztech_renderSystem_init(
    view_count: *c_int,
    ambient_light_vector: *CVec4,
    gui_model_ptr: **GuiModel,
    gamma_table: [*]c_ushort,
    identity_matrix: [*]f32,
    cube_axis: [*]CMat3,
    front_end_job_list: **ParallelJobList,
    envprobe_job_list: **ParallelJobList,
    unit_square_triangles: **SurfaceTriangles,
    zero_one_cube_triangles: **SurfaceTriangles,
    zero_one_sphere_triangles: **SurfaceTriangles,
    test_image_triangles: **SurfaceTriangles,
    default_material: *?*const Material,
    default_point_light: *?*const Material,
    default_projected_light: *?*const Material,
    white_material: *?*const Material,
    char_set_material: *?*const Material,
    imgui_material: *?*const Material,
    omit_swap_buffers: *bool,
    tr_gui_model_ptr: **GuiModel,
) callconv(.C) void {
    RenderSystem.instance.init(global.gpa.allocator()) catch unreachable;
    const instance = &RenderSystem.instance;

    view_count.* = @intCast(instance.view_count);
    ambient_light_vector.* = CVec4.fromVec4f(instance.ambient_light_vector);
    gui_model_ptr.* = instance.gui_model;
    tr_gui_model_ptr.* = instance.gui_model;

    for (gamma_table[0..256], 0..) |*item, i| {
        item.* = instance.gamma_table[i];
    }

    for (identity_matrix[0..16], 0..) |*item, i| {
        item.* = instance.identity_space[i];
    }

    for (cube_axis[0..6], 0..) |*item, i| {
        item.* = CMat3.fromMat3f(instance.cube_axis[i]);
    }

    front_end_job_list.* = instance.front_end_job_list;
    envprobe_job_list.* = instance.envprobe_job_list;

    unit_square_triangles.* = instance.unit_square_triangles;
    zero_one_cube_triangles.* = instance.zero_one_cube_triangles;
    zero_one_sphere_triangles.* = instance.zero_one_sphere_triangles;
    test_image_triangles.* = instance.test_image_triangles;

    default_material.* = instance.default_material;
    default_point_light.* = instance.default_point_light;
    default_projected_light.* = instance.default_projected_light;
    white_material.* = instance.white_material;
    char_set_material.* = instance.char_set_material;
    imgui_material.* = instance.imgui_material;

    omit_swap_buffers.* = instance.omit_swap_buffers;

    RenderModelManager.instance.init();
}

export fn ztech_renderSystem_deinit(
    command_list_ptr: *?*nvrhi.ICommandList,
) callconv(.C) void {
    RenderSystem.instance.deinit(global.gpa.allocator());

    command_list_ptr.* = null;
}
