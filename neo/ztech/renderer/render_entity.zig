const std = @import("std");
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const MAX_ENTITY_SHADER_PARMS = @as(usize, 12);
const MAX_RENDERENTITY_GUI = @as(usize, 3);

const RenderEntity = @This();

pub const CBounds = extern struct { b: [2]CVec3 = [_]CVec3{ .{}, .{} } };

const deferredEntityCallback_t = fn (?*anyopaque, ?*anyopaque) callconv(.C) bool;

pub const CRenderEntity = extern struct {
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
    shaderParms: [RenderEntity.MAX_ENTITY_SHADER_PARMS]f32 = std.mem.zeroes([RenderEntity.MAX_ENTITY_SHADER_PARMS]f32),
    // networking: see WriteGUIToSnapshot / ReadGUIFromSnapshot
    gui: [RenderEntity.MAX_RENDERENTITY_GUI]?*anyopaque = std.mem.zeroes([RenderEntity.MAX_RENDERENTITY_GUI]?*anyopaque),
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
};
