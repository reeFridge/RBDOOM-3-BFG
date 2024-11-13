const std = @import("std");
const render_system = @import("render_system.zig");
const fs = @import("../framework/file_system.zig");
const device_manager = @import("../sys/device_manager.zig");
const image_manager = @import("image_manager.zig");
const nvrhi = @import("nvrhi.zig");
const idlib = @import("../idlib.zig");
const material = @import("material.zig");
const frame_data = @import("frame_data.zig");
const BinaryImage = @import("binary_image.zig").BinaryImage;

pub const ImageGeneratorFunction = fn (*Image, *nvrhi.ICommandList) callconv(.C) void;

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

pub const TextureFormat = enum(c_int) {
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

pub const TextureColor = enum(c_int) {
    CFM_DEFAULT, // RGBA
    CFM_NORMAL_DXT5, // XY format and use the fast DXT5 compressor
    CFM_YCOCG_DXT5, // convert RGBA to CoCg_Y format
    CFM_GREEN_ALPHA, // Copy the alpha channel to green

    // RB: don't change above for legacy .bimage compatibility
    CFM_YCOCG_RGBA8,
    // RB end
};

const ImageOptions = extern struct {
    textureType: TextureType = .TT_2D,
    format: TextureFormat = .FMT_NONE,
    colorFormat: TextureColor = .CFM_DEFAULT,
    samples: u32 = 1,
    width: u32 = 0,
    height: u32 = 0,
    numLevels: u32 = 0,
    gammaMips: bool = false,
    readback: bool = false,
    isRenderTarget: bool = false,
    isUAV: bool = false,
};

const vulkan = @cImport(@cInclude("vulkan/vulkan.h"));
const vk_mem_alloc = @cImport(@cInclude("vk_mem_alloc.h"));

pub const Image = extern struct {
    var garbage_index: usize = 0;
    var image_garbage: [frame_data.NUM_FRAME_DATA]idlib.idList(vulkan.VkImage) = undefined;
    var allocation_garbage: [frame_data.NUM_FRAME_DATA]idlib.idList(vk_mem_alloc.VmaAllocation) = undefined;

    imgName: idlib.idStr = .{},
    cubeFiles: CubeFiles = .CF_2D,
    cubeMapSize: u32 = 0,
    generatorFunction: ?*const ImageGeneratorFunction = null,
    usage: TextureUsage = .TD_DEFAULT,
    opts: ImageOptions = .{},
    filter: material.TextureFilter = .TF_DEFAULT,
    repeat: material.TextureRepeat = .TR_REPEAT,
    isLoaded: bool = false,
    referencedOutsideLevelLoad: bool = false,
    levelLoadReferenced: bool = false,
    defaulted: bool = false,
    sourceFileTime: idlib.ID_TIME_T = fs.FILE_NOT_FOUND_TIMESTAMP,
    binaryFileTime: idlib.ID_TIME_T = fs.FILE_NOT_FOUND_TIMESTAMP,
    refCount: u32 = 0,
    texture: nvrhi.TextureHandle = .{},
    sampler: nvrhi.SamplerHandle = .{},
    samplerDesc: nvrhi.SamplerDesc = .{},
    image: vulkan.VkImage = null,
    allocation: vk_mem_alloc.VmaAllocation = null,

    pub fn init(image: *Image, name: []const u8) error{OutOfMemory}!void {
        image.imgName.initEmptyBuffer();
        try image.imgName.assignSlice(name);

        _ = image.sampler.reset();
        _ = image.texture.reset();

        try image.addToDeferredLoad();
    }

    pub fn purgeImage(image: *Image) void {
        _ = image.texture.reset();

        if (device_manager.vma_allocator != null and image.image != null) {
            _ = Image.image_garbage[Image.garbage_index]
                .append(image.image) catch unreachable;
            _ = Image.allocation_garbage[Image.garbage_index]
                .append(image.allocation) catch unreachable;

            image.image = null;
            image.allocation = null;
        }

        _ = image.sampler.reset();
        image.isLoaded = false;
        image.defaulted = false;
    }

    pub fn makeDefault(image: *Image, opt_command_list: ?*nvrhi.ICommandList) error{OutOfMemory}!void {
        const size = 16;
        var data: [size][size][4]u8 = undefined;

        const com_developer = true;
        if (com_developer) {
            for (0..size) |y| {
                for (0..size) |x| {
                    data[y][x][0] = 32;
                    data[y][x][1] = 32;
                    data[y][x][2] = 32;
                    data[y][x][3] = 255;
                }
            }

            for (0..size) |x| {
                data[0][x][0] = 255;
                data[0][x][1] = 255;
                data[0][x][2] = 255;
                data[0][x][3] = 255;

                data[x][0][0] = 255;
                data[x][0][1] = 255;
                data[x][0][2] = 255;
                data[x][0][3] = 255;

                data[size - 1][x][0] = 255;
                data[size - 1][x][1] = 255;
                data[size - 1][x][2] = 255;
                data[size - 1][x][3] = 255;

                data[x][size - 1][0] = 255;
                data[x][size - 1][1] = 255;
                data[x][size - 1][2] = 255;
                data[x][size - 1][3] = 255;
            }
        } else {
            for (0..size) |y| {
                for (0..size) |x| {
                    data[y][x][0] = 0;
                    data[y][x][1] = 0;
                    data[y][x][2] = 0;
                    data[y][x][3] = 0;
                }
            }
        }

        try image.generateImage(
            @ptrCast(&data),
            size,
            size,
            .TF_DEFAULT,
            .TR_REPEAT,
            .TD_DEFAULT,
            opt_command_list,
            false,
            false,
            1,
            .CF_2D,
        );

        image.defaulted = true;
    }

    pub fn generateImage(
        image: *Image,
        pic: ?[*]const u8,
        width: u32,
        height: u32,
        filter: material.TextureFilter,
        repeat: material.TextureRepeat,
        usage: TextureUsage,
        opt_command_list: ?*nvrhi.ICommandList,
        is_render_target: bool,
        is_uav: bool,
        sample_count: u32,
        cube_files: CubeFiles,
    ) error{OutOfMemory}!void {
        image.purgeImage();

        image.filter = filter;
        image.repeat = repeat;
        image.usage = usage;
        image.cubeFiles = cube_files;

        image.opts.textureType = if (sample_count > 1) .TT_2D_MULTISAMPLE else .TT_2D;
        image.opts.width = width;
        image.opts.height = height;
        image.opts.numLevels = 0;
        image.opts.samples = sample_count;
        image.opts.isRenderTarget = is_render_target;
        image.opts.isUAV = is_uav;

        if (image.cubeFiles == .CF_2D_PACKED_MIPCHAIN) {
            image.opts.width = @intFromFloat(@as(f32, @floatFromInt(width)) * (2.0 / 3.0));
        }

        image.deriveOpts();

        if (pic == null or image.opts.textureType == .TT_2D_MULTISAMPLE) {
            image.createTexture();
            image.isLoaded = true;
        } else {
            var im = BinaryImage{};
            try im.init(image.imgName.constSlice());

            if (image.cubeFiles == .CF_2D_PACKED_MIPCHAIN) {
                im.load2DAtlasMipchainFromMemory(
                    width,
                    image.opts.height,
                    pic.?,
                    image.opts.numLevels,
                    image.opts.format,
                    image.opts.colorFormat,
                );
            } else {
                im.load2DFromMemory(
                    width,
                    height,
                    pic.?,
                    image.opts.numLevels,
                    image.opts.format,
                    image.opts.colorFormat,
                    image.opts.gammaMips,
                );
            }

            //common.loadPacifierBinarizeEnd();

            image.createTexture();

            if (opt_command_list) |command_list| {
                command_list.beginTrackingTextureState(
                    image.texture.ptr_.?,
                    nvrhi.AllSubresources,
                    nvrhi.ResourceStates.Common,
                );

                for (im.images.constSlice()) |*image_data| {
                    const img = image_data.header;
                    const data = image_data.data.?;

                    const row_pitch = getRowPitch(image.opts.format, img.width);
                    command_list.writeTexture(
                        image.texture.ptr_.?,
                        img.destZ,
                        img.level,
                        data,
                        row_pitch,
                        0,
                    );
                }

                command_list.setPermanentTextureState(
                    image.texture.ptr_.?,
                    .ShaderResource,
                );
                command_list.commitBarriers();
            }

            image.isLoaded = true;
        }
    }

    fn getRowPitch(format: TextureFormat, width: u32) u32 {
        if (format == .FMT_DXT1 or format == .FMT_DXT5) {
            const block_size = blockSizeForFormat(format);

            return @max(1, (width + 3) / 4) * block_size;
        }

        const bpe = bitsForFormat(format);
        return width * (bpe / 8);
    }

    fn bitsForFormat(format: TextureFormat) u32 {
        return switch (format) {
            .FMT_NONE => 0,
            .FMT_RGBA8 => 32,
            .FMT_XRGB8 => 32,
            .FMT_RGB565 => 16,
            .FMT_L8A8 => 16,
            .FMT_ALPHA => 8,
            .FMT_LUM8 => 8,
            .FMT_INT8 => 8,
            .FMT_DXT1 => 4,
            .FMT_DXT5 => 8,
            .FMT_ETC1_RGB8_OES => 4,
            .FMT_SHADOW_ARRAY => (32 * 6),
            .FMT_RG16F => 32,
            .FMT_RGBA16F => 64,
            .FMT_RGBA16S => 64,
            .FMT_RGBA32F => 128,
            .FMT_R32F => 32,
            .FMT_R11G11B10F => 32,
            .FMT_DEPTH => 32,
            .FMT_DEPTH_STENCIL => 32,
            .FMT_X16 => 16,
            .FMT_Y16_X16 => 32,
            .FMT_R8 => 4,
            else => unreachable,
        };
    }

    fn blockSizeForFormat(format: TextureFormat) u32 {
        return switch (format) {
            .FMT_NONE => 0,
            .FMT_DXT1 => 8,
            .FMT_DXT5 => 16,
            else => 1,
        };
    }

    fn deriveOpts(image: *Image) void {
        const opts = &image.opts;

        if (opts.format == .FMT_NONE) {
            opts.colorFormat = .CFM_DEFAULT;

            switch (image.usage) {
                .TD_COVERAGE => {
                    opts.format = .FMT_DXT1;
                    opts.colorFormat = .CFM_GREEN_ALPHA;
                },

                .TD_DEPTH => {
                    opts.format = .FMT_DEPTH;
                },

                // sp begin
                .TD_DEPTH_STENCIL => {
                    opts.format = .FMT_DEPTH_STENCIL;
                },
                // sp end

                .TD_SHADOW_ARRAY => {
                    opts.format = .FMT_SHADOW_ARRAY;
                },

                .TD_RG16F => {
                    opts.format = .FMT_RG16F;
                },

                .TD_RGBA16F => {
                    opts.format = .FMT_RGBA16F;
                },

                .TD_RGBA16S => {
                    opts.format = .FMT_RGBA16S;
                },

                .TD_RGBA32F => {
                    opts.format = .FMT_RGBA32F;
                },

                .TD_R32F => {
                    opts.format = .FMT_R32F;
                },

                .TD_R8F => {
                    opts.format = .FMT_R8;
                },

                .TD_R11G11B10F => {
                    opts.format = .FMT_R11G11B10F;
                },

                .TD_DIFFUSE => {
                    // TD_DIFFUSE gets only set to when its a diffuse texture for an interaction
                    opts.gammaMips = true;
                    opts.format = .FMT_DXT5;
                    opts.colorFormat = .CFM_YCOCG_DXT5;
                },
                .TD_SPECULAR => {
                    opts.gammaMips = true;
                    opts.format = .FMT_DXT1;
                    opts.colorFormat = .CFM_DEFAULT;
                },

                .TD_SPECULAR_PBR_RMAO => {
                    opts.gammaMips = false;
                    opts.format = .FMT_DXT1;
                    opts.colorFormat = .CFM_DEFAULT;
                },

                .TD_SPECULAR_PBR_RMAOD => {
                    opts.gammaMips = false;
                    opts.format = .FMT_DXT5;
                    opts.colorFormat = .CFM_DEFAULT;
                },

                .TD_DEFAULT => {
                    opts.gammaMips = true;
                    opts.format = .FMT_DXT5;
                    opts.colorFormat = .CFM_DEFAULT;
                },
                .TD_BUMP => {
                    opts.format = .FMT_DXT5;
                    opts.colorFormat = .CFM_NORMAL_DXT5;
                },
                .TD_FONT => {
                    opts.format = .FMT_DXT1;
                    opts.colorFormat = .CFM_GREEN_ALPHA;
                    opts.numLevels = 4; // We only support 4 levels because we align to 16 in the exporter
                    opts.gammaMips = true;
                },
                .TD_LIGHT => {
                    // TODO check binary format version
                    // D3 BFG assets require RGB565 but it introduces color banding
                    // mods would prefer .FMT_RGBA8
                    opts.format = .FMT_RGB565; //.FMT_RGBA8;
                    opts.gammaMips = true;
                },
                .TD_LOOKUP_TABLE_MONO => {
                    opts.format = .FMT_INT8;
                },
                .TD_LOOKUP_TABLE_ALPHA => {
                    opts.format = .FMT_ALPHA;
                },
                .TD_LOOKUP_TABLE_RGB1, .TD_LOOKUP_TABLE_RGBA => {
                    opts.format = .FMT_RGBA8;
                },
                // motorsep 05-17-2015; added this for uncompressed cubemap/skybox textures
                .TD_HIGHQUALITY_CUBE => {
                    opts.colorFormat = .CFM_DEFAULT;
                    opts.format = .FMT_RGBA8;
                    opts.gammaMips = true;
                },
                .TD_LOWQUALITY_CUBE => {
                    opts.colorFormat = .CFM_DEFAULT; // .CFM_YCOCG_DXT5;
                    opts.format = .FMT_DXT5;
                    opts.gammaMips = true;
                },
                else => {
                    opts.format = .FMT_RGBA8;
                    unreachable;
                },
            }
        }

        if (opts.numLevels == 0) {
            opts.numLevels = 1;

            if (image.filter == .TF_LINEAR or image.filter == .TF_NEAREST) {
                // don't create mip maps if we aren't going to be using them
            } else {
                var temp_width = opts.width;
                var temp_height = opts.height;
                while (temp_width > 1 or temp_height > 1) {
                    temp_width >>= 1;
                    temp_height >>= 1;
                    if ((opts.format == .FMT_DXT1 or opts.format == .FMT_DXT5 or opts.format == .FMT_ETC1_RGB8_OES) and
                        ((temp_width & 0x3) != 0 or (temp_height & 0x3) != 0))
                    {
                        break;
                    }
                    opts.numLevels += 1;
                }
            }
        }
    }

    fn createTexture(image: *Image) void {
        image.purgeImage();
        image.createSamplerDesc();

        const format: nvrhi.Format = switch (image.opts.format) {
            .FMT_RGBA8 => .RGBA8_UNORM,
            .FMT_XRGB8 => .X32G8_UINT,
            .FMT_RGB565 => .B5G6R5_UNORM,
            .FMT_ALPHA, .FMT_LUM8, .FMT_INT8, .FMT_R8 => .R8_UNORM,
            .FMT_L8A8 => .RG8_UNORM,
            .FMT_DXT1 => .BC1_UNORM,
            .FMT_DXT5 => .BC3_UNORM,
            .FMT_DEPTH, .FMT_SHADOW_ARRAY => .D32,
            //.FMT_DEPTH_STENCIL => if (device_manager.instance().m_DeviceParams.enableImageFormatD24S8)
            //    .D24S8
            //else
            //    .D32S8,
            .FMT_RG16F => .RG16_FLOAT,
            .FMT_RGBA16F => .RGBA16_FLOAT,
            .FMT_RGBA16S => .RGBA16_SNORM,
            .FMT_RGBA32F => .RGBA32_FLOAT,
            .FMT_R32F => .R32_FLOAT,
            .FMT_X16, .FMT_Y16_X16 => .RGBA8_UINT,
            // see http://what-when-how.com/Tutorial/topic-615ll9ug/Praise-for-OpenGL-ES-30-Programming-Guide-291.html
            .FMT_R11G11B10F => .R11G11B10_FLOAT,
            .FMT_SRGB8 => .SRGBA8_UNORM,
            else => {
                std.debug.print(
                    "[IMAGE][ERR] Unhandled image format {} in {s}\n",
                    .{ image.opts.format, image.imgName.constSlice() },
                );
                @panic("fatal");
            },
        };

        if (!render_system.instance.backend_initialized) return;

        const original_width = image.opts.width;
        const original_height = image.opts.height;
        var scaled_width = original_width;
        var scaled_height = original_height;

        if (image.isCompressed()) {
            scaled_width = @intCast(@as(i32, @intCast(original_width + 3)) & ~@as(i32, 3));
            scaled_height = @intCast(@as(i32, @intCast(original_height + 3)) & ~@as(i32, 3));
        }

        var texture_desc = nvrhi.TextureDesc{
            .dimension = .Texture2D,
            .width = scaled_width,
            .height = scaled_height,
            .format = format,
            .isUAV = image.opts.isUAV,
            .sampleCount = image.opts.samples,
            .mipLevels = image.opts.numLevels,
        };

        if (image.opts.colorFormat == .CFM_GREEN_ALPHA) {
            texture_desc.componentMapping.r = .One;
            texture_desc.componentMapping.g = .One;
            texture_desc.componentMapping.b = .One;
            texture_desc.componentMapping.a = .Green;
        } else if (image.opts.format == .FMT_LUM8) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Red;
            texture_desc.componentMapping.b = .Red;
            texture_desc.componentMapping.a = .One;
        } else if (image.opts.format == .FMT_L8A8) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Red;
            texture_desc.componentMapping.b = .Red;
            texture_desc.componentMapping.a = .Green;
        } else if (image.opts.format == .FMT_ALPHA) {
            texture_desc.componentMapping.r = .One;
            texture_desc.componentMapping.g = .One;
            texture_desc.componentMapping.b = .One;
            texture_desc.componentMapping.a = .Red;
        } else if (image.opts.format == .FMT_INT8) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Red;
            texture_desc.componentMapping.b = .Red;
            texture_desc.componentMapping.a = .Red;
        } else if (image.opts.format == .FMT_R11G11B10F) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Green;
            texture_desc.componentMapping.b = .Blue;
            texture_desc.componentMapping.a = .One;
        }

        if (image.opts.isRenderTarget) {
            texture_desc.initialState = .RenderTarget;
            texture_desc.clearValue = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
            texture_desc.isRenderTarget = true;
            texture_desc.keepInitialState = true;

            if (image.opts.format == .FMT_DEPTH or
                image.opts.format == .FMT_DEPTH_STENCIL or
                image.opts.format == .FMT_SHADOW_ARRAY)
            {
                texture_desc.initialState = .DepthWrite;
                texture_desc.clearValue = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
            }

            if (image.opts.isUAV) {
                // This is a hack to make cszBuffer and ambient occlusion uav work.
                texture_desc.isUAV = true;
            }
        }

        if (image.opts.textureType == .TT_2D) {
            texture_desc.dimension = .Texture2D;
        } else if (image.opts.textureType == .TT_CUBIC) {
            texture_desc.dimension = .TextureCube;
            texture_desc.arraySize = 6;
        } else if (image.opts.textureType == .TT_2D_ARRAY) {
            texture_desc.dimension = .Texture2DArray;
            texture_desc.arraySize = 6;
        } else if (image.opts.textureType == .TT_2D_MULTISAMPLE) {
            texture_desc.dimension = .Texture2DMS;
            texture_desc.arraySize = 1;
        }

        if (device_manager.vma_allocator) |vma_allocator| {
            const image_create_info = vulkan.VkImageCreateInfo{
                .sType = vulkan.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
                .flags = if (image.opts.textureType == .TT_CUBIC)
                    vulkan.VK_IMAGE_CREATE_CUBE_COMPATIBLE_BIT
                else
                    0,
                .imageType = vulkan.VK_IMAGE_TYPE_2D,
                .format = nvrhi.vulkan.convertFormat(format),
                .extent = .{
                    .width = scaled_width,
                    .height = scaled_height,
                    .depth = 1,
                },
                .mipLevels = image.opts.numLevels,
                .arrayLayers = texture_desc.arraySize,
                .samples = image.opts.samples,
                .tiling = vulkan.VK_IMAGE_TILING_OPTIMAL,
                .usage = selectImageUsage(&texture_desc),
                .sharingMode = vulkan.VK_SHARING_MODE_EXCLUSIVE,
                .initialLayout = vulkan.VK_IMAGE_LAYOUT_UNDEFINED,
            };

            const alloc_create_info = vk_mem_alloc.VmaAllocationCreateInfo{
                .usage = vk_mem_alloc.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
            };
            const result = vk_mem_alloc.vmaCreateImage(
                vma_allocator,
                @ptrCast(&image_create_info),
                @ptrCast(&alloc_create_info),
                @ptrCast(&image.image),
                @ptrCast(&image.allocation),
                null,
            );
            std.debug.assert(result == vulkan.VK_SUCCESS);

            const device = device_manager.instance().getDevice();
            image.texture = device.createHandleForNativeTexture(
                nvrhi.ObjectTypes.VK_Image,
                .{ .u = .{ .pointer = image.image } },
                &texture_desc,
            );
        }

        std.debug.assert(image.texture.ptr_ != null);
    }

    pub inline fn isCompressed(image: *const Image) bool {
        return image.opts.format == .FMT_DXT1 or image.opts.format == .FMT_DXT5;
    }

    fn createSamplerDesc(image: *Image) void {
        _ = image.sampler.reset();
        image.samplerDesc = .{
            .minFilter = false,
            .magFilter = false,
            .mipFilter = false,
            .maxAnisotropy = 1.0,
        };

        if (image.opts.format == .FMT_DEPTH or image.opts.format == .FMT_DEPTH_STENCIL) {
            image.samplerDesc.reductionType = .Comparison;
        }

        const r_maxAnisotropicFiltering = 8;

        switch (image.filter) {
            .TF_DEFAULT => {
                image.samplerDesc.minFilter = true;
                image.samplerDesc.magFilter = true;
                image.samplerDesc.mipFilter = true;
                image.samplerDesc.maxAnisotropy = r_maxAnisotropicFiltering;
            },

            .TF_LINEAR => {
                image.samplerDesc.minFilter = true;
                image.samplerDesc.magFilter = true;
                image.samplerDesc.mipFilter = true;
            },

            .TF_NEAREST => {
                image.samplerDesc.minFilter = false;
                image.samplerDesc.magFilter = false;
                image.samplerDesc.mipFilter = false;
            },

            .TF_NEAREST_MIPMAP => {
                image.samplerDesc.minFilter = true;
                image.samplerDesc.magFilter = true;
                image.samplerDesc.mipFilter = true;
            },
        }

        switch (image.repeat) {
            .TR_REPEAT => {
                image.samplerDesc.addressU = .Repeat;
                image.samplerDesc.addressV = .Repeat;
                image.samplerDesc.addressW = .Repeat;
            },

            .TR_CLAMP => {
                image.samplerDesc.addressU = .ClampToEdge;
                image.samplerDesc.addressV = .ClampToEdge;
                image.samplerDesc.addressW = .ClampToEdge;
            },

            .TR_CLAMP_TO_ZERO_ALPHA => {
                image.samplerDesc.borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
                image.samplerDesc.addressU = .ClampToBorder;
                image.samplerDesc.addressV = .ClampToBorder;
                image.samplerDesc.addressW = .ClampToBorder;
            },

            .TR_CLAMP_TO_ZERO => {
                image.samplerDesc.borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
                image.samplerDesc.addressU = .ClampToBorder;
                image.samplerDesc.addressV = .ClampToBorder;
                image.samplerDesc.addressW = .ClampToBorder;
            },
        }
    }

    fn addToDeferredLoad(image: *Image) error{OutOfMemory}!void {
        _ = try image_manager.instance.imagesToLoad.addUnique(&image);
    }

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

fn selectImageUsage(desc: *const nvrhi.TextureDesc) vulkan.VkImageUsageFlags {
    const format_info = nvrhi.getFormatInfo(desc.format);
    var usage_flags =
        vulkan.VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
        vulkan.VK_IMAGE_USAGE_TRANSFER_DST_BIT |
        vulkan.VK_IMAGE_USAGE_SAMPLED_BIT;

    if (desc.isRenderTarget) {
        usage_flags |= if (format_info.hasDepth or format_info.hasStencil)
            vulkan.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT
        else
            vulkan.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    }

    if (desc.isUAV)
        usage_flags |= vulkan.VK_IMAGE_USAGE_STORAGE_BIT;

    if (desc.isShadingRateSurface)
        usage_flags |= vulkan.VK_IMAGE_USAGE_FRAGMENT_SHADING_RATE_ATTACHMENT_BIT_KHR;

    return @intCast(usage_flags);
}
