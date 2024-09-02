const std = @import("std");
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const sys_types = @import("../sys/types.zig");
const VertexCacheHandle = @import("vertex_cache.zig").VertexCacheHandle;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const Material = @import("material.zig").Material;
const RenderModelManager = @import("render_model_manager.zig");

pub const DominantTri = extern struct {
    v2: sys_types.TriIndex,
    v3: sys_types.TriIndex,
    normalizationScale: [3]f32,
};

pub const SurfaceTriangles = extern struct {
    bounds: CBounds,
    generateNormals: bool,
    tangentsCalculated: bool,
    perfectHull: bool,
    referencedVerts: bool,
    referencedIndexes: bool,
    numVerts: c_int,
    verts: ?[*]align(16) DrawVertex,
    numIndexes: c_int,
    indexes: ?[*]align(16) sys_types.TriIndex,
    silIndexes: ?[*]align(16) sys_types.TriIndex,
    numMirroredVerts: c_int,
    mirroredVerts: ?[*]align(16) c_int,
    numDupVerts: c_int,
    dupVerts: ?[*]align(16) c_int,
    dominantTris: ?[*]align(16) DominantTri,
    ambientSurface: [*c]SurfaceTriangles,
    nextDeferredFree: [*c]SurfaceTriangles,
    staticModelWithJoints: ?*anyopaque,
    indexCache: VertexCacheHandle,
    ambientCache: VertexCacheHandle,

    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!*SurfaceTriangles {
        const tris = try allocator.create(SurfaceTriangles);
        tris.* = std.mem.zeroes(SurfaceTriangles);

        return tris;
    }

    pub fn deinit(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        tri.resetSurfaceTrianglesVertexCaches();

        if (!tri.referencedVerts) {
            if (tri.verts) |verts| {
                // R_CreateLightTris points tri->verts at the verts of the ambient surface
                if (@intFromPtr(tri.ambientSurface) == 0 or verts != tri.ambientSurface.*.verts) {
                    const verts_slice = verts[0..@intCast(tri.numVerts)];
                    allocator.free(verts_slice);
                }
            }
        }

        if (!tri.referencedIndexes) {
            if (tri.indexes) |indexes| {
                // if a surface is completely inside a light volume R_CreateLightTris points tri->indexes at the indexes of the ambient surface
                if (@intFromPtr(tri.ambientSurface) == 0 or indexes != tri.ambientSurface.*.indexes) {
                    const indexes_slice = indexes[0..@intCast(tri.numIndexes)];
                    allocator.free(indexes_slice);
                }
            }

            if (tri.silIndexes) |sil_indexes| {
                const indexes_slice = sil_indexes[0..@intCast(tri.numIndexes)];
                allocator.free(indexes_slice);
            }

            if (tri.dominantTris) |dominant_tris| {
                const slice = dominant_tris[0..@intCast(tri.numVerts)];
                allocator.free(slice);
            }

            if (tri.mirroredVerts) |mirrored_verts| {
                const slice = mirrored_verts[0..@intCast(tri.numMirroredVerts)];
                allocator.free(slice);
            }

            if (tri.dupVerts) |dup_verts| {
                const slice = dup_verts[0..@intCast(tri.numDupVerts * 2)];
                allocator.free(slice);
            }
        }

        tri.* = std.mem.zeroes(SurfaceTriangles);

        allocator.destroy(tri);
    }

    pub fn resetSurfaceTrianglesVertexCaches(tri: *SurfaceTriangles) void {
        // we don't support reclaiming static geometry memory
        // without a level change
        tri.ambientCache = 0;
        tri.indexCache = 0;
    }

    pub fn freeVertices(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        tri.ambientCache = 0;

        if (tri.verts) |verts| {
            // R_CreateLightTris points tri->verts at the verts of the ambient surface
            if (@intFromPtr(tri.ambientSurface) == 0 or verts != tri.ambientSurface.*.verts) {
                const verts_slice = verts[0..@intCast(tri.numVerts)];
                allocator.free(verts_slice);
            }
        }
    }

    pub fn allocDupVertices(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}!void {
        std.debug.assert(tris.dupVerts == null);
        const double_len = len * 2;
        const verts = try allocator.alignedAlloc(c_int, 16, double_len);
        tris.dupVerts = verts.ptr;
        tris.numDupVerts = @intCast(len);
    }

    pub fn allocMirroredVertices(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}!void {
        std.debug.assert(tris.mirroredVerts == null);
        const verts = try allocator.alignedAlloc(c_int, 16, len);
        tris.mirroredVerts = verts.ptr;
        tris.numMirroredVerts = @intCast(verts.len);
    }

    pub fn allocVertices(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}!void {
        std.debug.assert(tris.verts == null);
        const verts = try allocator.alignedAlloc(DrawVertex, 16, len);
        tris.verts = verts.ptr;
        tris.numVerts = @intCast(verts.len);
    }

    pub fn allocIndexes(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        std.debug.assert(tris.indexes == null);
        const indexes = try allocator.alignedAlloc(sys_types.TriIndex, 16, len);
        tris.indexes = indexes.ptr;
        tris.numIndexes = @intCast(indexes.len);
    }

    pub fn allocSilIndexes(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        std.debug.assert(tris.silIndexes == null);
        const indexes = try allocator.alignedAlloc(sys_types.TriIndex, 16, len);
        tris.silIndexes = indexes.ptr;
    }

    pub fn allocDominantTris(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        std.debug.assert(tris.dominantTris == null);
        const dominant_tris = try allocator.alignedAlloc(DominantTri, 16, len);
        tris.dominantTris = dominant_tris.ptr;
    }

    pub fn resizeVertices(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        std.debug.assert(tris.verts != null);
        const new_verts = try allocator.realloc(tris.verts.?[0..@intCast(tris.numVerts)], len);
        tris.verts = new_verts.ptr;
        tris.numVerts = @intCast(new_verts.len);
    }

    pub fn resizeIndexes(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        std.debug.assert(tris.indexes != null);
        const new_indexes = try allocator.realloc(tris.indexes.?[0..@intCast(tris.numIndexes)], len);
        tris.indexes = new_indexes.ptr;
        tris.numIndexes = @intCast(new_indexes.len);
    }
};

