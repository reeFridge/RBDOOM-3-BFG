const std = @import("std");
const nvrhi = @import("nvrhi.zig");
const idlib = @import("../idlib.zig");
const backend = @import("render_backend.zig");
const RenderModel = @import("model.zig").RenderModel;
const RenderModelStatic = @import("model.zig").RenderModelStatic;

pub const RenderModelManager = extern struct {
    pub const GetModelError = error{ModelNotFound};

    extern fn c_renderModelManager_allocModel(*RenderModelManager) *RenderModel;
    extern fn c_renderModelManager_addModel(*RenderModelManager, *RenderModel) void;
    extern fn c_renderModelManager_removeModel(*RenderModelManager, *RenderModel) void;
    extern fn c_renderModelManager_findModel(*RenderModelManager, [*:0]const u8) ?*RenderModel;
    extern fn c_renderModelManager_defaultModel(*RenderModelManager) ?*RenderModel;
    extern fn c_renderModelManager_init(*RenderModelManager) void;
    extern fn c_renderModelManager_shutdown(*RenderModelManager) void;

    vptr: *anyopaque = undefined,
    models: idlib.idList(*RenderModel) = .{},
    hash: idlib.idHashIndex = .{},
    default_model: ?*RenderModel = null,
    beam_model: ?*RenderModel = null,
    sprite_model: ?*RenderModel = null,
    inside_level_load: bool = false,
    command_list_handle: nvrhi.CommandListHandle = .{},

    pub fn init(
        manager: *RenderModelManager,
        device: *nvrhi.IDevice,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!void {
        manager.* = .{};

        _ = if (manager.command_list_handle.ptr_) |ptr|
            ptr
        else command_list: {
            const mb: u32 = @intCast(backend.r_vk_upload_buffer_size_mb.integer_value);
            const handle = device.createCommandList(.{
                // if api == VULKAN
                .uploadChunkSize = mb * 1024 * 1024,
            });
            manager.command_list_handle = handle;

            break :command_list handle.ptr_ orelse @panic("Fails to create command-list!");
        };

        // TODO: addCommand: listModels
        // TODO: addCommand: printModel
        // TODO: addCommand: reloadModels
        // TODO: addCommand: touchModel

        const model = try allocator.create(RenderModelStatic);
        model.initEmpty("_DEFAULT");
        model.makeDefaultModel();
        model.level_load_referenced = true;
        manager.default_model = @ptrCast(model);
        try manager.addModel(@ptrCast(model));

        const beam = try allocator.create(RenderModelStatic);
        beam.initEmpty("_BEAM");
        beam.level_load_referenced = true;
        manager.beam_model = @ptrCast(beam);
        try manager.addModel(@ptrCast(beam));

        const sprite = try allocator.create(RenderModelStatic);
        sprite.initEmpty("_SPRITE");
        sprite.level_load_referenced = true;
        manager.sprite_model = @ptrCast(sprite);
        try manager.addModel(@ptrCast(sprite));
    }

    pub fn shutdown(manager: *RenderModelManager, allocator: std.mem.Allocator) void {
        for (manager.models.constSlice()) |_| {
            _ = allocator;
            // TODO: provide type_id to upcast
            //allocator.destroy(model_ptr);
        }

        manager.models.clear();
        manager.hash.free();
        _ = manager.command_list_handle.reset();
    }

    pub fn allocModel(manager: *RenderModelManager) *RenderModel {
        return c_renderModelManager_allocModel(manager);
    }

    pub fn addModel(manager: *RenderModelManager, model_ptr: *RenderModel) error{}!void {
        _ = model_ptr;
        _ = manager;

        @panic("not implemented");
    }

    pub fn removeModel(manager: *RenderModelManager, model_ptr: *RenderModel) void {
        _ = model_ptr;
        _ = manager;

        @panic("not implemented");
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
