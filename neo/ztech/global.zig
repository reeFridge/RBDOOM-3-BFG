const std = @import("std");
const entity = @import("entity.zig");
const Types = @import("types.zig").ExportedTypes;

pub const Entities = entity.Entities(Types);

pub var entities: Entities = undefined;

pub const gravity = 1066.0;

pub var gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub const DeclManager = struct {
    extern fn c_declManager_findMaterial([*:0]const u8) callconv(.C) ?*anyopaque;

    pub fn findMaterial(name: []const u8) !?*anyopaque {
        const allocator = gpa.allocator();
        const name_sentinel = try allocator.dupeZ(u8, name);
        defer allocator.free(name_sentinel);

        return c_declManager_findMaterial(name_sentinel.ptr);
    }
};

pub const RenderModelManager = struct {
    extern fn c_renderModelManager_allocModel() callconv(.C) *anyopaque;
    extern fn c_renderModelManager_addModel(*anyopaque) callconv(.C) void;
    extern fn c_renderModelManager_removeModel(*anyopaque) callconv(.C) void;
    extern fn c_renderModelManager_findModel([*:0]const u8) callconv(.C) *anyopaque;

    pub fn allocModel() *anyopaque {
        return c_renderModelManager_allocModel();
    }

    pub fn addModel(model_ptr: *anyopaque) void {
        c_renderModelManager_addModel(model_ptr);
    }

    pub fn removeModel(model_ptr: *anyopaque) void {
        c_renderModelManager_removeModel(model_ptr);
    }

    pub fn findModel(model_name: [*:0]const u8) *anyopaque {
        return c_renderModelManager_findModel(model_name);
    }
};
