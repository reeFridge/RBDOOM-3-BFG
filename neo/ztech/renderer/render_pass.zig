const std = @import("std");
const nvrhi = @import("nvrhi.zig");
const CVec4 = @import("../math/vector.zig").CVec4;
const CVec2 = @import("../math/vector.zig").CVec2;
const Vec2 = @import("../math/vector.zig").Vec2;
const ViewDef = @import("common.zig").ViewDef;
const Image = @import("image.zig").Image;
const Allocator = std.mem.Allocator;
const RenderProgManager = @import("render_prog_manager.zig").RenderProgManager;
const Shader = @import("render_prog_manager.zig").Shader;
const render_backend = @import("render_backend.zig");

fn CppStdUnorderedMap(Key: type, T: type, Hash: type) type {
    _ = Hash;

    return extern struct {
        const Self = @This();

        table: [40]u8,

        extern fn c_unorderedMap_getOrCreateRef(*anyopaque, Key) *T;

        fn getOrCreateRef(self: *Self, key: Key) *T {
            return c_unorderedMap_getOrCreateRef(@ptrCast(self), key);
        }
    };
}

pub const BlitConstants = extern struct {
    source_origin: CVec2,
    source_size: CVec2,
    target_origin: CVec2,
    target_size: CVec2,
    sharpen_factor: f32 = 0,
};

pub const BlitSampler = enum(u32) {
    point,
    linear,
    sharpen,
};

pub const BlitParameters = extern struct {
    target_framebuffer: ?*nvrhi.IFramebuffer = null,
    target_viewport: nvrhi.Viewport = .{},
    target_box: CVec4 = .{ .x = 0, .y = 0, .z = 1, .w = 1 },
    source_texture: ?*nvrhi.ITexture = null,
    source_array_slice: u32 = 0,
    source_mip: u32 = 0,
    source_box: CVec4 = .{ .x = 0, .y = 0, .z = 1, .w = 1 },
    sampler: BlitSampler = .linear,
    blend_state: nvrhi.BlendState.RenderTarget = .{},
    blend_constant_color: nvrhi.Color = .{},
};

