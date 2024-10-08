const std = @import("std");
const nvrhi = @import("nvrhi.zig");
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const Bounds = @import("../bounding_volume/bounds.zig");
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const RenderModel = @import("model.zig").RenderModel;
const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;
const VertexCache = @import("vertex_cache.zig");
const sys_types = @import("../sys/types.zig");
const material = @import("material.zig");
const RenderWorld = @import("render_world.zig");
const Plane = @import("../math/plane.zig").Plane;
const Vec3 = @import("../math/vector.zig").Vec3;

// Pre-generated shadow volumes from dmap are not present in surfaceInteraction_t,
// they are added separately.
pub const SurfaceInteraction = extern struct {
    // The vertexes for light tris will always come from ambient triangles.
    // For interactions created at load time, the indexes will be uniquely
    // generated in static vertex memory.
    numLightTrisIndexes: c_int,
    lightTrisIndexCache: VertexCache.VertexCacheHandle,
};

pub const Interaction = extern struct {
    // if an entity / light combination has been evaluated and found to not genrate any surfaces or shadows,
    // the constant INTERACTION_EMPTY will be stored in the interaction table, int contrasts to NULL, which
    // means that the combination has not yet been tested for having surfaces.
    pub var INTERACTION_EMPTY: Interaction = .{};

    // this may be 0 if the light and entity do not actually intersect
    // -1 = an untested interaction
    numSurfaces: c_int = 0,

    // if there is a whole-entity optimized shadow hull, it will
    // be present as a surfaceInteraction_t with a NULL ambientTris, but
    // possibly having a shader to specify the shadow sorting order
    // (FIXME: actually try making shadow hulls?  we never did.)
    surfaces: ?[*]SurfaceInteraction = null,

    // get space from here, if NULL, it is a pre-generated shadow volume from dmap
    entityDef: ?*RenderEntityLocal = null,
    lightDef: ?*RenderLightLocal = null,
    // for lightDef chains
    lightNext: ?*Interaction = null,
    lightPrev: ?*Interaction = null,
    // for entityDef chains
    entityNext: ?*Interaction = null,
    entityPrev: ?*Interaction = null,

    // true if the interaction was created at map load time in static buffer space
    staticInteraction: bool = false,

    pub fn isEmpty(inter: Interaction) bool {
        return inter.numSurfaces == 0;
    }

    // returns true if the interaction is not yet completely created
    pub fn isDeferred(inter: Interaction) bool {
        return inter.numSurfaces == -1;
    }

    pub fn freeSurfaces(inter: *Interaction, allocator: std.mem.Allocator) void {
        // anything regenerated is no longer an optimized static version
        inter.staticInteraction = false;

        if (inter.surfaces) |surfaces_ptr| {
            const surfaces = surfaces_ptr[0..@intCast(inter.numSurfaces)];
            allocator.free(surfaces);
            inter.surfaces = null;
        }
        inter.numSurfaces = -1;
    }

    pub fn unlink(inter: *Interaction) void {
        // unlink from the entity's list
        if (inter.entityPrev) |entity_prev|
            entity_prev.entityNext = inter.entityNext
        else if (inter.entityDef) |entity_def|
            entity_def.firstInteraction = inter.entityNext;

        if (inter.entityNext) |entity_next|
            entity_next.entityPrev = inter.entityPrev
        else if (inter.entityDef) |entity_def|
            entity_def.lastInteraction = inter.entityPrev;

        inter.entityPrev = null;
        inter.entityNext = null;

        // unlink from the light's list
        if (inter.lightPrev) |light_prev|
            light_prev.lightNext = inter.lightNext
        else if (inter.lightDef) |light_def|
            light_def.firstInteraction = inter.lightNext;

        if (inter.lightNext) |light_next|
            light_next.lightPrev = inter.lightPrev
        else if (inter.lightDef) |light_def|
            light_def.lastInteraction = inter.lightPrev;

        inter.lightPrev = null;
        inter.lightNext = null;
    }

    pub fn unlinkAndFree(inter: *Interaction, allocator: std.mem.Allocator) void {
        const light_def = inter.lightDef orelse return;
        const entity_def = inter.entityDef orelse return;
        const render_world = light_def.world orelse return;

        // clear the table pointer
        if (render_world.interaction_table) |interaction_table| {
            const index = @as(usize, @intCast(light_def.index)) *
                render_world.interaction_table_width +
                @as(usize, @intCast(entity_def.index));
            const entry = interaction_table[index];
            if (entry != inter and entry != &INTERACTION_EMPTY) {
                @panic("Interaction: interaction_table wasn't set");
            }
            interaction_table[index] = null;
        }

        inter.unlink();
        inter.freeSurfaces(allocator);

        // put it back on the free list
        render_world.interaction_allocator.destroy(inter);
    }

    pub fn allocAndLink(
        entity_def: *RenderEntityLocal,
        light_def: *RenderLightLocal,
    ) error{ OutOfMemory, NotInitialized }!*Interaction {
        var render_world = entity_def.world orelse return error.NotInitialized;
        var inter = try render_world.interaction_allocator.create();

        // link and init
        inter.lightDef = light_def;
        inter.entityDef = entity_def;

        // not checked yet
        inter.numSurfaces = -1;
        inter.surfaces = null;

        // link at the start of the light's list
        inter.lightNext = light_def.firstInteraction;
        inter.lightPrev = null;
        light_def.firstInteraction = inter;
        if (inter.lightNext) |light_next|
            light_next.lightPrev = inter
        else
            light_def.lastInteraction = inter;

        // link at the start of the entity's list
        inter.entityNext = entity_def.firstInteraction;
        inter.entityPrev = null;
        entity_def.firstInteraction = inter;
        if (inter.entityNext) |entity_next|
            entity_next.entityPrev = inter
        else
            entity_def.lastInteraction = inter;

        // update the interaction table
        if (render_world.interaction_table) |table| {
            const index = @as(usize, @intCast(light_def.index)) * render_world.interaction_table_width + @as(usize, @intCast(entity_def.index));
            const entry = &table[index];
            if (entry.* != null)
                @panic("Interaction: non null table entry!");

            entry.* = inter;
        }

        return inter;
    }

    pub fn createStaticInteraction(
        inter: *Interaction,
        command_list: *nvrhi.ICommandList,
        surface_allocator: std.mem.Allocator,
    ) error{OutOfMemory}!void {
        const entity_def = inter.entityDef orelse return;
        const light_def = inter.lightDef orelse return;

        inter.staticInteraction = true;

        const render_model = if (entity_def.parms.hModel) |model_ptr| render_model: {
            if (model_ptr.numSurfaces() <= 0 or model_ptr.isDynamicModel() != .DM_STATIC) {
                inter.makeEmpty();
                return;
            }

            break :render_model model_ptr;
        } else {
            inter.makeEmpty();
            return;
        };

        const bounds = render_model.boundsFromDef(&entity_def.parms).toBounds();

        // if it doesn't contact the light frustum, none of the surfaces will
        if (cullModelBoundsToLight(light_def.*, bounds, entity_def.modelRenderMatrix)) {
            inter.makeEmpty();
            return;
        }

        // create slots for each of the model's surfaces
        inter.numSurfaces = render_model.numSurfaces();
        const surfaces = try surface_allocator.alloc(SurfaceInteraction, @intCast(inter.numSurfaces));
        for (surfaces) |*surface| surface.* = std.mem.zeroes(SurfaceInteraction);

        inter.surfaces = surfaces.ptr;

        var interaction_generated = false;
        defer {
            if (!interaction_generated) {
                surface_allocator.free(surfaces);
                inter.surfaces = null;
                inter.makeEmpty();
            }
        }

        // check each surface in the model

        for (0..@intCast(render_model.numSurfaces())) |c| {
            const surf = render_model.getSurface(c) orelse continue;
            const tri = surf.geometry orelse continue;
            const shader_ptr = surf.shader orelse continue;

            const shader = material.remapShaderBySkin(
                shader_ptr,
                entity_def.parms.customSkin,
                entity_def.parms.customShader,
            ) orelse continue;

            // try to cull each surface
            if (cullModelBoundsToLight(light_def.*, tri.bounds.toBounds(), entity_def.modelRenderMatrix))
                continue;

            var sint = &surfaces[c];

            // generate a set of indexes for the lit surfaces, culling away triangles that are
            // not at least partially inside the light
            if (shader.receivesLighting()) {
                if (try createInteractionLightSurfaceTriangles(
                    surface_allocator,
                    entity_def.*,
                    tri,
                    light_def.*,
                    shader,
                )) |light_tris| {
                    // make a static index cache
                    sint.numLightTrisIndexes = light_tris.numIndexes;
                    sint.lightTrisIndexCache = VertexCache.instance.allocStaticIndex(
                        @ptrCast(light_tris.indexes),
                        @as(usize, @intCast(light_tris.numIndexes)) * @sizeOf(sys_types.TriIndex),
                        command_list,
                    );
                    interaction_generated = true;

                    light_tris.deinit(surface_allocator);
                }
            }
        }
    }

    /// Relinks the interaction at the end of both the light and entity chains
    /// and adds the INTERACTION_EMPTY marker to the interactionTable.
    /// It is necessary to keep the empty interaction so when entities or lights move
    /// they can set all the interactionTable values to NULL.
    pub fn makeEmpty(inter: *Interaction) void {
        inter.numSurfaces = 0;
        inter.unlink();

        // link at the end of the light's list
        if (inter.lightDef) |light_def| {
            inter.lightNext = null;
            inter.lightPrev = light_def.lastInteraction;
            light_def.lastInteraction = inter;
            if (inter.lightPrev) |light_prev|
                light_prev.lightNext = inter
            else
                light_def.firstInteraction = inter;
        }

        // relink at the end of the entity's list
        if (inter.entityDef) |entity_def| {
            inter.entityNext = null;
            inter.entityPrev = entity_def.lastInteraction;
            entity_def.lastInteraction = inter;
            if (inter.entityPrev) |entity_prev|
                entity_prev.entityNext = inter
            else
                entity_def.firstInteraction = inter;
        }

        // store the special marker in the interaction table
        const e_index: usize = if (inter.entityDef) |entity_def| @intCast(entity_def.index) else return;
        const l_index: usize = if (inter.lightDef) |light_def| @intCast(light_def.index) else return;
        const world = inter.entityDef.?.world orelse return;

        const index = l_index * world.interaction_table_width + e_index;
        if (world.interaction_table.?[index] != inter)
            @panic("Interaction: makeEmpty assert fails!");

        world.interaction_table.?[index] = &INTERACTION_EMPTY;
    }
};

