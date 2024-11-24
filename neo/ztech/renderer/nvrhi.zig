const std = @import("std");

pub const GraphicsAPI = enum(u8) {
    D3D11,
    D3D12,
    VULKAN,
};

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
    pub const AllMipLevels = std.math.maxInt(MipLevel);
    pub const AllArraySlices = std.math.maxInt(ArraySlice);

    baseMipLevel: MipLevel = 0,
    numMipLevels: MipLevel = 1,
    baseArraySlice: ArraySlice = 0,
    numArraySlices: ArraySlice = 1,
};

pub const AllSubresources = TextureSubresourceSet{
    .baseMipLevel = 0,
    .numMipLevels = TextureSubresourceSet.AllMipLevels,
    .baseArraySlice = 0,
    .numArraySlices = TextureSubresourceSet.AllArraySlices,
};

pub const BufferRange = extern struct {
    byteOffset: u64,
    byteSize: u64,
};

pub const BindingSetItem = extern struct {
    resourceHandle: ?*IResource,
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

pub fn static_vector(T: type, max_elements: u32) type {
    return extern struct {
        const Self = @This();

        base: [max_elements]T = undefined,
        current_size: usize = 0,

        pub fn fromSlice(comptime slice: []const T) Self {
            var base: [max_elements]T = undefined;
            inline for (base[0..slice.len], slice) |*item, in| {
                item.* = in;
            }

            return .{
                .base = base,
                .current_size = slice.len,
            };
        }
    };
}

pub const BindingSetDesc = extern struct {
    bindings: static_vector(BindingSetItem, c_MaxBindingsPerLayout),
    trackLiveness: bool,
};

pub const Color = extern struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 0,
};

pub const SamplerAddressMode = enum(u8) {
    pub const D3D = struct {
        pub const Clamp = SamplerAddressMode.ClampToEdge;
        pub const Wrap = SamplerAddressMode.Repeat;
        pub const Border = SamplerAddressMode.ClampToBorder;
        pub const Mirror = SamplerAddressMode.MirroredRepeat;
        pub const MirrorOnce = SamplerAddressMode.MirrorClampToEdge;
    };

    // Vulkan names
    ClampToEdge,
    Repeat,
    ClampToBorder,
    MirroredRepeat,
    MirrorClampToEdge,
};

pub const SamplerReductionType = enum(u8) {
    Standard,
    Comparison,
    Minimum,
    Maximum,
};

pub const SamplerDesc = extern struct {
    borderColor: Color = .{ .r = 1, .g = 1, .b = 1, .a = 1 },
    maxAnisotropy: f32 = 1,
    mipBias: f32 = 0,
    minFilter: bool = true,
    magFilter: bool = true,
    mipFilter: bool = true,
    addressU: SamplerAddressMode = .ClampToEdge,
    addressV: SamplerAddressMode = .ClampToEdge,
    addressW: SamplerAddressMode = .ClampToEdge,
    reductionType: SamplerReductionType = .Standard,
};

pub const TextureDimension = enum(u8) {
    Unknown,
    Texture1D,
    Texture1DArray,
    Texture2D,
    Texture2DArray,
    TextureCube,
    TextureCubeArray,
    Texture2DMS,
    Texture2DMSArray,
    Texture3D,
};

pub const ComponentSwizzle = enum(c_int) {
    Red,
    Green,
    Blue,
    Alpha,
    Zero,
    One,
};

pub const ComponentMapping = extern struct {
    r: ComponentSwizzle = .Red,
    g: ComponentSwizzle = .Green,
    b: ComponentSwizzle = .Blue,
    a: ComponentSwizzle = .Alpha,
};

