const Framebuffer = @import("framebuffer.zig").Framebuffer;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const TriIndex = @import("../sys/types.zig").TriIndex;
const Material = @import("material.zig").Material;

pub const GuiModel = opaque {
    extern fn c_guiModel_heapCreate() callconv(.C) *GuiModel;
    extern fn c_guiModel_heapDestroy(*GuiModel) callconv(.C) void;
    extern fn c_guiModel_clear(*GuiModel) callconv(.C) void;
    extern fn c_guiModel_beginFrame(*GuiModel) callconv(.C) void;
    extern fn c_guiModel_emitFullScreen(*GuiModel, ?*Framebuffer) callconv(.C) void;
    extern fn c_guiModel_allocTris(
        *GuiModel,
        c_int,
        [*]const TriIndex,
        c_int,
        ?*const Material,
        u64,
        c_int,
    ) callconv(.C) ?[*]align(16) DrawVertex;

    pub fn heapCreate() *GuiModel {
        return c_guiModel_heapCreate();
    }

    pub fn heapDestroy(gui_model: *GuiModel) void {
        c_guiModel_heapDestroy(gui_model);
    }

    pub fn clear(gui_model: *GuiModel) void {
        c_guiModel_clear(gui_model);
    }

    pub fn emitFullScreen(gui_model: *GuiModel, render_target: ?*Framebuffer) void {
        c_guiModel_emitFullScreen(gui_model, render_target);
    }

    pub fn beginFrame(gui_model: *GuiModel) void {
        c_guiModel_beginFrame(gui_model);
    }

    pub fn allocTris(
        gui_model: *GuiModel,
        num_verts: usize,
        indexes: []const TriIndex,
        material: ?*const Material,
        gl_state: u64,
        stereo_type: c_int,
    ) ?[]align(16) DrawVertex {
        const opt_array_ptr = c_guiModel_allocTris(
            gui_model,
            @intCast(num_verts),
            indexes.ptr,
            @intCast(indexes.len),
            material,
            gl_state,
            stereo_type,
        );

        return if (opt_array_ptr) |array_ptr| array_ptr[0..num_verts] else null;
    }
};
