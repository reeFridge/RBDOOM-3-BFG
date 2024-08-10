const DeclSkin = @import("common.zig").DeclSkin;

pub const MAX_GLOBAL_SHADER_PARMS: usize = 12;

extern fn c_material_remapShaderBySkin(*const DeclSkin, *const Material) callconv(.C) ?*const Material;

pub fn remapShaderBySkin(
    shader: *const Material,
    opt_skin: ?*const DeclSkin,
    opt_custom_shader: ?*const Material,
) ?*const Material {
    // never remap surfaces that were originally nodraw, like collision hulls
    if (!shader.isDrawn()) return shader;

    if (opt_custom_shader) |custom_shader| {
        // this is sort of a hack, but cause deformed surfaces to map to empty surfaces,
        // so the item highlight overlay doesn't highlight the autosprite surface
        return if (shader.deform() > 0)
            null
        else
            custom_shader;
    }

    return if (opt_skin) |skin|
        c_material_remapShaderBySkin(skin, shader)
    else
        shader;
}

pub const Flags = struct {
    pub const MF_DEFAULTED: c_int = 1;
    pub const MF_POLYGONOFFSET: c_int = 2;
    pub const MF_NOSHADOWS: c_int = 4;
    pub const MF_FORCESHADOWS: c_int = 8;
    pub const MF_NOSELFSHADOW: c_int = 16;
    pub const MF_NOPORTALFOG: c_int = 32;
    pub const MF_EDITOR_VISIBLE: c_int = 64;
    pub const MF_LOD1_SHIFT: c_int = 7;
    pub const MF_LOD1: c_int = 128;
    pub const MF_LOD2: c_int = 256;
    pub const MF_LOD3: c_int = 512;
    pub const MF_LOD4: c_int = 1024;
    pub const MF_LOD_PERSISTENT: c_int = 2048;
    pub const MF_GUITARGET: c_int = 4096;
    pub const MF_AUTOGEN_TEMPLATE: c_int = 8192;
    pub const MF_ORIGIN: c_int = 16384;
};

pub const Material = opaque {
    extern fn c_material_isDrawn(*const Material) callconv(.C) bool;
    extern fn c_material_deform(*const Material) callconv(.C) c_int;
    extern fn c_material_isFogLight(*const Material) callconv(.C) bool;
    extern fn c_material_testMaterialFlag(*const Material, c_int) callconv(.C) bool;
    extern fn c_material_spectrum(*const Material) callconv(.C) c_int;
    extern fn c_material_addReference(*Material) callconv(.C) void;
    extern fn c_material_receivesLighting(*const Material) callconv(.C) bool;

    pub fn isDrawn(material: *const Material) bool {
        return c_material_isDrawn(material);
    }

    pub fn deform(material: *const Material) c_int {
        return c_material_deform(material);
    }

    pub fn receivesLighting(material: *const Material) bool {
        return c_material_receivesLighting(material);
    }

    pub fn addReference(material: *Material) void {
        c_material_addReference(material);
    }

    pub fn spectrum(material: *const Material) c_int {
        return c_material_spectrum(material);
    }

    pub fn isFogLight(material: *const Material) bool {
        return c_material_isFogLight(material);
    }

    pub fn testMaterialFlag(material: *const Material, flag: c_int) bool {
        return c_material_testMaterialFlag(material, flag);
    }
};