pub const TextureDesc = extern struct {
    width: u32 = 1,
    height: u32 = 1,
    depth: u32 = 1,
    arraySize: u32 = 1,
    mipLevels: u32 = 1,
    sampleCount: u32 = 1,
    sampleQuality: u32 = 0,
    format: Format = .UNKNOWN,
    dimension: TextureDimension = .Texture2D,
    componentMapping: ComponentMapping = .{},
    debugName: CppString = std.mem.zeroes(CppString),
    isShaderResource: bool = true,
    isRenderTarget: bool = false,
    isUAV: bool = false,
    isTypeless: bool = false,
    isShadingRateSurface: bool = false,
    sharedResourceFlags: SharedResourceFlags = .None,
    isVirtual: bool = false,
    clearValue: Color = .{},
    useClearValue: bool = false,
    initialState: ResourceStates = .Unknown,
    keepInitialState: bool = false,
    padding_: [7]u8 = undefined,
};

pub const Format = enum(u8) {
    UNKNOWN,
    R8_UINT,
    R8_SINT,
    R8_UNORM,
    R8_SNORM,
    RG8_UINT,
    RG8_SINT,
    RG8_UNORM,
    RG8_SNORM,
    R16_UINT,
    R16_SINT,
    R16_UNORM,
    R16_SNORM,
    R16_FLOAT,
    BGRA4_UNORM,
    B5G6R5_UNORM,
    B5G5R5A1_UNORM,
    RGBA8_UINT,
    RGBA8_SINT,
    RGBA8_UNORM,
    RGBA8_SNORM,
    BGRA8_UNORM,
    SRGBA8_UNORM,
    SBGRA8_UNORM,
    R10G10B10A2_UNORM,
    R11G11B10_FLOAT,
    RG16_UINT,
    RG16_SINT,
    RG16_UNORM,
    RG16_SNORM,
    RG16_FLOAT,
    R32_UINT,
    R32_SINT,
    R32_FLOAT,
    RGBA16_UINT,
    RGBA16_SINT,
    RGBA16_FLOAT,
    RGBA16_UNORM,
    RGBA16_SNORM,
    RG32_UINT,
    RG32_SINT,
    RG32_FLOAT,
    RGB32_UINT,
    RGB32_SINT,
    RGB32_FLOAT,
    RGBA32_UINT,
    RGBA32_SINT,
    RGBA32_FLOAT,
    D16,
    D24S8,
    X24G8_UINT,
    D32,
    D32S8,
    X32G8_UINT,
    BC1_UNORM,
    BC1_UNORM_SRGB,
    BC2_UNORM,
    BC2_UNORM_SRGB,
    BC3_UNORM,
    BC3_UNORM_SRGB,
    BC4_UNORM,
    BC4_SNORM,
    BC5_UNORM,
    BC5_SNORM,
    BC6H_UFLOAT,
    BC6H_SFLOAT,
    BC7_UNORM,
    BC7_UNORM_SRGB,
    COUNT,
};

pub const FormatKind = enum(u8) {
    Integer,
    Normalized,
    Float,
    DepthStencil,
};

pub const FormatInfo = extern struct {
    format: Format,
    name: [*:0]const u8,
    bytesPerBlock: u8,
    blockSize: u8,
    kind: FormatKind,
    hasRed: bool,
    hasGreen: bool,
    hasBlue: bool,
    hasAlpha: bool,
    hasDepth: bool,
    hasStencil: bool,
    isSigned: bool,
    isSRGB: bool,
};

extern fn c_nvrhi_getFormatInfo(Format) *const FormatInfo;
pub fn getFormatInfo(format: Format) FormatInfo {
    return c_nvrhi_getFormatInfo(format).*;
}

const CppString = [24]u8;

