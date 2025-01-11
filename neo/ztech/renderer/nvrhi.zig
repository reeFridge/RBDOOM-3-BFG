const std = @import("std");

pub const GraphicsAPI = enum(u8) {
    D3D11,
    D3D12,
    VULKAN,
};

pub const IResource = opaque {
    extern fn c_nvrhi_resource_addRef(*IResource) c_ulong;
    extern fn c_nvrhi_resource_release(*IResource) c_ulong;

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
pub const c_MaxRenderTargets: usize = 8;
pub const c_MaxBindingLayouts: usize = 5;
pub const c_MaxBindingsPerLayout: usize = 128;
pub const c_MaxVertexAttributes: usize = 16;
pub const c_MaxViewports: usize = 16;

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

pub const EntireBuffer = BufferRange{
    .byteOffset = 0,
    .byteSize = std.math.maxInt(u64),
};

pub const BindingSetItem = extern struct {
    resourceHandle: ?*IResource,
    slot: u32,
    type: ResourceType,
    dimension: TextureDimension,
    format: Format,
    unused: u8,
    unnamed_0: extern union {
        subresources: TextureSubresourceSet,
        range: BufferRange,
        rawData: [2]u64,
    },

    pub fn createConstantBuffer(
        slot: u32,
        opt_buffer: ?*IBuffer,
        range: BufferRange,
    ) BindingSetItem {
        const is_volatile = if (opt_buffer) |buffer|
            buffer.getDesc().isVolatile
        else
            false;

        return .{
            .slot = slot,
            .type = if (is_volatile) .VolatileConstantBuffer else .ConstantBuffer,
            .resourceHandle = @ptrCast(opt_buffer),
            .format = .UNKNOWN,
            .dimension = .Unknown,
            .unnamed_0 = .{
                .range = range,
            },
            .unused = 0,
        };
    }

    pub fn createTextureSrv(
        slot: u32,
        texture: *ITexture,
        format: Format,
        subresources: TextureSubresourceSet,
        dimension: TextureDimension,
    ) BindingSetItem {
        return .{
            .slot = slot,
            .type = .Texture_SRV,
            .resourceHandle = @ptrCast(texture),
            .format = format,
            .dimension = dimension,
            .unused = 0,
            .unnamed_0 = .{
                .subresources = subresources,
            },
        };
    }

    pub fn createPushConstants(slot: u32, byte_size: u32) BindingSetItem {
        return .{
            .slot = slot,
            .type = .PushConstants,
            .resourceHandle = null,
            .format = .UNKNOWN,
            .dimension = .Unknown,
            .unused = 0,
            .unnamed_0 = .{
                .range = .{ .byteOffset = 0, .byteSize = byte_size },
            },
        };
    }

    pub fn createSampler(slot: u32, sampler: *ISampler) BindingSetItem {
        return .{
            .slot = slot,
            .type = .Sampler,
            .resourceHandle = @ptrCast(sampler),
            .format = .UNKNOWN,
            .dimension = .Unknown,
            .unused = 0,
            .unnamed_0 = .{
                .rawData = .{ 0, 0 },
            },
        };
    }
};

pub fn static_vector(T: type, max_elements: u32) type {
    return extern struct {
        const Self = @This();

        base: [max_elements]T = undefined,
        current_size: usize = 0,

        pub fn pushBack(self: *Self, element: T) void {
            std.debug.assert(self.current_size < max_elements);

            self.base[self.current_size] = element;
            self.current_size += 1;
        }

        pub fn slice(self: *Self) []T {
            return self.base[0..self.current_size];
        }

        pub fn fromSliceWithDefault(init_slice: []const T, default: T) Self {
            var base: [max_elements]T = undefined;
            for (base[0..init_slice.len], init_slice) |*item, in| {
                item.* = in;
            }

            if (base.len > init_slice.len) {
                for (base[init_slice.len..]) |*item| {
                    item.* = default;
                }
            }

            return .{
                .base = base,
                .current_size = init_slice.len,
            };
        }

        pub fn fromSlice(init_slice: []const T) Self {
            var base: [max_elements]T = undefined;
            for (base[0..init_slice.len], init_slice) |*item, in| {
                item.* = in;
            }

            return .{
                .base = base,
                .current_size = init_slice.len,
            };
        }
    };
}

extern fn c_nvrhi_hashCombine_ptr(*usize, *anyopaque) void;
pub fn hashCombine_ptr(seed: *usize, ptr: *anyopaque) void {
    c_nvrhi_hashCombine_ptr(seed, ptr);
}

extern fn c_nvrhi_hashCombine_u64(seed: *usize, u: u64) void;
pub fn hashCombine_u64(seed: *usize, u: u64) void {
    c_nvrhi_hashCombine_u64(seed, u);
}

extern fn c_nvrhi_hashCombine_int(seed: *usize, i: c_int) void;
pub fn hashCombine_int(seed: *usize, i: c_int) void {
    c_nvrhi_hashCombine_int(seed, i);
}

extern fn c_nvrhi_hashCombine_float(seed: *usize, f: f32) void;
pub fn hashCombine_float(seed: *usize, f: f32) void {
    c_nvrhi_hashCombine_float(seed, f);
}

pub const BindingSetDesc = extern struct {
    extern fn c_nvrhi_bindingSetDesc_hashCombine(*const BindingSetDesc, *usize) void;
    extern fn c_nvrhi_bindingSetDesc_eql(*const BindingSetDesc, *const BindingSetDesc) bool;

    bindings: static_vector(BindingSetItem, c_MaxBindingsPerLayout),
    trackLiveness: bool = true,

    pub fn hashCombine(desc: *const BindingSetDesc, seed: *usize) void {
        c_nvrhi_bindingSetDesc_hashCombine(desc, seed);
    }

    pub fn eql(desc: *const BindingSetDesc, other: *const BindingSetDesc) bool {
        return c_nvrhi_bindingSetDesc_eql(desc, other);
    }
};

pub const Color = extern struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 0,
};

