const nvrhi = @import("nvrhi.zig");
const idlib = @import("../idlib.zig");
const Image = @import("image.zig").Image;

pub const ImageManager = extern struct {
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
    // RB begin
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
    // RB end
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

    extern fn c_imageManager_reloadImages(*ImageManager, bool, *nvrhi.ICommandList) callconv(.C) void;
    extern fn c_imageManager_init(*ImageManager) callconv(.C) void;
    extern fn c_imageManager_shutdown(*ImageManager) callconv(.C) void;
    extern fn c_imageManager_purgeAllImages(*ImageManager) callconv(.C) void;

    pub fn reloadImages(image_manager: *ImageManager, all: bool, command_list_ptr: *nvrhi.ICommandList) void {
        c_imageManager_reloadImages(image_manager, all, command_list_ptr);
    }

    pub fn init(image_manager: *ImageManager) void {
        c_imageManager_init(image_manager);
    }

    pub fn shutdown(image_manager: *ImageManager) void {
        c_imageManager_shutdown(image_manager);
    }

    pub fn purgeAllImages(image_manager: *ImageManager) void {
        c_imageManager_purgeAllImages(image_manager);
    }
};

pub const instance = @extern(*ImageManager, .{ .name = "imageManager" });