const Material = @import("material.zig").Material;

pub fn globalPointToLocal(model_matrix: []const f32, in: Vec3(f32)) Vec3(f32) {
    const temp = Vec3(f32){ .v = .{
        in.x() - model_matrix[3 * 4 + 0],
        in.y() - model_matrix[3 * 4 + 1],
        in.z() - model_matrix[3 * 4 + 2],
    } };

    return .{ .v = .{
        temp.x() * model_matrix[0 * 4 + 0] + temp.x() * model_matrix[0 * 4 + 1] + temp.x() * model_matrix[0 * 4 + 2],
        temp.y() * model_matrix[1 * 4 + 0] + temp.y() * model_matrix[1 * 4 + 1] + temp.y() * model_matrix[1 * 4 + 2],
        temp.z() * model_matrix[2 * 4 + 0] + temp.z() * model_matrix[2 * 4 + 1] + temp.z() * model_matrix[2 * 4 + 2],
    } };
}

pub fn globalPlaneToLocal(model_matrix: []const f32, in: Plane) Plane {
    var out: Plane = std.mem.zeroes(Plane);

    out.a = in.a * model_matrix[0 * 4 + 0] + in.b * model_matrix[0 * 4 + 1] + in.c * model_matrix[0 * 4 + 2];
    out.b = in.a * model_matrix[1 * 4 + 0] + in.b * model_matrix[1 * 4 + 1] + in.c * model_matrix[1 * 4 + 2];
    out.c = in.a * model_matrix[2 * 4 + 0] + in.b * model_matrix[2 * 4 + 1] + in.c * model_matrix[2 * 4 + 2];
    out.d = in.a * model_matrix[3 * 4 + 0] + in.b * model_matrix[3 * 4 + 1] + in.c * model_matrix[3 * 4 + 2] + in.d;
    return out;
}

