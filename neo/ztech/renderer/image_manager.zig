const std = @import("std");
const global = @import("../global.zig");
const nvrhi = @import("nvrhi.zig");
const fs = @import("../framework/file_system.zig");
const idlib = @import("../idlib.zig");
const image_ = @import("image.zig");
const Image = image_.Image;

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
    insideLevelLoad: bool,
    preloadingMapImages: bool,
    commandList: nvrhi.CommandListHandle,

    extern fn c_imageManager_reloadImages(*ImageManager, bool, *nvrhi.ICommandList) void;
    extern fn c_imageManager_init(*ImageManager) void;
    extern fn c_imageManager_shutdown(*ImageManager) void;
    extern fn c_imageManager_purgeAllImages(*ImageManager) void;

    pub fn reloadImages(
        image_manager: *ImageManager,
        all: bool,
        command_list_ptr: *nvrhi.ICommandList,
    ) void {
        c_imageManager_reloadImages(image_manager, all, command_list_ptr);
    }

    pub fn init(image_manager: *ImageManager) error{OutOfMemory}!void {
        try image_manager.images.resizeWithGranularity(1024, 1024);
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
        image_manager.defaultImage = try image_manager.imageFromFunction("_default", image_gen.defaultImage);
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
    fn defaultImage(image: *Image, commandList: *nvrhi.ICommandList) callconv(.C) void {
        image.makeDefault(commandList) catch |err| {
            std.debug.print("[IMAGE][ERR:{s}] While image gen\n", .{@errorName(err)});
            @panic("fatal");
        };
    }
};
