const nvrhi = @import("nvrhi.zig");
const FrameData = @import("frame_data.zig");
const buffer_object = @import("buffer_object.zig");
const c = @import("../sys/c_import.zig").c;

pub const VertexCacheHandle = packed struct(u64) {
    static: bool = false,
    size: u23 = 0,
    offset: u25 = 0,
    frame: u15 = 0,

    pub inline fn isDefined(h: VertexCacheHandle) bool {
        return @as(u64, @bitCast(h)) != 0;
    }
};

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
    fn InterlockedInt(IntType: type) type {
        return extern struct {
            value: IntType,
        };
    }

    index_buffer: buffer_object.IndexBuffer,
    vertex_buffer: buffer_object.VertexBuffer,
    joint_buffer: buffer_object.UniformBuffer,
    mapped_vertex_base: ?[*]u8,
    mapped_index_base: ?[*]u8,
    mapped_joint_base: ?[*]u8,
    index_mem_used: InterlockedInt(u32),
    vertex_mem_used: InterlockedInt(u32),
    joint_mem_used: InterlockedInt(u32),
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
        _ = gbs.vertex_buffer.allocBufferObject(
            null,
            vertex_bytes,
            usage,
            command_list,
            vma_allocator,
            device,
            buffer_device_address_enabled,
        );
        _ = gbs.index_buffer.allocBufferObject(
            null,
            index_bytes,
            usage,
            command_list,
            vma_allocator,
            device,
            buffer_device_address_enabled,
        );

        if (joint_bytes > 0) {
            _ = gbs.joint_buffer.allocBufferObject(
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
        gbs.index_mem_used.value = 0;
        gbs.vertex_mem_used.value = 0;
        gbs.joint_mem_used.value = 0;
        gbs.allocations = 0;
    }

    fn map(gbs: *GeoBufferSet) void {
        if (gbs.mapped_vertex_base == null) {
            gbs.mapped_vertex_base = gbs.vertex_buffer.mapBuffer();
        }

        if (gbs.mapped_index_base == null) {
            gbs.mapped_index_base = gbs.index_buffer.mapBuffer();
        }

        if (gbs.mapped_joint_base == null and gbs.joint_buffer.getAllocedSize() != 0) {
            gbs.mapped_joint_base = gbs.joint_buffer.mapBuffer();
        }
    }

    fn unmap(gbs: *GeoBufferSet) void {
        if (gbs.mapped_vertex_base != null) {
            gbs.vertex_buffer.unmapBuffer();
            gbs.mapped_vertex_base = null;
        }

        if (gbs.mapped_index_base != null) {
            gbs.index_buffer.unmapBuffer();
            gbs.mapped_index_base = null;
        }

        if (gbs.mapped_joint_base != null) {
            gbs.joint_buffer.unmapBuffer();
            gbs.mapped_joint_base = null;
        }
    }
};

pub const frame_mask: u32 = 0x7fff;

pub const VertexCache = extern struct {
    current_frame: u32,
    list_num: u32,
    draw_list_num: u32,
    static_data: GeoBufferSet,
    frame_data: [FrameData.num_frame_data]GeoBufferSet,
    uniform_buffer_offset_alignment: u32,
    most_used_vertex: u32,
    most_used_index: u32,
    most_used_joint: u32,

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
            &vertex_cache.frame_data[@intCast(vertex_cache.list_num)],
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
            &vertex_cache.frame_data[@intCast(vertex_cache.list_num)],
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
            &vertex_cache.frame_data[@intCast(vertex_cache.list_num)],
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
        vertex_cache.current_frame = 0;
        vertex_cache.list_num = 0;

        vertex_cache.uniform_buffer_offset_alignment = uniform_buffer_offset_alignment;

        vertex_cache.most_used_vertex = 0;
        vertex_cache.most_used_index = 0;
        vertex_cache.most_used_joint = 0;

        for (&vertex_cache.frame_data) |*frame_data| {
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

        vertex_cache.static_data.alloc(
            STATIC_VERTEX_MEMORY,
            STATIC_INDEX_MEMORY,
            0,
            .STATIC,
            command_list,
            vma_allocator,
            device,
            buffer_device_address_enabled,
        );

        vertex_cache.frame_data[0].map();
    }

    pub fn shutdown(vertex_cache: *VertexCache, vma_allocator: c.VmaAllocator) void {
        for (&vertex_cache.frame_data) |*frame_data| {
            frame_data.vertex_buffer.freeBufferObject(vma_allocator);
            frame_data.index_buffer.freeBufferObject(vma_allocator);
            frame_data.joint_buffer.freeBufferObject(vma_allocator);
        }

        vertex_cache.static_data.vertex_buffer.freeBufferObject(vma_allocator);
        vertex_cache.static_data.index_buffer.freeBufferObject(vma_allocator);
        vertex_cache.static_data.joint_buffer.freeBufferObject(vma_allocator);
    }

    pub fn beginBackend(vertex_cache: *VertexCache) void {
        vertex_cache.most_used_vertex = @max(
            vertex_cache.most_used_vertex,
            vertex_cache.frame_data[vertex_cache.list_num].vertex_mem_used.value,
        );
        vertex_cache.most_used_index = @max(
            vertex_cache.most_used_index,
            vertex_cache.frame_data[vertex_cache.list_num].index_mem_used.value,
        );
        vertex_cache.most_used_joint = @max(
            vertex_cache.most_used_joint,
            vertex_cache.frame_data[vertex_cache.list_num].joint_mem_used.value,
        );

        vertex_cache.frame_data[vertex_cache.list_num].unmap();
        vertex_cache.static_data.unmap();

        vertex_cache.draw_list_num = vertex_cache.list_num;
        vertex_cache.current_frame += 1;
        vertex_cache.list_num = vertex_cache.current_frame % FrameData.num_frame_data;

        vertex_cache.frame_data[vertex_cache.list_num].map();
        vertex_cache.frame_data[vertex_cache.list_num].clear();
    }
};

pub const instance = @extern(*VertexCache, .{ .name = "vertexCache" });
