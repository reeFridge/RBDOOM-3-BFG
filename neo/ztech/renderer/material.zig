const std = @import("std");
const idlib = @import("../idlib.zig");
const decl = @import("../framework/decl_manager.zig");
const DeclSkin = @import("common.zig").DeclSkin;
const Image = @import("image.zig").Image;
const lexer_ = @import("../lexer.zig");
const Lexer = lexer_.Lexer;
const token_ = @import("../token.zig");
const Token = token_.Token;
const ui_manager = @import("../ui/manager.zig");
const UserInterface = @import("../ui/user_interface.zig").UserInterface;
const flags = @import("../flags.zig");
const TextureUsage = @import("image.zig").TextureUsage;
const CubeFiles = @import("image.zig").CubeFiles;
const image = @import("image.zig");
const gl_state = @import("gl_state.zig");
const render_prog_manager = @import("render_prog_manager.zig");
const Shader = render_prog_manager.Shader;
const Cinematic = @import("cinematic.zig").Cinematic;
const image_program = @import("image_program.zig");
const image_manager = @import("image_manager.zig");

pub const max_global_shader_parms: usize = 12;

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

pub const SurfaceType = enum(u4) {
    none,
    metal,
    stone,
    flesh,
    wood,
    cardboard,
    liquid,
    glass,
    plastic,
    ricochet,
    @"10",
    @"11",
    @"12",
    @"13",
    @"14",
    @"15",
};

