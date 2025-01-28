const std = @import("std");
const decl_manager = @import("../framework/decl_manager.zig");
const common = @import("../entity_types/common.zig");
const idlib = @import("../idlib.zig");
const CVec3 = @import("../math/vector.zig").CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const material = @import("material.zig");
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Bounds = @import("../bounding_volume/bounds.zig");
const RenderSystem = @import("render_system.zig");
const Image = @import("image.zig").Image;
const ViewLight = @import("common.zig").ViewLight;
const Allocator = std.mem.Allocator;

pub const RenderLight = extern struct {
    axis: CMat3 = CMat3.fromMat3f(Mat3(f32).identity()),
    origin: CVec3 = .{},
    suppress_light_in_view_id: u32 = 0,
    allow_light_in_view_id: u32 = 0,
    force_shadows: bool = false,
    no_shadows: bool = false,
    no_specular: bool = false,
    point_light: bool = false,
    parallel: bool = false,
    light_radius: CVec3 = .{},
    light_center: CVec3 = .{},
    target: CVec3 = .{},
    right: CVec3 = .{},
    up: CVec3 = .{},
    start: CVec3 = .{},
    end: CVec3 = .{},
    light_id: u32 = 0,
    shader: ?*Material = null,
    shader_params: [material.max_global_shader_params]f32 = std.mem.zeroes([material.max_global_shader_params]f32),
    reference_sound: ?*anyopaque = null,

    pub fn initFromSpawnArgs(
        self: *RenderLight,
        dict: *const idlib.Dict,
        allocator: Allocator,
    ) decl_manager.DeclManager.FindDeclError!void {
        const origin_str = dict.getString("light_origin") orelse
            dict.getString("origin") orelse
            "0 0 0";

        self.origin = CVec3.fromVec3f(
            common.parseVec3f(origin_str) catch Vec3(f32){},
        );

        self.shader_params[ShaderParam.red] = 1;
        self.shader_params[ShaderParam.green] = 1;
        self.shader_params[ShaderParam.blue] = 1;
        self.shader_params[ShaderParam.timescale] = 1;

        const texture_str = dict.getString("texture") orelse "lights/squarelight1";

        self.shader = try decl_manager.instance.findMaterial(texture_str, allocator);

        // TODO: parse all args
    }
};

const ShaderParam = RenderWorld.ShaderParam;
const RenderWorld = @import("render_world.zig");
const Plane = @import("../math/plane.zig").Plane;
const AreaReference = @import("common.zig").AreaReference;
const Interaction = @import("interaction.zig").Interaction;
const DoublePortal = @import("render_world.zig").DoublePortal;
const MaterialFlags = @import("material.zig").Flags;
const Material = @import("material.zig").Material;
const Winding = @import("../geometry/winding.zig").Winding;

