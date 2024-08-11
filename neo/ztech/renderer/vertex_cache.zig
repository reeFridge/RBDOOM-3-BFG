const nvrhi = @import("nvrhi.zig");

pub const VertexCacheHandle = c_ulonglong;

extern fn c_vertexCache_allocStaticIndex(*const anyopaque, c_int, *nvrhi.ICommandList) callconv(.C) VertexCacheHandle;

pub fn allocStaticIndex(data: *const anyopaque, bytes: usize, command_list: *nvrhi.ICommandList) VertexCacheHandle {
    return c_vertexCache_allocStaticIndex(data, @intCast(bytes), command_list);
}
