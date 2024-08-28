const nvrhi = @import("nvrhi.zig");

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

    pub fn destroy(pass: *SsaoPass) void {
        c_ssaoPass_delete(pass);
    }
};

pub const MipMapGenPass = opaque {
    extern fn c_mipMapGenPass_delete(*MipMapGenPass) callconv(.C) void;

    pub fn destroy(pass: *MipMapGenPass) void {
        c_mipMapGenPass_delete(pass);
    }
};

pub const TonemapPass = opaque {
    extern fn c_tonemapPass_delete(*TonemapPass) callconv(.C) void;

    pub fn destroy(pass: *TonemapPass) void {
        c_tonemapPass_delete(pass);
    }
};

pub const TemporalAntiAliasingPass = opaque {
    extern fn c_temporalAntiAliasingPass_delete(*TemporalAntiAliasingPass) callconv(.C) void;

    pub fn destroy(pass: *TemporalAntiAliasingPass) void {
        c_temporalAntiAliasingPass_delete(pass);
    }
};
