const CBounds = @import("bounding_volume/bounds.zig").CBounds;
const CWinding = @import("geometry/winding.zig").CWinding;
const CPlane = @import("math/plane.zig").CPlane;

const MAX_CURRENT_PVS: usize = 64;

pub const Handle = extern struct {
    i: c_int,
    h: c_uint,
};

pub const Current = extern struct {
    handle: Handle,
    pvs: [*]u8,
};

pub const Portal = extern struct {
    areaNum: c_int,
    w: *CWinding,
    bounds: CBounds,
    plane: CPlane,
    passages: [*]Passage,
    done: bool,
    vis: [*]u8,
    mightSee: [*]u8,
};

pub const Area = extern struct {
    numPortals: c_int,
    bounds: CBounds,
    portals: [*]*Portal,
};

pub const Passage = extern struct {
    canSee: [*]u8,
};

const PVS = extern struct {
    numAreas: c_int,
    numPortals: c_int,
    connectedAreas: [*]bool,
    areaQueue: [*]c_int,
    areaPVS: [*]u8,
    currentPVS: Current[MAX_CURRENT_PVS],
    portalVisBytes: c_int,
    portalVisLongs: c_int,
    areaVisBytes: c_int,
    areaVisLongs: c_int,
    pvsPortals: [*]Portal,
    pvsAreas: [*]Area,
};

const Bounds = @import("bounding_volume/bounds.zig");

extern fn c_pvsGetPVSAreas(*const CBounds, [*]c_int, c_int) callconv(.C) usize;

pub fn getPVSAreas(bounds: Bounds, areas: []c_int) usize {
    return c_pvsGetPVSAreas(&CBounds.fromBounds(bounds), areas.ptr, @intCast(areas.len));
}