pub const CommonRenderPasses = extern struct {
    const PsoCacheKey = extern struct {
        const Hash = extern struct {};

        fb_info: nvrhi.FramebufferInfoEx,
        shader: *nvrhi.IShader,
        blend_state: nvrhi.BlendState.RenderTarget,
    };

    device_handle: nvrhi.DeviceHandle,
    blit_pso_cache: CppStdUnorderedMap(
        PsoCacheKey,
        nvrhi.GraphicsPipelineHandle,
        PsoCacheKey.Hash,
    ),
    rect_vs: nvrhi.ShaderHandle,
    blit_ps: nvrhi.ShaderHandle,
    blit_array_ps: nvrhi.ShaderHandle,
    sharpen_ps: nvrhi.ShaderHandle,
    sharpen_array_ps: nvrhi.ShaderHandle,
    black_texture: nvrhi.TextureHandle,
    gray_texture: nvrhi.TextureHandle,
    white_texture: nvrhi.TextureHandle,
    black_texture_2d_array: nvrhi.TextureHandle,
    white_texture_2d_array: nvrhi.TextureHandle,
    black_cube_map_array: nvrhi.TextureHandle,
    point_clamp_sampler: nvrhi.SamplerHandle,
    point_wrap_sampler: nvrhi.SamplerHandle,
    linear_clamp_sampler: nvrhi.SamplerHandle,
    linear_border_sampler: nvrhi.SamplerHandle, // D3 zeroClamp
    linear_clamp_compare_sampler: nvrhi.SamplerHandle,
    linear_wrap_sampler: nvrhi.SamplerHandle,
    anisotropic_wrap_sampler: nvrhi.SamplerHandle,
    anisotropic_clamp_edge_sampler: nvrhi.SamplerHandle,
    blit_binding_layout: nvrhi.BindingLayoutHandle,

    extern fn c_commonRenderPasses_shutdown(*CommonRenderPasses) callconv(.C) void;

    pub const InitError = RenderProgManager.LoadShaderError;
    pub fn init(
        common_pass: *CommonRenderPasses,
        device: *nvrhi.IDevice,
        prog_manager: *RenderProgManager,
        allocator: Allocator,
    ) InitError!void {
        common_pass.device_handle = nvrhi.DeviceHandle.init(device);

        {
            const rect_index = try prog_manager.findShader(
                "builtin/rect",
                Shader.Stage.vertex,
                "",
                &.{},
                true,
                allocator,
            );
            common_pass.rect_vs = nvrhi.ShaderHandle.init(
                prog_manager.shaders.constSlice()[rect_index].handle.ptr_,
            );
        }

        {
            const blit_index = try prog_manager.findShader(
                "builtin/blit",
                Shader.Stage.fragment,
                "",
                &.{&.{ "TEXTURE_ARRAY", "0" }},
                true,
                allocator,
            );
            common_pass.blit_ps = nvrhi.ShaderHandle.init(
                prog_manager.shaders.constSlice()[blit_index].handle.ptr_,
            );
        }

        {
            const blit_index = try prog_manager.findShader(
                "builtin/blit",
                Shader.Stage.fragment,
                "",
                &.{&.{ "TEXTURE_ARRAY", "1" }},
                true,
                allocator,
            );
            common_pass.blit_array_ps = nvrhi.ShaderHandle.init(
                prog_manager.shaders.constSlice()[blit_index].handle.ptr_,
            );
        }

        common_pass.point_clamp_sampler = device.createSampler(&.{
            .minFilter = false,
            .magFilter = false,
            .mipFilter = false,
            .addressU = .ClampToEdge,
            .addressV = .ClampToEdge,
            .addressW = .ClampToEdge,
        });

        common_pass.point_wrap_sampler = device.createSampler(&.{
            .minFilter = false,
            .magFilter = false,
            .mipFilter = false,
            .addressU = .Repeat,
            .addressV = .Repeat,
            .addressW = .Repeat,
        });

        common_pass.linear_clamp_sampler = device.createSampler(&.{
            .minFilter = true,
            .magFilter = true,
            .mipFilter = true,
            .addressU = .ClampToEdge,
            .addressV = .ClampToEdge,
            .addressW = .ClampToEdge,
        });

        common_pass.linear_border_sampler = device.createSampler(&.{
            .borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .minFilter = true,
            .magFilter = true,
            .mipFilter = true,
            .addressU = .ClampToBorder,
            .addressV = .ClampToBorder,
            .addressW = .ClampToBorder,
        });

        common_pass.linear_clamp_compare_sampler = device.createSampler(&.{
            .borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .minFilter = true,
            .magFilter = true,
            .mipFilter = true,
            .addressU = .ClampToBorder,
            .addressV = .ClampToBorder,
            .addressW = .ClampToBorder,
            .reductionType = .Comparison,
        });

        common_pass.linear_wrap_sampler = device.createSampler(&.{
            .borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .minFilter = true,
            .magFilter = true,
            .mipFilter = true,
            .addressU = .Repeat,
            .addressV = .Repeat,
            .addressW = .Repeat,
            .reductionType = .Comparison,
        });

        common_pass.anisotropic_wrap_sampler = device.createSampler(&.{
            .maxAnisotropy = 16,
            .borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .minFilter = true,
            .magFilter = true,
            .mipFilter = true,
            .addressU = .Repeat,
            .addressV = .Repeat,
            .addressW = .Repeat,
            .reductionType = .Comparison,
        });

        common_pass.anisotropic_clamp_edge_sampler = device.createSampler(&.{
            .maxAnisotropy = 16,
            .borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 },
            .minFilter = true,
            .magFilter = true,
            .mipFilter = true,
            .addressU = .ClampToEdge,
            .addressV = .ClampToEdge,
            .addressW = .ClampToEdge,
            .reductionType = .Comparison,
        });

        common_pass.black_texture = device.createTexture(&.{
            .format = .RGBA8_UNORM,
            .width = 1,
            .height = 1,
            .mipLevels = 1,
        });

        common_pass.gray_texture = device.createTexture(&.{
            .format = .RGBA8_UNORM,
            .width = 1,
            .height = 1,
            .mipLevels = 1,
        });

        common_pass.white_texture = device.createTexture(&.{
            .format = .RGBA8_UNORM,
            .width = 1,
            .height = 1,
            .mipLevels = 1,
        });

        common_pass.black_cube_map_array = device.createTexture(&.{
            .format = .RGBA8_UNORM,
            .width = 1,
            .height = 1,
            .mipLevels = 1,
            .arraySize = 6,
            .dimension = .TextureCubeArray,
        });

        common_pass.black_texture_2d_array = device.createTexture(&.{
            .format = .RGBA8_UNORM,
            .width = 1,
            .height = 1,
            .mipLevels = 1,
            .arraySize = 6,
            .dimension = .Texture2DArray,
        });

        common_pass.white_texture_2d_array = device.createTexture(&.{
            .format = .RGBA8_UNORM,
            .width = 1,
            .height = 1,
            .mipLevels = 1,
            .arraySize = 6,
            .dimension = .Texture2DArray,
        });

        // Write the textures using a temporary command_list
        {
            var command_list_handle = device.createCommandList(.{});
            defer command_list_handle.deinit();

            const command_list = command_list_handle.ptr_.?;

            command_list.open();

            command_list.beginTrackingTextureState(
                common_pass.black_texture.ptr_.?,
                nvrhi.AllSubresources,
                .{ .Common = true },
            );

            command_list.beginTrackingTextureState(
                common_pass.white_texture.ptr_.?,
                nvrhi.AllSubresources,
                .{ .Common = true },
            );

            command_list.beginTrackingTextureState(
                common_pass.black_cube_map_array.ptr_.?,
                nvrhi.AllSubresources,
                .{ .Common = true },
            );

            command_list.beginTrackingTextureState(
                common_pass.black_texture_2d_array.ptr_.?,
                nvrhi.AllSubresources,
                .{ .Common = true },
            );

            command_list.beginTrackingTextureState(
                common_pass.white_texture_2d_array.ptr_.?,
                nvrhi.AllSubresources,
                .{ .Common = true },
            );

            const black_image = std.mem.asBytes(&@as(u32, 0xff000000));
            command_list.writeTexture(
                common_pass.black_texture.ptr_.?,
                0,
                0,
                black_image.ptr,
                0,
                0,
            );

            const gray_image = std.mem.asBytes(&@as(u32, 0xff808080));
            command_list.writeTexture(
                common_pass.gray_texture.ptr_.?,
                0,
                0,
                gray_image.ptr,
                0,
                0,
            );

            const white_image = std.mem.asBytes(&@as(u32, 0xffffffff));
            command_list.writeTexture(
                common_pass.white_texture.ptr_.?,
                0,
                0,
                white_image.ptr,
                0,
                0,
            );

            {
                var array_slice: u32 = 0;
                while (array_slice < 6) : (array_slice += 1) {
                    command_list.writeTexture(
                        common_pass.black_texture_2d_array.ptr_.?,
                        array_slice,
                        0,
                        black_image.ptr,
                        0,
                        0,
                    );

                    command_list.writeTexture(
                        common_pass.white_texture_2d_array.ptr_.?,
                        array_slice,
                        0,
                        white_image.ptr,
                        0,
                        0,
                    );

                    command_list.writeTexture(
                        common_pass.black_cube_map_array.ptr_.?,
                        array_slice,
                        0,
                        black_image.ptr,
                        0,
                        0,
                    );
                }
            }

            command_list.setPermanentTextureState(
                common_pass.black_texture.ptr_.?,
                .{ .ShaderResource = true },
            );

            command_list.setPermanentTextureState(
                common_pass.gray_texture.ptr_.?,
                .{ .ShaderResource = true },
            );

            command_list.setPermanentTextureState(
                common_pass.white_texture.ptr_.?,
                .{ .ShaderResource = true },
            );

            command_list.setPermanentTextureState(
                common_pass.black_cube_map_array.ptr_.?,
                .{ .ShaderResource = true },
            );

            command_list.setPermanentTextureState(
                common_pass.black_texture_2d_array.ptr_.?,
                .{ .ShaderResource = true },
            );

            command_list.setPermanentTextureState(
                common_pass.white_texture_2d_array.ptr_.?,
                .{ .ShaderResource = true },
            );

            command_list.commitBarriers();

            command_list.close();
            device.executeCommandList(command_list);
        }

        const BindingsArray = std.meta.FieldType(nvrhi.BindingLayoutDesc, .bindings);
        common_pass.blit_binding_layout = device.createBindingLayout(&.{
            .visibility = .All,
            .bindings = BindingsArray.fromSlice(&.{
                .{
                    .type = .PushConstants,
                    .slot = 0,
                    .size = @sizeOf(BlitConstants),
                },
                .{ .type = .Texture_SRV, .slot = 0 },
                .{ .type = .Sampler, .slot = 0 },
            }),
        });
    }

    pub fn shutdown(common_pass: *CommonRenderPasses) void {
        c_commonRenderPasses_shutdown(common_pass);
    }

    pub fn blitTexture(
        common_pass: *CommonRenderPasses,
        command_list: *nvrhi.ICommandList,
        blit_params: BlitParameters,
        opt_binding_cache: ?*render_backend.BindingCache,
        allocator: Allocator,
    ) Allocator.Error!void {
        const target_framebuffer = blit_params.target_framebuffer orelse @panic("no target framebuffer");
        const source_texture = blit_params.source_texture orelse @panic("no source texture");

        const target_fb_desc = target_framebuffer.getDesc();
        std.debug.assert(target_fb_desc.colorAttachments.current_size == 1);
        std.debug.assert(target_fb_desc.colorAttachments.base[0].valid());
        std.debug.assert(target_fb_desc.depthAttachment.valid() == false);

        const fb_info = target_framebuffer.getFramebufferInfo();
        const source_desc = source_texture.getDesc();

        std.debug.assert(isSupportedBlitDimension(source_desc.dimension));
        const is_texture_array = isTextureArray(source_desc.dimension);

        const shader = switch (blit_params.sampler) {
            .point, .linear => if (is_texture_array)
                common_pass.blit_array_ps.ptr_.?
            else
                common_pass.blit_ps.ptr_.?,
            .sharpen => if (is_texture_array)
                common_pass.sharpen_array_ps.ptr_.?
            else
                common_pass.sharpen_ps.ptr_.?,
        };

        const pso_handle_ptr = common_pass.blit_pso_cache.getOrCreateRef(.{
            .fb_info = fb_info.*,
            .shader = shader,
            .blend_state = blit_params.blend_state,
        });

        const pso_ptr = if (pso_handle_ptr.ptr_) |ptr|
            ptr
        else pso_ptr: {
            const LayoutsArray = std.meta.FieldType(
                nvrhi.GraphicsPipelineDesc,
                .bindingLayouts,
            );

            var blend_state = nvrhi.BlendState{};
            blend_state.targets[0] = blit_params.blend_state;

            pso_handle_ptr.* = common_pass.device_handle.ptr_.?.createGraphicsPipeline(
                &.{
                    .bindingLayouts = LayoutsArray.fromSliceWithDefault(
                        &.{
                            common_pass.blit_binding_layout,
                        },
                        .{},
                    ),
                    .VS = common_pass.rect_vs,
                    .PS = nvrhi.ShaderHandle{ .ptr_ = shader },
                    .primType = .TriangleStrip,
                    .renderState = .{
                        .rasterState = .{
                            .cullMode = .None,
                        },
                        .depthStencilState = .{
                            .depthTestEnable = false,
                            .stencilEnable = false,
                        },
                        .blendState = blend_state,
                    },
                },
                target_framebuffer,
            );

            break :pso_ptr pso_handle_ptr.ptr_.?;
        };

        const binding_set_desc: nvrhi.BindingSetDesc = desc: {
            const source_dimension = if (source_desc.dimension == .TextureCube or
                source_desc.dimension == .TextureCubeArray)
                .Texture2DArray
            else
                source_desc.dimension;

            const source_subresources: nvrhi.TextureSubresourceSet = .{
                .baseMipLevel = blit_params.source_mip,
                .baseArraySlice = blit_params.source_array_slice,
            };

            const BindingsArray = std.meta.FieldType(nvrhi.BindingSetDesc, .bindings);

            break :desc .{
                .bindings = BindingsArray.fromSlice(&.{
                    nvrhi.BindingSetItem.createPushConstants(0, @sizeOf(BlitConstants)),
                    nvrhi.BindingSetItem.createTextureSrv(
                        0,
                        source_texture,
                        .UNKNOWN,
                        source_subresources,
                        source_dimension,
                    ),
                    nvrhi.BindingSetItem.createSampler(
                        0,
                        if (blit_params.sampler == .point)
                            common_pass.point_clamp_sampler.ptr_.?
                        else
                            common_pass.linear_clamp_sampler.ptr_.?,
                    ),
                }),
            };
        };

        var source_binding_set = if (opt_binding_cache) |binding_cache|
            try binding_cache.getOrCreateBindingSet(
                &binding_set_desc,
                common_pass.blit_binding_layout.ptr_.?,
                allocator,
            )
        else
            common_pass.device_handle.ptr_.?.createBindingSet(
                &binding_set_desc,
                common_pass.blit_binding_layout.ptr_.?,
            );
        defer source_binding_set.deinit();

        const target_viewport = if (blit_params.target_viewport.width() == 0 and
            blit_params.target_viewport.height() == 0)
            nvrhi.Viewport.fromWidthHeight(
                @floatFromInt(fb_info.width),
                @floatFromInt(fb_info.height),
            )
        else
            blit_params.target_viewport;

        const BindingSetVector = std.meta.FieldType(nvrhi.GraphicsState, .bindings);
        const ViewportArray = std.meta.FieldType(nvrhi.ViewportState, .viewports);
        const RectArray = std.meta.FieldType(nvrhi.ViewportState, .scissorRects);
        const state: nvrhi.GraphicsState = .{
            .pipeline = pso_ptr,
            .framebuffer = target_framebuffer,
            .blendConstantColor = blit_params.blend_constant_color,
            .bindings = BindingSetVector.fromSlice(&.{
                source_binding_set.ptr_.?,
            }),
            .viewport = .{
                .viewports = ViewportArray.fromSlice(&.{
                    target_viewport,
                }),
                .scissorRects = RectArray.fromSlice(&.{
                    nvrhi.Rect.fromViewport(&target_viewport),
                }),
            },
        };

        const blit_constants: BlitConstants = .{
            .source_origin = .{
                .x = blit_params.source_box.x,
                .y = blit_params.source_box.y,
            },
            .source_size = .{
                .x = blit_params.source_box.z,
                .y = blit_params.source_box.w,
            },
            .target_origin = .{
                .x = blit_params.target_box.x,
                .y = blit_params.target_box.y,
            },
            .target_size = .{
                .x = blit_params.target_box.z,
                .y = blit_params.target_box.w,
            },
        };

        command_list.setGraphicsState(&state);
        command_list.setPushConstants(
            @ptrCast(&blit_constants),
            @sizeOf(BlitConstants),
        );
        command_list.draw(&.{
            .instanceCount = 1,
            .vertexCount = 4,
        });
    }
};

