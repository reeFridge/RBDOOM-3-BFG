const std = @import("std");
const idlib = @import("../idlib.zig");
const decl = @import("../framework/decl_manager.zig");
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
        return if (shader.deformType() != .none)
            null
        else
            custom_shader;
    }

    return if (opt_skin) |skin|
        c_material_remapShaderBySkin(skin, shader)
    else
        shader;
}

pub const ContentFlags = packed struct(u32) {
    solid: bool = false, // an eye is never valid in a solid
    @"opaque": bool = false, // blocks visibility (for ai)
    water: bool = false, // used for water
    playerclip: bool = false, // solid to players
    monsterclip: bool = false, // solid to monsters
    moveableclip: bool = false, // solid to moveable entities
    ikclip: bool = false, // solid to IK
    blood: bool = false, // used to detect blood decals
    body: bool = false, // used for actors
    projectile: bool = false, // used for projectiles
    corpse: bool = false, // used for dead bodies
    rendermodel: bool = false, // used for render models for collision detection
    trigger: bool = false, // used for triggers
    aas_solid: bool = false, // solid for AAS
    aas_obstacle: bool = false, // used to compile an obstacle into AAS that can be enabled/disabled
    flashlight_trigger: bool = false, // used for triggers that are activated by the flashlight
    slime: bool = false, // used for slime
    fog: bool = false, // used for fog
    lava: bool = false,
    areaportal: bool = false, // portal separating renderer areas
    nocsg: bool = false, // don't cut this brush with CSG operations in the editor
    origin: bool = false,
    reserved_: u10 = 0,
};

pub const Flags = packed struct(u32) {
    defaulted: bool = false,
    polygonoffset: bool = false,
    noshadows: bool = false,
    forceshadows: bool = false,
    noselfshadow: bool = false,
    noportalfog: bool = false,
    editor_visible: bool = false,
    lod1_shift: bool = false,
    lod1: bool = false,
    lod2: bool = false,
    lod3: bool = false,
    lod4: bool = false,
    lod_persistent: bool = false,
    guitarget: bool = false,
    autogen_template: bool = false,
    origin: bool = false,
    reserved_: u16 = 0,
};

pub const MAX_VERTEX_PARAMS: usize = 4;
pub const MAX_FRAGMENT_IMAGES: usize = 8;

pub const DecalInfo = extern struct {
    stayTime: c_int,
    fadeTime: c_int,
    start: [4]f32,
    end: [4]f32,
};

pub const Cinematic = extern struct {
    vptr: *anyopaque,
};

pub const TextureStage = extern struct {
    cinematic: ?*Cinematic,
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
    bad,
    @"opaque", // completely fills the triangle, will have black drawn on fillDepthBuffer
    perforated, // may have alpha tested holes
    translucent, // blended with background
};

pub const DynamicImage = enum(c_int) {
    static,
    scratch,
    cube_render,
    mirror_render,
    xray_render,
    remote_render,
    gui_render,
    render_target,
};

pub const Deform = enum(c_int) {
    none,
    sprite,
    tube,
    flare,
    expand,
    move,
    eyeball,
    particle,
    particle2,
    turb,
};

pub const TexGen = enum(c_int) {
    explicit,
    diffuse_cube,
    reflect_cube,
    skybox_cube,
    wobblesky_cube,
    screen,
    screen2,
    glasswarp,
};

pub const StageLighting = enum(c_int) {
    ambient,
    bump,
    diffuse,
    specular,
    coverage,
};

pub const StageVertexColor = enum(c_int) {
    ignore,
    modulate,
    inverse_modulate,
};

pub const ColorStage = extern struct {
    registers: [4]c_int,
};

pub const StencilComp = enum(c_int) {
    greater,
    gequal,
    less,
    lequal,
    equal,
    notequal,
    always,
    never,
};

pub const StencilOperation = enum(c_int) {
    keep,
    zero,
    replace,
    incrsat,
    decrsat,
    invert,
    incrwrap,
    decrwrap,
};

