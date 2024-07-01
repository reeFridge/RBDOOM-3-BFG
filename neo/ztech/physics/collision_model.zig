const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const ExternEntityHandle = @import("../global.zig").Entities.ExternEntityHandle;

pub const ContactInfo = extern struct {
    type: c_int = 0,
    point: CVec3 = .{},
    normal: CVec3 = .{},
    dist: f32 = 0,
    contents: c_int = 0,
    material: ?*anyopaque = null,
    modelFeature: c_int = 0,
    trmFeature: c_int = 0,
    entityNum: c_int = 0,
    id: c_int = 0,
    externalEntityHandle: ExternEntityHandle = undefined,
};

pub const TraceResult = extern struct {
    fraction: f32 = 0,
    endpos: CVec3 = .{},
    endAxis: CMat3 = .{},
    c: ContactInfo = .{},
};
