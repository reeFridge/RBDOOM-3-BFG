const std = @import("std");

const IBuffer = opaque {};
const IGraphicsPipeline = opaque {};
const IComputePipeline = opaque {};
const IMeshletPipeline = opaque {};
const IFramebuffer = opaque {};
const IBindingSet = opaque {};
const IShaderTable = opaque {};

pub const MipLevel = u32;
pub const ArraySlice = u32;

pub const HeapType = enum(u8) {
    device_local,
    upload,
    readback,
};

pub const HeapDesc = struct {
    capacity: u64 = 0,
    type: HeapType,
    debug_name: [:0]const u8,
};

pub const TextureSubresourceSet = struct {
    pub const all_subresources = TextureSubresourceSet{
        .base_mip_level = 0,
        .num_mip_levels = all_mip_levels,
        .base_array_slice = 0,
        .num_array_slices = all_array_slices,
    };
    pub const all_mip_levels = std.math.maxInt(MipLevel);
    pub const all_array_slices = std.math.maxInt(ArraySlice);

    base_mip_level: MipLevel = 0,
    num_mip_levels: MipLevel = 1,
    base_array_slice: ArraySlice = 0,
    num_array_slices: ArraySlice = 1,

    pub fn resolve(
        subresources: TextureSubresourceSet,
        desc: *const TextureDesc,
        single_mip_level: bool,
    ) TextureSubresourceSet {
        var ret: TextureSubresourceSet = .{
            .base_mip_level = subresources.base_mip_level,
        };

        if (single_mip_level) {
            ret.num_mip_levels = 1;
        } else {
            const last_mip_level_plus_one = @min(
                subresources.base_mip_level + subresources.num_mip_levels,
                desc.mip_levels,
            );
            ret.num_mip_levels = @as(
                MipLevel,
                @max(0, last_mip_level_plus_one - subresources.base_mip_level),
            );
        }

        switch (desc.dimension) {
            .texture_1d_array,
            .texture_2d_array,
            .texture_cube,
            .texture_cube_array,
            .texture_2d_ms_array,
            => {
                ret.base_array_slice = subresources.base_array_slice;
                const last_array_slice_plus_one = @min(
                    subresources.base_array_slice + subresources.num_array_slices,
                    desc.array_size,
                );
                ret.num_array_slices = @as(
                    ArraySlice,
                    @max(0, last_array_slice_plus_one - subresources.base_array_slice),
                );
            },
            else => {
                ret.base_array_slice = 0;
                ret.num_array_slices = 1;
            },
        }

        return ret;
    }

    pub fn isEntireTexture(
        subresources: TextureSubresourceSet,
        desc: *const TextureDesc,
    ) bool {
        if (subresources.base_mip_level > 0 or
            (subresources.base_mip_level + subresources.num_mip_levels) < desc.mip_levels)
            return false;

        return switch (desc.dimension) {
            .texture_1d_array,
            .texture_2d_array,
            .texture_cube,
            .texture_cube_array,
            .texture_2d_ms_array,
            => if (subresources.base_array_slice > 0 or
                (subresources.base_array_slice + subresources.num_array_slices) < desc.array_size)
                false
            else
                true,
            else => true,
        };
    }
};

pub const TextureDimension = enum(u8) {
    unknown,
    texture_1d,
    texture_1d_array,
    texture_2d,
    texture_2d_array,
    texture_cube,
    texture_cube_array,
    texture_2d_ms,
    texture_2d_ms_array,
    texture_3d,
};

pub const ComponentSwizzle = enum(u8) {
    red,
    green,
    blue,
    alpha,
    zero,
    one,
};

pub const ComponentMapping = struct {
    r: ComponentSwizzle = .red,
    g: ComponentSwizzle = .green,
    b: ComponentSwizzle = .blue,
    a: ComponentSwizzle = .alpha,
};

pub const SharedResourceFlags = enum(u32) {
    none = 0,
    shared = 0x01,
    shared_nt_handle = 0x02,
    shared_cross_Adapter = 0x04,
};

pub const TextureDesc = struct {
    width: u32 = 1,
    height: u32 = 1,
    depth: u32 = 1,
    array_size: u32 = 1,
    mip_levels: u32 = 1,
    sample_count: u32 = 1,
    sample_quality: u32 = 0,
    format: Format = .unknown,
    dimension: TextureDimension = .texture_2d,
    component_mapping: ComponentMapping = .{},
    debug_name: [:0]const u8 = &.{},
    is_shader_resource: bool = false,
    is_render_target: bool = false,
    is_uav: bool = false,
    is_typeless: bool = false,
    is_shading_rate_surface: bool = false,
    shared_resource_flags: SharedResourceFlags = .none,
    is_virtual: bool = false,
    is_tiled: bool = false,
    clear_value: Color = .{},
    use_clear_value: bool = false,
    initial_state: ResourceStates = ResourceStates.unknown,
    keep_initial_state: bool = false,
};

