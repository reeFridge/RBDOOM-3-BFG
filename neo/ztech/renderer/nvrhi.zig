pub const RefCountPtr = extern struct {
    ptr_: ?*anyopaque,
};

pub const CommandListHandle = RefCountPtr;
pub const BufferHandle = RefCountPtr;
pub const BindingLayoutHandle = RefCountPtr;
pub const IBuffer = opaque {};
pub const ICommandList = opaque {};
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
pub const IDevice = opaque {};
