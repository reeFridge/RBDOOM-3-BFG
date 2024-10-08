const std = @import("std");
const math = @import("../math/math.zig");
const RenderEntity = @import("render_entity.zig").RenderEntity;
const RenderModel = @import("model.zig").RenderModel;
const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const ViewDef = @import("common.zig").ViewDef;
const ViewEntity = @import("common.zig").ViewEntity;
const DrawSurface = @import("common.zig").DrawSurface;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const sys_types = @import("../sys/types.zig");
const Material = @import("material.zig").Material;
const FrameData = @import("frame_data.zig");
const VertexCache = @import("vertex_cache.zig");

const MAX_DEFERRED_DECALS: usize = 16;
// don't create a decal if it wasn't visible within the first second
const DEFERRED_DECAL_TIMEOUT: c_int = 1000;
const MAX_DECALS: usize = 128;
const NUM_DECAL_BOUNDING_PLANES: usize = 6;
// 3 triangle verts clipped NUM_DECAL_BOUNDING_PLANES + 3 times (plus 6 for safety)
const MAX_DECAL_VERTS: usize = 3 + NUM_DECAL_BOUNDING_PLANES + 3 + 6;
const MAX_DECAL_INDEXES: usize = (MAX_DECAL_VERTS - 2) * 3;

const CVec3 = @import("../math/vector.zig").CVec3;
const Plane = @import("../math/plane.zig").Plane;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
pub const DecalProjectionParams = extern struct {
    boundingPlanes: [NUM_DECAL_BOUNDING_PLANES]Plane,
    fadePlanes: [2]Plane,
    textureAxis: [2]Plane,
    projectionOrigin: CVec3,
    projectionBounds: CBounds,
    material: ?*const Material,
    fadeDepth: f32,
    startTime: c_int,
    parallel: bool,
    force: bool,
};

pub const Decal align(16) = extern struct {
    verts: [MAX_DECAL_VERTS]DrawVertex align(16),
    indexes: [MAX_DECAL_INDEXES]sys_types.TriIndex align(16),
    vertDepthFade: [MAX_DECAL_VERTS]f32,
    numVerts: c_int,
    numIndexes: c_int,
    startTime: c_int,
    material: ?*const Material,
};

