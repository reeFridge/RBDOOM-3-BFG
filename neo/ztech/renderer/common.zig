const std = @import("std");
const FrameData = @import("frame_data.zig");
const idlib = @import("../idlib.zig");
const nvrhi = @import("nvrhi.zig");
const VertexCache = @import("vertex_cache.zig");
const JointMat = @import("../anim/animator.zig").JointMat;
const RenderEntity = @import("render_entity.zig").RenderEntity;
const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;
const RenderEnvprobeLocal = @import("render_envprobe.zig").RenderEnvprobeLocal;
const PortalArea = @import("render_world.zig").PortalArea;
const RenderView = @import("render_world.zig").RenderView;
const render_matrix = @import("matrix.zig");
const RenderMatrix = render_matrix.RenderMatrix;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const Image = @import("image.zig").Image;
const CVec3 = @import("../math/vector.zig").CVec3;
const CVec2i = @import("../math/vector.zig").CVec2i;
const CVec4 = @import("../math/vector.zig").CVec4;
const Vec4 = @import("../math/vector.zig").Vec4;
const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const VertexCacheHandle = @import("vertex_cache.zig").VertexCacheHandle;
const Material = @import("material.zig").Material;
const Deform = @import("material.zig").Deform;
const Plane = @import("../math/plane.zig").Plane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const globalPlaneToLocal = @import("interaction.zig").globalPlaneToLocal;
const RenderSystem = @import("render_system.zig");
const RenderWorld = @import("render_world.zig");

const MAX_ENTITY_SHADER_PARAMS = @import("render_entity.zig").MAX_ENTITY_SHADER_PARAMS;
const MAX_EXPRESSION_REGISTERS = @import("material.zig").MAX_EXPRESSION_REGISTERS;

// areas have references to hold all the lights and entities in them
pub const AreaReference = extern struct {
    // chain in the area
    areaNext: ?*AreaReference = null,
    areaPrev: ?*AreaReference = null,
    // chain on either the entityDef or lightDef
    ownerNext: ?*AreaReference = null,
    // only one of entity / light / envprobe will be non-NULL
    entity: ?*RenderEntityLocal = null,
    // only one of entity / light / envprobe will be non-NULL
    light: ?*RenderLightLocal = null,
    // only one of entity / light / envprobe will be non-NULL
    envprobe: ?*RenderEnvprobeLocal = null,
    // so owners can find all the areas they are in
    area: ?*PortalArea = null,
};

pub const DeclSkin = opaque {
    extern fn c_declSkin_remapShaderBySkin(
        *const DeclSkin,
        ?*const Material,
    ) ?*const Material;

    pub fn remapShaderBySkin(skin: *const DeclSkin, shader: ?*const Material) ?*const Material {
        return c_declSkin_remapShaderBySkin(skin, shader);
    }
};

