const std = @import("std");
const nvrhi = @import("nvrhi.zig");
const idlib = @import("../idlib.zig");
const backend = @import("render_backend.zig");
const RenderModel = @import("model.zig").RenderModel;
const RenderModelStatic = @import("model.zig").RenderModelStatic;
const Allocator = std.mem.Allocator;
const Material = @import("material.zig").Material;

pub const RenderModelManager = extern struct {
    pub const GetModelError = error{ModelNotFound};

    extern fn c_renderModelManager_findModel(
        *RenderModelManager,
        [*:0]const u8,
    ) ?*RenderModel;
    extern fn c_renderModelManager_defaultModel(*RenderModelManager) ?*RenderModel;

    vptr: *anyopaque = undefined,
    models: idlib.List(*RenderModelStatic) = .{},
    hash: idlib.HashIndex = .{},
    default_model: ?*RenderModelStatic = null,
    beam_model: ?*RenderModelStatic = null,
    sprite_model: ?*RenderModelStatic = null,
    inside_level_load: bool = false,
    command_list_handle: nvrhi.CommandListHandle = .{},

    pub fn init(
        manager: *RenderModelManager,
        default_material: *const Material,
        device: *nvrhi.IDevice,
        allocator: Allocator,
    ) Allocator.Error!void {
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
        model.* = .{};
        try model.initEmpty("_DEFAULT", allocator);
        try model.makeDefault(default_material, allocator);
        model.level_load_referenced = true;
        manager.default_model = model;
        try manager.addModel(model, allocator);

        const beam = try allocator.create(RenderModelStatic);
        beam.* = .{};
        try beam.initEmpty("_BEAM", allocator);
        beam.level_load_referenced = true;
        manager.beam_model = beam;
        try manager.addModel(beam, allocator);

        const sprite = try allocator.create(RenderModelStatic);
        sprite.* = .{};
        try sprite.initEmpty("_SPRITE", allocator);
        sprite.level_load_referenced = true;
        manager.sprite_model = sprite;
        try manager.addModel(sprite, allocator);
    }

    pub fn shutdown(manager: *RenderModelManager, allocator: Allocator) void {
        for (manager.models.constSlice()) |model_ptr| {
            model_ptr.deinit(allocator);
        }

        manager.models.clear(allocator);
        manager.hash.free(allocator);
        manager.command_list_handle.deinit();
    }

    pub fn addModel(
        manager: *RenderModelManager,
        model: *RenderModelStatic,
        allocator: Allocator,
    ) Allocator.Error!void {
        const index = try manager.models.append(model, allocator);

        try manager.hash.add(
            manager.hash.generateKey(model.name.constSlice(), false),
            @intCast(index),
            allocator,
        );
    }

    pub fn removeModel(manager: *RenderModelManager, model: *RenderModelStatic) void {
        if (manager.models.findIndex(&model)) |index| {
            manager.hash.removeIndex(
                manager.hash.generateKey(model.name.constSlice(), false),
                @intCast(index),
            );
            manager.models.removeIndex(index);
        }
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
