const std = @import("std");
const writeIndexPair = @import("model_decal.zig").writeIndexPair;
const ViewEntity = @import("common.zig").ViewEntity;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const DrawSurface = @import("common.zig").DrawSurface;
const RenderModel = @import("model.zig").RenderModel;
const RenderModelStatic = @import("model.zig").RenderModelStatic;
const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const ViewDef = @import("common.zig").ViewDef;
const Material = @import("material.zig").Material;
const sys_types = @import("../sys/types.zig");
const Plane = @import("../math/plane.zig").Plane;
const FrameData = @import("frame_data.zig");
const VertexCache = @import("vertex_cache.zig");

const MAX_DEFERRED_OVERLAYS: usize = 4;
// don't create a decal if it wasn't visible within the first 200 milliseconds
const DEFERRED_OVERLAY_TIMEOUT: c_int = 200;
const MAX_OVERLAYS: usize = 8;

pub const OverlayProjectionParams = extern struct {
    localTextureAxis: [2]Plane,
    material: ?*const Material,
    startTime: c_int,
};

pub const OverlayVertex = extern struct {
    vertexNum: c_int,
    st: [2]f16,
};

pub const Overlay = extern struct {
    surfaceNum: c_int,
    surfaceId: c_int,
    maxReferencedVertex: c_int,
    numIndexes: c_int,
    indexes: ?[*]sys_types.TriIndex,
    numVerts: c_int,
    verts: ?[*]OverlayVertex,
    material: ?*const Material,
};

