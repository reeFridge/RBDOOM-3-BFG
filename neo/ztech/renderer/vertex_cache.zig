const nvrhi = @import("nvrhi.zig");
const FrameData = @import("frame_data.zig");
const buffer_object = @import("buffer_object.zig");
const c = @import("../sys/c_import.zig").c;

pub const VertexCacheHandle = c_ulonglong;

pub const CacheType = enum(c_int) {
    CACHE_VERTEX,
    CACHE_INDEX,
    CACHE_JOINT,
};

const INDEX_MEMORY_PER_FRAME: u32 = 31 * 1024 * 1024;
const VERTEX_MEMORY_PER_FRAME: u32 = 31 * 1024 * 1024;
const JOINT_MEMORY_PER_FRAME: u32 = 256 * 1024;

const STATIC_INDEX_MEMORY: u32 = 31 * 1024 * 1024;
const STATIC_VERTEX_MEMORY: u32 = 31 * 1024 * 1024;

pub const GeoBufferSet = extern struct {
    const InterlockedInt = c_int;
    const SysInterlockedInteger = extern struct {
        value: InterlockedInt,
    };

    indexBuffer: buffer_object.IndexBuffer,
    vertexBuffer: buffer_object.VertexBuffer,
    jointBuffer: buffer_object.UniformBuffer,
    mappedVertexBase: ?[*]u8,
    mappedIndexBase: ?[*]u8,
    mappedJointBase: ?[*]u8,
    indexMemUsed: SysInterlockedInteger,
    vertexMemUsed: SysInterlockedInteger,
    jointMemUsed: SysInterlockedInteger,
    allocations: u32,

    fn alloc(
        gbs: *GeoBufferSet,
        vertex_bytes: u32,
        index_bytes: u32,
        joint_bytes: u32,
        usage: buffer_object.BufferUsageType,
        command_list: *nvrhi.ICommandList,
        vma_allocator: c.VmaAllocator,
        device: *nvrhi.IDevice,
        buffer_device_address_enabled: bool,
    ) void {
        _ = gbs.vertexBuffer.allocBufferObject(
            null,
            vertex_bytes,
            usage,
            command_list,
            vma_allocator,
            device,
            buffer_device_address_enabled,
        );
        _ = gbs.indexBuffer.allocBufferObject(
            null,
            index_bytes,
            usage,
            command_list,
            vma_allocator,
            device,
            buffer_device_address_enabled,
        );

        if (joint_bytes > 0) {
            _ = gbs.jointBuffer.allocBufferObject(
                null,
                joint_bytes,
                usage,
                command_list,
                vma_allocator,
                device,
                buffer_device_address_enabled,
            );
        }

        gbs.clear();
    }

    fn clear(gbs: *GeoBufferSet) void {
        gbs.indexMemUsed.value = 0;
        gbs.vertexMemUsed.value = 0;
        gbs.jointMemUsed.value = 0;
        gbs.allocations = 0;
    }

    fn map(gbs: *GeoBufferSet) void {
        if (gbs.mappedVertexBase == null) {
            gbs.mappedVertexBase = gbs.vertexBuffer.mapBuffer();
        }

        if (gbs.mappedIndexBase == null) {
            gbs.mappedIndexBase = gbs.indexBuffer.mapBuffer();
        }

        if (gbs.mappedJointBase == null and gbs.jointBuffer.getAllocedSize() != 0) {
            gbs.mappedJointBase = gbs.jointBuffer.mapBuffer();
        }
    }

    fn unmap(gbs: *GeoBufferSet) void {
        if (gbs.mappedVertexBase != null) {
            gbs.vertexBuffer.unmapBuffer();
            gbs.mappedVertexBase = null;
        }

        if (gbs.mappedIndexBase != null) {
            gbs.indexBuffer.unmapBuffer();
            gbs.mappedIndexBase = null;
        }

        if (gbs.mappedJointBase != null) {
            gbs.jointBuffer.unmapBuffer();
            gbs.mappedJointBase = null;
        }
    }
};

pub const VertexCache = extern struct {
    currentFrame: u32,
    listNum: u32,
    drawListNum: u32,
    staticData: GeoBufferSet,
    frameData: [FrameData.NUM_FRAME_DATA]GeoBufferSet,
    uniformBufferOffsetAlignment: u32,
    mostUsedVertex: u32,
    mostUsedIndex: u32,
    mostUsedJoint: u32,

    extern fn c_vertexCache_cacheIsCurrent(*VertexCache, VertexCacheHandle) bool;
    extern fn c_vertexCache_allocStaticIndex(
        *VertexCache,
        *const anyopaque,
        c_int,
        *nvrhi.ICommandList,
    ) VertexCacheHandle;
    extern fn c_vertexCache_allocStaticVertex(
        *VertexCache,
        *const anyopaque,
        c_int,
        *nvrhi.ICommandList,
    ) VertexCacheHandle;
    extern fn c_vertexCache_shutdown(*VertexCache) void;
    extern fn c_vertexCache_init(*VertexCache, c_int, *nvrhi.ICommandList) void;
    extern fn c_vertexCache_beginBackend(*VertexCache) void;
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
        uniform_buffer_offset_alignment: u32,
        command_list: *nvrhi.ICommandList,
        vma_allocator: c.VmaAllocator,
        device: *nvrhi.IDevice,
        buffer_device_address_enabled: bool,
    ) void {
        vertex_cache.currentFrame = 0;
        vertex_cache.listNum = 0;

        vertex_cache.uniformBufferOffsetAlignment = uniform_buffer_offset_alignment;

        vertex_cache.mostUsedVertex = 0;
        vertex_cache.mostUsedIndex = 0;
        vertex_cache.mostUsedJoint = 0;

        for (&vertex_cache.frameData) |*frame_data| {
            frame_data.alloc(
                VERTEX_MEMORY_PER_FRAME,
                INDEX_MEMORY_PER_FRAME,
                JOINT_MEMORY_PER_FRAME,
                .DYNAMIC,
                command_list,
                vma_allocator,
                device,
                buffer_device_address_enabled,
            );
        }

        vertex_cache.staticData.alloc(
            STATIC_VERTEX_MEMORY,
            STATIC_INDEX_MEMORY,
            0,
            .STATIC,
            command_list,
            vma_allocator,
            device,
            buffer_device_address_enabled,
        );

        vertex_cache.frameData[0].map();
    }

    pub fn shutdown(vertex_cache: *VertexCache, vma_allocator: c.VmaAllocator) void {
        for (&vertex_cache.frameData) |*frame_data| {
            frame_data.vertexBuffer.freeBufferObject(vma_allocator);
            frame_data.indexBuffer.freeBufferObject(vma_allocator);
            frame_data.jointBuffer.freeBufferObject(vma_allocator);
        }

        vertex_cache.staticData.vertexBuffer.freeBufferObject(vma_allocator);
        vertex_cache.staticData.indexBuffer.freeBufferObject(vma_allocator);
        vertex_cache.staticData.jointBuffer.freeBufferObject(vma_allocator);
    }

    pub fn beginBackend(vertex_cache: *VertexCache) void {
        c_vertexCache_beginBackend(vertex_cache);
    }
};

pub const instance = @extern(*VertexCache, .{ .name = "vertexCache" });
