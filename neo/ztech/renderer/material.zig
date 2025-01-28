const std = @import("std");
const idlib = @import("../idlib.zig");
const decl = @import("../framework/decl_manager.zig");
const DeclLocal = decl.DeclLocal;
const DeclSkin = @import("common.zig").DeclSkin;
const ViewDef = @import("common.zig").ViewDef;
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
const render_entity = @import("render_entity.zig");
const string = @import("../string.zig");
const Allocator = std.mem.Allocator;

const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;
const CFlags = cvar.CVarFlags;

pub var r_use_constant_materials = CVar.init(
    "r_useConstantMaterials",
    "1",
    CFlags.renderer | CFlags.bool,
    "use pre-calculated material registers if possible",
);

pub const max_global_shader_params: usize = 12;

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

    pub fn create(allocator: Allocator) Allocator.Error!*SoundWindow {
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
    a: u32,
    b: u32,
    c: u32,
};

pub const ExpRegisters = enum {
    time,
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
    pub const subview: f32 = -3;
    pub const gui: f32 = -2;
    pub const bad: f32 = -1;
    pub const @"opaque": f32 = 0;
    pub const portal_sky: f32 = 1;
    pub const decal: f32 = 2;
    pub const far: f32 = 3;
    pub const medium: f32 = 4;
    pub const close: f32 = 5;
    pub const almost_nearest: f32 = 6;
    pub const nearest: f32 = 7;
    pub const post_process: f32 = 100;
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
    desc: idlib.Str = .{},
    render_bump: idlib.Str = .{},
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
    sort: f32 = MaterialSort.bad,
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
    editor_image_name: idlib.Str = .{},
    editor_image: ?*Image = null,
    editor_alpha: f32 = 1,
    suppress_in_subview: bool = false,
    portal_sky: bool = false,
    ref_count: u32 = 0,

    extern fn c_material_isLodVisibleForDistance(*const Material, f32, f32) bool;

    pub fn getStages(material: *const Material) []const ShaderStage {
        return if (material.stages) |stages|
            stages[0..material.num_stages]
        else
            &.{};
    }

    pub fn init(self: *Material) void {
        self.* = .{};
    }

    pub const ParseError =
        EvaluateRegistersError ||
        Allocator.Error ||
        ParseMaterialError ||
        Lexer.LoadMemoryError;

    pub fn parse(
        material: *Material,
        definition_text: []const u8,
        allow_binary_version: bool,
        allocator: Allocator,
    ) ParseError!void {
        _ = allow_binary_version;

        var lexer = Lexer{ .flags = decl.decl_lexer_flags };
        defer lexer.deinit(allocator);

        const decl_local = material.base.base.?;

        try lexer.loadMemory(
            definition_text,
            decl_local.filename() orelse "*invalid*",
            decl_local.source_line,
            allocator,
        );

        try lexer.skipUntilString("{", allocator);

        var parsing_data = std.mem.zeroes(MtrParsingData);
        material.pd = &parsing_data;
        defer material.pd = null;

        try material.parseMaterial(&lexer, allocator);

        // count non-lit stages
        {
            material.num_ambient_stages = 0;
            for (0..material.num_stages) |i| {
                if (material.pd.?.parse_stages[i].lighting == .ambient) {
                    material.num_ambient_stages += 1;
                }
            }
        }

        // check if there is a subview stage
        if (material.sort == MaterialSort.subview) {
            material.has_subview = true;
        } else {
            material.has_subview = false;
            for (0..material.num_stages) |i| {
                if (material.pd.?.parse_stages[i].texture.dynamic != .static) {
                    material.has_subview = true;
                    break;
                }
            }
        }

        // automatically determine coverage if not explicitly set
        if (material.coverage == .bad) {
            const bits = material.pd.?.parse_stages[0].draw_state_bits;
            const dst_blend_bits = bits & gl_state.GLS_DSTBLEND_BITS;
            const src_blend_bits = bits & gl_state.GLS_SRCBLEND_BITS;

            material.coverage = if (material.num_stages == 0)
                .translucent
            else if (material.num_stages != material.num_ambient_stages)
                .@"opaque"
            else if (dst_blend_bits != gl_state.GLS_DSTBLEND_ZERO or
                src_blend_bits == gl_state.GLS_SRCBLEND_DST_COLOR or
                src_blend_bits == gl_state.GLS_SRCBLEND_ONE_MINUS_DST_COLOR or
                src_blend_bits == gl_state.GLS_SRCBLEND_DST_ALPHA or
                src_blend_bits == gl_state.GLS_SRCBLEND_ONE_MINUS_DST_ALPHA)
                .translucent
            else
                .@"opaque";
        }

        if (material.coverage == .translucent) {
            material.material_flags.noshadows = true;
            material.editor_alpha = 0.5;
        } else {
            material.content_flags.@"opaque" = true;
            material.editor_alpha = 1;
        }

        if (material.sort == MaterialSort.bad) {
            material.sort = if (material.material_flags.polygonoffset)
                MaterialSort.decal
            else if (material.coverage == .translucent)
                MaterialSort.medium
            else
                MaterialSort.@"opaque";
        }

        for (0..material.num_stages) |i| stages: {
            const ps = &material.pd.?.parse_stages[i];
            if (ps.texture.image == image_manager.instance.originalCurrentRenderImage) {
                if (material.sort != MaterialSort.portal_sky) {
                    material.sort = MaterialSort.post_process;
                    material.coverage = .translucent;
                }
                break :stages;
            }

            if (ps.new_stage) |new_stage| {
                const images = new_stage.fragment_program_images[0..new_stage.num_fragment_program_images];
                for (images) |image_| {
                    if (image_ == image_manager.instance.originalCurrentRenderImage) {
                        if (material.sort != MaterialSort.portal_sky) {
                            material.sort = MaterialSort.post_process;
                            material.coverage = .translucent;
                        }

                        break :stages;
                    }
                }
            }
        }

        for (0..material.num_stages) |i| {
            const ps = &material.pd.?.parse_stages[i];

            if (material.sort == MaterialSort.post_process) {
                ps.draw_state_bits |= gl_state.GLS_DEPTHFUNC_LESS;
            } else if (material.coverage == .translucent or ps.ignore_alpha_test) {
                ps.draw_state_bits |= gl_state.GLS_DEPTHFUNC_LESS | gl_state.GLS_DEPTHMASK;
            } else {
                ps.draw_state_bits |= gl_state.GLS_DEPTHFUNC_EQUAL | gl_state.GLS_DEPTHMASK;
            }
        }

        if (material.pd.?.force_overlays) {
            material.allow_overlays = true;
        } else if (!material.isDrawn() or
            material.coverage != .@"opaque" or
            material.surface_flags.noimpact)
        {
            material.allow_overlays = false;
        }

        if (material.num_stages > 0) {
            const stages = try allocator.alloc(ShaderStage, material.num_stages);
            errdefer allocator.free(stages);
            @memcpy(
                stages,
                material.pd.?.parse_stages[0..material.num_stages],
            );

            material.stages = stages.ptr;
            material.num_stages = @intCast(stages.len);
        }

        if (material.num_ops > 0) {
            const ops = try allocator.alloc(ExpOp, material.num_ops);
            errdefer allocator.free(ops);
            @memcpy(
                ops,
                material.pd.?.shader_ops[0..material.num_ops],
            );
            material.ops = ops.ptr;
            material.num_ops = @intCast(ops.len);
        }

        if (material.num_registers > 0) {
            const expression_regs = try allocator.alloc(f32, material.num_registers);
            errdefer allocator.free(expression_regs);
            @memcpy(
                expression_regs,
                material.pd.?.shader_registers[0..material.num_registers],
            );
            material.expression_registers = expression_regs.ptr;
            material.num_registers = @intCast(expression_regs.len);
        }

        try material.checkForConstantRegisters(allocator);
        material.setFastPathImages() catch {
            material.fast_path_bump_image = null;
            material.fast_path_diffuse_image = null;
            material.fast_path_specular_image = null;
        };

        if (material.material_flags.defaulted) {
            try material.makeDefault(allocator);
            return;
        }
    }

    fn setFastPathImages(material: *Material) error{NonTrivial}!void {
        material.fast_path_bump_image = null;
        material.fast_path_diffuse_image = null;
        material.fast_path_specular_image = null;

        const constant_regs = if (material.constant_registers) |regs_ptr|
            regs_ptr[0..material.num_registers]
        else
            return;

        const stages = if (material.stages) |stages_ptr|
            stages_ptr[0..material.num_stages]
        else
            return;

        for (stages) |*stage| {
            if (stage.texture.has_matrix) return error.NonTrivial;
            if (stage.vertex_color != .ignore) return error.NonTrivial;

            for (&stage.color.registers) |reg_index| {
                if (@abs(constant_regs[reg_index] - 1) > 0.1) return error.NonTrivial;
            }

            switch (stage.lighting) {
                .coverage, .ambient => {},
                .bump => {
                    if (material.fast_path_bump_image != null) return error.NonTrivial;
                    material.fast_path_bump_image = stage.texture.image;
                },
                .diffuse => {
                    if (material.fast_path_diffuse_image != null) return error.NonTrivial;
                    material.fast_path_diffuse_image = stage.texture.image;
                },
                .specular => {
                    if (material.fast_path_specular_image != null) return error.NonTrivial;
                    material.fast_path_specular_image = stage.texture.image;
                },
            }
        }

        if (material.fast_path_bump_image == null or material.fast_path_diffuse_image == null)
            return error.NonTrivial;

        if (material.fast_path_specular_image == null) {
            material.fast_path_specular_image = image_manager.instance.blackImage;
        }
    }

    fn makeDefault(
        material: *Material,
        allocator: Allocator,
    ) DeclLocal.MakeDefaultError!void {
        const decl_local = material.base.base.?;
        const rt_decl_type = decl.instance.getRuntimeType(decl_local.decl_type);
        try decl_local.makeDefault(rt_decl_type, allocator);
    }

    fn checkForConstantRegisters(material: *Material, allocator: Allocator) EvaluateRegistersError!void {
        std.debug.assert(material.constant_registers == null);

        if (!material.pd.?.registers_are_constant) return;
        if (r_use_constant_materials.integer_value == 0) return;

        const constant_registers = try allocator.alloc(f32, material.num_registers);
        for (constant_registers) |*reg| reg.* = 0;

        var shader_params = std.mem.zeroes([render_entity.max_entity_shader_params]f32);
        var view_def = std.mem.zeroes(ViewDef);

        try material.evaluateRegisters(
            constant_registers,
            &shader_params,
            &view_def.renderView.shader_params,
            0,
            null,
            allocator,
        );
    }

    const ParseMaterialError =
        AddImplicitStagesError ||
        ParseStageError ||
        ui_manager.UserInterfaceManager.FindGuiOrLoadError ||
        Lexer.ReadTokenError ||
        Lexer.ReadOnLineError;
    fn parseMaterial(
        material: *Material,
        lexer: *Lexer,
        allocator: Allocator,
    ) ParseMaterialError!void {
        var token = Token{};
        defer token.deinit(allocator);

        material.num_ops = 0;
        material.num_registers = ExpRegisters.num_predefined;
        for (0..ExpRegisters.num_predefined) |i| {
            material.pd.?.register_is_temporary[i] = true;
        }
        material.num_stages = 0;
        material.pd.?.registers_are_constant = true;

        var trp_default: TextureRepeat = .repeat;

        while (true) {
            if (material.material_flags.defaulted) return;

            lexer.readToken(&token, allocator) catch {
                material.material_flags.defaulted = true;
                return;
            };

            // end of definition
            if (token.eql("}")) {
                break;
            } else if (token.ieql("qer_editorimage")) {
                try lexer.readTokenOnLine(&token, allocator);
                try material.editor_image_name.assignSlice(token.slice(), allocator);
                try lexer.skipRestOfLine(allocator);
            } else if (token.ieql("description")) {
                try lexer.readTokenOnLine(&token, allocator);
                try material.desc.assignSlice(token.slice(), allocator);
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
                lexer.readTokenOnLine(&token, allocator) catch {
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
                material.sort = MaterialSort.subview;
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
                const str = try image_program.parse(lexer, allocator);
                material.light_falloff_image = try image_manager.instance.imageFromFile(
                    str,
                    .default,
                    .clamp,
                    .default,
                    .@"2d",
                    0,
                    allocator,
                );
            } else if (token.ieql("guisurf")) {
                try lexer.readTokenOnLine(&token, allocator);

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
                try lexer.readTokenOnLine(&token, allocator);
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
                try lexer.parseRestOfLine(&material.render_bump, allocator);
            } else if (token.ieql("diffusemap") or token.ieql("basecolormap")) {
                const str = try image_program.parse(lexer, allocator);
                // TODO: free str
                var temp_lexer = Lexer{
                    .flags = .{
                        .no_fatal_errors = true,
                        .no_string_concat = true,
                        .no_string_escape_chars = true,
                        .allow_path_names = true,
                    },
                };
                defer temp_lexer.deinit(allocator);

                var buffer: [1024]u8 = undefined;
                const fmt = "blend diffusemap\nmap {s}\n}}\n";
                const definition_text = std.fmt.bufPrint(&buffer, fmt, .{str}) catch unreachable;

                try temp_lexer.loadMemory(
                    definition_text,
                    "diffusemap",
                    0,
                    allocator,
                );

                try material.parseStage(&temp_lexer, trp_default, allocator);
            } else if (token.ieql("specularmap")) {
                const str = try image_program.parse(lexer, allocator);
                // TODO: free str
                var temp_lexer = Lexer{
                    .flags = .{
                        .no_fatal_errors = true,
                        .no_string_concat = true,
                        .no_string_escape_chars = true,
                        .allow_path_names = true,
                    },
                };
                defer temp_lexer.deinit(allocator);

                var buffer: [1024]u8 = undefined;
                const fmt = "blend specularmap\nmap {s}\n}}\n";
                const definition_text = std.fmt.bufPrint(&buffer, fmt, .{str}) catch unreachable;

                try temp_lexer.loadMemory(
                    definition_text,
                    "specularmap",
                    0,
                    allocator,
                );

                try material.parseStage(&temp_lexer, trp_default, allocator);
            } else if (token.ieql("rmaomap") or token.ieql("reflectionmap") or token.ieql("pbrmap")) {
                const str = try image_program.parse(lexer, allocator);
                // TODO: free str
                var temp_lexer = Lexer{
                    .flags = .{
                        .no_fatal_errors = true,
                        .no_string_concat = true,
                        .no_string_escape_chars = true,
                        .allow_path_names = true,
                    },
                };
                defer temp_lexer.deinit(allocator);

                var buffer: [1024]u8 = undefined;
                const fmt = "blend rmaomap\nmap {s}\n}}\n";
                const definition_text = std.fmt.bufPrint(&buffer, fmt, .{str}) catch unreachable;

                try temp_lexer.loadMemory(
                    definition_text,
                    "rmaomap",
                    0,
                    allocator,
                );

                try material.parseStage(&temp_lexer, trp_default, allocator);
            } else if (token.ieql("bumpmap") or token.ieql("normalmap")) {
                const str = try image_program.parse(lexer, allocator);
                // TODO: free str
                var temp_lexer = Lexer{
                    .flags = .{
                        .no_fatal_errors = true,
                        .no_string_concat = true,
                        .no_string_escape_chars = true,
                        .allow_path_names = true,
                    },
                };
                defer temp_lexer.deinit(allocator);

                var buffer: [1024]u8 = undefined;
                const fmt = "blend bumpmap\nmap {s}\n}}\n";
                const definition_text = std.fmt.bufPrint(&buffer, fmt, .{str}) catch unreachable;

                try temp_lexer.loadMemory(
                    definition_text,
                    "blendmap",
                    0,
                    allocator,
                );

                try material.parseStage(&temp_lexer, trp_default, allocator);
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

        try material.addImplicitStages(.repeat, allocator);
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

    pub fn setDefaultText(
        material: *Material,
        allocator: Allocator,
    ) Allocator.Error!void {
        const decl_local = material.base.base orelse @panic("uninitialized material");

        var buffer: [2048]u8 = undefined;

        const mat_name = decl_local.name.constSlice();

        const prefix = "lighteditor/";
        const fmt =
            \\material {s} // IMPLICITLY GENERATED
            \\{{
            \\  {{
            \\      blend blend
            \\      colored
            \\      map "{s}"
            \\      clamp
            \\  }}
            \\}}
        ;
        const generated_text = if (std.ascii.startsWithIgnoreCase(mat_name, prefix))
            std.fmt.bufPrint(
                &buffer,
                fmt,
                .{ mat_name, mat_name[prefix.len..] },
            ) catch unreachable
        else
            std.fmt.bufPrint(&buffer, fmt, .{ mat_name, mat_name }) catch unreachable;

        try decl_local.setText(generated_text, allocator);
    }

    pub fn freeData(material: *Material, allocator: Allocator) void {
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

    pub const EvaluateRegistersError = Allocator.Error || decl.DeclTable.ParseError;
    pub fn evaluateRegisters(
        material: *const Material,
        registers: []f32,
        local_params: []const f32,
        global_params: []const f32,
        time: f32,
        sound_emitter: ?*anyopaque,
        allocator: Allocator,
    ) EvaluateRegistersError!void {
        {
            var i = ExpRegisters.num_predefined;
            while (i < material.num_registers) : (i += 1) {
                registers[i] = material.expression_registers.?[i];
            }
        }

        // copy the local and global parameters
        registers[@intFromEnum(ExpRegisters.time)] = time;
        registers[@intFromEnum(ExpRegisters.parm0)] = local_params[0];
        registers[@intFromEnum(ExpRegisters.parm1)] = local_params[1];
        registers[@intFromEnum(ExpRegisters.parm2)] = local_params[2];
        registers[@intFromEnum(ExpRegisters.parm3)] = local_params[3];
        registers[@intFromEnum(ExpRegisters.parm4)] = local_params[4];
        registers[@intFromEnum(ExpRegisters.parm5)] = local_params[5];
        registers[@intFromEnum(ExpRegisters.parm6)] = local_params[6];
        registers[@intFromEnum(ExpRegisters.parm7)] = local_params[7];
        registers[@intFromEnum(ExpRegisters.parm8)] = local_params[8];
        registers[@intFromEnum(ExpRegisters.parm9)] = local_params[9];
        registers[@intFromEnum(ExpRegisters.parm10)] = local_params[10];
        registers[@intFromEnum(ExpRegisters.parm11)] = local_params[11];
        registers[@intFromEnum(ExpRegisters.global0)] = global_params[0];
        registers[@intFromEnum(ExpRegisters.global1)] = global_params[1];
        registers[@intFromEnum(ExpRegisters.global2)] = global_params[2];
        registers[@intFromEnum(ExpRegisters.global3)] = global_params[3];
        registers[@intFromEnum(ExpRegisters.global4)] = global_params[4];
        registers[@intFromEnum(ExpRegisters.global5)] = global_params[5];
        registers[@intFromEnum(ExpRegisters.global6)] = global_params[6];
        registers[@intFromEnum(ExpRegisters.global7)] = global_params[7];

        const ops = if (material.ops) |ops_ptr| ops_ptr[0..material.num_ops] else return;
        for (ops) |op| {
            switch (op.op_type) {
                .add => {
                    registers[op.c] = registers[op.a] + registers[op.b];
                },
                .subtract => {
                    registers[op.c] = registers[op.a] - registers[op.b];
                },
                .multiply => {
                    registers[op.c] = registers[op.a] * registers[op.b];
                },
                .divide => {
                    registers[op.c] = registers[op.a] / registers[op.b];
                },
                .mod => {
                    var b: i32 = @intFromFloat(registers[op.b]);
                    b = if (b != 0) b else 1;
                    registers[op.c] = @floatFromInt(@mod(@as(i32, @intFromFloat(registers[op.a])), b));
                },
                .table => {
                    const table: *decl.DeclTable = @ptrCast(try decl.instance.declByIndex(
                        .table,
                        op.a,
                        true,
                        allocator,
                    ));
                    registers[op.c] = table.tableLookup(registers[op.b]);
                },
                .sound => {
                    _ = sound_emitter;
                    @panic("not implemented");
                    //if( r_forceSoundOpAmplitude.GetFloat() > 0 )
                    //{
                    //	registers[op->c] = r_forceSoundOpAmplitude.GetFloat();
                    //}
                    //else if( soundEmitter )
                    //{
                    //	registers[op->c] = soundEmitter->CurrentAmplitude();
                    //}
                    //else
                    //{
                    //	registers[op->c] = 0;
                    //}
                },
                .gt => {
                    registers[op.c] = if (registers[op.a] > registers[op.b]) 1 else 0;
                },
                .ge => {
                    registers[op.c] = if (registers[op.a] >= registers[op.b]) 1 else 0;
                },
                .lt => {
                    registers[op.c] = if (registers[op.a] < registers[op.b]) 1 else 0;
                },
                .le => {
                    registers[op.c] = if (registers[op.a] <= registers[op.b]) 1 else 0;
                },
                .eq => {
                    registers[op.c] = if (registers[op.a] == registers[op.b]) 1 else 0;
                },
                .ne => {
                    registers[op.c] = if (registers[op.a] != registers[op.b]) 1 else 0;
                },
                .@"and" => {
                    registers[op.c] = if (registers[op.a] != 0 and registers[op.b] != 0) 1 else 0;
                },
                .@"or" => {
                    registers[op.c] = if (registers[op.a] != 0 or registers[op.b] != 0) 1 else 0;
                },
            }
        }
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
        .{ .name = "areaportal", .clear_solid = true, .content_flags = .{ .areaportal = true } }, // divides areas
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
        allocator: Allocator,
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
        new_stage.fragment_program = -1;
        new_stage.vertex_program = -1;
        new_stage.program = -1;

        var stencil_stage = std.mem.zeroes(StencilStage);

        const ss = &material.pd.?.parse_stages[material.num_stages];
        const ts = &ss.texture;

        material.clearStage(ss);

        var token = Token{};
        defer token.deinit(allocator);

        var cube_map_size: u32 = 0;

        while (true) {
            if (material.material_flags.defaulted) return;

            lexer.readToken(&token, allocator) catch {
                material.material_flags.defaulted = true;
                return;
            };

            if (token.eql("}")) break;

            if (token.ieql("name")) {
                try lexer.skipRestOfLine(allocator);
                continue;
            }

            if (token.ieql("blend")) {
                material.parseBlend(lexer, ss, allocator);
                continue;
            }

            if (token.ieql("map")) {
                const str = try image_program.parse(lexer, allocator);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                continue;
            }

            if (token.ieql("remoteRenderMap")) {
                ts.dynamic = .remote_render;
                ts.width = @intCast(try lexer.parseInt(allocator));
                ts.height = @intCast(try lexer.parseInt(allocator));
                continue;
            }

            if (token.ieql("mirrorRenderMap")) {
                ts.dynamic = .mirror_render;
                ts.width = @intCast(try lexer.parseInt(allocator));
                ts.height = @intCast(try lexer.parseInt(allocator));
                ts.texgen = .screen;
                continue;
            }

            if (token.ieql("xrayRenderMap")) {
                ts.dynamic = .xray_render;
                ts.width = @intCast(try lexer.parseInt(allocator));
                ts.height = @intCast(try lexer.parseInt(allocator));
                ts.texgen = .screen;
                continue;
            }

            if (token.ieql("guiRenderMap")) {
                ts.dynamic = .gui_render;
                ts.width = @intCast(try lexer.parseInt(allocator));
                ts.height = @intCast(try lexer.parseInt(allocator));
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
                lexer.readToken(&token, allocator) catch {
                    std.debug.print(
                        "missing parameter for 'videomap' keyword in material {s}\n",
                        .{material.base.base.?.name.constSlice()},
                    );
                    continue;
                };

                var loop = false;
                if (token.ieql("loop")) {
                    loop = true;

                    lexer.readToken(&token, allocator) catch {
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
                lexer.readToken(&token, allocator) catch {
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
                const str = try image_program.parse(lexer, allocator);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                cube_map = .native;
                continue;
            }

            if (token.ieql("cubeMapSingle")) {
                const str = try image_program.parse(lexer, allocator);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                cube_map = .single;
                texture_usage = .highquality_cube;
                continue;
            }

            if (token.ieql("cubeMapSize")) {
                cube_map_size = @intCast(try lexer.parseInt(allocator));
                continue;
            }

            if (token.ieql("cameraCubeMap")) {
                const str = try image_program.parse(lexer, allocator);
                image_name.len = 0;
                image_name.appendSliceAssumeCapacity(str);
                cube_map = .camera;
                continue;
            }

            if (token.ieql("quakeCubeMap")) {
                const str = try image_program.parse(lexer, allocator);
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
                lexer.readTokenOnLine(&token, allocator) catch {
                    ss.private_polygon_offset = 1;
                    continue;
                };

                try lexer.unreadToken(&token, allocator);
                ss.private_polygon_offset = try lexer.parseFloat(allocator);
                continue;
            }

            if (token.ieql("texGen")) {
                try lexer.readToken(&token, allocator);

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
                material.matchTokenOrDefaulted(lexer, ",", allocator);
                ss.color.registers[1] = @intCast(material.parseExpression(lexer));
                material.matchTokenOrDefaulted(lexer, ",", allocator);
                ss.color.registers[2] = @intCast(material.parseExpression(lexer));
                material.matchTokenOrDefaulted(lexer, ",", allocator);
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
                    try lexer.readTokenOnLine(&token, allocator);
                    const find_fragment_shader_result = render_prog_manager.instance.findShader(
                        token.slice(),
                        Shader.Stage.fragment,
                        "",
                        macros,
                        false,
                        allocator,
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
                        allocator,
                    );
                    if (find_vertex_shader_result) |shader_index| {
                        new_stage.vertex_program = @intCast(shader_index);
                    } else |_| {
                        new_stage.vertex_program = -1;
                    }
                    continue;
                }

                if (token.ieql("fragmentProgram")) {
                    try lexer.readTokenOnLine(&token, allocator);
                    const find_shader_result = render_prog_manager.instance.findShader(
                        token.slice(),
                        Shader.Stage.fragment,
                        "",
                        macros,
                        false,
                        allocator,
                    );
                    if (find_shader_result) |shader_index| {
                        new_stage.fragment_program = @intCast(shader_index);
                    } else |_| {
                        new_stage.fragment_program = -1;
                    }
                    continue;
                }

                if (token.ieql("vertexProgram")) {
                    try lexer.readTokenOnLine(&token, allocator);
                    const find_shader_result = render_prog_manager.instance.findShader(
                        token.slice(),
                        Shader.Stage.vertex,
                        "",
                        macros,
                        false,
                        allocator,
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
                allocator,
            );
            new_stage.program = @intCast(program_index);

            const stage = try allocator.create(NewShaderStage);
            stage.* = new_stage;

            ss.new_stage = stage;
        }

        material.num_stages += 1;

        if (texture_usage == .default) {
            texture_usage = switch (ss.lighting) {
                .bump => .bump,
                .diffuse => .diffuse,
                .specular => texture_usage: {
                    const img = image_name.constSlice();
                    break :texture_usage if (string.icontains(img, "_rmaod") != null)
                        .specular_pbr_rmaod
                    else if (string.icontains(img, "_rmao") != null)
                        .specular_pbr_rmao
                    else
                        .specular;
                },
                else => texture_usage,
            };
        }

        if (texture_usage == .diffuse and ss.has_alpha_test) {
            const new_coverage_stage = &material.pd.?.parse_stages[material.num_stages];
            material.num_stages += 1;

            new_coverage_stage.* = ss.*;

            ss.has_alpha_test = false;
            new_coverage_stage.has_alpha_test = true;
            new_coverage_stage.lighting = .coverage;
            const coverage_ts = &new_coverage_stage.texture;

            if (image_name.constSlice().len != 0) {
                coverage_ts.image = image_manager.instance.imageFromFile(
                    image_name.constSlice(),
                    texture_filter,
                    texture_repeat,
                    .coverage,
                    cube_map,
                    cube_map_size,
                    allocator,
                ) catch image_manager.instance.defaultImage;
            } else if (coverage_ts.cinematic == null and
                coverage_ts.dynamic == .static and
                ss.new_stage == null)
            {
                std.debug.print(
                    "material {s} had stage with no image\n",
                    .{material.base.base.?.name.constSlice()},
                );
                coverage_ts.image = image_manager.instance.defaultImage;
            }
        }

        if (image_name.constSlice().len != 0) {
            ts.image = image_manager.instance.imageFromFile(
                image_name.constSlice(),
                texture_filter,
                texture_repeat,
                texture_usage,
                cube_map,
                cube_map_size,
                allocator,
            ) catch image_manager.instance.defaultImage;
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

    const AddImplicitStagesError =
        Allocator.Error ||
        ParseStageError ||
        Lexer.LoadMemoryError;
    fn addImplicitStages(
        material: *Material,
        trp_default: TextureRepeat,
        allocator: Allocator,
    ) AddImplicitStagesError!void {
        var has_bump = false;
        var has_diffuse = false;
        var has_reflection = false;
        var has_specular = false;

        for (0..material.num_stages) |i| {
            const ps = &material.pd.?.parse_stages[i];
            if (ps.lighting == .bump) {
                has_bump = true;
            }

            if (ps.lighting == .diffuse) {
                has_diffuse = true;
            }

            if (ps.lighting == .specular) {
                has_specular = true;
            }

            if (ps.texture.texgen == .reflect_cube) {
                has_reflection = true;
            }
        }

        if (!has_bump and !has_diffuse and !has_specular) return;

        if (material.num_stages == max_shader_stages) return;

        const lexer_flags = lexer_.Flags{
            .no_string_concat = true,
            .no_string_escape_chars = true,
            .allow_path_names = true,
            .no_fatal_errors = true,
        };

        if (!has_bump) {
            var lexer = Lexer{ .flags = lexer_flags };
            defer lexer.deinit(allocator);

            const definition_text = "blend bumpmap\nmap _flat\n}\n";

            try lexer.loadMemory(
                definition_text,
                "bumpmap",
                0,
                allocator,
            );

            try material.parseStage(&lexer, trp_default, allocator);
        }

        if (!has_diffuse and !has_specular and !has_reflection) {
            var lexer = Lexer{ .flags = lexer_flags };
            defer lexer.deinit(allocator);

            const definition_text = "blend diffusemap\nmap _white\n}\n";

            try lexer.loadMemory(
                definition_text,
                "diffusemap",
                0,
                allocator,
            );

            try material.parseStage(&lexer, trp_default, allocator);
        }
    }

    fn sortInteractionStages(material: *Material) void {
        var i: u32 = 0;
        var j: u32 = undefined;

        while (i < material.num_stages) : (i = j) {
            // find the next bump_map
            j = i + 1;
            while (j < material.num_stages) : (j += 1) {
                const psi = &material.pd.?.parse_stages[i];
                const psj = &material.pd.?.parse_stages[j];

                if (psj.lighting == .bump and psi.lighting == .bump) break;
            }

            // bubble sort
            for (1..(j - i)) |l| {
                for (i..(j - l)) |k| {
                    const current = &material.pd.?.parse_stages[k];
                    const next = &material.pd.?.parse_stages[k + 1];

                    if (@intFromEnum(current.lighting) > @intFromEnum(next.lighting)) {
                        const temp = current.*;
                        current.* = next.*;
                        next.* = temp;
                    }
                }
            }
        }
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

    fn parseBlend(
        material: *Material,
        lexer: *Lexer,
        stage: *ShaderStage,
        allocator: Allocator,
    ) void {
        var token = Token{};
        defer token.deinit(allocator);

        lexer.readToken(&token, allocator) catch return;

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
        material.matchTokenOrDefaulted(lexer, ",", allocator);

        lexer.readToken(&token, allocator) catch return;

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

    fn matchTokenOrDefaulted(
        material: *Material,
        lexer: *Lexer,
        match: []const u8,
        allocator: Allocator,
    ) void {
        lexer.expectTokenString(match, allocator) catch {
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
