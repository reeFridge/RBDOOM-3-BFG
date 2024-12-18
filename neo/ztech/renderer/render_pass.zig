const std = @import("std");
const nvrhi = @import("nvrhi.zig");
const CVec2 = @import("../math/vector.zig").CVec2;
const Vec2 = @import("../math/vector.zig").Vec2;
const ViewDef = @import("common.zig").ViewDef;
const Image = @import("image.zig").Image;
const Allocator = std.mem.Allocator;
const RenderProgManager = @import("render_prog_manager.zig").RenderProgManager;
const Shader = @import("render_prog_manager.zig").Shader;

fn CppStdUnorderedMap(Key: type, T: type, Hash: type) type {
    _ = Key;
    _ = T;
    _ = Hash;

    return extern struct {
        table: [40]u8,
    };
}

pub const BlitConstants = extern struct {
    source_origin: CVec2,
    source_size: CVec2,
    target_origin: CVec2,
    target_size: CVec2,
    sharpen_factor: f32,
};

pub const CommonRenderPasses = extern struct {
    const PsoCacheKey = extern struct {
        const Hash = extern struct {};

        fbinfo: nvrhi.FramebufferInfoEx,
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

        common_pass.linear_wrap_sampler = device.createSampler(&.{
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
};

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