pub const Viewport = extern struct {
    minX: f32 = 0,
    maxX: f32 = 0,
    minY: f32 = 0,
    maxY: f32 = 0,
    minZ: f32 = 0,
    maxZ: f32 = 1,

    pub fn width(viewport: *const Viewport) f32 {
        return viewport.maxX - viewport.minX;
    }

    pub fn height(viewport: *const Viewport) f32 {
        return viewport.maxY - viewport.minY;
    }

    pub fn fromWidthHeight(w: f32, h: f32) Viewport {
        return .{
            .maxX = w,
            .maxY = h,
        };
    }
};

pub const SamplerAddressMode = enum(u8) {
    // Vulkan names
    ClampToEdge,
    Repeat,
    ClampToBorder,
    MirroredRepeat,
    MirrorClampToEdge,

    // D3D names
    pub const Clamp = SamplerAddressMode.ClampToEdge;
    pub const Wrap = SamplerAddressMode.Repeat;
    pub const Border = SamplerAddressMode.ClampToBorder;
    pub const Mirror = SamplerAddressMode.MirroredRepeat;
    pub const MirrorOnce = SamplerAddressMode.MirrorClampToEdge;
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

    extern fn c_nvrhi_samplerDesc_hashCombine(*const SamplerDesc, *usize) void;

    pub fn hashCombine(desc: *const SamplerDesc, hash: *usize) void {
        c_nvrhi_samplerDesc_hashCombine(desc, hash);
    }
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
    initialState: ResourceStates = ResourceStates.unknown,
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

extern fn c_cpp_string_set(*anyopaque, [*:0]const u8) void;
pub fn cppString_set(ptr: *CppString, value: [:0]const u8) void {
    c_cpp_string_set(@ptrCast(ptr), value.ptr);
}

extern fn c_cpp_string_get(*const anyopaque) [*:0]const u8;
pub fn cppString_get(ptr: *const CppString) [:0]const u8 {
    return std.mem.span(c_cpp_string_get(@ptrCast(ptr)));
}

pub const VertexAttributeDesc = extern struct {
    name: CppString = std.mem.zeroes(CppString),
    format: Format = .UNKNOWN,
    arraySize: u32 = 1,
    bufferIndex: u32 = 0,
    offset: u32 = 0,
    elementStride: u32 = 0,
    isInstanced: bool = false,

    pub fn setName(desc: *VertexAttributeDesc, name: [:0]const u8) void {
        cppString_set(&desc.name, name);
    }

    pub fn getName(desc: *const VertexAttributeDesc) [:0]const u8 {
        return cppString_get(&desc.name);
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
    debugName: [*:0]const u8 = "",
    entryName: [*:0]const u8 = "main",
    hlslExtensionsUAV: c_int = -1,
    useSpecificShaderExt: bool = false,
    numCustomSemantics: u32 = 0,
    pCustomSemantics: ?*CustomSemantic = null,
    fastGSFlags: @typeInfo(FastGeometryShaderFlags).Enum.tag_type = 0,
    pCoordinateSwizzling: ?*u32 = null,
};

pub const BlendFactor = enum(u8) {
    Zero = 1,
    One = 2,
    SrcColor = 3,
    InvSrcColor = 4,
    SrcAlpha = 5,
    InvSrcAlpha = 6,
    DstAlpha = 7,
    InvDstAlpha = 8,
    DstColor = 9,
    InvDstColor = 10,
    SrcAlphaSaturate = 11,
    ConstantColor = 14,
    InvConstantColor = 15,
    Src1Color = 16,
    InvSrc1Color = 17,
    Src1Alpha = 18,
    InvSrc1Alpha = 19,

    pub const OneMinusSrcColor = BlendFactor.InvSrcColor;
    pub const OneMinusSrcAlpha = BlendFactor.InvSrcAlpha;
    pub const OneMinusDstAlpha = BlendFactor.InvDstAlpha;
    pub const OneMinusDstColor = BlendFactor.InvDstColor;
    pub const OneMinusConstantColor = BlendFactor.InvConstantColor;
    pub const OneMinusSrc1Color = BlendFactor.InvSrc1Color;
    pub const OneMinusSrc1Alpha = BlendFactor.InvSrc1Alpha;
};

pub const BlendOp = enum(u8) {
    Add = 1,
    Subrtact = 2,
    ReverseSubtract = 3,
    Min = 4,
    Max = 5,
};

pub const ColorMask = enum(u8) {
    Red = 1,
    Green = 2,
    Blue = 4,
    Alpha = 8,
    All = 0xF,
};

pub const BlendState = extern struct {
    pub const RenderTarget = extern struct {
        blendEnable: bool = false,
        srcBlend: BlendFactor = .One,
        destBlend: BlendFactor = .Zero,
        blendOp: BlendOp = .Add,
        srcBlendAlpha: BlendFactor = .One,
        destBlendAlpha: BlendFactor = .Zero,
        blendOpAlpha: BlendOp = .Add,
        colorWriteMask: ColorMask = .All,
    };

    targets: [c_MaxRenderTargets]RenderTarget = [_]RenderTarget{.{}} ** c_MaxRenderTargets,
    alphaToCoverageEnable: bool = false,
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

pub const ITexture = opaque {
    extern fn c_nvrhi_texture_getDesc(*const ITexture) *const TextureDesc;

    pub fn getDesc(texture: *const ITexture) *const TextureDesc {
        return c_nvrhi_texture_getDesc(texture);
    }
};

pub const ISampler = opaque {
    extern fn c_nvrhi_sampler_getDesc(*const ISampler) *const SamplerDesc;

    pub fn getDesc(sampler: *const ISampler) *const SamplerDesc {
        return c_nvrhi_sampler_getDesc(sampler);
    }
};

pub const IShader = opaque {};

pub const FramebufferInfo = extern struct {
    colorFormats: static_vector(Format, c_MaxRenderTargets) = .{},
    depthFormat: Format = .UNKNOWN,
    sampleCount: u32 = 1,
    sampleQuality: u32 = 0,
};

pub const FramebufferInfoEx = extern struct {
    framebuffer_info: FramebufferInfo,
    width: u32 = 0,
    height: u32 = 0,
};

pub const IFramebuffer = opaque {
    extern fn c_nvrhi_framebuffer_getFramebufferInfo(*const IFramebuffer) *const FramebufferInfoEx;
    extern fn c_nvrhi_framebuffer_getDesc(*const IFramebuffer) *const FramebufferDesc;

    pub fn getFramebufferInfo(framebuffer: *const IFramebuffer) *const FramebufferInfoEx {
        return c_nvrhi_framebuffer_getFramebufferInfo(framebuffer);
    }

    pub fn getDesc(framebuffer: *const IFramebuffer) *const FramebufferDesc {
        return c_nvrhi_framebuffer_getDesc(framebuffer);
    }
};

pub const IInputLayout = opaque {};

pub const IBindingSet = opaque {
    extern fn c_nvrhi_bindingSet_getDesc(*const IBindingSet) *const BindingSetDesc;

    pub fn getDesc(binding_set: *const IBindingSet) *const BindingSetDesc {
        return c_nvrhi_bindingSet_getDesc(binding_set);
    }
};

pub const PrimitiveType = enum(u8) {
    PointList,
    LineList,
    TriangleList,
    TriangleStrip,
    TriangleFan,
    TriangleListWithAdjacency,
    TriangleStripWithAdjacency,
    PatchList,
};

pub const StencilOp = enum(u8) {
    Keep = 1,
    Zero = 2,
    Replace = 3,
    IncrementAndClamp = 4,
    DecrementAndClamp = 5,
    Invert = 6,
    IncrementAndWrap = 7,
    DecrementAndWrap = 8,
};

pub const ComparisonFunc = enum(u8) {
    Never = 1,
    Less = 2,
    Equal = 3,
    LessOrEqual = 4,
    Greater = 5,
    NotEqual = 6,
    GreaterOrEqual = 7,
    Always = 8,
};

pub const DepthStencilState = extern struct {
    pub const StencilOpDesc = extern struct {
        failOp: StencilOp = .Keep,
        depthFailOp: StencilOp = .Keep,
        passOp: StencilOp = .Keep,
        stencilFunc: ComparisonFunc = .Always,
    };

    depthTestEnable: bool = true,
    depthWriteEnable: bool = true,
    depthFunc: ComparisonFunc = .Less,
    stencilEnable: bool = false,
    stencilReadMask: u8 = 0xff,
    stencilWriteMask: u8 = 0xff,
    stencilRefValue: u8 = 0,
    dynamicStencilRef: bool = false,
    frontFaceStencil: StencilOpDesc = .{},
    backFaceStencil: StencilOpDesc = .{},
};

pub const RasterFillMode = enum(u8) {
    Solid,
    Wireframe,

    pub const Fill = RasterFillMode.Solid;
    pub const Line = RasterFillMode.Wireframe;
};

pub const RasterCullMode = enum(u8) {
    Back,
    Front,
    None,
};

pub const RasterState = extern struct {
    fillMode: RasterFillMode = .Solid,
    cullMode: RasterCullMode = .Back,
    frontCounterClockwise: bool = false,
    depthClipEnable: bool = false,
    scissorEnable: bool = false,
    multisampleEnable: bool = false,
    antialiasedLineEnable: bool = false,
    depthBias: i32 = 0,
    depthBiasClamp: f32 = 0,
    slopeScaledDepthBias: f32 = 0,
    forcedSampleCount: u8 = 0,
    programmableSamplePositionsEnable: bool = false,
    conservativeRasterEnable: bool = false,
    quadFillEnable: bool = false,
    samplePositionsX: [16]u8 = std.mem.zeroes([16]u8),
    samplePositionsY: [16]u8 = std.mem.zeroes([16]u8),
};

pub const SinglePassStereoState = extern struct {
    enabled: bool = false,
    independentViewportMask: bool = false,
    renderTargetIndexOffset: u16 = 0,
};

pub const RenderState = extern struct {
    blendState: BlendState = .{},
    depthStencilState: DepthStencilState = .{},
    rasterState: RasterState = .{},
    singlePassStereo: SinglePassStereoState = .{},
};

pub const VertexBufferBinding = extern struct {
    buffer: ?*IBuffer = null,
    slot: u32,
    offset: u64,
};

pub const IndexBufferBinding = extern struct {
    buffer: ?*IBuffer = null,
    format: Format = .UNKNOWN,
    offset: u32 = 0,
};

pub const Rect = extern struct {
    minX: i32,
    maxX: i32,
    minY: i32,
    maxY: i32,

    pub fn fromViewport(viewport: *const Viewport) Rect {
        return .{
            .minX = @intFromFloat(@floor(viewport.minX)),
            .maxX = @intFromFloat(@ceil(viewport.maxX)),
            .minY = @intFromFloat(@floor(viewport.minY)),
            .maxY = @intFromFloat(@ceil(viewport.maxY)),
        };
    }
};

pub const ViewportState = extern struct {
    viewports: static_vector(Viewport, c_MaxViewports) = .{},
    scissorRects: static_vector(Rect, c_MaxViewports) = .{},
};

pub const GraphicsState = extern struct {
    pipeline: ?*IGraphicsPipeline = null,
    framebuffer: ?*IFramebuffer = null,
    viewport: ViewportState = .{},
    shadingRateState: VariableRateShadingState = .{},
    blendConstantColor: Color = .{},
    dynamicStencilRefValue: u8 = 0,
    bindings: static_vector(*IBindingSet, c_MaxBindingLayouts) = .{},
    vertexBuffers: static_vector(VertexBufferBinding, c_MaxVertexAttributes) = .{},
    indexBuffer: IndexBufferBinding = .{},
    indirectParams: ?*IBuffer = null,
};

pub const VariableShadingRate = enum(u8) {
    e1x1,
    e1x2,
    e2x1,
    e2x2,
    e2x4,
    e4x2,
    e4x4,
};

pub const ShadingRateCombiner = enum(u8) {
    Passthrough,
    Override,
    Min,
    Max,
    ApplyRelative,
};

pub const VariableRateShadingState = extern struct {
    enabled: bool = false,
    shadingRate: VariableShadingRate = .e1x1,
    pipelinePrimitiveCombiner: ShadingRateCombiner = .Passthrough,
    imageCombiner: ShadingRateCombiner = .Passthrough,
};

pub const GraphicsPipelineDesc = extern struct {
    primType: PrimitiveType = .TriangleList,
    patchControlPoints: u32 = 0,
    inputLayout: InputLayoutHandle = .{},

    VS: ShaderHandle = .{},
    HS: ShaderHandle = .{},
    DS: ShaderHandle = .{},
    GS: ShaderHandle = .{},
    PS: ShaderHandle = .{},

    renderState: RenderState = .{},
    shadingRateState: VariableRateShadingState = .{},

    bindingLayouts: static_vector(BindingLayoutHandle, c_MaxBindingLayouts) = .{},
};

pub const IGraphicsPipeline = opaque {};

pub const IBindingLayout = opaque {};
pub const IBuffer = opaque {
    extern fn c_nvrhi_buffer_getDesc(*const IBuffer) *const BufferDesc;

    pub fn getDesc(texture: *const IBuffer) *const BufferDesc {
        return c_nvrhi_buffer_getDesc(texture);
    }
};
pub const IDevice = opaque {
    extern fn c_nvrhi_device_createHandleForNativeTexture(
        *IDevice,
        *TextureHandle,
        ObjectType,
        Object,
        *const TextureDesc,
    ) void;
    extern fn c_nvrhi_device_createHandleForNativeBuffer(
        device: *IDevice,
        handle: *BufferHandle,
        object_type: ObjectType,
        buffer: Object,
        desc: *const BufferDesc,
    ) void;
    extern fn c_nvrhi_device_runGarbageCollection(*IDevice) void;
    extern fn c_nvrhi_device_waitForIdle(*IDevice) void;
    extern fn c_nvrhi_device_executeCommandList(*IDevice, *ICommandList) void;
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
    extern fn c_nvrhi_device_createFramebuffer(
        *IDevice,
        *FramebufferHandle,
        *const FramebufferDesc,
    ) void;
    extern fn c_nvrhi_device_createShader(
        *IDevice,
        *ShaderHandle,
        *const ShaderDesc,
        *const anyopaque,
        usize,
    ) void;
    extern fn c_nvrhi_device_createBindingSet(
        *IDevice,
        *BindingSetHandle,
        *const BindingSetDesc,
        *IBindingLayout,
    ) void;
    extern fn c_nvrhi_device_createBindingLayout(
        *IDevice,
        *BindingLayoutHandle,
        *const BindingLayoutDesc,
    ) void;
    extern fn c_nvrhi_device_createSampler(
        *IDevice,
        *SamplerHandle,
        *const SamplerDesc,
    ) void;
    extern fn c_nvrhi_device_createTexture(
        *IDevice,
        *TextureHandle,
        *const TextureDesc,
    ) void;
    extern fn c_nvrhi_device_createInputLayout(
        *IDevice,
        *InputLayoutHandle,
        [*]const VertexAttributeDesc,
        u32,
        ?*IShader,
    ) void;
    extern fn c_nvrhi_device_createGraphicsPipeline(
        *IDevice,
        *GraphicsPipelineHandle,
        *const GraphicsPipelineDesc,
        *IFramebuffer,
    ) void;

    pub fn runGarbageCollection(device: *IDevice) void {
        c_nvrhi_device_runGarbageCollection(device);
    }

    pub fn executeCommandList(device: *IDevice, command_list_ptr: *ICommandList) void {
        c_nvrhi_device_executeCommandList(device, command_list_ptr);
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createBindingSet(
        device: *IDevice,
        desc: *const BindingSetDesc,
        layout: *IBindingLayout,
    ) BindingSetHandle {
        var handle = BindingSetHandle{};
        c_nvrhi_device_createBindingSet(device, &handle, desc, layout);

        return handle;
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createGraphicsPipeline(
        device: *IDevice,
        desc: *const GraphicsPipelineDesc,
        fb: *IFramebuffer,
    ) GraphicsPipelineHandle {
        var handle = GraphicsPipelineHandle{};
        c_nvrhi_device_createGraphicsPipeline(device, &handle, desc, fb);

        return handle;
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
    pub fn createSampler(device: *IDevice, desc: *const SamplerDesc) SamplerHandle {
        var handle = SamplerHandle{};
        c_nvrhi_device_createSampler(device, &handle, desc);

        return handle;
    }

    /// increases ref count
    /// should call handle.deinit on resource release
    pub fn createTexture(device: *IDevice, desc: *const TextureDesc) TextureHandle {
        var handle = TextureHandle{};
        c_nvrhi_device_createTexture(device, &handle, desc);

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

    pub fn createFramebuffer(
        device: *IDevice,
        desc: *const FramebufferDesc,
    ) FramebufferHandle {
        var handle = FramebufferHandle{};
        c_nvrhi_device_createFramebuffer(
            device,
            &handle,
            desc,
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

    pub fn createHandleForNativeBuffer(
        device: *IDevice,
        object_type: ObjectType,
        buffer: Object,
        desc: *const BufferDesc,
    ) BufferHandle {
        var handle = BufferHandle{};
        c_nvrhi_device_createHandleForNativeBuffer(
            device,
            &handle,
            object_type,
            buffer,
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

pub const DrawArguments = extern struct {
    vertexCount: u32 = 0,
    instanceCount: u32 = 1,
    startIndexLocation: u32 = 0,
    startVertexLocation: u32 = 0,
    startInstanceLocation: u32 = 0,
};

pub const ICommandList = opaque {
    extern fn c_nvrhi_commandList_setGraphicsState(*ICommandList, *const GraphicsState) void;
    extern fn c_nvrhi_commandList_draw(*ICommandList, *const DrawArguments) void;
    extern fn c_nvrhi_commandList_drawIndexed(*ICommandList, *const DrawArguments) void;
    extern fn c_nvrhi_commandList_setPushConstants(*ICommandList, *const anyopaque, usize) void;
    extern fn c_nvrhi_commandList_open(*ICommandList) void;
    extern fn c_nvrhi_commandList_close(*ICommandList) void;
    extern fn c_nvrhi_commandList_clearDepthStencilTexture(
        *ICommandList,
        *ITexture,
        TextureSubresourceSet,
        bool,
        f32,
        bool,
        u8,
    ) void;
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
    extern fn c_nvrhi_commandList_setPermanentBufferState(
        *ICommandList,
        *IBuffer,
        ResourceStates,
    ) void;
    extern fn c_nvrhi_commandList_beginTrackingBufferState(
        *ICommandList,
        *IBuffer,
        ResourceStates,
    ) void;
    extern fn c_nvrhi_commandList_writeBuffer(
        *ICommandList,
        *IBuffer,
        ?[*]const u8,
        usize,
        u64,
    ) void;

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

    pub fn beginTrackingBufferState(
        command_list: *ICommandList,
        buffer: *IBuffer,
        state_bits: ResourceStates,
    ) void {
        c_nvrhi_commandList_beginTrackingBufferState(command_list, buffer, state_bits);
    }

    pub fn writeBuffer(
        command_list: *ICommandList,
        buffer: *IBuffer,
        data: ?[*]const u8,
        data_size: usize,
        dest_offset_bytes: u64,
    ) void {
        c_nvrhi_commandList_writeBuffer(
            command_list,
            buffer,
            data,
            data_size,
            dest_offset_bytes,
        );
    }

    pub fn setPermanentBufferState(
        command_list: *ICommandList,
        buffer: *IBuffer,
        state_bits: ResourceStates,
    ) void {
        c_nvrhi_commandList_setPermanentBufferState(command_list, buffer, state_bits);
    }

    pub fn clearDepthStencilTexture(
        command_list: *ICommandList,
        t: *ITexture,
        subresources: TextureSubresourceSet,
        clear_depth: bool,
        depth: f32,
        clear_stencil: bool,
        stencil: u8,
    ) void {
        c_nvrhi_commandList_clearDepthStencilTexture(
            command_list,
            t,
            subresources,
            clear_depth,
            depth,
            clear_stencil,
            stencil,
        );
    }

    pub fn setGraphicsState(
        command_list: *ICommandList,
        state: *const GraphicsState,
    ) void {
        c_nvrhi_commandList_setGraphicsState(command_list, state);
    }

    pub fn draw(command_list: *ICommandList, args: *const DrawArguments) void {
        c_nvrhi_commandList_draw(command_list, args);
    }

    pub fn drawIndexed(command_list: *ICommandList, args: *const DrawArguments) void {
        c_nvrhi_commandList_drawIndexed(command_list, args);
    }

    pub fn setPushConstants(
        command_list: *ICommandList,
        data: *const anyopaque,
        byte_size: usize,
    ) void {
        c_nvrhi_commandList_setPushConstants(command_list, data, byte_size);
    }
};

pub const ResourceStates = packed struct(u32) {
    pub const unknown: ResourceStates = .{};

    Common: bool = false,
    ConstantBuffer: bool = false,
    VertexBuffer: bool = false,
    IndexBuffer: bool = false,
    IndirectArgument: bool = false,
    ShaderResource: bool = false,
    UnorderedAccess: bool = false,
    RenderTarget: bool = false,
    DepthWrite: bool = false,
    DepthRead: bool = false,
    StreamOut: bool = false,
    CopyDest: bool = false,
    CopySource: bool = false,
    ResolveDest: bool = false,
    ResolveSource: bool = false,
    Present: bool = false,
    AccelStructRead: bool = false,
    AccelStructWrite: bool = false,
    AccelStructBuildInput: bool = false,
    AccelStructBuildBlas: bool = false,
    ShadingRateSurface: bool = false,
    OpacityMicromapWrite: bool = false,
    OpacityMicromapBuildInput: bool = false,
    _reserved: u9 = 0,
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
    debugName: CppString = std.mem.zeroes(CppString),
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
    initialState: ResourceStates = .{ .Common = true },
    keepInitialState: bool = false,
    cpuAccess: CpuAccessMode = .None,
    sharedResourceFlags: SharedResourceFlags = .None,
};

pub const FramebufferAttachment = extern struct {
    texture: ?*ITexture = null,
    subresources: TextureSubresourceSet = .{},
    format: Format = .UNKNOWN,
    isReadOnly: bool = false,

    pub inline fn valid(attach: *const FramebufferAttachment) bool {
        return attach.texture != null;
    }
};

pub const FramebufferDesc = extern struct {
    pub const ColorAttachments = static_vector(FramebufferAttachment, c_MaxRenderTargets);

    colorAttachments: ColorAttachments = .{},
    depthAttachment: FramebufferAttachment = .{},
    shadingRateAttachment: FramebufferAttachment = .{},
};

pub const utils = struct {
    extern fn c_nvrhi_utils_createVolatileConstantBufferDesc(
        u32,
        [*:0]const u8,
        u32,
    ) BufferDesc;

    extern fn c_nvrhi_utils_clearColorAttachment(
        *ICommandList,
        *IFramebuffer,
        u32,
        Color,
    ) void;

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

    pub fn clearColorAttachment(
        command_list: *ICommandList,
        framebuffer: *IFramebuffer,
        attachment_index: u32,
        color: Color,
    ) void {
        c_nvrhi_utils_clearColorAttachment(
            command_list,
            framebuffer,
            attachment_index,
            color,
        );
    }
};

pub const IMessageCallback = opaque {};

pub const vulkan = struct {
    const c = @import("../sys/c_import.zig").c;

    pub const IVulkanDevice = opaque {
        extern fn c_nvrhi_vulkan_device_queueWaitForSemaphore(
            *IVulkanDevice,
            CommandQueue,
            c.VkSemaphore,
            u64,
        ) void;
        extern fn c_nvrhi_vulkan_device_queueSignalSemaphore(
            *IVulkanDevice,
            CommandQueue,
            c.VkSemaphore,
            u64,
        ) void;

        pub fn queueWaitForSemaphore(
            device: *IVulkanDevice,
            wait_queue: CommandQueue,
            semaphore: c.VkSemaphore,
            value: u64,
        ) void {
            c_nvrhi_vulkan_device_queueWaitForSemaphore(
                device,
                wait_queue,
                semaphore,
                value,
            );
        }

        pub fn queueSignalSemaphore(
            device: *IVulkanDevice,
            execution_queue: CommandQueue,
            semaphore: c.VkSemaphore,
            value: u64,
        ) void {
            c_nvrhi_vulkan_device_queueSignalSemaphore(
                device,
                execution_queue,
                semaphore,
                value,
            );
        }
    };

    pub const VulkanDeviceHandle = RefCountPtr(IVulkanDevice);

    extern fn c_nvrhi_vulkan_convertFormat(Format) c.VkFormat;
    extern fn c_nvrhi_vulkan_createDevice(
        *const DeviceDesc,
        *VulkanDeviceHandle,
        c.PFN_vkGetInstanceProcAddr,
    ) void;

    pub fn convertFormat(format: Format) c.VkFormat {
        return c_nvrhi_vulkan_convertFormat(format);
    }

    pub const DeviceDesc = extern struct {
        errorCB: ?*IMessageCallback = null,
        instance: c.VkInstance,
        physicalDevice: c.VkPhysicalDevice,
        device: c.VkDevice,
        graphicsQueue: c.VkQueue = null,
        graphicsQueueIndex: c_int = -1,
        transferQueue: c.VkQueue = null,
        transferQueueIndex: c_int = -1,
        computeQueue: c.VkQueue = null,
        computeQueueIndex: c_int = -1,
        allocationCallbacks: ?*c.VkAllocationCallbacks = null,
        instanceExtensions: ?[*][*:0]const u8 = null,
        numInstanceExtensions: usize = 0,
        deviceExtensions: ?[*][*:0]const u8 = null,
        numDeviceExtensions: usize = 0,
        maxTimerQuerues: u32 = 256,
        bufferDeviceAddressSupported: bool = false,
    };

    pub fn createDevice(
        desc: *const DeviceDesc,
        vkGetInstanceProcAddr: c.PFN_vkGetInstanceProcAddr,
    ) VulkanDeviceHandle {
        var handle = VulkanDeviceHandle{};
        c_nvrhi_vulkan_createDevice(desc, &handle, vkGetInstanceProcAddr);

        return handle;
    }
};
