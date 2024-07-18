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
const fs = @import("../fs.zig");

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

pub const PortalConnection = struct {
    pub const NUM_PORTAL_ATTRIBUTES: c_int = 3;
    pub const PS_BLOCK_NONE: c_int = 0;
    pub const PS_BLOCK_VIEW: c_int = 1;
    pub const PS_BLOCK_LOCATION: c_int = 2;
    pub const PS_BLOCK_AIR: c_int = 4;
    pub const PS_BLOCK_ALL: c_int = 7;
};

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
    entityHandle: qhandle_t = -1,
    lastStartTime: c_int = 0,
    decals: ?*RenderModelDecal = null,
};

const RenderModelOverlay = @import("model_overlay.zig").ModelOverlay;
pub const ReusableOverlay = extern struct {
    entityHandle: qhandle_t = -1,
    lastStartTime: c_int = 0,
    overlays: ?*RenderModelOverlay = null,
};

const FILE_NOT_FOUND_TIMESTAMP: fs.Time = -1;

allocator: std.mem.Allocator,
arena: std.heap.ArenaAllocator,
map_name: []u8,
// for fast reloads of the same level
map_time_stamp: fs.Time = FILE_NOT_FOUND_TIMESTAMP,
area_nodes: ?[]AreaNode = null,
portal_areas: ?[]PortalArea = null,
// incremented every time a door portal state changes
connected_area_num: usize = 0,
area_screen_rect: ?*ScreenRect = null,
double_portals: ?[]DoublePortal = null,
local_models: std.ArrayList(model.RenderModel), // idRenderModel
entity_defs: std.ArrayList(?*RenderEntityLocal),
light_defs: std.ArrayList(?*RenderLightLocal),
envprobe_defs: std.ArrayList(?*RenderEnvprobeLocal),
area_reference_allocator: std.heap.MemoryPool(AreaReference),
interaction_allocator: std.heap.MemoryPool(Interaction),

decals: [MAX_DECAL_SURFACES]ReusableDecal,
overlays: [MAX_DECAL_SURFACES]ReusableOverlay,

// all light / entity interactions are referenced here for fast lookup without
// having to crawl the doubly linked lists. EntityDefs are sequential for better
// cache access, because the table is accessed by light in idRenderWorldLocal::CreateLightDefInteractions()
// Growing this table is time consuming, so we add a pad value to the number
// of entityDefs and lightDefs
interaction_table: ?**Interaction = null,
// entityDefs
interaction_table_width: usize = 0,
// lightDefs
interaction_table_height: usize = 0,
generate_all_interactions_called: bool = false,

const global = @import("../global.zig");

pub fn numPortalsInArea(render_world: RenderWorld, area_index: usize) error{ BadAreaIndex, NotInitialized }!usize {
    return if (render_world.portal_areas) |portal_areas| num: {
        if (area_index >= portal_areas.len) break :num error.BadAreaIndex;

        const area = &portal_areas[area_index];
        var count: usize = 0;
        var opt_portal: ?*Portal = area.portals;
        while (opt_portal) |portal| : (opt_portal = portal.next) {
            count += 1;
        }

        break :num count;
    } else error.NotInitialized;
}

pub fn init(allocator: std.mem.Allocator) !RenderWorld {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const arena_allocator = arena.allocator();

    var decals = [_]ReusableDecal{.{}} ** MAX_DECAL_SURFACES;
    for (&decals) |*decal| {
        decal.decals = try arena_allocator.create(RenderModelDecal);
    }

    var overlays = [_]ReusableOverlay{.{}} ** MAX_DECAL_SURFACES;
    for (&overlays) |*overlay| {
        overlay.overlays = try arena_allocator.create(RenderModelOverlay);
    }

    return .{
        .map_name = try allocator.alloc(u8, 0),
        .local_models = std.ArrayList(model.RenderModel).init(allocator),
        .entity_defs = std.ArrayList(?*RenderEntityLocal).init(allocator),
        .light_defs = std.ArrayList(?*RenderLightLocal).init(allocator),
        .envprobe_defs = std.ArrayList(?*RenderEnvprobeLocal).init(allocator),
        .area_reference_allocator = std.heap.MemoryPool(AreaReference).init(allocator),
        .interaction_allocator = std.heap.MemoryPool(Interaction).init(allocator),
        .decals = decals,
        .overlays = overlays,
        .allocator = allocator,
        .arena = arena,
    };
}

