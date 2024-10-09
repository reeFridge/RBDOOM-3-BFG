const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const render_entity = @import("render_entity.zig");
const RenderWorld = @import("render_world.zig");
const RenderSystem = @import("render_system.zig");
const ViewEnvprobe = @import("common.zig").ViewEnvprobe;

pub const RenderEnvironmentProbe = extern struct {
    origin: CVec3,
    shaderParms: [render_entity.MAX_ENTITY_SHADER_PARAMS]f32,

    // if non-zero, the environment probe will not show up in the specific view,
    // which may be used if we want to have slightly different muzzle
    // flash lights for the player and other views
    suppressEnvprobeInViewID: c_int,
    // if non-zero, the environment probe will only show up in the specific view
    // which can allow player gun gui lights and such to not effect everyone
    allowEnvprobeInViewID: c_int,
};

const RenderMatrix = @import("matrix.zig").RenderMatrix;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;
const Image = @import("image.zig").Image;

pub const RenderEnvprobeLocal = extern struct {
    _vptr: *anyopaque = undefined,
    // specification
    parms: RenderEnvironmentProbe,
    // the envprobe has changed its position since it was
    // first added, so the preenvprobe model is not valid
    envprobeHasMoved: bool,
    world: ?*RenderWorld,
    // in world envprobeDefs
    index: c_int,
    // if not -1, we may be able to cull all the light's
    // interactions if !viewDef->connectedAreas[areaNum]
    areaNum: c_int,
    // to determine if it is constantly changing,
    // and should go in the dynamic frame memory, or kept
    // in the cached memory
    lastModifiedFrameNum: c_int,
    // for demo writing
    archived: bool,

    // derived information
    // transforms the zero-to-one cube to exactly cover the light in world space
    inverseBaseProbeProject: RenderMatrix,
    globalProbeBounds: CBounds,
    // each area the light is present in will have a envprobeRef
    references: ?*AreaReference,
    // cubemap image used for diffuse IBL by backend
    irradianceImage: ?*Image,
    // cubemap image used for specular IBL by backend
    radianceImage: ?*Image,
    // if == tr.viewCount, the envprobe is on the viewDef->viewEnvprobes list
    viewCount: c_int,
    viewEnvprobe: ?*ViewEnvprobe,

    extern fn R_DeriveEnvprobeData2(*RenderEnvprobeLocal, [*]const u8, c_int) callconv(.C) void;

    fn deriveData(probe: *RenderEnvprobeLocal) !void {
        const render_world = probe.world orelse return;

        // determine the areaNum for the envprobe origin, which may let us
        // cull the envprobe if it is behind a closed door
        if (probe.areaNum != -1) {
            // HACK: this should be in the gamecode and set by the entity properties
            const bounds = try render_world.areaBounds(@intCast(probe.areaNum));
            probe.globalProbeBounds = CBounds.fromBounds(bounds);
        } else {
            var bounds = probe.globalProbeBounds.toBounds();
            bounds.clear();
            probe.globalProbeBounds = CBounds.fromBounds(bounds);
        }

        R_DeriveEnvprobeData2(probe, render_world.map_name.ptr, probe.areaNum);
    }

    pub fn createRefs(probe: *RenderEnvprobeLocal) !void {
        const render_world = probe.world orelse return;
        const area_nodes = render_world.area_nodes orelse return;
        const portal_areas = render_world.portal_areas orelse return;

        if (render_world.pointInArea(probe.parms.origin.toVec3f())) |area_num| {
            probe.areaNum = @intCast(area_num);
        } else |_| {
            probe.areaNum = -1;
        }

        try probe.deriveData();

        RenderSystem.instance.incViewCount();
        try render_world.pushEnvprobeIntoTree_r(probe, 0, area_nodes, portal_areas);
    }

    pub fn freeDerivedData(probe: *RenderEnvprobeLocal) void {
        const render_world = probe.world orelse return;

        var opt_ref = probe.references;
        var next: ?*AreaReference = null;
        while (opt_ref) |ref| : (opt_ref = next) {
            next = ref.ownerNext;

            ref.areaNext.?.areaPrev = ref.areaPrev;
            ref.areaPrev.?.areaNext = ref.areaNext;

            render_world.area_reference_allocator.destroy(ref);
        }

        probe.references = null;
    }
};
