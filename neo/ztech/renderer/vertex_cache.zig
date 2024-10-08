const nvrhi = @import("nvrhi.zig");
const FrameData = @import("frame_data.zig");
const idlib = @import("../idlib.zig");

const vulkan = @cImport(@cInclude("vulkan/vulkan.h"));
const vk_mem_alloc = @cImport(@cInclude("vk_mem_alloc.h"));

pub const VertexCacheHandle = c_ulonglong;

pub const BufferUsageType = enum(c_int) {
    BU_STATIC, // GPU R
    BU_DYNAMIC, // GPU R, CPU R/W
};

pub const CacheType = enum(c_int) {
    CACHE_VERTEX,
    CACHE_INDEX,
    CACHE_JOINT,
};

pub const BufferObject = extern struct {
    size: c_int,
    offsetInOtherBuffer: c_int,
    usage: BufferUsageType,
    inputLayout: nvrhi.InputLayoutHandle,
    bufferHandle: nvrhi.BufferHandle,
    buffer: ?*anyopaque,
    debugName: idlib.idStr,
    vkBuffer: vulkan.VkBuffer,
    allocation: vk_mem_alloc.VmaAllocation,
    allocationInfo: vk_mem_alloc.VmaAllocationInfo,
};

pub const IndexBuffer = extern struct {
    base: BufferObject,
};

pub const VertexBuffer = extern struct {
    base: BufferObject,
};

pub const UniformBuffer = extern struct {
    base: BufferObject,
};

pub const GeoBufferSet = extern struct {
    const InterlockedInt = c_int;
    const SysInterlockedInteger = extern struct {
        value: InterlockedInt,
    };

    indexBuffer: IndexBuffer,
    vertexBuffer: VertexBuffer,
    jointBuffer: UniformBuffer,
    mappedVertexBase: ?[*]u8,
    mappedIndexBase: ?[*]u8,
    mappedJointBase: ?[*]u8,
    indexMemUsed: SysInterlockedInteger,
    vertexMemUsed: SysInterlockedInteger,
    jointMemUsed: SysInterlockedInteger,
    alloactions: c_int,
};

pub const VertexCache = extern struct {
    currentFrame: c_int,
    listNum: c_int,
    drawListNum: c_int,
    staticData: GeoBufferSet,
    frameData: [FrameData.NUM_FRAME_DATA]GeoBufferSet,
    uniformBufferOffsetAlignment: c_int,
    mostUsedVertex: c_int,
    mostUsedIndex: c_int,
    mostUsedJoint: c_int,

    extern fn c_vertexCache_cacheIsCurrent(*VertexCache, VertexCacheHandle) bool;
    extern fn c_vertexCache_allocStaticIndex(*VertexCache, *const anyopaque, c_int, *nvrhi.ICommandList) callconv(.C) VertexCacheHandle;
    extern fn c_vertexCache_allocStaticVertex(*VertexCache, *const anyopaque, c_int, *nvrhi.ICommandList) callconv(.C) VertexCacheHandle;
    extern fn c_vertexCache_shutdown(*VertexCache) callconv(.C) void;
    extern fn c_vertexCache_init(*VertexCache, c_int, *nvrhi.ICommandList) callconv(.C) void;
    extern fn c_vertexCache_beginBackend(*VertexCache) callconv(.C) void;
    extern fn c_vertexCache_actuallyAlloc(
        *VertexCache,
        *GeoBufferSet,
        ?*const anyopaque,
        c_int,
        CacheType,
        ?*nvrhi.ICommandList,
    ) VertexCacheHandle;
    extern fn c_vertexCache_mappedVertexBuffer(*VertexCache, VertexCacheHandle) [*]u8;
    extern fn c_vertexCache_mappedIndexBuffer(*VertexCache, VertexCacheHandle) [*]u8;

    pub fn mappedVertexBuffer(
        vertex_cache: *VertexCache,
        handle: VertexCacheHandle,
    ) [*]u8 {
        return c_vertexCache_mappedVertexBuffer(vertex_cache, handle);
    }

    pub fn mappedIndexBuffer(
        vertex_cache: *VertexCache,
        handle: VertexCacheHandle,
    ) [*]u8 {
        return c_vertexCache_mappedIndexBuffer(vertex_cache, handle);
    }

    pub fn cacheIsCurrent(
        vertex_cache: *VertexCache,
        handle: VertexCacheHandle,
    ) bool {
        return c_vertexCache_cacheIsCurrent(vertex_cache, handle);
    }

    pub fn allocVertex(
        vertex_cache: *VertexCache,
        data: ?*const anyopaque,
        num: usize,
        size: usize,
        command_list: ?*nvrhi.ICommandList,
    ) VertexCacheHandle {
        return c_vertexCache_actuallyAlloc(
            vertex_cache,
            &vertex_cache.frameData[@intCast(vertex_cache.listNum)],
            data,
            @intCast(num * size),
            .CACHE_VERTEX,
            command_list,
        );
    }

    pub fn allocIndex(
        vertex_cache: *VertexCache,
        data: ?*const anyopaque,
        num: usize,
        size: usize,
        command_list: ?*nvrhi.ICommandList,
    ) VertexCacheHandle {
        return c_vertexCache_actuallyAlloc(
            vertex_cache,
            &vertex_cache.frameData[@intCast(vertex_cache.listNum)],
            data,
            @intCast(num * size),
            .CACHE_INDEX,
            command_list,
        );
    }

    pub fn allocJoint(
        vertex_cache: *VertexCache,
        data: ?*const anyopaque,
        num: usize,
        size: usize,
        command_list: ?*nvrhi.ICommandList,
    ) VertexCacheHandle {
        return c_vertexCache_actuallyAlloc(
            vertex_cache,
            &vertex_cache.frameData[@intCast(vertex_cache.listNum)],
            data,
            @intCast(num * size),
            .CACHE_JOINT,
            command_list,
        );
    }

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

    pub fn init(
        vertex_cache: *VertexCache,
        uniform_buffer_offset_alignment: usize,
        command_list: *nvrhi.ICommandList,
    ) void {
        c_vertexCache_init(
            vertex_cache,
            @intCast(uniform_buffer_offset_alignment),
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