pub fn deinit(render_world: *RenderWorld) void {
    render_world.freeWorld();

    render_world.allocator.free(render_world.map_name);
    render_world.local_models.deinit();

    render_world.entity_defs.deinit();
    render_world.light_defs.deinit();
    render_world.envprobe_defs.deinit();

    render_world.interaction_allocator.deinit();
    render_world.area_reference_allocator.deinit();

    // frees .decals and .overlays
    render_world.arena.deinit();
}

pub fn freeDefs(render_world: *RenderWorld) void {
    render_world.generate_all_interactions_called = false;

    if (render_world.interaction_table != null) {
        render_world.interaction_table = null;
    }

    for (render_world.light_defs.items) |*item| {
        if (item.*) |item_ptr| {
            render_world.allocator.destroy(item_ptr);
            item.* = null;
        }
    }

    for (render_world.envprobe_defs.items) |*item| {
        if (item.*) |item_ptr| {
            render_world.allocator.destroy(item_ptr);
            item.* = null;
        }
    }

    for (render_world.entity_defs.items) |*item| {
        if (item.*) |item_ptr| {
            render_world.allocator.destroy(item_ptr);
            item.* = null;
        }
    }

    // Reset decals and overlays
    for (&render_world.decals) |*decal| {
        decal.entityHandle = -1;
        decal.lastStartTime = 0;
    }

    for (&render_world.overlays) |*overlay| {
        overlay.entityHandle = -1;
        overlay.lastStartTime = 0;
    }
}

pub fn freeWorld(render_world: *RenderWorld) void {
    render_world.freeDefs();

    // free all the portals and check light/model references
    // TODO: for (render_world.portal_areas)

    if (render_world.portal_areas) |portal_areas| {
        render_world.allocator.free(portal_areas);
        render_world.portal_areas = null;
    }

    if (render_world.area_screen_rect) |area_screen_rect| {
        render_world.allocator.destroy(area_screen_rect);
        render_world.area_screen_rect = null;
    }

    if (render_world.double_portals) |double_portals| {
        render_world.allocator.free(double_portals);
        render_world.double_portals = null;
    }

    if (render_world.area_nodes) |area_nodes| {
        render_world.allocator.free(area_nodes);
        render_world.area_nodes = null;
    }

    for (render_world.local_models.items) |*item| {
        global.RenderModelManager.removeModel(item.ptr);
        item.deinit(render_world);
    }
    render_world.local_models.clearAndFree();

    if (!render_world.area_reference_allocator.reset(.free_all)) {
        unreachable;
    }

    if (!render_world.interaction_allocator.reset(.free_all)) {
        unreachable;
    }
}

pub fn setMapName(render_world: *RenderWorld, name: []const u8) !void {
    render_world.allocator.free(render_world.map_name);
    render_world.map_name = try render_world.allocator.dupe(u8, name);
}

pub fn clearWorld(render_world: *RenderWorld) !void {
    var portal_areas = try render_world.allocator.alloc(PortalArea, 1);
    errdefer render_world.allocator.free(portal_areas);
    portal_areas[0] = std.mem.zeroes(PortalArea);

    render_world.portal_areas = portal_areas;

    const screen_rect = try render_world.allocator.create(ScreenRect);
    errdefer render_world.allocator.destroy(screen_rect);
    screen_rect.* = std.mem.zeroes(ScreenRect);

    render_world.area_screen_rect = screen_rect;

    render_world.setupAreaRefs(portal_areas);

    var area_nodes = try render_world.allocator.alloc(AreaNode, 1);
    area_nodes[0] = std.mem.zeroes(AreaNode);
    area_nodes[0].plane.d = 1;
    area_nodes[0].children[0] = -1;
    area_nodes[0].children[1] = -1;

    render_world.area_nodes = area_nodes;
}