pub const ModelOverlay = extern struct {
    overlays: [MAX_OVERLAYS]Overlay,
    firstOverlay: c_uint,
    nextOverlay: c_uint,

    deferredOverlays: [MAX_DEFERRED_OVERLAYS]OverlayProjectionParams,
    firstDeferredOverlay: c_uint,
    nextDeferredOverlay: c_uint,

    overlayMaterials: [MAX_OVERLAYS]?*const Material,
    numOverlayMaterials: c_uint,

    extern fn c_modelOverlay_createOverlay(
        *ModelOverlay,
        *const RenderModel,
        [*]const Plane,
        *const Material,
    ) void;
    extern fn c_modelOverlay_freeOverlay(
        *ModelOverlay,
        *Overlay,
    ) void;

    pub fn freeOverlay(model_overlay: *ModelOverlay, overlay: *Overlay) void {
        c_modelOverlay_freeOverlay(model_overlay, overlay);
    }

    pub fn createOverlay(
        overlay: *ModelOverlay,
        model: *const RenderModel,
        local_texture_axis: []const Plane,
        material: *const Material,
    ) void {
        c_modelOverlay_createOverlay(
            overlay,
            model,
            local_texture_axis.ptr,
            material,
        );
    }

    pub fn createOverlayDrawSurf(
        overlay: *ModelOverlay,
        space: *const ViewEntity,
        opt_base_model: ?*const RenderModel,
        index: usize,
        view_def: *ViewDef,
    ) ?*DrawSurface {
        if (index >= overlay.numOverlayMaterials) return null;
        const base_model = opt_base_model orelse return null;
        if (base_model.isDefaultModel() or base_model.numSurfaces() == 0) return null;
        std.debug.assert(base_model.isDynamicModel() == .DM_STATIC);

        const material = overlay.overlayMaterials[index] orelse return null;

        var max_verts: usize = 0;
        var max_indexes: usize = 0;
        const first: usize = @intCast(overlay.firstOverlay);
        const last: usize = @intCast(overlay.nextOverlay);

        for (first..last) |i| {
            const overlay_ = &overlay.overlays[i % MAX_OVERLAYS];
            if (overlay_.material == material) {
                max_verts += @intCast(overlay_.numVerts);
                max_indexes += @intCast(overlay_.numIndexes);
            }
        }

        if (max_verts == 0 or max_indexes == 0)
            return null;

        // create a new triangle surface in frame memory so it gets automatically disposed of
        const new_tri = FrameData.frameCreate(SurfaceTriangles);
        new_tri.* = std.mem.zeroes(SurfaceTriangles);
        //new_tri.numVerts = @intCast(max_verts);
        //new_tri.numIndexes = @intCast(max_indexes);
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

        const static_model: *const RenderModelStatic = @ptrCast(@alignCast(base_model));

        var num_verts: usize = 0;
        var num_indexes: usize = 0;
        for (first..last) |i| {
            const overlay_ = &overlay.overlays[i % MAX_OVERLAYS];
            if (overlay_.numVerts == 0) {
                if (i == overlay.firstOverlay) overlay.firstOverlay += 1;
                continue;
            }

            if (overlay_.material != material) continue;

            var opt_base_surf = if (overlay_.surfaceNum < base_model.numSurfaces())
                base_model.getSurface(@intCast(overlay_.surfaceNum))
            else
                null;

            const surf_id_matched = if (opt_base_surf) |base_surf|
                base_surf.id == overlay_.surfaceId
            else
                false;

            // if the surface ids no longer match
            if (opt_base_surf == null or !surf_id_matched) {
                // find the surface with the correct id
                var surface_num: usize = 0;
                if (static_model.findSurfaceWithId(@intCast(overlay_.surfaceId), &surface_num)) {
                    overlay_.surfaceNum = @intCast(surface_num);
                    opt_base_surf = base_model.getSurface(surface_num);
                } else {
                    overlay.freeOverlay(overlay_);
                    if (i == overlay.firstOverlay) overlay.firstOverlay += 1;
                    continue;
                }
            }

            const base_surf = opt_base_surf orelse continue;
            // check for out of range vertex references
            const base_tri = base_surf.geometry orelse continue;
            if (overlay_.maxReferencedVertex >= base_tri.numVerts) {
                // This can happen when playing a demofile and a model has been changed since it was recorded, so just issue a warning and go on.
                std.debug.print("overlay vertex out of range.  Model has probably changed since generating the overlay.\n", .{});
                overlay.freeOverlay(overlay_);
                if (i == overlay.firstOverlay) overlay.firstOverlay += 1;
                continue;
            }

            copyOverlaySurface(
                mapped_verts,
                num_verts,
                mapped_indexes,
                num_indexes,
                overlay_,
                base_tri.verts.?,
            );
            num_indexes += @intCast(overlay_.numIndexes);
            num_verts += @intCast(overlay_.numVerts);
        }

        new_tri.numVerts = @intCast(num_verts);
        new_tri.numIndexes = @intCast(num_indexes);

        const draw_surf = FrameData.frameCreate(DrawSurface);
        draw_surf.frontEndGeo = new_tri;
        draw_surf.numIndexes = new_tri.numIndexes;
        draw_surf.ambientCache = new_tri.ambientCache;
        draw_surf.indexCache = new_tri.indexCache;
        draw_surf.space = space;
        draw_surf.scissorRect = space.scissorRect;
        draw_surf.extraGLState = 0;

        draw_surf.setupShader(material, &space.entityDef.?.parms, view_def);
        draw_surf.setupJoints(new_tri, null);

        return draw_surf;
    }

    pub fn createDeferredOverlays(
        overlay: *ModelOverlay,
        model: *const RenderModel,
        view_def: *const ViewDef,
    ) void {
        const first: usize = @intCast(overlay.firstDeferredOverlay);
        const last: usize = @intCast(overlay.nextDeferredOverlay);
        for (first..last) |i| {
            const params = &overlay.deferredOverlays[i % MAX_DEFERRED_OVERLAYS];
            const material = params.material orelse continue;
            if (params.startTime > (view_def.renderView.time[0] - DEFERRED_OVERLAY_TIMEOUT)) {
                overlay.createOverlay(
                    model,
                    &params.localTextureAxis,
                    material,
                );
            }
        }

        overlay.firstDeferredOverlay = 0;
        overlay.nextDeferredOverlay = 0;
    }

    pub fn getNumOverlayDrawSurfs(overlay: *ModelOverlay) usize {
        overlay.numOverlayMaterials = 0;

        const first: usize = @intCast(overlay.firstOverlay);
        const last: usize = @intCast(overlay.nextOverlay);

        for (first..last) |i| {
            const overlay_ = &overlay.overlays[i % MAX_OVERLAYS];
            var j: usize = 0;
            while (j < overlay.numOverlayMaterials) : (j += 1) {
                if (overlay.overlayMaterials[j] == overlay_.material)
                    break;
            }

            if (j >= overlay.numOverlayMaterials) {
                overlay.overlayMaterials[@intCast(overlay.numOverlayMaterials)] = overlay_.material;
                overlay.numOverlayMaterials += 1;
            }
        }

        return @intCast(overlay.numOverlayMaterials);
    }
};

fn copyOverlaySurface(
    verts: [*]DrawVertex,
    num_verts: usize,
    indexes: [*]sys_types.TriIndex,
    num_indexes: usize,
    overlay: *const Overlay,
    source_verts: [*]const DrawVertex,
) void {
    // copy vertices
    for (0..@intCast(overlay.numVerts)) |i| {
        const overlay_vert = &overlay.verts.?[i];
        verts[num_verts + i] = source_verts[@intCast(overlay_vert.vertexNum)];
        verts[num_verts + i].setTexCoordNative(
            overlay_vert.st[0],
            overlay_vert.st[1],
        );
    }

    // copy indexes
    var i: usize = 0;
    while (i < overlay.numIndexes) : (i += 2) {
        std.debug.assert(overlay.indexes.?[i + 0] < overlay.numVerts and
            overlay.indexes.?[i + 1] < overlay.numVerts);
        writeIndexPair(
            &indexes[num_indexes + i],
            @intCast(num_verts + overlay.indexes.?[i + 0]),
            @intCast(num_verts + overlay.indexes.?[i + 1]),
        );
    }
}
