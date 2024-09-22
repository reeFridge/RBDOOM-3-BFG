const std = @import("std");
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const sys_types = @import("../sys/types.zig");
const VertexCacheHandle = @import("vertex_cache.zig").VertexCacheHandle;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const Material = @import("material.zig").Material;
const RenderModelManager = @import("render_model_manager.zig");
const JointHandle = @import("../anim/animator.zig").JointHandle;

pub const DeformInfo = extern struct {
    numSourceVerts: c_int,
    numOutputVerts: c_int,
    verts: ?[*]align(16) DrawVertex,
    vertsAlloced: c_uint,
    numIndexes: c_int,
    indexes: ?[*]align(16) sys_types.TriIndex,
    indexesAlloced: c_uint,
    silIndexes: ?[*]align(16) sys_types.TriIndex,
    silIndexesAlloced: c_uint,
    numMirroredVerts: c_int,
    mirroredVerts: ?[*]align(16) c_int,
    mirroredVertsAlloced: c_uint,
    numDupVerts: c_int,
    dupVerts: ?[*]align(16) c_int,
    dupVertsAlloced: c_uint,
    staticIndexCache: VertexCacheHandle,
    staticAmbientCache: VertexCacheHandle,

    pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!*DeformInfo {
        const deform = try allocator.create(DeformInfo);
        deform.* = std.mem.zeroes(DeformInfo);

        return deform;
    }

    pub fn deinit(deform: *DeformInfo, allocator: std.mem.Allocator) void {
        if (deform.verts) |verts| {
            const verts_slice = verts[0..@intCast(deform.vertsAlloced)];
            allocator.free(verts_slice);
            deform.vertsAlloced = 0;
        }

        if (deform.indexes) |indexes| {
            const indexes_slice = indexes[0..@intCast(deform.indexesAlloced)];
            allocator.free(indexes_slice);
            deform.indexesAlloced = 0;
        }

        if (deform.silIndexes) |sil_indexes| {
            const indexes_slice = sil_indexes[0..@intCast(deform.silIndexesAlloced)];
            allocator.free(indexes_slice);
            deform.silIndexesAlloced = 0;
        }

        if (deform.mirroredVerts) |mirrored_verts| {
            const slice = mirrored_verts[0..@intCast(deform.mirroredVertsAlloced)];
            allocator.free(slice);
            deform.mirroredVertsAlloced = 0;
        }

        if (deform.dupVerts) |dup_verts| {
            const slice = dup_verts[0..@intCast(deform.dupVertsAlloced)];
            allocator.free(slice);
            deform.dupVertsAlloced = 0;
        }

        deform.* = std.mem.zeroes(DeformInfo);

        allocator.destroy(deform);
    }
};

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
    vertsAlloced: c_uint,
    numIndexes: c_int,
    indexes: ?[*]align(16) sys_types.TriIndex,
    indexesAlloced: c_uint,
    silIndexes: ?[*]align(16) sys_types.TriIndex,
    silIndexesAlloced: c_uint,
    numMirroredVerts: c_int,
    mirroredVerts: ?[*]align(16) c_int,
    mirroredVertsAlloced: c_uint,
    numDupVerts: c_int,
    dupVerts: ?[*]align(16) c_int,
    dupVertsAlloced: c_uint,
    dominantTris: ?[*]align(16) DominantTri,
    dominantTrisAlloced: c_uint,
    ambientSurface: [*c]SurfaceTriangles,
    nextDeferredFree: [*c]SurfaceTriangles,
    staticModelWithJoints: ?*anyopaque,
    indexCache: VertexCacheHandle,
    ambientCache: VertexCacheHandle,

    pub fn indexesSlice(tri: *SurfaceTriangles) []align(16) sys_types.TriIndex {
        return if (tri.indexes) |indexes_ptr|
            indexes_ptr[0..@intCast(tri.numIndexes)]
        else
            &.{};
    }

    pub fn verticesSlice(tri: *SurfaceTriangles) []align(16) DrawVertex {
        return if (tri.verts) |vertices_ptr|
            vertices_ptr[0..@intCast(tri.numVerts)]
        else
            &.{};
    }

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
                    const verts_slice = verts[0..@intCast(tri.vertsAlloced)];
                    allocator.free(verts_slice);
                    tri.vertsAlloced = 0;
                }
            }
        }

        if (!tri.referencedIndexes) {
            if (tri.indexes) |indexes| {
                // if a surface is completely inside a light volume R_CreateLightTris points tri->indexes at the indexes of the ambient surface
                if (@intFromPtr(tri.ambientSurface) == 0 or indexes != tri.ambientSurface.*.indexes) {
                    const indexes_slice = indexes[0..@intCast(tri.indexesAlloced)];
                    allocator.free(indexes_slice);
                    tri.indexesAlloced = 0;
                }
            }

            if (tri.silIndexes) |sil_indexes| {
                const indexes_slice = sil_indexes[0..@intCast(tri.silIndexesAlloced)];
                allocator.free(indexes_slice);
                tri.silIndexesAlloced = 0;
            }

            if (tri.dominantTris) |dominant_tris| {
                const slice = dominant_tris[0..@intCast(tri.dominantTrisAlloced)];
                allocator.free(slice);
                tri.dominantTrisAlloced = 0;
            }

            if (tri.mirroredVerts) |mirrored_verts| {
                const slice = mirrored_verts[0..@intCast(tri.mirroredVertsAlloced)];
                allocator.free(slice);
                tri.mirroredVertsAlloced = 0;
            }

            if (tri.dupVerts) |dup_verts| {
                const slice = dup_verts[0..@intCast(tri.dupVertsAlloced)];
                allocator.free(slice);
                tri.dupVertsAlloced = 0;
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
                const verts_slice = verts[0..@intCast(tri.vertsAlloced)];
                allocator.free(verts_slice);
                tri.verts = null;
                tri.vertsAlloced = 0;
            }
        }
    }

    pub fn freeSilIndexes(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        if (tri.silIndexes) |sil_indexes| {
            const indexes_slice = sil_indexes[0..@intCast(tri.silIndexesAlloced)];
            allocator.free(indexes_slice);
            tri.silIndexes = null;
            tri.silIndexesAlloced = 0;
        }
    }

    pub fn freeDominantTris(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        if (tri.dominantTris) |dominant_tris| {
            const slice = dominant_tris[0..@intCast(tri.dominantTrisAlloced)];
            allocator.free(slice);
            tri.dominantTrisAlloced = 0;
        }
    }

    pub fn allocDupVertices(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}![]align(16) c_int {
        std.debug.assert(tris.dupVerts == null);
        const double_len = len * 2;
        const verts = try allocator.alignedAlloc(c_int, 16, double_len);
        tris.dupVerts = verts.ptr;
        tris.dupVertsAlloced = @intCast(verts.len);

        return verts;
    }

    pub fn allocMirroredVertices(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}![]align(16) c_int {
        std.debug.assert(tris.mirroredVerts == null);
        const verts = try allocator.alignedAlloc(c_int, 16, len);
        tris.mirroredVerts = verts.ptr;
        tris.mirroredVertsAlloced = @intCast(verts.len);

        return verts;
    }

    pub fn allocVertices(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}![]align(16) DrawVertex {
        std.debug.assert(tris.verts == null);
        const verts = try allocator.alignedAlloc(DrawVertex, 16, len);
        tris.verts = verts.ptr;
        tris.vertsAlloced = @intCast(verts.len);

        return verts;
    }

    pub fn allocIndexes(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}![]align(16) sys_types.TriIndex {
        std.debug.assert(tris.indexes == null);
        const indexes = try allocator.alignedAlloc(sys_types.TriIndex, 16, len);
        tris.indexes = indexes.ptr;
        tris.indexesAlloced = @intCast(indexes.len);

        return indexes;
    }

    pub fn allocSilIndexes(
        tris: *SurfaceTriangles,
        allocator: std.mem.Allocator,
        len: usize,
    ) error{OutOfMemory}![]align(16) sys_types.TriIndex {
        std.debug.assert(tris.silIndexes == null);
        const indexes = try allocator.alignedAlloc(sys_types.TriIndex, 16, len);
        tris.silIndexes = indexes.ptr;
        tris.silIndexesAlloced = @intCast(indexes.len);

        return indexes;
    }

    pub fn allocDominantTris(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}![]align(16) DominantTri {
        std.debug.assert(tris.dominantTris == null);
        const dominant_tris = try allocator.alignedAlloc(DominantTri, 16, len);
        tris.dominantTris = dominant_tris.ptr;
        tris.dominantTrisAlloced = @intCast(dominant_tris.len);

        return dominant_tris;
    }

    pub fn resizeVertices(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        std.debug.assert(tris.verts != null);
        const new_verts = try allocator.realloc(tris.verts.?[0..@intCast(tris.vertsAlloced)], len);
        tris.verts = new_verts.ptr;
        tris.vertsAlloced = @intCast(new_verts.len);
    }

    pub fn resizeIndexes(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        std.debug.assert(tris.indexes != null);
        const new_indexes = try allocator.realloc(tris.indexes.?[0..@intCast(tris.indexesAlloced)], len);
        tris.indexes = new_indexes.ptr;
        tris.indexesAlloced = @intCast(new_indexes.len);
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
    extern fn c_renderModel_reset(*RenderModel) void;
    extern fn c_renderModel_getJointHandle(*const RenderModel, [*]const u8) JointHandle;

    pub fn getJointHandle(model: *const RenderModel, joint_name: []const u8) ?JointHandle {
        const joint_handle = c_renderModel_getJointHandle(model, joint_name.ptr);
        return if (joint_handle == -1) null else joint_handle;
    }

    pub fn reset(model: *RenderModel) void {
        c_renderModel_reset(model);
    }

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
