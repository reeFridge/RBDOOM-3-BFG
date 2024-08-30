const nvrhi = @import("nvrhi.zig");
const ViewDef = @import("common.zig").ViewDef;
const Image = @import("image.zig").Image;

fn CppStdUnorderedMap(Key: type, T: type, Hash: type) type {
    _ = Key;
    _ = T;
    _ = Hash;

    return extern struct {
        table: [40]u8,
    };
}

pub const CommonRenderPasses = extern struct {
    const PsoCacheKey = extern struct {
        const Hash = extern struct {};

        fbinfo: nvrhi.FramebufferInfoEx,
        shader: *nvrhi.IShader,
        blendState: nvrhi.BlendState.RenderTarget,
    };

    m_Device: nvrhi.DeviceHandle,
    m_BlitPsoCache: CppStdUnorderedMap(PsoCacheKey, nvrhi.GraphicsPipelineHandle, PsoCacheKey.Hash),
    m_RectVS: nvrhi.ShaderHandle,
    m_BlitPS: nvrhi.ShaderHandle,
    m_BlitArrayPS: nvrhi.ShaderHandle,
    m_SharpenPS: nvrhi.ShaderHandle,
    m_SharpenArrayPS: nvrhi.ShaderHandle,
    m_BlackTexture: nvrhi.TextureHandle,
    m_GrayTexture: nvrhi.TextureHandle,
    m_WhiteTexture: nvrhi.TextureHandle,
    m_BlackTexture2DArray: nvrhi.TextureHandle,
    m_WhiteTexture2DArray: nvrhi.TextureHandle,
    m_BlackCubeMapArray: nvrhi.TextureHandle,
    m_PointClampSampler: nvrhi.SamplerHandle,
    m_PointWrapSampler: nvrhi.SamplerHandle,
    m_LinearClampSampler: nvrhi.SamplerHandle,
    m_LinearBorderSampler: nvrhi.SamplerHandle, // D3 zeroClamp
    m_LinearClampCompareSampler: nvrhi.SamplerHandle,
    m_LinearWrapSampler: nvrhi.SamplerHandle,
    m_AnisotropicWrapSampler: nvrhi.SamplerHandle,
    m_AnisotropicClampEdgeSampler: nvrhi.SamplerHandle,
    m_BlitBindingLayout: nvrhi.BindingLayoutHandle,

    extern fn c_commonRenderPasses_init(*CommonRenderPasses, *nvrhi.IDevice) callconv(.C) void;
    extern fn c_commonRenderPasses_shutdown(*CommonRenderPasses) callconv(.C) void;

    pub fn init(common_pass: *CommonRenderPasses, device: *nvrhi.IDevice) void {
        //common_pass.m_Device = nvrhi.DeviceHandle.init(device);
        c_commonRenderPasses_init(common_pass, device);
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
};
