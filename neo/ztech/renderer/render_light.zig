const std = @import("std");
const decl_manager = @import("../framework/decl_manager.zig");
const DeclManager = decl_manager.DeclManager;
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
const axisToModelMatrix = @import("render_entity.zig").axisToModelMatrix;
const localPlaneToGlobal = @import("interaction.zig").localPlaneToGlobal;

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

        const got_target = false;
        if (!got_target) {
            self.point_light = true;
            self.light_radius = .{ .x = 300, .y = 300, .z = 300 };
        }

        self.axis = CMat3.fromMat3f(common.parseMat3f("1 0 0 0 1 0 0 0 1") catch unreachable);

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

    pub fn deriveLightData(light: *RenderLightLocal, allocator: Allocator) DeclManager.FindDeclError!void {
        const light_shader = if (light.params.shader) |shader|
            shader
        else if (light.light_shader) |shader|
            shader
        else if (light.params.point_light)
            RenderSystem.instance.default_point_light orelse @panic("default_point_light is undefined")
        else
            RenderSystem.instance.default_projected_light orelse @panic("default_projected_light is undefined");
        light.light_shader = light_shader;

        light.falloff_image = if (light_shader.light_falloff_image) |image|
            image
        else falloff_image: {
            const default_shader = if (light.params.point_light)
                RenderSystem.instance.default_point_light orelse @panic("default_point_light is undefined")
            else
                RenderSystem.instance.default_projected_light orelse @panic("default_projected_light is undefined");

            try decl_manager.instance.touch(@ptrCast(default_shader), allocator);

            break :falloff_image default_shader.light_falloff_image;
        };

        const local_project = light.computeProjectionMatrix();
        var light_transform: [16]f32 = undefined;
        axisToModelMatrix(light.params.axis, light.params.origin, &light_transform);

        for (&light.light_project) |*plane| {
            plane.* = localPlaneToGlobal(&light_transform, plane.*);
        }

        if (light.params.parallel) {
            var dir, const len = light.params.light_center.toVec3f().normalizeLen();
            if (len == 0.0) {
                dir.v[2] = 1.0;
            }

            light.global_light_origin = CVec3.fromVec3f(
                dir.scale(100000).add(light.params.origin.toVec3f()),
            );
        } else {
            const axis = light.params.axis.toMat3f();
            const light_center = light.params.light_center.toVec3f();
            const origin = light.params.origin.toVec3f();
            light.global_light_origin = CVec3.fromVec3f(
                axis.multiplyVec3(light_center).add(origin),
            );
        }

        const light_matrix = RenderMatrix.createFromOriginMatrix(
            light.params.origin.toVec3f(),
            light.params.axis.toMat3f(),
        );

        var inverse_light_matrix = std.mem.zeroes(RenderMatrix);
        if (!RenderMatrix.inverse(&light_matrix, &inverse_light_matrix)) {
            std.debug.print("[WARN] light_matrix invert failed\n", .{});
        }

        light.base_light_project = RenderMatrix.multiply(local_project, inverse_light_matrix);

        if (!RenderMatrix.inverse(&light.base_light_project, &light.inverse_base_light_project)) {
            std.debug.print("[WARN] base_light_project invert failed\n", .{});
        }

        RenderMatrix.projectedBounds(
            &light.global_light_bounds,
            light.inverse_base_light_project,
            CBounds.fromBounds(Bounds.zero_one_cube),
            false,
        );
    }

    extern fn c_computeSpotLightProjectionMatrix(*RenderLightLocal, *RenderMatrix) f32;
    fn computeProjectionMatrix(light: *RenderLightLocal) RenderMatrix {
        var z_scale: f32 = 1.0;
        var local_project = std.mem.zeroes(RenderMatrix);

        if (light.params.parallel) {
            local_project.r(0)[0] = 0.5 / light.params.light_radius.x;
            local_project.r(1)[1] = 0.5 / light.params.light_radius.y;
            local_project.r(2)[2] = 0.5 / light.params.light_radius.z;
            local_project.r(0)[3] = 0.5;
            local_project.r(1)[3] = 0.5;
            local_project.r(2)[3] = 0.5;
            local_project.r(3)[3] = 1;
        } else if (light.params.point_light) {
            local_project.r(0)[0] = 0.5 / light.params.light_radius.x;
            local_project.r(1)[1] = 0.5 / light.params.light_radius.y;
            local_project.r(2)[2] = 0.5 / light.params.light_radius.z;
            local_project.r(0)[3] = 0.5;
            local_project.r(1)[3] = 0.5;
            local_project.r(2)[3] = 0.5;
            local_project.r(3)[3] = 1;
        } else {
            z_scale = c_computeSpotLightProjectionMatrix(light, &local_project);
        }

        light.light_project[0].slice()[0] = local_project.r(0)[0];
        light.light_project[0].slice()[1] = local_project.r(0)[1];
        light.light_project[0].slice()[2] = local_project.r(0)[2];
        light.light_project[0].slice()[3] = local_project.r(0)[3];

        light.light_project[1].slice()[0] = local_project.r(1)[0];
        light.light_project[1].slice()[1] = local_project.r(1)[1];
        light.light_project[1].slice()[2] = local_project.r(1)[2];
        light.light_project[1].slice()[3] = local_project.r(1)[3];

        light.light_project[2].slice()[0] = local_project.r(3)[0];
        light.light_project[2].slice()[1] = local_project.r(3)[1];
        light.light_project[2].slice()[2] = local_project.r(3)[2];
        light.light_project[2].slice()[3] = local_project.r(3)[3];

        light.light_project[3].slice()[0] = local_project.r(2)[0] * z_scale;
        light.light_project[3].slice()[1] = local_project.r(2)[1] * z_scale;
        light.light_project[3].slice()[2] = local_project.r(2)[2] * z_scale;
        light.light_project[3].slice()[3] = local_project.r(2)[3] * z_scale;

        return local_project;
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

    pub fn createLightRefs(light: *RenderLightLocal, allocator: Allocator) !void {
        try light.deriveLightData(allocator);

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