pub const TextureFilter = enum(c_int) {
    linear,
    nearest,
    nearest_mipmap,
    default,
};

pub const TextureRepeat = enum(c_int) {
    repeat,
    clamp,
    clamp_to_zero, // guarantee 0,0,0,255 edge for projected textures
    clamp_to_zero_alpha, // guarantee 0 alpha edge for projected textures
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

pub const CullType = enum(c_int) {
    front_sided,
    back_sided,
    two_sided,
};

pub const SubViewType = enum(u16) {
    none,
    mirror,
    direct_portal,
};

pub const ExpOpType = enum(c_int) {
    add,
    subtract,
    multiply,
    divide,
    mod,
    table,
    gt,
    ge,
    lt,
    le,
    eq,
    ne,
    @"and",
    @"or",
    sound,
};

pub const ExpOp = extern struct {
    opType: ExpOpType,
    a: c_int,
    b: c_int,
    c: c_int,
};

const MtrParsingData = extern struct {
    registerIsTemporary: [MAX_EXPRESSION_REGISTERS]bool,
    shaderRegisters: [MAX_EXPRESSION_REGISTERS]f32,
    shaderOps: [MAX_EXPRESSION_OPS]ExpOp,
    parseStages: [MAX_SHADER_STAGES]ShaderStage,
    registersAreConstant: bool,
    forceOverlays: bool,
};

pub const UserInterface = opaque {};

pub const MAX_EXPRESSION_OPS: usize = 4096;
pub const MAX_EXPRESSION_REGISTERS: usize = 4096;
pub const MAX_SHADER_STAGES: usize = 256;
pub const MAX_TEXGEN_REGISTERS: usize = 4;

pub const MaterialSort = enum(c_int) {
    bad = -1,
};

pub const Material = extern struct {
    pub const default_definition =
        \\{
        \\  {
        \\      blend blend
        \\      map _default
        \\  }
        \\}
    ;

    base: decl.Decl = .{},
    desc: idlib.idStr = .{},
    renderBump: idlib.idStr = .{},
    lightFalloffImage: ?*Image = null,
    fastPathBumpImage: ?*Image = null,
    fastPathDiffuseImage: ?*Image = null,
    fastPathSpecularImage: ?*Image = null,
    entityGui: c_int = 0,
    gui: ?*UserInterface = null,
    noFog: bool = false,
    spectrum: c_int = 0,
    polygonOffset: f32 = 0,
    contentFlags: ContentFlags = .{ .solid = true },
    surfaceFlags: c_int = 0,
    materialFlags: c_int = 0,
    decalInfo: DecalInfo = .{
        .stayTime = 10000,
        .fadeTime = 4000,
        .start = .{ 1, 1, 1, 1 },
        .end = .{ 0, 0, 0, 0 },
    },
    sort: f32 = @floatFromInt(@intFromEnum(MaterialSort.bad)),
    stereoEye: f32 = 0,
    deform: Deform = .none,
    deformRegisters: [4]c_int = [_]c_int{0} ** 4,
    deformDecl: ?*const decl.Decl = null,
    texGenRegisters: [MAX_TEXGEN_REGISTERS]c_int = [_]c_int{0} ** MAX_TEXGEN_REGISTERS,
    coverage: MaterialCoverage = .bad,
    cullType: CullType = .front_sided,
    subViewType: SubViewType = .none,
    shouldCreateBackSides: bool = false,
    fogLight: bool = false,
    blendLight: bool = false,
    ambientLight: bool = false,
    unsmoothedTangents: bool = false,
    mikktspace: bool = false,
    hasSubview: bool = false,
    allowOverlays: bool = true,
    numOps: u32 = 0,
    ops: ?[*]ExpOp = null,
    numRegisters: u32 = 0,
    expressionRegisters: ?[*]f32 = null,
    constantRegisters: ?[*]f32 = null,
    numStages: u32 = 0,
    numAmbientStages: u32 = 0,
    stages: ?[*]ShaderStage = null,
    pd: ?*MtrParsingData = null,
    surfaceArea: f32 = 0,
    editorImageName: idlib.idStr = .{},
    editorImage: ?*Image = null,
    editorAlpha: f32 = 1,
    suppressInSubview: bool = false,
    portalSky: bool = false,
    refCount: u32 = 0,

    extern fn c_material_isDrawn(*const Material) bool;
    extern fn c_material_testMaterialFlag(*const Material, c_int) bool;
    extern fn c_material_addReference(*Material) callconv(.C) void;
    extern fn c_material_receivesLighting(*const Material) bool;
    extern fn c_material_lightCastsShadows(*const Material) bool;
    extern fn c_material_surfaceCastsShadow(*const Material) bool;
    extern fn c_material_isLod(*const Material) bool;
    extern fn c_material_isLodVisibleForDistance(*const Material, f32, f32) bool;
    extern fn c_material_evaluateRegisters(
        *const Material,
        [*]f32,
        [*]const f32,
        [*]const f32,
        f32,
        ?*anyopaque,
    ) void;

    pub fn init(self: *Material) void {
        self.* = .{};
        self.desc.initEmptyBuffer();
        self.renderBump.initEmptyBuffer();
        self.editorImageName.initEmptyBuffer();
    }

    pub fn parse(
        material: *Material,
        definition_text: []const u8,
        allow_binary_version: bool,
        allocator: std.mem.Allocator,
    ) error{}!void {
        _ = material;
        _ = allocator;
        _ = definition_text;
        _ = allow_binary_version;

        @panic("Material.parse is not implemented");
    }

    pub fn setDefaultText(material: *Material) error{}!bool {
        _ = material;

        @panic("Material.setDefaultText is not implemented");
    }

    pub fn freeData(material: *Material, allocator: std.mem.Allocator) void {
        if (material.stages) |stages| {
            const slice = stages[0..material.numStages];
            for (slice) |*stage| {
                if (stage.texture.cinematic) |cinematic| {
                    // TODO: cinematic.deinit(allocator);
                    allocator.destroy(cinematic);
                    stage.texture.cinematic = null;
                }

                if (stage.newStage) |new_stage| {
                    allocator.destroy(new_stage);
                    stage.newStage = null;
                }

                if (stage.stencilStage) |stencil_stage| {
                    allocator.destroy(stencil_stage);
                    stage.stencilStage = null;
                }
            }

            allocator.free(slice);
            material.stages = null;
        }

        if (material.expressionRegisters) |expression_registers| {
            const slice = expression_registers[0..material.numRegisters];
            allocator.free(slice);
            material.expressionRegisters = null;
        }

        if (material.constantRegisters) |constant_registers| {
            const slice = constant_registers[0..material.numRegisters];
            allocator.free(slice);
            material.constantRegisters = null;
        }

        if (material.ops) |ops| {
            const slice = ops[0..material.numOps];
            allocator.free(slice);
            material.ops = null;
        }
    }

    pub fn getDecalInfo(material: *const Material) DecalInfo {
        return material.decalInfo;
    }

    pub fn coverage(material: *const Material) MaterialCoverage {
        return material.coverage;
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
        return if (material.stages) |stages|
            &stages[stage_num]
        else
            null;
    }

    pub fn evaluateRegisters(
        material: *const Material,
        regs: []f32,
        local_params: []const f32,
        global_params: []const f32,
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
        return @intCast(material.numRegisters);
    }

    pub fn getNumStages(material: *const Material) usize {
        return @intCast(material.numStages);
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
        return material.deform;
    }

    pub fn receivesLighting(material: *const Material) bool {
        return c_material_receivesLighting(material);
    }

    pub fn addReference(material: *Material) void {
        c_material_addReference(material);
    }

    pub fn isBlendLight(material: *const Material) bool {
        return material.blendLight;
    }

    pub fn isFogLight(material: *const Material) bool {
        return material.fogLight;
    }

    pub fn testMaterialFlag(material: *const Material, flag: Flags) bool {
        return c_material_testMaterialFlag(material, @intCast(@as(u32, @bitCast(flag))));
    }
};