pub const DrawSurface = extern struct {
    frontEndGeo: ?*const SurfaceTriangles,
    numIndexes: c_int,
    indexCache: VertexCacheHandle,
    ambientCache: VertexCacheHandle,
    jointCache: VertexCacheHandle,
    space: ?*const ViewEntity,
    material: ?*const Material,
    extraGLState: c_ulonglong,
    sort: f32,
    shaderRegisters: [*]const f32,
    nextOnLight: ?*DrawSurface,
    linkChain: ?*?*DrawSurface,
    scissorRect: ScreenRect,

    extern fn c_drawSurf_deform(
        *DrawSurface,
        Deform,
        *ViewDef,
    ) ?*DrawSurface;

    pub fn setupShader(
        draw_surf: *DrawSurface,
        shader: *const Material,
        render_entity: *const RenderEntity,
        view_def: *ViewDef,
    ) void {
        draw_surf.material = shader;
        draw_surf.sort = shader.sort;
        const time_sec: f32 = @as(f32, @floatFromInt(
            view_def.renderView.time[@intCast(render_entity.timeGroup)],
        )) * 0.001;

        // process the shader expressions for conditionals / color / texcoords
        if (shader.constantRegisters) |constant_registers| {
            // shader only uses constant values
            draw_surf.shaderRegisters = constant_registers;
        } else {
            var gen_shader_params = std.mem.zeroes([MAX_ENTITY_SHADER_PARAMS]f32);
            // by default evaluate with the entityDef's shader parms
            const shader_params = if (render_entity.referenceShader) |ref_shader| shader_params: {
                // evaluate the reference shader to find our shader parms
                var ref_regs = std.mem.zeroes([MAX_EXPRESSION_REGISTERS]f32);
                ref_shader.evaluateRegisters(
                    &ref_regs,
                    &render_entity.shaderParms,
                    &view_def.renderView.shaderParms,
                    time_sec,
                    render_entity.referenceSound,
                );

                const p_stage = ref_shader.getStage(0) orelse @panic("No primary stage!");
                gen_shader_params = render_entity.shaderParms;
                gen_shader_params[0] = ref_regs[@intCast(p_stage.color.registers[0])];
                gen_shader_params[1] = ref_regs[@intCast(p_stage.color.registers[1])];
                gen_shader_params[2] = ref_regs[@intCast(p_stage.color.registers[2])];

                break :shader_params &gen_shader_params;
            } else &render_entity.shaderParms;

            // allocate frame memory for the shader register values
            const regs = FrameData.frameAlloc(f32, @intCast(shader.getNumRegisters()));
            draw_surf.shaderRegisters = @ptrCast(regs);

            // process the shader expressions for conditionals / color / texcoords
            shader.evaluateRegisters(
                regs,
                shader_params,
                &view_def.renderView.shaderParms,
                time_sec,
                render_entity.referenceSound,
            );
        }
    }

    const r_use_gpu_skinning = true;
    pub fn setupJoints(
        surf: *DrawSurface,
        tri: *const SurfaceTriangles,
        command_list: ?*nvrhi.ICommandList,
    ) void {
        // if gpu skinning is not available
        if (tri.staticModelWithJoints == null or !r_use_gpu_skinning) {
            surf.jointCache = 0;
            return;
        }

        const model = tri.staticModelWithJoints orelse return;
        std.debug.assert(model.jointsInverted != null);

        if (!VertexCache.instance.cacheIsCurrent(model.jointsInvertedBuffer)) {
            model.jointsInvertedBuffer = VertexCache.instance.allocJoint(
                @ptrCast(model.jointsInverted),
                @intCast(model.numInvertedJoints),
                @sizeOf(JointMat),
                command_list,
            );
        }
        surf.jointCache = model.jointsInvertedBuffer;
    }

    pub fn deform(surf: *DrawSurface, view_def: *ViewDef) ?*DrawSurface {
        return if (surf.material) |material|
            c_drawSurf_deform(surf, material.deformType(), view_def)
        else
            null;
    }
};

pub const ViewEntity = extern struct {
    next: ?*ViewEntity,
    entityDef: ?*RenderEntityLocal,
    scissorRect: ScreenRect,
    isGuiSurface: bool,
    skipMotionBlur: bool,
    weaponDepthHack: bool,
    modelDepthHack: f32,
    modelMatrix: [16]f32,
    modelViewMatrix: [16]f32,
    mvp: RenderMatrix,
    unjitteredMVP: RenderMatrix,
    drawSurfs: ?*DrawSurface,
    useLightGrid: bool,
    lightGridAtlasImage: ?*Image,
    lightGridAtlasSingleProbeSize: c_int,
    lightGridAtlasBorderSize: c_int,
    lightGridOrigin: CVec3,
    lightGridSize: CVec3,
    lightGridBounds: [3]c_int,
};

pub const ShadowOnlyEntity = extern struct {
    next: ?*ShadowOnlyEntity,
    edef: ?*RenderEntityLocal,
};

pub const InteractionState = enum(u8) {
    INTERACTION_UNCHECKED,
    INTERACTION_NO,
    INTERACTION_YES,
};