const SurfaceCullInfo = struct {
    const PlanesNum = 6;
    const BitSet = std.bit_set.StaticBitSet(PlanesNum);

    facing: ?std.bit_set.DynamicBitSet,
    cull_bits: ?[]BitSet,
    cull_all_front: bool,
    local_clip_planes: [PlanesNum]Plane,

    pub fn init() SurfaceCullInfo {
        return .{
            .facing = null,
            .cull_bits = null,
            .cull_all_front = false,
            .local_clip_planes = std.mem.zeroes([PlanesNum]Plane),
        };
    }

    pub fn calcFacing(
        info: *SurfaceCullInfo,
        allocator: std.mem.Allocator,
        global_light_origin: Vec3(f32),
        model_matrix: []const f32,
        tri: SurfaceTriangles,
    ) error{OutOfMemory}!void {
        if (info.facing != null) return;

        const num_indexes: usize = @intCast(tri.numIndexes);
        const num_faces = num_indexes / 3;
        info.facing = try std.bit_set.DynamicBitSet.initEmpty(allocator, num_faces + 1);

        const local_light_origin = globalPointToLocal(model_matrix, global_light_origin);

        var i: usize = 0;
        var face: usize = 0;
        while (i < num_indexes) : ({
            i += 3;
            face += 1;
        }) {
            const v0 = &tri.verts[tri.indexes[i + 0]];
            const v1 = &tri.verts[tri.indexes[i + 1]];
            const v2 = &tri.verts[tri.indexes[i + 2]];
            const plane = Plane{
                .a = v0.xyz.x,
                .b = v1.xyz.y,
                .c = v2.xyz.z,
                .d = 0,
            };
            const d = plane.distance(local_light_origin);
            info.facing.setValue(face, d >= 0.0);
        }
        info.facing.set(num_faces); // for dangling edges to reference
    }

    const LIGHT_CLIP_EPSILON = 0.1;
    fn calcCullFrontBits(
        info: *SurfaceCullInfo,
        base_light_project: RenderMatrix,
        model_matrix: []const f32,
        tri: SurfaceTriangles,
    ) BitSet {
        const frustum_planes = RenderMatrix.getFrustumPlanes(base_light_project, true, true);

        // cull the triangle surface bounding box
        var front_bits = BitSet.initEmpty();
        for (&info.local_clip_planes, frustum_planes, 0..) |*clip_plane, frustum_plane, i| {
            clip_plane.* = globalPlaneToLocal(model_matrix, frustum_plane);

            // get front bits for the whole surface
            if (tri.bounds.toBounds().planeDistance(clip_plane.*) >= LIGHT_CLIP_EPSILON) {
                front_bits.set(i);
            }
        }

        // if the surface is completely inside the light frustum
        return front_bits;
    }

    pub fn calcCullBits(
        info: *SurfaceCullInfo,
        allocator: std.mem.Allocator,
        base_light_project: RenderMatrix,
        model_matrix: []const f32,
        tri: SurfaceTriangles,
    ) error{OutOfMemory}!void {
        if (info.cull_bits != null) return;

        const front_bits = info.calcCullFrontBits(base_light_project, model_matrix, tri);
        info.cull_all_front = front_bits.eql(BitSet.initFull());
        if (info.cull_all_front) return;

        const num_verts: usize = @intCast(tri.numVerts);
        const cull_bits = try allocator.alloc(BitSet, num_verts);
        for (cull_bits) |*bit| bit.* = BitSet.initEmpty();

        info.cull_bits = cull_bits;

        for (info.local_clip_planes, 0..) |clip_plane, i| {
            if (front_bits.isSet(i)) continue;

            for (cull_bits, 0..) |*bit, j| {
                const d = clip_plane.distance(tri.verts.?[j].xyz.toVec3f());
                bit.setValue(i, d < LIGHT_CLIP_EPSILON);
            }
        }
    }

    pub fn deinit(info: *SurfaceCullInfo, allocator: std.mem.Allocator) void {
        if (info.facing) |*facing| {
            facing.deinit();
            info.facing = null;
        }
        if (info.cull_bits) |cull_bits| {
            allocator.free(cull_bits);
            info.cull_bits = null;
        }
        info.cull_all_front = false;
        info.local_clip_planes = std.mem.zeroes([PlanesNum]Plane);
    }
};

