const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const TraceModel = @import("trace_model.zig").TraceModel;
const Entities = @import("../global.zig").Entities;
const MassProperties = @import("physics.zig").MassProperties;

extern fn c_getMassProperties(*const ClipModel, f32, *f32, *CVec3, *CMat3) callconv(.C) void;
extern fn c_checkClipModelPath([*c]const u8) callconv(.C) bool;
extern fn c_initClipModel(*anyopaque, [*c]const u8) callconv(.C) void;
extern fn c_initClipModelFromTraceModel(*anyopaque, *const TraceModel) callconv(.C) void;
extern fn c_deinitClipModel(*ClipModel) callconv(.C) void;
extern fn c_linkClipModelUpdated(*ClipModel, c_int, CVec3, CMat3) callconv(.C) void;
extern fn c_linkClipModel(*ClipModel) callconv(.C) void;
extern fn c_unlinkClipModel(*ClipModel) callconv(.C) void;

pub const ClipModelError = error{CheckNotPassed};

const ClipSector = extern struct {
    axis: c_int,
    dist: f32,
    childred: [2]?*ClipSector,
    clipLinks: ?*ClipLink,
};

const ClipLink = extern struct {
    clipModel: ?*ClipModel,
    sector: ?*ClipSector,
    prevInSector: ?*ClipLink,
    nextInSector: ?*ClipLink,
    nextLink: ?*ClipLink,
};

pub const ClipModel = extern struct {
    external: bool = true,
    externalEntityHandle: Entities.ExternEntityHandle = undefined,
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
    clipLinks: ?*ClipLink = null,
    touchCount: c_int = -1,

    pub fn fromModel(model_path: []const u8) ClipModelError!ClipModel {
        if (!c_checkClipModelPath(model_path.ptr)) return error.CheckNotPassed;

        var clip_model = ClipModel{};
        c_initClipModel(&clip_model, model_path.ptr);

        return clip_model;
    }

    pub fn fromTraceModel(trace_model: TraceModel) ClipModel {
        var clip_model = ClipModel{};

        c_initClipModelFromTraceModel(&clip_model, &trace_model);

        return clip_model;
    }

    pub fn mass_properties(self: ClipModel, density: f32) MassProperties {
        var mass: f32 = 0.0;
        var center_of_mass = CVec3{};
        var inertia_tensor = CMat3{};

        c_getMassProperties(&self, density, &mass, &center_of_mass, &inertia_tensor);

        return .{
            .mass = mass,
            .center_of_mass = center_of_mass.toVec3f(),
            .inertia_tensor = inertia_tensor.toMat3f(),
        };
    }

    pub fn deinit(self: *ClipModel) void {
        c_deinitClipModel(self);
    }

    pub fn unlink(self: *ClipModel) void {
        c_unlinkClipModel(self);
    }

    pub fn link(self: *ClipModel) void {
        c_linkClipModel(self);
    }

    pub fn linkUpdated(self: *ClipModel, origin: Vec3(f32), axis: Mat3(f32)) void {
        c_linkClipModelUpdated(self, self.id, CVec3.fromVec3f(origin), CMat3.fromMat3f(axis));
    }

    pub fn component_init(self: *ClipModel) void {
        self.link();
    }

    pub fn component_deinit(self: *ClipModel) void {
        if (self.clipLinks != null) {
            self.deinit();
        }
    }
};