pub fn setupAreaRefs(render_world: *RenderWorld, portal_areas: []PortalArea) void {
    render_world.connected_area_num = 0;
    for (portal_areas, 0..) |*portal_area, i| {
        portal_area.areaNum = @intCast(i);

        portal_area.lightRefs.areaPrev = &portal_area.lightRefs;
        portal_area.lightRefs.areaNext = portal_area.lightRefs.areaPrev;

        portal_area.entityRefs.areaPrev = &portal_area.entityRefs;
        portal_area.entityRefs.areaNext = portal_area.entityRefs.areaPrev;

        portal_area.envprobeRefs.areaPrev = &portal_area.envprobeRefs;
        portal_area.envprobeRefs.areaNext = portal_area.envprobeRefs.areaPrev;
    }
}

export fn ztech_RenderWorld_initFromMap(rw: *anyopaque, c_map_name: [*c]const u8) callconv(.C) bool {
    const render_world_ptr: *RenderWorld = @alignCast(@ptrCast(rw));
    const map_name: [:0]const u8 = std.mem.span(c_map_name);

    render_world_ptr.initFromMap(map_name) catch return false;

    return true;
}

const MAX_OS_PATH: usize = 256;
const PROC_FILE_EXT = "proc";
const BPROC_FILE_EXT = "bproc";
const PROC_FILE_ID = "mapProcFile003";

const Lexer = @import("../lexer.zig");
const Token = @import("../token.zig");

const MapError = error{
    ProcFileNotFound,
    BadProcFileId,
};

