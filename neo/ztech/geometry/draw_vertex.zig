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

    pub inline fn clear(draw_vertex: *DrawVertex) void {
        draw_vertex.xyz = .{};
        draw_vertex.st = .{ 0, 0 };
        const normal_ptr: *u32 = @ptrCast((&draw_vertex.normal).ptr);
        normal_ptr.* = 0x00FF8080; // x=0, y=0, z=1
        const tangent_ptr: *u32 = @ptrCast((&draw_vertex.tangent).ptr);
        tangent_ptr.* = 0xFF8080FF; // x=1, y=0, z=0
        const color_ptr: *u32 = @ptrCast((&draw_vertex.color).ptr);
        color_ptr.* = 0;
        const color2_ptr: *u32 = @ptrCast((&draw_vertex.color2).ptr);
        color2_ptr.* = 0;
    }

    pub inline fn setTexCoordS(draw_vertex: *DrawVertex, s: f32) void {
        draw_vertex.st[0] = @floatCast(s);
    }

    pub inline fn setTexCoordT(draw_vertex: *DrawVertex, t: f32) void {
        draw_vertex.st[1] = @floatCast(t);
    }

    pub inline fn setTexCoordNative(draw_vertex: *DrawVertex, s: f16, t: f16) void {
        draw_vertex.st[0] = s;
        draw_vertex.st[1] = t;
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

    pub inline fn setNativeOrderColor(draw_vertex: *DrawVertex, color: u32) void {
        const color_ptr: *u32 = @ptrCast((&draw_vertex.color).ptr);
        color_ptr.* = color;
    }

    pub inline fn clearColor2(draw_vertex: *DrawVertex) void {
        const color2_ptr: *u32 = @ptrCast((&draw_vertex.color2).ptr);
        color2_ptr.* = 0x80808080;
    }
};
