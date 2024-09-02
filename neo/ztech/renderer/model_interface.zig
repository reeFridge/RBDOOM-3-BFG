const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const DominantTri = @import("model.zig").DominantTri;
const sys_types = @import("../sys/types.zig");
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const std = @import("std");
const global = @import("../global.zig");

export fn ztech_triSurf_deinit(tris: *SurfaceTriangles) void {
    tris.deinit(global.gpa.allocator());
}

export fn ztech_triSurf_init() *SurfaceTriangles {
    return SurfaceTriangles.init(global.gpa.allocator()) catch unreachable;
}

export fn ztech_triSurf_freeVertices(tris: *SurfaceTriangles) void {
    tris.freeVertices(global.gpa.allocator());
}

export fn ztech_triSurf_allocDupVertices(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.allocDupVertices(allocator, len) catch unreachable;
}

export fn ztech_triSurf_allocMirroredVertices(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.allocMirroredVertices(allocator, len) catch unreachable;
}

export fn ztech_triSurf_allocVertices(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.allocVertices(allocator, len) catch unreachable;
}

export fn ztech_triSurf_allocIndexes(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.allocIndexes(allocator, len) catch unreachable;
}

export fn ztech_triSurf_allocSilIndexes(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.allocSilIndexes(allocator, len) catch unreachable;
}

export fn ztech_triSurf_allocDominantTris(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.allocDominantTris(allocator, len) catch unreachable;
}

export fn ztech_triSurf_resizeVertices(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.resizeVertices(allocator, len) catch unreachable;
}

export fn ztech_triSurf_resizeIndexes(
    tris: *SurfaceTriangles,
    len: usize,
) void {
    const allocator = global.gpa.allocator();
    tris.resizeIndexes(allocator, len) catch unreachable;
}
