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

pub const max_image_name = 256;

pub const TextureUsage = enum(c_int) {
    specular, // may be compressed, and always zeros the alpha channel
    diffuse, // may be compressed
    default, // generic RGBA texture (particles, etc...)
    bump, // may be compressed with 8 bit lookup
    font, // Font image
    light, // Light image
    lookup_table_mono, // Mono lookup table (including alpha)
    lookup_table_alpha, // Alpha lookup table with a white color channel
    lookup_table_rgb1, // RGB lookup table with a solid white alpha
    lookup_table_rgba, // RGBA lookup table
    coverage, // coverage map for fill depth pass when YCoCG is used
    depth, // depth buffer copy for motion blur
    specular_pbr_rmao, // may be compressed, and always zeros the alpha channel, linear RGB R = roughness, G = metal, B = ambient occlusion
    specular_pbr_rmaod, // may be compressed, alpha channel contains displacement map
    highquality_cube, // motorsep - Uncompressed cubemap texture (RGB colorspace)
    lowquality_cube, // motorsep - Compressed cubemap texture (RGB colorspace DXT5)
    shadow_array, // 2D depth buffer array for shadow mapping
    rg16f,
    rgba16f,
    rgba16s,
    rgba32f,
    r32f,
    r11g11b10f, // memory efficient HDR RGB format with only 32bpp
    r8f, // Stephen: Added for ambient occlusion render target.
    ldr, // Stephen: Added for SRGB render target when tonemapping.
    depth_stencil, // depth buffer and stencil buffer
};

pub const CubeFiles = enum(c_int) {
    @"2d", // not a cube map
    native, // _px, _nx, _py, etc, directly sent to GL
    camera, // _forward, _back, etc, rotated and flipped as needed before sending to GL
    quake1, // _ft, _bk, etc, rotated and flipped as needed before sending to GL
    panorama, // TODO latlong encoded HDRI panorama typically used by Substance or Blender
    @"2d_array", // not a cube map but not a single 2d texture either
    @"2d_packed_mipchain", // usually 2d but can be an octahedron, packed mipmaps into single 2d texture atlas and limited to dim^2
    single, // SP: A single texture cubemap. All six sides in one image.
};

pub const TextureType = enum(c_int) {
    disabled,
    @"2d",
    cubic,
    @"2d_array",
    @"2d_multisample",
};

pub const TextureFormat = enum(c_int) {
    none,
    rgba8, // 32 bpp
    xrgb8, // 32 bpp
    alpha,
    l8a8, // 16 bpp
    lum8, //  8 bpp
    int8, //  8 bpp
    dxt1, // 4 bpp
    dxt5, // 8 bpp
    depth, // 24 bpp
    x16, // 16 bpp
    y16_x16, // 32 bpp
    rgb565, // 16 bpp
    etc1_rgb8_oes, // 4 bpp
    shadow_array, // 32 bpp * 6
    rg16f, // 32 bpp
    rgba16f, // 64 bpp
    rgba32f, // 128 bpp
    r32f, // 32 bpp
    r11g11b10f, // 32 bpp
    r8,
    depth_stencil, // 32 bpp
    rgba16s, // 64 bpp
    srgb8,
};

pub const TextureColor = enum(c_int) {
    default, // RGBA
    normal_dxt5, // XY format and use the fast DXT5 compressor
    ycocg_dxt5, // convert RGBA to CoCg_Y format
    green_alpha, // Copy the alpha channel to green
    ycocg_rgba8,
};

const ImageOptions = extern struct {
    textureType: TextureType = .@"2d",
    format: TextureFormat = .none,
    colorFormat: TextureColor = .default,
    samples: u32 = 1,
    width: u32 = 0,
    height: u32 = 0,
    numLevels: u32 = 0,
    gammaMips: bool = false,
    readback: bool = false,
    isRenderTarget: bool = false,
    isUAV: bool = false,
};

const vulkan = @import("vulkan");
const c = @import("../sys/c_import.zig").c;

