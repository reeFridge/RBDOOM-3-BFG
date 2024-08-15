const Framebuffer = @import("framebuffer.zig").Framebuffer;

pub const GuiModel = opaque {
    extern fn c_guiModel_heapCreate() callconv(.C) *GuiModel;
    extern fn c_guiModel_heapDestroy(*GuiModel) callconv(.C) void;
    extern fn c_guiModel_clear(*GuiModel) callconv(.C) void;
    extern fn c_guiModel_beginFrame(*GuiModel) callconv(.C) void;
    extern fn c_guiModel_emitFullScreen(*GuiModel, ?*Framebuffer) callconv(.C) void;

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
};