pub const VertexAttributeDesc = extern struct {
    name: CppString = std.mem.zeroes([24]u8),
    format: Format = .UNKNOWN,
    arraySize: u32 = 1,
    bufferIndex: u32 = 0,
    offset: u32 = 0,
    elementStride: u32 = 0,
    isInstanced: bool = false,

    extern fn c_nvrhi_vertexAttributeDesc_setName(*VertexAttributeDesc, [*:0]const u8) void;
    extern fn c_nvrhi_vertexAttributeDesc_getName(*const VertexAttributeDesc) [*:0]const u8;

    pub fn setName(desc: *VertexAttributeDesc, name: [:0]const u8) void {
        c_nvrhi_vertexAttributeDesc_setName(desc, name.ptr);
    }

    pub fn getName(desc: *const VertexAttributeDesc) [:0]const u8 {
        return std.mem.span(c_nvrhi_vertexAttributeDesc_getName(desc));
    }
};

pub const ResourceType = enum(u8) {
    None,
    Texture_SRV,
    Texture_UAV,
    TypedBuffer_SRV,
    TypedBuffer_UAV,
    StructuredBuffer_SRV,
    StructuredBuffer_UAV,
    RawBuffer_SRV,
    RawBuffer_UAV,
    ConstantBuffer,
    VolatileConstantBuffer,
    Sampler,
    RayTracingAccelStruct,
    PushConstants,
    Count,
};

pub const BindingLayoutItem = extern struct {
    slot: u32,
    type: ResourceType,
    unused: u8 = 0,
    size: u16 = 0,

    comptime {
        std.debug.assert(@sizeOf(BindingLayoutItem) == 8);
    }
};

pub const BindingLayoutItemArray = static_vector(BindingLayoutItem, c_MaxBindingsPerLayout);

pub const VulkanBindingOffsets = extern struct {
    shaderResource: u32 = 0,
    sampler: u32 = 128,
    constantBuffer: u32 = 256,
    unorderedAccess: u32 = 384,
};

pub const ShaderType = enum(u16) {
    None = 0x0000,
    Compute = 0x0020,
    Vertex = 0x0001,
    Hull = 0x0002,
    Domain = 0x0004,
    Geometry = 0x0008,
    Pixel = 0x0010,
    Amplification = 0x0040,
    Mesh = 0x0080,
    AllGraphics = 0x00FE,
    RayGeneration = 0x0100,
    AnyHit = 0x0200,
    ClosestHit = 0x0400,
    Miss = 0x0800,
    Intersection = 0x1000,
    Callable = 0x2000,
    AllRayTracing = 0x3F00,
    All = 0x3FFF,
};

pub const CustomSemantic = extern struct {
    const Type = enum(c_int) {
        Undefined = 0,
        XRight = 1,
        ViewportMask = 2,
    };

    type: Type,
    name: CppString,
};

pub const FastGeometryShaderFlags = enum(u8) {
    ForceFastGS = 0x01,
    UseViewportMask = 0x02,
    OffsetTargetIndexByViewportIndex = 0x04,
    StrictApiOrder = 0x08,
};

pub const ShaderDesc = extern struct {
    shaderType: ShaderType = .None,
    debugName: CppString = std.mem.zeroes(CppString),
    entryName: CppString = std.mem.zeroes(CppString),
    hlslExtensionsUAV: c_int = -1,
    useSpecificShaderExt: bool = false,
    numCustomSemantics: u32 = 0,
    pCustomSemantics: ?*CustomSemantic = null,
    fastGSFlags: @typeInfo(FastGeometryShaderFlags).Enum.tag_type = 0,
    pCoordinateSwizzling: ?*u32 = null,
};

pub const BindingLayoutDesc = extern struct {
    visibility: ShaderType = .None,
    registerSpace: u32 = 0,
    registerSpaceIsDescriptorSet: bool = false,
    bindings: BindingLayoutItemArray = .{},
    bindingOffsets: VulkanBindingOffsets = .{},
};

pub const ObjectType = u32;

