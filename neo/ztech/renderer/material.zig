const DeclSkin = @import("common.zig").DeclSkin;
const Image = @import("image.zig").Image;

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
        return if (shader.deformType() != .DFRM_NONE)
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

pub const MAX_VERTEX_PARAMS: usize = 4;
pub const MAX_FRAGMENT_IMAGES: usize = 8;

pub const DecalInfo = extern struct {
    stayTime: c_int,
    fadeTime: c_int,
    start: [4]f32,
    end: [4]f32,
};

pub const TextureStage = extern struct {
    cinematic: ?*anyopaque,
    image: ?*Image,
    texgen: TexGen,
    hasMatrix: bool,
    matrix: [2][3]c_int,
    dynamic: DynamicImage,
    width: c_int,
    height: c_int,
    dynamicFrameCount: c_int,
};

pub const MaterialCoverage = enum(c_int) {
    MC_BAD,
    MC_OPAQUE, // completely fills the triangle, will have black drawn on fillDepthBuffer
    MC_PERFORATED, // may have alpha tested holes
    MC_TRANSLUCENT, // blended with background
};

pub const DynamicImage = enum(c_int) {
    DI_STATIC,
    DI_SCRATCH,
    DI_CUBE_RENDER,
    DI_MIRROR_RENDER,
    DI_XRAY_RENDER,
    DI_REMOTE_RENDER,
    DI_GUI_RENDER,
    DI_RENDER_TARGET,
};

pub const Deform = enum(c_int) {
    DFRM_NONE,
    DFRM_SPRITE,
    DFRM_TUBE,
    DFRM_FLARE,
    DFRM_EXPAND,
    DFRM_MOVE,
    DFRM_EYEBALL,
    DFRM_PARTICLE,
    DFRM_PARTICLE2,
    DFRM_TURB,
};

pub const TexGen = enum(c_int) {
    TG_EXPLICIT,
    TG_DIFFUSE_CUBE,
    TG_REFLECT_CUBE,
    TG_SKYBOX_CUBE,
    TG_WOBBLESKY_CUBE,
    TG_SCREEN,
    TG_SCREEN2,
    TG_GLASSWARP,
};

pub const StageLighting = enum(c_int) {
    SL_AMBIENT,
    SL_BUMP,
    SL_DIFFUSE,
    SL_SPECULAR,
    SL_COVERAGE,
};

pub const StageVertexColor = enum(c_int) {
    SVC_IGNORE,
    SVC_MODULATE,
    SVC_INVERSE_MODULATE,
};

pub const ColorStage = extern struct {
    registers: [4]c_int,
};

pub const StencilComp = enum(c_int) {
    STENCIL_COMP_GREATER,
    STENCIL_COMP_GEQUAL,
    STENCIL_COMP_LESS,
    STENCIL_COMP_LEQUAL,
    STENCIL_COMP_EQUAL,
    STENCIL_COMP_NOTEQUAL,
    STENCIL_COMP_ALWAYS,
    STENCIL_COMP_NEVER,
};

pub const StencilOperation = enum(c_int) {
    STENCIL_OP_KEEP,
    STENCIL_OP_ZERO,
    STENCIL_OP_REPLACE,
    STENCIL_OP_INCRSAT,
    STENCIL_OP_DECRSAT,
    STENCIL_OP_INVERT,
    STENCIL_OP_INCRWRAP,
    STENCIL_OP_DECRWRAP,
};

pub const TextureFilter = enum(c_int) {
    TF_LINEAR,
    TF_NEAREST,
    TF_NEAREST_MIPMAP, // RB: no linear interpolation but explicit mip-map levels for hierarchical depth buffer
    TF_DEFAULT, // use the user-specified r_textureFilter
};

pub const TextureRepeat = enum(c_int) {
    TR_REPEAT,
    TR_CLAMP,
    TR_CLAMP_TO_ZERO, // guarantee 0,0,0,255 edge for projected textures
    TR_CLAMP_TO_ZERO_ALPHA, // guarantee 0 alpha edge for projected textures
};

pub const StencilStage = extern struct {
    ref: u8,
    readMask: u8,
    writeMask: u8,
    comp: StencilComp,
    pass: StencilOperation,
    fail: StencilOperation,
    zFail: StencilOperation,
};

