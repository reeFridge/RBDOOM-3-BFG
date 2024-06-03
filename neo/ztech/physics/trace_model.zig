const std = @import("std");
const CVec3 = @import("../math/vector.zig").CVec3;
const CBounds = @import("../renderer/render_entity.zig").CBounds;

const MAX_TRACEMODEL_VERTS = @as(usize, 32);
const MAX_TRACEMODEL_EDGES = @as(usize, 32);
const MAX_TRACEMODEL_POLYS = @as(usize, 16);
const MAX_TRACEMODEL_POLYEDGES = @as(usize, 16);

const Edge = extern struct {
    v: [2]c_int,
    normal: CVec3,
};

const Poly = extern struct {
    normal: CVec3,
    dist: f32,
    bounds: CBounds,
    numEdges: c_int,
    edges: [MAX_TRACEMODEL_POLYEDGES]Edge,
};

pub const TraceModel = extern struct {
    type: c_int,
    numVerts: c_int,
    verts: [MAX_TRACEMODEL_VERTS]CVec3,
    numEdges: c_int,
    edges: [MAX_TRACEMODEL_EDGES + 1]Edge,
    numPolys: c_int,
    polys: [MAX_TRACEMODEL_POLYS]Poly,
    offset: CVec3,
    bounds: CBounds,
    isConvex: bool,

    pub fn fromModel(model_path: []const u8) ?TraceModel {
        var trace_model: TraceModel = std.mem.zeroes(TraceModel);

        return if (c_initTraceModelFromModel(
            model_path.ptr,
            &trace_model,
        )) trace_model else null;
    }
};

extern fn c_initTraceModelFromModel([*c]const u8, *TraceModel) callconv(.C) bool;