pub const ViewLight = extern struct {
    next: ?*ViewLight,
    lightDef: ?*RenderLightLocal,
    scissorRect: ScreenRect,
    removeFromList: bool,
    shadowOnlyViewEntities: ?*ShadowOnlyEntity,
    entityInteractionState: ?[*]InteractionState, // [numEntities]
    globalLightOrigin: CVec3,
    lightProject: [4]Plane,
    fogPlane: Plane,
    baseLightProject: RenderMatrix,
    pointLight: bool,
    parallel: bool,
    lightCenter: CVec3,
    shadowLOD: c_int,
    shadowFadeOut: f32,
    shadowV: [6]RenderMatrix,
    shadowP: [6]RenderMatrix,
    imageSize: CVec2i,
    imageAtlasOffset: [6]CVec2i,
    inverseBaseLightProject: RenderMatrix,
    lightShader: ?*const Material,
    shaderRegisters: [*]const f32,
    falloffImage: ?*Image,
    globalShadows: ?*DrawSurface,
    localInteractions: ?*DrawSurface,
    localShadows: ?*DrawSurface,
    globalInteractions: ?*DrawSurface,
    translucentInteractions: ?*DrawSurface,

    pub fn imageAtlasPlaced(view_light: ViewLight) bool {
        return (view_light.imageSize.x != -1) and (view_light.imageSize.y != -1);
    }
};

pub const ViewEnvprobe = extern struct {
    next: ?*ViewEnvprobe,
    envprobeDef: ?*RenderEnvprobeLocal,
    scissorRect: ScreenRect,
    removeFromList: bool,
    globalOrigin: CVec3,
    globalProbeBounds: CBounds,
    inverseBaseProbeProject: RenderMatrix,
    irradianceImage: ?*Image,
    radianceImage: ?*Image,
};

pub const FRUSTUM_PLANES: usize = 6;
pub const MAX_FRUSTUMS: usize = 6;
pub const Frustum = [FRUSTUM_PLANES]Plane;

