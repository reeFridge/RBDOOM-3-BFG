const render_entity = @import("../render_entity.zig");
const CMat3 = render_entity.CMat3;
const CVec3 = render_entity.CVec3;

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
};

pub const TraceResult = extern struct {
    fraction: f32 = 0,
    endpos: CVec3 = .{},
    endAxis: CMat3 = .{},
    c: ContactInfo = .{},
};
