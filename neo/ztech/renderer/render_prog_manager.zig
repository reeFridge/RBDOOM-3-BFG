const std = @import("std");
const device_manager = @import("../sys/device_manager.zig");
const fs = @import("../framework/file_system.zig");
const common = @import("common.zig");
const idlib = @import("../idlib.zig");
const nvrhi = @import("nvrhi.zig");
const buffer_object = @import("buffer_object.zig");
const CVec4 = @import("../math/vector.zig").CVec4;
const bit = @import("../math/math.zig").bit;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const shader_blob = @import("shader_blob.zig");
const global = @import("../global.zig");
const Allocator = std.mem.Allocator;

const BuiltinShader = enum(c_int) {
    GUI,
    COLOR,
    COLOR_SKINNED,
    VERTEX_COLOR,
    AMBIENT_LIGHTING_IBL,
    AMBIENT_LIGHTING_IBL_SKINNED,
    AMBIENT_LIGHTING_IBL_PBR,
    AMBIENT_LIGHTING_IBL_PBR_SKINNED,
    AMBIENT_LIGHTGRID_IBL,
    AMBIENT_LIGHTGRID_IBL_SKINNED,
    AMBIENT_LIGHTGRID_IBL_PBR,
    AMBIENT_LIGHTGRID_IBL_PBR_SKINNED,
    SMALL_GEOMETRY_BUFFER,
    SMALL_GEOMETRY_BUFFER_SKINNED,
    TEXTURED,
    TEXTURE_VERTEXCOLOR,
    TEXTURE_VERTEXCOLOR_SRGB,
    TEXTURE_VERTEXCOLOR_SKINNED,
    TEXTURE_TEXGEN_VERTEXCOLOR,
    INTERACTION,
    INTERACTION_SKINNED,
    INTERACTION_AMBIENT,
    INTERACTION_AMBIENT_SKINNED,
    PBR_INTERACTION,
    PBR_INTERACTION_SKINNED,
    PBR_INTERACTION_AMBIENT,
    PBR_INTERACTION_AMBIENT_SKINNED,
    INTERACTION_SHADOW_MAPPING_SPOT,
    INTERACTION_SHADOW_MAPPING_SPOT_SKINNED,
    INTERACTION_SHADOW_MAPPING_POINT,
    INTERACTION_SHADOW_MAPPING_POINT_SKINNED,
    INTERACTION_SHADOW_MAPPING_PARALLEL,
    INTERACTION_SHADOW_MAPPING_PARALLEL_SKINNED,
    PBR_INTERACTION_SHADOW_MAPPING_SPOT,
    PBR_INTERACTION_SHADOW_MAPPING_SPOT_SKINNED,
    PBR_INTERACTION_SHADOW_MAPPING_POINT,
    PBR_INTERACTION_SHADOW_MAPPING_POINT_SKINNED,
    PBR_INTERACTION_SHADOW_MAPPING_PARALLEL,
    PBR_INTERACTION_SHADOW_MAPPING_PARALLEL_SKINNED,
    INTERACTION_SHADOW_ATLAS_SPOT,
    INTERACTION_SHADOW_ATLAS_SPOT_SKINNED,
    INTERACTION_SHADOW_ATLAS_POINT,
    INTERACTION_SHADOW_ATLAS_POINT_SKINNED,
    INTERACTION_SHADOW_ATLAS_PARALLEL,
    INTERACTION_SHADOW_ATLAS_PARALLEL_SKINNED,
    PBR_INTERACTION_SHADOW_ATLAS_SPOT,
    PBR_INTERACTION_SHADOW_ATLAS_SPOT_SKINNED,
    PBR_INTERACTION_SHADOW_ATLAS_POINT,
    PBR_INTERACTION_SHADOW_ATLAS_POINT_SKINNED,
    PBR_INTERACTION_SHADOW_ATLAS_PARALLEL,
    PBR_INTERACTION_SHADOW_ATLAS_PARALLEL_SKINNED,
    DEBUG_LIGHTGRID,
    DEBUG_LIGHTGRID_SKINNED,
    DEBUG_OCTAHEDRON,
    DEBUG_OCTAHEDRON_SKINNED,
    ENVIRONMENT,
    ENVIRONMENT_SKINNED,
    BUMPY_ENVIRONMENT,
    BUMPY_ENVIRONMENT_SKINNED,
    DEPTH,
    DEPTH_SKINNED,
    BLENDLIGHT,
    BLENDLIGHT_SKINNED,
    FOG,
    FOG_SKINNED,
    SKYBOX,
    WOBBLESKY,
    POSTPROCESS,
    POSTPROCESS_RETRO_2BIT, // CGA, Gameboy, cool for Gamejams
    POSTPROCESS_RETRO_C64, // Commodore 64
    POSTPROCESS_RETRO_CPC, // Amstrad 6128
    POSTPROCESS_RETRO_NES, // NES
    POSTPROCESS_RETRO_GENESIS, // Sega Genesis / Megadrive
    POSTPROCESS_RETRO_PSX, // Sony Playstation 1
    CRT_MATTIAS,
    CRT_NUPIXIE,
    CRT_EASYMODE,
    SCREEN,
    TONEMAP,
    BRIGHTPASS,
    HDR_GLARE_CHROMATIC,
    HDR_DEBUG,
    SMAA_EDGE_DETECTION,
    SMAA_BLENDING_WEIGHT_CALCULATION,
    SMAA_NEIGHBORHOOD_BLENDING,
    TAA_MOTION_VECTORS,
    TAA_RESOLVE,
    TAA_RESOLVE_MSAA_2X,
    TAA_RESOLVE_MSAA_4X,
    TAA_RESOLVE_MSAA_8X,
    AMBIENT_OCCLUSION,
    AMBIENT_OCCLUSION_AND_OUTPUT,
    AMBIENT_OCCLUSION_BLUR,
    AMBIENT_OCCLUSION_BLUR_AND_OUTPUT,
    DEEP_GBUFFER_RADIOSITY_SSGI,
    DEEP_GBUFFER_RADIOSITY_BLUR,
    DEEP_GBUFFER_RADIOSITY_BLUR_AND_OUTPUT,
    STEREO_DEGHOST,
    STEREO_WARP,
    BINK,
    BINK_SRGB,
    BINK_GUI,
    STEREO_INTERLACE,
    MOTION_BLUR,
    DEBUG_SHADOWMAP,
    BLIT,
    RECT,
    TONEMAPPING,
    TONEMAPPING_TEX_ARRAY,
    HISTOGRAM_CS,
    HISTOGRAM_TEX_ARRAY_CS,
    EXPOSURE_CS,
    MAX_BUILTINS,

    pub inline fn toIndex(e: BuiltinShader) usize {
        return @intCast(@intFromEnum(e));
    }
};

