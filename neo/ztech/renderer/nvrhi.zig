const std = @import("std");

pub const IResource = opaque {
    extern fn c_nvrhi_resource_addRef(*IResource) callconv(.C) c_ulong;
    extern fn c_nvrhi_resource_release(*IResource) callconv(.C) c_ulong;

    pub fn addRef(resource: *IResource) c_ulong {
        return c_nvrhi_resource_addRef(resource);
    }

    pub fn release(resource: *IResource) c_ulong {
        return c_nvrhi_resource_release(resource);
    }
};

pub fn RefCountPtr(InterfaceType: type) type {
    return extern struct {
        const Self = @This();

        ptr_: ?*InterfaceType = null,

        pub fn init(other: ?*InterfaceType) Self {
            var ref = Self{ .ptr_ = other };
            ref.internalAddRef();
            return ref;
        }

        pub fn deinit(self: *Self) void {
            _ = self.internalRelease();
        }

        pub fn detach(self: *Self) ?*InterfaceType {
            const ptr = self.ptr_;
            self.ptr_ = null;
            return ptr;
        }

        pub fn swap(self: *Self, r: *Self) void {
            const tmp = self.ptr_;
            self.ptr_ = r.ptr_;
            r.ptr_ = tmp;
        }

        pub fn attach(self: *Self, other: *InterfaceType) void {
            if (self.ptr_) |ptr| {
                const ref = ptr.release();

                std.debug.assert(ref != 0 or @intFromPtr(ptr) != @intFromPtr(other));
            }

            self.ptr_ = other;
        }

        pub fn create(other: ?*InterfaceType) Self {
            var ref_ptr = RefCountPtr(InterfaceType){};
            ref_ptr.attach(other);
            return ref_ptr;
        }

        pub fn reset(self: *Self) c_ulong {
            return self.internalRelease();
        }

        fn internalAddRef(self: *Self) void {
            if (self.ptr_) |ptr| {
                _ = @as(*IResource, @ptrCast(ptr)).addRef();
            }
        }

        fn internalRelease(self: *Self) c_ulong {
            var ref: c_ulong = 0;

            if (self.ptr_) |ptr| {
                self.ptr_ = null;
                ref = @as(*IResource, @ptrCast(ptr)).release();
            }

            return ref;
        }
    };
}

pub const CommandListHandle = RefCountPtr(ICommandList);
pub const BufferHandle = RefCountPtr(IBuffer);
pub const BindingLayoutHandle = RefCountPtr(IBindingLayout);
pub const GraphicsPipelineHandle = RefCountPtr(IGraphicsPipeline);
pub const BindingSetHandle = RefCountPtr(IBindingSet);
pub const c_MaxBindingLayouts: usize = 5;
pub const c_MaxBindingsPerLayout: usize = 128;

pub const MipLevel = u32;
pub const ArraySlice = u32;

pub const TextureSubresourceSet = extern struct {
    baseMipLevel: MipLevel,
    numMipLevels: MipLevel,
    baseArraySlice: ArraySlice,
    numArraySlices: ArraySlice,
};

pub const BufferRange = extern struct {
    byteOffset: u64,
    byteSize: u64,
};

pub const BindingSetItem = extern struct {
    resourceHandle: ?*anyopaque,
    slot: u32,
    type: u8,
    dimension: u8,
    format: u8,
    unused: u8,
    unnamed_0: extern union {
        subresources: TextureSubresourceSet,
        range: BufferRange,
        rawData: [2]u64,
    },
};

pub const BindingSetDesc = extern struct {
    bindings: [c_MaxBindingsPerLayout]BindingSetItem,
    trackLiveness: bool,
};

pub const InputLayoutHandle = RefCountPtr(IInputLayout);
pub const ShaderHandle = RefCountPtr(IShader);
pub const DeviceHandle = RefCountPtr(IDevice);
pub const TextureHandle = RefCountPtr(ITexture);
pub const SamplerHandle = RefCountPtr(ISampler);

const ITexture = opaque {};
const ISampler = opaque {};
const IShader = opaque {};
const IInputLayout = opaque {};
const IBindingSet = opaque {};
const IGraphicsPipeline = opaque {};
const IBindingLayout = opaque {};
pub const IBuffer = opaque {};
pub const IDevice = opaque {
    extern fn c_nvrhi_device_waitForIdle(*IDevice) callconv(.C) void;
    extern fn c_nvrhi_device_executeCommandList(*IDevice, *ICommandList) callconv(.C) void;
    extern fn c_nvrhi_device_createCommandList(*IDevice, *CommandListHandle) callconv(.C) void;

    pub fn executeCommandList(device: *IDevice, command_list_ptr: *ICommandList) void {
        c_nvrhi_device_executeCommandList(device, command_list_ptr);
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createCommandList(device: *IDevice) CommandListHandle {
        var handle = CommandListHandle{};
        c_nvrhi_device_createCommandList(device, &handle);

        return handle;
    }

    pub fn waitForIdle(device: *IDevice) void {
        return c_nvrhi_device_waitForIdle(device);
    }
};

pub const ICommandList = opaque {
    extern fn c_nvrhi_commandList_open(*ICommandList) callconv(.C) void;
    extern fn c_nvrhi_commandList_close(*ICommandList) callconv(.C) void;

    pub fn open(command_list: *ICommandList) void {
        c_nvrhi_commandList_open(command_list);
    }

    pub fn close(command_list: *ICommandList) void {
        c_nvrhi_commandList_close(command_list);
    }
};
