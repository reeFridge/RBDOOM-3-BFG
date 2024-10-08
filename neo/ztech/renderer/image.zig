const nvrhi = @import("nvrhi.zig");
const idlib = @import("../idlib.zig");
const material = @import("material.zig");

const imageGeneratorFunction = fn (*Image, *nvrhi.ICommandList) void;

const TextureUsage = enum(c_int) {
    TD_SPECULAR, // may be compressed, and always zeros the alpha channel
    TD_DIFFUSE, // may be compressed
    TD_DEFAULT, // generic RGBA texture (particles, etc...)
    TD_BUMP, // may be compressed with 8 bit lookup
    TD_FONT, // Font image
    TD_LIGHT, // Light image
    TD_LOOKUP_TABLE_MONO, // Mono lookup table (including alpha)
    TD_LOOKUP_TABLE_ALPHA, // Alpha lookup table with a white color channel
    TD_LOOKUP_TABLE_RGB1, // RGB lookup table with a solid white alpha
    TD_LOOKUP_TABLE_RGBA, // RGBA lookup table
    TD_COVERAGE, // coverage map for fill depth pass when YCoCG is used
    TD_DEPTH, // depth buffer copy for motion blur
    // RB begin
    TD_SPECULAR_PBR_RMAO, // may be compressed, and always zeros the alpha channel, linear RGB R = roughness, G = metal, B = ambient occlusion
    TD_SPECULAR_PBR_RMAOD, // may be compressed, alpha channel contains displacement map
    TD_HIGHQUALITY_CUBE, // motorsep - Uncompressed cubemap texture (RGB colorspace)
    TD_LOWQUALITY_CUBE, // motorsep - Compressed cubemap texture (RGB colorspace DXT5)
    TD_SHADOW_ARRAY, // 2D depth buffer array for shadow mapping
    TD_RG16F,
    TD_RGBA16F,
    TD_RGBA16S,
    TD_RGBA32F,
    TD_R32F,
    TD_R11G11B10F, // memory efficient HDR RGB format with only 32bpp
    // RB end
    TD_R8F, // Stephen: Added for ambient occlusion render target.
    TD_LDR, // Stephen: Added for SRGB render target when tonemapping.
    TD_DEPTH_STENCIL, // depth buffer and stencil buffer
};

const CubeFiles = enum(c_int) {
    CF_2D, // not a cube map
    CF_NATIVE, // _px, _nx, _py, etc, directly sent to GL
    CF_CAMERA, // _forward, _back, etc, rotated and flipped as needed before sending to GL
    CF_QUAKE1, // _ft, _bk, etc, rotated and flipped as needed before sending to GL
    CF_PANORAMA, // TODO latlong encoded HDRI panorama typically used by Substance or Blender
    CF_2D_ARRAY, // not a cube map but not a single 2d texture either
    CF_2D_PACKED_MIPCHAIN, // usually 2d but can be an octahedron, packed mipmaps into single 2d texture atlas and limited to dim^2
    CF_SINGLE, // SP: A single texture cubemap. All six sides in one image.
};

const TextureType = enum(c_int) {
    TT_DISABLED,
    TT_2D,
    TT_CUBIC,
    // RB begin
    TT_2D_ARRAY,
    TT_2D_MULTISAMPLE,
    // RB end
};

const TextureFormat = enum(c_int) {
    FMT_NONE,

    //------------------------
    // Standard color image formats
    //------------------------

    FMT_RGBA8, // 32 bpp
    FMT_XRGB8, // 32 bpp

    //------------------------
    // Alpha channel only
    //------------------------

    // Alpha ends up being the same as L8A8 in our current implementation, because straight
    // alpha gives 0 for color, but we want 1.
    FMT_ALPHA,

    //------------------------
    // Luminance replicates the value across RGB with a constant A of 255
    // Intensity replicates the value across RGBA
    //------------------------

    FMT_L8A8, // 16 bpp
    FMT_LUM8, //  8 bpp
    FMT_INT8, //  8 bpp

    //------------------------
    // Compressed texture formats
    //------------------------

    FMT_DXT1, // 4 bpp
    FMT_DXT5, // 8 bpp

    //------------------------
    // Depth buffer formats
    //------------------------

    FMT_DEPTH, // 24 bpp

    //------------------------
    //
    //------------------------

    FMT_X16, // 16 bpp
    FMT_Y16_X16, // 32 bpp
    FMT_RGB565, // 16 bpp

    // RB: don't change above for .bimage compatibility up until RBDOOM-3-BFG 1.1
    FMT_ETC1_RGB8_OES, // 4 bpp
    FMT_SHADOW_ARRAY, // 32 bpp * 6
    FMT_RG16F, // 32 bpp
    FMT_RGBA16F, // 64 bpp
    FMT_RGBA32F, // 128 bpp
    FMT_R32F, // 32 bpp
    FMT_R11G11B10F, // 32 bpp

    // ^-- used up until RBDOOM-3-BFG 1.3
    FMT_R8,
    FMT_DEPTH_STENCIL, // 32 bpp
    FMT_RGBA16S, // 64 bpp
    FMT_SRGB8,
};

const TextureColor = enum(c_int) {
    CFM_DEFAULT, // RGBA
    CFM_NORMAL_DXT5, // XY format and use the fast DXT5 compressor
    CFM_YCOCG_DXT5, // convert RGBA to CoCg_Y format
    CFM_GREEN_ALPHA, // Copy the alpha channel to green

    // RB: don't change above for legacy .bimage compatibility
    CFM_YCOCG_RGBA8,
    // RB end
};

const ImageOptions = extern struct {
    textureType: TextureType,
    format: TextureFormat,
    colorFormat: TextureColor,
    samples: c_uint,
    width: c_int,
    height: c_int,
    numLevels: c_int,
    gammaMips: bool,
    readback: bool,
    isRenderTarget: bool,
    isUAV: bool,
};

const vulkan = @cImport(@cInclude("vulkan/vulkan.h"));
const vk_mem_alloc = @cImport(@cInclude("vk_mem_alloc.h"));

pub const Image = extern struct {
    imgName: idlib.idStr,
    cubeFiles: CubeFiles,
    generatorFunction: ?*const imageGeneratorFunction,
    usage: TextureUsage,
    opts: ImageOptions,
    filter: material.TextureFilter,
    repeat: material.TextureRepeat,
    isLoaded: bool,
    referencedOutsideLevelLoad: bool,
    levelLoadReferenced: bool,
    defaulted: bool,
    sourceFileTime: idlib.ID_TIME_T,
    binaryFileTime: idlib.ID_TIME_T,
    refCount: c_int,
    texture: nvrhi.TextureHandle,
    sampler: nvrhi.SamplerHandle,
    samplerDesc: nvrhi.SamplerDesc,
    image: vulkan.VkImage,
    allocation: vk_mem_alloc.VmaAllocation,

    pub fn getTextureHandle(image: *Image) nvrhi.TextureHandle {
        return nvrhi.TextureHandle.init(image.texture.ptr_);
    }

    pub fn getTexturePtr(image: *Image) ?*nvrhi.ITexture {
        return image.texture.ptr_;
    }

    pub fn getTextureID(image: *Image) ?*anyopaque {
        return @ptrCast(image.texture.ptr_);
    }
};

extern fn c_image_emptyGarbage() callconv(.C) void;

pub fn emptyGarbage() void {
    c_image_emptyGarbage();
}
