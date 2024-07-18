const std = @import("std");
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Bounds = @import("../bounding_volume/bounds.zig");
const ModelDecal = @import("model_decal.zig").ModelDecal;
const ModelOverlay = @import("model_overlay.zig").ModelOverlay;

pub const MAX_ENTITY_SHADER_PARMS: usize = 12;
pub const MAX_RENDERENTITY_GUI: usize = 3;

const deferredEntityCallback_t = fn (?*anyopaque, ?*anyopaque) callconv(.C) bool;

extern fn c_parseSpawnArgsToRenderEntity(*anyopaque, *RenderEntity) callconv(.C) void;

pub const RenderEntity = extern struct {
    // this can only be null if callback is set
    hModel: ?*anyopaque = null,
    entityNum: c_int = -1,
    bodyId: c_int = -1,

    // Entities that are expensive to generate, like skeletal models, can be
    // deferred until their bounds are found to be in view, in the frustum
    // of a shadowing light that is in view, or contacted by a trace / overlay test.
    // This is also used to do visual cueing on items in the view
    // The renderView may be NULL if the callback is being issued for a non-view related
    // source.
    // The callback function should clear renderEntity->callback if it doesn't
    // want to be called again next time the entity is referenced (ie, if the
    // callback has now made the entity valid until the next updateEntity)

    // only needs to be set for deferred models and md5s
    bounds: CBounds = .{},
    callback: ?*const deferredEntityCallback_t = null,

    // used for whatever the callback wants
    callbackData: ?*anyopaque = null,
    // player bodies and possibly player shadows should be suppressed in views from
    // that player's eyes, but will show up in mirrors and other subviews
    // security cameras could suppress their model in their subviews if we add a way
    // of specifying a view number for a remoteRenderMap view

    suppressSurfaceInViewID: c_int = 0,
    suppressShadowInViewID: c_int = 0,

    // world models for the player and weapons will not cast shadows from view weapon
    // muzzle flashes
    suppressShadowInLightID: c_int = 0,

    // if non-zero, the surface and shadow (if it casts one)
    // will only show up in the specific view, ie: player weapons
    allowSurfaceInViewID: c_int = 0,

    // positioning
    // axis rotation vectors must be unit length for many
    // R_LocalToGlobal functions to work, so don't scale models!
    // axis vectors are [0] = forward, [1] = left, [2] = up
    origin: CVec3 = .{},
    axis: CMat3 = .{},

    // texturing

    // if non-0, all surfaces will use this
    customShader: ?*anyopaque = null,
    // used so flares can reference the proper light shader
    referenceShader: ?*anyopaque = null,
    // 0 for no remapping
    customSkin: ?*anyopaque = null,
    // for shader sound tables, allowing effects to vary with sounds
    referenceSound: ?*anyopaque = null,
    // can be used in any way by shader or model generation
    shaderParms: [MAX_ENTITY_SHADER_PARMS]f32 = std.mem.zeroes([MAX_ENTITY_SHADER_PARMS]f32),
    // networking: see WriteGUIToSnapshot / ReadGUIFromSnapshot
    gui: [MAX_RENDERENTITY_GUI]?*anyopaque = std.mem.zeroes([MAX_RENDERENTITY_GUI]?*anyopaque),
    // any remote camera surfaces will use this
    remoteRenderView: ?*anyopaque = null,

    numJoints: c_int = 0,
    // array of joints that will modify vertices.
    // NULL if non-deformable model.  NOT freed by renderer
    joints: ?*anyopaque = null,

    // squash depth range so particle effects don't clip into walls
    modelDepthHack: bool = false,

    // options to override surface shader flags (replace with material parameters?)

    // cast shadows onto other objects,but not self
    noSelfShadow: bool = false,
    // no shadow at all
    noShadow: bool = false,

    // don't create any light / shadow interactions after
    // the level load is completed.  This is a performance hack
    // for the gigantic outdoor meshes in the monorail map, so
    // all the lights in the moving monorail don't touch the meshes
    noDynamicInteractions: bool = false,

    // squash depth range so view weapons don't poke into walls
    // this automatically implies noShadow
    weaponDepthHack: bool = false,
    // force no overlays on this model
    noOverlays: bool = false,
    // Mask out this object during motion blur
    skipMotionBlur: bool = false,
    // force an update (NOTE: not a bool to keep this struct a multiple of 4 bytes)
    forceUpdate: c_int = 0,
    timeGroup: c_int = 0,
    xrayIndex: c_int = 0,

    pub fn initFromSpawnArgs(self: *RenderEntity, dict: *anyopaque) void {
        c_parseSpawnArgsToRenderEntity(dict, self);
    }
};

