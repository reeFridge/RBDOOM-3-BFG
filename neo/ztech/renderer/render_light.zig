const std = @import("std");
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const material = @import("material.zig");
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Bounds = @import("../bounding_volume/bounds.zig");
const RenderSystem = @import("render_system.zig");
const Image = @import("image.zig").Image;
const ViewLight = @import("common.zig").ViewLight;

pub const RenderLight = extern struct {
    axis: CMat3 = .{},
    origin: CVec3 = .{},
    suppressLightInViewID: c_int = 0,
    allowLightInViewID: c_int = 0,
    forceShadows: bool = false,
    noShadows: bool = false,
    noSpecular: bool = false,
    pointLight: bool = false,
    parallel: bool = false,
    lightRadius: CVec3 = .{},
    lightCenter: CVec3 = .{},
    target: CVec3 = .{},
    right: CVec3 = .{},
    up: CVec3 = .{},
    start: CVec3 = .{},
    end: CVec3 = .{},
    lightId: c_int = 0,
    shader: ?*Material = null,
    shaderParms: [material.MAX_GLOBAL_SHADER_PARMS]f32 = std.mem.zeroes([material.MAX_GLOBAL_SHADER_PARMS]f32),
    referenceSound: ?*anyopaque = null,

    extern fn c_parseSpawnArgsToRenderLight(*anyopaque, *RenderLight) callconv(.C) void;
    pub fn initFromSpawnArgs(self: *RenderLight, dict: *anyopaque) void {
        c_parseSpawnArgsToRenderLight(dict, self);
    }
};

const RenderWorld = @import("render_world.zig");
const Plane = @import("../math/plane.zig").Plane;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;
const DoublePortal = @import("render_world.zig").DoublePortal;
const MaterialFlags = @import("material.zig").Flags;
const Material = @import("material.zig").Material;
const CWinding = @import("../geometry/winding.zig").CWinding;

pub const RenderLightLocal = extern struct {
    _vptr: *anyopaque = undefined,
    // specification
    parms: RenderLight = .{},
    // the light has changed its position since it was
    // first added, so the prelight model is not valid
    lightHasMoved: bool = false,
    world: ?*RenderWorld = null,
    // in world lightDefs
    index: c_int = 0,
    // if not -1, we may be able to cull all the light's
    // interactions if !viewDef->connectedAreas[areaNum]
    areaNum: c_int = 0,
    // to determine if it is constantly changing,
    // and should go in the dynamic frame memory, or kept
    // in the cached memory
    lastModifiedFrameNum: c_int = 0,
    // for demo writing
    archived: bool = false,

    // derived information
    // old style light projection where Z and W are flipped and projected lights lightProject[3] is divided by ( zNear + zFar )
    lightProject: [4]Plane = std.mem.zeroes([4]Plane),
    // global xyz1 to projected light strq
    baseLightProject: RenderMatrix = std.mem.zeroes(RenderMatrix),
    // transforms the zero-to-one cube to exactly cover the light in world space
    inverseBaseLightProject: RenderMatrix = std.mem.zeroes(RenderMatrix),
    // guaranteed to be valid, even if parms.shader isn't
    lightShader: ?*const Material = null,
    falloffImage: ?*Image = null,
    // accounting for lightCenter and parallel
    globalLightOrigin: CVec3 = std.mem.zeroes(CVec3),
    globalLightBounds: CBounds = std.mem.zeroes(CBounds),
    // if == tr.viewCount, the light is on the viewDef->viewLights list
    viewCount: c_int = 0,
    viewLight: ?*ViewLight = null, // viewLight_t
    // each area the light is present in will have a lightRef
    references: ?*AreaReference = null,
    // doubly linked list
    firstInteraction: ?*Interaction = null,
    lastInteraction: ?*Interaction = null,
    foggedPortals: ?*DoublePortal = null,

    extern fn R_DeriveLightData(*RenderLightLocal) void;
    pub fn deriveLightData(light: *RenderLightLocal) void {
        // TODO
        R_DeriveLightData(light);
    }

    // Frees all references and lit surfaces from the light
    pub fn freeLightDerivedData(light: *RenderLightLocal) void {
        const world = light.world orelse return;

        // remove any portal fog references
        var opt_dp = light.foggedPortals;
        while (opt_dp) |dp| : (opt_dp = dp.nextFoggedPortal) {
            dp.fogLight = null;
        }

        // free all the interactions
        while (light.firstInteraction) |inter| {
            inter.unlinkAndFree(world.allocator);
        }

        // free all the references to the light
        var opt_next_ref: ?*AreaReference = null;
        var opt_light_ref = light.references;
        while (opt_light_ref) |light_ref| : (opt_light_ref = opt_next_ref) {
            opt_next_ref = light_ref.ownerNext;

            // unlink from the area
            light_ref.areaNext.?.areaPrev = light_ref.areaPrev;
            light_ref.areaPrev.?.areaNext = light_ref.areaNext;

            // put it back on the free list for reuse
            world.area_reference_allocator.destroy(light_ref);
        }

        light.references = null;
    }

    pub fn createLightRefs(light: *RenderLightLocal) !void {
        light.deriveLightData();

        const world = light.world orelse return;

        // cull the light if it is behind a closed door
        // it is debatable if we want to use the entity origin or the center offset origin,
        // but we definitely don't want to use a parallel offset origin
        if (world.pointInArea(light.globalLightOrigin.toVec3f())) |area_num| {
            light.areaNum = @intCast(area_num);
        } else |_| {
            if (world.pointInArea(light.parms.origin.toVec3f())) |area_num| {
                light.areaNum = @intCast(area_num);
            } else |_| {
                light.areaNum = -1;
            }
        }

        // bump the view count so we can tell if an
        // area already has a reference
        RenderSystem.instance.incViewCount();

        // push the light frustum down the BSP tree into areas
        try world.pushFrustumIntoTree(
            null,
            light,
            light.inverseBaseLightProject,
            Bounds.zero_one_cube,
        );

        light.createLightFogPortals();
    }

    // When a fog light is created or moved, see if it completely
    // encloses any portals, which may allow them to be fogged closed.
    fn createLightFogPortals(light: *RenderLightLocal) void {
        light.foggedPortals = null;

        if (light.lightShader) |shader| {
            if (shader.isFogLight() or shader.testMaterialFlag(MaterialFlags.MF_NOPORTALFOG))
                return;
        }

        var opt_light_ref = light.references;
        while (opt_light_ref) |light_ref| : (opt_light_ref = light_ref.ownerNext) {
            const area = light_ref.area orelse continue;
            var opt_portal = area.portals;
            while (opt_portal) |portal| : (opt_portal = portal.next) {
                var dp = portal.doublePortal orelse continue;

                // we only handle a single fog volume covering a portal
                // this will never cause incorrect drawing, but it may
                // fail to cull a portal
                if (dp.fogLight == null or
                    windingCompletelyInsideLight(portal.w.*, light.*))
                    continue;

                dp.fogLight = light;
                dp.nextFoggedPortal = light.foggedPortals;
                light.foggedPortals = dp;
            }
        }
    }
};

fn windingCompletelyInsideLight(w: CWinding, light: RenderLightLocal) bool {
    for (0..@intCast(w.numPoints)) |i| {
        if (light.baseLightProject.cullPointToMVP(w.getVec3Point(i), true))
            return false;
    }

    return true;
}