fn createInteractionLightSurfaceTriangles(
    allocator: std.mem.Allocator,
    entity_def: RenderEntityLocal,
    tri: *SurfaceTriangles,
    light_def: RenderLightLocal,
    shader: *const Material,
) error{OutOfMemory}!?*SurfaceTriangles {
    const r_lightAllBackFaces = true;
    const include_back_faces =
        r_lightAllBackFaces or
        light_def.lightShader.?.lightEffectsBackSides() or
        shader.ReceivesLightingOnBackSides() or
        entity_def.parms.noSelfShadow or
        entity_def.parms.noShadow;

    var surface_triangles = try SurfaceTriangles.init(allocator);
    errdefer surface_triangles.deinit(allocator);

    // save a reference to the original surface
    surface_triangles.ambientSurface = tri;

    // the light surface references the verts of the ambient surface
    surface_triangles.numVerts = tri.numVerts;
    surface_triangles.verts = tri.verts;
    surface_triangles.vertsAlloced = tri.vertsAlloced;
    var cull_info = SurfaceCullInfo.init();
    defer cull_info.deinit(allocator);

    if (!include_back_faces) {
        try cull_info.calcFacing(
            allocator,
            light_def.globalLightOrigin.toVec3f(),
            &entity_def.modelMatrix,
            tri.*,
        );
    }

    try cull_info.calcCullBits(
        allocator,
        light_def.baseLightProject,
        &entity_def.modelMatrix,
        tri.*,
    );

    var num_indexes: usize = 0;
    var bounds = Bounds.zero;
    // if the surface is completely inside the light frustum
    if (cull_info.cull_all_front) {
        if (include_back_faces) {
            // the whole surface is lit so the light surface just references the indexes of the ambient surface
            surface_triangles.indexes = tri.indexes;
            surface_triangles.indexCache = tri.indexCache;
            surface_triangles.indexesAlloced = tri.indexesAlloced;
            num_indexes = @intCast(tri.numIndexes);
            bounds = tri.bounds.toBounds();
        } else {
            const facing = cull_info.facing orelse @panic("facing must be calculated!");

            // the light tris indexes are going to be a subset of the original indexes so we generally
            // allocate too much memory here but we decrease the memory block when the number of indexes is known
            const indexes = try surface_triangles.allocIndexes(allocator, @intCast(tri.numIndexes));
            const tri_indexes = tri.indexesSlice();

            // back face cull the individual triangles
            const i: usize = 0;
            const face_num: usize = 0;
            while (i < tri_indexes.len) : ({
                i += 3;
                face_num += 1;
            }) {
                if (!facing.isSet(face_num)) {
                    //c_incBackfaced();
                    continue;
                }

                indexes[num_indexes + 0] = tri_indexes[i + 0];
                indexes[num_indexes + 1] = tri_indexes[i + 1];
                indexes[num_indexes + 2] = tri_indexes[i + 2];
                num_indexes += 3;
            }

            if (num_indexes > 0) {
                const tri_verts = tri.verticesSlice();
                // get bounds for the surface
                var min: @Vector(3, f32) = @splat(std.math.floatMax(f32));
                var max: @Vector(3, f32) = @splat(std.math.floatMin(f32));
                for (indexes[0..num_indexes]) |tri_index| {
                    const src_vec: @Vector(3, f32) = tri_verts[@intCast(tri_index)].xyz.toVec3f().v;
                    min = @min(min, src_vec);
                    max = @max(max, src_vec);
                }
                bounds.min.v = min;
                bounds.max.v = max;
            }

            // decrease the size of the memory block to the size of the number of used indexes
            try surface_triangles.resizeIndexes(allocator, num_indexes);
            surface_triangles.numIndexes = @intCast(num_indexes);
        }
    } else {
        const cull_bits = cull_info.cull_bits orelse @panic("cull_bits must be calculated!");
        const indexes = try surface_triangles.allocIndexes(allocator, @intCast(tri.numIndexes));
        const tri_indexes = tri.indexesSlice();

        var i: usize = 0;
        var face_num: usize = 0;
        while (i < tri_indexes.len) : ({
            i += 3;
            face_num += 1;
        }) {
            const index1: usize = @intCast(tri_indexes[i + 0]);
            const index2: usize = @intCast(tri_indexes[i + 1]);
            const index3: usize = @intCast(tri_indexes[i + 2]);

            // if we aren't self shadowing, let back facing triangles get
            // through so the smooth shaded bump maps light all the way around
            if (!include_back_faces) {
                const facing = cull_info.facing orelse @panic("facing must be calculated");
                // back face cull
                if (!facing.isSet(face_num)) {
                    //c_incBackFaced();
                    continue;
                }
            }

            const intersection = cull_bits[index1]
                .intersectWith(cull_bits[index2])
                .intersectWith(cull_bits[index3]);

            // fast cull outside the frustum
            // if all three points are off one plane side, it definately isn't visible
            if (intersection.findFirstSet() != null) {
                //c_incDistance();
                continue;
            }

            indexes[num_indexes + 0] = @intCast(index1);
            indexes[num_indexes + 1] = @intCast(index2);
            indexes[num_indexes + 2] = @intCast(index3);
            num_indexes += 3;
        }

        if (num_indexes > 0) {
            const tri_verts = tri.verticesSlice();
            var min: @Vector(3, f32) = @splat(std.math.floatMax(f32));
            var max: @Vector(3, f32) = @splat(std.math.floatMin(f32));
            for (indexes[0..num_indexes]) |tri_index| {
                const src_vec: @Vector(3, f32) = tri_verts[@intCast(tri_index)].xyz.toVec3f().v;
                min = @min(min, src_vec);
                max = @max(max, src_vec);
            }
            bounds.min.v = min;
            bounds.max.v = max;
        }

        try surface_triangles.resizeIndexes(allocator, num_indexes);
        surface_triangles.numIndexes = @intCast(num_indexes);
    }

    if (num_indexes == 0) {
        surface_triangles.deinit(allocator);
        return null;
    }

    surface_triangles.numIndexes = @intCast(num_indexes);
    surface_triangles.bounds = CBounds.fromBounds(bounds);

    return surface_triangles;
}

pub fn cullModelBoundsToLight(light: RenderLightLocal, local_bounds: Bounds, model_render_matrix: RenderMatrix) bool {
    var model_light_project = light.baseLightProject.multiply(model_render_matrix);

    return model_light_project.cullBoundsToMVP(local_bounds, true);
}
