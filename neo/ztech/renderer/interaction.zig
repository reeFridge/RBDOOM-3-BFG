const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;

pub const VertexCacheHandle = c_ulonglong;

// Pre-generated shadow volumes from dmap are not present in surfaceInteraction_t,
// they are added separately.
pub const SurfaceInteraction = extern struct {
    // The vertexes for light tris will always come from ambient triangles.
    // For interactions created at load time, the indexes will be uniquely
    // generated in static vertex memory.
    numLightTrisIndexes: c_int,
    lightTrisIndexCache: VertexCacheHandle,
};

pub const Interaction = extern struct {
    // this may be 0 if the light and entity do not actually intersect
    // -1 = an untested interaction
    numSurfaces: c_int,

    // if there is a whole-entity optimized shadow hull, it will
    // be present as a surfaceInteraction_t with a NULL ambientTris, but
    // possibly having a shader to specify the shadow sorting order
    // (FIXME: actually try making shadow hulls?  we never did.)
    surfaces: ?*SurfaceInteraction,

    // get space from here, if NULL, it is a pre-generated shadow volume from dmap
    entityDef: ?*RenderEntityLocal,
    lightDef: ?*RenderLightLocal,
    // for lightDef chains
    lightNext: ?*Interaction,
    lightPrev: ?*Interaction,
    // for entityDef chains
    entityNext: ?*Interaction,
    entityPrev: ?*Interaction,

    // true if the interaction was created at map load time in static buffer space
    staticInteraction: bool,
};