pub const CpuAccessMode = enum(u8) {
    none,
    read,
    write,
};

pub const BufferDesc = struct {
    byte_size: u64 = 0,
    struct_stride: u32 = 0,
    max_versions: u32 = 0,
    debug_name: [*:0]const u8 = &.{},
    format: Format = .unknown,
    can_have_uavs: bool = false,
    can_have_typed_views: bool = false,
    can_have_raw_views: bool = false,
    is_vertex_buffer: bool = false,
    is_index_buffer: bool = false,
    is_constant_buffer: bool = false,
    is_draw_indirect_args: bool = false,
    is_accel_struct_build_input: bool = false,
    is_accel_struct_storage: bool = false,
    is_shader_binding_table: bool = false,
    is_volatile: bool = false,
    is_virtual: bool = false,
    initial_state: ResourceStates = .{ .common = true },
    keep_initial_state: bool = false,
    cpu_access: CpuAccessMode = .none,
    shared_resource_flags: SharedResourceFlags = .none,
};

pub const IMessageCallback = struct {
    pub const MessageSeverity = enum(u8) {
        info,
        warning,
        @"error",
        fatal,
    };

    ptr: *anyopaque,
    messageFn: *const fn (*anyopaque, MessageSeverity, []const u8) anyerror!void,

    pub fn message(self: IMessageCallback, severity: MessageSeverity, text: []const u8) !void {
        try self.messageFn(self.ptr, severity, text);
    }
};

pub const ResourceStates = packed struct(u32) {
    pub const unknown: ResourceStates = .{};

    common: bool = false,
    constant_buffer: bool = false,
    vertex_buffer: bool = false,
    index_buffer: bool = false,
    indirect_argument: bool = false,
    shader_resource: bool = false,
    unordered_access: bool = false,
    render_target: bool = false,
    depth_write: bool = false,
    depth_read: bool = false,
    stream_out: bool = false,
    copy_dest: bool = false,
    copy_source: bool = false,
    resolve_dest: bool = false,
    resolve_source: bool = false,
    present: bool = false,
    accel_struct_read: bool = false,
    accel_struct_write: bool = false,
    accel_struct_build_input: bool = false,
    accel_struct_build_blas: bool = false,
    shading_rate_surface: bool = false,
    opacity_micromap_write: bool = false,
    opacity_micromap_build_input: bool = false,
    _reserved: u9 = 0,
};

pub const Format = enum(u8) {
    unknown,
    r8_uint,
    r8_sint,
    r8_unorm,
    r8_snorm,
    rg8_uint,
    rg8_sint,
    rg8_unorm,
    rg8_snorm,
    r16_uint,
    r16_sint,
    r16_unorm,
    r16_snorm,
    r16_float,
    bgra4_unorm,
    b5g6r5_unorm,
    b5g5r5a1_unorm,
    rgba8_uint,
    rgba8_sint,
    rgba8_unorm,
    rgba8_snorm,
    bgra8_unorm,
    srgba8_unorm,
    sbgra8_unorm,
    r10g10b10a2_unorm,
    r11g11b10_float,
    rg16_uint,
    rg16_sint,
    rg16_unorm,
    rg16_snorm,
    rg16_float,
    r32_uint,
    r32_sint,
    r32_float,
    rgba16_uint,
    rgba16_sint,
    rgba16_float,
    rgba16_unorm,
    rgba16_snorm,
    rg32_uint,
    rg32_sint,
    rg32_float,
    rgb32_uint,
    rgb32_sint,
    rgb32_float,
    rgba32_uint,
    rgba32_sint,
    rgba32_float,
    d16,
    d24s8,
    x24g8_uint,
    d32,
    d32s8,
    x32g8_uint,
    bc1_unorm,
    bc1_unorm_srgb,
    bc2_unorm,
    bc2_unorm_srgb,
    bc3_unorm,
    bc3_unorm_srgb,
    bc4_unorm,
    bc4_snorm,
    bc5_unorm,
    bc5_snorm,
    bc6h_ufloat,
    bc6h_sfloat,
    bc7_unorm,
    bc7_unorm_srgb,
};

pub const max_render_targets = 8;
pub const max_binding_layouts = 5;
pub const max_bindings_per_layout = 128;
pub const max_vertex_attributes = 16;
pub const max_viewports = 16;

