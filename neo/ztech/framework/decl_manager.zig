const Material = @import("../renderer/material.zig").Material;
const global = @import("../global.zig");

pub const instance = @extern(*DeclManager, .{ .name = "declManagerLocal" });

pub const DeclType = enum(c_int) {
    DECL_TABLE = 0,
    DECL_MATERIAL,
    DECL_SKIN,
    DECL_SOUND,
    DECL_ENTITYDEF,
    DECL_MODELDEF,
    DECL_FX,
    DECL_PARTICLE,
    DECL_AF,
    DECL_PDA,
    DECL_VIDEO,
    DECL_AUDIO,
    DECL_EMAIL,
    DECL_MODELEXPORT,
    DECL_MAPDEF,

    // new decl types can be added here

    DECL_MAX_TYPES = 32,
};

pub const Decl = opaque {};
pub const DeclBase = opaque {};

pub const DeclManager = opaque {
    extern fn c_declManager_findMaterial(*DeclManager, [*:0]const u8, bool) callconv(.C) ?*Material;
    extern fn c_declManager_findType(*DeclManager, DeclType, [*:0]const u8, bool) ?*Decl;

    pub fn findType(
        manager: *DeclManager,
        decl_type: DeclType,
        name: []const u8,
        make_default: bool,
    ) ?*Decl {
        const allocator = global.gpa.allocator();
        const name_sentinel = allocator.dupeZ(u8, name) catch unreachable;
        defer allocator.free(name_sentinel);

        return c_declManager_findType(manager, decl_type, name_sentinel, make_default);
    }

    pub fn findMaterial(manager: *DeclManager, name: []const u8) ?*Material {
        return manager.findMaterial_(name, false);
    }

    pub fn findMaterialDefault(manager: *DeclManager, name: []const u8) ?*Material {
        return manager.findMaterial_(name, true);
    }

    fn findMaterial_(manager: *DeclManager, name: []const u8, make_default: bool) ?*Material {
        const allocator = global.gpa.allocator();
        const name_sentinel = allocator.dupeZ(u8, name) catch unreachable;
        defer allocator.free(name_sentinel);

        return c_declManager_findMaterial(manager, name_sentinel.ptr, make_default);
    }
};