pub const RenderLightLocal = extern struct {
    _vptr: *anyopaque = undefined,
    // specification
    params: RenderLight = .{},
    // the light has changed its position since it was
    // first added, so the prelight model is not valid
    light_has_moved: bool = false,
    world: ?*RenderWorld = null,
    // in world lightDefs
    index: c_int = 0,
    // if not -1, we may be able to cull all the light's
    // interactions if !viewDef->connectedAreas[areaNum]
    area_num: c_int = 0,
    // to determine if it is constantly changing,
    // and should go in the dynamic frame memory, or kept
    // in the cached memory
    last_modified_frame_num: c_int = 0,
    // for demo writing
    archived: bool = false,

    // derived information
    // old style light projection where Z and W are flipped and projected lights lightProject[3] is divided by ( zNear + zFar )
    light_project: [4]Plane = std.mem.zeroes([4]Plane),
    // global xyz1 to projected light strq
    base_light_project: RenderMatrix = std.mem.zeroes(RenderMatrix),
    // transforms the zero-to-one cube to exactly cover the light in world space
    inverse_base_light_project: RenderMatrix = std.mem.zeroes(RenderMatrix),
    // guaranteed to be valid, even if params.shader isn't
    light_shader: ?*const Material = null,
    falloff_image: ?*Image = null,
    // accounting for lightCenter and parallel
    global_light_origin: CVec3 = std.mem.zeroes(CVec3),
    global_light_bounds: CBounds = std.mem.zeroes(CBounds),
    // if == tr.viewCount, the light is on the viewDef->viewLights list
    view_count: c_int = 0,
    view_light: ?*ViewLight = null, // viewLight_t
    // each area the light is present in will have a lightRef
    references: ?*AreaReference = null,
    // doubly linked list
    first_interaction: ?*Interaction = null,
    last_interaction: ?*Interaction = null,
    fogged_portals: ?*DoublePortal = null,

    extern fn R_DeriveLightData(*RenderLightLocal) void;
    pub fn deriveLightData(light: *RenderLightLocal) void {
        // TODO
        R_DeriveLightData(light);
    }

    pub fn lightCastsShadows(light: *const RenderLightLocal) bool {
        const light_shader_casts_shadows = if (light.light_shader) |light_shader|
            light_shader.lightCastsShadows()
        else
            false;

        return light.params.force_shadows or
            (!light.params.no_shadows and light_shader_casts_shadows);
    }

    // Frees all references and lit surfaces from the light
    pub fn freeLightDerivedData(light: *RenderLightLocal) void {
        const world = light.world orelse return;

        // remove any portal fog references
        var opt_dp = light.fogged_portals;
        while (opt_dp) |dp| : (opt_dp = dp.next_fogged_portal) {
            dp.fog_light = null;
        }

        // free all the interactions
        while (light.first_interaction) |inter| {
            inter.unlinkAndFree(world.allocator);
        }

        // free all the references to the light
        var opt_next_ref: ?*AreaReference = null;
        var opt_light_ref = light.references;
        while (opt_light_ref) |light_ref| : (opt_light_ref = opt_next_ref) {
            opt_next_ref = light_ref.owner_next;

            // unlink from the area
            light_ref.area_next.?.area_prev = light_ref.area_prev;
            light_ref.area_prev.?.area_next = light_ref.area_next;

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
        if (world.pointInArea(light.global_light_origin.toVec3f())) |area_num| {
            light.area_num = @intCast(area_num);
        } else |_| {
            if (world.pointInArea(light.params.origin.toVec3f())) |area_num| {
                light.area_num = @intCast(area_num);
            } else |_| {
                light.area_num = -1;
            }
        }

        // bump the view count so we can tell if an
        // area already has a reference
        RenderSystem.instance.incViewCount();

        // push the light frustum down the BSP tree into areas
        try world.pushFrustumIntoTree(
            null,
            light,
            light.inverse_base_light_project,
            Bounds.zero_one_cube,
        );

        light.createLightFogPortals();
    }

    // When a fog light is created or moved, see if it completely
    // encloses any portals, which may allow them to be fogged closed.
    fn createLightFogPortals(light: *RenderLightLocal) void {
        light.fogged_portals = null;

        if (light.light_shader) |shader| {
            if (shader.isFogLight() or shader.testMaterialFlag(.{ .noportalfog = true }))
                return;
        }

        var opt_light_ref = light.references;
        while (opt_light_ref) |light_ref| : (opt_light_ref = light_ref.owner_next) {
            const area = light_ref.area orelse continue;
            var opt_portal = area.portals;
            while (opt_portal) |portal| : (opt_portal = portal.next) {
                var dp = portal.double_portal;

                // we only handle a single fog volume covering a portal
                // this will never cause incorrect drawing, but it may
                // fail to cull a portal
                if (dp.fog_light == null or
                    windingCompletelyInsideLight(portal.winding.*, light.*))
                    continue;

                dp.fog_light = light;
                dp.next_fogged_portal = light.fogged_portals;
                light.fogged_portals = dp;
            }
        }
    }
};

fn windingCompletelyInsideLight(w: Winding, light: RenderLightLocal) bool {
    for (0..w.num_points) |i| {
        if (light.base_light_project.cullPointToMVP(w.getVec3Point(i), true))
            return false;
    }

    return true;
}