pub const ModelSurface = extern struct {
    id: c_int,
    shader: ?*const Material,
    geometry: ?*SurfaceTriangles,
};

const global = @import("../global.zig");
const RenderWorld = @import("render_world.zig");
const RenderEntity = @import("render_entity.zig").RenderEntity;

pub const DynamicModelType = struct {
    pub const DM_STATIC: c_int = 0; // never creates a dynamic model
    pub const DM_CACHED: c_int = 1; // once created, stays constant until the entity is updated (animating characters)
    pub const DM_CONTINUOUS: c_int = 2; // must be recreated for every single view (time dependent things like particles)
};

pub const RenderModel = opaque {
    extern fn c_renderModel_initEmpty(*RenderModel, [*:0]const u8) callconv(.C) void;
    extern fn c_renderModel_free(*RenderModel) callconv(.C) void;
    extern fn c_renderModel_addSurface(*RenderModel, ModelSurface) callconv(.C) void;
    extern fn c_renderModel_finishSurfaces(*RenderModel, bool) callconv(.C) void;
    extern fn c_renderModel_numSurfaces(*const RenderModel) callconv(.C) c_int;
    extern fn c_renderModel_surface(*const RenderModel, c_int) callconv(.C) [*c]ModelSurface;
    extern fn c_renderModel_clearSurfaces(*RenderModel) callconv(.C) void;
    extern fn c_renderModel_bounds(*const RenderModel) callconv(.C) CBounds;
    extern fn c_renderModel_boundsFromDef(*const RenderModel, *const RenderEntity) callconv(.C) CBounds;
    extern fn c_renderModel_modelHasDrawingSurfaces(*const RenderModel) callconv(.C) bool;
    extern fn c_renderModel_isDefaultModel(*const RenderModel) callconv(.C) bool;
    extern fn c_renderModel_isStaticWorldModel(*const RenderModel) callconv(.C) bool;
    extern fn c_renderModel_isDynamicModel(*const RenderModel) callconv(.C) c_int;

    pub fn initEmpty(name: []const u8) !*RenderModel {
        const ptr = RenderModelManager.instance.allocModel();
        const allocator = global.gpa.allocator();
        const name_sentinel = try allocator.dupeZ(u8, name);
        defer allocator.free(name_sentinel);

        c_renderModel_initEmpty(ptr, name_sentinel.ptr);

        return ptr;
    }

    pub fn deinit(model: *RenderModel, render_world: *RenderWorld) void {
        const num_surfaces: usize = @intCast(c_renderModel_numSurfaces(model));
        for (0..num_surfaces) |i| {
            if (model.getSurface(i)) |surface_ptr|
                render_world.destroyModelSurface(surface_ptr);
        }
        c_renderModel_clearSurfaces(model);
        c_renderModel_free(model);
    }

    pub fn getSurface(model: *const RenderModel, index: usize) ?*ModelSurface {
        const surface_c_ptr = c_renderModel_surface(model, @intCast(index));
        return if (surface_c_ptr) |ptr|
            @ptrCast(ptr)
        else
            null;
    }

    pub fn isDynamicModel(model: *const RenderModel) c_int {
        return c_renderModel_isDynamicModel(model);
    }

    pub fn numSurfaces(model: *const RenderModel) c_int {
        return c_renderModel_numSurfaces(model);
    }

    pub fn addSurface(model: *RenderModel, surface: ModelSurface) void {
        c_renderModel_addSurface(model, surface);
    }

    pub fn finishSurfaces(model: *RenderModel, use_mikktspace: bool) void {
        c_renderModel_finishSurfaces(model, use_mikktspace);
    }

    pub fn boundsFromDef(model: *const RenderModel, render_entity: *const RenderEntity) CBounds {
        return c_renderModel_boundsFromDef(model, render_entity);
    }

    pub fn bounds(model: *const RenderModel) CBounds {
        return c_renderModel_bounds(model);
    }

    pub fn hasDrawingSurfaces(model: *const RenderModel) bool {
        return c_renderModel_modelHasDrawingSurfaces(model);
    }

    pub fn isDefaultModel(model: *const RenderModel) bool {
        return c_renderModel_isDefaultModel(model);
    }

    pub fn isStaticWorldModel(model: *const RenderModel) bool {
        return c_renderModel_isStaticWorldModel(model);
    }
};
