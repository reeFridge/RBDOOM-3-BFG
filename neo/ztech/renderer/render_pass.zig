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
};

pub const SsaoPass = opaque {};
pub const MipMapGenPass = opaque {};
pub const TonemapPass = opaque {};
pub const TemporalAntiAliasingPass = opaque {};
