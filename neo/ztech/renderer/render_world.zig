const CVec3 = @import("../math/vector.zig").CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;
const std = @import("std");
const CMat3 = @import("../math/matrix.zig").CMat3;
const Plane = @import("../math/plane.zig").Plane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Bounds = @import("../bounding_volume/bounds.zig");
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const FrustumCorners = @import("matrix.zig").FrustumCorners;
const FrustumCull = @import("matrix.zig").FrustumCull;
const CWinding = @import("../geometry/winding.zig").CWinding;
const CFixedWinding = @import("../geometry/winding.zig").CFixedWinding;
const material = @import("material.zig");
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;
const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderEnvprobeLocal = @import("render_envprobe.zig").RenderEnvprobeLocal;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const RenderSystem = @import("render_system.zig");
const fs = @import("../fs.zig");
const Image = @import("image.zig").Image;
const RenderModelManager = @import("render_model_manager.zig");
const GuiModel = @import("gui_model.zig").GuiModel;

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
    globalMaterial: ?*const material.Material,
    viewEyeBuffer: c_int,
    stereoScreenSeparation: f32,
    rdflags: c_int,
};

// RenderWorld
const RenderWorld = @This();

extern var game_ztechRenderWorld: ?*RenderWorld;

pub inline fn instance() *RenderWorld {
    return game_ztechRenderWorld orelse @panic("Unable to access RenderWorld instance");
}

pub const MAX_DECAL_SURFACES: usize = 32;

pub const AreaNode = extern struct {
    pub const CHILDREN_HAVE_MULTIPLE_AREAS: c_int = -2;
    pub const AREANUM_SOLID: c_int = -1;

    plane: Plane,
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
    irradianceImage: ?*Image,
    imageSingleProbeSize: c_int,
    imageBorderSize: c_int,
};

pub const Portal = extern struct {
    // area this portal leads to
    intoArea: c_int,
    // winding points have counter clockwise ordering seen this area
    w: *CWinding,
    // view must be on the positive side of the plane to cross
    plane: Plane,
    // next portal of the area
    next: ?*Portal,
    doublePortal: ?*DoublePortal,
};

