const CVec3 = @import("../math/vector.zig").CVec3;
const std = @import("std");
const CMat3 = @import("../math/matrix.zig").CMat3;
const CPlane = @import("../math/plane.zig").CPlane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const CWinding = @import("../geometry/winding.zig").CWinding;
const material = @import("material.zig");
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;
const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderEnvprobeLocal = @import("render_envprobe.zig").RenderEnvprobeLocal;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const heap = @import("../heap.zig");

pub const RenderView = extern struct {
    viewID: c_int,
    fov_x: f32,
    fov_y: f32,
    vieworg: CVec3,
    vieworg_weapon: CVec3,
    viewaxis: CMat3,
    cramZNear: bool,
    flipProjection: bool,
    forceUpdate: bool,
    time: [2]c_int,
    shaderParms: [material.MAX_GLOBAL_SHADER_PARMS]f32,
    globalMaterial: ?*const anyopaque,
    viewEyeBuffer: c_int,
    stereoScreenSeparation: f32,
    rdflags: c_int,
};

// RenderWorld
const RenderWorld = @This();

// Signed because -1 means "File not found" and we don't want that to compare > than any other time
const Time = c_longlong;

pub const MAX_DECAL_SURFACES: usize = 32;

pub const AreaNode = extern struct {
    pub const CHILDREN_HAVE_MULTIPLE_AREAS: c_int = -2;
    pub const AREANUM_SOLID: c_int = -1;

    plane: CPlane,
    // negative numbers are (-1 - areaNumber), 0 = solid
    children: [2]c_int,
    // if all children are either solid or a single area,
    // this is the area number, else CHILDREN_HAVE_MULTIPLE_AREAS
    commonChildrenArea: c_int,
};

pub const NUM_PORTAL_ATTRIBUTES: usize = 3;

const List = extern struct {
    num: c_int,
    size: c_int,
    granularity: c_int,
    list: ?*anyopaque, // type
    memTag: u8,
};

pub const LightGrid = extern struct {
    lightGridOrigin: CVec3,
    lightGridSize: CVec3,
    lightGridBounds: [3]c_int,
    lightGridPoints: List,
    area: c_int,
    irradianceImage: ?*anyopaque, // idImage
    imageSingleProbeSize: c_int,
    imageBorderSize: c_int,
};

pub const Portal = extern struct {
    // area this portal leads to
    intoArea: c_int,
    // winding points have counter clockwise ordering seen this area
    w: *CWinding,
    // view must be on the positive side of the plane to cross
    plane: CPlane,
    // next portal of the area
    next: ?*Portal,
    doublePortal: ?*DoublePortal,
};

pub const DoublePortal = extern struct {
    portals: [2]*Portal,
    // PS_BLOCK_VIEW, PS_BLOCK_AIR, etc, set by doors that shut them off
    blockingBits: c_int,
    // A portal will be considered closed if it is past the
    // fog-out point in a fog volume.  We only support a single
    // fog volume over each portal.
    fogLight: ?*RenderLightLocal,
    nextFoggedPortal: ?*DoublePortal,
};

pub const PortalArea = extern struct {
    areaNum: c_int,
    // if two areas have matching connectedAreaNum, they are
    // not separated by a portal with the apropriate PS_BLOCK_* blockingBits
    connectedAreaNum: [NUM_PORTAL_ATTRIBUTES]c_int,
    globalBounds: CBounds,
    lightGrid: LightGrid,
    viewCount: c_int,
    portals: *Portal,
    entityRefs: AreaReference,
    lightRefs: AreaReference,
    envprobeRefs: AreaReference,
};

const qhandle_t = c_int;

const RenderModelDecal = @import("model_decal.zig").ModelDecal;
pub const ReusableDecal = extern struct {
    entityHandle: qhandle_t,
    lastStartTime: c_int,
    decals: ?*RenderModelDecal,
};

const RenderModelOverlay = @import("model_overlay.zig").ModelOverlay;
pub const ReusableOverlay = extern struct {
    entityHandle: qhandle_t,
    lastStartTime: c_int,
    overlays: ?*RenderModelOverlay,
};

map_name: []const u8,
// for fast reloads of the same level
map_time_stamp: Time,
area_nodes: ?*AreaNode,
area_nodes_num: usize,
portal_areas: ?*PortalArea,
portal_areas_num: usize,
// incremented every time a door portal state changes
connected_area_num: usize,
area_screen_rect: ?*ScreenRect,
double_portals: ?*DoublePortal,
inter_area_portals_num: usize,
local_models: std.ArrayList(*anyopaque), // idRenderModel
entity_defs: std.ArrayList(*RenderEntityLocal),
light_defs: std.ArrayList(*RenderLightLocal),
envprobe_defs: std.ArrayList(*RenderEnvprobeLocal),
area_reference_allocator: heap.BlockAllocator(AreaReference),
interaction_allocator: heap.BlockAllocator(Interaction),

decals: [MAX_DECAL_SURFACES]ReusableDecal,
overlays: [MAX_DECAL_SURFACES]ReusableOverlay,

// all light / entity interactions are referenced here for fast lookup without
// having to crawl the doubly linked lists. EntityDefs are sequential for better
// cache access, because the table is accessed by light in idRenderWorldLocal::CreateLightDefInteractions()
// Growing this table is time consuming, so we add a pad value to the number
// of entityDefs and lightDefs
interaction_table: **Interaction,
// entityDefs
interaction_table_width: usize,
// lightDefs
interaction_table_height: usize,
generate_all_interactions_called: bool,