pub const NewShaderStage = extern struct {
    vertexProgram: c_int,
    numVertexParms: c_int,
    vertexParms: [MAX_VERTEX_PARAMS][4]c_int,
    fragmentProgram: c_int,
    glslProgram: c_int,
    numFragmentProgramImages: c_int,
    fragmentProgramImages: [MAX_FRAGMENT_IMAGES]?*Image,
};

pub const ShaderStage = extern struct {
    conditionRegister: c_int,
    lighting: StageLighting,
    drawStateBits: u64,
    color: ColorStage,
    hasAlphaTest: bool,
    alphaTestRegister: c_int,
    texture: TextureStage,
    vertexColor: StageVertexColor,
    ignoreAlphaTest: bool,
    privatePolygonOffset: f32,
    stencilStage: ?*StencilStage,
    newStage: ?*NewShaderStage,
};

pub const Material = opaque {
    extern fn c_material_isDrawn(*const Material) callconv(.C) bool;
    extern fn c_material_deform(*const Material) Deform;
    extern fn c_material_isFogLight(*const Material) callconv(.C) bool;
    extern fn c_material_isBlendLight(*const Material) bool;
    extern fn c_material_testMaterialFlag(*const Material, c_int) callconv(.C) bool;
    extern fn c_material_spectrum(*const Material) callconv(.C) c_int;
    extern fn c_material_addReference(*Material) callconv(.C) void;
    extern fn c_material_receivesLighting(*const Material) callconv(.C) bool;
    extern fn c_material_hasSubview(*const Material) callconv(.C) bool;
    extern fn c_material_lightCastsShadows(*const Material) bool;
    extern fn c_material_surfaceCastsShadow(*const Material) bool;
    extern fn c_material_isLod(*const Material) bool;
    extern fn c_material_isLodVisibleForDistance(*const Material, f32, f32) bool;
    extern fn c_material_getNumRegisters(*const Material) c_int;
    extern fn c_material_getNumStages(*const Material) c_int;
    extern fn c_material_coverage(*const Material) MaterialCoverage;
    extern fn c_material_evaluateRegisters(
        *const Material,
        [*]f32,
        [*]const f32,
        [*]const f32,
        f32,
        ?*anyopaque,
    ) void;
    extern fn c_material_getStage(*const Material, c_int) ?*const ShaderStage;
    extern fn c_material_getDecalInfo(*const Material) DecalInfo;

    pub fn getDecalInfo(material: *const Material) DecalInfo {
        return c_material_getDecalInfo(material);
    }

    pub fn coverage(material: *const Material) MaterialCoverage {
        return c_material_coverage(material);
    }

    pub fn isLod(material: *const Material) bool {
        return c_material_isLod(material);
    }

    pub fn isLodVisibleForDistance(
        material: *const Material,
        distance: f32,
        lod_base: f32,
    ) bool {
        return c_material_isLodVisibleForDistance(material, distance, lod_base);
    }

    pub fn getStage(material: *const Material, stage_num: usize) ?*const ShaderStage {
        return c_material_getStage(material, @intCast(stage_num));
    }

    pub fn evaluateRegisters(
        material: *const Material,
        regs: []f32,
        local_params: []f32,
        global_params: []f32,
        time: f32,
        sound_emitter: ?*anyopaque,
    ) void {
        c_material_evaluateRegisters(
            material,
            regs.ptr,
            local_params.ptr,
            global_params.ptr,
            time,
            sound_emitter,
        );
    }

    pub fn getNumRegisters(material: *const Material) usize {
        return @intCast(c_material_getNumRegisters(material));
    }

    pub fn getNumStages(material: *const Material) usize {
        return @intCast(c_material_getNumStages(material));
    }

    pub fn lightCastsShadows(material: *const Material) bool {
        return c_material_lightCastsShadows(material);
    }

    pub fn surfaceCastsShadow(material: *const Material) bool {
        return c_material_surfaceCastsShadow(material);
    }

    pub fn isDrawn(material: *const Material) bool {
        return c_material_isDrawn(material);
    }

    pub fn deformType(material: *const Material) Deform {
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

    pub fn isBlendLight(material: *const Material) bool {
        return c_material_isBlendLight(material);
    }

    pub fn isFogLight(material: *const Material) bool {
        return c_material_isFogLight(material);
    }

    pub fn testMaterialFlag(material: *const Material, flag: c_int) bool {
        return c_material_testMaterialFlag(material, flag);
    }

    pub fn hasSubview(material: *const Material) bool {
        return c_material_hasSubview(material);
    }
};