const RenderProg = extern struct {
    name: idlib.Str = .{},
    vertexShaderIndex: c_int = -1,
    fragmentShaderIndex: c_int = -1,
    computeShaderIndex: c_int = -1,
    builtin: bool = true,
    usesJoints: bool = false,
    vertexLayout: common.VertexLayoutType = .UNKNOWN,
    bindingLayoutType: common.BindingLayoutType = .DEFAULT,
    inputLayout: nvrhi.InputLayoutHandle = .{},
    bindingLayouts: idlib.StaticList(
        nvrhi.BindingLayoutHandle,
        nvrhi.c_MaxBindingLayouts,
    ) = .{},

    pub fn deinit(prog: *RenderProg, allocator: Allocator) void {
        prog.name.deinit(allocator);
        for (prog.bindingLayouts.slice()) |*bind| bind.deinit();
        prog.inputLayout.deinit();
    }
};

const ShaderMacro = extern struct {
    name: idlib.Str = .{},
    definition: idlib.Str = .{},

    pub fn deinit(macro: *ShaderMacro, allocator: Allocator) void {
        macro.name.deinit(allocator);
        macro.definition.deinit(allocator);
    }
};

pub const Shader = extern struct {
    const StageType = c_int;
    pub const Stage = struct {
        pub const vertex: StageType = bit(0);
        pub const fragment: StageType = bit(1);
        pub const compute: StageType = bit(2);
        pub const default: StageType = vertex | fragment;
    };

    name: idlib.Str = .{},
    nameOutSuffix: idlib.Str = .{},
    shaderFeatures: u32,
    builtin: bool,
    macros: idlib.List(ShaderMacro) = .{},
    handle: nvrhi.ShaderHandle = .{},
    stage: StageType,

    pub fn deinit(shader: *Shader, allocator: Allocator) void {
        shader.name.deinit(allocator);
        shader.nameOutSuffix.deinit(allocator);

        for (shader.macros.slice()) |*macro| macro.deinit(allocator);
        shader.macros.deinit(allocator);

        shader.handle.deinit();
    }
};

pub const RenderParam = enum(u32) {
    screencorrectionfactor = 0,
    windowcoord,
    diffusemodifier,
    specularmodifier,
    locallightorigin,
    localvieworigin,
    lightprojection_s,
    lightprojection_t,
    lightprojection_q,
    lightfalloff_s,
    bumpmatrix_s,
    bumpmatrix_t,
    diffusematrix_s,
    diffusematrix_t,
    specularmatrix_s,
    specularmatrix_t,
    vertexcolor_modulate,
    vertexcolor_add,
    color,
    vieworigin,
    globaleyepos,
    mvpmatrix_x,
    mvpmatrix_y,
    mvpmatrix_z,
    mvpmatrix_w,
    modelmatrix_x,
    modelmatrix_y,
    modelmatrix_z,
    modelmatrix_w,
    projmatrix_x,
    projmatrix_y,
    projmatrix_z,
    projmatrix_w,
    modelviewmatrix_x,
    modelviewmatrix_y,
    modelviewmatrix_z,
    modelviewmatrix_w,
    texturematrix_s,
    texturematrix_t,
    texgen_0_s,
    texgen_0_t,
    texgen_0_q,
    texgen_0_enabled,
    texgen_1_s,
    texgen_1_t,
    texgen_1_q,
    texgen_1_enabled,
    wobblesky_x,
    wobblesky_y,
    wobblesky_z,
    overbright,
    enable_skinning,
    alpha_test,
    ambient_color,
    globallightorigin,
    jittertexscale,
    jittertexoffset,
    psx_distortions,
    cascadedistances,
    shadow_matrix_0_x,
    shadow_matrix_0_y,
    shadow_matrix_0_z,
    shadow_matrix_0_w,
    shadow_matrix_1_x,
    shadow_matrix_1_y,
    shadow_matrix_1_z,
    shadow_matrix_1_w,
    shadow_matrix_2_x,
    shadow_matrix_2_y,
    shadow_matrix_2_z,
    shadow_matrix_2_w,
    shadow_matrix_3_x,
    shadow_matrix_3_y,
    shadow_matrix_3_z,
    shadow_matrix_3_w,
    shadow_matrix_4_x,
    shadow_matrix_4_y,
    shadow_matrix_4_z,
    shadow_matrix_4_w,
    shadow_matrix_5_x,
    shadow_matrix_5_y,
    shadow_matrix_5_z,
    shadow_matrix_5_w,
    shadow_atlas_offset_0,
    shadow_atlas_offset_1,
    shadow_atlas_offset_2,
    shadow_atlas_offset_3,
    shadow_atlas_offset_4,
    shadow_atlas_offset_5,
    user0,
    user1,
    user2,
    user3,
    user4,
    user5,
    user6,
    user7,
};