fn isTextureArray(dimension: nvrhi.TextureDimension) bool {
    return dimension == .Texture2DArray or
        dimension == .TextureCube or
        dimension == .TextureCubeArray;
}

fn isSupportedBlitDimension(dimension: nvrhi.TextureDimension) bool {
    return dimension == .Texture2D or
        dimension == .Texture2DArray or
        dimension == .TextureCube or
        dimension == .TextureCubeArray;
}

pub const SsaoPass = opaque {
    extern fn c_ssaoPass_delete(*SsaoPass) callconv(.C) void;
    extern fn c_ssaoPass_create(
        *nvrhi.IDevice,
        *CommonRenderPasses,
        ?*nvrhi.ITexture,
        ?*nvrhi.ITexture,
        ?*nvrhi.ITexture,
    ) callconv(.C) *SsaoPass;

    pub fn create(
        device: *nvrhi.IDevice,
        common_passes: *CommonRenderPasses,
        gbuffer_depth: ?*nvrhi.ITexture,
        gbuffer_normals: ?*nvrhi.ITexture,
        destination_texture: ?*nvrhi.ITexture,
    ) *SsaoPass {
        return c_ssaoPass_create(
            device,
            common_passes,
            gbuffer_depth,
            gbuffer_normals,
            destination_texture,
        );
    }

    pub fn destroy(pass: *SsaoPass) void {
        c_ssaoPass_delete(pass);
    }
};

