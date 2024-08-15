const CVec3 = @import("../math/vector.zig").CVec3;
const math = @import("../math/math.zig");

pub inline fn vertexFloatToByte(f: f32) u8 {
    return math.ftob((f + 1.0) * (255.0 / 2.0) + 0.5);
}

pub const DrawVertex = extern struct {
    xyz: CVec3,
    st: [2]f16,
    normal: [4]u8,
    tangent: [4]u8,
    color: [4]u8,
    color2: [4]u8,

    pub inline fn setTexCoordS(draw_vertex: *DrawVertex, s: f32) void {
        draw_vertex.st[0] = @floatCast(s);
    }

    pub inline fn setTexCoordT(draw_vertex: *DrawVertex, t: f32) void {
        draw_vertex.st[1] = @floatCast(t);
    }

    pub inline fn setTexCoord(draw_vertex: *DrawVertex, s: f32, t: f32) void {
        draw_vertex.setTexCoordS(s);
        draw_vertex.setTexCoordT(t);
    }

    pub inline fn setNormal(draw_vertex: *DrawVertex, x: f32, y: f32, z: f32) void {
        draw_vertex.normal[0] = vertexFloatToByte(x);
        draw_vertex.normal[1] = vertexFloatToByte(y);
        draw_vertex.normal[2] = vertexFloatToByte(z);
    }
};