pub const Image = extern struct {
    var garbage_index: usize = 0;
    var image_garbage: [frame_data.NUM_FRAME_DATA]idlib.idList(vulkan.Image) = undefined;
    var allocation_garbage: [frame_data.NUM_FRAME_DATA]idlib.idList(c.VmaAllocation) = undefined;

    name: idlib.idStr = .{},
    cube_files: CubeFiles = .@"2d",
    cube_map_size: u32 = 0,
    generator_function: ?*const ImageGeneratorFunction = null,
    usage: TextureUsage = .default,
    opts: ImageOptions = .{},
    filter: material.TextureFilter = .default,
    repeat: material.TextureRepeat = .repeat,
    is_loaded: bool = false,
    referenced_outside_level_load: bool = false,
    level_load_referenced: bool = false,
    defaulted: bool = false,
    source_file_time: idlib.ID_TIME_T = fs.FILE_NOT_FOUND_TIMESTAMP,
    binary_file_time: idlib.ID_TIME_T = fs.FILE_NOT_FOUND_TIMESTAMP,
    ref_count: u32 = 0,
    texture: nvrhi.TextureHandle = .{},
    sampler: nvrhi.SamplerHandle = .{},
    sampler_desc: nvrhi.SamplerDesc = .{},
    image: vulkan.Image = .null_handle,
    allocation: c.VmaAllocation = null,

    pub fn reload(
        image: *Image,
        force: bool,
        command_list: *nvrhi.ICommandList,
    ) error{OutOfMemory}!void {
        if (image.generator_function) |gen_fn| {
            gen_fn(image, command_list);
            return;
        }

        if (!force) {
            const current_time: idlib.ID_TIME_T = fs.FILE_NOT_FOUND_TIMESTAMP;
            if (image.cube_files == .native or
                image.cube_files == .camera or
                image.cube_files == .quake1 or
                image.cube_files == .single)
            {
                // TODO: loadCubeImages();
            } else {
                // TODO: loadImageProgram();
            }

            if (current_time <= image.source_file_time) return;
        }

        image.purgeImage();
        try image.addToDeferredLoad();
    }

    pub fn init(image: *Image, name: []const u8) error{OutOfMemory}!void {
        image.name.initEmptyBuffer();
        try image.name.assignSlice(name);

        _ = image.sampler.reset();
        _ = image.texture.reset();

        try image.addToDeferredLoad();
    }

    pub fn purgeImage(image: *Image) void {
        _ = image.texture.reset();

        if (device_manager.vma_allocator != null and image.image != .null_handle) {
            _ = Image.image_garbage[Image.garbage_index]
                .append(image.image) catch unreachable;
            _ = Image.allocation_garbage[Image.garbage_index]
                .append(image.allocation) catch unreachable;

            image.image = .null_handle;
            image.allocation = null;
        }

        _ = image.sampler.reset();
        image.is_loaded = false;
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
            .default,
            .repeat,
            .default,
            opt_command_list,
            false,
            false,
            1,
            .@"2d",
        );

        image.defaulted = true;
    }

    pub fn generateShadowArray(
        image: *Image,
        width: u32,
        height: u32,
        filter: material.TextureFilter,
        repeat: material.TextureRepeat,
        usage: TextureUsage,
        _: *nvrhi.ICommandList,
    ) error{}!void {
        image.purgeImage();

        image.filter = filter;
        image.repeat = repeat;
        image.usage = usage;
        image.cube_files = .@"2d_array";

        image.opts.textureType = .@"2d_array";
        image.opts.width = width;
        image.opts.height = height;
        image.opts.numLevels = 0;
        image.opts.isRenderTarget = true;

        image.deriveOpts();

        // The image will be uploaded to the gpu on a deferred state.
        image.createTexture();

        image.is_loaded = true;
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
        image.cube_files = cube_files;

        image.opts.textureType = if (sample_count > 1) .@"2d_multisample" else .@"2d";
        image.opts.width = width;
        image.opts.height = height;
        image.opts.numLevels = 0;
        image.opts.samples = sample_count;
        image.opts.isRenderTarget = is_render_target;
        image.opts.isUAV = is_uav;

        if (image.cube_files == .@"2d_packed_mipchain") {
            image.opts.width = @intFromFloat(@as(f32, @floatFromInt(width)) * (2.0 / 3.0));
        }

        image.deriveOpts();

        if (pic == null or image.opts.textureType == .@"2d_multisample") {
            image.createTexture();
            image.is_loaded = true;
        } else {
            var im = BinaryImage{};
            try im.init(image.name.constSlice());

            if (image.cube_files == .@"2d_packed_mipchain") {
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
                    .{ .Common = true },
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
                    .{ .ShaderResource = true },
                );
                command_list.commitBarriers();
            }

            image.is_loaded = true;
        }
    }

    fn getRowPitch(format: TextureFormat, width: u32) u32 {
        if (format == .dxt1 or format == .dxt5) {
            const block_size = blockSizeForFormat(format);

            return @max(1, (width + 3) / 4) * block_size;
        }

        const bpe = bitsForFormat(format);
        return width * (bpe / 8);
    }

    fn bitsForFormat(format: TextureFormat) u32 {
        return switch (format) {
            .none => 0,
            .rgba8 => 32,
            .xrgb8 => 32,
            .rgb565 => 16,
            .l8a8 => 16,
            .alpha => 8,
            .lum8 => 8,
            .int8 => 8,
            .dxt1 => 4,
            .dxt5 => 8,
            .etc1_rgb8_oes => 4,
            .shadow_array => (32 * 6),
            .rg16f => 32,
            .rgba16f => 64,
            .rgba16s => 64,
            .rgba32f => 128,
            .r32f => 32,
            .r11g11b10f => 32,
            .depth => 32,
            .depth_stencil => 32,
            .x16 => 16,
            .y16_x16 => 32,
            .r8 => 4,
            else => unreachable,
        };
    }

    fn blockSizeForFormat(format: TextureFormat) u32 {
        return switch (format) {
            .none => 0,
            .dxt1 => 8,
            .dxt5 => 16,
            else => 1,
        };
    }

    fn deriveOpts(image: *Image) void {
        const opts = &image.opts;

        if (opts.format == .none) {
            opts.colorFormat = .default;

            switch (image.usage) {
                .coverage => {
                    opts.format = .dxt1;
                    opts.colorFormat = .green_alpha;
                },
                .depth => {
                    opts.format = .depth;
                },
                .depth_stencil => {
                    opts.format = .depth_stencil;
                },
                .shadow_array => {
                    opts.format = .shadow_array;
                },
                .rg16f => {
                    opts.format = .rg16f;
                },
                .rgba16f => {
                    opts.format = .rgba16f;
                },
                .rgba16s => {
                    opts.format = .rgba16s;
                },
                .rgba32f => {
                    opts.format = .rgba32f;
                },
                .r32f => {
                    opts.format = .r32f;
                },
                .r8f => {
                    opts.format = .r8;
                },
                .r11g11b10f => {
                    opts.format = .r11g11b10f;
                },
                .diffuse => {
                    // TD_DIFFUSE gets only set to when its a diffuse texture for an interaction
                    opts.gammaMips = true;
                    opts.format = .dxt5;
                    opts.colorFormat = .ycocg_dxt5;
                },
                .specular => {
                    opts.gammaMips = true;
                    opts.format = .dxt1;
                    opts.colorFormat = .default;
                },
                .specular_pbr_rmao => {
                    opts.gammaMips = false;
                    opts.format = .dxt1;
                    opts.colorFormat = .default;
                },
                .specular_pbr_rmaod => {
                    opts.gammaMips = false;
                    opts.format = .dxt5;
                    opts.colorFormat = .default;
                },
                .default => {
                    opts.gammaMips = true;
                    opts.format = .dxt5;
                    opts.colorFormat = .default;
                },
                .bump => {
                    opts.format = .dxt5;
                    opts.colorFormat = .normal_dxt5;
                },
                .font => {
                    opts.format = .dxt1;
                    opts.colorFormat = .green_alpha;
                    opts.numLevels = 4; // We only support 4 levels because we align to 16 in the exporter
                    opts.gammaMips = true;
                },
                .light => {
                    // TODO check binary format version
                    // D3 BFG assets require RGB565 but it introduces color banding
                    // mods would prefer .FMT_RGBA8
                    opts.format = .rgb565; //.FMT_RGBA8;
                    opts.gammaMips = true;
                },
                .lookup_table_mono => {
                    opts.format = .int8;
                },
                .lookup_table_alpha => {
                    opts.format = .alpha;
                },
                .lookup_table_rgb1, .lookup_table_rgba => {
                    opts.format = .rgba8;
                },
                .highquality_cube => {
                    opts.colorFormat = .default;
                    opts.format = .rgba8;
                    opts.gammaMips = true;
                },
                .lowquality_cube => {
                    opts.colorFormat = .default; // .CFM_YCOCG_DXT5;
                    opts.format = .dxt5;
                    opts.gammaMips = true;
                },
                else => {
                    opts.format = .rgba8;
                    unreachable;
                },
            }
        }

        if (opts.numLevels == 0) {
            opts.numLevels = 1;

            if (image.filter == .linear or image.filter == .nearest) {
                // don't create mip maps if we aren't going to be using them
            } else {
                var temp_width = opts.width;
                var temp_height = opts.height;
                while (temp_width > 1 or temp_height > 1) {
                    temp_width >>= 1;
                    temp_height >>= 1;
                    if ((opts.format == .dxt1 or
                        opts.format == .dxt5 or
                        opts.format == .etc1_rgb8_oes) and
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
            .rgba8 => .RGBA8_UNORM,
            .xrgb8 => .X32G8_UINT,
            .rgb565 => .B5G6R5_UNORM,
            .alpha, .lum8, .int8, .r8 => .R8_UNORM,
            .l8a8 => .RG8_UNORM,
            .dxt1 => .BC1_UNORM,
            .dxt5 => .BC3_UNORM,
            .depth, .shadow_array => .D32,
            .depth_stencil => if (device_manager.instance().device_params.enable_image_format_d24s8)
                .D24S8
            else
                .D32S8,
            .rg16f => .RG16_FLOAT,
            .rgba16f => .RGBA16_FLOAT,
            .rgba16s => .RGBA16_SNORM,
            .rgba32f => .RGBA32_FLOAT,
            .r32f => .R32_FLOAT,
            .x16, .y16_x16 => .RGBA8_UINT,
            // see http://what-when-how.com/Tutorial/topic-615ll9ug/Praise-for-OpenGL-ES-30-Programming-Guide-291.html
            .r11g11b10f => .R11G11B10_FLOAT,
            .srgb8 => .SRGBA8_UNORM,
            else => {
                std.debug.print(
                    "[IMAGE][ERR] Unhandled image format {} in {s}\n",
                    .{ image.opts.format, image.name.constSlice() },
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

        if (image.opts.colorFormat == .green_alpha) {
            texture_desc.componentMapping.r = .One;
            texture_desc.componentMapping.g = .One;
            texture_desc.componentMapping.b = .One;
            texture_desc.componentMapping.a = .Green;
        } else if (image.opts.format == .lum8) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Red;
            texture_desc.componentMapping.b = .Red;
            texture_desc.componentMapping.a = .One;
        } else if (image.opts.format == .l8a8) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Red;
            texture_desc.componentMapping.b = .Red;
            texture_desc.componentMapping.a = .Green;
        } else if (image.opts.format == .alpha) {
            texture_desc.componentMapping.r = .One;
            texture_desc.componentMapping.g = .One;
            texture_desc.componentMapping.b = .One;
            texture_desc.componentMapping.a = .Red;
        } else if (image.opts.format == .int8) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Red;
            texture_desc.componentMapping.b = .Red;
            texture_desc.componentMapping.a = .Red;
        } else if (image.opts.format == .r11g11b10f) {
            texture_desc.componentMapping.r = .Red;
            texture_desc.componentMapping.g = .Green;
            texture_desc.componentMapping.b = .Blue;
            texture_desc.componentMapping.a = .One;
        }

        if (image.opts.isRenderTarget) {
            texture_desc.initialState = .{ .RenderTarget = true };
            texture_desc.clearValue = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
            texture_desc.isRenderTarget = true;
            texture_desc.keepInitialState = true;

            if (image.opts.format == .depth or
                image.opts.format == .depth_stencil or
                image.opts.format == .shadow_array)
            {
                texture_desc.initialState = .{ .DepthWrite = true };
                texture_desc.clearValue = .{ .r = 1, .g = 1, .b = 1, .a = 1 };
            }

            if (image.opts.isUAV) {
                // This is a hack to make cszBuffer and ambient occlusion uav work.
                texture_desc.isUAV = true;
            }
        }

        if (image.opts.textureType == .@"2d") {
            texture_desc.dimension = .Texture2D;
        } else if (image.opts.textureType == .cubic) {
            texture_desc.dimension = .TextureCube;
            texture_desc.arraySize = 6;
        } else if (image.opts.textureType == .@"2d_array") {
            texture_desc.dimension = .Texture2DArray;
            texture_desc.arraySize = 6;
        } else if (image.opts.textureType == .@"2d_multisample") {
            texture_desc.dimension = .Texture2DMS;
            texture_desc.arraySize = 1;
        }

        if (device_manager.vma_allocator) |vma_allocator| {
            const image_create_info = vulkan.ImageCreateInfo{
                .flags = if (image.opts.textureType == .cubic)
                    .{ .cube_compatible_bit = true }
                else
                    .{},
                .image_type = .@"2d",
                .format = @enumFromInt(nvrhi.vulkan.convertFormat(format)),
                .extent = .{
                    .width = scaled_width,
                    .height = scaled_height,
                    .depth = 1,
                },
                .mip_levels = image.opts.numLevels,
                .array_layers = texture_desc.arraySize,
                .samples = vulkan.SampleCountFlags.fromInt(image.opts.samples),
                .tiling = .optimal,
                .usage = selectImageUsage(&texture_desc),
                .sharing_mode = .exclusive,
                .initial_layout = .undefined,
            };

            const alloc_create_info = c.VmaAllocationCreateInfo{
                .usage = c.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE,
            };

            const result = c.vmaCreateImage(
                vma_allocator,
                @ptrCast(&image_create_info),
                @ptrCast(&alloc_create_info),
                @ptrCast(&image.image),
                @ptrCast(&image.allocation),
                null,
            );
            std.debug.assert(result == @intFromEnum(vulkan.Result.success));

            const device = device_manager.instance().getDevice();
            image.texture = device.createHandleForNativeTexture(
                nvrhi.ObjectTypes.VK_Image,
                .{ .u = .{ .integer = @intFromEnum(image.image) } },
                &texture_desc,
            );
        }

        std.debug.assert(image.texture.ptr_ != null);
    }

    pub inline fn isCompressed(image: *const Image) bool {
        return image.opts.format == .dxt1 or image.opts.format == .dxt5;
    }

    fn createSamplerDesc(image: *Image) void {
        _ = image.sampler.reset();
        image.sampler_desc = .{
            .minFilter = false,
            .magFilter = false,
            .mipFilter = false,
            .maxAnisotropy = 1.0,
        };

        if (image.opts.format == .depth or image.opts.format == .depth_stencil) {
            image.sampler_desc.reductionType = .Comparison;
        }

        const r_maxAnisotropicFiltering = 8;

        switch (image.filter) {
            .default => {
                image.sampler_desc.minFilter = true;
                image.sampler_desc.magFilter = true;
                image.sampler_desc.mipFilter = true;
                image.sampler_desc.maxAnisotropy = r_maxAnisotropicFiltering;
            },
            .linear => {
                image.sampler_desc.minFilter = true;
                image.sampler_desc.magFilter = true;
                image.sampler_desc.mipFilter = true;
            },
            .nearest => {
                image.sampler_desc.minFilter = false;
                image.sampler_desc.magFilter = false;
                image.sampler_desc.mipFilter = false;
            },
            .nearest_mipmap => {
                image.sampler_desc.minFilter = true;
                image.sampler_desc.magFilter = true;
                image.sampler_desc.mipFilter = true;
            },
        }

        switch (image.repeat) {
            .repeat => {
                image.sampler_desc.addressU = .Repeat;
                image.sampler_desc.addressV = .Repeat;
                image.sampler_desc.addressW = .Repeat;
            },
            .clamp => {
                image.sampler_desc.addressU = .ClampToEdge;
                image.sampler_desc.addressV = .ClampToEdge;
                image.sampler_desc.addressW = .ClampToEdge;
            },
            .clamp_to_zero_alpha => {
                image.sampler_desc.borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 0 };
                image.sampler_desc.addressU = .ClampToBorder;
                image.sampler_desc.addressV = .ClampToBorder;
                image.sampler_desc.addressW = .ClampToBorder;
            },
            .clamp_to_zero => {
                image.sampler_desc.borderColor = .{ .r = 0, .g = 0, .b = 0, .a = 1 };
                image.sampler_desc.addressU = .ClampToBorder;
                image.sampler_desc.addressV = .ClampToBorder;
                image.sampler_desc.addressW = .ClampToBorder;
            },
        }
    }

    fn addToDeferredLoad(image: *Image) error{OutOfMemory}!void {
        _ = try image_manager.instance.images_to_load.addUnique(&image);
    }

    fn removeFromDeferredLoad(image: *Image) void {
        _ = image_manager.instance.images_to_load.remove(&image);
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

    pub fn actuallyLoadImage(_: *Image, _: bool, _: ?*nvrhi.ICommandList) error{}!void {
        @panic("not implemented");
    }
};

extern fn c_image_emptyGarbage() callconv(.C) void;

pub fn emptyGarbage() void {
    c_image_emptyGarbage();
}

fn selectImageUsage(desc: *const nvrhi.TextureDesc) vulkan.ImageUsageFlags {
    const format_info = nvrhi.getFormatInfo(desc.format);
    var usage_flags = vulkan.ImageUsageFlags{
        .transfer_src_bit = true,
        .transfer_dst_bit = true,
        .sampled_bit = true,
    };

    if (desc.isRenderTarget) {
        if (format_info.hasDepth or format_info.hasStencil) {
            usage_flags.depth_stencil_attachment_bit = true;
        } else {
            usage_flags.color_attachment_bit = true;
        }
    }

    if (desc.isUAV)
        usage_flags.storage_bit = true;

    if (desc.isShadingRateSurface)
        usage_flags.fragment_shading_rate_attachment_bit_khr = true;

    return usage_flags;
}