pub const MipMapGenPass = opaque {
    pub const Mode = enum(u8) {
        MODE_COLOR = 0, // bilinear reduction of RGB channels
        MODE_MIN = 1, // min() reduction of R channel
        MODE_MAX = 2, // max() reduction of R channel
        MODE_MINMAX = 3, // min() and max() reductions of R channel into RG channels
    };

    extern fn c_mipMapGenPass_delete(*MipMapGenPass) callconv(.C) void;
    extern fn c_mipMapGenPass_create(*nvrhi.IDevice, ?*nvrhi.ITexture, Mode) callconv(.C) *MipMapGenPass;

    pub fn create(
        device: *nvrhi.IDevice,
        texture: ?*nvrhi.ITexture,
        mode: Mode,
    ) *MipMapGenPass {
        return c_mipMapGenPass_create(device, texture, mode);
    }

    pub fn destroy(pass: *MipMapGenPass) void {
        c_mipMapGenPass_delete(pass);
    }
};

pub const TonemapPass = opaque {
    pub const CreateParameters = extern struct {
        isTextureArray: bool = false,
        histogramBins: u32 = 256,
        numConstantBufferVersions: u32 = 32,
        exposureBufferOverride: ?*nvrhi.IBuffer = null,
        colorLUT: ?*Image = null,
    };

    extern fn c_tonemapPass_delete(*TonemapPass) callconv(.C) void;
    extern fn c_tonemapPass_create() callconv(.C) *TonemapPass;
    extern fn c_tonemapPass_init(
        *TonemapPass,
        *nvrhi.IDevice,
        *CommonRenderPasses,
        *const CreateParameters,
        *nvrhi.IFramebuffer,
    ) callconv(.C) void;

    pub fn init(
        pass: *TonemapPass,
        device: *nvrhi.IDevice,
        common_passes: *CommonRenderPasses,
        params: CreateParameters,
        sample_framebuffer: *nvrhi.IFramebuffer,
    ) void {
        c_tonemapPass_init(
            pass,
            device,
            common_passes,
            &params,
            sample_framebuffer,
        );
    }

    pub fn create() *TonemapPass {
        return c_tonemapPass_create();
    }

    pub fn destroy(pass: *TonemapPass) void {
        c_tonemapPass_delete(pass);
    }
};

