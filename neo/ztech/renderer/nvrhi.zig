pub const RefCountPtr = extern struct {
    extern fn c_commandListHandle_reset(*RefCountPtr) callconv(.C) c_ulong;

    ptr_: ?*anyopaque = null,

    pub fn commandList_ptr(ref: *RefCountPtr) ?*ICommandList {
        return @ptrCast(ref.ptr_);
    }

    pub fn commandListHandle_reset(ref: *RefCountPtr) c_ulong {
        return c_commandListHandle_reset(ref);
    }
};

pub const CommandListHandle = RefCountPtr;
pub const BufferHandle = RefCountPtr;
pub const BindingLayoutHandle = RefCountPtr;
pub const GraphicsPipelineHandle = RefCountPtr;
pub const BindingSetHandle = RefCountPtr;
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

pub const InputLayoutHandle = RefCountPtr;
pub const ShaderHandle = RefCountPtr;
pub const DeviceHandle = RefCountPtr;
pub const TextureHandle = RefCountPtr;
pub const SamplerHandle = RefCountPtr;

pub const IBuffer = opaque {};
pub const IDevice = opaque {
    extern fn c_device_waitForIdle(*IDevice) callconv(.C) void;
    extern fn c_device_executeCommandList(*IDevice, *ICommandList) callconv(.C) void;
    extern fn c_device_createCommandList(*IDevice) callconv(.C) *ICommandList;

    pub fn executeCommandList(device: *IDevice, command_list_ptr: *ICommandList) void {
        c_device_executeCommandList(device, command_list_ptr);
    }

    pub fn createCommandList(device: *IDevice) CommandListHandle {
        return .{ .ptr_ = c_device_createCommandList(device) };
    }

    pub fn waitForIdle(device: *IDevice) void {
        return c_device_waitForIdle(device);
    }
};

pub const ICommandList = opaque {
    extern fn c_commandList_open(*ICommandList) callconv(.C) void;
    extern fn c_commandList_close(*ICommandList) callconv(.C) void;

    pub fn open(command_list: *ICommandList) void {
        c_commandList_open(command_list);
    }

    pub fn close(command_list: *ICommandList) void {
        c_commandList_close(command_list);
    }
};