pub fn initFromMap(render_world: *RenderWorld, map_name: []const u8) !void {
    var buffer: [MAX_OS_PATH * 2]u8 = undefined;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    defer fixed_allocator.reset();

    const ext = std.fs.path.extension(map_name);
    const map_name_wo_ext = map_name[0 .. map_name.len - ext.len];

    const allocator = fixed_allocator.allocator();

    // 1. Force `filename` ext to PROC_FILE_EXT
    const proc_filename = try std.fmt.allocPrintZ(
        allocator,
        "{s}." ++ PROC_FILE_EXT,
        .{map_name_wo_ext},
    );
    defer allocator.free(proc_filename);

    // 2. Create `filename` for output binary file as `generated/{filename}.bproc`
    const bproc_filename = try std.fmt.allocPrintZ(
        allocator,
        "generated/{s}." ++ BPROC_FILE_EXT,
        .{map_name_wo_ext},
    );
    defer allocator.free(bproc_filename);

    std.debug.print("RenderWorld.initFromMap:\nmap = {s}\nproc_file = {s}\nbproc_file = {s}\n", .{
        map_name,
        proc_filename,
        bproc_filename,
    });

    // 3. if we are reloading the same map, check the timestamp and try to skip all the work
    const current_time_stamp = fs.getTimestamp(proc_filename);

    if (std.mem.eql(u8, map_name, render_world.map_name)) {
        if (current_time_stamp != FILE_NOT_FOUND_TIMESTAMP and current_time_stamp == render_world.map_time_stamp) {
            std.debug.print("Retaining existing map\n", .{});
            //render_world.freeDefs();
            //render_world.touchWorldModels();
            //render_world.addWorldModelEntities();
            //render_world.clearPortalStates();
            //render_world.setupLightGrid();
            return;
        }
    }

    // 4. call FreeWorld (removes defs)
    render_world.freeWorld();
    try render_world.setMapName("<FREED>");

    // 5. Check if we have an already generated version of file (see 2)
    const loaded = if (fs.openFileReadMemory(bproc_filename)) |_| loaded: {
        // and load from .bproc
        break :loaded false;
    } else false;

    // 6. Else parse .proc file and generate binary .bproc from it
    if (!loaded) {
        var lexer = Lexer.init(
            proc_filename,
            Lexer.Flags.LEXFL_NOSTRINGCONCAT | Lexer.Flags.LEXFL_NODOLLARPRECOMPILE,
        );
        defer lexer.deinit();

        if (!lexer.isLoaded()) {
            try render_world.clearWorld();
            std.debug.print("Proc map file ({s}) not found.\n", .{proc_filename});
            return error.ProcFileNotFound;
        }

        render_world.allocator.free(render_world.map_name);
        render_world.map_name = try render_world.allocator.dupe(u8, map_name);

        render_world.map_time_stamp = current_time_stamp;

        var token = Token.init();
        defer token.deinit();

        if (!lexer.readToken(&token) or !std.mem.eql(u8, token.slice(), PROC_FILE_ID)) {
            std.debug.print("Bad id {s} instead of {s}\n", .{ token.slice(), PROC_FILE_ID });
            return error.BadProcFileId;
        }

        var numEntries: usize = 0;
        while (lexer.readToken(&token)) {
            if (std.mem.eql(u8, token.slice(), "model")) {
                const render_model = try render_world.parseModel(&lexer);
                // add it to the model manager list
                global.RenderModelManager.addModel(render_model.ptr);

                // save it in the list to free when clearing this map
                try render_world.local_models.append(render_model);
                numEntries += 1;
                continue;
            }

            if (std.mem.eql(u8, token.slice(), "shadowModel")) {
                //const last_model = render_world.parseShadowModel(&lexer);
                // add it to the model manager list
                //global.renderModelManager.addModel(last_model);

                // save it in the list to free when clearing this map
                //render_world.local_models.append(last_model);
                numEntries += 1;
                continue;
            }

            if (std.mem.eql(u8, token.slice(), "interAreaPortals")) {
                //render_world.parseInterAreaPortals(&lexer);
                numEntries += 1;
                continue;
            }

            if (std.mem.eql(u8, token.slice(), "nodes")) {
                //render_world.parseNodes(&lexer);
                numEntries += 1;
                continue;
            }

            std.debug.print("Bad token {s}\n", .{token.slice()});
            return error.BadToken;
        }
    }

    // 7. if it was a trivial map without any areas, create a single area
    if (render_world.portal_areas == null) {
        try render_world.clearWorld();
    }

    // 8. find the points where we can early-our of reference pushing into the BSP tree
    if (render_world.area_nodes) |area_nodes| {
        _ = commonChildrenArea_r(&area_nodes[0], area_nodes);
    }

    if (render_world.portal_areas) |portal_areas| {
        try render_world.addWorldModelEntities(portal_areas);
    }

    render_world.clearPortalStates();
    render_world.setupLightGrid();
}

fn commonChildrenArea_r(node: *AreaNode, area_nodes: []AreaNode) c_int {
    var nums: [2]c_int = .{ 0, 0 };

    for (&nums, 0..) |*num, i| {
        num.* = if (node.children[i] <= 0)
            -1 - node.children[i]
        else
            commonChildrenArea_r(&area_nodes[@intCast(node.children[i])], area_nodes);
    }

    // solid nodes will match any area
    if (nums[0] == AreaNode.AREANUM_SOLID)
        nums[0] = nums[1];

    if (nums[1] == AreaNode.AREANUM_SOLID)
        nums[1] = nums[0];

    const common = if (nums[0] == nums[1])
        nums[0]
    else
        AreaNode.CHILDREN_HAVE_MULTIPLE_AREAS;

    node.commonChildrenArea = common;

    return common;
}

