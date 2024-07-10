const MAX_DEFERRED_DECALS: usize = 16;
// don't create a decal if it wasn't visible within the first second
const DEFFERED_DECAL_TIMEOUT: c_int = 1000;
const MAX_DECALS: usize = 128;
const NUM_DECAL_BOUNDING_PLANES: usize = 6;
// 3 triangle verts clipped NUM_DECAL_BOUNDING_PLANES + 3 times (plus 6 for safety)
const MAX_DECAL_VERTS: usize = 3 + NUM_DECAL_BOUNDING_PLANES + 3 + 6;
const MAX_DECAL_INDEXES: usize = (MAX_DECAL_VERTS - 2) * 3;

const CPlane = @import("../math/plane.zig").CPlane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
pub const DecalProjectionParams = extern struct {
    boundingPlanes: [NUM_DECAL_BOUNDING_PLANES]CPlane,
    fadePlanes: [2]CPlane,
    textureAxis: [2]CPlane,
    projectionOrigin: CVec3,
    projectionBounds: CBounds,
    material: ?*const anyopaque, // idMaterial
    fadeDepth: f32,
    startTime: c_int,
    parallel: bool,
    force: bool,
};

const CVec3 = @import("../math/vector.zig").CVec3;
const HalfFloat = c_ushort;
pub const DrawVert = extern struct {
    xyz: CVec3,
    st: [2]HalfFloat,
    normal: [4]u8,
    tangent: [4]u8,
    color: [4]u8,
    color2: [4]u8,
};

const TriIndex = c_ushort;

pub const Decal align(16) = extern struct {
    verts: [MAX_DECAL_VERTS]DrawVert align(16),
    indexes: [MAX_DECAL_INDEXES]TriIndex align(16),
    vertDepthFade: [MAX_DECAL_VERTS]f32,
    numVerts: c_int,
    numIndexes: c_int,
    startTime: c_int,
    material: ?*const anyopaque, // idMaterial
};

pub const Modeldecal = extern struct {
    decals: [MAX_DECALS]Decal,
    firstDecal: c_uint,
    nextDecal: c_uint,

    deferredDecals: [MAX_DEFERRED_DECALS]DecalProjectionParams,
    firstDeferredDecal: c_uint,
    nextDeferredDecal: c_uint,

    decalMaterials: [MAX_DECALS]?*const anyopaque, // idMaterial
    numDecalMaterials: c_uint,
};
