const std = @import("std");
const entity = @import("entity.zig");
const Types = @import("types.zig").ExportedTypes;
const Material = @import("renderer/material.zig").Material;
const RenderModel = @import("renderer/model.zig").RenderModel;

pub const Entities = entity.Entities(Types);

pub var entities: Entities = undefined;

pub const gravity = 1066.0;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const DeclManager = struct {
    extern fn c_declManager_findMaterial([*:0]const u8) callconv(.C) ?*Material;

    pub fn findMaterial(name: []const u8) !?*Material {
        const allocator = gpa.allocator();
        const name_sentinel = try allocator.dupeZ(u8, name);
        defer allocator.free(name_sentinel);

        return c_declManager_findMaterial(name_sentinel.ptr);
    }
};

pub const RenderModelManager = struct {
    pub const GetModelError = error{ModelNotFound};

    extern fn c_renderModelManager_allocModel() callconv(.C) *RenderModel;
    extern fn c_renderModelManager_addModel(*RenderModel) callconv(.C) void;
    extern fn c_renderModelManager_removeModel(*RenderModel) callconv(.C) void;
    extern fn c_renderModelManager_findModel([*:0]const u8) callconv(.C) ?*RenderModel;
    extern fn c_renderModelManager_defaultModel() callconv(.C) ?*RenderModel;

    pub fn allocModel() *RenderModel {
        return c_renderModelManager_allocModel();
    }

    pub fn addModel(model_ptr: *RenderModel) void {
        c_renderModelManager_addModel(model_ptr);
    }

    pub fn removeModel(model_ptr: *RenderModel) void {
        c_renderModelManager_removeModel(model_ptr);
    }

    pub fn findModel(model_name: [*:0]const u8) GetModelError!*RenderModel {
        return if (c_renderModelManager_findModel(model_name)) |ptr|
            ptr
        else
            error.ModelNotFound;
    }

    pub fn defaultModel() GetModelError!*RenderModel {
        return if (c_renderModelManager_defaultModel()) |ptr|
            ptr
        else
            error.ModelNotFound;
    }
};
