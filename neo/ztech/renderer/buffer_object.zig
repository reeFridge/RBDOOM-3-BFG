const nvrhi = @import("nvrhi.zig");
const vulkan = @import("vulkan");
const vk_mem_alloc = @cImport(@cInclude("vk_mem_alloc.h"));
const idlib = @import("../idlib.zig");

pub const BufferUsageType = enum(c_int) {
    BU_STATIC, // GPU R
    BU_DYNAMIC, // GPU R, CPU R/W
};

pub const BufferObject = extern struct {
    size: c_int,
    offsetInOtherBuffer: c_int,
    usage: BufferUsageType,
    inputLayout: nvrhi.InputLayoutHandle,
    bufferHandle: nvrhi.BufferHandle,
    buffer: ?*anyopaque,
    debugName: idlib.idStr,
    vkBuffer: vulkan.Buffer,
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