fn addWorldModelEntities(render_world: *RenderWorld, portal_areas: []PortalArea) !void {
    var buffer: [256]u8 = undefined;
    var fixed_allocator = std.heap.FixedBufferAllocator.init(&buffer);
    defer fixed_allocator.reset();
    const string_allocator = fixed_allocator.allocator();

    for (portal_areas, 0..) |*area, area_index| {
        defer fixed_allocator.reset();

        var def = try render_world.allocator.create(RenderEntityLocal);
        errdefer render_world.allocator.destroy(def);
        def.* = RenderEntityLocal{};

        const index = for (render_world.entity_defs.items, 0..) |*item, item_index| {
            if (item.* == null) {
                item.* = def;
                break item_index;
            }
        } else index: {
            try render_world.entity_defs.append(def);
            break :index render_world.entity_defs.items.len - 1;
        };

        def.index = @intCast(index);
        def.world = @ptrCast(render_world);

        const model_name = try std.fmt.allocPrintZ(string_allocator, "_area{d}", .{area_index});
        const model_ptr = global.RenderModelManager.findModel(model_name);
        const render_model = model.RenderModel{ .ptr = model_ptr };
        def.parms.hModel = model_ptr;

        // TODO: error if hModel->IsDefaultModel() or !hModel->IsStaticWorldModel()
        // TODO: set needsPortalSky if model shader name matches "textures/smf/portal_sky"

        // the local and global reference bounds are the same for area models
        def.localReferenceBounds = render_model.bounds();
        def.globalReferenceBounds = render_model.bounds();

        def.parms.axis.mat[0].x = 1.0;
        def.parms.axis.mat[1].y = 1.0;
        def.parms.axis.mat[2].z = 1.0;

        def.parms.shaderParms[0] = 1.0;
        def.parms.shaderParms[1] = 1.0;
        def.parms.shaderParms[2] = 1.0;
        def.parms.shaderParms[3] = 1.0;

        def.deriveEntityData();
        try render_world.addEntityRefToArea(def, area);

        area.globalBounds = def.globalReferenceBounds;
    }
}

extern fn c_incEntityReferences() callconv(.C) void;

pub fn addEntityRefToArea(
    render_world: *RenderWorld,
    def: *RenderEntityLocal,
    area: *PortalArea,
) error{OutOfMemory}!void {
    {
        // check if we already have reference to that area
        var opt_ref: ?*AreaReference = def.entityRefs;
        while (opt_ref) |ref| : (opt_ref = ref.ownerNext) {
            if (ref.area == area) return;
        }
    }

    var ref = try render_world.area_reference_allocator.create();
    ref.* = AreaReference{};

    c_incEntityReferences();

    ref.entity = def;

    // link to entityDef
    ref.ownerNext = def.entityRefs;
    def.entityRefs = ref;

    // link to end of area list
    ref.area = area;
    ref.areaNext = &area.entityRefs;
    ref.areaPrev = area.entityRefs.areaPrev;
    ref.areaNext.?.areaPrev = ref;
    ref.areaPrev.?.areaNext = ref;
}

fn clearPortalStates(render_world: *RenderWorld) void {
    // all portals start off open
    if (render_world.double_portals) |double_portals| {
        for (double_portals) |*double_portal| {
            double_portal.blockingBits = PortalConnection.PS_BLOCK_NONE;
        }
    }

    // flood fill all area connections
    if (render_world.portal_areas) |portal_areas| {
        for (portal_areas) |*portal_area| {
            for (0..NUM_PORTAL_ATTRIBUTES) |attribute_index| {
                render_world.connected_area_num += 1;
                render_world.floodConnectedAreas(portal_areas, portal_area, attribute_index);
            }
        }
    }
}

fn floodConnectedAreas(
    render_world: *RenderWorld,
    portal_areas: []PortalArea,
    area: *PortalArea,
    portal_attribute_index: usize,
) void {
    if (area.connectedAreaNum[portal_attribute_index] == render_world.connected_area_num)
        return;

    area.connectedAreaNum[portal_attribute_index] = @intCast(render_world.connected_area_num);

    var opt_portal: ?*Portal = area.portals;
    while (opt_portal) |portal| : (opt_portal = portal.next) {
        if (portal.doublePortal) |double_portal| {
            const attribute_mask = @as(c_int, 1) << @intCast(portal_attribute_index);
            if ((double_portal.blockingBits & attribute_mask) == 0) {
                render_world.floodConnectedAreas(
                    portal_areas,
                    &portal_areas[@intCast(portal.intoArea)],
                    portal_attribute_index,
                );
            }
        }
    }
}