pub const ExitPortal = extern struct {
    areas: [2]c_int,
    w: *CWinding,
    blockingBits: c_int,
    portalHandle: qhandle_t,
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
    portals: ?*Portal,
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
area_screen_rect: ?[]ScreenRect = null,
double_portals: ?[]DoublePortal = null,
local_models: std.ArrayList(*model.RenderModel),
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
interaction_table: ?[]?*Interaction = null,
// entityDefs
interaction_table_width: usize = 0,
// lightDefs
interaction_table_height: usize = 0,
generate_all_interactions_called: bool = false,

const global = @import("../global.zig");
const RenderEntity = @import("render_entity.zig").RenderEntity;
const RenderLight = @import("render_light.zig").RenderLight;
const RenderEnvironmentProbe = @import("render_envprobe.zig").RenderEnvironmentProbe;

pub const DefIndexAccessError = error{
    OutOfRange,
    SlotIsNull,
};

pub fn getRenderEntity(render_world: *const RenderWorld, index: usize) ?*const RenderEntity {
    if (index >= render_world.entity_defs.items.len) return null;
    const def = render_world.entity_defs.items[index] orelse return null;

    return &def.parms;
}

pub fn getRenderLight(render_world: *const RenderWorld, index: usize) ?*const RenderLight {
    if (index >= render_world.light_defs.items.len) return null;
    const def = render_world.light_defs.items[index] orelse return null;

    return &def.parms;
}

// Frees all references and lit surfaces from the light, and
// NULL's out it's entry in the world list
pub fn freeLightDefByIndex(render_world: *RenderWorld, light_index: usize) DefIndexAccessError!void {
    if (light_index >= render_world.light_defs.items.len) return error.OutOfRange;

    if (render_world.light_defs.items[light_index]) |def| {
        render_world.freeLightDef(def, light_index);
    } else return error.SlotIsNull;
}

inline fn freeLightDef(render_world: *RenderWorld, def: *RenderLightLocal, light_index: usize) void {
    def.freeLightDerivedData();
    render_world.allocator.destroy(def);
    render_world.light_defs.items[light_index] = null;
}

pub fn addLightDef(render_world: *RenderWorld, render_light: RenderLight) !usize {
    // try reuse a free slot
    const index = for (render_world.light_defs.items, 0..) |item, item_index| {
        if (item == null) break item_index;
    } else index: {
        try render_world.light_defs.append(null);
        const new_len = render_world.light_defs.items.len;

        if (render_world.interaction_table != null and
            new_len > render_world.interaction_table_width)
        {
            try render_world.resizeInteractionTable();
        }

        break :index new_len - 1;
    };

    try render_world.updateLightDef(index, render_light);

    return index;
}

pub fn updateLightDef(
    render_world: *RenderWorld,
    light_index: usize,
    render_light: RenderLight,
) !void {
    // TODO: light_index > MAX_LIGHT_DEFS_INDEX(10000)

    // create new slots if needed
    while (light_index >= render_world.light_defs.items.len)
        try render_world.light_defs.append(null);

    var just_update = false;
    var light = if (render_world.light_defs.items[light_index]) |light_def| light: {
        // if the shape of the light stays the same, we don't need to dump
        // any of our derived data, because shader parms are calculated every frame
        const axis_match = render_light.axis.toMat3f().eql(light_def.parms.axis.toMat3f());
        const light_center_match = render_light.lightCenter.toVec3f().eql(light_def.parms.lightCenter.toVec3f());
        const light_radius_match = render_light.lightRadius.toVec3f().eql(light_def.parms.lightRadius.toVec3f());
        const noshadows_match = render_light.noShadows == light_def.parms.noShadows;
        const origin_match = render_light.origin.toVec3f().eql(light_def.parms.origin.toVec3f());
        const parallel_match = render_light.parallel == light_def.parms.parallel;
        const pointlight_match = render_light.pointLight == light_def.parms.pointLight;
        const shader_match = render_light.shader == light_def.lightShader;
        const start_match = render_light.start.toVec3f().eql(light_def.parms.start.toVec3f());
        const end_match = render_light.end.toVec3f().eql(light_def.parms.end.toVec3f());
        const right_match = render_light.right.toVec3f().eql(light_def.parms.right.toVec3f());
        const up_match = render_light.up.toVec3f().eql(light_def.parms.up.toVec3f());
        const target_match = render_light.target.toVec3f().eql(light_def.parms.target.toVec3f());

        if (axis_match and
            light_center_match and
            noshadows_match and
            light_radius_match and
            origin_match and
            parallel_match and
            pointlight_match and
            shader_match and
            start_match and
            end_match and
            right_match and
            up_match and
            target_match)
        {
            just_update = true;
        } else {
            // if we are updating shadows, the prelight model is no longer valid
            light_def.lightHasMoved = true;
            light_def.freeLightDerivedData();
        }

        break :light light_def;
    } else light: {
        // create a new one
        var light_def = try render_world.allocator.create(RenderLightLocal);
        light_def.* = RenderLightLocal{};
        render_world.light_defs.items[light_index] = light_def;

        light_def.index = @intCast(light_index);
        light_def.world = render_world;
        break :light light_def;
    };

    light.parms = render_light;
    light.lastModifiedFrameNum = @intCast(RenderSystem.instance.frameCount());

    // new for BFG edition: force noShadows on spectrum lights so teleport spawns
    // don't cause such a slowdown.  Hell writing shouldn't be shadowed anyway...
    if (light.parms.shader) |shader| {
        if (shader.spectrum() > 0)
            light.parms.noShadows = true;
    }

    if (!just_update)
        try light.createLightRefs();
}

pub fn freeEntityDefByIndex(render_world: *RenderWorld, entity_index: usize) DefIndexAccessError!void {
    if (entity_index >= render_world.entity_defs.items.len) return error.OutOfRange;

    if (render_world.entity_defs.items[entity_index]) |def| {
        render_world.freeEntityDef(def, entity_index);
    } else return error.SlotIsNull;
}

inline fn freeEntityDef(render_world: *RenderWorld, def: *RenderEntityLocal, entity_index: usize) void {
    def.freeEntityDerivedData(false, false);

    def.parms.gui[0] = null;
    def.parms.gui[1] = null;
    def.parms.gui[2] = null;

    render_world.allocator.destroy(def);
    render_world.entity_defs.items[entity_index] = null;
}

pub fn addEnvprobeDef(render_world: *RenderWorld, envprobe: RenderEnvironmentProbe) !usize {
    // try reuse a free slot
    const index = for (render_world.envprobe_defs.items, 0..) |item, item_index| {
        if (item == null) break item_index;
    } else index: {
        try render_world.envprobe_defs.append(null);
        const new_len = render_world.envprobe_defs.items.len;

        break :index new_len - 1;
    };

    try render_world.updateEnvprobeDef(index, envprobe);

    return index;
}

pub fn updateEnvprobeDef(
    render_world: *RenderWorld,
    envprobe_index: usize,
    envprobe: RenderEnvironmentProbe,
) !void {
    // create new slots if needed
    while (envprobe_index >= render_world.envprobe_defs.items.len)
        try render_world.envprobe_defs.append(null);

    var just_update = false;
    var probe = if (render_world.envprobe_defs.items[envprobe_index]) |def| probe: {
        if (envprobe.origin.toVec3f().eql(def.parms.origin.toVec3f())) {
            just_update = true;
        } else {
            def.envprobeHasMoved = true;
            def.freeDerivedData();
        }

        break :probe def;
    } else probe: {
        // create a new one
        var def = try render_world.allocator.create(RenderEnvprobeLocal);
        def.* = std.mem.zeroes(RenderEnvprobeLocal);
        def.world = render_world;
        def.index = @intCast(envprobe_index);
        def.viewCount = 0;

        render_world.envprobe_defs.items[envprobe_index] = def;

        break :probe def;
    };

    probe.parms = envprobe;
    probe.lastModifiedFrameNum = @intCast(RenderSystem.instance.frameCount());

    if (!just_update)
        try probe.createRefs();
}

pub fn freeEnvprobeDefByIndex(render_world: *RenderWorld, envprobe_index: usize) DefIndexAccessError!void {
    if (envprobe_index >= render_world.envprobe_defs.items.len) return error.OutOfRange;

    if (render_world.envprobe_defs.items[envprobe_index]) |def| {
        render_world.freeEnvprobeDef(def, envprobe_index);
    } else return error.SlotIsNull;
}

inline fn freeEnvprobeDef(render_world: *RenderWorld, def: *RenderEnvprobeLocal, index: usize) void {
    def.freeDerivedData();
    render_world.allocator.destroy(def);
    render_world.envprobe_defs.items[index] = null;
}

pub fn addEntityDef(render_world: *RenderWorld, render_entity: RenderEntity) !usize {
    // try reuse a free slot
    const index = for (render_world.entity_defs.items, 0..) |item, item_index| {
        if (item == null) break item_index;
    } else index: {
        try render_world.entity_defs.append(null);
        const new_len = render_world.entity_defs.items.len;

        if (render_world.interaction_table != null and
            new_len > render_world.interaction_table_width)
        {
            try render_world.resizeInteractionTable();
        }

        break :index new_len - 1;
    };

    try render_world.updateEntityDef(index, render_entity);

    return index;
}

fn resizeInteractionTable(render_world: *RenderWorld) error{OutOfMemory}!void {
    // we overflowed the interaction table, so make it larger
    const old_table = render_world.interaction_table orelse return;
    const old_width = render_world.interaction_table_width;
    const old_height = render_world.interaction_table_height;

    // build the interaction table
    // this will be dynamically resized if the entity / light counts grow too much
    render_world.interaction_table_width = render_world.entity_defs.items.len + 100;
    render_world.interaction_table_height = render_world.light_defs.items.len + 100;
    const size: usize = render_world.interaction_table_width * render_world.interaction_table_height;
    const interaction_table = try render_world.allocator.alloc(?*Interaction, size);
    for (interaction_table) |*elem| elem.* = null;

    for (0..old_height) |h| {
        for (0..old_width) |w| {
            interaction_table[h * render_world.interaction_table_width + w] = old_table[h * old_width + w];
        }
    }

    render_world.interaction_table = interaction_table;
    render_world.allocator.free(old_table);
}

const DeviceManager = @import("../sys/device_manager.zig");
const Session = @import("../sys/session.zig");

/// Force the generation of all light / surface interactions at the start of a level
/// If this isn't called, they will all be dynamically generated
pub fn generateAllInteractions(render_world: *RenderWorld) !void {
    if (!RenderSystem.instance.initialized) return;
    render_world.generate_all_interactions_called = false;

    // let the interaction creation code know that it shouldn't
    // try and do any view specific optimizations
    RenderSystem.instance.clearViewDef();

    render_world.interaction_table_width = render_world.entity_defs.items.len + 100;
    render_world.interaction_table_height = render_world.light_defs.items.len + 100;

    const size: usize = render_world.interaction_table_width * render_world.interaction_table_height;
    const interaction_table = try render_world.allocator.alloc(?*Interaction, size);
    for (interaction_table) |*elem| elem.* = null;
    render_world.interaction_table = interaction_table;

    const command_list_ptr = RenderSystem.instance.command_list.ptr_ orelse @panic("CommandListHandle is not initialized!");

    command_list_ptr.open();
    defer {
        command_list_ptr.close();
        DeviceManager.instance().getDevice()
            .executeCommandList(command_list_ptr);
    }

    for (render_world.light_defs.items) |opt_light_def| {
        const light_def = opt_light_def orelse continue;
        defer Session.instance.pump();

        var opt_light_ref = light_def.references;
        while (opt_light_ref) |light_ref| : (opt_light_ref = light_ref.ownerNext) {
            var area = light_ref.area orelse continue;
            var opt_entity_ref = area.entityRefs.areaNext;

            // check all the models in this area
            while (opt_entity_ref) |entity_ref| : (opt_entity_ref = entity_ref.areaNext) {
                if (entity_ref == &area.entityRefs) break;
                const entity_def = entity_ref.entity orelse continue;

                var opt_inter = entity_def.firstInteraction;
                while (opt_inter) |inter| : (opt_inter = inter.entityNext) {
                    if (inter.lightDef == light_def) break;
                }

                // if we already have an interaction, we don't need to do anything
                if (opt_inter != null) continue;

                var new_inter = try Interaction.allocAndLink(entity_def, light_def);
                errdefer new_inter.unlinkAndFree(render_world.allocator);
                try new_inter.createStaticInteraction(
                    command_list_ptr,
                    render_world.allocator,
                );
            }
        }
    }

    render_world.generate_all_interactions_called = true;
}

const FrameData = @import("frame_data.zig");
const ViewDef = @import("common.zig").ViewDef;
const ViewEntity = @import("common.zig").ViewEntity;
const ViewLight = @import("common.zig").ViewLight;
const ViewEnvprobe = @import("common.zig").ViewEnvprobe;
const DrawSurface = @import("common.zig").DrawSurface;

extern fn R_SetupViewMatrix(*ViewDef) callconv(.C) void;
extern fn R_SetupProjectionMatrix(*ViewDef, bool) callconv(.C) void;
extern fn R_SetupUnprojection(*ViewDef) callconv(.C) void;
extern fn R_SetupSplitFrustums(*ViewDef) callconv(.C) void;
extern fn R_AddInGameGuis2([*]*DrawSurface, c_int, *ViewDef, *GuiModel) callconv(.C) void;
extern fn R_OptimizeViewLightsList(*ViewDef) callconv(.C) void;
extern fn R_SortDrawSurfs([*]*DrawSurface, c_int) callconv(.C) void;

pub fn renderScene(render_world: *RenderWorld, render_view: RenderView) void {
    if (!RenderSystem.instance.initialized) return;

    // close any gui drawing
    RenderSystem.instance.gui_model.emitFullScreen(null);
    RenderSystem.instance.gui_model.clear();

    const r_skip_front_end = false;

    if (r_skip_front_end) return;

    var view_def = FrameData.frameCreate(ViewDef);
    view_def.renderView = render_view;
    view_def.targetRender = null;

    var window_width = RenderSystem.instance.getWidth();
    var window_height = RenderSystem.instance.getHeight();

    RenderSystem.instance.performResolutionScaling(&window_width, &window_height);
    RenderSystem.instance.cropRenderSize(window_width, window_height);
    view_def.viewport = RenderSystem.instance.getCroppedViewport();

    view_def.scissor.x1 = 0;
    view_def.scissor.y1 = 0;
    view_def.scissor.x2 = view_def.viewport.x2 - view_def.viewport.x1;
    view_def.scissor.y2 = view_def.viewport.y2 - view_def.viewport.y1;

    view_def.isSubview = false;
    view_def.isObliqueProjection = false;
    view_def.initialViewAreaOrigin = render_view.vieworg;
    view_def.renderWorld = @ptrCast(render_world);

    const cross = Vec3(f32).cross(
        render_view.viewaxis.mat[1].toVec3f(),
        render_view.viewaxis.mat[2].toVec3f(),
    );

    view_def.isMirror = cross.dot(render_view.viewaxis.mat[0].toVec3f()) <= 0;

    render_world.renderView(view_def);
    renderPostProcess(view_def);

    RenderSystem.instance.uncrop();
    RenderSystem.instance.gui_model.clear();
}

fn renderView(render_world: *RenderWorld, view_def: *ViewDef) void {
    const old_view_def = RenderSystem.instance.getView();
    RenderSystem.instance.setView(view_def);
    defer RenderSystem.instance.setView(old_view_def);

    R_SetupViewMatrix(view_def);
    R_SetupProjectionMatrix(view_def, true);
    R_SetupProjectionMatrix(view_def, false);
    R_SetupUnprojection(view_def);

    const projection_matrix = RenderMatrix{ .m = view_def.projectionMatrix };
    view_def.projectionRenderMatrix = projection_matrix.transpose();
    const model_view_matrix = RenderMatrix{ .m = view_def.worldSpace.modelViewMatrix };
    const view_render_matrix = model_view_matrix.transpose();
    view_def.worldSpace.mvp = view_def.projectionRenderMatrix.multiply(view_render_matrix);
    const unjittered_projection_matrix = RenderMatrix{ .m = view_def.unjitteredProjectionMatrix };
    view_def.unjitteredProjectionRenderMatrix = unjittered_projection_matrix.transpose();
    view_def.worldSpace.unjitteredMVP = view_def.unjitteredProjectionRenderMatrix.multiply(view_render_matrix);

    var frustum_planes = RenderMatrix.getFrustumPlanes(
        view_def.worldSpace.mvp,
        false,
        true,
    );

    for (&frustum_planes) |*plane| {
        plane.* = plane.flip();
    }

    const r_znear: f32 = 3.0;
    frustum_planes[4].d -= r_znear;
    const FRUSTUM_PRIMARY: usize = 0;
    view_def.frustums[FRUSTUM_PRIMARY] = frustum_planes;

    R_SetupSplitFrustums(view_def);

    render_world.findViewLightsAndEntities(&view_def.frustums[FRUSTUM_PRIMARY]);

    RenderSystem.instance.front_end_job_list.wait();

    render_world.addLights();
    render_world.addModels();

    if (view_def.drawSurfs) |draw_surfs| {
        R_AddInGameGuis2(
            draw_surfs,
            view_def.numDrawSurfs,
            view_def,
            RenderSystem.instance.gui_model,
        );
    }

    R_OptimizeViewLightsList(view_def);

    if (view_def.drawSurfs) |draw_surfs| {
        // sort all the ambient surfaces for translucency ordering
        R_SortDrawSurfs(draw_surfs, view_def.numDrawSurfs);
        // generate any subviews (mirrors, cameras, etc) before adding this view
        render_world.generateSubviews(draw_surfs[0..@intCast(view_def.numDrawSurfs)]);
    }

    render_world.findClosestEnvironmentProbes(view_def);

    var cmd = FrameData.createCommand(FrameData.DrawSurfacesCommand);
    cmd.commandId = .RC_DRAW_VIEW_3D;
    cmd.viewDef = view_def;
}

fn renderPostProcess(view_def: *ViewDef) void {
    const old_view_def = RenderSystem.instance.getView();
    RenderSystem.instance.setView(view_def);
    defer RenderSystem.instance.setView(old_view_def);

    const RDF_IRRADIANCE: c_int = 4;
    if ((view_def.renderView.rdflags & RDF_IRRADIANCE) == 0) {
        var cmd = FrameData.createCommand(FrameData.PostProcessCommand);
        cmd.commandId = .RC_POST_PROCESS;
        cmd.viewDef = view_def;
    }
}

const ImageManager = @import("image_manager.zig");

fn findClosestEnvironmentProbes(_: RenderWorld, view_def: *ViewDef) void {
    view_def.globalProbeBounds = .{};
    view_def.irradianceImage = ImageManager.instance.defaultUACIrradianceCube;
    view_def.radianceImageBlends = .{ .x = 1 };
    for (&view_def.radianceImages) |*opt_image_ptr| {
        opt_image_ptr.* = ImageManager.instance.defaultUACRadianceCube;
    }

    if (view_def.areaNum == -1 or view_def.isSubview)
        return;

    // TODO: continue
}

fn generateSubviews(_: *RenderWorld, draw_surfs: []*const DrawSurface) void {
    for (draw_surfs) |surf_ptr| {
        const surf_material = surf_ptr.material orelse continue;
        if (!surf_material.hasSubview()) continue;

        // TODO: generate subview surface
    }
}

extern fn c_addSingleLight(*anyopaque, *ViewLight, *ViewDef) callconv(.C) void;

fn addLights(render_world: *RenderWorld) void {
    const view_def = RenderSystem.instance.getView() orelse return;
    var opt_view_light = view_def.viewLights;
    while (opt_view_light) |view_light| : (opt_view_light = view_light.next) {
        c_addSingleLight(@ptrCast(render_world), view_light, view_def);
    }

    cullLightsMarkedAsRemoved(view_def);
}

extern fn c_addSingleModel(*anyopaque, *ViewEntity, *ViewDef) callconv(.C) void;
extern fn R_SortViewEntities(?*ViewEntity) callconv(.C) ?*ViewEntity;

fn addModels(render_world: *RenderWorld) void {
    const view_def = RenderSystem.instance.getView() orelse return;
    view_def.viewEntitys = R_SortViewEntities(view_def.viewEntitys);

    var opt_view_entity = view_def.viewEntitys;
    while (opt_view_entity) |view_entity| : (opt_view_entity = view_entity.next) {
        c_addSingleModel(@ptrCast(render_world), view_entity, view_def);
    }

    moveDrawSurfsToView(view_def);
}

extern fn R_LinkDrawSurfToView(*DrawSurface, *ViewDef) callconv(.C) void;
inline fn moveDrawSurfsToView(def: *ViewDef) void {
    // clear the ambient surface list
    def.numDrawSurfs = 0;
    // will be set to INITIAL_DRAWSURFS on R_LinkDrawSurfToView
    def.maxDrawSurfs = 0;

    var opt_v_entity = def.viewEntitys;
    while (opt_v_entity) |v_entity| : (opt_v_entity = v_entity.next) {
        var opt_draw_surf = v_entity.drawSurfs;
        while (opt_draw_surf) |draw_surf| {
            // save it before assign
            opt_draw_surf = draw_surf.nextOnLight;
            if (draw_surf.linkChain) |link_chain| {
                draw_surf.nextOnLight = link_chain.*;
                link_chain.* = draw_surf;
            } else {
                R_LinkDrawSurfToView(draw_surf, def);
            }
        }

        v_entity.drawSurfs = null;
    }
}

pub fn findViewLightsAndEntities(render_world: *RenderWorld, frustum_planes: []Plane) void {
    const view_def = RenderSystem.instance.getView() orelse return;
    RenderSystem.instance.incViewCount();

    view_def.viewLights = null;
    view_def.viewEntitys = null;
    view_def.viewEnvprobes = null;

    for (render_world.area_screen_rect.?) |*screen_rect| {
        screen_rect.clear();
    }

    const r_use_portals = true;
    if (!r_use_portals) {
        view_def.areaNum = -1;
    } else {
        if (render_world.pointInArea(view_def.initialViewAreaOrigin.toVec3f())) |area_num| {
            view_def.areaNum = @intCast(area_num);
        } else |_| {
            view_def.areaNum = -1;
        }
    }

    render_world.buildConnectedAreas(view_def);

    const r_single_area = false;
    if (r_single_area) {
        if (view_def.areaNum >= 0) {
            var ps = std.mem.zeroes(PortalStack);
            ps.next = null;
            ps.p = null;

            for (ps.portalPlanes[0..5], frustum_planes[0..5]) |*portal_plane, plane| {
                portal_plane.* = plane;
            }

            ps.numPortalPlanes = 5;
            ps.rect = view_def.scissor;

            render_world.addAreaToView(@intCast(view_def.areaNum), &ps);
        }
    } else {
        render_world.flowViewThroughPortals(
            view_def.renderView.vieworg.toVec3f(),
            frustum_planes[0..5],
        );
    }
}

const MAX_PORTAL_PLANES: usize = 20;
const PortalStack = extern struct {
    p: ?*const Portal,
    next: ?*const PortalStack,
    numPortalPlanes: c_int,
    portalPlanes: [MAX_PORTAL_PLANES + 1]Plane,
    rect: ScreenRect,
};

fn flowViewThroughPortals(
    render_world: *RenderWorld,
    origin: Vec3(f32),
    planes: []Plane,
) void {
    std.debug.assert(planes.len <= MAX_PORTAL_PLANES);
    const view_def = RenderSystem.instance.getView() orelse return;

    var ps = std.mem.zeroes(PortalStack);
    ps.next = null;
    ps.p = null;

    for (planes, 0..) |plane, i| {
        ps.portalPlanes[i] = plane;
    }

    ps.numPortalPlanes = @intCast(planes.len);
    ps.rect = view_def.scissor;

    if (view_def.areaNum < 0) {
        for (render_world.area_screen_rect.?, 0..) |*rect, i| {
            rect.* = view_def.scissor;
            render_world.addAreaToView(i, &ps);
        }
    } else {
        render_world.floodViewThroughArea_r(origin, @intCast(view_def.areaNum), &ps);
    }
}

extern fn c_screenRectFromWinding(*const CWinding, [*]const f32) callconv(.C) ScreenRect;

fn floodViewThroughArea_r(
    render_world: *RenderWorld,
    origin: Vec3(f32),
    area_num: usize,
    ps: *const PortalStack,
) void {
    const area = &render_world.portal_areas.?[area_num];
    render_world.addAreaToView(area_num, ps);

    if (render_world.area_screen_rect) |rects| {
        if (rects[area_num].isEmpty()) {
            rects[area_num] = ps.rect;
        } else {
            rects[area_num].unionWith(ps.rect);
        }
    }

    var opt_portal: ?*Portal = area.portals;
    while (opt_portal) |portal| : (opt_portal = portal.next) {
        if ((portal.doublePortal.?.blockingBits & PS_BLOCK_VIEW) > 0)
            continue;

        const d = portal.plane.distance(origin);
        if (d < -0.1)
            continue;

        var opt_check: ?*const PortalStack = ps;
        while (opt_check) |check| : (opt_check = check.next) {
            if (check.p == portal) break;
        }

        if (opt_check != null) continue;

        if (d < 1.0) {
            var new_ps = ps.*;
            new_ps.p = portal;
            new_ps.next = ps;
            render_world.floodViewThroughArea_r(origin, @intCast(portal.intoArea), &new_ps);
            continue;
        }

        var w = CFixedWinding.fromWinding(portal.w.*);
        for (ps.portalPlanes[0..@intCast(ps.numPortalPlanes)]) |plane| {
            if (!w.clipInPlace(plane.flip(), 0, false)) break;
        }

        if (w.numPoints == 0) continue;
        if (render_world.portalIsFoggedOut(portal.*)) continue;

        var new_ps = std.mem.zeroes(PortalStack);
        new_ps.next = ps;
        new_ps.p = portal;
        new_ps.rect = c_screenRectFromWinding(
            @ptrCast(&w),
            (&RenderSystem.instance.identity_space).ptr,
        );
        new_ps.rect.intersect(ps.rect);

        const add_planes: usize = if (w.numPoints > MAX_PORTAL_PLANES)
            MAX_PORTAL_PLANES
        else
            @intCast(w.numPoints);

        new_ps.numPortalPlanes = 0;

        for (0..add_planes) |i| {
            const j = if (i + 1 == @as(usize, @intCast(w.numPoints))) 0 else i + 1;

            const v1 = origin.subtract(w.p[i].toVec3().toVec3f());
            const v2 = origin.subtract(w.p[j].toVec3().toVec3f());
            var portal_plane = &new_ps.portalPlanes[@intCast(new_ps.numPortalPlanes)];
            portal_plane.setNormal(Vec3(f32).cross(v1, v2));

            if (portal_plane.normalize(true) < 0.01) continue;

            portal_plane.fitThroughPoint(origin);
            new_ps.numPortalPlanes += 1;
        }

        new_ps.portalPlanes[@intCast(new_ps.numPortalPlanes)] = portal.plane;
        new_ps.numPortalPlanes += 1;

        render_world.floodViewThroughArea_r(origin, @intCast(portal.intoArea), &new_ps);
    }
}

fn portalIsFoggedOut(_: RenderWorld, portal: Portal) bool {
    _ = portal.doublePortal.?.fogLight orelse return false;

    // TODO: convert
    return false;
}

fn addAreaToView(
    render_world: *RenderWorld,
    area_num: usize,
    ps: *const PortalStack,
) void {
    render_world.portal_areas.?[area_num].viewCount = @intCast(RenderSystem.instance.viewCount());

    render_world.addAreaViewEntities(area_num, ps);
    render_world.addAreaViewLights(area_num, ps);
    render_world.addAreaViewEnvprobes(area_num, ps);
}

extern fn c_cullEntityByPortals(*const RenderMatrix, *const PortalStack) callconv(.C) bool;

fn addAreaViewEntities(
    render_world: *RenderWorld,
    area_num: usize,
    ps: *const PortalStack,
) void {
    const area = &render_world.portal_areas.?[area_num];
    var opt_ref: ?*AreaReference = area.entityRefs.areaNext;
    while (opt_ref) |ref| : (opt_ref = ref.areaNext) {
        if (ref == &area.entityRefs) break;
        const entity = ref.entity orelse continue;

        if (c_cullEntityByPortals(&entity.inverseBaseModelProject, ps))
            continue;

        var view_entity = setEntityDefViewEntity(entity);
        view_entity.scissorRect.unionWith(ps.rect);
    }
}

inline fn cullLightsMarkedAsRemoved(def: *ViewDef) void {
    //cull lights from the list if they turned out to not be needed
    var ptr = &def.viewLights;
    while (ptr.*) |v_light| {
        if (v_light.removeFromList) {
            // this probably doesn't matter with current code
            if (v_light.lightDef) |light_def| light_def.viewCount = -1;
            ptr.* = v_light.next;
            continue;
        }

        ptr = &v_light.next;

        var opt_shadow_ent = v_light.shadowOnlyViewEntities;
        while (opt_shadow_ent) |shadow_ent| : (opt_shadow_ent = shadow_ent.next) {
            if (shadow_ent.edef) |entity_def| {
                _ = setEntityDefViewEntity(entity_def);
            }
        }

        const r_show_light_scissors = false;
        if (r_show_light_scissors) {
            // TODO: R_ShowColoredScreenRect(v_light.scissorRect, v_light.lightDef.index);
        }
    }
}

fn setEntityDefViewEntity(def: *RenderEntityLocal) *ViewEntity {
    const view_count: c_int = @intCast(RenderSystem.instance.viewCount());
    if (def.viewCount == view_count)
        return def.viewEntity.?;

    def.viewCount = view_count;
    var v_model = FrameData.frameCreate(ViewEntity);
    v_model.entityDef = def;
    v_model.scissorRect.clear();
    const view_def = RenderSystem.instance.getView() orelse unreachable;
    v_model.next = view_def.viewEntitys;
    view_def.viewEntitys = v_model;
    def.viewEntity = v_model;

    return v_model;
}

extern fn c_cullLightByPortals(*const RenderMatrix, *const RenderMatrix, *const PortalStack) callconv(.C) bool;

fn addAreaViewLights(
    render_world: *RenderWorld,
    area_num: usize,
    ps: *const PortalStack,
) void {
    const area = &render_world.portal_areas.?[area_num];
    var opt_ref: ?*AreaReference = area.lightRefs.areaNext;
    while (opt_ref) |ref| : (opt_ref = ref.areaNext) {
        if (ref == &area.lightRefs) break;
        const light = ref.light orelse continue;

        if (c_cullLightByPortals(&light.inverseBaseLightProject, &light.baseLightProject, ps))
            continue;

        var view_light = setLightDefViewLight(light);
        view_light.scissorRect.unionWith(ps.rect);
    }
}

fn setLightDefViewLight(light: *RenderLightLocal) *ViewLight {
    const view_count: c_int = @intCast(RenderSystem.instance.viewCount());
    if (light.viewCount == view_count)
        return light.viewLight.?;

    light.viewCount = view_count;
    var v_light = FrameData.frameCreate(ViewLight);
    v_light.lightDef = light;
    v_light.scissorRect.clear();

    const view_def = RenderSystem.instance.getView() orelse unreachable;
    v_light.next = view_def.viewLights;
    view_def.viewLights = v_light;

    light.viewLight = v_light;

    return v_light;
}

fn addAreaViewEnvprobes(
    render_world: *RenderWorld,
    area_num: usize,
    ps: *const PortalStack,
) void {
    const area = &render_world.portal_areas.?[area_num];
    var opt_ref: ?*AreaReference = area.envprobeRefs.areaNext;
    while (opt_ref) |ref| : (opt_ref = ref.areaNext) {
        if (ref == &area.envprobeRefs) break;
        const probe = ref.envprobe orelse continue;

        var v_probe = setEnvprobeDefViewEnvprobe(probe);
        v_probe.scissorRect.unionWith(ps.rect);
    }
}

fn setEnvprobeDefViewEnvprobe(probe: *RenderEnvprobeLocal) *ViewEnvprobe {
    const view_count: c_int = @intCast(RenderSystem.instance.viewCount());
    if (probe.viewCount == view_count)
        return probe.viewEnvprobe.?;

    probe.viewCount = view_count;
    var v_probe = FrameData.frameCreate(ViewEnvprobe);
    v_probe.envprobeDef = probe;
    v_probe.scissorRect.clear();
    v_probe.globalOrigin = probe.parms.origin;
    v_probe.globalProbeBounds = probe.globalProbeBounds;
    v_probe.inverseBaseProbeProject = probe.inverseBaseProbeProject;
    v_probe.irradianceImage = probe.irradianceImage;
    v_probe.radianceImage = probe.radianceImage;

    const view_def = RenderSystem.instance.getView() orelse unreachable;
    v_probe.next = view_def.viewEnvprobes;
    view_def.viewEnvprobes = v_probe;
    probe.viewEnvprobe = v_probe;

    return v_probe;
}

fn buildConnectedAreas(render_world: *RenderWorld, view_def: *ViewDef) void {
    const connected_areas = FrameData.frameAlloc(bool, render_world.portal_areas.?.len);
    @memset(connected_areas, false);
    view_def.connectedAreas = connected_areas.ptr;

    if (view_def.areaNum == -1) {
        @memset(connected_areas, true);
        return;
    }

    render_world.buildConnectedAreas_r(view_def, view_def.areaNum);
}

const PS_BLOCK_VIEW: c_int = 1;

fn buildConnectedAreas_r(render_world: *RenderWorld, view_def: *ViewDef, area_num: c_int) void {
    const connected_state = &view_def.connectedAreas.?[@intCast(area_num)];

    if (connected_state.*) return;

    connected_state.* = true;

    var opt_portal: ?*Portal = render_world.portal_areas.?[@intCast(area_num)].portals;
    while (opt_portal) |portal| : (opt_portal = portal.next) {
        if ((portal.doublePortal.?.blockingBits & PS_BLOCK_VIEW) == 0) {
            render_world.buildConnectedAreas_r(view_def, portal.intoArea);
        }
    }
}

pub fn updateEntityDef(
    render_world: *RenderWorld,
    entity_index: usize,
    render_entity: RenderEntity,
) !void {
    if (render_entity.hModel == null and render_entity.callback == null)
        return error.NoModel;

    // TODO: entity_index > MAX_ENTITY_DEFS_INDEX(10000)

    // create new slots if needed
    while (entity_index >= render_world.entity_defs.items.len)
        try render_world.entity_defs.append(null);

    var def = if (render_world.entity_defs.items[entity_index]) |entity_def| def: {
        if (!(render_entity.forceUpdate == 1)) {
            // check for exact match (OPTIMIZE: check through pointers more)
            if (render_entity.joints == null and
                render_entity.callbackData == null and
                entity_def.dynamicModel == null and
                std.mem.eql(u8, std.mem.asBytes(&entity_def.parms), std.mem.asBytes(&render_entity)))
                return;

            // if the only thing that changed was shaderparms, we can just leave things as they are
            // after updating parms

            // if we have a callback function and the bounds, origin, axis and model match,
            // then we can leave the references as they are
            if (render_entity.callback != null) {
                const axis_match = render_entity.axis.toMat3f().eql(entity_def.parms.axis.toMat3f());
                const origin_match = render_entity.origin.toVec3f().eql(entity_def.parms.origin.toVec3f());
                const bounds_match = render_entity.bounds.toBounds().eql(entity_def.localReferenceBounds.toBounds());
                const model_match = render_entity.hModel == entity_def.parms.hModel;

                if (bounds_match and origin_match and axis_match and model_match) {
                    // only clear the dynamic model and interaction surfaces if they exist
                    entity_def.clearEntityDynamicModel();
                    entity_def.parms = render_entity;
                    return;
                }
            }
        }

        if (entity_def.parms.hModel == render_entity.hModel)
            entity_def.freeEntityDerivedData(true, true)
        else
            entity_def.freeEntityDerivedData(false, false);

        break :def entity_def;
    } else def: {
        // creating a new one
        var entity_def = try render_world.allocator.create(RenderEntityLocal);
        entity_def.* = RenderEntityLocal{};
        render_world.entity_defs.items[entity_index] = entity_def;

        entity_def.index = @intCast(entity_index);
        entity_def.world = render_world;
        break :def entity_def;
    };

    def.parms = render_entity;
    def.lastModifiedFrameNum = @intCast(RenderSystem.instance.frameCount());

    // optionally immediately issue any callbacks
    const r_use_entity_callbacks = false; // TODO: CVar system
    if (!r_use_entity_callbacks and def.parms.callback != null) {
        const view_def = RenderSystem.instance.getView();
        _ = def.issueEntityDefCallback(view_def);
    }

    // trigger entities don't need to get linked in and processed,
    // they only exist for editor use
    if (def.parms.hModel) |model_ptr| {
        if (!model_ptr.hasDrawingSurfaces()) return;
    }

    // based on the model bounds, add references in each area
    // that may contain the updated surface
    try def.createEntityRefs();
}

pub fn pushFrustumIntoTree(
    render_world: *RenderWorld,
    def: ?*RenderEntityLocal,
    light: ?*RenderLightLocal,
    frustumTransform: RenderMatrix,
    frustumBounds: Bounds,
) !void {
    // TODO: properly check
    const area_nodes = render_world.area_nodes orelse return;
    const portal_areas = render_world.portal_areas orelse return;

    // calculate the corners of the frustum in world space
    const corners = RenderMatrix.getFrustumCorners(frustumTransform, CBounds.fromBounds(frustumBounds));

    try render_world.pushFrustumIntoTree_r(
        def,
        light,
        corners,
        0,
        area_nodes,
        portal_areas,
    );
}

/// Used for both light volumes and model volumes.
/// This does not clip the points by the planes, so some slop
/// occurs.
/// tr.viewCount should be bumped before calling, allowing it
/// to prevent double checking areas.
/// We might alternatively choose to do this with an area flow.
fn pushFrustumIntoTree_r(
    render_world: *RenderWorld,
    def: ?*RenderEntityLocal,
    light: ?*RenderLightLocal,
    corners: FrustumCorners,
    node_num: c_int,
    area_nodes: []AreaNode,
    portal_areas: []PortalArea,
) !void {
    if (node_num < 0) {
        const area_num: usize = @intCast(-1 - node_num);
        var area = &portal_areas[area_num];

        // already added a reference here
        if (area.viewCount == RenderSystem.instance.viewCount()) return;

        area.viewCount = @intCast(RenderSystem.instance.viewCount());

        if (def) |render_entity|
            try render_world.addEntityRefToArea(render_entity, area);

        if (light) |render_light|
            try render_world.addLightRefToArea(render_light, area);

        return;
    }

    const node = area_nodes[@intCast(node_num)];

    const r_use_node_common_children = true;

    // if we know that all possible children nodes only touch an area
    // we have already marked, we can early out
    if (node.commonChildrenArea != AreaNode.CHILDREN_HAVE_MULTIPLE_AREAS and
        r_use_node_common_children)
    {
        // note that we do NOT try to set a reference in this area
        // yet, because the test volume may yet wind up being in the
        // solid part, which would cause bounds slightly poked into
        // a wall to show up in the next room
        if (portal_areas[@intCast(node.commonChildrenArea)].viewCount == RenderSystem.instance.viewCount())
            return;
    }

    // exact check all the corners against the node plane
    const cull = RenderMatrix.cullFrustumCornersToPlane(corners, node.plane);

    if (cull != FrustumCull.BACK) {
        const node_num_ = node.children[0];
        if (node_num_ != 0) // 0 = solid
            try render_world.pushFrustumIntoTree_r(
                def,
                light,
                corners,
                node_num_,
                area_nodes,
                portal_areas,
            );
    }

    if (cull != FrustumCull.FRONT) {
        const node_num_ = node.children[1];
        if (node_num_ != 0) // 0 = solid
            try render_world.pushFrustumIntoTree_r(
                def,
                light,
                corners,
                node_num_,
                area_nodes,
                portal_areas,
            );
    }
}

pub fn pushEnvprobeIntoTree_r(
    render_world: *RenderWorld,
    opt_def: ?*RenderEnvprobeLocal,
    node_num: c_int,
    area_nodes: []AreaNode,
    portal_areas: []PortalArea,
) !void {
    if (node_num < 0) {
        const area_num: usize = @intCast(-1 - node_num);
        var area = &portal_areas[area_num];

        // already added a reference here
        if (area.viewCount == RenderSystem.instance.viewCount()) return;

        area.viewCount = @intCast(RenderSystem.instance.viewCount());

        if (opt_def) |render_entity|
            try render_world.addEnvprobeRefToArea(render_entity, area);

        return;
    }

    const node = area_nodes[@intCast(node_num)];

    const r_use_node_common_children = true;

    // if we know that all possible children nodes only touch an area
    // we have already marked, we can early out
    if (node.commonChildrenArea != AreaNode.CHILDREN_HAVE_MULTIPLE_AREAS and
        r_use_node_common_children)
    {
        // note that we do NOT try to set a reference in this area
        // yet, because the test volume may yet wind up being in the
        // solid part, which would cause bounds slightly poked into
        // a wall to show up in the next room
        if (portal_areas[@intCast(node.commonChildrenArea)].viewCount == RenderSystem.instance.viewCount())
            return;
    }

    const def = opt_def orelse return;
    const cull = node.plane.side(def.parms.origin.toVec3f());

    if (cull != .back) {
        const node_num_ = node.children[0];
        if (node_num_ != 0) // 0 = solid
            try render_world.pushEnvprobeIntoTree_r(
                def,
                node_num_,
                area_nodes,
                portal_areas,
            );
    }

    if (cull != .front) {
        const node_num_ = node.children[1];
        if (node_num_ != 0) // 0 = solid
            try render_world.pushEnvprobeIntoTree_r(
                def,
                node_num_,
                area_nodes,
                portal_areas,
            );
    }
}

pub const AreaAccessError = error{
    BadAreaIndex,
    NotInitialized,
};

pub const GetPortalError = error{
    BadPortalIndex,
    NoDoublePortal,
    DoublePortalHandleNotFound,
} || AreaAccessError;

pub fn getPortal(render_world: RenderWorld, area_num: usize, portal_num: usize) GetPortalError!ExitPortal {
    const portal_areas = render_world.portal_areas orelse return error.NotInitialized;
    const double_portals = render_world.double_portals orelse return error.NotInitialized;
    if (area_num >= portal_areas.len) return error.BadAreaIndex;

    const area = &portal_areas[area_num];
    var count: usize = 0;
    var opt_portal: ?*Portal = area.portals;
    var ret: ExitPortal = std.mem.zeroes(ExitPortal);

    while (opt_portal) |portal| : (opt_portal = portal.next) {
        if (count == portal_num) {
            ret.areas[0] = @intCast(area_num);
            ret.areas[1] = portal.intoArea;
            ret.w = portal.w;

            const double_portal = portal.doublePortal orelse return error.NoDoublePortal;
            ret.blockingBits = double_portal.blockingBits;
            for (double_portals, 0..) |*double_portal_ptr, i| {
                if (double_portal_ptr == double_portal) {
                    ret.portalHandle = @intCast(i);
                    break;
                }
            } else return error.DoublePortalHandleNotFound;
            return ret;
        }
        count += 1;
    }

    return error.BadPortalIndex;
}

pub const PointInAreaError = error{
    AreaNotFound,
    PointNotInArea,
    NotInitialized,
    AreaOutOfRange,
};

/// Will return -1 if the point is not in an area, otherwise
/// it will return 0 <= value < tr.world->numPortalAreas
pub fn pointInArea(render_world: RenderWorld, point: Vec3(f32)) PointInAreaError!usize {
    return if (render_world.area_nodes) |area_nodes| index: {
        var node_num: usize = 0;
        var node = &area_nodes[node_num];
        break :index while (true) : (node = &area_nodes[node_num]) {
            const normal = Vec3(f32){ .v = .{ node.plane.a, node.plane.b, node.plane.c } };
            const d = point.dot(normal) + node.plane.d;

            const node_num_ = if (d > 0) node.children[0] else node.children[1];

            if (node_num_ == 0) break error.PointNotInArea; // in solid

            if (node_num_ < 0) {
                node_num = @intCast(-1 - node_num_);
                if (node_num >= area_nodes.len) break error.AreaOutOfRange;

                break node_num;
            }

            node_num = @intCast(node_num_);
        } else error.AreaNotFound;
    } else error.NotInitialized;
}

pub fn boundsInAreas(render_world: RenderWorld, bounds: Bounds, areas: []c_int) usize {
    // TODO: assert
    const area_nodes = render_world.area_nodes orelse return 0;

    var num_areas: usize = 0;
    boundsInAreas_r(0, bounds, areas, &num_areas, area_nodes);

    return num_areas;
}

pub fn boundsInAreas_r(
    arg_node_num: c_int,
    bounds: Bounds,
    areas: []c_int,
    num_areas: *usize,
    area_nodes: []AreaNode,
) void {
    var node_num = arg_node_num;

    var first_iteration = true;
    while (first_iteration or node_num != 0) {
        defer first_iteration = false;

        if (node_num < 0) {
            node_num = -1 - node_num;
            const max = num_areas.*;
            const i = for (0..max) |n| {
                if (areas[n] == node_num) break n;
            } else max;

            if (i >= max and max < areas.len) {
                num_areas.* += 1;
                areas[num_areas.*] = node_num;
            }

            return;
        }

        const node = &area_nodes[@intCast(node_num)];
        switch (bounds.planeSide(node.plane)) {
            .front => node_num = node.children[0],
            .back => node_num = node.children[1],
            else => {
                if (node.children[1] != 0) {
                    boundsInAreas_r(
                        node.children[1],
                        bounds,
                        areas,
                        num_areas,
                        area_nodes,
                    );

                    if (num_areas.* >= areas.len) return;
                }
                node_num = node.children[0];
            },
        }
    }
}

pub fn areaBounds(render_world: RenderWorld, area_num: usize) !Bounds {
    return if (render_world.portal_areas) |portal_areas| bounds: {
        if (area_num >= portal_areas.len) return error.AreaOutOfRange;

        break :bounds portal_areas[area_num].globalBounds.toBounds();
    } else error.NotInitialized;
}

pub fn areasAreConnected(render_world: RenderWorld, area_a: usize, area_b: usize, connection: c_int) !bool {
    return if (render_world.portal_areas) |portal_areas| connected: {
        if (area_a >= portal_areas.len or area_b >= portal_areas.len)
            break :connected error.AreaOutOfRange;

        var attribute: c_int = 0;
        var int_connection = connection;

        while (int_connection > 1) {
            attribute += 1;
            int_connection >>= 1;
        }

        const attribute_mask = @as(c_int, 1) << @intCast(attribute);
        if (attribute >= NUM_PORTAL_ATTRIBUTES or attribute_mask != connection)
            break :connected error.BadConnectionNumber;

        const num_a = portal_areas[area_a].connectedAreaNum[@intCast(attribute)];
        const num_b = portal_areas[area_b].connectedAreaNum[@intCast(attribute)];

        break :connected num_a == num_b;
    } else error.NotInitialized;
}

pub fn numPortalsInArea(render_world: RenderWorld, area_index: usize) AreaAccessError!usize {
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
        .local_models = std.ArrayList(*model.RenderModel).init(allocator),
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

    if (render_world.interaction_table) |table| {
        render_world.allocator.free(table);
        render_world.interaction_table = null;
    }

    for (render_world.light_defs.items, 0..) |*item, index| {
        if (item.*) |item_ptr| {
            render_world.freeLightDef(item_ptr, index);
        }
    }

    for (render_world.envprobe_defs.items, 0..) |*item, index| {
        if (item.*) |item_ptr| {
            render_world.freeEnvprobeDef(item_ptr, index);
        }
    }

    for (render_world.entity_defs.items, 0..) |*item, index| {
        if (item.*) |item_ptr| {
            render_world.freeEntityDef(item_ptr, index);
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

fn freeInteractions(render_world: *RenderWorld) void {
    for (render_world.entity_defs.items) |opt_item_ptr| {
        const item_ptr = opt_item_ptr orelse continue;
        while (item_ptr.firstInteraction) |inter| {
            inter.unlinkAndFree(render_world.allocator);
        }
    }
}

pub fn freeWorld(render_world: *RenderWorld) void {
    render_world.freeInteractions();
    render_world.freeDefs();

    // free all the portals and check light/model references

    if (render_world.portal_areas) |portal_areas| {
        for (portal_areas) |*area| {
            var opt_portal: ?*Portal = area.portals;
            var opt_next_portal: ?*Portal = null;
            while (opt_portal) |portal| : (opt_portal = opt_next_portal) {
                opt_next_portal = portal.next;
                portal.w.destroy();
                render_world.allocator.destroy(portal);
            }

            // TODO:
            // area.lightGrid.lightGridPoints.clear();

            // there shouldn't be any remaining lightRefs or entityRefs
            if (area.lightRefs.areaNext != &area.lightRefs)
                @panic("freeWorld: unexpected remaining lightRefs");

            if (area.entityRefs.areaNext != &area.entityRefs)
                @panic("freeWorld: unexpected remaining entityRefs");
        }

        render_world.allocator.free(portal_areas);
        render_world.portal_areas = null;
    }

    if (render_world.area_screen_rect) |area_screen_rect| {
        render_world.allocator.free(area_screen_rect);
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

    for (render_world.local_models.items) |item| {
        RenderModelManager.instance.removeModel(item);
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

    const screen_rects = try render_world.allocator.alloc(ScreenRect, 1);
    errdefer render_world.allocator.free(screen_rects);
    screen_rects[0] = std.mem.zeroes(ScreenRect);

    render_world.area_screen_rect = screen_rects;

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
                RenderModelManager.instance.addModel(render_model);

                // save it in the list to free when clearing this map
                try render_world.local_models.append(render_model);
                numEntries += 1;
                continue;
            }

            if (std.mem.eql(u8, token.slice(), "shadowModel")) {
                _ = try render_world.parseShadowModel(&lexer);
                //const last_model = render_world.parseShadowModel(&lexer);
                // add it to the model manager list
                //global.renderModelManager.addModel(last_model);

                // save it in the list to free when clearing this map
                //render_world.local_models.append(last_model);
                numEntries += 1;
                continue;
            }

            if (std.mem.eql(u8, token.slice(), "interAreaPortals")) {
                try render_world.parseInterAreaPortals(&lexer);
                numEntries += 1;
                continue;
            }

            if (std.mem.eql(u8, token.slice(), "nodes")) {
                try render_world.parseNodes(&lexer);
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
        def.world = render_world;

        const model_name = try std.fmt.allocPrintZ(string_allocator, "_area{d}", .{area_index});
        const model_ptr = try RenderModelManager.instance.findModel(model_name);
        def.parms.hModel = model_ptr;

        if (model_ptr.isDefaultModel() or !model_ptr.isStaticWorldModel())
            return error.BadModel;

        // TODO: set needsPortalSky if model shader name matches "textures/smf/portal_sky"

        // the local and global reference bounds are the same for area models
        def.localReferenceBounds = model_ptr.bounds();
        def.globalReferenceBounds = model_ptr.bounds();

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

pub fn addEnvprobeRefToArea(
    render_world: *RenderWorld,
    def: *RenderEnvprobeLocal,
    area: *PortalArea,
) error{OutOfMemory}!void {
    {
        var opt_ref = def.references;
        while (opt_ref) |ref| : (opt_ref = ref.ownerNext) {
            if (ref.area == area) return;
        }
    }

    var ref = try render_world.area_reference_allocator.create();
    ref.* = AreaReference{};
    ref.envprobe = def;
    ref.area = area;
    ref.ownerNext = def.references;
    def.references = ref;

    area.envprobeRefs.areaNext.?.areaPrev = ref;
    ref.areaNext = area.envprobeRefs.areaNext;
    ref.areaPrev = &area.envprobeRefs;
    area.envprobeRefs.areaNext = ref;
}

pub fn addLightRefToArea(
    render_world: *RenderWorld,
    def: *RenderLightLocal,
    area: *PortalArea,
) error{OutOfMemory}!void {
    {
        var opt_ref = def.references;
        while (opt_ref) |ref| : (opt_ref = ref.ownerNext) {
            if (ref.area == area) return;
        }
    }

    var ref = try render_world.area_reference_allocator.create();
    ref.* = AreaReference{};
    ref.light = def;
    ref.area = area;
    ref.ownerNext = def.references;
    def.references = ref;

    area.lightRefs.areaNext.?.areaPrev = ref;
    ref.areaNext = area.lightRefs.areaNext;
    ref.areaPrev = &area.lightRefs;
    area.lightRefs.areaNext = ref;
}

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

fn parseModel(render_world: *RenderWorld, lexer: *Lexer) !*model.RenderModel {
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

fn parseNodes(render_world: *RenderWorld, lexer: *Lexer) !void {
    try lexer.expectTokenString("{");
    const num_area_nodes = try lexer.parseSize();

    const area_nodes = try render_world.allocator.alloc(AreaNode, num_area_nodes);
    errdefer render_world.allocator.free(area_nodes);
    for (area_nodes) |*node| {
        node.* = std.mem.zeroes(AreaNode);
    }

    render_world.area_nodes = area_nodes;

    for (area_nodes) |*node| {
        var vec = std.mem.zeroes([4]f32);
        try lexer.parse1DMatrix(&vec);

        node.plane = Plane.fromSlice(&vec);
        node.children[0] = try lexer.parseInt();
        node.children[1] = try lexer.parseInt();
    }
    try lexer.expectTokenString("}");
}

fn parseInterAreaPortals(render_world: *RenderWorld, lexer: *Lexer) !void {
    try lexer.expectTokenString("{");
    const num_portal_areas = try lexer.parseSize();
    const num_inter_area_portals = try lexer.parseSize();

    const portal_areas = try render_world.allocator.alloc(PortalArea, num_portal_areas);
    errdefer render_world.allocator.free(portal_areas);
    for (portal_areas) |*area| {
        area.* = std.mem.zeroes(PortalArea);
    }

    render_world.portal_areas = portal_areas;

    const screen_rects = try render_world.allocator.alloc(ScreenRect, num_portal_areas);
    errdefer render_world.allocator.free(screen_rects);
    for (screen_rects) |*rect| {
        rect.* = std.mem.zeroes(ScreenRect);
    }

    render_world.area_screen_rect = screen_rects;

    render_world.setupAreaRefs(portal_areas);

    const double_portals = try render_world.allocator.alloc(DoublePortal, num_inter_area_portals);
    errdefer render_world.allocator.free(double_portals);
    for (double_portals) |*portal| {
        portal.* = std.mem.zeroes(DoublePortal);
    }

    render_world.double_portals = double_portals;

    for (0..num_inter_area_portals) |i| {
        const num_points = try lexer.parseSize();
        const a1 = try lexer.parseSize();
        const a2 = try lexer.parseSize();

        const w = CWinding.create(num_points);
        w.setNumPoints(num_points);

        for (0..num_points) |j| {
            const vec = @as([*]f32, @ptrCast(&w.p[j]))[0..3];
            try lexer.parse1DMatrix(vec);
        }

        const p1 = try render_world.allocator.create(Portal);
        errdefer render_world.allocator.destroy(p1);
        p1.intoArea = @intCast(a2);
        p1.doublePortal = &double_portals[i];
        p1.w = w;
        p1.plane = w.getPlane();
        p1.next = portal_areas[a1].portals;
        portal_areas[a1].portals = p1;
        double_portals[i].portals[0] = p1;

        const p2 = try render_world.allocator.create(Portal);
        errdefer render_world.allocator.destroy(p2);
        p2.intoArea = @intCast(a1);
        p2.doublePortal = &double_portals[i];
        p2.w = w.reverse();
        p2.plane = w.getPlane();
        p2.next = portal_areas[a2].portals;
        portal_areas[a2].portals = p2;
        double_portals[i].portals[1] = p2;
    }

    try lexer.expectTokenString("}");
}

fn parseShadowModel(_: *RenderWorld, lexer: *Lexer) !?*model.RenderModel {
    // TODO
    try lexer.expectTokenString("{");

    // reusable token
    var token = Token.init();
    defer token.deinit();

    // model name
    try lexer.expectAnyToken(&token);
    const num_verts = try lexer.parseSize(); // numVerts
    _ = try lexer.parseSize();
    _ = try lexer.parseSize();
    const num_indexes = try lexer.parseSize(); // numIndexes
    _ = try lexer.parseSize();

    for (0..num_verts) |_| {
        var vec = std.mem.zeroes([3]f32);
        try lexer.parse1DMatrix(&vec);
    }

    for (0..num_indexes) |_| {
        _ = try lexer.parseSize();
    }

    try lexer.expectTokenString("}");

    return null;
}

/// Game code uses this to identify which portals are inside doors.
/// Returns 0 if no portal contacts the bounds
pub fn findPortal(render_world: RenderWorld, b: Bounds) usize {
    const double_portals =
        render_world.double_portals orelse return 0;

    var wb = Bounds.zero;
    for (double_portals, 0..) |*portal, i| {
        const w = portal.portals[0].w;
        wb.clear();

        for (0..@intCast(w.numPoints)) |j| {
            _ = wb.addPoint(w.getVec3Point(j).toVec3f());
        }

        if (wb.intersectsBounds(b)) return i + 1;
    }

    return 0;
}

pub fn setPortalState(render_world: *RenderWorld, portal_index: usize, block_types: c_int) void {
    if (portal_index == 0) return;
    const double_portals = render_world.double_portals orelse @panic("double_portals not initialized!");
    const portal_areas = render_world.portal_areas orelse @panic("portal_areas not initialized!");

    const old_state = double_portals[portal_index - 1].blockingBits;
    if (old_state == block_types) return;
    double_portals[portal_index - 1].blockingBits = block_types;

    // leave the connectedAreaGroup the same on one side,
    // then flood fill from the other side with a new number for each changed attribute
    for (0..NUM_PORTAL_ATTRIBUTES) |i| {
        const attribute_mask = @as(c_int, 1) << @intCast(i);
        if (((old_state ^ block_types) & attribute_mask) != 0) {
            render_world.connected_area_num += 1;
            const portal = double_portals[portal_index - 1].portals[1];
            render_world.floodConnectedAreas(
                portal_areas,
                &portal_areas[@intCast(portal.intoArea)],
                i,
            );
        }
    }
}

pub fn getPortalState(render_world: *RenderWorld, portal_index: usize) c_int {
    if (portal_index == 0) return 0;

    return if (render_world.double_portals) |double_portals|
        double_portals[portal_index - 1].blockingBits
    else
        0;
}

const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;

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

    const opt_material_ptr = global.DeclManager.findMaterial(meterial_name);
    if (opt_material_ptr) |material_ptr| material_ptr.addReference();

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

    const verts = try surface_triangles.allocVertices(render_world.allocator, num_vertices);
    for (0..num_vertices) |i| {
        verts[i].xyz.x = vertices[i * 8 + 0];
        verts[i].xyz.y = vertices[i * 8 + 1];
        verts[i].xyz.z = vertices[i * 8 + 2];
        verts[i].setTexCoord(vertices[i * 8 + 3], vertices[i * 8 + 4]);
        verts[i].setNormal(vertices[i * 8 + 5], vertices[i * 8 + 6], vertices[i * 8 + 7]);
    }

    const indexes = try surface_triangles.allocIndexes(render_world.allocator, indices.len);
    for (indexes, indices) |*surface_index, index| {
        surface_index.* = index;
    }

    return surface;
}

pub fn destroyModelSurface(render_world: *RenderWorld, model_surface: *model.ModelSurface) void {
    const geometry = if (model_surface.geometry) |tris| tris else return;

    geometry.deinit(render_world.allocator);
    model_surface.geometry = null;
}