pub const CommandQueue = enum(u8) {
    graphics = 0,
    compute,
    copy,
};

pub const CommandListParameters = struct {
    enable_immediate_execution: bool = true,
    upload_chunk_size: usize = 64 * 1024,
    scratch_chunk_size: usize = 64 * 1024,
    scratch_max_memory: usize = 1024 * 1024 * 1024,
    queue_type: CommandQueue = .graphics,
};

pub const BlendFactor = enum(u8) {
    zero = 1,
    one = 2,
    src_color = 3,
    inv_src_color = 4,
    src_alpha = 5,
    inv_src_alpha = 6,
    dst_alpha = 7,
    inv_dst_alpha = 8,
    dst_color = 9,
    inv_dst_color = 10,
    src_alpha_saturate = 11,
    constant_color = 14,
    inv_constant_color = 15,
    src_1_color = 16,
    inv_src_1_color = 17,
    src_1_alpha = 18,
    inv_src_1_alpha = 19,

    pub const OneMinusSrcColor = BlendFactor.inv_src_color;
    pub const OneMinusSrcAlpha = BlendFactor.inv_src_alpha;
    pub const OneMinusDstAlpha = BlendFactor.inv_dst_alpha;
    pub const OneMinusDstColor = BlendFactor.inv_dst_color;
    pub const OneMinusConstantColor = BlendFactor.inv_constant_color;
    pub const OneMinusSrc1Color = BlendFactor.inv_src_1_color;
    pub const OneMinusSrc1Alpha = BlendFactor.inv_src_1_alpha;
};

pub const BlendOp = enum(u8) {
    add = 1,
    subrtact = 2,
    reverse_subtract = 3,
    min = 4,
    max = 5,
};

pub const ColorMask = enum(u8) {
    red = 1,
    green = 2,
    blue = 4,
    alpha = 8,
    all = 0xF,
};

pub const BlendState = struct {
    pub const RenderTarget = struct {
        blend_enable: bool = false,
        src_blend: BlendFactor = .one,
        dest_blend: BlendFactor = .zero,
        blend_op: BlendOp = .add,
        src_blend_alpha: BlendFactor = .one,
        dest_blend_alpha: BlendFactor = .zero,
        blend_op_alpha: BlendOp = .add,
        color_write_mask: ColorMask = .all,
    };

    targets: [max_render_targets]RenderTarget = [_]RenderTarget{.{}} ** max_render_targets,
    alpha_to_coverage_enable: bool = false,
};

pub const PrimitiveType = enum(u8) {
    point_list,
    line_list,
    triangle_list,
    triangle_strip,
    triangle_fan,
    triangle_list_with_adjacency,
    triangle_strip_with_adjacency,
    patch_list,
};

pub const StencilOp = enum(u8) {
    keep = 1,
    zero = 2,
    replace = 3,
    increment_and_clamp = 4,
    decrement_and_clamp = 5,
    invert = 6,
    increment_and_wrap = 7,
    decrement_and_wrap = 8,
};

pub const ComparisonFunc = enum(u8) {
    never = 1,
    less = 2,
    equal = 3,
    less_or_equal = 4,
    greater = 5,
    not_equal = 6,
    greater_or_equal = 7,
    always = 8,
};

pub const DepthStencilState = struct {
    pub const StencilOpDesc = struct {
        fail_op: StencilOp = .keep,
        depth_fail_op: StencilOp = .keep,
        pass_op: StencilOp = .keep,
        stencil_func: ComparisonFunc = .always,
    };

    depth_test_enable: bool = true,
    depth_write_enable: bool = true,
    depth_func: ComparisonFunc = .Less,
    stencil_enable: bool = false,
    stencil_read_mask: u8 = 0xff,
    stencil_write_mask: u8 = 0xff,
    stencil_ref_value: u8 = 0,
    dynamic_stencil_ref: bool = false,
    front_face_stencil: StencilOpDesc = .{},
    back_face_stencil: StencilOpDesc = .{},
};

pub const RasterFillMode = enum(u8) {
    solid,
    wireframe,

    pub const fill = RasterFillMode.solid;
    pub const line = RasterFillMode.wireframe;
};

pub const RasterCullMode = enum(u8) {
    back,
    front,
    none,
};

