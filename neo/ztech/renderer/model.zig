const std = @import("std");
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const sys_types = @import("../sys/types.zig");
const VertexCacheHandle = @import("vertex_cache.zig").VertexCacheHandle;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const Material = @import("material.zig").Material;

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
    verts: [*c]DrawVertex,
    numIndexes: c_int,
    indexes: [*c]sys_types.TriIndex,
    silIndexes: [*c]sys_types.TriIndex,
    numMirroredVerts: c_int,
    mirroredVerts: [*c]c_int,
    numDupVerts: c_int,
    dupVerts: [*c]c_int,
    dominantTris: [*c]DominantTri,
    ambientSurface: [*c]SurfaceTriangles,
    nextDeferredFree: [*c]SurfaceTriangles,
    staticModelWithJoints: ?*anyopaque,
    indexCache: VertexCacheHandle,
    ambientCache: VertexCacheHandle,

    pub fn resizeVertices(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        const new_verts = try allocator.realloc(tris.verts[0..@intCast(tris.numVerts)], len);
        tris.verts = new_verts.ptr;
        tris.numVerts = @intCast(new_verts.len);
    }

    pub fn resizeIndexes(tris: *SurfaceTriangles, allocator: std.mem.Allocator, len: usize) error{OutOfMemory}!void {
        const new_indexes = try allocator.realloc(tris.indexes[0..@intCast(tris.numIndexes)], len);
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
        const ptr = global.RenderModelManager.allocModel();
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
