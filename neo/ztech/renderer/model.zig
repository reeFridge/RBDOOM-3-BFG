//! @exportCVars
const std = @import("std");
const idlib = @import("../idlib.zig");
const JointMat = @import("../anim/animator.zig").JointMat;
const Bounds = @import("../bounding_volume/bounds.zig");
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const sys_types = @import("../sys/types.zig");
const VertexCacheHandle = @import("vertex_cache.zig").VertexCacheHandle;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const Material = @import("material.zig").Material;
const RenderModelManager = @import("render_model_manager.zig");
const JointHandle = @import("../anim/animator.zig").JointHandle;
const Allocator = std.mem.Allocator;
const Vec3 = @import("../math/vector.zig").Vec3;
const CVec3 = @import("../math/vector.zig").CVec3;

const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;
const CFlags = cvar.CVarFlags;

pub var r_use_sil_remap = CVar.init(
    "r_useSilRemap",
    "1",
    CFlags.renderer | CFlags.bool,
    "consider verts with the same XYZ, but different ST the same for shadows",
);

pub const DeformInfo = extern struct {
    numSourceVerts: u32,
    numOutputVerts: u32,
    verts: ?[*]align(16) DrawVertex,
    vertsAlloced: u32,
    numIndexes: u32,
    indexes: ?[*]align(16) sys_types.TriIndex,
    indexesAlloced: u32,
    silIndexes: ?[*]align(16) sys_types.TriIndex,
    silIndexesAlloced: u32,
    numMirroredVerts: u32,
    mirroredVerts: ?[*]align(16) c_int,
    mirroredVertsAlloced: u32,
    numDupVerts: u32,
    dupVerts: ?[*]align(16) c_int,
    dupVertsAlloced: u32,
    staticIndexCache: VertexCacheHandle,
    staticAmbientCache: VertexCacheHandle,

    pub fn init(allocator: Allocator) Allocator.Error!*DeformInfo {
        const deform = try allocator.create(DeformInfo);
        deform.* = std.mem.zeroes(DeformInfo);

        return deform;
    }

    pub fn deinit(deform: *DeformInfo, allocator: Allocator) void {
        if (deform.verts) |verts| {
            const verts_slice = verts[0..deform.vertsAlloced];
            allocator.free(verts_slice);
            deform.vertsAlloced = 0;
        }

        if (deform.indexes) |indexes| {
            const indexes_slice = indexes[0..deform.indexesAlloced];
            allocator.free(indexes_slice);
            deform.indexesAlloced = 0;
        }

        if (deform.silIndexes) |sil_indexes| {
            const indexes_slice = sil_indexes[0..deform.silIndexesAlloced];
            allocator.free(indexes_slice);
            deform.silIndexesAlloced = 0;
        }

        if (deform.mirroredVerts) |mirrored_verts| {
            const slice = mirrored_verts[0..deform.mirroredVertsAlloced];
            allocator.free(slice);
            deform.mirroredVertsAlloced = 0;
        }

        if (deform.dupVerts) |dup_verts| {
            const slice = dup_verts[0..deform.dupVertsAlloced];
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
    normalization_scale: [3]f32,
};

pub const SurfaceTriangles = extern struct {
    const derive_unsmoothed_bitangent = true;

    bounds: CBounds,
    generateNormals: bool,
    tangentsCalculated: bool,
    perfectHull: bool,
    referencedVerts: bool,
    referencedIndexes: bool,
    numVerts: u32,
    verts: ?[*]align(16) DrawVertex,
    vertsAlloced: u32,
    numIndexes: u32,
    indexes: ?[*]align(16) sys_types.TriIndex,
    indexesAlloced: u32,
    silIndexes: ?[*]align(16) sys_types.TriIndex, // sil = silhouette
    silIndexesAlloced: u32,
    numMirroredVerts: u32,
    mirroredVerts: ?[*]align(16) u32,
    mirroredVertsAlloced: u32,
    numDupVerts: u32,
    dupVerts: ?[*]align(16) u32,
    dupVertsAlloced: u32,
    dominantTris: ?[*]align(16) DominantTri,
    dominantTrisAlloced: u32,
    ambientSurface: [*c]SurfaceTriangles,
    nextDeferredFree: [*c]SurfaceTriangles,
    staticModelWithJoints: ?*RenderModelStatic,
    indexCache: VertexCacheHandle,
    ambientCache: VertexCacheHandle,

    extern fn R_DeriveTangentsWithoutNormals(*SurfaceTriangles, bool) void;
    extern fn R_DeriveNormalsAndTangents(*SurfaceTriangles) void;

    fn deriveTangentsWithoutNormals(tri: *SurfaceTriangles, use_mikktspace: bool) void {
        R_DeriveTangentsWithoutNormals(tri, use_mikktspace);
    }

    pub fn deriveNormalsAndTangents(tri: *SurfaceTriangles) void {
        R_DeriveNormalsAndTangents(tri);
    }

    pub fn clone(
        tri: *const SurfaceTriangles,
        allocator: Allocator,
    ) Allocator.Error!*SurfaceTriangles {
        const new_tri = try create(allocator);
        errdefer allocator.destroy(new_tri);

        const verts = try new_tri.allocVertices(allocator, tri.numVerts);
        errdefer allocator.free(verts);
        const indexes = try new_tri.allocIndexes(allocator, tri.numIndexes);
        new_tri.numVerts = tri.numVerts;
        new_tri.numIndexes = tri.numIndexes;

        @memcpy(verts, tri.constVerticesSlice());
        @memcpy(indexes, tri.constIndexesSlice());

        return new_tri;
    }

    // This is called once for static surfaces, and every frame for deforming surfaces
    // Builds tangents, normals, and face planes
    pub fn deriveTangents(tri: *SurfaceTriangles) void {
        if (tri.tangentsCalculated) return;

        if (tri.dominantTris != null) {
            tri.deriveUnsmoothedNormalsAndTangents();
        } else {
            tri.deriveNormalsAndTangents();
        }

        tri.tangentsCalculated = true;
    }

    pub fn deriveUnsmoothedNormalsAndTangents(tri: *SurfaceTriangles) void {
        std.debug.assert(tri.dominantTris != null and tri.verts != null);

        for (0..tri.numVerts) |i| {
            const dominant_tri = tri.dominantTris.?[i];
            const a = &tri.verts.?[i];
            const b = &tri.verts.?[dominant_tri.v2];
            const c = &tri.verts.?[dominant_tri.v3];

            const a_st = a.getTexCoordVec2();
            const b_st = b.getTexCoordVec2();
            const c_st = c.getTexCoordVec2();

            const d0 = b.xyz.x - a.xyz.z;
            const d1 = b.xyz.y - a.xyz.y;
            const d2 = b.xyz.z - a.xyz.z;
            const d3 = b_st.v[0] - a_st.v[0];
            const d4 = b_st.v[1] - a_st.v[1];

            const d5 = c.xyz.x - a.xyz.x;
            const d6 = c.xyz.y - a.xyz.y;
            const d7 = c.xyz.z - a.xyz.z;
            const d8 = c_st.v[0] - a_st.v[0];
            const d9 = c_st.v[1] - a_st.v[1];

            const s0 = dominant_tri.normalization_scale[0];
            const s1 = dominant_tri.normalization_scale[1];
            const s2 = dominant_tri.normalization_scale[2];

            const n0 = s2 * (d6 * d2 - d7 * d1);
            const n1 = s2 * (d7 * d0 - d5 * d2);
            const n2 = s2 * (d5 * d1 - d6 * d0);

            const t0 = s0 * (d0 * d9 - d4 * d5);
            const t1 = s0 * (d1 * d9 - d4 * d6);
            const t2 = s0 * (d2 * d9 - d4 * d7);

            var t3: f32 = undefined;
            var t4: f32 = undefined;
            var t5: f32 = undefined;
            if (derive_unsmoothed_bitangent) {
                t3 = s1 * (n2 * t1 - n1 * t2);
                t4 = s1 * (n0 * t2 - n2 * t0);
                t5 = s1 * (n1 * t0 - n0 * t1);
            } else {
                t3 = s1 * (d3 * d5 - d0 * d8);
                t4 = s1 * (d3 * d6 - d1 * d8);
                t5 = s1 * (d3 * d7 - d2 * d8);
            }

            a.setNormal(n0, n1, n2);
            a.setTangent(t0, t1, t2);
            a.setBiTangent(t3, t4, t5);
        }
    }

    pub fn reverse(tri: *SurfaceTriangles) void {
        for (tri.verticesSlice()) |*vertex| {
            vertex.setNormalVec3(
                Vec3(f32).fromScalar(0).subtract(vertex.getNormalVec3()),
            );
        }

        var i: u32 = 0;
        const indexes = tri.indexesSlice();
        while (i < tri.numIndexes) : (i += 3) {
            const temp = indexes[i + 0];
            indexes[i + 0] = indexes[i + 1];
            indexes[i + 1] = temp;
        }
    }

    fn rangeCheckIndices(tri: *const SurfaceTriangles) void {
        if (tri.numIndexes % 3 != 0) @panic("num_indexes % 3");
        for (tri.constIndexesSlice()) |index| {
            if (index >= tri.numVerts) @panic("index out of range");
        }

        // this should not be possible unless there are unused verts
        if (tri.numVerts > tri.numIndexes) @panic("numVerts > numIndexes");
    }

    fn createSilIndices(
        tri: *SurfaceTriangles,
        allocator: Allocator,
    ) Allocator.Error!void {
        tri.freeSilIndexes(allocator);
        const sil_indexes = try tri.allocSilIndexes(allocator, tri.numIndexes);
        errdefer tri.freeSilIndexes(allocator);

        const remap = try tri.createSilRemap(allocator);
        defer allocator.free(remap);

        for (tri.constIndexesSlice(), sil_indexes) |index, *sil_index| {
            sil_index.* = @intCast(remap[index]);
        }
    }

    fn createSilRemap(
        tri: *const SurfaceTriangles,
        allocator: Allocator,
    ) Allocator.Error![]u32 {
        const remap = try allocator.alloc(u32, tri.numVerts);
        errdefer allocator.free(remap);
        for (remap) |*index| index.* = 0;

        if (r_use_sil_remap.integer_value == 0) {
            for (remap, 0..) |*index, i| {
                index.* = @intCast(i);
            }
        }

        var hash = idlib.HashIndex.init(1024, tri.numVerts);
        const verts = tri.constVerticesSlice();
        for (remap, verts, 0..) |*index, *vert, i| {
            const hash_key = hash.generateKeyVec3(&CVec3.toVec3f(vert.xyz));

            var j = hash.first(hash_key);
            while (j >= 0) : (j = hash.next(@intCast(j))) {
                const uj: u32 = @intCast(j);
                const v2 = &verts[uj];
                if (v2.xyz.toVec3f().eql(vert.xyz.toVec3f())) {
                    index.* = uj;
                    break;
                }
            }

            if (j < 0) {
                index.* = @intCast(i);
                try hash.add(hash_key, @intCast(i), allocator);
            }
        }

        return remap;
    }

    fn markDegenerateTrianglesAsUnused(tri: *SurfaceTriangles) void {
        std.debug.assert(tri.silIndexes != null and tri.indexes != null);

        const sil_indexes = tri.silIndexes.?[0..tri.silIndexesAlloced];
        const indexes = tri.indexes.?[0..tri.indexesAlloced];

        var i: u32 = 0;
        while (i < tri.numIndexes) : (i += 3) {
            const a = sil_indexes[i + 0];
            const b = sil_indexes[i + 1];
            const c = sil_indexes[i + 2];

            if (a == b or a == c or b == c) {
                std.mem.copyBackwards(
                    sys_types.TriIndex,
                    indexes[i..],
                    indexes[i + 3 .. tri.numIndexes - i - 3],
                );
                std.mem.copyBackwards(
                    sys_types.TriIndex,
                    sil_indexes[i..],
                    sil_indexes[i + 3 .. tri.numIndexes - i - 3],
                );
                tri.numIndexes -= 3;
                i -= 3;
            }
        }
    }

    fn duplicateMirroredVertices(
        tri: *SurfaceTriangles,
        allocator: Allocator,
    ) Allocator.Error!void {
        std.debug.assert(tri.indexes != null);
        const indexes = tri.indexes.?[0..tri.indexesAlloced];

        const TangentVertex = struct {
            use_polarity: [2]bool = .{ false, false },
            negative_remap: u32 = 0,
        };

        const tangent_verts = try allocator.alloc(TangentVertex, tri.numVerts);
        defer allocator.free(tangent_verts);
        for (tangent_verts) |*vert| vert.* = .{};

        {
            var i: u32 = 0;
            while (i < tri.numIndexes) : (i += 3) {
                const polarity: u32 = @intFromBool(tri.faceNegativePolarity(i));
                for (0..3) |j| {
                    tangent_verts[indexes[i + j]].use_polarity[polarity] = true;
                }
            }
        }

        var total_verts = tri.numVerts;
        for (tangent_verts) |*vert| {
            if (vert.use_polarity[0] and vert.use_polarity[1]) {
                vert.negative_remap = total_verts;
                total_verts += 1;
            }
        }

        tri.numMirroredVerts = total_verts - tri.numVerts;

        if (tri.numMirroredVerts == 0) {
            tri.mirroredVerts = null;
            return;
        }

        const mirrored_verts = try tri.allocMirroredVertices(
            allocator,
            tri.numMirroredVerts,
        );
        errdefer allocator.free(mirrored_verts);
        try tri.resizeVertices(allocator, total_verts);
        const verts = tri.verts.?[0..tri.vertsAlloced];
        errdefer allocator.free(tri.verts.?[0..tri.vertsAlloced]);

        var num_mirror: u32 = 0;
        for (tangent_verts, 0..) |*vert, i| {
            const j = vert.negative_remap;
            if (j != 0) {
                verts[j] = verts[i];
                mirrored_verts[num_mirror] = @intCast(i);
                num_mirror += 1;
            }
        }
        tri.numVerts = total_verts;

        for (tri.indexesSlice(), 0..) |*index, i| {
            if (tangent_verts[index.*].negative_remap != 0 and
                tri.faceNegativePolarity(@intCast(3 * (i / 3))))
            {
                index.* = @intCast(tangent_verts[index.*].negative_remap);
            }
        }
    }

    fn faceNegativePolarity(tri: *const SurfaceTriangles, first_index: u32) bool {
        std.debug.assert(tri.verts != null and tri.indexes != null);
        const indexes = tri.constIndexesSlice();
        const verts = tri.constVerticesSlice();

        const a = verts[indexes[first_index + 0]];
        const b = verts[indexes[first_index + 1]];
        const c = verts[indexes[first_index + 2]];

        const a_st = a.getTexCoordVec2();
        const b_st = b.getTexCoordVec2();
        const c_st = c.getTexCoordVec2();

        var d0: [5]f32 = undefined;
        d0[3] = b_st.v[0] - a_st.v[0];
        d0[4] = b_st.v[1] - a_st.v[1];

        var d1: [5]f32 = undefined;
        d1[3] = c_st.v[0] - a_st.v[0];
        d1[4] = c_st.v[1] - a_st.v[1];

        const area = d0[3] * d1[4] - d0[4] * d1[3];

        return area < 0;
    }

    fn createDuplicateVertices(
        tri: *SurfaceTriangles,
        allocator: Allocator,
    ) Allocator.Error!void {
        const remap_indexes = try allocator.alloc(u32, tri.numVerts);
        defer allocator.free(remap_indexes);

        for (remap_indexes, 0..) |*index, i| {
            index.* = @intCast(i);
        }

        for (tri.indexesSlice(), tri.silIndexesSlice()) |index, sil_index| {
            remap_indexes[index] = sil_index;
        }

        const temp_dup_verts = try allocator.alignedAlloc(u32, 16, tri.numVerts * 2);
        tri.numDupVerts = 0;

        for (0..tri.numVerts) |i| {
            if (remap_indexes[i] != i) {
                temp_dup_verts[tri.numDupVerts * 2 + 0] = @intCast(i);
                temp_dup_verts[tri.numDupVerts * 2 + 1] = remap_indexes[i];
                tri.numDupVerts += 1;
            }
        }

        const dup_verts = try tri.allocDupVertices(allocator, tri.numDupVerts);
        @memcpy(dup_verts, temp_dup_verts[0 .. tri.numDupVerts * 2]);
    }

    const IndexSortElement = struct {
        vertex_num: u32,
        face_num: u32,
    };

    fn indexSort(_: void, lhs: IndexSortElement, rhs: IndexSortElement) bool {
        if (lhs.vertex_num < rhs.vertex_num) return true;
        if (lhs.vertex_num > rhs.vertex_num) return false;

        return false;
    }

    pub fn buildDominantTriangles(
        tri: *SurfaceTriangles,
        allocator: Allocator,
    ) Allocator.Error!void {
        std.debug.assert(tri.verts != null and tri.indexes != null);

        const ind = try allocator.alloc(IndexSortElement, tri.numIndexes);
        defer allocator.free(ind);

        for (ind, tri.indexesSlice(), 0..) |*index_sort, index, i| {
            index_sort.vertex_num = index;
            index_sort.face_num = @intCast(i / 3);
        }

        std.mem.sort(
            IndexSortElement,
            ind,
            {},
            indexSort,
        );

        const dominant_tris = try tri.allocDominantTris(allocator, tri.numVerts);
        errdefer allocator.free(dominant_tris);
        for (dominant_tris) |*dt| dt.* = std.mem.zeroes(DominantTri);

        const indexes = tri.indexesSlice();
        const verts = tri.verticesSlice();

        const num_indexes = tri.numIndexes;
        var i: u32 = 0;
        var j: u32 = 0;
        while (i < num_indexes) : (i += j) {
            var max_area: f32 = 0;
            const vert_num = ind[i].vertex_num;
            while (i + j < num_indexes and
                ind[i + j].vertex_num == vert_num) : (j += 1)
            {
                const @"i1" = indexes[ind[i + j].face_num * 3 + 0];
                const @"i2" = indexes[ind[i + j].face_num * 3 + 1];
                const @"i3" = indexes[ind[i + j].face_num * 3 + 2];

                const a = verts[@"i1"];
                const b = verts[@"i2"];
                const c = verts[@"i3"];

                const a_st = a.getTexCoordVec2();
                const b_st = b.getTexCoordVec2();
                const c_st = c.getTexCoordVec2();

                var d0: [5]f32 = undefined;
                d0[0] = b.xyz.x - a.xyz.x;
                d0[1] = b.xyz.y - a.xyz.y;
                d0[2] = b.xyz.z - a.xyz.z;
                d0[3] = b_st.v[0] - a_st.v[0];
                d0[4] = b_st.v[1] - a_st.v[1];

                var d1: [5]f32 = undefined;
                d1[0] = c.xyz.x - a.xyz.x;
                d1[1] = c.xyz.y - a.xyz.y;
                d1[2] = c.xyz.z - a.xyz.z;
                d1[3] = c_st.v[0] - a_st.v[0];
                d1[4] = c_st.v[1] - a_st.v[1];

                {
                    var normal: Vec3(f32) = .{};
                    normal.v[0] = d1[1] * d0[2] - d1[2] * d0[1];
                    normal.v[1] = d1[2] * d0[0] - d1[0] * d0[2];
                    normal.v[2] = d1[0] * d0[1] - d1[1] * d0[0];

                    const area = normal.lengthFast();

                    if (area < max_area) continue;
                    max_area = area;

                    if (@"i1" == vert_num) {
                        dominant_tris[vert_num].v2 = @"i2";
                        dominant_tris[vert_num].v3 = @"i3";
                    } else if (@"i2" == vert_num) {
                        dominant_tris[vert_num].v2 = @"i3";
                        dominant_tris[vert_num].v3 = @"i1";
                    } else {
                        dominant_tris[vert_num].v2 = @"i1";
                        dominant_tris[vert_num].v3 = @"i2";
                    }

                    const len = @max(0.001, area);

                    dominant_tris[vert_num].normalization_scale[2] = 1 / len;
                }

                const texture_area = d0[3] * d1[4] - d0[4] * d1[3];
                {
                    var tangent: Vec3(f32) = .{};
                    tangent.v[0] = d0[0] * d1[4] - d0[4] * d1[0];
                    tangent.v[1] = d0[1] * d1[4] - d0[4] * d1[1];
                    tangent.v[2] = d0[2] * d1[4] - d0[4] * d1[2];
                    const len = @max(0.001, tangent.lengthFast());
                    dominant_tris[vert_num].normalization_scale[0] = if (texture_area > 0)
                        1 / len
                    else
                        -1 / len;
                }

                {
                    var bitangent: Vec3(f32) = .{};
                    bitangent.v[0] = d0[3] * d1[0] - d0[0] * d1[3];
                    bitangent.v[1] = d0[3] * d1[1] - d0[1] * d1[3];
                    bitangent.v[2] = d0[3] * d1[2] - d0[2] * d1[3];
                    const len = @max(0.001, bitangent.lengthFast());

                    if (derive_unsmoothed_bitangent) {
                        dominant_tris[vert_num].normalization_scale[1] = if (texture_area > 0)
                            1
                        else
                            -1;
                    } else {
                        dominant_tris[vert_num].normalization_scale[1] = if (texture_area > 0)
                            1 / len
                        else
                            -1 / len;
                    }
                }
            }
        }
    }

    pub fn cleanup(
        tri: *SurfaceTriangles,
        create_normals: bool,
        use_unsmoothed_tangents: bool,
        use_mikktspace: bool,
        allocator: Allocator,
    ) Allocator.Error!void {
        tri.rangeCheckIndices();
        try tri.createSilIndices(allocator);
        tri.markDegenerateTrianglesAsUnused();
        try tri.duplicateMirroredVertices(allocator);
        try tri.createDuplicateVertices(allocator);
        tri.updateBoundsByVertices();

        if (use_unsmoothed_tangents) {
            try tri.buildDominantTriangles(allocator);
            tri.deriveTangents();
        } else if (!create_normals) {
            tri.deriveTangentsWithoutNormals(use_mikktspace);
        } else {
            tri.deriveTangents();
        }
    }

    pub fn updateBoundsByVertices(tri: *SurfaceTriangles) void {
        var min: @Vector(3, f32) = @splat(std.math.floatMax(f32));
        var max: @Vector(3, f32) = @splat(std.math.floatMin(f32));
        for (tri.verticesSlice()) |vertex| {
            const src_vec: @Vector(3, f32) = vertex.xyz.toVec3f().v;
            min = @min(min, src_vec);
            max = @max(max, src_vec);
        }

        tri.bounds = .{
            .b = .{ CVec3.fromVec3f(.{ .v = min }), CVec3.fromVec3f(.{ .v = max }) },
        };
    }

    pub fn constIndexesSlice(tri: *const SurfaceTriangles) []align(16) const sys_types.TriIndex {
        return if (tri.indexes) |indexes_ptr|
            indexes_ptr[0..tri.numIndexes]
        else
            &.{};
    }

    pub fn constVerticesSlice(tri: *const SurfaceTriangles) []align(16) const DrawVertex {
        return if (tri.verts) |vertices_ptr|
            vertices_ptr[0..tri.numVerts]
        else
            &.{};
    }

    pub fn silIndexesSlice(tri: *SurfaceTriangles) []align(16) sys_types.TriIndex {
        return if (tri.silIndexes) |indexes_ptr|
            indexes_ptr[0..tri.numIndexes]
        else
            &.{};
    }

    pub fn indexesSlice(tri: *SurfaceTriangles) []align(16) sys_types.TriIndex {
        return if (tri.indexes) |indexes_ptr|
            indexes_ptr[0..tri.numIndexes]
        else
            &.{};
    }

    pub fn verticesSlice(tri: *SurfaceTriangles) []align(16) DrawVertex {
        return if (tri.verts) |vertices_ptr|
            vertices_ptr[0..tri.numVerts]
        else
            &.{};
    }

    pub fn create(allocator: Allocator) Allocator.Error!*SurfaceTriangles {
        const tris = try allocator.create(SurfaceTriangles);
        tris.* = std.mem.zeroes(SurfaceTriangles);

        return tris;
    }

    pub fn deinit(tri: *SurfaceTriangles, allocator: Allocator) void {
        tri.resetSurfaceTrianglesVertexCaches();

        if (!tri.referencedVerts) {
            if (tri.verts) |verts| {
                // R_CreateLightTris points tri->verts at the verts of the ambient surface
                if (tri.ambientSurface == 0 or
                    verts != tri.ambientSurface.*.verts)
                {
                    const verts_slice = verts[0..tri.vertsAlloced];
                    allocator.free(verts_slice);
                    tri.vertsAlloced = 0;
                }
            }
        }

        if (!tri.referencedIndexes) {
            if (tri.indexes) |indexes| {
                // if a surface is completely inside a light volume R_CreateLightTris points tri->indexes at the indexes of the ambient surface
                if (@intFromPtr(tri.ambientSurface) == 0 or
                    indexes != tri.ambientSurface.*.indexes)
                {
                    const indexes_slice = indexes[0..tri.indexesAlloced];
                    allocator.free(indexes_slice);
                    tri.indexesAlloced = 0;
                }
            }

            if (tri.silIndexes) |sil_indexes| {
                const indexes_slice = sil_indexes[0..tri.silIndexesAlloced];
                allocator.free(indexes_slice);
                tri.silIndexesAlloced = 0;
            }

            if (tri.dominantTris) |dominant_tris| {
                const slice = dominant_tris[0..tri.dominantTrisAlloced];
                allocator.free(slice);
                tri.dominantTrisAlloced = 0;
            }

            if (tri.mirroredVerts) |mirrored_verts| {
                const slice = mirrored_verts[0..tri.mirroredVertsAlloced];
                allocator.free(slice);
                tri.mirroredVertsAlloced = 0;
            }

            if (tri.dupVerts) |dup_verts| {
                const slice = dup_verts[0..tri.dupVertsAlloced];
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
        tri.ambientCache = .{};
        tri.indexCache = .{};
    }

    pub fn freeVertices(tri: *SurfaceTriangles, allocator: Allocator) void {
        tri.ambientCache = .{};

        if (tri.verts) |verts| {
            // R_CreateLightTris points tri->verts at the verts of the ambient surface
            if (@intFromPtr(tri.ambientSurface) == 0 or
                verts != tri.ambientSurface.*.verts)
            {
                const verts_slice = verts[0..tri.vertsAlloced];
                allocator.free(verts_slice);
                tri.verts = null;
                tri.vertsAlloced = 0;
            }
        }
    }

    pub fn freeSilIndexes(tri: *SurfaceTriangles, allocator: Allocator) void {
        if (tri.silIndexes) |sil_indexes| {
            const indexes_slice = sil_indexes[0..tri.silIndexesAlloced];
            allocator.free(indexes_slice);
            tri.silIndexes = null;
            tri.silIndexesAlloced = 0;
        }
    }

    pub fn freeDominantTris(tri: *SurfaceTriangles, allocator: Allocator) void {
        if (tri.dominantTris) |dominant_tris| {
            const slice = dominant_tris[0..tri.dominantTrisAlloced];
            allocator.free(slice);
            tri.dominantTrisAlloced = 0;
        }
    }

    pub fn allocDupVertices(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error![]align(16) u32 {
        std.debug.assert(tris.dupVerts == null);
        const double_len = len * 2;
        const verts = try allocator.alignedAlloc(u32, 16, double_len);
        tris.dupVerts = verts.ptr;
        tris.dupVertsAlloced = @intCast(verts.len);

        return verts;
    }

    pub fn allocMirroredVertices(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error![]align(16) u32 {
        std.debug.assert(tris.mirroredVerts == null);
        const verts = try allocator.alignedAlloc(u32, 16, len);
        tris.mirroredVerts = verts.ptr;
        tris.mirroredVertsAlloced = @intCast(verts.len);

        return verts;
    }

    pub fn allocVertices(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error![]align(16) DrawVertex {
        std.debug.assert(tris.verts == null);
        const verts = try allocator.alignedAlloc(DrawVertex, 16, len);
        tris.verts = verts.ptr;
        tris.vertsAlloced = @intCast(verts.len);

        return verts;
    }

    pub fn allocIndexes(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error![]align(16) sys_types.TriIndex {
        std.debug.assert(tris.indexes == null);
        const indexes = try allocator.alignedAlloc(sys_types.TriIndex, 16, len);
        tris.indexes = indexes.ptr;
        tris.indexesAlloced = @intCast(indexes.len);

        return indexes;
    }

    pub fn allocSilIndexes(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error![]align(16) sys_types.TriIndex {
        std.debug.assert(tris.silIndexes == null);
        const indexes = try allocator.alignedAlloc(sys_types.TriIndex, 16, len);
        tris.silIndexes = indexes.ptr;
        tris.silIndexesAlloced = @intCast(indexes.len);

        return indexes;
    }

    pub fn allocDominantTris(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error![]align(16) DominantTri {
        std.debug.assert(tris.dominantTris == null);
        const dominant_tris = try allocator.alignedAlloc(DominantTri, 16, len);
        tris.dominantTris = dominant_tris.ptr;
        tris.dominantTrisAlloced = @intCast(dominant_tris.len);

        return dominant_tris;
    }

    pub fn resizeVertices(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error!void {
        std.debug.assert(tris.verts != null);
        const new_verts = try allocator.realloc(
            tris.verts.?[0..@intCast(tris.vertsAlloced)],
            len,
        );
        tris.verts = new_verts.ptr;
        tris.vertsAlloced = @intCast(new_verts.len);
    }

    pub fn resizeIndexes(
        tris: *SurfaceTriangles,
        allocator: Allocator,
        len: usize,
    ) Allocator.Error!void {
        std.debug.assert(tris.indexes != null);
        const new_indexes = try allocator.realloc(
            tris.indexes.?[0..@intCast(tris.indexesAlloced)],
            len,
        );
        tris.indexes = new_indexes.ptr;
        tris.indexesAlloced = @intCast(new_indexes.len);
    }
};

pub const ModelSurface = extern struct {
    id: u32 = undefined,
    shader: ?*const Material,
    geometry: ?*SurfaceTriangles,
};

const global = @import("../global.zig");
const RenderWorld = @import("render_world.zig");
const RenderEntity = @import("render_entity.zig").RenderEntity;

pub const DynamicModelType = enum(c_int) {
    static, // never creates a dynamic model
    cached, // once created, stays constant until the entity is updated (animating characters)
    continuous, // must be recreated for every single view (time dependent things like particles)
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
    extern fn c_renderModel_isDynamicModel(*const RenderModel) DynamicModelType;
    extern fn c_renderModel_reset(*RenderModel) void;
    extern fn c_renderModel_getJointHandle(*const RenderModel, [*]const u8) JointHandle;
    extern fn c_renderModel_modelHasShadowCastingSurfaces(*const RenderModel) bool;
    extern fn c_renderModel_modelHasInteractingSurfaces(*const RenderModel) bool;

    pub fn hasShadowCastingSurfaces(model: *const RenderModel) bool {
        return c_renderModel_modelHasShadowCastingSurfaces(model);
    }

    pub fn hasInteractingSurfaces(model: *const RenderModel) bool {
        return c_renderModel_modelHasInteractingSurfaces(model);
    }

    pub fn getJointHandle(model: *const RenderModel, joint_name: []const u8) ?JointHandle {
        const joint_handle = c_renderModel_getJointHandle(model, joint_name.ptr);
        return if (joint_handle == -1) null else joint_handle;
    }

    pub fn reset(model: *RenderModel) void {
        c_renderModel_reset(model);
    }

    pub fn initEmpty(name: []const u8) !*RenderModel {
        const allocator = global.gpa.allocator();
        const ptr = try allocator.create(RenderModelStatic);
        errdefer allocator.destroy(ptr);
        ptr.* = .{};
        const name_sentinel = try allocator.dupeZ(u8, name);
        defer allocator.free(name_sentinel);

        c_renderModel_initEmpty(@ptrCast(ptr), name_sentinel.ptr);

        return @ptrCast(ptr);
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

    pub fn isDynamicModel(model: *const RenderModel) DynamicModelType {
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

/// All model types contains it
pub const RenderModelStatic = extern struct {
    vptr: *anyopaque = undefined,
    surfaces: idlib.List(ModelSurface) = .{},
    bounds: CBounds = CBounds.fromBounds(Bounds.cleared),
    overlays_added: u32 = 0,
    num_inverted_joints: u32 = 0,
    joints_inverted: ?[*]JointMat = null,
    joints_inverted_buffer: VertexCacheHandle = .{},
    last_modified_frame: u32 = 0,
    last_archived_frame: u32 = 0,
    name: idlib.Str = idlib.Str.initStatic("<undefined>"),
    is_static_world_model: bool = false,
    defaulted: bool = false,
    purged: bool = false,
    fast_load: bool = false,
    reloadable: bool = true,
    level_load_referenced: bool = false,
    has_drawing_surfaces: bool = true,
    has_interacting_surfaces: bool = true,
    has_shadow_casting_surfaces: bool = true,
    timestamp: idlib.Time = 0,

    pub fn reset(model: *RenderModelStatic) void {
        _ = model;
    }

    pub fn getJointHandle(model: *const RenderModelStatic, joint_name: []const u8) ?JointHandle {
        _ = model;
        _ = joint_name;

        return null;
    }

    pub fn boundsFromDef(model: *const RenderModelStatic, render_entity: *const RenderEntity) CBounds {
        _ = render_entity;
        return model.bounds;
    }

    pub fn dynamicModelType(model: *const RenderModelStatic) DynamicModelType {
        _ = model;
        return .static;
    }

    pub fn initEmpty(
        model: *RenderModelStatic,
        filename: []const u8,
        allocator: Allocator,
    ) Allocator.Error!void {
        const search_str = "_area";
        const trunc_filename = filename[0..@min(filename.len, search_str.len)];

        model.is_static_world_model = std.mem.eql(u8, trunc_filename, search_str);
        try model.name.assignSlice(filename, allocator);
        model.reloadable = false; // not from a fil
        model.purge(allocator);
        model.purged = false;
        model.bounds = .{};
    }

    pub fn deinit(model: *RenderModelStatic, allocator: Allocator) void {
        model.purge(allocator);
    }

    pub fn purge(model: *RenderModelStatic, allocator: Allocator) void {
        for (model.surfaces.slice()) |*model_surface| {
            if (model_surface.geometry) |geometry| {
                geometry.deinit(allocator);
            }
        }
        model.surfaces.clear(allocator);

        if (model.joints_inverted) |joints_inverted| {
            allocator.free(joints_inverted[0..model.num_inverted_joints]);
            model.joints_inverted = null;
        }

        model.purged = true;
    }

    pub fn findSurfaceWithId(
        model: *const RenderModelStatic,
        id: usize,
        surface_num: *usize,
    ) bool {
        for (model.surfaces.constSlice(), 0..) |*surface, i| {
            if (surface.id == id) {
                surface_num.* = i;
                return true;
            }
        }

        return false;
    }

    pub fn makeDefault(
        model: *RenderModelStatic,
        default_material: *const Material,
        allocator: Allocator,
    ) Allocator.Error!void {
        model.defaulted = true;

        model.purge(allocator);

        const geometry = try SurfaceTriangles.create(allocator);
        errdefer geometry.deinit(allocator);

        const verts = try geometry.allocVertices(allocator, 24);
        const indexes = try geometry.allocIndexes(allocator, 36);

        addCubeFaceToSurfTri(
            geometry,
            verts,
            indexes,
            .{ .v = .{ -1, 1, 1 } },
            .{ .v = .{ 1, 1, 1 } },
            .{ .v = .{ 1, -1, 1 } },
            .{ .v = .{ -1, -1, 1 } },
        );

        addCubeFaceToSurfTri(
            geometry,
            verts,
            indexes,
            .{ .v = .{ -1, 1, -1 } },
            .{ .v = .{ -1, -1, -1 } },
            .{ .v = .{ 1, -1, -1 } },
            .{ .v = .{ 1, 1, -1 } },
        );

        addCubeFaceToSurfTri(
            geometry,
            verts,
            indexes,
            .{ .v = .{ 1, -1, 1 } },
            .{ .v = .{ 1, 1, 1 } },
            .{ .v = .{ 1, 1, -1 } },
            .{ .v = .{ 1, -1, -1 } },
        );

        addCubeFaceToSurfTri(
            geometry,
            verts,
            indexes,
            .{ .v = .{ -1, -1, 1 } },
            .{ .v = .{ -1, -1, -1 } },
            .{ .v = .{ -1, 1, -1 } },
            .{ .v = .{ -1, 1, 1 } },
        );

        addCubeFaceToSurfTri(
            geometry,
            verts,
            indexes,
            .{ .v = .{ -1, -1, 1 } },
            .{ .v = .{ 1, -1, 1 } },
            .{ .v = .{ 1, -1, -1 } },
            .{ .v = .{ -1, -1, -1 } },
        );

        addCubeFaceToSurfTri(
            geometry,
            verts,
            indexes,
            .{ .v = .{ -1, 1, 1 } },
            .{ .v = .{ -1, 1, -1 } },
            .{ .v = .{ 1, 1, -1 } },
            .{ .v = .{ 1, 1, 1 } },
        );

        geometry.generateNormals = true;

        try model.addSurface(.{
            .shader = default_material,
            .geometry = geometry,
        }, allocator);

        const use_mikktspace = false;
        try model.finishSurfaces(use_mikktspace, allocator);
    }

    pub fn addSurface(
        model: *RenderModelStatic,
        surface: ModelSurface,
        allocator: Allocator,
    ) Allocator.Error!void {
        _ = try model.surfaces.append(surface, allocator);
        if (surface.geometry) |geometry| {
            var b = CBounds.toBounds(model.bounds);
            _ = b.addBounds(&CBounds.toBounds(geometry.bounds));

            model.bounds = CBounds.fromBounds(b);
        }
    }

    pub fn finishSurfaces(
        model: *RenderModelStatic,
        use_mikktspace: bool,
        allocator: Allocator,
    ) Allocator.Error!void {
        model.has_drawing_surfaces = false;
        model.has_interacting_surfaces = false;
        model.has_shadow_casting_surfaces = false;
        model.purged = false;

        model.bounds = .{};

        if (model.surfaces.constSlice().len == 0) return;

        if (model.fast_load) {
            for (model.surfaces.constSlice()) |*surface| {
                if (surface.geometry) |geometry| {
                    geometry.updateBoundsByVertices();
                    var b = CBounds.toBounds(model.bounds);
                    _ = b.addBounds(&CBounds.toBounds(geometry.bounds));

                    model.bounds = CBounds.fromBounds(b);
                }
            }

            return;
        }

        for (model.surfaces.constSlice()) |*surface| {
            std.debug.assert(surface.geometry != null and surface.shader != null);
        }

        {
            const surfaces = model.surfaces.constSlice();
            for (surfaces) |*surface| {
                if (surface.shader.?.should_create_back_sides) {
                    const new_tri = try surface.geometry.?.clone(allocator);
                    errdefer new_tri.deinit(allocator);
                    new_tri.reverse();

                    try model.addSurface(.{
                        .shader = surface.shader.?,
                        .geometry = new_tri,
                    }, allocator);
                }
            }
        }

        for (model.surfaces.constSlice()) |*surface| {
            const mikktspace = use_mikktspace or surface.shader.?.mikktspace;

            try surface.geometry.?.cleanup(
                surface.geometry.?.generateNormals,
                surface.shader.?.unsmoothed_tangents,
                mikktspace,
                allocator,
            );
        }

        // TODO: add up the total surface area for development information

        for (model.surfaces.constSlice()) |*surface| {
            const shader = surface.shader.?;
            model.has_drawing_surfaces = shader.isDrawn();
            model.has_shadow_casting_surfaces = shader.surfaceCastsShadow();
            model.has_interacting_surfaces = shader.receivesLighting();
        }

        const surfaces = model.surfaces.constSlice();
        if (surfaces.len == 0) {
            model.bounds = .{};
            return;
        }

        var bounds = Bounds.cleared;
        defer model.bounds = CBounds.fromBounds(bounds);

        for (surfaces) |*surface| {
            const shader = surface.shader.?;
            const geometry = surface.geometry.?;

            if (shader.deform != .none) {
                var tri_bounds = CBounds.toBounds(geometry.bounds);
                defer geometry.bounds = CBounds.fromBounds(tri_bounds);

                const mid = tri_bounds.max.add(tri_bounds.min).scale(0.5);
                const radius = tri_bounds.min.subtract(mid).lengthFast() + 20.0;

                tri_bounds.min.v[0] = mid.v[0] - radius;
                tri_bounds.min.v[1] = mid.v[1] - radius;
                tri_bounds.min.v[2] = mid.v[2] - radius;

                tri_bounds.max.v[0] = mid.v[0] - radius;
                tri_bounds.max.v[1] = mid.v[1] - radius;
                tri_bounds.max.v[2] = mid.v[2] - radius;
            }

            _ = bounds.addBounds(&CBounds.toBounds(geometry.bounds));
        }
    }
};

fn addCubeFaceToSurfTri(
    tri: *SurfaceTriangles,
    verts: []DrawVertex,
    indexes: []sys_types.TriIndex,
    v1: Vec3(f32),
    v2: Vec3(f32),
    v3: Vec3(f32),
    v4: Vec3(f32),
) void {
    verts[tri.numVerts + 0].clear();
    verts[tri.numVerts + 0].xyz = CVec3.fromVec3f(v1.scale(8));
    verts[tri.numVerts + 0].setTexCoord(0, 0);

    verts[tri.numVerts + 1].clear();
    verts[tri.numVerts + 1].xyz = CVec3.fromVec3f(v2.scale(8));
    verts[tri.numVerts + 1].setTexCoord(1, 0);

    verts[tri.numVerts + 2].clear();
    verts[tri.numVerts + 2].xyz = CVec3.fromVec3f(v3.scale(8));
    verts[tri.numVerts + 2].setTexCoord(1, 1);

    verts[tri.numVerts + 3].clear();
    verts[tri.numVerts + 3].xyz = CVec3.fromVec3f(v4.scale(8));
    verts[tri.numVerts + 3].setTexCoord(0, 1);

    indexes[tri.numIndexes + 0] = @intCast(tri.numVerts + 0);
    indexes[tri.numIndexes + 1] = @intCast(tri.numVerts + 1);
    indexes[tri.numIndexes + 2] = @intCast(tri.numVerts + 2);
    indexes[tri.numIndexes + 3] = @intCast(tri.numVerts + 0);
    indexes[tri.numIndexes + 4] = @intCast(tri.numVerts + 2);
    indexes[tri.numIndexes + 5] = @intCast(tri.numVerts + 3);

    tri.numVerts += 4;
    tri.numIndexes += 6;
}