fn setupLightGrid(_: *RenderWorld) void {
    // TODO: convert
    // idRenderWorldLocal::SetupLightGrid (hard)
    // -> idRenderWorldLocal::LoadLightGridFile (parse and generate binary) (hard)
    // -> idRenderWorldLocal::LoadLightGridImages (execute nvrhi command list) (hard)
    // -> LightGrid::SetupLightGrid (medium)
    // -> -> LightGrid::CalculateLightGridPointPositions (medium)
    // -> LightGrid::CountValidGridPoints (easy)
}

const ParseModelError = error{
    BadNumSurfaces,
    BadNumVertices,
    BadNumIndices,
};

const sys_types = @import("../sys/types.zig");
const model = @import("model.zig");

fn parseModel(render_world: *RenderWorld, lexer: *Lexer) !model.RenderModel { // idRenderModel
    try lexer.expectTokenString("{");

    // reusable token
    var token = Token.init();
    defer token.deinit();

    // model name
    try lexer.expectAnyToken(&token);

    var render_model = try model.RenderModel.initEmpty(token.slice());
    errdefer render_model.deinit(render_world);

    const num_surfaces = try lexer.parseSize();

    for (0..num_surfaces) |surface_id| {
        // surface parsing start
        try lexer.expectTokenString("{");

        try lexer.expectAnyToken(&token);

        const num_vertices = try lexer.parseSize();
        const num_indices = try lexer.parseSize();

        // parse vertices
        const row_len = 8;
        var vertices = try render_world.allocator.alloc(f32, row_len * num_vertices);
        defer render_world.allocator.free(vertices);
        for (0..num_vertices) |vi| {
            const start = vi * row_len;
            const end = start + row_len;
            try lexer.parse1DMatrix(vertices[start..end]);
        }

        // parse indices
        const indices = try render_world.allocator.alloc(sys_types.TriIndex, num_indices);
        defer render_world.allocator.free(indices);
        for (indices) |*index| {
            index.* = @intCast(try lexer.parseSize());
        }

        // surface parsing end
        try lexer.expectTokenString("}");

        // add the completed surface to the model
        render_model.addSurface(try render_world.createModelSurface(
            surface_id,
            token.slice(),
            vertices,
            num_vertices,
            indices,
        ));
    }

    try lexer.expectTokenString("}");

    // RB: FIXME add check for mikktspace
    render_model.finishSurfaces(false);

    return render_model;
}

const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
extern fn c_material_addReference(*anyopaque) callconv(.C) void;