pub const MAX_CLIP_PLANES: usize = 1;
pub const ViewDef = extern struct {
    renderView: RenderView,
    projectionMatrix: [16]f32,
    projectionRenderMatrix: RenderMatrix,
    unjitteredProjectionMatrix: [16]f32,
    unjitteredProjectionRenderMatrix: RenderMatrix,
    unprojectionToCameraMatrix: [16]f32,
    unprojectionToCameraRenderMatrix: RenderMatrix,
    unprojectionToWorldMatrix: [16]f32,
    unprojectionToWorldRenderMatrix: RenderMatrix,
    worldSpace: ViewEntity,
    renderWorld: ?*anyopaque,
    initialViewAreaOrigin: CVec3,
    isSubview: bool,
    isMirror: bool,
    isXraySubview: bool,
    isEditor: bool,
    is2Dgui: bool,
    isObliqueProjection: bool,
    numClipPlanes: c_int,
    clipPlanes: [MAX_CLIP_PLANES]Plane,
    viewport: ScreenRect,
    scissor: ScreenRect,
    superView: ?*ViewDef,
    subviewSurface: ?*const DrawSurface,
    drawSurfs: ?[*]*DrawSurface,
    numDrawSurfs: c_int,
    maxDrawSurfs: c_int,
    viewLights: ?*ViewLight,
    viewEntitys: ?*ViewEntity,
    frustums: [MAX_FRUSTUMS]Frustum,
    frustumSplitDistances: [MAX_FRUSTUMS]f32,
    frustumMVPs: [MAX_FRUSTUMS]RenderMatrix,
    areaNum: c_int,
    connectedAreas: ?[*]bool,
    viewEnvprobes: ?*ViewEnvprobe,
    globalProbeBounds: CBounds,
    inverseBaseEnvProbeProject: RenderMatrix,
    irradianceImage: ?*Image,
    radianceImages: [3]?*Image,
    radianceImageBlends: CVec4,
    targetRender: ?*Framebuffer,

    const flip_matrix: [16]f32 = .{
        // convert from our coordinate system (looking down X)
        // to OpenGL's coordinate system (looking down -Z)
        0,  0, -1, 0,
        -1, 0, 0,  0,
        0,  1, 0,  0,
        0,  0, 0,  1,
    };

    pub fn setupUnprojection(view_def: *ViewDef) void {
        render_matrix.fullInverseSlice(
            &view_def.projectionMatrix,
            &view_def.unprojectionToCameraMatrix,
        );

        const unprojection_to_camera: *RenderMatrix = @ptrCast(&view_def.unprojectionToCameraMatrix);
        view_def.unprojectionToCameraRenderMatrix = unprojection_to_camera.transpose();

        render_matrix.multiplySlice(
            &view_def.worldSpace.modelViewMatrix,
            &view_def.projectionMatrix,
            &view_def.unprojectionToWorldMatrix,
        );

        render_matrix.fullInverseSlice(
            &view_def.unprojectionToWorldMatrix,
            &view_def.unprojectionToWorldMatrix,
        );

        const unprojection_to_world: *RenderMatrix = @ptrCast(&view_def.unprojectionToWorldMatrix);
        view_def.unprojectionToWorldRenderMatrix = unprojection_to_world.transpose();
    }

    pub fn setupViewMatrix(view_def: *ViewDef) void {
        const world = &view_def.worldSpace;
        world.* = std.mem.zeroes(ViewEntity);

        // identity
        world.modelMatrix[0 * 4 + 0] = 1.0;
        world.modelMatrix[1 * 4 + 1] = 1.0;
        world.modelMatrix[2 * 4 + 2] = 1.0;

        const origin = view_def.renderView.vieworg.constSlice();
        const axis = view_def.renderView.viewaxis.constSlice();
        var viewer_matrix = std.mem.zeroes([16]f32);

        viewer_matrix[0 * 4 + 0] = axis[0 * 3 + 0];
        viewer_matrix[1 * 4 + 0] = axis[0 * 3 + 1];
        viewer_matrix[2 * 4 + 0] = axis[0 * 3 + 2];
        viewer_matrix[3 * 4 + 0] =
            -origin[0] * axis[0 * 3 + 0] -
            origin[1] * axis[0 * 3 + 1] -
            origin[2] * axis[0 * 3 + 2];

        viewer_matrix[0 * 4 + 1] = axis[1 * 3 + 0];
        viewer_matrix[1 * 4 + 1] = axis[1 * 3 + 1];
        viewer_matrix[2 * 4 + 1] = axis[1 * 3 + 2];
        viewer_matrix[3 * 4 + 1] =
            -origin[0] * axis[1 * 3 + 0] -
            origin[1] * axis[1 * 3 + 1] -
            origin[2] * axis[1 * 3 + 2];

        viewer_matrix[0 * 4 + 2] = axis[2 * 3 + 0];
        viewer_matrix[1 * 4 + 2] = axis[2 * 3 + 1];
        viewer_matrix[2 * 4 + 2] = axis[2 * 3 + 2];
        viewer_matrix[3 * 4 + 2] =
            -origin[0] * axis[2 * 3 + 0] -
            origin[1] * axis[2 * 3 + 1] -
            origin[2] * axis[2 * 3 + 2];

        viewer_matrix[0 * 4 + 3] = 0.0;
        viewer_matrix[1 * 4 + 3] = 0.0;
        viewer_matrix[2 * 4 + 3] = 0.0;
        viewer_matrix[3 * 4 + 3] = 1.0;

        // convert from our coordinate system (looking down X)
        // to OpenGL's coordinate system (looking down -Z)
        render_matrix.multiplySlice(
            &viewer_matrix,
            &flip_matrix,
            &world.modelViewMatrix,
        );
    }

    const r_znear: f32 = 3;
    const r_use_temporal_aa = false;
    pub fn setupProjectionMatrix(view_def: *ViewDef, do_jitter: bool) void {
        // random jittering is usefull when multiple
        // frames are going to be blended together
        // for motion blurred anti-aliasing
        var jitterx: f32 = 0;
        var jittery: f32 = 0;

        const irradiance_flag_set = (view_def.renderView.rdflags & RenderWorld.RDF_IRRADIANCE) != 0;
        if (r_use_temporal_aa and do_jitter and !irradiance_flag_set) {
            // TODO: R_UseTemporalAA
            const pixel_offset = RenderSystem.backend_.getCurrentPixelOffset();
            jitterx = pixel_offset.v[0];
            jittery = pixel_offset.v[1];
        }

        const z_near = if (view_def.renderView.cramZNear)
            r_znear * 0.25
        else
            r_znear;

        const view_width = view_def.viewport.x2 - view_def.viewport.x1 + 1;
        const view_height = view_def.viewport.y2 - view_def.viewport.y1 + 1;

        const xoffset = -2.0 * jitterx / @as(f32, @floatFromInt(view_width));
        const yoffset = -2.0 * jittery / @as(f32, @floatFromInt(view_height));

        const projection_matrix = if (do_jitter)
            &view_def.projectionMatrix
        else
            &view_def.unjitteredProjectionMatrix;

        // alternative far plane at infinity Z for better precision in the distance but still no reversed depth buffer
        // see Foundations of Game Engine Development 2, chapter 6.3

        const aspect = view_def.renderView.fov_x / view_def.renderView.fov_y;

        const y_scale = 1.0 / (std.math.tan(0.5 * std.math.degreesToRadians(view_def.renderView.fov_y)));
        const x_scale = y_scale / aspect;

        const epsilon = 1.9073486328125e-6; // 2^-19;
        //const z_far = 160000.0;

        //const k = z_far / ( z_far - z_near );
        const k = 1.0 - epsilon;

        projection_matrix[0 * 4 + 0] = x_scale;
        projection_matrix[1 * 4 + 0] = 0.0;
        projection_matrix[2 * 4 + 0] = xoffset;
        projection_matrix[3 * 4 + 0] = 0.0;

        projection_matrix[0 * 4 + 1] = 0.0;
        projection_matrix[1 * 4 + 1] = y_scale;
        projection_matrix[2 * 4 + 1] = yoffset;
        projection_matrix[3 * 4 + 1] = 0.0;

        projection_matrix[0 * 4 + 2] = 0.0;
        projection_matrix[1 * 4 + 2] = 0.0;

        // adjust value to prevent imprecision issues
        projection_matrix[2 * 4 + 2] = -k;

        // the clip space Z range has changed from [-1 .. 1] to [0 .. 1] for DX12 & Vulkan
        projection_matrix[3 * 4 + 2] = -k * z_near;

        projection_matrix[0 * 4 + 3] = 0.0;
        projection_matrix[1 * 4 + 3] = 0.0;
        projection_matrix[2 * 4 + 3] = -1.0;
        projection_matrix[3 * 4 + 3] = 0.0;

        if (view_def.renderView.flipProjection) {
            projection_matrix[1 * 4 + 1] = -projection_matrix[1 * 4 + 1];
            projection_matrix[1 * 4 + 3] = -projection_matrix[1 * 4 + 3];
        }

        if (view_def.isObliqueProjection and do_jitter) {
            view_def.obliqueProjection();
        }
    }

    fn obliqueProjection(view_def: *ViewDef) void {
        var mvt = std.mem.zeroes([16]f32);
        render_matrix.transposeSlice(
            &view_def.worldSpace.modelViewMatrix,
            &mvt,
        );

        // transform plane (which is set to the surface we're mirroring about's plane) to camera space
        const camera_plane = globalPlaneToLocal(&mvt, view_def.clipPlanes[0]);
        const clip_plane = Vec4(f32){ .v = .{
            camera_plane.a, camera_plane.b,
            camera_plane.c, camera_plane.d,
        } };

        const proj = &view_def.projectionMatrix;
        const q = Vec4(f32){ .v = .{
            (std.math.sign(clip_plane.x()) + proj[8]) / proj[0],
            (std.math.sign(clip_plane.y()) + proj[9]) / proj[5],
            -1.0,
            (1.0 + proj[10]) / proj[14],
        } };

        // scaled plane vector
        const d = 1.0 / clip_plane.dot(q);

        // Replace the third row of the projection matrix
        proj[2] = clip_plane.x() * d;
        proj[6] = clip_plane.y() * d;
        proj[10] = clip_plane.z() * d;
        proj[14] = clip_plane.w() * d;
    }
};

pub const CalcEnvprobeParams = extern struct {
    radiance: [6]*u8,
    freeRadiance: c_int,
    samples: c_int,
    outWidth: c_int,
    outHeight: c_int,
    printProgress: bool,
    printWidth: c_int,
    printHeight: c_int,
    filename: idlib.idStr,
    outBuffer: [*]f16,
    time: c_int,
};

pub const CalcLightGridPointParams = extern struct {
    radiance: [6]*u8,
    gridCoord: [3]c_int,
    outWidth: c_int,
    outHeight: c_int,
    outBuffer: [*]f16,
    time: c_int,
};

pub const GLImplParams = extern struct {
    x: c_int = 0, // ignored in fullscreen
    y: c_int = 0, // ignored in fullscreen
    width: c_int,
    height: c_int,
    fullScreen: c_int = 0, // 0 = windowed, otherwise 1 based monitor number to go full screen on
    // -1 = borderless window for spanning multiple displays
    startMaximized: bool = false,
    stereo: bool = false,
    displayHz: c_int = 0,
    multiSamples: c_int,
};
