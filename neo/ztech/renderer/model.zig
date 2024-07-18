const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const sys_types = @import("../sys/types.zig");
const VertexCacheHandle = @import("vertex_cache.zig").VertexCacheHandle;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;

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
    ambientSurface: [*c]DominantTri,
    nextDeferredFree: [*c]DominantTri,
    staticModelWithJoints: ?*anyopaque,
    indexCache: VertexCacheHandle,
    ambientCache: VertexCacheHandle,
};

pub const ModelSurface = extern struct {
    id: c_int,
    shader: ?*const anyopaque,
    geometry: ?*SurfaceTriangles,
};

const global = @import("../global.zig");
const RenderWorld = @import("render_world.zig");

extern fn c_renderModel_initEmpty(*anyopaque, [*:0]const u8) callconv(.C) void;
extern fn c_renderModel_free(*anyopaque) callconv(.C) void;
extern fn c_renderModel_addSurface(*anyopaque, ModelSurface) callconv(.C) void;
extern fn c_renderModel_finishSurfaces(*anyopaque, bool) callconv(.C) void;
extern fn c_renderModel_numSurfaces(*const anyopaque) callconv(.C) c_int;
extern fn c_renderModel_surface(*const anyopaque, c_int) callconv(.C) [*c]ModelSurface;
extern fn c_renderModel_clearSurfaces(*anyopaque) callconv(.C) void;
extern fn c_renderModel_bounds(*const anyopaque) callconv(.C) CBounds;

pub const RenderModel = struct {
    ptr: *anyopaque,

    pub fn initEmpty(name: []const u8) !RenderModel {
        const ptr = global.RenderModelManager.allocModel();
        const allocator = global.gpa.allocator();
        const name_sentinel = try allocator.dupeZ(u8, name);
        defer allocator.free(name_sentinel);

        c_renderModel_initEmpty(ptr, name_sentinel.ptr);

        return .{
            .ptr = ptr,
        };
    }

    pub fn deinit(model: *RenderModel, render_world: *RenderWorld) void {
        const num_surfaces: usize = @intCast(c_renderModel_numSurfaces(model.ptr));
        for (0..num_surfaces) |i| {
            const surface = c_renderModel_surface(model.ptr, @intCast(i));
            if (@intFromPtr(surface) != 0) {
                render_world.destroyModelSurface(@ptrCast(surface));
            }
        }
        c_renderModel_clearSurfaces(model.ptr);

        c_renderModel_free(model.ptr);
    }

    pub fn addSurface(model: *RenderModel, surface: ModelSurface) void {
        c_renderModel_addSurface(model.ptr, surface);
    }

    pub fn finishSurfaces(model: *RenderModel, use_mikktspace: bool) void {
        c_renderModel_finishSurfaces(model.ptr, use_mikktspace);
    }

    pub fn bounds(model: RenderModel) CBounds {
        return c_renderModel_bounds(model.ptr);
    }
};
