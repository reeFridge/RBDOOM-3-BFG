const std = @import("std");
const global = @import("../global.zig");
const nvrhi = @import("nvrhi.zig");
const fs = @import("../framework/file_system.zig");
const idlib = @import("../idlib.zig");
const image_ = @import("image.zig");
const Image = image_.Image;
const RenderSystem = @import("render_system.zig");
const framebuffer = @import("framebuffer.zig");
const material = @import("material.zig");

pub const ImageManager = extern struct {
    defaultImage: ?*Image,
    flatNormalMap: ?*Image,
    alphaNotchImage: ?*Image,
    whiteImage: ?*Image,
    blackImage: ?*Image,
    blackDiffuseImage: ?*Image,
    cyanImage: ?*Image,
    noFalloffImage: ?*Image,
    fogImage: ?*Image,
    fogEnterImage: ?*Image,
    shadowAtlasImage: ?*Image,
    shadowImage: [5]?*Image,
    jitterImage1: ?*Image,
    jitterImage4: ?*Image,
    jitterImage16: ?*Image,
    grainImage1: ?*Image,
    randomImage256: ?*Image,
    blueNoiseImage256: ?*Image,
    currentRenderHDRImage: ?*Image,
    ldrImage: ?*Image,
    taaMotionVectorsImage: ?*Image,
    taaResolvedImage: ?*Image,
    taaFeedback1Image: ?*Image,
    taaFeedback2Image: ?*Image,
    bloomRenderImage: [2]?*Image,
    glowImage: [2]?*Image,
    glowDepthImage: [2]?*Image,
    accumTransparencyImage: ?*Image,
    revealTransparencyImage: ?*Image,
    envprobeHDRImage: ?*Image,
    envprobeDepthImage: ?*Image,
    heatmap5Image: ?*Image,
    heatmap7Image: ?*Image,
    smaaInputImage: ?*Image,
    smaaAreaImage: ?*Image,
    smaaSearchImage: ?*Image,
    smaaEdgesImage: ?*Image,
    smaaBlendImage: ?*Image,
    gbufferNormalsRoughnessImage: ?*Image,
    ambientOcclusionImage: [2]?*Image,
    hierarchicalZBufferImage: ?*Image,
    imguiFontImage: ?*Image,
    chromeSpecImage: ?*Image,
    plasticSpecImage: ?*Image,
    brdfLutImage: ?*Image,
    defaultUACIrradianceCube: ?*Image,
    defaultUACRadianceCube: ?*Image,
    scratchImage: ?*Image,
    scratchImage2: ?*Image,
    accumImage: ?*Image,
    currentRenderImage: ?*Image,
    currentDepthImage: ?*Image,
    originalCurrentRenderImage: ?*Image,
    loadingIconImage: ?*Image,
    hellLoadingIconImage: ?*Image,
    guiEdit: ?*Image,
    guiEditDepthStencilImage: ?*Image,

    images: idlib.idList(*Image),
    image_hash: idlib.idHashIndex,
    images_to_load: idlib.idList(*Image),
    inside_level_load: bool = false,
    preloading_map_images: bool = false,
    command_list: nvrhi.CommandListHandle = .{},

    extern fn c_imageManager_shutdown(*ImageManager) void;
    extern fn c_imageManager_purgeAllImages(*ImageManager) void;

    pub fn imageFromFile(
        image_manager: *ImageManager,
        arg_name: []const u8,
        filter: material.TextureFilter,
        repeat: material.TextureRepeat,
        arg_usage: image_.TextureUsage,
        cube_map: image_.CubeFiles,
        cube_map_size: u32,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!*Image {
        if (std.ascii.eqlIgnoreCase(arg_name, "default") or
            std.ascii.eqlIgnoreCase(arg_name, "_default"))
        {
            return image_manager.defaultImage.?;
        }

        const usage = if (std.ascii.eqlIgnoreCase(arg_name[0..@min(5, arg_name.len)], "fonts") or
            std.ascii.eqlIgnoreCase(arg_name[0..@min(8, arg_name.len)], "newfonts"))
            image_.TextureUsage.font
        else if (std.ascii.eqlIgnoreCase(arg_name[0..@min(6, arg_name.len)], "lights"))
            image_.TextureUsage.light
        else
            arg_usage;

        const ext = std.fs.path.extension(arg_name);
        const name = if (std.mem.eql(u8, ".tga", ext))
            arg_name[0 .. arg_name.len - ext.len]
        else
            arg_name[0..];

        const hash = idlib.idStr.fileNameHash(name);
        var i = image_manager.image_hash.first(hash);
        const images = image_manager.images.constSlice();
        while (i != -1) : (i = image_manager.image_hash.next(@intCast(i))) {
            const index: usize = @intCast(i);
            const image = images[index];

            if (std.ascii.eqlIgnoreCase(name, image.name.constSlice())) {
                // builtin - no need to check other options
                if (name[0] == '_') return image;

                if (image.cube_files != cube_map) {
                    std.debug.print(
                        "Image {s} has been referenced with conflicting cube_map states\n",
                        .{arg_name},
                    );
                    @panic("conflicting cube_map states");
                }

                if (image.filter != filter or
                    image.repeat != repeat or
                    image.usage != usage)
                {
                    continue;
                }

                image.usage = usage;
                image.level_load_referenced = true;

                if ((!image_manager.inside_level_load or image_manager.preloading_map_images) and
                    !image.is_loaded)
                {
                    image.referenced_outside_level_load =
                        !image_manager.inside_level_load and
                        !image_manager.preloading_map_images;

                    try image.actuallyLoadImage(null, allocator);
                }

                return image;
            }
        }

        const image = try image_manager.allocImage(name);
        image.cube_files = cube_map;
        image.cube_map_size = cube_map_size;
        image.usage = usage;
        image.filter = filter;
        image.repeat = repeat;
        image.level_load_referenced = true;

        if (!image_manager.inside_level_load or image_manager.preloading_map_images) {
            image.referenced_outside_level_load =
                !image_manager.inside_level_load and
                !image_manager.preloading_map_images;

            try image.actuallyLoadImage(null, allocator);
        }

        return image;
    }

    pub fn reloadImages(
        image_manager: *ImageManager,
        all: bool,
        command_list: *nvrhi.ICommandList,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!void {
        for (image_manager.images.constSlice()) |image| {
            try image.reload(all, command_list);
        }

        try image_manager.loadDeferredImages(command_list, allocator);
    }

    fn loadDeferredImages(
        image_manager: *ImageManager,
        command_list: *nvrhi.ICommandList,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!void {
        if (image_manager.inside_level_load) return;

        for (image_manager.images_to_load.slice()) |image| {
            try image.actuallyLoadImage(command_list, allocator);
        }

        image_manager.images_to_load.clear();
    }

    pub fn init(image_manager: *ImageManager) error{OutOfMemory}!void {
        try image_manager.images.resizeWithGranularity(1024, 1024);
        image_manager.image_hash = .{};
        try image_manager.image_hash.resizeIndex(1024);

        try image_manager.createIntrinsicImages();
        // TODO: addCommand reloadImages
        // TODO: addCommand listImages
        // TODO: addCommand combineCubeImages
        // TODO: image_manager.loadDeferredImages
    }

    pub fn shutdown(image_manager: *ImageManager) void {
        c_imageManager_shutdown(image_manager);
    }

    pub fn purgeAllImages(image_manager: *ImageManager) void {
        c_imageManager_purgeAllImages(image_manager);
    }

    fn createIntrinsicImages(image_manager: *ImageManager) error{OutOfMemory}!void {
        image_manager.defaultImage = try image_manager.imageFromFunction(
            "_default",
            image_gen.defaultImage,
        );

        image_manager.ldrImage = try image_manager.imageFromFunction(
            "_currentRenderLDR",
            image_gen.ldrNativeImage,
        );

        image_manager.currentRenderImage = try image_manager.imageFromFunction(
            "_currentRender",
            image_gen.hdrRGBA16FImageResNative,
        );

        image_manager.currentDepthImage = try image_manager.imageFromFunction(
            "_currentDepth",
            image_gen.depthImage,
        );

        image_manager.currentRenderHDRImage = try image_manager.imageFromFunction(
            "_currentRenderHDR",
            image_gen.hdrRGBA16FImageResNativeMSAAOpt,
        );

        image_manager.ambientOcclusionImage[0] = try image_manager.imageFromFunction(
            "_ao0",
            image_gen.ambientOcclusionImageResNative,
        );

        image_manager.ambientOcclusionImage[1] = try image_manager.imageFromFunction(
            "_ao1",
            image_gen.ambientOcclusionImageResNative,
        );

        image_manager.hierarchicalZBufferImage = try image_manager.imageFromFunction(
            "_cszBuffer",
            image_gen.hierarchicalZBufferImageResNative,
        );

        image_manager.gbufferNormalsRoughnessImage = try image_manager.imageFromFunction(
            "_currentNormals",
            image_gen.geometryBufferImageResNative,
        );

        image_manager.taaMotionVectorsImage = try image_manager.imageFromFunction(
            "_taaMotionVectors",
            image_gen.hdrRG16FImageResNative,
        );

        image_manager.taaResolvedImage = try image_manager.imageFromFunction(
            "_taaResolved",
            image_gen.hdrRGBA16FImageResNativeUav,
        );

        image_manager.taaFeedback1Image = try image_manager.imageFromFunction(
            "_taaFeedback1",
            image_gen.hdrRGBA16SImageResNativeUav,
        );

        image_manager.taaFeedback2Image = try image_manager.imageFromFunction(
            "_taaFeedback2",
            image_gen.hdrRGBA16SImageResNativeUav,
        );

        image_manager.envprobeHDRImage = try image_manager.imageFromFunction(
            "_envprobeHDR",
            image_gen.envprobeImageHdr,
        );

        image_manager.envprobeDepthImage = try image_manager.imageFromFunction(
            "_envprobeDepth",
            image_gen.envprobeImageDepth,
        );

        image_manager.smaaEdgesImage = try image_manager.imageFromFunction(
            "_smaaEdges",
            image_gen.smaaImageResNative,
        );

        image_manager.smaaBlendImage = try image_manager.imageFromFunction(
            "_smaaBlend",
            image_gen.smaaImageResNative,
        );

        image_manager.shadowAtlasImage = try image_manager.imageFromFunction(
            "_shadowMapAtlas",
            image_gen.createShadowMapImageAtlas,
        );

        image_manager.bloomRenderImage[0] = try image_manager.imageFromFunction(
            "_bloomRender0",
            image_gen.hdrRGBA16FImageResQuarterLinear,
        );

        image_manager.bloomRenderImage[1] = try image_manager.imageFromFunction(
            "_bloomRender1",
            image_gen.hdrRGBA16FImageResQuarterLinear,
        );

        image_manager.guiEdit = try image_manager.imageFromFunction(
            "_guiEdit",
            image_gen.guiEditFunction,
        );

        image_manager.guiEditDepthStencilImage = try image_manager.imageFromFunction(
            "_guiEditDepthStencil",
            image_gen.guiEditDepthStencilFunction,
        );

        image_manager.accumImage = try image_manager.imageFromFunction(
            "_accum",
            image_gen.RGBA8ImageRT,
        );

        var string_buffer: [256]u8 = undefined;

        image_manager.shadowImage[0] = try image_manager.imageFromFunction(
            std.fmt.bufPrint(
                &string_buffer,
                "_shadowMapArray0_{}",
                .{framebuffer.shadow_map_resolutions[0]},
            ) catch unreachable,
            image_gen.createShadowMapImageRes0,
        );

        image_manager.shadowImage[1] = try image_manager.imageFromFunction(
            std.fmt.bufPrint(
                &string_buffer,
                "_shadowMapArray1_{}",
                .{framebuffer.shadow_map_resolutions[1]},
            ) catch unreachable,
            image_gen.createShadowMapImageRes1,
        );

        image_manager.shadowImage[2] = try image_manager.imageFromFunction(
            std.fmt.bufPrint(
                &string_buffer,
                "_shadowMapArray2_{}",
                .{framebuffer.shadow_map_resolutions[2]},
            ) catch unreachable,
            image_gen.createShadowMapImageRes2,
        );

        image_manager.shadowImage[3] = try image_manager.imageFromFunction(
            std.fmt.bufPrint(
                &string_buffer,
                "_shadowMapArray3_{}",
                .{framebuffer.shadow_map_resolutions[3]},
            ) catch unreachable,
            image_gen.createShadowMapImageRes3,
        );

        image_manager.shadowImage[4] = try image_manager.imageFromFunction(
            std.fmt.bufPrint(
                &string_buffer,
                "_shadowMapArray4_{}",
                .{framebuffer.shadow_map_resolutions[4]},
            ) catch unreachable,
            image_gen.createShadowMapImageRes4,
        );
    }

    fn imageFromFunction(
        image_manager: *ImageManager,
        name: []const u8,
        image_gen_fn: *const image_.ImageGeneratorFunction,
    ) error{OutOfMemory}!*Image {
        const ext = std.fs.path.extension(name);
        const adjusted_name = if (std.mem.eql(u8, ".tga", ext))
            name[0 .. name.len - ext.len]
        else
            name[0..];

        const hash = idlib.idStr.fileNameHash(adjusted_name);

        var i = image_manager.image_hash.first(hash);
        const images = image_manager.images.constSlice();
        while (i != -1) : (i = image_manager.image_hash.next(@intCast(i))) {
            const index: usize = @intCast(i);
            const image = images[index];
            if (std.mem.eql(u8, adjusted_name, image.name.constSlice())) {
                if (image.generator_function != image_gen_fn) {
                    std.debug.print("[IMAGE][WARN] reused image {s} with mixed generators\n", .{adjusted_name});
                }

                return image;
            }
        }

        const image = try image_manager.allocImage(adjusted_name);
        image.generator_function = image_gen_fn;
        image.referenced_outside_level_load = true;
        return image;
    }

    fn allocImage(image_manager: *ImageManager, name: []const u8) error{OutOfMemory}!*Image {
        if (name.len >= image_.max_image_name) {
            std.debug.print("[IMAGE][ERR] '{s}' is too long", .{name});
            @panic("too long image name");
        }

        const hash = idlib.idStr.fileNameHash(name);
        var allocator = global.gpa.allocator();
        const image = try allocator.create(Image);
        errdefer allocator.destroy(image);

        image.* = .{};
        try image.init(name);

        const image_index = try image_manager.images.append(image);
        try image_manager.image_hash.add(hash, @intCast(image_index));
        return image;
    }
};

pub const instance = @extern(*ImageManager, .{ .name = "imageManager" });

const image_gen = struct {
    fn defaultImage(image: *Image, opt_command_list: ?*nvrhi.ICommandList) callconv(.C) void {
        const allocator = global.gpa.allocator();
        image.makeDefault(opt_command_list, allocator) catch |err| genFatal(image, err);
    }

    fn envprobeImageHdr(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            .nearest,
            .clamp,
            .rgba16f,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn guiEditDepthStencilFunction(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.SCREEN_WIDTH,
            RenderSystem.SCREEN_HEIGHT,
            .nearest,
            .clamp,
            .depth_stencil,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn envprobeImageDepth(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            .nearest,
            .clamp,
            .depth_stencil,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn ldrNativeImage(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .lookup_table_rgba,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNative(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16f,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNativeMSAAOpt(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16f,
            true,
            sample_count == 1,
            sample_count,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn depthImage(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .depth_stencil,
            true,
            false,
            sample_count,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn ambientOcclusionImageResNative(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .linear,
            .clamp,
            .r8f,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hierarchicalZBufferImageResNative(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest_mipmap,
            .clamp,
            .r32f,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn geometryBufferImageResNative(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .linear,
            .clamp,
            .rgba16f,
            true,
            false,
            sample_count,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNativeUav(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16f,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16SImageResNativeUav(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16s,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResQuarterLinear(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth() / 4,
            RenderSystem.instance.getHeight() / 4,
            .linear,
            .clamp,
            .lookup_table_rgba,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRG16FImageResNative(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rg16f,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn smaaImageResNative(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .linear,
            .clamp,
            .lookup_table_rgba,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn RGBA8ImageRT(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            512,
            512,
            .nearest,
            .clamp,
            .lookup_table_rgba,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn guiEditFunction(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            RenderSystem.SCREEN_WIDTH,
            RenderSystem.SCREEN_HEIGHT,
            .nearest,
            .clamp,
            .lookup_table_rgba,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageAtlas(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        image.generateImageInternal(
            @intCast(RenderSystem.r_shadow_map_atlas_size.integer_value),
            @intCast(RenderSystem.r_shadow_map_atlas_size.integer_value),
            .linear,
            .clamp_to_zero_alpha,
            .depth,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes0(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[0];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes1(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[1];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes2(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[2];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes3(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[3];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes4(image: *Image, _: ?*nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[4];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
        ) catch |err| genFatal(image, err);
    }

    inline fn genFatal(image: *const Image, err: anytype) noreturn {
        std.debug.print(
            "[IMAGE][ERR:{s}] While image gen {s}\n",
            .{ @errorName(err), image.name.constSlice() },
        );
        @panic("fatal");
    }
};
