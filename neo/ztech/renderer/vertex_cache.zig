const nvrhi = @import("nvrhi.zig");

pub const VertexCacheHandle = c_ulonglong;

pub const VertexCache = opaque {
    extern fn c_vertexCache_allocStaticIndex(*VertexCache, *const anyopaque, c_int, *nvrhi.ICommandList) callconv(.C) VertexCacheHandle;
    extern fn c_vertexCache_allocStaticVertex(*VertexCache, *const anyopaque, c_int, *nvrhi.ICommandList) callconv(.C) VertexCacheHandle;
    extern fn c_vertexCache_shutdown(*VertexCache) callconv(.C) void;
    extern fn c_vertexCache_beginBackend(*VertexCache) callconv(.C) void;

    pub fn allocStaticIndex(
        vertex_cache: *VertexCache,
        data: *const anyopaque,
        bytes: usize,
        command_list: *nvrhi.ICommandList,
    ) VertexCacheHandle {
        return c_vertexCache_allocStaticIndex(
            vertex_cache,
            data,
            @intCast(bytes),
            command_list,
        );
    }

    pub fn allocStaticVertex(
        vertex_cache: *VertexCache,
        data: *const anyopaque,
        bytes: usize,
        command_list: *nvrhi.ICommandList,
    ) VertexCacheHandle {
        return c_vertexCache_allocStaticVertex(
            vertex_cache,
            data,
            @intCast(bytes),
            command_list,
        );
    }

    pub fn shutdown(vertex_cache: *VertexCache) void {
        c_vertexCache_shutdown(vertex_cache);
    }

    pub fn beginBackend(vertex_cache: *VertexCache) void {
        c_vertexCache_beginBackend(vertex_cache);
    }
};

pub const instance = @extern(*VertexCache, .{ .name = "vertexCache" });
