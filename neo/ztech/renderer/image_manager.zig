const std = @import("std");
const global = @import("../global.zig");
const nvrhi = @import("nvrhi.zig");
const fs = @import("../framework/file_system.zig");
const idlib = @import("../idlib.zig");
const image_ = @import("image.zig");
const Image = image_.Image;
const RenderSystem = @import("render_system.zig");

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
    hierarchicalZbufferImage: ?*Image, // zbuffer with mip maps to accelerate screen space ray tracing
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
            image_gen.AmbientOcclusionImage_ResNative,
        );

        image_manager.ambientOcclusionImage[1] = try image_manager.imageFromFunction(
            "_ao1",
            image_gen.AmbientOcclusionImage_ResNative,
        );

        image_manager.hierarchicalZbufferImage = try image_manager.imageFromFunction(
            "_cszBuffer",
            image_gen.HierarchicalZBufferImage_ResNative,
        );

        image_manager.gbufferNormalsRoughnessImage = try image_manager.imageFromFunction(
            "_currentNormals",
            image_gen.GeometryBufferImage_ResNative,
        );

        image_manager.taaMotionVectorsImage = try image_manager.imageFromFunction(
            "_taaMotionVectors",
            image_gen.HDR_RG16FImage_ResNative,
        );

        image_manager.taaResolvedImage = try image_manager.imageFromFunction(
            "_taaResolved",
            image_gen.HDR_RGBA16FImage_ResNative_UAV,
        );

        image_manager.taaFeedback1Image = try image_manager.imageFromFunction(
            "_taaFeedback1",
            image_gen.HDR_RGBA16SImage_ResNative_UAV,
        );

        image_manager.taaFeedback2Image = try image_manager.imageFromFunction(
            "_taaFeedback2",
            image_gen.HDR_RGBA16SImage_ResNative_UAV,
        );

        image_manager.smaaEdgesImage = try image_manager.imageFromFunction(
            "_smaaEdges",
            image_gen.SMAAImage_ResNative,
        );

        image_manager.smaaBlendImage = try image_manager.imageFromFunction(
            "_smaaBlend",
            image_gen.SMAAImage_ResNative,
        );

        image_manager.shadowAtlasImage = try image_manager.imageFromFunction(
            "_shadowMapAtlas",
            image_gen.CreateShadowMapImage_Atlas,
        );

        image_manager.bloomRenderImage[0] = try image_manager.imageFromFunction(
            "_bloomRender0",
            image_gen.HDR_RGBA16FImage_ResQuarter_Linear,
        );

        image_manager.bloomRenderImage[1] = try image_manager.imageFromFunction(
            "_bloomRender1",
            image_gen.HDR_RGBA16FImage_ResQuarter_Linear,
        );

        image_manager.guiEdit = try image_manager.imageFromFunction(
            "_guiEdit",
            image_gen.GuiEditFunction,
        );

        image_manager.accumImage = try image_manager.imageFromFunction(
            "_accum",
            image_gen.RGBA8Image_RT,
        );

        //image_manager.shadowImage[0] = try image_manager.imageFromFunction( va( "_shadowMapArray0_%i", shadowMapResolutions[0] ), image_gen.createShadowMapImageRes0 );
        //image_manager.shadowImage[1] = try image_manager.imageFromFunction( va( "_shadowMapArray1_%i", shadowMapResolutions[1] ), image_gen.createShadowMapImageRes1 );
        //image_manager.shadowImage[2] = try image_manager.imageFromFunction( va( "_shadowMapArray2_%i", shadowMapResolutions[2] ), image_gen.createShadowMapImageRes2 );
        //image_manager.shadowImage[3] = try image_manager.imageFromFunction( va( "_shadowMapArray3_%i", shadowMapResolutions[3] ), image_gen.createShadowMapImageRes3 );
        //image_manager.shadowImage[4] = try image_manager.imageFromFunction( va( "_shadowMapArray4_%i", shadowMapResolutions[4] ), image_gen.createShadowMapImageRes4 );
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
        while (i != -1) : (i = image_manager.imageHash.next(i)) {
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

    fn ldrNativeImage(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .TF_NEAREST,
            .TR_CLAMP,
            .TD_LOOKUP_TABLE_RGBA,
            null,
            true,
            false,
            1,
            .CF_2D,
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNative(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .TF_NEAREST,
            .TR_CLAMP,
            .TD_RGBA16F,
            null,
            true,
            false,
            1,
            .CF_2D,
        ) catch |err| genFatal(image, err);
    }

    fn hdrRGBA16FImageResNativeMSAAOpt(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .TF_NEAREST,
            .TR_CLAMP,
            .TD_RGBA16F,
            null,
            true,
            sample_count == 1,
            sample_count,
            .CF_2D,
        ) catch |err| genFatal(image, err);
    }

    fn depthImage(image: *Image, _: *nvrhi.ICommandList) callconv(.C) void {
        const sample_count = 1;
        image.generateImage(
            null,
            RenderSystem.instance.getWidth(),
            RenderSystem.instance.getHeight(),
            .TF_NEAREST,
            .TR_CLAMP,
            .TD_DEPTH_STENCIL,
            null,
            true,
            false,
            sample_count,
            .CF_2D,
        ) catch |err| genFatal(image, err);
    }

    inline fn genFatal(image: *const Image, err: anytype) noreturn {
        std.debug.print("[IMAGE][ERR:{s}] While image gen {s}\n", .{ @errorName(err), image.imgName.constSlice() });
        @panic("fatal");
    }
};