inline fn createModelSurface(
    render_world: *RenderWorld,
    surface_id: usize,
    meterial_name: []const u8,
    vertices: []f32,
    num_vertices: usize,
    indices: []sys_types.TriIndex,
) !model.ModelSurface {
    var surface_triangles = try render_world.allocator.create(model.SurfaceTriangles);
    surface_triangles.* = std.mem.zeroes(model.SurfaceTriangles);
    surface_triangles.numVerts = @intCast(num_vertices);
    surface_triangles.numIndexes = @intCast(indices.len);

    const opt_material_ptr = try global.DeclManager.findMaterial(meterial_name);
    if (opt_material_ptr) |ptr| c_material_addReference(ptr);

    const surface: model.ModelSurface = .{
        .id = @intCast(surface_id),
        .shader = opt_material_ptr,
        .geometry = surface_triangles,
    };

    // find the island that each vertex belongs to
    var num_islands: usize = 0;
    const vertex_islands = try render_world.allocator.alloc(usize, vertices.len);
    defer render_world.allocator.free(vertex_islands);
    for (vertex_islands) |*item| item.* = 0;

    {
        const tris_visited = try render_world.allocator.alloc(bool, indices.len);
        defer render_world.allocator.free(tris_visited);
        for (tris_visited) |*item| item.* = false;

        var j: usize = 0;
        while (j < indices.len) : (j += 3) {
            if (tris_visited[j]) continue;

            num_islands += 1;
            const island_num = num_islands;

            vertex_islands[indices[j + 0]] = island_num;
            vertex_islands[indices[j + 1]] = island_num;
            vertex_islands[indices[j + 2]] = island_num;
            tris_visited[j] = true;

            var queue = std.ArrayList(usize).init(render_world.allocator);
            defer queue.deinit();
            try queue.append(j);

            var n: usize = 0;
            while (n < queue.items.len) : (n += 1) {
                const t = queue.items[n];

                var k: usize = 0;
                while (k < indices.len) : (k += 3) {
                    if (tris_visited[k]) continue;

                    const connected =
                        indices[t + 0] == indices[k + 0] or
                        indices[t + 0] == indices[k + 1] or
                        indices[t + 0] == indices[k + 2] or
                        indices[t + 1] == indices[k + 0] or
                        indices[t + 1] == indices[k + 1] or
                        indices[t + 1] == indices[k + 2] or
                        indices[t + 2] == indices[k + 0] or
                        indices[t + 2] == indices[k + 1] or
                        indices[t + 2] == indices[k + 2];

                    if (connected) {
                        vertex_islands[indices[k + 0]] = island_num;
                        vertex_islands[indices[k + 1]] = island_num;
                        vertex_islands[indices[k + 2]] = island_num;
                        tris_visited[k] = true;
                        try queue.append(k);
                    }
                }
            }
        }
    }

    // center the texture coordinates for each island for maximum 16-bit precision
    for (1..num_islands) |island_num| {
        var min_S = std.math.floatMax(f32);
        var min_T = std.math.floatMax(f32);
        var max_S = -std.math.floatMax(f32);
        var max_T = -std.math.floatMax(f32);
        for (0..num_vertices) |vertex_index| {
            if (vertex_islands[vertex_index] == island_num) {
                min_S = @min(min_S, vertices[vertex_index * 8 + 3]);
                max_S = @max(max_S, vertices[vertex_index * 8 + 3]);
                min_T = @min(min_T, vertices[vertex_index * 8 + 4]);
                max_T = @max(max_T, vertices[vertex_index * 8 + 4]);
            }
        }

        const average_S: f32 = @floor((min_S + max_S) * 0.5);
        const average_T: f32 = @floor((min_T + max_T) * 0.5);
        for (0..num_vertices) |vertex_index| {
            if (vertex_islands[vertex_index] == island_num) {
                vertices[vertex_index * 8 + 3] -= average_S;
                vertices[vertex_index * 8 + 4] -= average_T;
            }
        }
    }

    // TODO: alloc alignment = 16
    const verts = try render_world.allocator.alloc(DrawVertex, num_vertices);
    for (0..num_vertices) |i| {
        verts[i].xyz.x = vertices[i * 8 + 0];
        verts[i].xyz.y = vertices[i * 8 + 1];
        verts[i].xyz.z = vertices[i * 8 + 2];
        verts[i].setTexCoord(vertices[i * 8 + 3], vertices[i * 8 + 4]);
        verts[i].setNormal(vertices[i * 8 + 5], vertices[i * 8 + 6], vertices[i * 8 + 7]);
    }
    surface_triangles.verts = verts.ptr;

    // TODO: alloc alignment = 16
    const indexes = try render_world.allocator.alloc(sys_types.TriIndex, indices.len);
    for (indexes, indices) |*surface_index, index| {
        surface_index.* = index;
    }
    surface_triangles.indexes = indexes.ptr;

    return surface;
}

pub fn destroyModelSurface(render_world: *RenderWorld, model_surface: *model.ModelSurface) void {
    const geometry = if (model_surface.geometry) |tris| tris else return;

    if (geometry.verts) |verts| {
        const verts_slice = verts[0..@intCast(geometry.numVerts)];
        render_world.allocator.free(verts_slice);
    }

    if (geometry.indexes) |indexes| {
        const indexes_slice = indexes[0..@intCast(geometry.numIndexes)];
        render_world.allocator.free(indexes_slice);
    }

    render_world.allocator.destroy(geometry);
    model_surface.geometry = null;
}