pub const ModelDecal = extern struct {
    decals: [MAX_DECALS]Decal,
    firstDecal: c_uint,
    nextDecal: c_uint,

    deferredDecals: [MAX_DEFERRED_DECALS]DecalProjectionParams,
    firstDeferredDecal: c_uint,
    nextDeferredDecal: c_uint,

    decalMaterials: [MAX_DECALS]?*const Material,
    numDecalMaterials: c_uint,

    extern fn c_modelDecal_createDecal(
        *ModelDecal,
        *const RenderModel,
        *const DecalProjectionParams,
    ) void;

    pub fn createDeferredDecals(decal: *ModelDecal, model: *const RenderModel, view_def: *const ViewDef) void {
        const first: usize = @intCast(decal.firstDeferredDecal);
        const last: usize = @intCast(decal.nextDeferredDecal);
        for (first..last) |i| {
            const params = &decal.deferredDecals[i % MAX_DEFERRED_DECALS];
            if (params.startTime > (view_def.renderView.time[0] - DEFERRED_DECAL_TIMEOUT)) {
                decal.createDecal(model, params);
            }
        }

        decal.firstDeferredDecal = 0;
        decal.nextDeferredDecal = 0;
    }

    pub fn getNumDecalDrawSurfs(decal: *ModelDecal) usize {
        decal.numDecalMaterials = 0;

        const first: usize = @intCast(decal.firstDecal);
        const last: usize = @intCast(decal.nextDecal);

        for (first..last) |i| {
            const decal_ = &decal.decals[i % MAX_DECALS];
            var j: usize = 0;
            while (j < decal.numDecalMaterials) : (j += 1) {
                if (decal.decalMaterials[j] == decal_.material)
                    break;
            }

            if (j >= decal.numDecalMaterials) {
                decal.decalMaterials[@intCast(decal.numDecalMaterials)] = decal_.material;
                decal.numDecalMaterials += 1;
            }
        }

        return @intCast(decal.numDecalMaterials);
    }

    pub fn createDecalDrawSurf(
        model_decal: *ModelDecal,
        space: *const ViewEntity,
        index: usize,
        view_def: *ViewDef,
    ) ?*DrawSurface {
        if (index >= model_decal.numDecalMaterials) return null;

        const material = model_decal.decalMaterials[index] orelse return null;

        var max_verts: usize = 0;
        var max_indexes: usize = 0;
        const first: usize = @intCast(model_decal.firstDecal);
        const last: usize = @intCast(model_decal.nextDecal);
        for (first..last) |i| {
            const decal = &model_decal.decals[i % MAX_DECALS];
            if (decal.material == material) {
                max_verts += @intCast(decal.numVerts);
                max_indexes += @intCast(decal.numIndexes);
            }
        }

        if (max_verts == 0 or max_indexes == 0) return null;

        // create a new triangle surface in frame memory so it gets automatically disposed of
        const new_tri = FrameData.frameCreate(SurfaceTriangles);
        new_tri.* = std.mem.zeroes(SurfaceTriangles);
        new_tri.numVerts = @intCast(max_verts);
        new_tri.numIndexes = @intCast(max_indexes);
        new_tri.ambientCache = VertexCache.instance.allocVertex(
            null,
            max_verts,
            @sizeOf(DrawVertex),
            null,
        );
        new_tri.indexCache = VertexCache.instance.allocIndex(
            null,
            max_indexes,
            @sizeOf(sys_types.TriIndex),
            null,
        );

        const mapped_verts: [*]DrawVertex = @ptrCast(@alignCast(VertexCache.instance.mappedVertexBuffer(
            new_tri.ambientCache,
        )));
        const mapped_indexes: [*]sys_types.TriIndex = @ptrCast(@alignCast(VertexCache.instance.mappedIndexBuffer(
            new_tri.indexCache,
        )));

        const decal_info = material.getDecalInfo();
        const max_time = decal_info.stayTime + decal_info.fadeTime;
        const time = view_def.renderView.time[0];

        var num_verts: usize = 0;
        var num_indexes: usize = 0;
        for (first..last) |i| {
            const decal = &model_decal.decals[i % MAX_DECALS];
            if (decal.numVerts == 0) {
                if (i == model_decal.firstDecal) model_decal.firstDecal += 1;
                continue;
            }

            if (decal.material != material) continue;

            const delta_time = time - decal.startTime;
            const fade_time = delta_time - decal_info.stayTime;
            // already completely faded away, but not yet removed
            if (delta_time > max_time) continue;

            const f = if (delta_time > decal_info.stayTime)
                @as(f32, @floatFromInt(fade_time)) / @as(f32, @floatFromInt(decal_info.fadeTime))
            else
                0.0;

            var fade_color: [4]f32 align(16) = undefined;
            for (&fade_color, 0..) |*color, j| {
                color.* = 255.0 *
                    (decal_info.start[j] +
                    (decal_info.end[j] - decal_info.start[j]) * f);
            }

            copyDecalSurface(
                mapped_verts,
                num_verts,
                mapped_indexes,
                num_indexes,
                decal,
                &fade_color,
            );

            num_verts += @intCast(decal.numVerts);
            num_indexes += @intCast(decal.numIndexes);
        }

        new_tri.numVerts = @intCast(num_verts);
        new_tri.numIndexes = @intCast(num_indexes);

        const draw_surf = FrameData.frameCreate(DrawSurface);
        draw_surf.frontEndGeo = new_tri;
        draw_surf.numIndexes = new_tri.numIndexes;
        draw_surf.ambientCache = new_tri.ambientCache;
        draw_surf.indexCache = new_tri.indexCache;
        draw_surf.jointCache = 0;
        draw_surf.space = space;
        draw_surf.scissorRect = space.scissorRect;
        draw_surf.extraGLState = 0;

        draw_surf.setupShader(material, &space.entityDef.?.parms, view_def);

        return draw_surf;
    }

    fn createDecal(
        decal: *ModelDecal,
        model: *const RenderModel,
        params: *const DecalProjectionParams,
    ) void {
        c_modelDecal_createDecal(decal, model, params);
    }
};

fn copyDecalSurface(
    verts: [*]DrawVertex,
    num_verts: usize,
    indexes: [*]sys_types.TriIndex,
    num_indexes: usize,
    decal: *const Decal,
    fade_color: []const f32,
) void {
    // copy vertices and apply depth/time based fading
    for (0..@intCast(decal.numVerts)) |i| {
        verts[num_verts + i] = decal.verts[i];
        for (0..4) |j| {
            verts[num_verts + i].color[j] = math.ftob(
                fade_color[j] * decal.vertDepthFade[i],
            );
        }
    }

    // copy indices
    //std.debug.assert((decal.numIndexes & 1) == 0);
    var i: usize = 0;
    while (i < decal.numIndexes) : (i += 2) {
        const index_a = decal.indexes[i + 0];
        const index_b = decal.indexes[i + 1];
        std.debug.assert(index_a < decal.numVerts and index_b < decal.numVerts);

        writeIndexPair(
            &indexes[num_indexes + i],
            @intCast(num_verts + index_a),
            @intCast(num_verts + index_b),
        );
    }
}

pub fn writeIndexPair(
    dest: [*c]sys_types.TriIndex,
    a: sys_types.TriIndex,
    b: sys_types.TriIndex,
) void {
    const unsigned_dest = @as([*c]c_uint, @ptrCast(@alignCast(dest)));
    const unsigned_a = @as(c_uint, @bitCast(@as(c_uint, a)));
    const unsigned_b = @as(c_uint, @bitCast(@as(c_uint, b)));

    unsigned_dest.* = unsigned_a | (unsigned_b << @intCast(16));
}