pub const ObjectTypes = struct {
    pub const SharedHandle: ObjectType = 0x00000001;

    pub const D3D11_Device: ObjectType = 0x00010001;
    pub const D3D11_DeviceContext: ObjectType = 0x00010002;
    pub const D3D11_Resource: ObjectType = 0x00010003;
    pub const D3D11_Buffer: ObjectType = 0x00010004;
    pub const D3D11_RenderTargetView: ObjectType = 0x00010005;
    pub const D3D11_DepthStencilView: ObjectType = 0x00010006;
    pub const D3D11_ShaderResourceView: ObjectType = 0x00010007;
    pub const D3D11_UnorderedAccessView: ObjectType = 0x00010008;

    pub const D3D12_Device: ObjectType = 0x00020001;
    pub const D3D12_CommandQueue: ObjectType = 0x00020002;
    pub const D3D12_GraphicsCommandList: ObjectType = 0x00020003;
    pub const D3D12_Resource: ObjectType = 0x00020004;
    pub const D3D12_RenderTargetViewDescriptor: ObjectType = 0x00020005;
    pub const D3D12_DepthStencilViewDescriptor: ObjectType = 0x00020006;
    pub const D3D12_ShaderResourceViewGpuDescripror: ObjectType = 0x00020007;
    pub const D3D12_UnorderedAccessViewGpuDescripror: ObjectType = 0x00020008;
    pub const D3D12_RootSignature: ObjectType = 0x00020009;
    pub const D3D12_PipelineState: ObjectType = 0x0002000a;
    pub const D3D12_CommandAllocator: ObjectType = 0x0002000b;

    pub const VK_Device: ObjectType = 0x00030001;
    pub const VK_PhysicalDevice: ObjectType = 0x00030002;
    pub const VK_Instance: ObjectType = 0x00030003;
    pub const VK_Queue: ObjectType = 0x00030004;
    pub const VK_CommandBuffer: ObjectType = 0x00030005;
    pub const VK_DeviceMemory: ObjectType = 0x00030006;
    pub const VK_Buffer: ObjectType = 0x00030007;
    pub const VK_Image: ObjectType = 0x00030008;
    pub const VK_ImageView: ObjectType = 0x00030009;
    pub const VK_AccelerationStructureKHR: ObjectType = 0x0003000a;
    pub const VK_Sampler: ObjectType = 0x0003000b;
    pub const VK_ShaderModule: ObjectType = 0x0003000c;
    pub const VK_RenderPass: ObjectType = 0x0003000d;
    pub const VK_Framebuffer: ObjectType = 0x0003000e;
    pub const VK_DescriptorPool: ObjectType = 0x0003000f;
    pub const VK_DescriptorSetLayout: ObjectType = 0x00030010;
    pub const VK_DescriptorSet: ObjectType = 0x00030011;
    pub const VK_PipelineLayout: ObjectType = 0x00030012;
    pub const VK_Pipeline: ObjectType = 0x00030013;
    pub const VK_Micromap: ObjectType = 0x00030014;
};

pub const Object = extern struct {
    u: extern union {
        integer: u64,
        pointer: ?*anyopaque,
    },
};

pub const InputLayoutHandle = RefCountPtr(IInputLayout);
pub const ShaderHandle = RefCountPtr(IShader);
pub const DeviceHandle = RefCountPtr(IDevice);
pub const TextureHandle = RefCountPtr(ITexture);
pub const SamplerHandle = RefCountPtr(ISampler);
pub const FramebufferHandle = RefCountPtr(IFramebuffer);
pub const EventQueryHandle = RefCountPtr(IEventQuery);