pub const RenderProgManager = extern struct {
    const VertexAttribDescList = idlib.List(nvrhi.VertexAttributeDesc);
    const BindingLayoutList = idlib.StaticList(nvrhi.BindingLayoutHandle, nvrhi.c_MaxBindingLayouts);
    const NUM_VERTEX_LAYOUTS: usize = @intCast(@intFromEnum(common.VertexLayoutType.NUM_VERTEX_LAYOUTS));
    const NUM_BINDING_LAYOUTS: usize = @intCast(@intFromEnum(common.BindingLayoutType.NUM_BINDING_LAYOUTS));
    const MAX_BUILTINS: usize = @intCast(@intFromEnum(BuiltinShader.MAX_BUILTINS));
    const MAX_UNIFORMS: usize = @typeInfo(RenderParam).Enum.fields.len;

    vptr: *anyopaque,
    renderParmUbo: buffer_object.UniformBuffer,
    bindingParmUbo: [NUM_BINDING_LAYOUTS]buffer_object.UniformBuffer,
    mappedRenderParms: [NUM_BINDING_LAYOUTS]?*CVec4,
    builtinShaders: [MAX_BUILTINS]c_int,
    currentIndex: c_int,
    renderProgs: idlib.List(RenderProg),
    shaders: idlib.List(Shader),
    uniforms: idlib.StaticList(CVec4, MAX_UNIFORMS),
    uniformsChanged: bool,
    device: *nvrhi.IDevice,
    vertexLayoutDescs: idlib.StaticList(
        VertexAttribDescList,
        NUM_VERTEX_LAYOUTS,
    ),
    bindingLayouts: idlib.StaticList(
        BindingLayoutList,
        NUM_BINDING_LAYOUTS,
    ),
    constantBuffer: nvrhi.BufferHandle,

    extern fn c_renderProgManager_shutdown(*RenderProgManager) void;
    extern fn c_renderProgManager_unbind(*RenderProgManager) void;

    pub fn setUniformValue(
        prog_manager: *RenderProgManager,
        param: RenderParam,
        value: *const [4]f32,
    ) void {
        const uniforms = prog_manager.uniforms.slice();
        const param_ptr: *[4]f32 = @ptrCast(&uniforms[@intFromEnum(param)]);
        for (value, 0..) |component, i| {
            param_ptr[i] = component;
        }

        prog_manager.uniformsChanged = true;
    }

    pub fn bindProgramIndex(prog_manager: *RenderProgManager, index: u32) void {
        prog_manager.currentIndex = @intCast(index);
    }

    pub fn unbind(prog_manager: *RenderProgManager) void {
        prog_manager.currentIndex = -1;
    }

    pub fn init(
        prog_manager: *RenderProgManager,
        device: *nvrhi.IDevice,
        allocator: Allocator,
    ) LoadShaderError!void {
        for (&prog_manager.builtinShaders) |*builtin| {
            builtin.* = -1;
        }

        prog_manager.device = device;

        prog_manager.uniforms.setNum(MAX_UNIFORMS);
        for (prog_manager.uniforms.slice()) |*uniform| uniform.* = CVec4{};
        prog_manager.uniformsChanged = false;
        {
            const constBufferDesc = nvrhi.utils.createVolatileConstantBufferDesc(
                prog_manager.uniforms.memAllocated(),
                "RenderPrams_1",
                16384,
            );
            prog_manager.constantBuffer = device.createBuffer(&constBufferDesc);
        }

        prog_manager.vertexLayoutDescs.setNum(NUM_VERTEX_LAYOUTS);
        const desc_lists = prog_manager.vertexLayoutDescs.slice();
        for (desc_lists) |*list| list.* = .{};

        const descs = &desc_lists[common.VertexLayoutType.DRAW_VERT.toIndex()];

        {
            const index = try descs.append(.{
                .format = .RGB32_FLOAT,
                .offset = @offsetOf(DrawVertex, "xyz"),
                .elementStride = @sizeOf(DrawVertex),
            }, allocator);
            descs.slice()[index].setName("POSITION");
        }

        {
            const index = try descs.append(.{
                .format = .RG16_FLOAT,
                .offset = @offsetOf(DrawVertex, "st"),
                .elementStride = @sizeOf(DrawVertex),
            }, allocator);
            descs.slice()[index].setName("TEXCOORD");
        }

        {
            const index = try descs.append(.{
                .format = .RGBA8_UNORM,
                .offset = @offsetOf(DrawVertex, "normal"),
                .elementStride = @sizeOf(DrawVertex),
            }, allocator);
            descs.slice()[index].setName("NORMAL");
        }

        {
            const index = try descs.append(.{
                .format = .RGBA8_UNORM,
                .offset = @offsetOf(DrawVertex, "tangent"),
                .elementStride = @sizeOf(DrawVertex),
            }, allocator);
            descs.slice()[index].setName("TANGENT");
        }

        {
            const index = try descs.append(.{
                .arraySize = 2,
                .format = .RGBA8_UNORM,
                .offset = @offsetOf(DrawVertex, "color"),
                .elementStride = @sizeOf(DrawVertex),
            }, allocator);

            descs.slice()[index].setName("COLOR");
        }

        const constant_buffer = nvrhi.BindingLayoutItem{
            .type = .VolatileConstantBuffer,
            .slot = 0,
        };

        const BindingsArray = std.meta.FieldType(nvrhi.BindingLayoutDesc, .bindings);
        const uniforms_layout = device.createBindingLayout(&.{
            .visibility = .All,
            .bindings = BindingsArray.fromSlice(&.{constant_buffer}),
        });
        const skinning_layout = device.createBindingLayout(&.{
            .visibility = .All,
            .bindings = BindingsArray.fromSlice(&.{
                constant_buffer,
                .{ .type = .StructuredBuffer_SRV, .slot = 11 },
            }),
        });
        const sampler_one_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Sampler, .slot = 0 },
            }),
        });
        const default_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 0 },
            }),
        });

        const LayoutType = common.BindingLayoutType;
        prog_manager.bindingLayouts.setNum(LayoutType.NUM_BINDING_LAYOUTS.toIndex());
        const layouts = prog_manager.bindingLayouts.slice();
        layouts[LayoutType.DEFAULT.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            default_layout,
            sampler_one_layout,
        });
        layouts[LayoutType.DEFAULT_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            skinning_layout,
            default_layout,
            sampler_one_layout,
        });
        layouts[LayoutType.CONSTANT_BUFFER_ONLY.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
        });
        layouts[LayoutType.CONSTANT_BUFFER_ONLY_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            skinning_layout,
        });

        const default_material_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 0 },
                .{ .type = .Texture_SRV, .slot = 1 },
                .{ .type = .Texture_SRV, .slot = 2 },
            }),
        });
        const ambientIblLayout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 3 },
                .{ .type = .Texture_SRV, .slot = 4 },
                .{ .type = .Texture_SRV, .slot = 7 },
                .{ .type = .Texture_SRV, .slot = 8 },
                .{ .type = .Texture_SRV, .slot = 9 },
                .{ .type = .Texture_SRV, .slot = 10 },
            }),
        });
        const sampler_two_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Sampler, .slot = 0 },
                .{ .type = .Sampler, .slot = 1 },
            }),
        });
        layouts[LayoutType.AMBIENT_LIGHTING_IBL.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            default_material_layout,
            ambientIblLayout,
            sampler_two_layout,
        });
        layouts[LayoutType.AMBIENT_LIGHTING_IBL_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            skinning_layout,
            default_material_layout,
            ambientIblLayout,
            sampler_two_layout,
        });
        layouts[LayoutType.BLIT.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .All,
                .bindings = BindingsArray.fromSlice(&.{constant_buffer}),
            }),
        });
        layouts[LayoutType.DRAW_AO.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .All,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .Texture_SRV, .slot = 1 },
                    .{ .type = .Texture_SRV, .slot = 2 },
                }),
            }),
            sampler_one_layout,
        });
        layouts[LayoutType.DRAW_AO1.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .All,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                }),
            }),
            sampler_one_layout,
        });

        const interaction_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 3 },
                .{ .type = .Texture_SRV, .slot = 4 },
            }),
        });

        layouts[LayoutType.DRAW_INTERACTION.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            default_material_layout,
            interaction_layout,
            sampler_two_layout,
        });
        layouts[LayoutType.DRAW_INTERACTION_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            skinning_layout,
            default_material_layout,
            interaction_layout,
            sampler_two_layout,
        });

        const interaction_sm_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 3 },
                .{ .type = .Texture_SRV, .slot = 4 },
                .{ .type = .Texture_SRV, .slot = 5 },
                .{ .type = .Texture_SRV, .slot = 6 },
            }),
        });

        const sampler_four_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 0 },
                .{ .type = .Texture_SRV, .slot = 1 },
                .{ .type = .Texture_SRV, .slot = 2 },
                .{ .type = .Texture_SRV, .slot = 3 },
            }),
        });
        layouts[LayoutType.DRAW_INTERACTION_SM.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            default_material_layout,
            interaction_sm_layout,
            sampler_four_layout,
        });
        layouts[LayoutType.DRAW_INTERACTION_SM_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            skinning_layout,
            default_material_layout,
            interaction_sm_layout,
            sampler_four_layout,
        });

        const fog_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 0 },
                .{ .type = .Texture_SRV, .slot = 1 },
            }),
        });

        layouts[LayoutType.FOG.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            fog_layout,
            sampler_two_layout,
        });
        layouts[LayoutType.FOG_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            skinning_layout,
            fog_layout,
            sampler_two_layout,
        });

        const blend_light_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 0 },
                .{ .type = .Texture_SRV, .slot = 1 },
            }),
        });

        layouts[LayoutType.BLENDLIGHT.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            blend_light_layout,
            sampler_one_layout,
        });
        layouts[LayoutType.BLENDLIGHT_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            blend_light_layout,
            sampler_one_layout,
        });
        layouts[LayoutType.POST_PROCESS_INGAME.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .All,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .Texture_SRV, .slot = 1 },
                    .{ .type = .Texture_SRV, .slot = 2 },
                }),
            }),
            sampler_one_layout,
        });

        const pp_fx_layout = device.createBindingLayout(&.{
            .visibility = .All,
            .bindings = BindingsArray.fromSlice(&.{
                constant_buffer,
                .{ .type = .Texture_SRV, .slot = 0 },
                .{ .type = .Texture_SRV, .slot = 1 },
            }),
        });

        layouts[LayoutType.POST_PROCESS_FINAL.toIndex()] = BindingLayoutList.fromSlice(&.{
            pp_fx_layout,
            sampler_two_layout,
        });

        layouts[LayoutType.POST_PROCESS_CRT.toIndex()] = BindingLayoutList.fromSlice(&.{
            pp_fx_layout,
            sampler_two_layout,
        });

        layouts[LayoutType.POST_PROCESS_FINAL2.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .All,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .Texture_SRV, .slot = 1 },
                    .{ .type = .Texture_SRV, .slot = 2 },
                    .{ .type = .Texture_SRV, .slot = 3 },
                }),
            }),
            sampler_two_layout,
        });

        const normal_cube_layout = device.createBindingLayout(&.{
            .visibility = .Pixel,
            .bindings = BindingsArray.fromSlice(&.{
                .{ .type = .Texture_SRV, .slot = 0 },
                .{ .type = .Texture_SRV, .slot = 1 },
            }),
        });

        layouts[LayoutType.NORMAL_CUBE.toIndex()] = BindingLayoutList.fromSlice(&.{
            uniforms_layout,
            normal_cube_layout,
            sampler_one_layout,
        });
        layouts[LayoutType.NORMAL_CUBE_SKINNED.toIndex()] = BindingLayoutList.fromSlice(&.{
            skinning_layout,
            normal_cube_layout,
            sampler_one_layout,
        });

        layouts[LayoutType.BINK_VIDEO.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .All,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .Texture_SRV, .slot = 1 },
                    .{ .type = .Texture_SRV, .slot = 2 },
                }),
            }),
            sampler_one_layout,
        });

        layouts[LayoutType.TAA_MOTION_VECTORS.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .All,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .Texture_SRV, .slot = 1 },
                }),
            }),
            sampler_one_layout,
        });

        layouts[LayoutType.TONEMAP.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .Pixel,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .TypedBuffer_SRV, .slot = 1 },
                    .{ .type = .Texture_SRV, .slot = 2 },
                    .{ .type = .Sampler, .slot = 0 },
                }),
            }),
        });

        layouts[LayoutType.HISTOGRAM.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .Compute,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .TypedBuffer_UAV, .slot = 0 },
                }),
            }),
        });

        layouts[LayoutType.EXPOSURE.toIndex()] = BindingLayoutList.fromSlice(&.{
            device.createBindingLayout(&.{
                .visibility = .Compute,
                .bindings = BindingsArray.fromSlice(&.{
                    constant_buffer,
                    .{ .type = .Texture_SRV, .slot = 0 },
                    .{ .type = .TypedBuffer_UAV, .slot = 0 },
                }),
            }),
        });

        const BuiltinShaderDesc = struct {
            // index
            BuiltinShader,
            // name
            []const u8,
            // name_out_suffix
            []const u8,
            // macros array
            []const []const []const u8,
            // require gpu skinning
            bool,
            Shader.StageType,
            common.VertexLayoutType,
            common.BindingLayoutType,
        };
        const builtins = [_]BuiltinShaderDesc{
            .{ .GUI, "builtin/gui", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .COLOR, "builtin/color", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .CONSTANT_BUFFER_ONLY },
            .{ .COLOR_SKINNED, "builtin/color", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .CONSTANT_BUFFER_ONLY_SKINNED },
            .{ .VERTEX_COLOR, "builtin/vertex_color", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .CONSTANT_BUFFER_ONLY },

            .{ .AMBIENT_LIGHTING_IBL, "builtin/lighting/ambient_lighting_IBL", "", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL },
            .{ .AMBIENT_LIGHTING_IBL_SKINNED, "builtin/lighting/ambient_lighting_IBL", "_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL_SKINNED },
            .{ .AMBIENT_LIGHTING_IBL_PBR, "builtin/lighting/ambient_lighting_IBL", "_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL },
            .{ .AMBIENT_LIGHTING_IBL_PBR_SKINNED, "builtin/lighting/ambient_lighting_IBL", "_PBR_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL_SKINNED },

            .{ .AMBIENT_LIGHTGRID_IBL, "builtin/lighting/ambient_lightgrid_IBL", "", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL },
            .{ .AMBIENT_LIGHTGRID_IBL_SKINNED, "builtin/lighting/ambient_lightgrid_IBL", "_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL_SKINNED },
            .{ .AMBIENT_LIGHTGRID_IBL_PBR, "builtin/lighting/ambient_lightgrid_IBL", "_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL },
            .{ .AMBIENT_LIGHTGRID_IBL_PBR_SKINNED, "builtin/lighting/ambient_lightgrid_IBL", "_PBR_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .AMBIENT_LIGHTING_IBL_SKINNED },

            .{ .SMALL_GEOMETRY_BUFFER, "builtin/gbuffer", "", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .SMALL_GEOMETRY_BUFFER_SKINNED, "builtin/gbuffer", "_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DEFAULT_SKINNED },

            .{ .TEXTURED, "builtin/texture", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .TEXTURE_VERTEXCOLOR, "builtin/texture_color", "", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_SRGB", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .TEXTURE_VERTEXCOLOR_SRGB, "builtin/texture_color", "_sRGB", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_SRGB", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .TEXTURE_VERTEXCOLOR_SKINNED, "builtin/texture_color", "_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_SRGB", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DEFAULT_SKINNED },
            .{ .TEXTURE_TEXGEN_VERTEXCOLOR, "builtin/texture_color_texgen", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },

            .{ .INTERACTION, "builtin/lighting/interaction", "", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION },
            .{ .INTERACTION_SKINNED, "builtin/lighting/interaction", "_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SKINNED },

            .{ .INTERACTION_AMBIENT, "builtin/lighting/interactionAmbient", "", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION },
            .{ .INTERACTION_AMBIENT_SKINNED, "builtin/lighting/interactionAmbient", "_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SKINNED },

            // PBR variants
            .{ .PBR_INTERACTION, "builtin/lighting/interaction", "_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION },
            .{ .PBR_INTERACTION_SKINNED, "builtin/lighting/interaction", "_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SKINNED },

            .{ .PBR_INTERACTION_AMBIENT, "builtin/lighting/interactionAmbient", "_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "USE_PBR", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION },
            .{ .PBR_INTERACTION_AMBIENT_SKINNED, "builtin/lighting/interactionAmbient", "_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "USE_PBR", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SKINNED },

            // regular shadow mapping
            .{ .INTERACTION_SHADOW_MAPPING_SPOT, "builtin/lighting/interactionSM", "_spot", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .INTERACTION_SHADOW_MAPPING_SPOT_SKINNED, "builtin/lighting/interactionSM", "_spot_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .INTERACTION_SHADOW_MAPPING_POINT, "builtin/lighting/interactionSM", "_point", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .INTERACTION_SHADOW_MAPPING_POINT_SKINNED, "builtin/lighting/interactionSM", "_point_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .INTERACTION_SHADOW_MAPPING_PARALLEL, "builtin/lighting/interactionSM", "_parallel", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .INTERACTION_SHADOW_MAPPING_PARALLEL_SKINNED, "builtin/lighting/interactionSM", "_parallel_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .PBR_INTERACTION_SHADOW_MAPPING_SPOT, "builtin/lighting/interactionSM", "_spot_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .PBR_INTERACTION_SHADOW_MAPPING_SPOT_SKINNED, "builtin/lighting/interactionSM", "_spot_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .PBR_INTERACTION_SHADOW_MAPPING_POINT, "builtin/lighting/interactionSM", "_point_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .PBR_INTERACTION_SHADOW_MAPPING_POINT_SKINNED, "builtin/lighting/interactionSM", "_point_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .PBR_INTERACTION_SHADOW_MAPPING_PARALLEL, "builtin/lighting/interactionSM", "_parallel_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .PBR_INTERACTION_SHADOW_MAPPING_PARALLEL_SKINNED, "builtin/lighting/interactionSM", "_parallel_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "0" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            // shadow mapping using a big atlas
            .{ .INTERACTION_SHADOW_ATLAS_SPOT, "builtin/lighting/interactionSM", "_atlas_spot", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .INTERACTION_SHADOW_ATLAS_SPOT_SKINNED, "builtin/lighting/interactionSM", "_atlas_spot_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .INTERACTION_SHADOW_ATLAS_POINT, "builtin/lighting/interactionSM", "_atlas_point", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .INTERACTION_SHADOW_ATLAS_POINT_SKINNED, "builtin/lighting/interactionSM", "_atlas_point_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .INTERACTION_SHADOW_ATLAS_PARALLEL, "builtin/lighting/interactionSM", "_atlas_parallel", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .INTERACTION_SHADOW_ATLAS_PARALLEL_SKINNED, "builtin/lighting/interactionSM", "_atlas_parallel_skinned", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "0" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .PBR_INTERACTION_SHADOW_ATLAS_SPOT, "builtin/lighting/interactionSM", "_atlas_spot_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .PBR_INTERACTION_SHADOW_ATLAS_SPOT_SKINNED, "builtin/lighting/interactionSM", "_atlas_spot_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .PBR_INTERACTION_SHADOW_ATLAS_POINT, "builtin/lighting/interactionSM", "_atlas_point_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .PBR_INTERACTION_SHADOW_ATLAS_POINT_SKINNED, "builtin/lighting/interactionSM", "_atlas_point_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "1" }, &.{ "LIGHT_PARALLEL", "0" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            .{ .PBR_INTERACTION_SHADOW_ATLAS_PARALLEL, "builtin/lighting/interactionSM", "_atlas_parallel_PBR", &.{ &.{ "USE_GPU_SKINNING", "0" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM },
            .{ .PBR_INTERACTION_SHADOW_ATLAS_PARALLEL_SKINNED, "builtin/lighting/interactionSM", "_atlas_parallel_skinned_PBR", &.{ &.{ "USE_GPU_SKINNING", "1" }, &.{ "LIGHT_POINT", "0" }, &.{ "LIGHT_PARALLEL", "1" }, &.{ "USE_PBR", "1" }, &.{ "USE_NORMAL_FMT_RGB8", "0" }, &.{ "USE_SHADOW_ATLAS", "1" } }, true, Shader.Stage.default, .DRAW_VERT, .DRAW_INTERACTION_SM_SKINNED },

            // debug stuff
            .{ .DEBUG_LIGHTGRID, "builtin/debug/lightgrid", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .DEBUG_LIGHTGRID_SKINNED, "builtin/debug/lightgrid", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .DEFAULT_SKINNED },

            .{ .DEBUG_OCTAHEDRON, "builtin/debug/octahedron", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .DEBUG_OCTAHEDRON_SKINNED, "builtin/debug/octahedron", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .DEFAULT_SKINNED },

            .{ .ENVIRONMENT, "builtin/legacy/environment", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .ENVIRONMENT_SKINNED, "builtin/legacy/environment", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .DEFAULT_SKINNED },
            .{ .BUMPY_ENVIRONMENT, "builtin/legacy/bumpyenvironment", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .NORMAL_CUBE },
            .{ .BUMPY_ENVIRONMENT_SKINNED, "builtin/legacy/bumpyenvironment", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .NORMAL_CUBE_SKINNED },

            .{ .DEPTH, "builtin/depth", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .CONSTANT_BUFFER_ONLY },
            .{ .DEPTH_SKINNED, "builtin/depth", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .CONSTANT_BUFFER_ONLY_SKINNED },

            .{ .BLENDLIGHT, "builtin/fog/blendLight", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .BLENDLIGHT },
            .{ .BLENDLIGHT_SKINNED, "builtin/fog/blendLight", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .BLENDLIGHT_SKINNED },
            .{ .FOG, "builtin/fog/fog", "", &.{&.{ "USE_GPU_SKINNING", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .FOG },
            .{ .FOG_SKINNED, "builtin/fog/fog", "_skinned", &.{&.{ "USE_GPU_SKINNING", "1" }}, true, Shader.Stage.default, .DRAW_VERT, .FOG_SKINNED },
            .{ .SKYBOX, "builtin/legacy/skybox", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .WOBBLESKY, "builtin/legacy/wobblesky", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .POSTPROCESS, "builtin/post/postprocess", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL },
            .{ .POSTPROCESS_RETRO_2BIT, "builtin/post/retro_2bit", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL },
            .{ .POSTPROCESS_RETRO_C64, "builtin/post/retro_c64", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL },
            .{ .POSTPROCESS_RETRO_CPC, "builtin/post/retro_cpc", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL2 },
            .{ .POSTPROCESS_RETRO_NES, "builtin/post/retro_nes", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL },
            .{ .POSTPROCESS_RETRO_GENESIS, "builtin/post/retro_genesis", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL },
            .{ .POSTPROCESS_RETRO_PSX, "builtin/post/retro_ps1", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL },
            .{ .CRT_MATTIAS, "builtin/post/crt_mattias", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_CRT },
            .{ .CRT_NUPIXIE, "builtin/post/crt_newpixie", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_CRT },
            .{ .CRT_EASYMODE, "builtin/post/crt_advanced", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .POST_PROCESS_FINAL }, // FINAL for linear filtering

            .{ .SCREEN, "builtin/post/screen", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .TONEMAP, "builtin/post/tonemap", "", &.{ &.{ "BRIGHTPASS", "0" }, &.{ "HDR_DEBUG", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .BRIGHTPASS, "builtin/post/tonemap", "_brightpass", &.{ &.{ "BRIGHTPASS", "1" }, &.{ "HDR_DEBUG", "0" } }, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .HDR_GLARE_CHROMATIC, "builtin/post/hdr_glare_chromatic", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .HDR_DEBUG, "builtin/post/tonemap", "_debug", &.{ &.{ "BRIGHTPASS", "0" }, &.{ "HDR_DEBUG", "1" } }, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },

            .{ .SMAA_EDGE_DETECTION, "builtin/post/SMAA_edge_detection", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .SMAA_BLENDING_WEIGHT_CALCULATION, "builtin/post/SMAA_blending_weight_calc", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .SMAA_NEIGHBORHOOD_BLENDING, "builtin/post/SMAA_final", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },

            .{ .MOTION_BLUR, "builtin/post/motionBlur", "_vectors", &.{&.{ "VECTORS_ONLY", "1" }}, false, Shader.Stage.default, .DRAW_VERT, .TAA_MOTION_VECTORS },
            .{ .TAA_RESOLVE, "builtin/post/taa", "", &.{ &.{ "SAMPLE_COUNT", "1" }, &.{ "USE_CATMULL_ROM_FILTER", "1" } }, false, Shader.Stage.compute, .UNKNOWN, .TAA_RESOLVE },
            .{ .TAA_RESOLVE_MSAA_2X, "builtin/post/taa", "_msaa2x", &.{ &.{ "SAMPLE_COUNT", "2" }, &.{ "USE_CATMULL_ROM_FILTER", "1" } }, false, Shader.Stage.compute, .UNKNOWN, .TAA_RESOLVE },
            .{ .TAA_RESOLVE_MSAA_4X, "builtin/post/taa", "_msaa4x", &.{ &.{ "SAMPLE_COUNT", "4" }, &.{ "USE_CATMULL_ROM_FILTER", "1" } }, false, Shader.Stage.compute, .UNKNOWN, .TAA_RESOLVE },
            .{ .TAA_RESOLVE_MSAA_8X, "builtin/post/taa", "_msaa8x", &.{ &.{ "SAMPLE_COUNT", "8" }, &.{ "USE_CATMULL_ROM_FILTER", "1" } }, false, Shader.Stage.compute, .UNKNOWN, .TAA_RESOLVE },

            .{ .AMBIENT_OCCLUSION, "builtin/SSAO/AmbientOcclusion_AO", "", &.{&.{ "BRIGHTPASS", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .DRAW_AO },
            .{ .AMBIENT_OCCLUSION_AND_OUTPUT, "builtin/SSAO/AmbientOcclusion_AO", "_write", &.{&.{ "BRIGHTPASS", "1" }}, false, Shader.Stage.default, .DRAW_VERT, .DRAW_AO },
            .{ .AMBIENT_OCCLUSION_BLUR, "builtin/SSAO/AmbientOcclusion_blur", "", &.{&.{ "BRIGHTPASS", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .DRAW_AO },
            .{ .AMBIENT_OCCLUSION_BLUR_AND_OUTPUT, "builtin/SSAO/AmbientOcclusion_blur", "_write", &.{&.{ "BRIGHTPASS", "1" }}, false, Shader.Stage.default, .DRAW_VERT, .DRAW_AO },
            .{ .DEEP_GBUFFER_RADIOSITY_SSGI, "builtin/SSGI/DeepGBufferRadiosity_radiosity", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .DEEP_GBUFFER_RADIOSITY_BLUR, "builtin/SSGI/DeepGBufferRadiosity_blur", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .DEEP_GBUFFER_RADIOSITY_BLUR_AND_OUTPUT, "builtin/SSGI/DeepGBufferRadiosity_blur", "_write", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },

            .{ .STEREO_DEGHOST, "builtin/VR/stereoDeGhost", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .STEREO_WARP, "builtin/VR/stereoWarp", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .BINK, "builtin/video/bink", "", &.{&.{ "USE_SRGB", "0" }}, false, Shader.Stage.default, .DRAW_VERT, .BINK_VIDEO },
            .{ .BINK_SRGB, "builtin/video/bink", "_srgb", &.{&.{ "USE_SRGB", "1" }}, false, Shader.Stage.default, .DRAW_VERT, .BINK_VIDEO },
            .{ .BINK_GUI, "builtin/video/bink_gui", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .BINK_VIDEO },
            .{ .STEREO_INTERLACE, "builtin/VR/stereoInterlace", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },
            .{ .MOTION_BLUR, "builtin/post/motionBlur", "", &.{&.{ "VECTORS_ONLY", "1" }}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },

            .{ .DEBUG_SHADOWMAP, "builtin/debug/debug_shadowmap", "", &.{}, false, Shader.Stage.default, .DRAW_VERT, .DEFAULT },

            .{ .BLIT, "builtin/blit", "", &.{&.{ "TEXTURE_ARRAY", "0" }}, false, Shader.Stage.fragment, .UNKNOWN, .BLIT },
            .{ .RECT, "builtin/rect", "", &.{}, false, Shader.Stage.vertex, .DRAW_VERT, .BLIT },
            .{ .TONEMAPPING, "builtin/post/tonemapping", "", &.{ &.{ "HISTOGRAM_BINS", "256" }, &.{ "SOURCE_ARRAY", "0" }, &.{ "QUAD_Z", "0" } }, false, Shader.Stage.default, .UNKNOWN, .TONEMAP },
            .{ .TONEMAPPING_TEX_ARRAY, "builtin/post/tonemapping", "", &.{ &.{ "HISTOGRAM_BINS", "256" }, &.{ "SOURCE_ARRAY", "1" }, &.{ "QUAD_Z", "0" } }, false, Shader.Stage.default, .UNKNOWN, .TONEMAP },
            .{ .HISTOGRAM_CS, "builtin/post/histogram", "", &.{ &.{ "HISTOGRAM_BINS", "256" }, &.{ "SOURCE_ARRAY", "0" } }, false, Shader.Stage.compute, .UNKNOWN, .HISTOGRAM },
            .{ .HISTOGRAM_TEX_ARRAY_CS, "builtin/post/histogram", "", &.{ &.{ "HISTOGRAM_BINS", "256" }, &.{ "SOURCE_ARRAY", "1" } }, false, Shader.Stage.compute, .UNKNOWN, .HISTOGRAM },
            .{ .EXPOSURE_CS, "builtin/post/exposure", "", &.{&.{ "HISTOGRAM_BINS", "256" }}, false, Shader.Stage.compute, .UNKNOWN, .EXPOSURE },
        };

        try prog_manager.renderProgs.setNum(builtins.len, allocator);

        for (prog_manager.renderProgs.slice(), &builtins, 0..) |*prog, *builtin, i| {
            const builtin_shader, const name, const suffix, const macros, const gpu_skinning, const stage, const vertex_layout, const binding_layout = builtin.*;

            prog.name = idlib.Str{};
            try prog.name.assignSlice(name, allocator);
            prog.builtin = true;
            prog.usesJoints = gpu_skinning;
            prog.vertexLayout = vertex_layout;
            prog.bindingLayoutType = binding_layout;
            prog_manager.builtinShaders[builtin_shader.toIndex()] = @intCast(i);

            const opt_vertex_index = if ((stage & Shader.Stage.vertex) != 0)
                prog_manager.findShader(
                    name,
                    Shader.Stage.vertex,
                    suffix,
                    macros,
                    true,
                    allocator,
                ) catch null
            else
                null;

            const opt_fragment_index = if ((stage & Shader.Stage.fragment) != 0)
                prog_manager.findShader(
                    name,
                    Shader.Stage.fragment,
                    suffix,
                    macros,
                    true,
                    allocator,
                ) catch null
            else
                null;

            const opt_compute_index = if ((stage & Shader.Stage.compute) != 0)
                prog_manager.findShader(
                    name,
                    Shader.Stage.compute,
                    suffix,
                    macros,
                    true,
                    allocator,
                ) catch null
            else
                null;

            const progs = prog_manager.renderProgs.slice();
            if (opt_vertex_index != null and opt_fragment_index != null) {
                prog_manager.loadProgram(
                    &progs[i],
                    opt_vertex_index.?,
                    opt_fragment_index.?,
                );
            }

            if (opt_compute_index) |compute_index| {
                prog_manager.loadComputeProgram(&progs[i], compute_index);
            }
        }

        // TODO: addCommand reloadShaders
    }

    pub fn shutdown(prog_manager: *RenderProgManager) void {
        c_renderProgManager_shutdown(prog_manager);
    }

    pub fn findProgramOrCreate(
        prog_manager: *RenderProgManager,
        name: []const u8,
        vertex_index: usize,
        fragment_index: usize,
        binding_type: common.BindingLayoutType,
        allocator: Allocator,
    ) Allocator.Error!usize {
        for (prog_manager.renderProgs.constSlice(), 0..) |prog, i| {
            if (prog.vertexShaderIndex == vertex_index and
                prog.fragmentShaderIndex == fragment_index)
            {
                return i;
            }
        }

        const index = try prog_manager.renderProgs.append(.{
            .vertexLayout = .DRAW_VERT,
            .bindingLayoutType = binding_type,
        }, allocator);

        const program = &prog_manager.renderProgs.slice()[index];
        try program.name.assignSlice(name, allocator);

        prog_manager.loadProgram(program, vertex_index, fragment_index);

        return index;
    }

    fn loadProgram(
        prog_manager: *RenderProgManager,
        prog: *RenderProg,
        vertex_index: usize,
        fragment_index: usize,
    ) void {
        prog.vertexShaderIndex = @intCast(vertex_index);
        prog.fragmentShaderIndex = @intCast(fragment_index);
        if (prog.vertexLayout != .UNKNOWN) {
            const descs = prog_manager.vertexLayoutDescs.constSlice();
            const shaders = prog_manager.shaders.constSlice();
            prog.inputLayout = prog_manager.device.createInputLayout(
                descs[prog.vertexLayout.toIndex()].constSlice(),
                shaders[@intCast(prog.vertexShaderIndex)].handle.ptr_,
            );
        }
        const binding_layouts = prog_manager.bindingLayouts.constSlice();
        prog.bindingLayouts = binding_layouts[prog.bindingLayoutType.toIndex()];
    }

    fn loadComputeProgram(
        prog_manager: *RenderProgManager,
        prog: *RenderProg,
        compute_index: usize,
    ) void {
        prog.computeShaderIndex = @intCast(compute_index);
        if (prog.vertexLayout != .UNKNOWN) {
            const descs = prog_manager.vertexLayoutDescs.constSlice();
            const shaders = prog_manager.shaders.constSlice();
            prog.inputLayout = prog_manager.device.createInputLayout(
                descs[prog.vertexLayout.toIndex()].constSlice(),
                shaders[@intCast(prog.vertexShaderIndex)].handle.ptr_,
            );
        }
        const binding_layouts = prog_manager.bindingLayouts.constSlice();
        prog.bindingLayouts = binding_layouts[prog.bindingLayoutType.toIndex()];
    }

    pub fn findShader(
        prog_manager: *RenderProgManager,
        path: []const u8,
        stage: Shader.StageType,
        suffix: []const u8,
        macros: []const []const []const u8,
        builtin: bool,
        allocator: Allocator,
    ) LoadShaderError!usize {
        const shader_name = fs.stripExtension(path);

        for (prog_manager.shaders.slice(), 0..) |*shader, i| {
            if (std.ascii.eqlIgnoreCase(shader.name.constSlice(), shader_name) and
                shader.stage == stage and
                std.ascii.eqlIgnoreCase(shader.nameOutSuffix.constSlice(), suffix))
            {
                try prog_manager.assureShaderLoaded(shader);
                return i;
            }
        }

        const index = try prog_manager.shaders.append(.{
            .shaderFeatures = 0,
            .builtin = builtin,
            .stage = stage,
        }, allocator);
        const shader = &prog_manager.shaders.slice()[index];
        try shader.name.assignSlice(shader_name, allocator);
        try shader.nameOutSuffix.assignSlice(suffix, allocator);

        try shader.macros.setNum(macros.len, allocator);

        for (shader.macros.slice(), macros) |*macro, in_macro| {
            macro.* = .{};
            const macro_name = in_macro[0];
            const macro_def = in_macro[1];

            try macro.name.assignSlice(macro_name, allocator);
            try macro.definition.assignSlice(macro_def, allocator);
        }

        try prog_manager.assureShaderLoaded(shader);
        return index;
    }

    fn assureShaderLoaded(
        prog_manager: *RenderProgManager,
        shader: *Shader,
    ) LoadShaderError!void {
        if (shader.handle.ptr_ != null) return;

        try prog_manager.loadShader(shader);
    }

    pub const LoadShaderError = fs.FileSystem.ReadFileAnyAllocError;
    fn loadShader(
        prog_manager: *RenderProgManager,
        shader: *Shader,
    ) LoadShaderError!void {
        const stage_name, const shader_type = switch (shader.stage) {
            Shader.Stage.vertex => .{ "vs", nvrhi.ShaderType.Vertex },
            Shader.Stage.fragment => .{ "ps", nvrhi.ShaderType.Pixel },
            Shader.Stage.compute => .{ "cs", nvrhi.ShaderType.Compute },
            else => unreachable,
        };

        var buffer = std.mem.zeroes([fs.max_os_path:0]u8);
        // TODO dxil support
        const adjusted_name = switch (device_manager.instance().getGraphicsApi()) {
            .VULKAN => std.fmt.bufPrintZ(
                &buffer,
                "renderprogs2/spirv/{s}.{s}.bin",
                .{ fs.stripExtension(shader.name.constSlice()), stage_name },
            ) catch return error.OutOfMemory,
            else => @panic("[RENDER PROG] Unsupported graphics api"),
        };

        const allocator = global.gpa.allocator();
        const blob = try fs.instance.readFileAnyAlloc(adjusted_name, allocator);
        defer allocator.free(blob);

        var constants = std.BoundedArray(shader_blob.ShaderConstant, 32)
            .init(0) catch unreachable;
        for (shader.macros.constSlice()) |*macro| {
            constants.append(.{
                .name = macro.name.constSlice(),
                .value = macro.definition.constSlice(),
            }) catch @panic("Buffer overflow");
        }

        const desc = nvrhi.ShaderDesc{ .shaderType = shader_type };

        if (createShaderPermutation(
            prog_manager.device,
            &desc,
            blob,
            constants.constSlice(),
        )) |shader_handle| {
            shader.handle = shader_handle;
        }
    }

    fn createShaderPermutation(
        device: *nvrhi.IDevice,
        desc: *const nvrhi.ShaderDesc,
        blob: []const u8,
        constants: []const shader_blob.ShaderConstant,
    ) ?nvrhi.ShaderHandle {
        const binary = shader_blob.findPermutationInBlob(blob, constants) orelse
            return null;

        return device.createShader(desc, binary);
    }
};

pub const instance = @extern(*RenderProgManager, .{ .name = "renderProgManager" });