pub const SurfaceFlags = packed struct(u32) {
    surface_type: SurfaceType = .none,
    nodamage: bool = false,
    slick: bool = false,
    collision: bool = false,
    ladder: bool = false,
    noimpact: bool = false,
    nosteps: bool = false,
    discrete: bool = false,
    nofragment: bool = false,
    nullnormal: bool = false,
    reserved_: u19 = 0,
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

pub const max_vertex_params: usize = 4;
pub const max_fragment_images: usize = 8;

pub const DecalInfo = extern struct {
    stayTime: c_int,
    fadeTime: c_int,
    start: [4]f32,
    end: [4]f32,
};

pub const SoundWindow = extern struct {
    base: Cinematic,
    show_waveform: bool,

    pub fn create(allocator: std.mem.Allocator) std.mem.Allocator.Error!*SoundWindow {
        const ptr = try allocator.create(SoundWindow);
        ptr.show_waveform = false;
        // TODO: init base

        return ptr;
    }
};

pub const TextureStage = extern struct {
    cinematic: ?*Cinematic,
    image: ?*Image,
    texgen: TexGen,
    has_matrix: bool,
    matrix: [2][3]c_int,
    dynamic: DynamicImage,
    width: u32,
    height: u32,
    dynamic_frame_count: u32,
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
    registers: [4]u32,
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
    read_mask: u8,
    write_mask: u8,
    comp: StencilComp,
    pass: StencilOperation,
    fail: StencilOperation,
    z_fail: StencilOperation,
};

pub const NewShaderStage = extern struct {
    vertex_program: i32,
    num_vertex_params: u32,
    vertex_params: [max_vertex_params][4]c_int,
    fragment_program: i32,
    program: i32,
    num_fragment_program_images: u32,
    fragment_program_images: [max_fragment_images]?*Image,
};

pub const ShaderStage = extern struct {
    condition_register: u32,
    lighting: StageLighting,
    draw_state_bits: u64,
    color: ColorStage,
    has_alpha_test: bool,
    alpha_test_register: u32,
    texture: TextureStage,
    vertex_color: StageVertexColor,
    ignore_alpha_test: bool,
    private_polygon_offset: f32,
    stencil_stage: ?*StencilStage,
    new_stage: ?*NewShaderStage,
};

pub const CullType = enum(c_int) {
    front_sided,
    back_sided,
    two_sided,
};

pub const SubviewType = enum(u16) {
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
    op_type: ExpOpType,
    a: c_int,
    b: c_int,
    c: c_int,
};

pub const ExpRegisters = enum {
    parm0,
    parm1,
    parm2,
    parm3,
    parm4,
    parm5,
    parm6,
    parm7,
    parm8,
    parm9,
    parm10,
    parm11,
    global0,
    global1,
    global2,
    global3,
    global4,
    global5,
    global6,
    global7,

    pub const num_predefined = @typeInfo(ExpRegisters).Enum.fields.len;
};

const MtrParsingData = extern struct {
    register_is_temporary: [max_expression_registers]bool,
    shader_registers: [max_expression_registers]f32,
    shader_ops: [max_expression_ops]ExpOp,
    parse_stages: [max_shader_stages]ShaderStage,
    registers_are_constant: bool,
    force_overlays: bool,
};

pub const max_expression_ops: usize = 4096;
pub const max_expression_registers: usize = 4096;
pub const max_shader_stages: usize = 256;
pub const max_texgen_registers: usize = 4;

pub const MaterialSort = enum(c_int) {
    subview = -3,
    gui = -2,
    bad = -1,
    @"opaque",
    portal_sky,
    decal,
    far,
    medium,
    close,
    almost_nearest,
    nearest,
    post_process = 100,
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
    render_bump: idlib.idStr = .{},
    light_falloff_image: ?*Image = null,
    fast_path_bump_image: ?*Image = null,
    fast_path_diffuse_image: ?*Image = null,
    fast_path_specular_image: ?*Image = null,
    entity_gui: c_int = 0,
    gui: ?*UserInterface = null,
    no_fog: bool = false,
    spectrum: c_int = 0,
    polygon_offset: f32 = 0,
    content_flags: ContentFlags = .{ .solid = true },
    surface_flags: SurfaceFlags = .{},
    material_flags: Flags = .{},
    decal_info: DecalInfo = .{
        .stayTime = 10000,
        .fadeTime = 4000,
        .start = .{ 1, 1, 1, 1 },
        .end = .{ 0, 0, 0, 0 },
    },
    sort: f32 = @floatFromInt(@intFromEnum(MaterialSort.bad)),
    stereo_eye: f32 = 0,
    deform: Deform = .none,
    deform_registers: [4]c_int = [_]c_int{0} ** 4,
    deform_decl: ?*const decl.Decl = null,
    tex_gen_registers: [max_texgen_registers]c_int = [_]c_int{0} ** max_texgen_registers,
    coverage: MaterialCoverage = .bad,
    cull_type: CullType = .front_sided,
    subview_type: SubviewType = .none,
    should_create_back_sides: bool = false,
    fog_light: bool = false,
    blend_light: bool = false,
    ambient_light: bool = false,
    unsmoothed_tangents: bool = false,
    mikktspace: bool = false,
    has_subview: bool = false,
    allow_overlays: bool = true,
    num_ops: u32 = 0,
    ops: ?[*]ExpOp = null,
    num_registers: u32 = 0,
    expression_registers: ?[*]f32 = null,
    constant_registers: ?[*]f32 = null,
    num_stages: u32 = 0,
    num_ambient_stages: u32 = 0,
    stages: ?[*]ShaderStage = null,
    pd: ?*MtrParsingData = null,
    surface_area: f32 = 0,
    editor_image_name: idlib.idStr = .{},
    editor_image: ?*Image = null,
    editor_alpha: f32 = 1,
    suppress_in_subview: bool = false,
    portal_sky: bool = false,
    ref_count: u32 = 0,

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
        self.render_bump.initEmptyBuffer();
        self.editor_image_name.initEmptyBuffer();
    }

    pub const ParseError =
        std.mem.Allocator.Error ||
        ParseMaterialError ||
        Lexer.LoadMemoryError;
    pub fn parse(
        material: *Material,
        definition_text: []const u8,
        allow_binary_version: bool,
        allocator: std.mem.Allocator,
    ) ParseError!void {
        _ = allow_binary_version;

        var lexer = Lexer{ .flags = decl.decl_lexer_flags };
        lexer.initEmpty();
        defer lexer.deinit(allocator);

        try lexer.loadMemory(
            definition_text,
            material.base.base.?.filename() orelse unreachable,
            material.base.base.?.source_line,
            allocator,
        );

        lexer.skipUntilString("{");

        var parsing_data = std.mem.zeroes(MtrParsingData);
        material.pd = &parsing_data;
        defer material.pd = null;

        try material.parseMaterial(&lexer, allocator);

        // TODO

        @panic("Material.parse is not implemented");
    }

    const ParseMaterialError =
        ParseStageError ||
        ui_manager.UserInterfaceManager.FindGuiOrLoadError ||
        Lexer.ReadTokenError ||
        Lexer.ReadOnLineError;
    fn parseMaterial(
        material: *Material,
        lexer: *Lexer,
        allocator: std.mem.Allocator,
    ) ParseMaterialError!void {
        var token = Token{};
        token.initEmpty();
        defer token.deinit();

        var trp_default: TextureRepeat = .repeat;

        while (true) {
            if (material.material_flags.defaulted) return;

            lexer.readToken(&token) catch {
                material.material_flags.defaulted = true;
                return;
            };

            // end of definition
            if (token.eql("}")) {
                break;
            } else if (token.ieql("qer_editorimage")) {
                try lexer.readTokenOnLine(&token);
                try material.editor_image_name.assignSlice(token.slice());
                try lexer.skipRestOfLine();
            } else if (token.ieql("description")) {
                try lexer.readTokenOnLine(&token);
                try material.desc.assignSlice(token.slice());
            } else if (checkSurfaceParam(&token)) |info| {
                material.surface_flags = flags.Flags(SurfaceFlags)
                    .merge(material.surface_flags, info.surface_flags);
                material.content_flags = flags.Flags(ContentFlags)
                    .merge(material.content_flags, info.content_flags);

                if (info.clear_solid) {
                    material.content_flags.solid = false;
                }
            } else if (token.ieql("polygonOffset")) {
                material.material_flags.polygonoffset = true;
                lexer.readTokenOnLine(&token) catch {
                    material.polygon_offset = 1;
                    continue;
                };
                material.polygon_offset = token.getFloatValue();
            } else if (token.ieql("noShadows")) {
                material.material_flags.noshadows = true;
            } else if (token.ieql("suppressInSubview")) {
                material.suppress_in_subview = true;
            } else if (token.ieql("portalSky")) {
                material.portal_sky = true;
            } else if (token.ieql("noSelfShadow")) {
                material.material_flags.noselfshadow = true;
            } else if (token.ieql("noPortalFog")) {
                material.material_flags.noportalfog = true;
            } else if (token.ieql("forceShadows")) {
                material.material_flags.forceshadows = true;
            } else if (token.ieql("noOverlays")) {
                material.allow_overlays = false;
            } else if (token.ieql("forceOverlays")) {
                material.pd.?.force_overlays = true;
            } else if (token.ieql("translucent")) {
                material.coverage = .translucent;
            } else if (token.ieql("zeroclamp")) {
                trp_default = .clamp_to_zero;
            } else if (token.ieql("clamp")) {
                trp_default = .clamp;
            } else if (token.ieql("alphazeroclamp")) {
                trp_default = .clamp_to_zero;
            } else if (token.ieql("forceOpaque")) {
                material.coverage = .@"opaque";
            } else if (token.ieql("twoSided")) {
                material.cull_type = .two_sided;
            } else if (token.ieql("backSided")) {
                material.cull_type = .back_sided;
                material.material_flags.noshadows = true;
            } else if (token.ieql("fogLight")) {
                material.fog_light = true;
            } else if (token.ieql("blendLight")) {
                material.blend_light = true;
            } else if (token.ieql("ambientLight")) {
                material.ambient_light = true;
            } else if (token.ieql("mirror")) {
                material.sort = @floatFromInt(@intFromEnum(MaterialSort.subview));
                material.coverage = .@"opaque";
                material.subview_type = .direct_portal;
            } else if (token.ieql("noFog")) {
                material.no_fog = true;
            } else if (token.ieql("unsmoothedTangents")) {
                material.unsmoothed_tangents = true;
            } else if (token.ieql("origin")) {
                material.material_flags.origin = true;
                material.content_flags.origin = true;
            } else if (token.ieql("mikktspace")) {
                material.mikktspace = true;
            } else if (token.ieql("lightFalloffImage")) {
                @panic("not implemented");
            } else if (token.ieql("guisurf")) {
                try lexer.readTokenOnLine(&token);

                if (token.ieql("entity")) {
                    material.entity_gui = 1;
                } else if (token.ieql("entity2")) {
                    material.entity_gui = 2;
                } else if (token.ieql("entity3")) {
                    material.entity_gui = 3;
                } else {
                    material.gui = try ui_manager.instance.findGuiOrLoad(
                        token.slice(),
                        allocator,
                    );
                }
            } else if (token.ieql("sort")) {
                try material.parseSort(lexer);
            } else if (token.ieql("stereoeye")) {
                try material.parseStereoEye(lexer);
            } else if (token.ieql("spectrum")) {
                try lexer.readTokenOnLine(&token);
                material.spectrum = std.fmt.parseInt(
                    c_int,
                    token.slice(),
                    10,
                ) catch unreachable;
            } else if (token.ieql("deform")) {
                try material.parseDeform(lexer);
            } else if (token.ieql("declInfo")) {
                try material.parseDecalInfo(lexer);
            } else if (token.ieql("renderbump")) {
                try lexer.parseRestOfLine(&material.render_bump);
            } else if (token.ieql("diffusemap") or token.ieql("basecolormap")) {
                @panic("not implemented");
            } else if (token.ieql("specularmap")) {
                @panic("not implemented");
            } else if (token.ieql("rmaomap") or token.ieql("reflectionmap") or token.ieql("pbrmap")) {
                @panic("not implemented");
            } else if (token.ieql("bumpmap") or token.ieql("normalmap")) {
                @panic("not implemented");
            } else if (token.ieql("DECAL_MACRO")) {
                @panic("not implemented");
            } else if (token.ieql("lod1")) {
                material.material_flags.lod1 = true;
            } else if (token.ieql("lod2")) {
                material.material_flags.lod2 = true;
            } else if (token.ieql("lod3")) {
                material.material_flags.lod3 = true;
            } else if (token.ieql("lod4")) {
                material.material_flags.lod4 = true;
            } else if (token.ieql("persistentLOD")) {
                material.material_flags.lod_persistent = true;
            } else if (token.eql("{")) {
                try material.parseStage(lexer, trp_default, allocator);
            } else {
                std.debug.print(
                    "[MATERIAL][WARN] unknown general material parameter\n{s} in {s}\n",
                    .{ token.slice(), material.base.base.?.name.constSlice() },
                );
                material.material_flags.defaulted = true;
                return;
            }
        }

        material.addImplicitStages(.repeat);
        material.sortInteractionStages();

        if (material.cull_type == .two_sided) {
            for (material.pd.?.parse_stages[0..material.num_stages]) |ps| {
                if (ps.lighting != .ambient or ps.texture.texgen != .explicit) {
                    if (material.cull_type == .two_sided) {
                        material.cull_type = .front_sided;
                        material.should_create_back_sides = true;
                    }
                    break;
                }
            }
        }

        var first_gen: TexGen = .explicit;
        for (material.pd.?.parse_stages[0..material.num_stages]) |ps| {
            if (ps.texture.texgen == .explicit) {
                first_gen = ps.texture.texgen;
            } else if (first_gen != ps.texture.texgen) {
                std.debug.print(
                    "[MATERIAL][WARN] material {s} has multiple stages with a texgen\n",
                    .{material.base.base.?.name.constSlice()},
                );
                break;
            }
        }
    }

    pub fn setDefaultText(material: *Material) error{}!bool {
        _ = material;

        @panic("Material.setDefaultText is not implemented");
    }

    pub fn freeData(material: *Material, allocator: std.mem.Allocator) void {
        if (material.stages) |stages| {
            const slice = stages[0..material.num_stages];
            for (slice) |*stage| {
                if (stage.texture.cinematic) |cinematic| {
                    // TODO: cinematic.deinit(allocator);
                    allocator.destroy(cinematic);
                    stage.texture.cinematic = null;
                }

                if (stage.new_stage) |new_stage| {
                    allocator.destroy(new_stage);
                    stage.new_stage = null;
                }

                if (stage.stencil_stage) |stencil_stage| {
                    allocator.destroy(stencil_stage);
                    stage.stencil_stage = null;
                }
            }

            allocator.free(slice);
            material.stages = null;
        }

        if (material.expression_registers) |expression_registers| {
            const slice = expression_registers[0..material.num_registers];
            allocator.free(slice);
            material.expression_registers = null;
        }

        if (material.constant_registers) |constant_registers| {
            const slice = constant_registers[0..material.num_registers];
            allocator.free(slice);
            material.constant_registers = null;
        }

        if (material.ops) |ops| {
            const slice = ops[0..material.num_ops];
            allocator.free(slice);
            material.ops = null;
        }
    }

    pub fn getDecalInfo(material: *const Material) DecalInfo {
        return material.decal_info;
    }

    pub fn coverage(material: *const Material) MaterialCoverage {
        return material.coverage;
    }

    pub fn isLod(material: *const Material) bool {
        return material.material_flags.lod1 or
            material.material_flags.lod2 or
            material.material_flags.lod3 or
            material.material_flags.lod4;
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

    const InfoParam = struct {
        name: []const u8,
        clear_solid: bool = false,
        surface_flags: SurfaceFlags = .{},
        content_flags: ContentFlags = .{},
    };
    const info_params = [_]InfoParam{
        .{ .name = "solid", .content_flags = .{ .solid = true } },
        .{ .name = "water", .clear_solid = true, .content_flags = .{ .water = true } },
        .{ .name = "playerclip", .content_flags = .{ .playerclip = true } },
        .{ .name = "monsterclip", .content_flags = .{ .monsterclip = true } },
        .{ .name = "moveableclip", .content_flags = .{ .moveableclip = true } },
        .{ .name = "ikclip", .content_flags = .{ .ikclip = true } },
        .{ .name = "blood", .content_flags = .{ .blood = true } },
        .{ .name = "trigger", .content_flags = .{ .trigger = true } },
        .{ .name = "aassolid", .content_flags = .{ .aas_solid = true } },
        .{ .name = "flashlight_trigger", .content_flags = .{ .flashlight_trigger = true } },
        .{ .name = "nonsolid", .clear_solid = true },
        .{ .name = "nullNormal", .surface_flags = .{ .nullnormal = true } },
    };

    fn checkSurfaceParam(token: *const Token) ?InfoParam {
        return for (info_params) |info| {
            if (token.ieql(info.name)) {
                break info;
            }
        } else null;
    }

    fn parseSort(material: *Material, lexer: *Lexer) error{}!void {
        _ = material;
        _ = lexer;
        @panic("not implemented");
    }

    fn parseStereoEye(material: *Material, lexer: *Lexer) error{}!void {
        _ = material;
        _ = lexer;
        @panic("not implemented");
    }

    fn parseDeform(material: *Material, lexer: *Lexer) error{}!void {
        _ = material;
        _ = lexer;
        @panic("not implemented");
    }

    fn parseDecalInfo(material: *Material, lexer: *Lexer) error{}!void {
        _ = material;
        _ = lexer;
        @panic("not implemented");
    }

    const ParseStageError =
        image_program.ParseImageProgramError ||
        render_prog_manager.RenderProgManager.LoadShaderError ||
        Lexer.ReadOnLineError ||
        Lexer.ReadTokenError ||
        Lexer.ParseIntError ||
        Lexer.ParseFloatError;
    fn parseStage(
        material: *Material,
        lexer: *Lexer,
        trp_default: TextureRepeat,
        allocator: std.mem.Allocator,
    ) ParseStageError!void {
        if (material.num_stages >= max_shader_stages) {
            material.material_flags.defaulted = true;
            std.debug.print(
                "[MATERIAL][WARN] {s} exceeded {} stages\n",
                .{
                    material.base.base.?.name.constSlice(),
                    max_shader_stages,
                },
            );
        }

        var texture_filter: TextureFilter = .default;
        var texture_repeat: TextureRepeat = trp_default;
        var texture_usage: TextureUsage = .default;
        var cube_map: CubeFiles = .@"2d";

        var image_name = std.BoundedArray(u8, image.max_image_name)
            .init(0) catch unreachable;

        var new_stage = std.mem.zeroes(NewShaderStage);
        new_stage.program = -1;

        var stencil_stage = std.mem.zeroes(StencilStage);

        const ss = &material.pd.?.parse_stages[material.num_stages];
        const ts = &ss.texture;

        material.clearStage(ss);

        var token = Token{};
        token.initEmpty();
        defer token.deinit();

        var cube_map_size: u32 = 0;

        while (true) {
            if (material.material_flags.defaulted) return;

            lexer.readToken(&token) catch {
                material.material_flags.defaulted = true;
                return;
            };

            if (token.eql("}")) break;

            if (token.ieql("name")) {
                try lexer.skipRestOfLine();
                continue;
            }

            if (token.ieql("blend")) {
                material.parseBlend(lexer, ss);
                continue;
            }

            if (token.ieql("map")) {
                const str = try image_program.parsePastImageProgram(lexer);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                continue;
            }

            if (token.ieql("remoteRenderMap")) {
                ts.dynamic = .remote_render;
                ts.width = @intCast(try lexer.parseInt());
                ts.height = @intCast(try lexer.parseInt());
                continue;
            }

            if (token.ieql("mirrorRenderMap")) {
                ts.dynamic = .mirror_render;
                ts.width = @intCast(try lexer.parseInt());
                ts.height = @intCast(try lexer.parseInt());
                ts.texgen = .screen;
                continue;
            }

            if (token.ieql("xrayRenderMap")) {
                ts.dynamic = .xray_render;
                ts.width = @intCast(try lexer.parseInt());
                ts.height = @intCast(try lexer.parseInt());
                ts.texgen = .screen;
                continue;
            }

            if (token.ieql("guiRenderMap")) {
                ts.dynamic = .gui_render;
                ts.width = @intCast(try lexer.parseInt());
                ts.height = @intCast(try lexer.parseInt());
                continue;
            }

            if (token.ieql("screen")) {
                ts.texgen = .screen;
                continue;
            }

            if (token.ieql("screen2")) {
                ts.texgen = .screen2;
                continue;
            }

            if (token.ieql("glassWarp")) {
                ts.texgen = .glasswarp;
                continue;
            }

            if (token.ieql("videomap")) {
                lexer.readToken(&token) catch {
                    std.debug.print(
                        "missing parameter for 'videomap' keyword in material {s}\n",
                        .{material.base.base.?.name.constSlice()},
                    );
                    continue;
                };

                var loop = false;
                if (token.ieql("loop")) {
                    loop = true;

                    lexer.readToken(&token) catch {
                        std.debug.print(
                            "missing parameter for 'videomap' keyword in material {s}\n",
                            .{material.base.base.?.name.constSlice()},
                        );
                        continue;
                    };
                }

                const cinematic = try Cinematic.create(allocator);
                errdefer allocator.destroy(cinematic);
                try cinematic.initFromFile(token.slice(), loop, null);

                ts.cinematic = cinematic;

                continue;
            }

            if (token.ieql("soundmap")) {
                lexer.readToken(&token) catch {
                    std.debug.print(
                        "missing parameter for 'soundmap' keyword in material {s}\n",
                        .{material.base.base.?.name.constSlice()},
                    );
                    continue;
                };

                const cinematic = try SoundWindow.create(allocator);
                errdefer allocator.destroy(cinematic);
                try cinematic.base.initFromFile(token.slice(), true, null);

                ts.cinematic = &cinematic.base;

                continue;
            }

            if (token.ieql("cubeMap")) {
                const str = try image_program.parsePastImageProgram(lexer);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                cube_map = .native;
                continue;
            }

            if (token.ieql("cubeMapSingle")) {
                const str = try image_program.parsePastImageProgram(lexer);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                cube_map = .single;
                texture_usage = .highquality_cube;
                continue;
            }

            if (token.ieql("cubeMapSize")) {
                cube_map_size = @intCast(try lexer.parseInt());
                continue;
            }

            if (token.ieql("cameraCubeMap")) {
                const str = try image_program.parsePastImageProgram(lexer);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                cube_map = .camera;
                continue;
            }

            if (token.ieql("quakeCubeMap")) {
                const str = try image_program.parsePastImageProgram(lexer);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                cube_map = .quake1;
                continue;
            }

            if (token.ieql("ignoreAlphaTest")) {
                ss.ignore_alpha_test = true;
                continue;
            }

            if (token.ieql("nearest")) {
                texture_filter = .nearest;
                continue;
            }

            if (token.ieql("linear")) {
                texture_filter = .linear;
                continue;
            }

            if (token.ieql("clamp")) {
                texture_repeat = .clamp;
                continue;
            }

            if (token.ieql("noclamp")) {
                texture_repeat = .repeat;
                continue;
            }

            if (token.ieql("zeroclamp")) {
                texture_repeat = .clamp_to_zero;
                continue;
            }

            if (token.ieql("alphazeroclamp")) {
                texture_repeat = .clamp_to_zero_alpha;
                continue;
            }

            if (token.ieql("forceHighQuality")) {
                continue;
            }

            if (token.ieql("highquality")) {
                continue;
            }

            if (token.ieql("uncompressedCubeMap")) {
                texture_usage = .highquality_cube;
                continue;
            }

            if (token.ieql("nopicmip")) {
                continue;
            }

            if (token.ieql("vertexColor")) {
                ss.vertex_color = .modulate;
                continue;
            } else if (token.ieql("privatePolygonOffset")) {
                lexer.readTokenOnLine(&token) catch {
                    ss.private_polygon_offset = 1;
                    continue;
                };

                try lexer.unreadToken(&token);
                ss.private_polygon_offset = try lexer.parseFloat();
                continue;
            }

            if (token.ieql("texGen")) {
                try lexer.readToken(&token);

                if (token.ieql("normal")) {
                    ts.texgen = .diffuse_cube;
                } else if (token.ieql("reflect")) {
                    ts.texgen = .reflect_cube;
                } else if (token.ieql("skybox")) {
                    ts.texgen = .skybox_cube;
                } else if (token.ieql("wobbleSky")) {
                    ts.texgen = .wobblesky_cube;
                } else {
                    std.debug.print(
                        "bad texgen '{s}' in material {s}\n",
                        .{
                            token.slice(),
                            material.base.base.?.name.constSlice(),
                        },
                    );
                    material.material_flags.defaulted = true;
                }
                continue;
            }

            if (token.ieql("scroll") or token.ieql("translate")) {
                @panic("not implemented");
            }

            if (token.ieql("scale")) {
                @panic("not implemented");
            }

            if (token.ieql("centerScale")) {
                @panic("not implemented");
            }

            if (token.ieql("shear")) {
                @panic("not implemented");
            }

            if (token.ieql("rotate")) {
                @panic("not implemented");
            }

            if (token.ieql("maskRed")) {
                ss.draw_state_bits |= gl_state.GLS_REDMASK;
                continue;
            }

            if (token.ieql("maskGreen")) {
                ss.draw_state_bits |= gl_state.GLS_GREENMASK;
                continue;
            }

            if (token.ieql("maskBlue")) {
                ss.draw_state_bits |= gl_state.GLS_BLUEMASK;
                continue;
            }

            if (token.ieql("maskAlpha")) {
                ss.draw_state_bits |= gl_state.GLS_ALPHAMASK;
                continue;
            }

            if (token.ieql("maskColor")) {
                ss.draw_state_bits |= gl_state.GLS_COLORMASK;
                continue;
            }

            if (token.ieql("maskDepth")) {
                ss.draw_state_bits |= gl_state.GLS_DEPTHMASK;
                continue;
            }

            if (token.ieql("alphaTest")) {
                ss.has_alpha_test = true;
                ss.alpha_test_register = @intCast(material.parseExpression(lexer));
                material.coverage = .perforated;
                continue;
            }

            if (token.ieql("colored")) {
                ss.color.registers[0] = @intFromEnum(ExpRegisters.parm0);
                ss.color.registers[1] = @intFromEnum(ExpRegisters.parm1);
                ss.color.registers[2] = @intFromEnum(ExpRegisters.parm2);
                ss.color.registers[3] = @intFromEnum(ExpRegisters.parm3);
                material.pd.?.registers_are_constant = false;
                continue;
            }

            if (token.ieql("color")) {
                ss.color.registers[0] = @intCast(material.parseExpression(lexer));
                material.matchTokenOrDefaulted(lexer, ",");
                ss.color.registers[1] = @intCast(material.parseExpression(lexer));
                material.matchTokenOrDefaulted(lexer, ",");
                ss.color.registers[2] = @intCast(material.parseExpression(lexer));
                material.matchTokenOrDefaulted(lexer, ",");
                ss.color.registers[3] = @intCast(material.parseExpression(lexer));
                continue;
            }

            if (token.ieql("red")) {
                ss.color.registers[0] = @intCast(material.parseExpression(lexer));
                continue;
            }

            if (token.ieql("green")) {
                ss.color.registers[1] = @intCast(material.parseExpression(lexer));
                continue;
            }

            if (token.ieql("blue")) {
                ss.color.registers[2] = @intCast(material.parseExpression(lexer));
                continue;
            }

            if (token.ieql("alpha")) {
                ss.color.registers[3] = @intCast(material.parseExpression(lexer));
                continue;
            }

            if (token.ieql("rgb")) {
                const expression: u32 = @intCast(material.parseExpression(lexer));

                ss.color.registers[0] = expression;
                ss.color.registers[1] = expression;
                ss.color.registers[2] = expression;
                continue;
            }

            if (token.ieql("rgba")) {
                const expression: u32 = @intCast(material.parseExpression(lexer));

                ss.color.registers[0] = expression;
                ss.color.registers[1] = expression;
                ss.color.registers[2] = expression;
                ss.color.registers[3] = expression;
                continue;
            }

            if (token.ieql("if")) {
                ss.condition_register = @intCast(material.parseExpression(lexer));
                continue;
            }

            {
                const macros = &.{
                    &.{ "USE_GPU_SKINNING", "0" },
                };
                if (token.ieql("program")) {
                    try lexer.readTokenOnLine(&token);
                    const find_fragment_shader_result = render_prog_manager.instance.findShader(
                        token.slice(),
                        Shader.Stage.fragment,
                        "",
                        macros,
                        false,
                    );
                    if (find_fragment_shader_result) |shader_index| {
                        new_stage.fragment_program = @intCast(shader_index);
                    } else |_| {
                        new_stage.fragment_program = -1;
                    }

                    const find_vertex_shader_result = render_prog_manager.instance.findShader(
                        token.slice(),
                        Shader.Stage.vertex,
                        "",
                        macros,
                        false,
                    );
                    if (find_vertex_shader_result) |shader_index| {
                        new_stage.vertex_program = @intCast(shader_index);
                    } else |_| {
                        new_stage.vertex_program = -1;
                    }
                    continue;
                }

                if (token.ieql("fragmentProgram")) {
                    try lexer.readTokenOnLine(&token);
                    const find_shader_result = render_prog_manager.instance.findShader(
                        token.slice(),
                        Shader.Stage.fragment,
                        "",
                        macros,
                        false,
                    );
                    if (find_shader_result) |shader_index| {
                        new_stage.fragment_program = @intCast(shader_index);
                    } else |_| {
                        new_stage.fragment_program = -1;
                    }
                    continue;
                }

                if (token.ieql("vertexProgram")) {
                    try lexer.readTokenOnLine(&token);
                    const find_shader_result = render_prog_manager.instance.findShader(
                        token.slice(),
                        Shader.Stage.vertex,
                        "",
                        macros,
                        false,
                    );
                    if (find_shader_result) |shader_index| {
                        new_stage.vertex_program = @intCast(shader_index);
                    } else |_| {
                        new_stage.vertex_program = -1;
                    }
                    continue;
                }
            }

            if (token.ieql("vertexParm2")) {
                try material.parseVertexParam2(lexer, &new_stage);
                continue;
            }

            if (token.ieql("vertexParm")) {
                try material.parseVertexParam(lexer, &new_stage);
                continue;
            }

            if (token.ieql("stencil")) {
                try material.parseStencil(lexer, &stencil_stage);
                const stencil_stage_ptr = try allocator.create(StencilStage);
                stencil_stage_ptr.* = stencil_stage;

                ss.stencil_stage = stencil_stage_ptr;
                continue;
            }

            std.debug.print(
                "unknown token {s} in material {s}\n",
                .{
                    token.slice(),
                    material.base.base.?.name.constSlice(),
                },
            );
            material.material_flags.defaulted = true;
            return;
        }

        if (new_stage.fragment_program != -1 and new_stage.vertex_program != -1) {
            const program_index = try render_prog_manager.instance.findProgramOrCreate(
                material.base.base.?.name.constSlice(),
                @intCast(new_stage.vertex_program),
                @intCast(new_stage.fragment_program),
                .POST_PROCESS_INGAME,
            );
            new_stage.program = @intCast(program_index);

            const stage = try allocator.create(NewShaderStage);
            stage.* = new_stage;

            ss.new_stage = stage;
        }

        material.num_stages += 1;

        if (texture_usage == .default) {
            @panic("not implemented");
        }

        if (texture_usage == .diffuse and ss.has_alpha_test) {
            @panic("not implemented");
        }

        if (image_name.constSlice().len != 0) {
            @panic("not implemented");
        } else if (ts.cinematic == null and
            ts.dynamic == .static and
            ss.new_stage == null)
        {
            std.debug.print(
                "material {s} had stage with no image\n",
                .{material.base.base.?.name.constSlice()},
            );
            ts.image = image_manager.instance.defaultImage;
        }
    }

    fn clearStage(material: *Material, shader_stage: *ShaderStage) void {
        shader_stage.draw_state_bits = 0;
        shader_stage.condition_register = material.getExpressionConstant(1) catch 0;

        const constant = material.getExpressionConstant(1) catch 0;
        shader_stage.color.registers[0] = constant;
        shader_stage.color.registers[1] = constant;
        shader_stage.color.registers[2] = constant;
        shader_stage.color.registers[3] = constant;
    }

    fn getExpressionConstant(material: *Material, f: f32) error{MaxRegistersHit}!u32 {
        {
            var i = ExpRegisters.num_predefined;
            while (i < material.num_registers) : (i += 1) {
                if (!material.pd.?.register_is_temporary[i] and
                    material.pd.?.shader_registers[i] == f)
                {
                    return @intCast(i);
                }
            }
        }

        if (material.num_registers == max_expression_registers) {
            material.material_flags.defaulted = true;
            return error.MaxRegistersHit;
        }

        const i = material.num_registers;
        material.pd.?.register_is_temporary[i] = false;
        material.pd.?.shader_registers[i] = f;
        material.num_registers += 1;

        return i;
    }

    fn addImplicitStages(material: *Material, trp_default: TextureRepeat) void {
        _ = material;
        _ = trp_default;
        @panic("not implemented");
    }

    const top_priority = 4;
    fn parseExpression(material: *const Material, lexer: *Lexer) i32 {
        return material.parseExpressionPriority(lexer, top_priority);
    }

    fn parseExpressionPriority(material: *const Material, lexer: *Lexer, priority: i32) i32 {
        _ = material;
        _ = lexer;
        _ = priority;

        @panic("not implemented");
    }

    fn sortInteractionStages(material: *Material) void {
        _ = material;
        @panic("not implemented");
    }

    fn parseStencil(material: *Material, lexer: *Lexer, stage: *StencilStage) error{}!void {
        _ = material;
        _ = lexer;
        _ = stage;

        @panic("not implemented");
    }

    fn parseVertexParam2(material: *Material, lexer: *Lexer, stage: *NewShaderStage) error{}!void {
        _ = material;
        _ = lexer;
        _ = stage;

        @panic("not implemented");
    }

    fn parseVertexParam(material: *Material, lexer: *Lexer, stage: *NewShaderStage) error{}!void {
        _ = material;
        _ = lexer;
        _ = stage;

        @panic("not implemented");
    }

    fn parseBlend(material: *Material, lexer: *Lexer, stage: *ShaderStage) void {
        var token = Token{};
        token.initEmpty();
        defer token.deinit();

        lexer.readToken(&token) catch return;

        if (token.ieql("blend")) {
            stage.draw_state_bits = gl_state.GLS_SRCBLEND_SRC_ALPHA | gl_state.GLS_DSTBLEND_ONE_MINUS_SRC_ALPHA;
            return;
        }
        if (token.ieql("add")) {
            stage.draw_state_bits = gl_state.GLS_SRCBLEND_ONE | gl_state.GLS_DSTBLEND_ONE;
            return;
        }
        if (token.ieql("filter") or token.ieql("modulate")) {
            stage.draw_state_bits = gl_state.GLS_SRCBLEND_DST_COLOR | gl_state.GLS_DSTBLEND_ZERO;
            return;
        }
        if (token.ieql("none")) {
            // none is used when defining an alpha mask that doesn't draw
            stage.draw_state_bits = gl_state.GLS_SRCBLEND_ZERO | gl_state.GLS_DSTBLEND_ONE;
            return;
        }
        if (token.ieql("bumpmap") or token.ieql("normalmap")) {
            stage.lighting = .bump;
            return;
        }
        if (token.ieql("diffusemap") or token.ieql("basecolormap")) {
            stage.lighting = .diffuse;
            return;
        }
        if (token.ieql("specularmap") or token.ieql("rmaomap")) {
            stage.lighting = .specular;
            return;
        }

        const src_blend = material.nameToSrcBlendMode(&token);
        material.matchTokenOrDefaulted(lexer, ",");

        lexer.readToken(&token) catch return;

        const dst_blend = material.nameToDstBlendMode(&token);

        stage.draw_state_bits = src_blend | dst_blend;
    }

    fn nameToDstBlendMode(material: *Material, name: *const Token) u64 {
        if (name.ieql("GL_ONE")) {
            return gl_state.GLS_DSTBLEND_ONE;
        } else if (name.ieql("GL_ZERO")) {
            return gl_state.GLS_DSTBLEND_ZERO;
        } else if (name.ieql("GL_SRC_ALPHA")) {
            return gl_state.GLS_DSTBLEND_SRC_ALPHA;
        } else if (name.ieql("GL_ONE_MINUS_SRC_ALPHA")) {
            return gl_state.GLS_DSTBLEND_ONE_MINUS_SRC_ALPHA;
        } else if (name.ieql("GL_DST_ALPHA")) {
            return gl_state.GLS_DSTBLEND_DST_ALPHA;
        } else if (name.ieql("GL_ONE_MINUS_DST_ALPHA")) {
            return gl_state.GLS_DSTBLEND_ONE_MINUS_DST_ALPHA;
        } else if (name.ieql("GL_SRC_COLOR")) {
            return gl_state.GLS_DSTBLEND_SRC_COLOR;
        } else if (name.ieql("GL_ONE_MINUS_SRC_COLOR")) {
            return gl_state.GLS_DSTBLEND_ONE_MINUS_SRC_COLOR;
        }

        material.material_flags.defaulted = true;

        return gl_state.GLS_DSTBLEND_ONE;
    }

    fn nameToSrcBlendMode(material: *Material, name: *const Token) u64 {
        if (name.ieql("GL_ONE")) {
            return gl_state.GLS_SRCBLEND_ONE;
        } else if (name.ieql("GL_ZERO")) {
            return gl_state.GLS_SRCBLEND_ZERO;
        } else if (name.ieql("GL_DST_COLOR")) {
            return gl_state.GLS_SRCBLEND_DST_COLOR;
        } else if (name.ieql("GL_ONE_MINUS_DST_COLOR")) {
            return gl_state.GLS_SRCBLEND_ONE_MINUS_DST_COLOR;
        } else if (name.ieql("GL_SRC_ALPHA")) {
            return gl_state.GLS_SRCBLEND_SRC_ALPHA;
        } else if (name.ieql("GL_ONE_MINUS_SRC_ALPHA")) {
            return gl_state.GLS_SRCBLEND_ONE_MINUS_SRC_ALPHA;
        } else if (name.ieql("GL_DST_ALPHA")) {
            return gl_state.GLS_SRCBLEND_DST_ALPHA;
        } else if (name.ieql("GL_ONE_MINUS_DST_ALPHA")) {
            return gl_state.GLS_SRCBLEND_ONE_MINUS_DST_ALPHA;
        } else if (name.ieql("GL_SRC_ALPHA_SATURATE")) {
            std.debug.assert(false);
            return gl_state.GLS_SRCBLEND_SRC_ALPHA;
        }

        material.material_flags.defaulted = true;

        return gl_state.GLS_SRCBLEND_ONE;
    }

    fn matchTokenOrDefaulted(material: *Material, lexer: *Lexer, match: []const u8) void {
        lexer.expectTokenString(match) catch {
            material.material_flags.defaulted = true;
            return;
        };
    }

    pub fn getNumRegisters(material: *const Material) usize {
        return material.num_registers;
    }

    pub fn getNumStages(material: *const Material) usize {
        return material.num_stages;
    }

    pub fn lightCastsShadows(material: *const Material) bool {
        return material.material_flags.forceshadows or
            (!material.fog_light and
            !material.ambient_light and
            !material.blend_light and
            !material.material_flags.noshadows);
    }

    pub fn surfaceCastsShadow(material: *const Material) bool {
        return material.material_flags.forceshadows or
            !material.material_flags.noshadows;
    }

    pub fn isDrawn(material: *const Material) bool {
        return material.num_stages > 0 or
            material.entity_gui != 0 or
            material.gui != null;
    }

    pub fn deformType(material: *const Material) Deform {
        return material.deform;
    }

    pub fn receivesLighting(material: *const Material) bool {
        return material.num_ambient_stages != material.num_stages;
    }

    pub fn addReference(material: *Material) void {
        material.ref_count += 1;

        if (material.stages) |stages| {
            const slice = stages[0..material.num_stages];
            for (slice) |*stage| {
                if (stage.texture.image) |image_ptr| {
                    image_ptr.ref_count += 1;
                }
            }
        }
    }

    pub fn isBlendLight(material: *const Material) bool {
        return material.blend_light;
    }

    pub fn isFogLight(material: *const Material) bool {
        return material.fog_light;
    }

    pub fn testMaterialFlag(material: *const Material, flag: Flags) bool {
        const material_flags_u32: u32 = @bitCast(material.material_flags);
        const flags_u32: u32 = @bitCast(flag);
        return (material_flags_u32 & flags_u32) != 0;
    }
};
