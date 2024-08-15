const RenderModel = @import("model.zig").RenderModel;

pub const RenderModelManager = opaque {
    pub const GetModelError = error{ModelNotFound};

    extern fn c_renderModelManager_allocModel(*RenderModelManager) callconv(.C) *RenderModel;
    extern fn c_renderModelManager_addModel(*RenderModelManager, *RenderModel) callconv(.C) void;
    extern fn c_renderModelManager_removeModel(*RenderModelManager, *RenderModel) callconv(.C) void;
    extern fn c_renderModelManager_findModel(*RenderModelManager, [*:0]const u8) callconv(.C) ?*RenderModel;
    extern fn c_renderModelManager_defaultModel(*RenderModelManager) callconv(.C) ?*RenderModel;
    extern fn c_renderModelManager_init(*RenderModelManager) callconv(.C) void;
    extern fn c_renderModelManager_shutdown(*RenderModelManager) callconv(.C) void;

    pub fn init(manager: *RenderModelManager) void {
        c_renderModelManager_init(manager);
    }

    pub fn shutdown(manager: *RenderModelManager) void {
        c_renderModelManager_shutdown(manager);
    }

    pub fn allocModel(manager: *RenderModelManager) *RenderModel {
        return c_renderModelManager_allocModel(manager);
    }

    pub fn addModel(manager: *RenderModelManager, model_ptr: *RenderModel) void {
        c_renderModelManager_addModel(manager, model_ptr);
    }

    pub fn removeModel(manager: *RenderModelManager, model_ptr: *RenderModel) void {
        c_renderModelManager_removeModel(manager, model_ptr);
    }

    pub fn findModel(manager: *RenderModelManager, model_name: [*:0]const u8) GetModelError!*RenderModel {
        return if (c_renderModelManager_findModel(manager, model_name)) |ptr|
            ptr
        else
            error.ModelNotFound;
    }

    pub fn defaultModel(manager: *RenderModelManager) GetModelError!*RenderModel {
        return if (c_renderModelManager_defaultModel(manager)) |ptr|
            ptr
        else
            error.ModelNotFound;
    }
};

pub const instance = @extern(*RenderModelManager, .{ .name = "localModelManager" });