const RenderMatrix = @import("matrix.zig").RenderMatrix;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;

pub const RenderEntityLocal = extern struct {
    // specification
    parms: RenderEntity = RenderEntity{},
    // this is just a rearrangement of parms.axis and parms.origin
    modelMatrix: [16]f32 = std.mem.zeroes([16]f32),
    modelRenderMatrix: RenderMatrix = std.mem.zeroes(RenderMatrix),
    // transforms the unit cube to exactly cover the model in world space
    inverseBaseModelProject: RenderMatrix = std.mem.zeroes(RenderMatrix),
    world: ?*anyopaque = null, // RenderWorld
    // in world entityDefs
    index: c_int = 0,
    // to determine if it is constantly changing,
    // and should go in the dynamic frame memory, or kept
    // in the cached memory
    lastModifiedFrameNum: c_int = 0,
    // if parms.model->IsDynamicModel(), this is the generated data
    dynamicModel: ?*anyopaque = null, // idRenderModel
    // continuously animating dynamic models will recreate
    dynamicModelFrameCount: c_int = 0,
    // dynamicModel if this doesn't == tr.viewCount
    cachedDynamicModel: ?*anyopaque = null, // idRenderModel
    // the local bounds used to place entityRefs, either from parms for dynamic entities, or a model bounds
    localReferenceBounds: CBounds = .{},
    // axis aligned bounding box in world space, derived from refernceBounds and
    // modelMatrix in R_CreateEntityRefs()
    globalReferenceBounds: CBounds = .{},
    // a viewEntity_t is created whenever a idRenderEntityLocal is considered for inclusion
    // in a given view, even if it turns out to not be visible
    // if tr.viewCount == viewCount, viewEntity is valid,
    // but the entity may still be off screen
    viewCount: c_int = 0,
    // in frame temporary memory
    viewEntity: ?*anyopaque = null, // viewEntity_t
    // decals that have been projected on this model
    decals: ?*ModelDecal = null, //RenderModelDecal
    overlays: ?*ModelOverlay = null, //RenderModelOverlay
    // chain of all reference
    entityRefs: ?*AreaReference = null,
    // doubly linked list
    firstInteraction: ?*Interaction = null,
    lastInteraction: ?*Interaction = null,
    needsPortalSky: bool = false,

    pub fn deriveEntityData(entity: *RenderEntityLocal) void {
        axisToModelMatrix(entity.parms.axis, entity.parms.origin, &entity.modelMatrix);

        RenderMatrix.createFromOriginAxis(
            entity.parms.origin,
            entity.parms.axis,
            &entity.modelRenderMatrix,
        );

        // calculate the matrix that transforms the unit cube to exactly cover the model in world space
        entity.modelRenderMatrix.offsetScaleForBounds(
            entity.localReferenceBounds,
            &entity.inverseBaseModelProject,
        );

        // calculate the global model bounds by inverse projecting the unit cube with the 'inverseBaseModelProject'
        RenderMatrix.projectedBounds(
            &entity.globalReferenceBounds,
            entity.inverseBaseModelProject,
            CBounds.fromBounds(Bounds.unitCube()),
            false,
        );
    }
};

pub fn axisToModelMatrix(axis: CMat3, origin: CVec3, model_matrix: []f32) void {
    model_matrix[0 * 4 + 0] = axis.mat[0].x;
    model_matrix[1 * 4 + 0] = axis.mat[1].x;
    model_matrix[2 * 4 + 0] = axis.mat[2].x;
    model_matrix[3 * 4 + 0] = origin.x;

    model_matrix[0 * 4 + 1] = axis.mat[0].y;
    model_matrix[1 * 4 + 1] = axis.mat[1].y;
    model_matrix[2 * 4 + 1] = axis.mat[2].y;
    model_matrix[3 * 4 + 1] = origin.y;

    model_matrix[0 * 4 + 2] = axis.mat[0].z;
    model_matrix[1 * 4 + 2] = axis.mat[1].z;
    model_matrix[2 * 4 + 2] = axis.mat[2].z;
    model_matrix[3 * 4 + 2] = origin.z;

    model_matrix[0 * 4 + 3] = 0.0;
    model_matrix[1 * 4 + 3] = 0.0;
    model_matrix[2 * 4 + 3] = 0.0;
    model_matrix[3 * 4 + 3] = 1.0;
}
