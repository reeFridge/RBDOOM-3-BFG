const std = @import("std");
const nvrhi = @import("nvrhi.zig");
const vulkan = @import("vulkan");
const c = @import("../sys/c_import.zig").c;
const idlib = @import("../idlib.zig");
const vertex_cache = @import("vertex_cache.zig");
const CVec4 = @import("../math/vector.zig").CVec4;

const cvar = @import("../framework/cvar_system.zig");
const CFlags = cvar.CVarFlags;
const CVar = cvar.CVar;

pub const BufferUsageType = enum(c_int) {
    STATIC, // GPU R
    DYNAMIC, // GPU R, CPU R/W
};

pub const BufferMapType = enum(c_int) {
    READ,
    WRITE,
};

pub const BufferObjectType = enum {
    vertex,
    index,
    uniform,
};

pub const VERTEX_CACHE_ALIGN: u32 = 32;
pub const INDEX_CACHE_ALIGN: u32 = 16;

pub const UniformBuffer = BufferObject(.uniform);
pub const IndexBuffer = BufferObject(.index);
pub const VertexBuffer = BufferObject(.vertex);

pub fn BufferObject(buffer_object_type: BufferObjectType) type {
    const mapped_flag: u32 = 1 << (4 * 8 - 1);
    const owns_buffer_flag: u32 = 1 << (4 * 8 - 1);

    return extern struct {
        const Self = @This();

        pub const object_type = buffer_object_type;

        size: u32 = 0,
        offset_in_other_buffer: u32 = owns_buffer_flag,
        usage: BufferUsageType = .STATIC,
        input_layout: nvrhi.InputLayoutHandle = .{},
        buffer_handle: nvrhi.BufferHandle = .{},
        buffer: ?[*]u8 = null,
        debug_name: idlib.Str = .{},
        vk_buffer: vulkan.Buffer = .null_handle,
        allocation: c.VmaAllocation = null,
        allocation_info: c.VmaAllocationInfo = .{},

        pub fn init() Self {
            var buffer_object = Self{};
            buffer_object.setUnmapped();
        }

        pub fn getSize(buffer_object: *const Self) u32 {
            return buffer_object.size & ~mapped_flag;
        }

        pub fn getAllocedSize(buffer_object: *const Self) u32 {
            return ((buffer_object.size & ~mapped_flag) + 15) & ~@as(u32, 15);
        }

        pub fn getApiObject(buffer_object: *const Self) ?*nvrhi.IBuffer {
            return buffer_object.buffer_handle.ptr_;
        }

        pub fn getOffset(buffer_object: *const Self) u32 {
            return buffer_object.offset_in_other_buffer & ~owns_buffer_flag;
        }

        pub fn isMapped(buffer_object: *const Self) bool {
            return (buffer_object.size & mapped_flag) != 0;
        }

        pub fn setMapped(buffer_object: *Self) void {
            buffer_object.size |= mapped_flag;
        }

        pub fn setUnmapped(buffer_object: *Self) void {
            buffer_object.size &= ~mapped_flag;
        }

        pub fn ownsBuffer(buffer_object: *const Self) bool {
            return (buffer_object.offset_in_other_buffer & owns_buffer_flag) != 0;
        }

        inline fn alignment() u32 {
            return switch (object_type) {
                .vertex => VERTEX_CACHE_ALIGN,
                .uniform => vertex_cache.instance.uniformBufferOffsetAlignment,
                .index => INDEX_CACHE_ALIGN,
            };
        }

        inline fn bufferDesc(num_bytes: u32, usage: BufferUsageType) nvrhi.BufferDesc {
            return switch (object_type) {
                .vertex => .{
                    .byteSize = num_bytes,
                    .isVertexBuffer = true,
                    .initialState = .{ .CopyDest = true },
                    .cpuAccess = if (usage == .DYNAMIC) .Write else .None,
                    .keepInitialState = usage == .STATIC,
                },
                .uniform => .{
                    .initialState = .{ .CopyDest = true },
                    .canHaveTypedViews = true,
                    .canHaveRawViews = true,
                    .byteSize = num_bytes,
                    .structStride = @sizeOf(CVec4),
                    .isConstantBuffer = true,
                    .cpuAccess = if (usage == .DYNAMIC) .Write else .None,
                    .keepInitialState = usage == .STATIC,
                },
                .index => .{
                    .byteSize = num_bytes,
                    .isIndexBuffer = true,
                    .initialState = .{ .CopyDest = true },
                    .canHaveRawViews = true,
                    .canHaveTypedViews = true,
                    .format = .R16_UINT,
                    .cpuAccess = if (usage == .DYNAMIC) .Write else .None,
                    .keepInitialState = usage == .STATIC,
                },
            };
        }

        pub fn allocBufferObject(
            self: *Self,
            opt_data: ?[*]const u8,
            alloc_size: u32,
            usage: BufferUsageType,
            command_list: *nvrhi.ICommandList,
            vma_allocator: c.VmaAllocator,
            device: *nvrhi.IDevice,
            buffer_device_address_enabled: bool,
        ) bool {
            std.debug.assert(self.buffer_handle.ptr_ == null);
            if (opt_data) |data|
                std.debug.assert(std.mem.isAligned(@intFromPtr(data), 16));

            if (alloc_size == 0) @panic("alloc_size = 0");

            self.size = std.mem.alignForward(
                u32,
                alloc_size,
                alignment(),
            );
            self.usage = usage;

            self.allocBuffer(
                &bufferDesc(self.getAllocedSize(), self.usage),
                vma_allocator,
                device,
                buffer_device_address_enabled,
            );

            if (self.buffer_handle.ptr_ == null) return false;

            if (opt_data) |data| {
                self.update(data, alloc_size, 0, true, command_list);
            }

            return true;
        }

        pub fn update(
            self: *Self,
            data: [*]const u8,
            update_size: u32,
            offset: u32,
            initial_update: bool,
            command_list: *nvrhi.ICommandList,
        ) void {
            std.debug.assert(self.buffer_handle.ptr_ != null);
            const buffer_handle_ptr = self.buffer_handle.ptr_ orelse unreachable;

            std.debug.assert(std.mem.isAligned(@intFromPtr(data), 16));
            std.debug.assert((self.getOffset() & 15) == 0);
            std.debug.assert((offset & alignment() - 1) == 0);

            const num_bytes: u32 = (update_size + 15) & ~@as(u32, 15);

            if ((offset + num_bytes) > self.getSize()) {
                return;
            }

            if (self.usage == .DYNAMIC) {
                std.debug.assert(self.isMapped());

                @memcpy(
                    self.buffer.?[offset..num_bytes],
                    data[0..num_bytes],
                );
            } else {
                if (initial_update) {
                    command_list.beginTrackingBufferState(
                        buffer_handle_ptr,
                        switch (object_type) {
                            .vertex, .index => .{ .CopyDest = true },
                            .uniform => .{ .Common = true },
                        },
                    );
                    command_list.writeBuffer(
                        buffer_handle_ptr,
                        data,
                        num_bytes,
                        self.getOffset() + offset,
                    );
                    command_list.setPermanentBufferState(
                        buffer_handle_ptr,
                        switch (object_type) {
                            .vertex => .{ .VertexBuffer = true },
                            .index => .{ .IndexBuffer = true },
                            .uniform => .{ .Common = true, .ShaderResource = true },
                        },
                    );

                    if (object_type == .index) {
                        command_list.commitBarriers();
                    }
                } else {
                    command_list.writeBuffer(
                        buffer_handle_ptr,
                        data,
                        num_bytes,
                        self.getOffset() + offset,
                    );
                }
            }
        }

        fn allocBuffer(
            self: *Self,
            desc: *const nvrhi.BufferDesc,
            vma_allocator: c.VmaAllocator,
            device: *nvrhi.IDevice,
            buffer_device_address_enabled: bool,
        ) void {
            const buffer_create_info = vulkan.BufferCreateInfo{
                .size = desc.byteSize,
                .usage = pickBufferUsage(desc, buffer_device_address_enabled),
                .sharing_mode = .exclusive,
            };

            var alloc_create_info = std.mem.zeroes(c.VmaAllocationCreateInfo);
            if (self.usage == .DYNAMIC) {
                alloc_create_info.usage = c.VMA_MEMORY_USAGE_AUTO_PREFER_HOST;
                alloc_create_info.flags =
                    c.VMA_ALLOCATION_CREATE_MAPPED_BIT |
                    c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT;
            } else {
                alloc_create_info.usage = c.VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
            }

            const result = c.vmaCreateBuffer(
                vma_allocator,
                @ptrCast(&buffer_create_info),
                &alloc_create_info,
                @ptrCast(&self.vk_buffer),
                &self.allocation,
                &self.allocation_info,
            );

            std.debug.assert(result == @intFromEnum(vulkan.Result.success));

            self.buffer_handle = device.createHandleForNativeBuffer(
                nvrhi.ObjectTypes.VK_Buffer,
                .{ .u = .{ .integer = @intFromEnum(self.vk_buffer) } },
                desc,
            );
        }

        pub fn freeBufferObject(self: *Self, vma_allocator: c.VmaAllocator) void {
            if (self.isMapped()) {
                self.unmapBuffer();
            }

            if (self.ownsBuffer() == false) {
                self.clearWithoutFreeing();
                return;
            }

            if (self.buffer_handle.ptr_ == null) {
                return;
            }

            _ = self.buffer_handle.reset();

            c.vmaDestroyBuffer(
                vma_allocator,
                @ptrFromInt(@intFromEnum(self.vk_buffer)),
                self.allocation,
            );

            self.clearWithoutFreeing();
        }

        pub fn mapBuffer(self: *Self) [*]u8 {
            std.debug.assert(self.buffer_handle.ptr_ != null);
            std.debug.assert(self.usage == .DYNAMIC);
            std.debug.assert(self.isMapped() == false);

            self.buffer = @as([*]u8, @ptrCast(self.allocation_info.pMappedData.?)) + self.getOffset();
            self.setMapped();

            return self.buffer orelse @panic("buffer is null after map");
        }

        pub fn unmapBuffer(self: *Self) void {
            std.debug.assert(self.buffer_handle.ptr_ != null);
            std.debug.assert(self.usage == .DYNAMIC);
            std.debug.assert(self.isMapped());

            self.setUnmapped();
        }

        pub fn clearWithoutFreeing(self: *Self) void {
            self.size = 0;
            self.offset_in_other_buffer = owns_buffer_flag;
            _ = self.buffer_handle.reset();
            self.allocation = null;
            self.allocation_info = .{};
        }
    };
}

fn pickBufferUsage(
    desc: *const nvrhi.BufferDesc,
    buffer_device_address_enabled: bool,
) vulkan.BufferUsageFlags {
    return .{
        .transfer_src_bit = true,
        .transfer_dst_bit = true,
        .vertex_buffer_bit = desc.isVertexBuffer,
        .index_buffer_bit = desc.isVertexBuffer,
        .indirect_buffer_bit = desc.isDrawIndirectArgs,
        .uniform_buffer_bit = desc.isConstantBuffer,
        .storage_buffer_bit = desc.structStride != 0 or desc.canHaveUAVs or desc.canHaveRawViews,
        .uniform_texel_buffer_bit = desc.canHaveTypedViews,
        .storage_texel_buffer_bit = desc.canHaveTypedViews and desc.canHaveUAVs,
        .acceleration_structure_build_input_read_only_bit_khr = desc.isAccelStructBuildInput,
        .acceleration_structure_storage_bit_khr = desc.isAccelStructStorage,
        .shader_device_address_bit = buffer_device_address_enabled,
    };
}