pub const TemporalAntiAliasingPass = opaque {
    pub const CreateParameters = extern struct {
        sourceDepth: ?*nvrhi.ITexture = null,
        motionVectors: ?*nvrhi.ITexture = null,
        unresolvedColor: ?*nvrhi.ITexture = null,
        resolvedColor: ?*nvrhi.ITexture = null,
        feedback1: ?*nvrhi.ITexture = null,
        feedback2: ?*nvrhi.ITexture = null,
        useCatmullRomFilter: bool = true,
        motionVectorStencilMask: u32 = 0,
        numConstantBufferVersions: u32 = 16,
    };

    extern fn c_temporalAntiAliasingPass_getCurrentPixelOffset(*TemporalAntiAliasingPass) CVec2;
    extern fn c_temporalAntiAliasingPass_advanceFrame(*TemporalAntiAliasingPass) callconv(.C) void;
    extern fn c_temporalAntiAliasingPass_delete(*TemporalAntiAliasingPass) callconv(.C) void;
    extern fn c_temporalAntiAliasingPass_create() callconv(.C) *TemporalAntiAliasingPass;
    extern fn c_temporalAntiAliasingPass_init(
        *TemporalAntiAliasingPass,
        *nvrhi.IDevice,
        *CommonRenderPasses,
        ?*const ViewDef,
        *const CreateParameters,
    ) callconv(.C) void;

    pub fn init(
        pass: *TemporalAntiAliasingPass,
        device: *nvrhi.IDevice,
        common_passes: *CommonRenderPasses,
        view_def: ?*const ViewDef,
        params: CreateParameters,
    ) void {
        c_temporalAntiAliasingPass_init(
            pass,
            device,
            common_passes,
            view_def,
            &params,
        );
    }

    pub fn create() *TemporalAntiAliasingPass {
        return c_temporalAntiAliasingPass_create();
    }

    pub fn destroy(pass: *TemporalAntiAliasingPass) void {
        c_temporalAntiAliasingPass_delete(pass);
    }

    pub fn advanceFrame(pass: *TemporalAntiAliasingPass) void {
        c_temporalAntiAliasingPass_advanceFrame(pass);
    }

    pub fn getCurrentPixelOffset(pass: *TemporalAntiAliasingPass) Vec2(f32) {
        return c_temporalAntiAliasingPass_getCurrentPixelOffset(pass).toVec2f();
    }
};
