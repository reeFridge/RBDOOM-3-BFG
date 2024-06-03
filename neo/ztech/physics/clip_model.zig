const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const CBounds = @import("../renderer/render_entity.zig").CBounds;
const TraceModel = @import("trace_model.zig").TraceModel;

extern fn c_checkClipModelPath([*c]const u8) callconv(.C) bool;
extern fn c_initClipModel(*anyopaque, [*c]const u8) callconv(.C) void;
extern fn c_initClipModelFromTraceModel(*anyopaque, *const TraceModel) callconv(.C) void;
extern fn c_deinitClipModel(*ClipModel) callconv(.C) void;
extern fn c_linkClipModel(*ClipModel, c_int, CVec3, CMat3) callconv(.C) void;
extern fn c_unlinkClipModel(*ClipModel) callconv(.C) void;

pub const ClipModel = extern struct {
    external: bool = true,
    enabled: bool = true,
    entity: ?*anyopaque = null,
    id: c_int = 0,
    owner: ?*anyopaque = null,
    origin: CVec3 = .{},
    axis: CMat3 = .{},
    bounds: CBounds = .{},
    absBounds: CBounds = .{},
    material: ?*anyopaque = null,
    contents: c_int = 256, // CONTENTS_BODY = BIT(8)
    collisionModelHandle: c_int = 0,
    renderModelHandle: c_int = -1,
    traceModelIndex: c_int = -1,
    clipLinks: ?*anyopaque = null,
    touchCount: c_int = -1,

    pub fn fromModel(model_path: []const u8) ?ClipModel {
        if (!c_checkClipModelPath(model_path.ptr)) return null;

        var clip_model = ClipModel{};
        c_initClipModel(&clip_model, model_path.ptr);

        return clip_model;
    }

    pub fn fromTraceModel(trace_model: *const TraceModel) ClipModel {
        var clip_model = ClipModel{};

        c_initClipModelFromTraceModel(&clip_model, trace_model);

        return clip_model;
    }

    pub fn deinit(self: *ClipModel) void {
        c_deinitClipModel(self);
    }

    pub fn unlink(self: *ClipModel) void {
        c_unlinkClipModel(self);
    }

    pub fn linkWithNewTransform(self: *ClipModel, id: c_int, origin: *const Vec3(f32), axis: *const Mat3(f32)) void {
        c_linkClipModel(self, id, CVec3.fromVec3f(origin), CMat3.fromMat3f(axis));
    }
};
