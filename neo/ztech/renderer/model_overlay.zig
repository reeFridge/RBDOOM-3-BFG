const MAX_DEFERRED_OVERLAYS: usize = 4;
// don't create a decal if it wasn't visible within the first 200 milliseconds
const DEFFERED_OVERLAY_TIMEOUT: c_int = 200;
const MAX_OVERLAYS: usize = 8;

const Plane = @import("../math/plane.zig").Plane;
pub const OverlayProjectionParams = extern struct {
    localTextureAxis: [2]Plane,
    material: ?*const anyopaque, // idMaterial
    startTime: c_int,
};

const HalfFloat = c_ushort;
pub const OverlayVertex = extern struct {
    vertexNum: c_int,
    st: [2]HalfFloat,
};

const TriIndex = c_ushort;

pub const Overlay = extern struct {
    surfaceNum: c_int,
    surfaceId: c_int,
    maxReferencedVertex: c_int,
    numIndexes: c_int,
    indexes: ?*TriIndex,
    numVerts: c_int,
    verts: ?*OverlayVertex,
    material: ?*const anyopaque, // idMaterial
};

pub const ModelOverlay = extern struct {
    overlays: [MAX_OVERLAYS]Overlay,
    firstOverlay: c_uint,
    nextOverlay: c_uint,

    deferredOverlays: [MAX_DEFERRED_OVERLAYS]OverlayProjectionParams,
    firstDeferredOverlay: c_uint,
    nextDeferredOverlay: c_uint,

    overlayMaterials: [MAX_OVERLAYS]?*const anyopaque, // idMaterial
    numOverlayMaterials: c_uint,
};