pub const RasterState = struct {
    fill_mode: RasterFillMode = .solid,
    cull_mode: RasterCullMode = .back,
    front_counter_clockwise: bool = false,
    depth_clip_enable: bool = false,
    scissor_enable: bool = false,
    multisample_enable: bool = false,
    antialiased_line_enable: bool = false,
    depth_bias: i32 = 0,
    depth_bias_clamp: f32 = 0,
    slope_scaled_depth_bias: f32 = 0,
    forced_sample_count: u8 = 0,
    programmable_sample_positions_enable: bool = false,
    conservative_raster_enable: bool = false,
    quad_fill_enable: bool = false,
    sample_positions_x: [16]u8 = std.mem.zeroes([16]u8),
    sample_positions_y: [16]u8 = std.mem.zeroes([16]u8),
};

pub const SinglePassStereoState = struct {
    enabled: bool = false,
    independent_viewport_mask: bool = false,
    render_target_index_offset: u16 = 0,
};

pub const RenderState = struct {
    blend_state: BlendState = .{},
    depth_stencil_state: DepthStencilState = .{},
    raster_state: RasterState = .{},
    single_pass_stereo: SinglePassStereoState = .{},
};

pub const VertexBufferBinding = struct {
    buffer: ?*IBuffer = null,
    slot: u32,
    offset: u64,
};

pub const IndexBufferBinding = struct {
    buffer: ?*IBuffer = null,
    format: Format = .unknown,
    offset: u32 = 0,
};

pub const Color = struct {
    r: f32 = 0,
    g: f32 = 0,
    b: f32 = 0,
    a: f32 = 0,
};

pub const Viewport = struct {
    min_x: f32 = 0,
    max_x: f32 = 0,
    min_y: f32 = 0,
    max_y: f32 = 0,
    min_z: f32 = 0,
    max_z: f32 = 1,

    pub fn width(viewport: *const Viewport) f32 {
        return viewport.max_x - viewport.min_x;
    }

    pub fn height(viewport: *const Viewport) f32 {
        return viewport.max_y - viewport.min_y;
    }

    pub fn fromWidthHeight(w: f32, h: f32) Viewport {
        return .{
            .max_x = w,
            .max_y = h,
        };
    }
};

pub const Rect = struct {
    min_x: i32,
    max_x: i32,
    min_y: i32,
    max_y: i32,

    pub fn fromViewport(viewport: *const Viewport) Rect {
        return .{
            .min_x = @intFromFloat(@floor(viewport.min_x)),
            .max_x = @intFromFloat(@ceil(viewport.max_x)),
            .min_y = @intFromFloat(@floor(viewport.min_y)),
            .max_y = @intFromFloat(@ceil(viewport.max_y)),
        };
    }
};

pub const ViewportState = struct {
    viewports: std.BoundedArray(Viewport, max_viewports) = .{},
    scissorRects: std.BoundedArray(Rect, max_viewports) = .{},
};

pub const GraphicsState = struct {
    pipeline: ?*IGraphicsPipeline = null,
    framebuffer: ?*IFramebuffer = null,
    viewport: ViewportState = .{},
    shading_rate_state: VariableRateShadingState = .{},
    blend_constant_color: Color = .{},
    dynamic_stencil_ref_value: u8 = 0,
    bindings: std.BoundedArray(*IBindingSet, max_binding_layouts) = .{},
    vertex_buffers: std.BoundedArray(VertexBufferBinding, max_vertex_attributes) = .{},
    index_buffer: IndexBufferBinding = .{},
    indirect_params: ?*IBuffer = null,
};

pub const VariableShadingRate = enum(u8) {
    @"1x1",
    @"1x2",
    @"2x1",
    @"2x2",
    @"2x4",
    @"4x2",
    @"4x4",
};

pub const ShadingRateCombiner = enum(u8) {
    passthrough,
    override,
    min,
    max,
    apply_relative,
};

pub const VariableRateShadingState = struct {
    enabled: bool = false,
    shading_rate: VariableShadingRate = .@"1x1",
    pipeline_primitive_combiner: ShadingRateCombiner = .passthrough,
    image_combiner: ShadingRateCombiner = .passthrough,
};

pub const ComputeState = struct {
    pipeline: ?*IComputePipeline = null,
    bindings: std.BoundedArray(*IBindingSet, max_binding_layouts) = .{},
    indirect_params: ?*IBuffer = null,
};

pub const MeshletState = struct {
    pipeline: ?*IMeshletPipeline = null,
    framebuffer: ?*IFramebuffer = null,
    viewport: ViewportState = .{},
    blend_constant_color: Color = .{},
    dynamic_stencil_ref_value: u8 = 0,
    bindings: std.BoundedArray(*IBindingSet, max_binding_layouts) = .{},
    indirect_params: ?*IBuffer = null,
};

pub const RayTracingState = struct {
    shader_table: ?*IShaderTable = null,
    bindings: std.BoundedArray(*IBindingSet, max_binding_layouts) = .{},
};