pub const IEventQuery = opaque {};
pub const ITexture = opaque {};
pub const ISampler = opaque {};
pub const IShader = opaque {};
pub const IFramebuffer = opaque {};
pub const IInputLayout = opaque {};
pub const IBindingSet = opaque {};
pub const IGraphicsPipeline = opaque {};
pub const IBindingLayout = opaque {};
pub const IBuffer = opaque {};
pub const IDevice = opaque {
    extern fn c_nvrhi_device_createHandleForNativeTexture(
        *IDevice,
        *TextureHandle,
        ObjectType,
        Object,
        *const TextureDesc,
    ) void;
    extern fn c_nvrhi_device_runGarbageCollection(*IDevice) callconv(.C) void;
    extern fn c_nvrhi_device_waitForIdle(*IDevice) callconv(.C) void;
    extern fn c_nvrhi_device_executeCommandList(*IDevice, *ICommandList) callconv(.C) void;
    extern fn c_nvrhi_device_createCommandList(
        *IDevice,
        *CommandListHandle,
        CommandListParameters,
    ) void;
    extern fn c_nvrhi_device_createEventQuery(*IDevice, *EventQueryHandle) void;
    extern fn c_nvrhi_device_setEventQuery(*IDevice, *IEventQuery, CommandQueue) void;
    extern fn c_nvrhi_device_createBuffer(
        *IDevice,
        *BufferHandle,
        *const BufferDesc,
    ) void;
    extern fn c_nvrhi_device_createShader(
        *IDevice,
        *ShaderHandle,
        *const ShaderDesc,
        *const anyopaque,
        usize,
    ) void;
    extern fn c_nvrhi_device_createBindingLayout(
        *IDevice,
        *BindingLayoutHandle,
        *const BindingLayoutDesc,
    ) void;
    extern fn c_nvrhi_device_createInputLayout(
        *IDevice,
        *InputLayoutHandle,
        [*]const VertexAttributeDesc,
        u32,
        ?*IShader,
    ) void;

    pub fn runGarbageCollection(device: *IDevice) void {
        c_nvrhi_device_runGarbageCollection(device);
    }

    pub fn executeCommandList(device: *IDevice, command_list_ptr: *ICommandList) void {
        c_nvrhi_device_executeCommandList(device, command_list_ptr);
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createCommandList(device: *IDevice, params: CommandListParameters) CommandListHandle {
        var handle = CommandListHandle{};
        c_nvrhi_device_createCommandList(device, &handle, params);

        return handle;
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createBuffer(device: *IDevice, desc: *const BufferDesc) BufferHandle {
        var handle = BufferHandle{};
        c_nvrhi_device_createBuffer(device, &handle, desc);

        return handle;
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createBindingLayout(device: *IDevice, desc: *const BindingLayoutDesc) BindingLayoutHandle {
        var handle = BindingLayoutHandle{};
        c_nvrhi_device_createBindingLayout(device, &handle, desc);

        return handle;
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createShader(device: *IDevice, desc: *const ShaderDesc, binary: []const u8) ShaderHandle {
        var handle = ShaderHandle{};
        c_nvrhi_device_createShader(device, &handle, desc, binary.ptr, binary.len);

        return handle;
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createEventQuery(device: *IDevice) EventQueryHandle {
        var handle = EventQueryHandle{};
        c_nvrhi_device_createEventQuery(device, &handle);

        return handle;
    }

    pub fn createInputLayout(
        device: *IDevice,
        descs: []const VertexAttributeDesc,
        shader_ptr: ?*IShader,
    ) InputLayoutHandle {
        var handle = InputLayoutHandle{};
        c_nvrhi_device_createInputLayout(
            device,
            &handle,
            descs.ptr,
            @intCast(descs.len),
            shader_ptr,
        );

        return handle;
    }

    pub fn createHandleForNativeTexture(
        device: *IDevice,
        object_type: ObjectType,
        object: Object,
        desc: *const TextureDesc,
    ) TextureHandle {
        var handle = TextureHandle{};
        c_nvrhi_device_createHandleForNativeTexture(
            device,
            &handle,
            object_type,
            object,
            desc,
        );

        return handle;
    }

    pub fn waitForIdle(device: *IDevice) void {
        return c_nvrhi_device_waitForIdle(device);
    }

    pub fn setEventQuery(
        device: *IDevice,
        query: *IEventQuery,
        command_queue: CommandQueue,
    ) void {
        c_nvrhi_device_setEventQuery(device, query, command_queue);
    }
};

pub const CommandQueue = enum(u8) {
    Graphics = 0,
    Compute,
    Copy,
    Count,
};

pub const CommandListParameters = extern struct {
    // A command list with enableImmediateExecution = true maps to the immediate context on DX11.
    // Two immediate command lists cannot be open at the same time, which is checked by the validation layer.
    enableImmediateExecution: bool = true,

    // Minimum size of memory chunks created to upload data to the device on DX12.
    uploadChunkSize: usize = 64 * 1024,

    // Minimum size of memory chunks created for AS build scratch buffers.
    scratchChunkSize: usize = 64 * 1024,

    // Maximum total memory size used for all AS build scratch buffers owned by this command list.
    scratchMaxMemory: usize = 1024 * 1024 * 1024,

    // Type of the queue that this command list is to be executed on.
    // COPY and COMPUTE queues have limited subsets of methods available.
    queueType: CommandQueue = CommandQueue.Graphics,
};

pub const ICommandList = opaque {
    extern fn c_nvrhi_commandList_open(*ICommandList) void;
    extern fn c_nvrhi_commandList_close(*ICommandList) void;
    extern fn c_nvrhi_commandList_beginTrackingTextureState(
        *ICommandList,
        *ITexture,
        TextureSubresourceSet,
        ResourceStates,
    ) void;
    extern fn c_nvrhi_commandList_writeTexture(
        *ICommandList,
        *ITexture,
        u32,
        u32,
        [*]const u8,
        usize,
        usize,
    ) void;
    extern fn c_nvrhi_commandList_setPermanentTextureState(
        *ICommandList,
        *ITexture,
        ResourceStates,
    ) void;
    extern fn c_nvrhi_commandList_commitBarriers(*ICommandList) void;

    pub fn open(command_list: *ICommandList) void {
        c_nvrhi_commandList_open(command_list);
    }

    pub fn close(command_list: *ICommandList) void {
        c_nvrhi_commandList_close(command_list);
    }

    pub fn commitBarriers(command_list: *ICommandList) void {
        c_nvrhi_commandList_commitBarriers(command_list);
    }

    pub fn beginTrackingTextureState(
        command_list: *ICommandList,
        texture: *ITexture,
        subresources: TextureSubresourceSet,
        state_bits: ResourceStates,
    ) void {
        c_nvrhi_commandList_beginTrackingTextureState(
            command_list,
            texture,
            subresources,
            state_bits,
        );
    }

    pub fn writeTexture(
        command_list: *ICommandList,
        dest: *ITexture,
        array_slice: u32,
        mip_level: u32,
        data: [*]const u8,
        row_pitch: usize,
        depth_pitch: usize,
    ) void {
        c_nvrhi_commandList_writeTexture(
            command_list,
            dest,
            array_slice,
            mip_level,
            data,
            row_pitch,
            depth_pitch,
        );
    }

    pub fn setPermanentTextureState(
        command_list: *ICommandList,
        texture: *ITexture,
        state_bits: ResourceStates,
    ) void {
        c_nvrhi_commandList_setPermanentTextureState(command_list, texture, state_bits);
    }
};

pub const ResourceStates = enum(u32) {
    Unknown = 0,
    Common = 0x00000001,
    ConstantBuffer = 0x00000002,
    VertexBuffer = 0x00000004,
    IndexBuffer = 0x00000008,
    IndirectArgument = 0x00000010,
    ShaderResource = 0x00000020,
    UnorderedAccess = 0x00000040,
    RenderTarget = 0x00000080,
    DepthWrite = 0x00000100,
    DepthRead = 0x00000200,
    StreamOut = 0x00000400,
    CopyDest = 0x00000800,
    CopySource = 0x00001000,
    ResolveDest = 0x00002000,
    ResolveSource = 0x00004000,
    Present = 0x00008000,
    AccelStructRead = 0x00010000,
    AccelStructWrite = 0x00020000,
    AccelStructBuildInput = 0x00040000,
    AccelStructBuildBlas = 0x00080000,
    ShadingRateSurface = 0x00100000,
    OpacityMicromapWrite = 0x00200000,
    OpacityMicromapBuildInput = 0x00400000,
};

pub const CpuAccessMode = enum(u8) {
    None,
    Read,
    Write,
};

pub const SharedResourceFlags = enum(u32) {
    None = 0,
    Shared = 0x01,
    Shared_NTHandle = 0x02,
    Shared_CrossAdapter = 0x04,
};

pub const BufferDesc = extern struct {
    byteSize: u64 = 0,
    structStride: u32 = 0,
    maxVersions: u32 = 0,
    debugName: CppString,
    format: Format = .UNKNOWN,
    canHaveUAVs: bool = false,
    canHaveTypedViews: bool = false,
    canHaveRawViews: bool = false,
    isVertexBuffer: bool = false,
    isIndexBuffer: bool = false,
    isConstantBuffer: bool = false,
    isDrawIndirectArgs: bool = false,
    isAccelStructBuildInput: bool = false,
    isAccelStructStorage: bool = false,
    isShaderBindingTable: bool = false,
    isVolatile: bool = false,
    isVirtual: bool = false,
    initialState: ResourceStates = .Common,
    keepInitialState: bool = false,
    cpuAccess: CpuAccessMode = .None,
    sharedResourceFlags: SharedResourceFlags = .None,
};

pub const utils = struct {
    extern fn c_nvrhi_utils_createVolatileConstantBufferDesc(
        u32,
        [*:0]const u8,
        u32,
    ) BufferDesc;

    pub fn createVolatileConstantBufferDesc(
        byte_size: u32,
        debug_name: [:0]const u8,
        max_versions: u32,
    ) BufferDesc {
        return c_nvrhi_utils_createVolatileConstantBufferDesc(
            byte_size,
            debug_name.ptr,
            max_versions,
        );
    }
};

pub const IMessageCallback = opaque {};

pub const vulkan = struct {
    const vk = @cImport(@cInclude("vulkan/vulkan.h"));

    extern fn c_nvrhi_vulkan_convertFormat(Format) vk.VkFormat;
    extern fn c_nvrhi_vulkan_createDevice(
        *const DeviceDesc,
        *DeviceHandle,
        vk.PFN_vkGetInstanceProcAddr,
    ) void;

    pub fn convertFormat(format: Format) vk.VkFormat {
        return c_nvrhi_vulkan_convertFormat(format);
    }

    pub const DeviceDesc = extern struct {
        errorCB: ?*IMessageCallback = null,
        instance: vk.VkInstance,
        physicalDevice: vk.VkPhysicalDevice,
        device: vk.VkDevice,
        graphicsQueue: vk.VkQueue = null,
        graphicsQueueIndex: c_int = -1,
        transferQueue: vk.VkQueue = null,
        transferQueueIndex: c_int = -1,
        computeQueue: vk.VkQueue = null,
        computeQueueIndex: c_int = -1,
        allocationCallbacks: ?*vk.VkAllocationCallbacks = null,
        instanceExtensions: ?[*][*:0]const u8 = null,
        numInstanceExtensions: usize = 0,
        deviceExtensions: ?[*][*:0]const u8 = null,
        numDeviceExtensions: usize = 0,
        maxTimerQuerues: u32 = 256,
        bufferDeviceAddressSupported: bool = false,
    };

    pub fn createDevice(desc: *const DeviceDesc, vkGetInstanceProcAddr: vk.PFN_vkGetInstanceProcAddr) DeviceHandle {
        var handle = DeviceHandle{};
        c_nvrhi_vulkan_createDevice(desc, &handle, vkGetInstanceProcAddr);

        return handle;
    }
};
