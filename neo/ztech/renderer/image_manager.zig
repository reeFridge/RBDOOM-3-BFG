const std = @import("std");
const global = @import("../global.zig");
const nvrhi = @import("nvrhi.zig");
const fs = @import("../framework/file_system.zig");
const idlib = @import("../idlib.zig");
const image_ = @import("image.zig");
const Image = image_.Image;
const RenderSystem = @import("render_system.zig");
const framebuffer = @import("framebuffer.zig");

pub const ImageManager = extern struct {
    const MAX_IMAGE_NAME = 256;

    defaultImage: ?*Image,
    flatNormalMap: ?*Image, // 128 128 255 in all pixels
    alphaNotchImage: ?*Image, // 2x1 texture with just 1110 and 1111 with point sampling
    whiteImage: ?*Image, // full of 0xff
    blackImage: ?*Image, // full of 0x00
    blackDiffuseImage: ?*Image, // full of 0x00
    cyanImage: ?*Image, // cyan
    noFalloffImage: ?*Image, // all 255, but zero clamped
    fogImage: ?*Image, // increasing alpha is denser fog
    fogEnterImage: ?*Image, // adjust fogImage alpha based on terminator plane
    shadowAtlasImage: ?*Image, // 8192 * 8192 for clustered forward shading
    shadowImage: [5]?*Image,
    jitterImage1: ?*Image, // shadow jitter
    jitterImage4: ?*Image,
    jitterImage16: ?*Image,
    grainImage1: ?*Image,
    randomImage256: ?*Image,
    blueNoiseImage256: ?*Image,
    currentRenderHDRImage: ?*Image,
    ldrImage: ?*Image, // tonemapped result which can be used for further post processing
    taaMotionVectorsImage: ?*Image, // motion vectors for TAA projection
    taaResolvedImage: ?*Image,
    taaFeedback1Image: ?*Image,
    taaFeedback2Image: ?*Image,
    bloomRenderImage: [2]?*Image,
    glowImage: [2]?*Image, // contains any glowable surface information.
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
    gbufferNormalsRoughnessImage: ?*Image, // cheap G-Buffer replacement, holds normals and surface roughness
    ambientOcclusionImage: [2]?*Image, // contain AO and bilateral filtering keys
    hierarchicalZBufferImage: ?*Image, // zbuffer with mip maps to accelerate screen space ray tracing
    imguiFontImage: ?*Image,

    chromeSpecImage: ?*Image, // only for the PBR color checker chart
    plasticSpecImage: ?*Image, // only for the PBR color checker chart
    brdfLutImage: ?*Image,
    defaultUACIrradianceCube: ?*Image,
    defaultUACRadianceCube: ?*Image,
    scratchImage: ?*Image,
    scratchImage2: ?*Image,
    accumImage: ?*Image,
    currentRenderImage: ?*Image, // for 3D scene SS_POST_PROCESS shaders for effects like heatHaze, in HDR now
    currentDepthImage: ?*Image, // for motion blur, SSAO and everything that requires depth to world pos reconstruction
    originalCurrentRenderImage: ?*Image, // currentRenderImage before any changes for stereo rendering
    loadingIconImage: ?*Image, // loading icon must exist always
    hellLoadingIconImage: ?*Image, // loading icon must exist always
    guiEdit: ?*Image, // SP: GUI editor image
    guiEditDepthStencilImage: ?*Image, // SP: Gui-editor image depth-stencil
    images: idlib.idList(*Image),
    imageHash: idlib.idHashIndex,
    imagesToLoad: idlib.idList(*Image),
    insideLevelLoad: bool = false,
    preloadingMapImages: bool = false,
    commandList: nvrhi.CommandListHandle = .{},

    extern fn c_imageManager_reloadImages(*ImageManager, bool, *nvrhi.ICommandList) void;
    extern fn c_imageManager_init(*ImageManager) void;
    extern fn c_imageManager_shutdown(*ImageManager) void;
    extern fn c_imageManager_purgeAllImages(*ImageManager) void;

    pub fn reloadImages(
        image_manager: *ImageManager,
        all: bool,
        command_list: *nvrhi.ICommandList,
    ) error{OutOfMemory}!void {
        for (image_manager.images.constSlice()) |image| {
            try image.reload(all, command_list);
        }

        image_manager.loadDeferredImages(command_list);
    }

    fn loadDeferredImages(
        image_manager: *ImageManager,
        command_list: *nvrhi.ICommandList,
    ) void {
        _ = image_manager;
        _ = command_list;
    }

    pub fn init(image_manager: *ImageManager) error{OutOfMemory}!void {
        try image_manager.images.resizeWithGranularity(1024, 1024);
        image_manager.imageHash = .{};
        try image_manager.imageHash.resizeIndex(1024);

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

        var i = image_manager.imageHash.first(hash);
        const images = image_manager.images.constSlice();
        while (i != -1) : (i = image_manager.imageHash.next(@intCast(i))) {
            const index: usize = @intCast(i);
            const image = images[index];
            if (std.mem.eql(u8, adjusted_name, image.imgName.constSlice())) {
                if (image.generatorFunction != image_gen_fn) {
                    std.debug.print("[IMAGE][WARN] reused image {s} with mixed generators\n", .{adjusted_name});
                }

                return image;
            }
        }

        const image = try image_manager.allocImage(adjusted_name);
        image.generatorFunction = image_gen_fn;
        image.referencedOutsideLevelLoad = true;
        return image;
    }

    fn allocImage(image_manager: *ImageManager, name: []const u8) error{OutOfMemory}!*Image {
        if (name.len >= MAX_IMAGE_NAME) {
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
        try image_manager.imageHash.add(hash, @intCast(image_index));
        return image;
    }
};

pub const instance = @extern(*ImageManager, .{ .name = "imageManager" });

const image_gen = struct {
    fn defaultImage(image: *Image, command_list: *nvrhi.ICommandList) callconv(.C) void {
        image.makeDefault(command_list) catch |err| genFatal(image, err);
    }

    fn envprobeImageHdr(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            .nearest,
            .clamp,
            .rgba16f,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn guiEditDepthStencilFunction(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.SCREEN_WIDTH,
            RenderSystem.SCREEN_HEIGHT,
            .nearest,
            .clamp,
            .depth_stencil,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn envprobeImageDepth(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            framebuffer.ENVPROBE_CAPTURE_SIZE,
            .nearest,
            .clamp,
            .depth_stencil,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn ldrNativeImage(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .lookup_table_rgba,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNative(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16f,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNativeMSAAOpt(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16f,
            null,
            true,
            sample_count == 1,
            sample_count,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn depthImage(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .depth_stencil,
            null,
            true,
            false,
            sample_count,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn ambientOcclusionImageResNative(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .linear,
            .clamp,
            .r8f,
            null,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hierarchicalZBufferImageResNative(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest_mipmap,
            .clamp,
            .r32f,
            null,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn geometryBufferImageResNative(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .linear,
            .clamp,
            .rgba16f,
            null,
            true,
            false,
            sample_count,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNativeUav(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16f,
            null,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16SImageResNativeUav(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rgba16s,
            null,
            true,
            true,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResQuarterLinear(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth() / 4,
            RenderSystem.instance.getHeight() / 4,
            .linear,
            .clamp,
            .lookup_table_rgba,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn hdrRG16FImageResNative(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .nearest,
            .clamp,
            .rg16f,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn smaaImageResNative(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .linear,
            .clamp,
            .lookup_table_rgba,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn RGBA8ImageRT(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            512,
            512,
            .nearest,
            .clamp,
            .lookup_table_rgba,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn guiEditFunction(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.SCREEN_WIDTH,
            RenderSystem.SCREEN_HEIGHT,
            .nearest,
            .clamp,
            .lookup_table_rgba,
            null,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageAtlas(image: *Image, command_list: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            @intCast(RenderSystem.r_shadow_map_atlas_size.integerValue),
            @intCast(RenderSystem.r_shadow_map_atlas_size.integerValue),
            .linear,
            .clamp_to_zero_alpha,
            .depth,
            command_list,
            true,
            false,
            1,
            .@"2d",
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes0(image: *Image, command_list: *nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[0];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
            command_list,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes1(image: *Image, command_list: *nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[1];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
            command_list,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes2(image: *Image, command_list: *nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[2];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
            command_list,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes3(image: *Image, command_list: *nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[3];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
            command_list,
        ) catch |err| genFatal(image, err);
    }

    fn createShadowMapImageRes4(image: *Image, command_list: *nvrhi.ICommandList) callconv(.C) void {
        const size = framebuffer.shadow_map_resolutions[4];
        image.generateShadowArray(
            size,
            size,
            .linear,
            .clamp_to_zero_alpha,
            .shadow_array,
            command_list,
        ) catch |err| genFatal(image, err);
    }

    //fn (image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
    //    image.generateImage() catch |err| genFatal(image, err);
    //}

    inline fn genFatal(image: *const Image, err: anytype) noreturn {
        std.debug.print("[IMAGE][ERR:{s}] While image gen {s}\n", .{ @errorName(err), image.imgName.constSlice() });
        @panic("fatal");
    }
};
