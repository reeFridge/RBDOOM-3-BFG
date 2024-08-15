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
    extern fn c_declManager_findMaterial([*:0]const u8, bool) callconv(.C) ?*Material;

    pub fn findMaterial(name: []const u8) ?*Material {
        const allocator = gpa.allocator();
        const name_sentinel = allocator.dupeZ(u8, name) catch unreachable;
        defer allocator.free(name_sentinel);

        return c_declManager_findMaterial(name_sentinel.ptr, false);
    }

    pub fn findMaterialDefault(name: []const u8) ?*Material {
        const allocator = gpa.allocator();
        const name_sentinel = allocator.dupeZ(u8, name) catch unreachable;
        defer allocator.free(name_sentinel);

        return c_declManager_findMaterial(name_sentinel.ptr, true);
    }
};
