const nvrhi = @import("nvrhi.zig");
const Image = @import("image.zig").Image;

extern fn c_immediateMode_init(*nvrhi.ICommandList) callconv(.C) void;
extern fn c_immediateMode_shutdown() callconv(.C) void;

pub const GfxMode = enum(c_int) {
    GFX_INVALID_ENUM = 0x0500,
    GFX_LINES = 0x0001,
    GFX_LINE_LOOP = 0x0002,
    GFX_TRIANGLES = 0x0004,
    GFX_QUADS = 0x0007,
    GFX_QUAD_STRIP = 0x0008,
    GFX_POLYGON = 0x0009,
};

pub const ImmediateMode = extern struct {
    command_list_handle: nvrhi.CommandListHandle,
    geometry_only: bool,
    current_tex_coord: [2]f32,
    current_mode: GfxMode,
    current_color: [4]u8,
    current_texture: ?*Image,
    draw_verts_used: u32,
};

pub fn init(command_list: *nvrhi.ICommandList) void {
    c_immediateMode_init(command_list);
}

pub fn shutdown() void {
    c_immediateMode_shutdown();
}
