const interface = @import("interface.zig");
const common = @import("common.zig");
const std = @import("std");
const vulkan = @import("vulkan");
const Allocator = std.mem.Allocator;

const Dispatch = struct {
    const required_instance_extensions: []const vulkan.ApiInfo = &.{
        vulkan.extensions.khr_surface,
        vulkan.extensions.khr_get_physical_device_properties_2,
    };
    const required_device_extensions: []const vulkan.ApiInfo = &.{
        vulkan.extensions.ext_extended_dynamic_state,
        vulkan.extensions.khr_dynamic_rendering,
        vulkan.extensions.khr_synchronization_2,
        vulkan.extensions.khr_swapchain,
        vulkan.extensions.khr_maintenance_1,
    };
    const optional_instance_extensions: []const vulkan.ApiInfo = &.{
        vulkan.extensions.ext_sampler_filter_minmax,
        vulkan.extensions.ext_debug_report,
    };
    const optional_device_extensions: []const vulkan.ApiInfo = &.{
        vulkan.extensions.ext_debug_marker,
        vulkan.extensions.ext_descriptor_indexing,
        vulkan.extensions.khr_buffer_device_address,
        vulkan.extensions.nv_mesh_shader,
        vulkan.extensions.khr_fragment_shading_rate,
        vulkan.extensions.khr_format_feature_flags_2,
        vulkan.extensions.ext_memory_budget,
    };
    const ray_tracing_device_extensions: []const vulkan.ApiInfo = &.{
        vulkan.extensions.khr_acceleration_structure,
        vulkan.extensions.khr_deferred_host_operations,
        vulkan.extensions.khr_pipeline_library,
        vulkan.extensions.khr_ray_query,
        vulkan.extensions.khr_ray_tracing_pipeline,
    };

    const base_api: []const vulkan.ApiInfo = &.{
        .{
            .base_commands = .{
                .enumerateInstanceExtensionProperties = true,
                .enumerateInstanceLayerProperties = true,
                .createInstance = true,
                .getInstanceProcAddr = true,
            },
            .instance_commands = .{
                .destroyInstance = true,
                .enumeratePhysicalDevices = true,
                .getPhysicalDeviceProperties = true,
                .getPhysicalDeviceProperties2 = true,
                .enumerateDeviceExtensionProperties = true,
                .enumerateDeviceLayerProperties = true,
                .getPhysicalDeviceFeatures = true,
                .getPhysicalDeviceQueueFamilyProperties = true,
                .getPhysicalDeviceFeatures2 = true,
                .createDevice = true,
                .getDeviceProcAddr = true,
                .getPhysicalDeviceImageFormatProperties = true,
            },
            .device_commands = .{
                .destroyDevice = true,
                .getDeviceQueue = true,
                .createSemaphore = true,
                .destroySemaphore = true,
                .deviceWaitIdle = true,
                .acquireNextImageKHR = true,
                .queuePresentKHR = true,
                .createDescriptorSetLayout = true,
                .createPipelineCache = true,
                .createCommandPool = true,
                .destroyCommandPool = true,
                .allocateCommandBuffers = true,
                .beginCommandBuffer = true,
                .endCommandBuffer = true,
                .cmdEndRenderPass = true,
                .cmdPipelineBarrier = true,
                .cmdPipelineBarrier2 = true,
                .flushMappedMemoryRanges = true,
                .queueSubmit = true,
            },
        },
        vulkan.extensions.ext_debug_utils,
    };

    const apis = base_api ++
        required_instance_extensions ++
        required_device_extensions ++
        optional_instance_extensions ++
        optional_device_extensions ++
        ray_tracing_device_extensions;

    pub const BaseDispatch = vulkan.BaseWrapper(apis);
    pub const InstanceDispatch = vulkan.InstanceWrapper(apis);
    pub const DeviceDispatch = vulkan.DeviceWrapper(apis);
    pub const InstanceProxy = vulkan.InstanceProxy(apis);
    pub const DeviceProxy = vulkan.DeviceProxy(apis);
    pub const CommandBufferProxy = vulkan.CommandBufferProxy(apis);
    pub const QueueProxy = vulkan.QueueProxy(apis);

    base: BaseDispatch,
    instance: InstanceProxy,
    device: DeviceProxy,
};

const Version = packed struct(u64) {
    id: u60 = 0,
    queue_id: u3 = 0,
    submitted: bool = false,

    fn make(id: u64, queue_id: interface.CommandQueue, submitted: bool) Version {
        return .{
            .id = @truncate(id),
            .queue_id = @intCast(@intFromEnum(queue_id)),
            .submitted = submitted,
        };
    }
};

pub const CommandList = struct {
    const ShaderTableState = struct {
        const default = vulkan.StridedDeviceAddressRegionKHR{ .stride = 0, .size = 0 };

        ray_gen: vulkan.StridedDeviceAddressRegionKHR = default,
        miss: vulkan.StridedDeviceAddressRegionKHR = default,
        hit_groups: vulkan.StridedDeviceAddressRegionKHR = default,
        callable: vulkan.StridedDeviceAddressRegionKHR = default,
        version: u32 = 0,
    };

    const VolatileBufferState = struct {
        latest_version: i32 = 0,
        min_version: i32 = 0,
        max_version: i32 = 0,
        initialized: bool = false,
    };

    const BufferChunk = struct {
        buffer: Buffer.Handle,
        version: Version = .{},
        buffer_size: u64 = 0,
        write_pointer: u64 = 0,
        mapped_memory: ?*anyopaque = null,

        const size_alignment: u64 = 4096; // gpu page size
    };

    const UploadManager = struct {
        device: *Device,
        default_chunk_size: u64,
        memory_limit: u64 = 0,
        allocated_memory: u64 = 0,
        is_scratch_buffer: bool = false,
        chunk_pool: std.SinglyLinkedList(*BufferChunk) = .{},
        current_chunk: ?*BufferChunk = null,

        fn submitChunks(
            upload_manager: *UploadManager,
            current_version: Version,
            submitted_version: Version,
            allocator: Allocator,
        ) Allocator.Error!void {
            if (upload_manager.current_chunk) |current_chunk| {
                const node = try allocator.create(std.SinglyLinkedList(*BufferChunk).Node);
                node.* = .{ .data = current_chunk };
                upload_manager.chunk_pool.prepend(node);

                // TODO: check shared refs
                upload_manager.current_chunk = null;
            }

            var it = upload_manager.chunk_pool.first;
            while (it) |node| : (it = node.next) {
                if (@as(u64, @bitCast(node.data.version)) == @as(u64, @bitCast(current_version))) {
                    node.data.version = submitted_version;
                }
            }
        }
    };

    ref_counter: RefCounter = .{},
    device: *Device,
    context: *const Context,
    parameters: interface.CommandListParameters,
    resource_state_tracker: common.CommandListResourceStateTracker,
    enable_automatic_barriers: bool = true,
    current_cmd_buf: ?*TrackedCommandBuffer = null,
    current_pipeline_layout: vulkan.PipelineLayout = .null_handle,
    current_push_constants_visibility: vulkan.ShaderStageFlags = .{},
    current_graphics_state: interface.GraphicsState = .{},
    current_compute_state: interface.ComputeState = .{},
    current_meshlet_state: interface.MeshletState = .{},
    current_ray_tracing_state: interface.RayTracingState = .{},
    any_volatile_buffer_writes: bool = false,
    current_shader_table_pointers: ShaderTableState = .{},
    volatile_buffer_states: std.AutoHashMapUnmanaged(*Buffer, VolatileBufferState) = .{},
    upload_manager: *UploadManager,
    scratch_manager: *UploadManager,

    fn create(
        device: *Device,
        context: *const Context,
        command_list_params: *const interface.CommandListParameters,
        allocator: Allocator,
    ) Allocator.Error!*CommandList {
        const command_list = try allocator.create(CommandList);
        errdefer allocator.destroy(command_list);

        const upload_manager = try allocator.create(UploadManager);
        errdefer allocator.destroy(upload_manager);
        upload_manager.* = .{
            .device = device,
            .default_chunk_size = command_list_params.upload_chunk_size,
        };
        const scratch_manager = try allocator.create(UploadManager);
        errdefer allocator.destroy(scratch_manager);
        scratch_manager.* = .{
            .device = device,
            .default_chunk_size = command_list_params.scratch_chunk_size,
            .memory_limit = command_list_params.scratch_max_memory,
            .is_scratch_buffer = true,
        };

        command_list.* = .{
            .device = device,
            .context = context,
            .parameters = command_list_params.*,
            .resource_state_tracker = .{ .message_callback = context.message_callback },
            .upload_manager = upload_manager,
            .scratch_manager = scratch_manager,
        };

        return command_list;
    }

    pub fn destroy(command_list: *CommandList, allocator: Allocator) void {
        allocator.destroy(command_list.upload_manager);
        allocator.destroy(command_list.scratch_manager);
        allocator.destroy(command_list);
    }

    pub const OpenError =
        Queue.CreateCommandBufferError ||
        Dispatch.CommandBufferProxy.BeginCommandBufferError;
    pub fn open(command_list: *CommandList, allocator: Allocator) OpenError!void {
        const queue = command_list.device.queues[
            @intFromEnum(command_list.parameters.queue_type)
        ] orelse @panic("queue not exists");

        const current_cmd_buf = try queue.getOrCreateCommandBuffer(allocator);
        command_list.current_cmd_buf = current_cmd_buf;

        const cmd_buf = Dispatch.CommandBufferProxy.init(
            current_cmd_buf.cmd_buf,
            command_list.context.dispatch.device.wrapper,
        );

        try cmd_buf.beginCommandBuffer(&.{
            .flags = .{ .one_time_submit_bit = true },
        });

        // TODO: get referenced

        command_list.clearState();
    }

    inline fn initCurrentCmdBufProxy(command_list: *CommandList) Dispatch.CommandBufferProxy {
        const current_cmd_buf = command_list.current_cmd_buf orelse
            @panic("no current cmd_buf");
        std.debug.assert(current_cmd_buf.cmd_buf != .null_handle);

        return Dispatch.CommandBufferProxy.init(
            current_cmd_buf.cmd_buf,
            command_list.context.dispatch.device.wrapper,
        );
    }

    pub const CloseError =
        CommitBarriersError ||
        Dispatch.CommandBufferProxy.EndCommandBufferError ||
        FlushVolatileBufferWritesError;
    pub fn close(command_list: *CommandList, allocator: Allocator) CloseError!void {
        command_list.endRenderPass();

        try command_list.resource_state_tracker.keepBufferInitialStates(allocator);
        try command_list.resource_state_tracker.keepTextureInitialStates(allocator);
        try command_list.commitBarriers(allocator);

        const cmd_buf = command_list.initCurrentCmdBufProxy();
        try cmd_buf.endCommandBuffer();

        command_list.clearState();
        try command_list.flushVolatileBufferWrites(allocator);
    }

    const CommitBarriersError = Allocator.Error;
    fn commitBarriers(
        command_list: *CommandList,
        allocator: Allocator,
    ) CommitBarriersError!void {
        const tracker = &command_list.resource_state_tracker;
        if (tracker.buffer_barriers.items.len == 0 and
            tracker.texture_barriers.items.len == 0)
            return;

        command_list.endRenderPass();

        const cmd_buf = command_list.initCurrentCmdBufProxy();

        var image_barriers: std.ArrayListUnmanaged(vulkan.ImageMemoryBarrier2) = .{};
        defer image_barriers.deinit(allocator);

        var buffer_barriers: std.ArrayListUnmanaged(vulkan.BufferMemoryBarrier2) = .{};
        defer buffer_barriers.deinit(allocator);

        for (tracker.texture_barriers.items) |barrier| {
            const before = convertResourceState(barrier.state_before);
            const after = convertResourceState(barrier.state_after);

            std.debug.assert(after.image_layout != .undefined);

            const texture: *Texture = @ptrCast(barrier.texture orelse @panic("barrier texture is not set"));
            const format_info = common.getFormatInfo(texture.desc.format);

            try image_barriers.append(allocator, .{
                .src_access_mask = before.access_mask,
                .dst_access_mask = after.access_mask,
                .src_stage_mask = before.stage_flags,
                .dst_stage_mask = after.stage_flags,
                .old_layout = before.image_layout,
                .new_layout = after.image_layout,
                .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
                .image = texture.image,
                .subresource_range = .{
                    .base_array_layer = if (barrier.entire_texture) 0 else barrier.array_slice,
                    .layer_count = if (barrier.entire_texture) texture.desc.array_size else 1,
                    .base_mip_level = if (barrier.entire_texture) 0 else barrier.mip_level,
                    .level_count = if (barrier.entire_texture) texture.desc.mip_levels else 1,
                    .aspect_mask = .{
                        .depth_bit = format_info.has_depth,
                        .stencil_bit = format_info.has_stencil,
                        .color_bit = !(format_info.has_depth and format_info.has_stencil),
                    },
                },
            });
        }

        if (image_barriers.items.len > 0) {
            cmd_buf.pipelineBarrier2(&.{
                .image_memory_barrier_count = @intCast(image_barriers.items.len),
                .p_image_memory_barriers = image_barriers.items.ptr,
            });
        }

        image_barriers.clearRetainingCapacity();

        for (tracker.buffer_barriers.items) |barrier| {
            const before = convertResourceState(barrier.state_before);
            const after = convertResourceState(barrier.state_after);

            const buffer: *Buffer = @ptrCast(barrier.buffer orelse @panic("barrier buffer is not set"));

            try buffer_barriers.append(allocator, .{
                .src_access_mask = before.access_mask,
                .dst_access_mask = after.access_mask,
                .src_stage_mask = before.stage_flags,
                .dst_stage_mask = after.stage_flags,
                .src_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
                .dst_queue_family_index = vulkan.QUEUE_FAMILY_IGNORED,
                .buffer = buffer.buffer,
                .offset = 0,
                .size = buffer.desc.byte_size,
            });
        }

        if (buffer_barriers.items.len > 0) {
            cmd_buf.pipelineBarrier2(&.{
                .buffer_memory_barrier_count = @intCast(buffer_barriers.items.len),
                .p_buffer_memory_barriers = buffer_barriers.items.ptr,
            });
        }

        buffer_barriers.clearRetainingCapacity();

        tracker.clearBarriers(allocator);
    }

    fn executed(
        command_list: *CommandList,
        queue: *Queue,
        submission_id: u64,
        allocator: Allocator,
    ) Allocator.Error!void {
        const current_cmd_buf = command_list.current_cmd_buf orelse @panic("no current cmd buffer");

        current_cmd_buf.submission_id = submission_id;

        const queue_id = queue.queue_id;
        const recording_id = current_cmd_buf.recording_id;

        command_list.current_cmd_buf = null;

        command_list.submitVolatileBuffers(recording_id, submission_id);
        command_list.resource_state_tracker.commandListSubmitted();

        try command_list.upload_manager.submitChunks(
            Version.make(recording_id, queue_id, false),
            Version.make(submission_id, queue_id, true),
            allocator,
        );

        try command_list.scratch_manager.submitChunks(
            Version.make(recording_id, queue_id, false),
            Version.make(submission_id, queue_id, true),
            allocator,
        );

        command_list.volatile_buffer_states.clearRetainingCapacity();
    }

    fn submitVolatileBuffers(
        command_list: *CommandList,
        recording_id: u64,
        submitted_id: u64,
    ) void {
        const state_to_find = Version.make(
            recording_id,
            command_list.parameters.queue_type,
            false,
        );
        const state_to_replace = Version.make(
            submitted_id,
            command_list.parameters.queue_type,
            true,
        );

        var iter = command_list.volatile_buffer_states.iterator();
        while (iter.next()) |entry| {
            const buffer = entry.key_ptr.*;
            const state = entry.value_ptr;

            if (!state.initialized) continue;

            var version = state.min_version;
            while (version <= state.max_version) : (version += 1) {
                const version_ptr = &buffer.version_tracking.items[@intCast(version)];
                // TODO(0.14.0): buffer.version_tracking.items[@intCast(version)].cmpxchgStrong(...)
                _ = @cmpxchgStrong(
                    u64,
                    @as(*u64, @ptrCast(&version_ptr.raw)),
                    @as(u64, @bitCast(state_to_find)),
                    @as(u64, @bitCast(state_to_replace)),
                    .seq_cst,
                    .seq_cst,
                );
            }
        }
    }

    const FlushVolatileBufferWritesError =
        Allocator.Error ||
        Dispatch.DeviceProxy.FlushMappedMemoryRangesError;
    fn flushVolatileBufferWrites(
        command_list: *CommandList,
        allocator: Allocator,
    ) FlushVolatileBufferWritesError!void {
        var ranges: std.ArrayListUnmanaged(vulkan.MappedMemoryRange) = .{};
        defer ranges.deinit(allocator);

        var iter = command_list.volatile_buffer_states.iterator();
        while (iter.next()) |entry| {
            const buffer = entry.key_ptr.*;
            const state = entry.value_ptr;

            if (state.max_version < state.min_version or !state.initialized)
                continue;

            const num_versions: u32 = @intCast(state.max_version - state.min_version + 1);

            try ranges.append(allocator, .{
                .memory = buffer.memory_resource.memory,
                .offset = @as(u32, @intCast(state.min_version)) * buffer.desc.byte_size,
                .size = num_versions * buffer.desc.byte_size,
            });
        }

        if (ranges.items.len > 0) {
            try command_list.context.dispatch.device.flushMappedMemoryRanges(
                @intCast(ranges.items.len),
                ranges.items.ptr,
            );
        }
    }

    fn clearState(command_list: *CommandList) void {
        command_list.endRenderPass();

        command_list.current_pipeline_layout = .null_handle;
        command_list.current_push_constants_visibility = .{};
        command_list.current_graphics_state = .{};
        command_list.current_compute_state = .{};
        command_list.current_meshlet_state = .{};
        command_list.current_ray_tracing_state = .{};
        command_list.current_shader_table_pointers = .{};
        command_list.any_volatile_buffer_writes = false;
    }

    fn endRenderPass(command_list: *CommandList) void {
        if (command_list.current_meshlet_state.framebuffer != null or
            command_list.current_graphics_state.framebuffer != null)
        {
            const current_cmd_buf = command_list.current_cmd_buf orelse
                @panic("no current cmd_buf");
            std.debug.assert(current_cmd_buf.cmd_buf != .null_handle);

            const cmd_buf = command_list.initCurrentCmdBufProxy();
            cmd_buf.endRenderPass();

            command_list.current_graphics_state.framebuffer = null;
            command_list.current_meshlet_state.framebuffer = null;
        }
    }
};

const EventQuery = struct {
    const Handle = RefCount(EventQuery);

    ref_counter: RefCounter = .{},
    queue: interface.CommandQueue = .graphics,
    command_list_id: u64 = 0,

    pub inline fn asResource(query: *EventQuery) ResourcePtr {
        return .{ .event_query = query };
    }

    pub fn destroy(query: *EventQuery, allocator: Allocator) void {
        allocator.destroy(query);
    }
};

const BufferVersionItem = std.atomic.Value(Version);

const Heap = struct {
    const Handle = RefCount(Heap);

    memory_resource: MemoryResource,
    ref_counter: RefCounter,
    desc: interface.HeapDesc,
    allocator: *VulkanAllocator,

    pub inline fn asResource(heap: *Heap) ResourcePtr {
        return .{ .heap = heap };
    }

    pub fn destroy(heap: *Heap, allocator: Allocator) void {
        allocator.destroy(heap);
    }
};

const Buffer = struct {
    const Handle = RefCount(Buffer);

    memory_resource: MemoryResource,
    ref_counter: RefCounter,
    state_extension: common.BufferStateExtension,
    desc: interface.BufferDesc,
    buffer: vulkan.Buffer,
    device_adress: vulkan.DeviceAddress,
    heap: Heap.Handle,
    view_cache: std.AutoHashMapUnmanaged(u64, vulkan.BufferView),
    version_tracking: std.ArrayListUnmanaged(BufferVersionItem),
    mapped_memory: ?*anyopaque,
    shared_handle: ?*anyopaque,
    version_search_start: u32,
    last_use_queue: interface.CommandQueue,
    last_use_command_list_id: u64,
    context: *const Context,
    allocator: *VulkanAllocator,

    pub inline fn asResource(buffer: *Buffer) ResourcePtr {
        return .{ .buffer = buffer };
    }

    pub fn destroy(buffer: *Buffer, allocator: Allocator) void {
        allocator.destroy(buffer);
    }
};

const TextureSubresourceView = struct {
    texture: *Texture,
    subresource: interface.TextureSubresourceSet,
    view: vulkan.ImageView = .null_handle,
    subresource_range: vulkan.ImageSubresourceRange,
};

const Texture = struct {
    const Handle = RefCount(Texture);

    const TextureSubresourceViewType = enum {
        all_aspects,
        depth_only,
        stencil_only,
    };

    const SubresourceViewKey = struct {
        interface.TextureSubresourceSet,
        TextureSubresourceViewType,
        interface.TextureDimension,
        interface.Format,
        vulkan.ImageUsageFlags,
    };
    const tile_byte_size = 65536;

    memory_resource: MemoryResource = .{},
    ref_counter: RefCounter = .{},
    state_extension: common.TextureStateExtension,
    desc: interface.TextureDesc = undefined,
    image_info: vulkan.ImageCreateInfo = undefined,
    external_memory_image_info: vulkan.ExternalMemoryImageCreateInfo = undefined,
    image: vulkan.Image = .null_handle,
    heap: Heap.Handle = .{},
    shared_handle: ?*anyopaque = null,
    subresource_views: std.AutoHashMapUnmanaged(
        SubresourceViewKey,
        TextureSubresourceView,
    ) = .{},
    context: *const Context,
    allocator: *VulkanAllocator,
    mutex: std.Thread.Mutex = .{},

    pub fn create(
        context: *const Context,
        vulkan_allocator: *VulkanAllocator,
        allocator: Allocator,
    ) Allocator.Error!*Texture {
        const texture = try allocator.create(Texture);
        texture.* = .{
            .state_extension = .{ .desc_ptr = &texture.desc },
            .context = context,
            .allocator = vulkan_allocator,
        };

        return texture;
    }

    pub inline fn asResource(texture: *Texture) ResourcePtr {
        return .{ .texture = texture };
    }

    pub fn destroy(texture: *Texture, allocator: Allocator) void {
        allocator.destroy(texture);
    }
};

const VulkanAllocator = struct {
    context: *const Context,

    fn allocateBufferMemory(allocator: VulkanAllocator, buffer: *Buffer, enable_buffer_address: bool) vulkan.Result {
        _ = allocator;
        _ = buffer;
        _ = enable_buffer_address;
        @panic("not implemented");
    }

    fn freeBufferMemory(allocator: VulkanAllocator, buffer: *Buffer) void {
        _ = allocator;
        _ = buffer;
        @panic("not implemented");
    }

    fn allocateTextureMemory(allocator: VulkanAllocator, texture: *Texture) vulkan.Result {
        _ = allocator;
        _ = texture;
        @panic("not implemented");
    }

    fn freeTextureMemory(allocator: VulkanAllocator, texture: *Texture) void {
        _ = allocator;
        _ = texture;
        @panic("not implemented");
    }

    fn allocateMemory(
        allocator: VulkanAllocator,
        resource: *MemoryResource,
        mem_requirements: vulkan.MemoryRequirements,
        mem_property_flags: vulkan.MemoryPropertyFlags,
        enable_device_address: bool,
        dedicated_image: vulkan.Image,
        dedicated_buffer: vulkan.Buffer,
    ) vulkan.Result {
        _ = allocator;
        _ = resource;
        _ = mem_requirements;
        _ = mem_property_flags;
        _ = enable_device_address;
        _ = dedicated_image;
        _ = dedicated_buffer;

        @panic("not implemented");
    }

    fn freeMemory(allocator: VulkanAllocator, resource: *MemoryResource) void {
        _ = allocator;
        _ = resource;
        @panic("not implemented");
    }
};

const GpuVirtualAddress = u64;

const RefCounter = struct {
    count: std.atomic.Value(u32) = std.atomic.Value(u32).init(1),

    pub fn addRef(ref_counter: *RefCounter) u32 {
        return ref_counter.count.fetchAdd(1, .monotonic) + 1;
    }

    pub fn release(ref_counter: *RefCounter) u32 {
        return ref_counter.count.fetchSub(1, .monotonic) - 1;
    }
};

fn RefCount(Type: type) type {
    return struct {
        const Self = @This();

        opt_ptr: ?*Type = null,

        pub fn initNoRef(other: *Type) Self {
            return .{ .opt_ptr = other };
        }

        pub fn initRef(other: ?*Type) Self {
            var ref_count = .{ .opt_ptr = other };
            ref_count.internalAddRef();
            return ref_count;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            _ = self.internalRelease(allocator);
        }

        pub fn reset(self: *Self, allocator: Allocator) u32 {
            return self.internalRelease(allocator);
        }

        pub fn detach(self: *Self) ?*Type {
            const ptr = self.opt_ptr;
            self.opt_ptr = null;
            return ptr;
        }

        pub fn swap(self: *Self, r: *Self) void {
            const tmp = self.opt_ptr;
            self.opt_ptr = r.opt_ptr;
            r.opt_ptr = tmp;
        }

        pub fn attach(self: *Self, other: *Type) void {
            if (self.opt_ptr) |ptr| {
                const ref = ptr.resource().release();

                std.debug.assert(ref != 0 or ptr != other);
            }

            self.opt_ptr = other;
        }

        fn internalAddRef(self: *Self) void {
            if (self.opt_ptr) |ptr| {
                _ = ptr.asResource().addRef();
            }
        }

        fn internalRelease(self: *Self, allocator: Allocator) u32 {
            var refs: u32 = 0;

            if (self.opt_ptr) |ptr| {
                self.opt_ptr = null;
                refs = ptr.asResource().release(allocator);
            }

            return refs;
        }
    };
}

const Context = struct {
    dispatch: Dispatch,
    instance: vulkan.Instance,
    physical_device: vulkan.PhysicalDevice,
    device: vulkan.Device,
    allocation_callbacks: ?*vulkan.AllocationCallbacks = null,
    pipeline_cache: vulkan.PipelineCache = .null_handle,

    extensions: struct {
        khr_synchronization2: bool = false,
        khr_maintenance1: bool = false,
        ext_debug_report: bool = false,
        ext_debug_marker: bool = false,
        khr_acceleration_structure: bool = false,
        buffer_device_address: bool = false,
        khr_ray_query: bool = false,
        khr_ray_tracing_pipeline: bool = false,
        nv_mesh_shader: bool = false,
        khr_fragment_shading_rate: bool = false,
        ext_conservative_rasterization: bool = false,
        ext_opacity_micromap: bool = false,
        nv_ray_tracing_invocation_reorder: bool = false,
        ext_debug_utils: bool = false,
    } = .{},

    physical_device_properties: vulkan.PhysicalDeviceProperties = undefined,
    ray_tracing_pipeline_properties: vulkan.PhysicalDeviceRayTracingPipelinePropertiesKHR = undefined,
    accel_struct_properties: vulkan.PhysicalDeviceAccelerationStructurePropertiesKHR = undefined,
    conservative_rasterization_properties: vulkan.PhysicalDeviceConservativeRasterizationPropertiesEXT = undefined,
    shading_rate_properties: vulkan.PhysicalDeviceFragmentShadingRatePropertiesKHR = undefined,
    opacity_micromap_properties: vulkan.PhysicalDeviceOpacityMicromapPropertiesEXT = undefined,
    nv_ray_tracing_invocation_reorder_properties: vulkan.PhysicalDeviceRayTracingInvocationReorderPropertiesNV = undefined,
    shading_rate_features: vulkan.PhysicalDeviceFragmentShadingRateFeaturesKHR = undefined,
    message_callback: ?*interface.IMessageCallback = null,
    empty_descriptor_set_layout: vulkan.DescriptorSetLayout = undefined,

    pub const InitError =
        error{CommandLoadFailure} ||
        Allocator.Error;
    fn init(
        desc: *const DeviceDesc,
        get_instance_proc_addr_fn: vulkan.PfnGetInstanceProcAddr,
        allocator: Allocator,
    ) InitError!Context {
        const vkb = try Dispatch.BaseDispatch.load(get_instance_proc_addr_fn);
        const vki = try allocator.create(Dispatch.InstanceDispatch);
        errdefer allocator.destroy(vki);
        vki.* = Dispatch.InstanceDispatch.loadNoFail(
            desc.instance,
            vkb.dispatch.vkGetInstanceProcAddr,
        );

        const instance = Dispatch.InstanceProxy.init(
            desc.instance,
            vki,
        );

        const vkd = try allocator.create(Dispatch.DeviceDispatch);
        errdefer allocator.destroy(vkd);
        vkd.* = Dispatch.DeviceDispatch.loadNoFail(
            desc.device,
            instance.wrapper.dispatch.vkGetDeviceProcAddr,
        );

        const device = Dispatch.DeviceProxy.init(
            desc.device,
            vkd,
        );
        errdefer device.destroyDevice(null);

        var context = Context{
            .message_callback = desc.error_callback,
            .dispatch = .{
                .base = vkb,
                .instance = instance,
                .device = device,
            },
            .instance = desc.instance,
            .physical_device = desc.physical_device,
            .device = desc.device,
        };

        try context.fillInfo(desc, allocator);

        context.pipeline_cache = context.dispatch.device.createPipelineCache(
            &.{},
            context.allocation_callbacks,
        ) catch @panic("failed to create PipelineCache");

        context.empty_descriptor_set_layout = context.dispatch.device.createDescriptorSetLayout(
            &.{ .binding_count = 0, .p_bindings = null },
            context.allocation_callbacks,
        ) catch @panic("failed to create empth DescriptorSetLayout");

        return context;
    }

    fn fillInfo(context: *Context, desc: *const DeviceDesc, allocator: Allocator) Allocator.Error!void {
        const Entry = struct { []const u8, *bool };
        const ext = vulkan.extensions;
        const ctx_ext = &context.extensions;
        const extension_string_map = try std.StaticStringMap(*bool).init(
            [_]Entry{
                .{ ext.ext_conservative_rasterization.name, &ctx_ext.ext_conservative_rasterization },
                .{ ext.ext_debug_marker.name, &ctx_ext.ext_debug_marker },
                .{ ext.ext_debug_report.name, &ctx_ext.ext_debug_report },
                .{ ext.ext_debug_utils.name, &ctx_ext.ext_debug_utils },
                .{ ext.ext_opacity_micromap.name, &ctx_ext.ext_opacity_micromap },
                .{ ext.khr_acceleration_structure.name, &ctx_ext.khr_acceleration_structure },
                .{ ext.khr_buffer_device_address.name, &ctx_ext.buffer_device_address },
                .{ ext.khr_fragment_shading_rate.name, &ctx_ext.khr_fragment_shading_rate },
                .{ ext.khr_maintenance_1.name, &ctx_ext.khr_maintenance1 },
                .{ ext.khr_ray_query.name, &ctx_ext.khr_ray_query },
                .{ ext.khr_ray_tracing_pipeline.name, &ctx_ext.khr_ray_tracing_pipeline },
                .{ ext.khr_synchronization_2.name, &ctx_ext.khr_synchronization2 },
                .{ ext.nv_mesh_shader.name, &ctx_ext.nv_mesh_shader },
                .{ ext.nv_ray_tracing_invocation_reorder.name, &ctx_ext.nv_ray_tracing_invocation_reorder },
            },
            allocator,
        );
        defer extension_string_map.deinit(allocator);

        for (desc.instance_extensions) |ext_name| {
            if (extension_string_map.get(std.mem.span(ext_name))) |ptr| {
                ptr.* = true;
            }
        }

        for (desc.device_extensions) |ext_name| {
            if (extension_string_map.get(std.mem.span(ext_name))) |ptr| {
                ptr.* = true;
            }
        }

        if (ctx_ext.ext_opacity_micromap and !ctx_ext.khr_synchronization2) {
            @panic("ext_opacity_micromap is used without khr_synchronization2");
        }

        context.extensions.buffer_device_address = desc.buffer_device_address_supported;

        var p_next: ?*anyopaque = null;
        var accel_struct_properties = undefinedInit(vulkan.PhysicalDeviceAccelerationStructurePropertiesKHR);
        if (context.extensions.khr_acceleration_structure)
            linkProperties(&accel_struct_properties, &p_next);

        var ray_tracing_pipeline_properties = undefinedInit(vulkan.PhysicalDeviceRayTracingPipelinePropertiesKHR);
        if (context.extensions.khr_ray_tracing_pipeline)
            linkProperties(&ray_tracing_pipeline_properties, &p_next);

        var shading_rate_properties = undefinedInit(vulkan.PhysicalDeviceFragmentShadingRatePropertiesKHR);
        if (context.extensions.khr_fragment_shading_rate)
            linkProperties(&shading_rate_properties, &p_next);

        var conservative_rasterization_properties = undefinedInit(vulkan.PhysicalDeviceConservativeRasterizationPropertiesEXT);
        if (context.extensions.ext_conservative_rasterization)
            linkProperties(&conservative_rasterization_properties, &p_next);

        var opacity_micromap_properties = undefinedInit(vulkan.PhysicalDeviceOpacityMicromapPropertiesEXT);
        if (context.extensions.ext_opacity_micromap)
            linkProperties(&opacity_micromap_properties, &p_next);

        var nv_ray_tracing_invocation_reorder_properties = undefinedInit(vulkan.PhysicalDeviceRayTracingInvocationReorderPropertiesNV);
        if (context.extensions.nv_ray_tracing_invocation_reorder)
            linkProperties(&nv_ray_tracing_invocation_reorder_properties, &p_next);

        var device_properties: vulkan.PhysicalDeviceProperties2 = .{ .p_next = p_next, .properties = undefined };

        context.dispatch.instance.getPhysicalDeviceProperties2(
            context.physical_device,
            &device_properties,
        );

        context.physical_device_properties = device_properties.properties;
        context.accel_struct_properties = accel_struct_properties;
        context.ray_tracing_pipeline_properties = ray_tracing_pipeline_properties;
        context.conservative_rasterization_properties = conservative_rasterization_properties;
        context.shading_rate_properties = shading_rate_properties;
        context.opacity_micromap_properties = opacity_micromap_properties;
        context.nv_ray_tracing_invocation_reorder_properties = nv_ray_tracing_invocation_reorder_properties;

        if (ctx_ext.khr_fragment_shading_rate) {
            var shading_rate_features = undefinedInit(vulkan.PhysicalDeviceFragmentShadingRateFeaturesKHR);
            var device_features: vulkan.PhysicalDeviceFeatures2 = .{ .p_next = &shading_rate_features, .features = undefined };

            context.dispatch.instance.getPhysicalDeviceFeatures2(
                context.physical_device,
                &device_features,
            );

            context.shading_rate_features = shading_rate_features;
        }
    }
};

const ResourcePtr = union(enum) {
    buffer: *Buffer,
    heap: *Heap,
    event_query: *EventQuery,
    texture: *Texture,

    inline fn asResource(resource: ResourcePtr) ResourcePtr {
        return resource;
    }

    pub fn addRef(resource: ResourcePtr) u32 {
        return switch (resource) {
            inline else => |impl| impl.ref_counter.addRef(),
        };
    }

    pub fn release(resource: ResourcePtr, allocator: Allocator) u32 {
        const refs = switch (resource) {
            inline else => |impl| impl.ref_counter.release(),
        };

        if (refs == 0) {
            switch (resource) {
                inline else => |impl| impl.destroy(allocator),
            }
        }

        return refs;
    }
};

const TrackedCommandBuffer = struct {
    cmd_buf: vulkan.CommandBuffer = .null_handle,
    cmd_pool: vulkan.CommandPool = .null_handle,
    referenced_resources: std.ArrayListUnmanaged(RefCount(ResourcePtr)) = .{},
    referenced_staging_buffers: std.ArrayListUnmanaged(RefCount(Buffer)) = .{},
    recording_id: u64 = 0,
    submission_id: u64 = 0,
    context: *const Context,
};

const Queue = struct {
    tracking_semaphore: vulkan.Semaphore = .null_handle,
    context: *const Context = undefined,
    queue: vulkan.Queue = .null_handle,
    queue_id: interface.CommandQueue = undefined,
    queue_family_index: u32 = 0,
    mutex: std.Thread.Mutex = .{},
    // maybe use SoA approach?
    wait_semaphores: std.ArrayListUnmanaged(vulkan.Semaphore) = .{},
    wait_semaphore_values: std.ArrayListUnmanaged(u64) = .{},
    // maybe use SoA approach?
    signal_semaphores: std.ArrayListUnmanaged(vulkan.Semaphore) = .{},
    signal_semaphore_values: std.ArrayListUnmanaged(u64) = .{},
    last_recording_id: u64 = 0,
    last_submitted_id: u64 = 0,
    last_finished_id: u64 = 0,
    command_buffers_in_flight: std.SinglyLinkedList(*TrackedCommandBuffer) = .{},
    command_buffers_pool: std.SinglyLinkedList(*TrackedCommandBuffer) = .{},

    fn create(
        context: *const Context,
        queue_id: interface.CommandQueue,
        queue: vulkan.Queue,
        queue_family_index: u32,
        allocator: Allocator,
    ) Allocator.Error!*Queue {
        const semaphore_type_info = vulkan.SemaphoreTypeCreateInfo{
            .semaphore_type = .timeline,
            .initial_value = 0,
        };

        const queue_ptr = try allocator.create(Queue);

        queue_ptr.* = .{
            .tracking_semaphore = context.dispatch.device.createSemaphore(
                &.{ .p_next = &semaphore_type_info },
                context.allocation_callbacks,
            ) catch @panic("failed to create Semaphore"),
            .context = context,
            .queue_id = queue_id,
            .queue = queue,
            .queue_family_index = queue_family_index,
        };

        return queue_ptr;
    }

    fn destroy(queue: *Queue, allocator: Allocator) void {
        queue.context.dispatch.device.destroySemaphore(
            queue.tracking_semaphore,
            queue.context.allocation_callbacks,
        );
        queue.tracking_semaphore = .null_handle;

        // TODO destroySemaphore for each wait semaphore
        queue.wait_semaphores.deinit(allocator);
        queue.wait_semaphore_values.deinit(allocator);
        // TODO destroySemaphore for each signal semaphore
        queue.signal_semaphores.deinit(allocator);
        queue.signal_semaphore_values.deinit(allocator);

        allocator.destroy(queue);
    }

    const SubmitError =
        Dispatch.QueueProxy.QueueSubmitError ||
        Allocator.Error;
    fn submit(queue: *Queue, cmd_lists: []const *const CommandList, allocator: Allocator) SubmitError!u64 {
        var wait_stage_array = wait_stage_array: {
            const array = try std.ArrayListUnmanaged(vulkan.PipelineStageFlags).initCapacity(
                allocator,
                queue.wait_semaphores.items.len,
            );

            for (array.items) |*flags| {
                flags.* = .{ .top_of_pipe_bit = true };
            }

            break :wait_stage_array array;
        };
        defer wait_stage_array.deinit(allocator);

        var command_buffers = try std.ArrayListUnmanaged(vulkan.CommandBuffer).initCapacity(
            allocator,
            cmd_lists.len,
        );
        defer command_buffers.deinit(allocator);

        queue.last_submitted_id += 1;

        for (cmd_lists) |cmd_list| {
            const command_buffer = cmd_list.current_cmd_buf orelse @panic("no current cmd buffer");
            command_buffers.appendAssumeCapacity(command_buffer.cmd_buf);

            const node = try allocator.create(std.SinglyLinkedList(*TrackedCommandBuffer).Node);
            node.* = .{ .data = command_buffer };
            queue.command_buffers_in_flight.prepend(node);

            for (command_buffer.referenced_staging_buffers.items) |buffer_ref| {
                const buffer = buffer_ref.opt_ptr orelse @panic("empty buffer ref");
                buffer.last_use_queue = queue.queue_id;
                buffer.last_use_command_list_id = queue.last_submitted_id;
            }
        }

        try queue.signal_semaphores.append(allocator, queue.tracking_semaphore);
        try queue.signal_semaphore_values.append(allocator, queue.last_submitted_id);

        const timeline_semaphore_info = vulkan.TimelineSemaphoreSubmitInfo{
            .wait_semaphore_value_count = @intCast(queue.wait_semaphore_values.items.len),
            .p_wait_semaphore_values = queue.wait_semaphore_values.items.ptr,
            .signal_semaphore_value_count = @intCast(queue.signal_semaphore_values.items.len),
            .p_signal_semaphore_values = queue.signal_semaphore_values.items.ptr,
        };

        const queue_proxy = Dispatch.QueueProxy.init(
            queue.queue,
            queue.context.dispatch.device.wrapper,
        );

        try queue_proxy.submit(
            1,
            &.{
                .{
                    .p_next = &timeline_semaphore_info,
                    .wait_semaphore_count = @intCast(queue.wait_semaphores.items.len),
                    .p_wait_semaphores = queue.wait_semaphores.items.ptr,
                    .p_wait_dst_stage_mask = wait_stage_array.items.ptr,
                    .command_buffer_count = @intCast(command_buffers.items.len),
                    .p_command_buffers = command_buffers.items.ptr,
                    .signal_semaphore_count = @intCast(queue.signal_semaphores.items.len),
                    .p_signal_semaphores = queue.signal_semaphores.items.ptr,
                },
            },
            .null_handle,
        );

        queue.wait_semaphores.clearRetainingCapacity();
        queue.wait_semaphore_values.clearRetainingCapacity();
        queue.signal_semaphores.clearRetainingCapacity();
        queue.signal_semaphore_values.clearRetainingCapacity();

        return queue.last_submitted_id;
    }

    fn addWaitSemaphore(queue: *Queue, semaphore: vulkan.Semaphore, value: u64, allocator: Allocator) Allocator.Error!void {
        if (semaphore == .null_handle) return;

        try queue.wait_semaphores.append(allocator, semaphore);
        try queue.wait_semaphore_values.append(allocator, value);
    }

    fn addSignalSemaphore(queue: *Queue, semaphore: vulkan.Semaphore, value: u64, allocator: Allocator) Allocator.Error!void {
        if (semaphore == .null_handle) return;

        try queue.signal_semaphores.append(allocator, semaphore);
        try queue.signal_semaphore_values.append(allocator, value);
    }

    pub const CreateCommandBufferError =
        Allocator.Error ||
        Dispatch.DeviceProxy.CreateCommandPoolError ||
        Dispatch.DeviceProxy.AllocateCommandBuffersError;
    fn createCommandBuffer(
        queue: *Queue,
        allocator: Allocator,
    ) CreateCommandBufferError!*TrackedCommandBuffer {
        const cmd_buf_ptr = try allocator.create(TrackedCommandBuffer);
        errdefer allocator.destroy(cmd_buf_ptr);
        cmd_buf_ptr.* = .{ .context = queue.context };

        cmd_buf_ptr.cmd_pool = try queue.context.dispatch.device.createCommandPool(
            &.{
                .queue_family_index = queue.queue_family_index,
                .flags = .{
                    .reset_command_buffer_bit = true,
                    .transient_bit = true,
                },
            },
            queue.context.allocation_callbacks,
        );
        errdefer queue.context.dispatch.device.destroyCommandPool(
            cmd_buf_ptr.cmd_pool,
            queue.context.allocation_callbacks,
        );

        try queue.context.dispatch.device.allocateCommandBuffers(
            &.{
                .level = .primary,
                .command_pool = cmd_buf_ptr.cmd_pool,
                .command_buffer_count = 1,
            },
            @ptrCast(&cmd_buf_ptr.cmd_buf),
        );

        return cmd_buf_ptr;
    }

    fn getOrCreateCommandBuffer(
        queue: *Queue,
        allocator: Allocator,
    ) Queue.CreateCommandBufferError!*TrackedCommandBuffer {
        queue.mutex.lock();
        defer queue.mutex.unlock();

        queue.last_recording_id += 1;
        const rec_id = queue.last_recording_id;

        const cmd_buf_ptr = if (queue.command_buffers_pool.popFirst()) |node|
            node.data
        else
            try queue.createCommandBuffer(allocator);

        cmd_buf_ptr.recording_id = rec_id;

        return cmd_buf_ptr;
    }
};

const BitSetAllocator = struct {};

pub const DeviceDesc = struct {
    const QueueParam = struct {
        queue: vulkan.Queue,
        index: u32,
    };

    error_callback: ?*interface.IMessageCallback = null,
    instance: vulkan.Instance,
    physical_device: vulkan.PhysicalDevice,
    device: vulkan.Device,
    graphics_queue: ?QueueParam = null,
    transfer_queue: ?QueueParam = null,
    compute_queue: ?QueueParam = null,
    allocation_callbacks: ?*vulkan.AllocationCallbacks = null,
    instance_extensions: []const [*:0]const u8,
    device_extensions: []const [*:0]const u8,
    max_timer_queries: u32 = 256,
    buffer_device_address_supported: bool = false,
};

const MemoryResource = struct {
    managed: bool = true,
    memory: vulkan.DeviceMemory = .null_handle,
};

pub const Device = struct {
    const queue_count = @typeInfo(interface.CommandQueue).Enum.fields.len;

    context: Context,
    allocator: VulkanAllocator,
    timer_query_pool: vulkan.QueryPool = .null_handle,
    timer_query_allocator: BitSetAllocator = .{},
    mutex: std.Thread.Mutex = .{},
    queues: [queue_count]?*Queue = [_]?*Queue{null} ** queue_count,

    pub const CreateError =
        Context.InitError ||
        Allocator.Error;
    pub fn create(
        desc: *const DeviceDesc,
        get_instance_proc_addr_fn: vulkan.PfnGetInstanceProcAddr,
        allocator: Allocator,
    ) CreateError!*Device {
        const dev_ptr = try allocator.create(Device);
        errdefer allocator.destroy(dev_ptr);

        dev_ptr.* = .{
            .context = try Context.init(desc, get_instance_proc_addr_fn, allocator),
            .allocator = VulkanAllocator{
                .context = &dev_ptr.context,
            },
        };

        if (desc.graphics_queue) |queue| {
            dev_ptr.queues[@intFromEnum(interface.CommandQueue.graphics)] = try Queue.create(
                &dev_ptr.context,
                .graphics,
                queue.queue,
                queue.index,
                allocator,
            );
        }

        if (desc.compute_queue) |queue| {
            dev_ptr.queues[@intFromEnum(interface.CommandQueue.compute)] = try Queue.create(
                &dev_ptr.context,
                .compute,
                queue.queue,
                queue.index,
                allocator,
            );
        }

        if (desc.transfer_queue) |queue| {
            dev_ptr.queues[@intFromEnum(interface.CommandQueue.copy)] = try Queue.create(
                &dev_ptr.context,
                .copy,
                queue.queue,
                queue.index,
                allocator,
            );
        }

        return dev_ptr;
    }

    pub fn destroy(device: *Device, allocator: Allocator) void {
        for (&device.queues) |opt_queue_ptr| {
            const queue = opt_queue_ptr orelse continue;
            queue.destroy(allocator);
        }
    }

    pub fn queueWaitForSemaphore(
        device: *Device,
        wait_queue_id: interface.CommandQueue,
        semaphore: vulkan.Semaphore,
        value: u64,
        allocator: Allocator,
    ) Allocator.Error!void {
        const wait_queue = device.queues[
            @intFromEnum(wait_queue_id)
        ] orelse @panic("queue not exists");

        try wait_queue.addWaitSemaphore(semaphore, value, allocator);
    }

    pub fn queueSignalSemaphore(
        device: *Device,
        execution_queue_id: interface.CommandQueue,
        semaphore: vulkan.Semaphore,
        value: u64,
        allocator: Allocator,
    ) Allocator.Error!void {
        const execution_queue = device.queues[
            @intFromEnum(execution_queue_id)
        ] orelse @panic("queue not exists");

        try execution_queue.addSignalSemaphore(semaphore, value, allocator);
    }

    pub fn createEventQuery(allocator: Allocator) Allocator.Error!*EventQuery {
        const event_query = try allocator.create(EventQuery);
        event_query.* = .{};

        return event_query;
    }

    pub fn setEventQuery(
        device: *const Device,
        query: *EventQuery,
        queue: interface.CommandQueue,
    ) void {
        std.debug.assert(query.command_list_id == 0);

        const queue_ptr = device.queues[@intFromEnum(queue)] orelse @panic("queue not exists");

        query.queue = queue;
        query.command_list_id = queue_ptr.last_submitted_id;
    }

    pub fn createWrapperForNativeTexture(
        device: *Device,
        image: vulkan.Image,
        desc: *const interface.TextureDesc,
        allocator: Allocator,
    ) Allocator.Error!*Texture {
        std.debug.assert(image != .null_handle);

        const texture = try Texture.create(
            &device.context,
            &device.allocator,
            allocator,
        );
        fillTextureInfo(texture, desc);

        texture.image = image;
        texture.memory_resource.managed = false;

        return texture;
    }

    pub fn createCommandList(
        device: *Device,
        params: *const interface.CommandListParameters,
        allocator: Allocator,
    ) Allocator.Error!*CommandList {
        return try CommandList.create(
            device,
            &device.context,
            params,
            allocator,
        );
    }

    pub const ExecuteCommandListsError = Allocator.Error || Queue.SubmitError;
    pub fn executeCommandLists(
        device: *Device,
        command_lists: []const *CommandList,
        exec_queue: interface.CommandQueue,
        allocator: Allocator,
    ) ExecuteCommandListsError!u64 {
        const queue_ptr = device.queues[@intFromEnum(exec_queue)] orelse @panic("queue not exists");
        const submission_id = try queue_ptr.submit(command_lists, allocator);

        for (command_lists) |cmd_list_ptr| {
            try cmd_list_ptr.executed(queue_ptr, submission_id, allocator);
        }

        return submission_id;
    }
};

inline fn linkProperties(properties_ptr: anytype, p_next: *?*anyopaque) void {
    properties_ptr.p_next = p_next.*;
    p_next.* = @ptrCast(properties_ptr);
}

fn fillTextureInfo(texture: *Texture, desc: *const interface.TextureDesc) void {
    texture.desc = desc.*;
    texture.image_info = .{
        .image_type = textureDimensionToImageType(desc.dimension),
        .extent = .{ .width = desc.width, .height = desc.height, .depth = desc.depth },
        .mip_levels = desc.mip_levels,
        .array_layers = desc.array_size,
        .format = convertFormat(desc.format),
        .initial_layout = .undefined,
        .usage = pickImageUsageFlags(desc),
        .sharing_mode = .exclusive,
        .samples = pickImageSampleCount(desc),
        .flags = pickImageCreateFlags(desc),
        .tiling = .optimal,
    };

    texture.external_memory_image_info = .{
        .handle_types = .{ .opaque_fd_bit = true },
    };

    if (desc.shared_resource_flags == .shared)
        texture.image_info.p_next = &texture.external_memory_image_info;
}

inline fn textureDimensionToImageType(dim: interface.TextureDimension) vulkan.ImageType {
    return switch (dim) {
        .texture_1d, .texture_1d_array => .@"1d",
        .texture_2d,
        .texture_2d_array,
        .texture_cube,
        .texture_cube_array,
        .texture_2d_ms,
        .texture_2d_ms_array,
        => .@"2d",
        .texture_3d => .@"3d",
        else => @panic("invalid texture dimension value"),
    };
}

inline fn pickImageUsageFlags(desc: *const interface.TextureDesc) vulkan.ImageUsageFlags {
    const format_info = common.getFormatInfo(desc.format);

    return .{
        .transfer_src_bit = true,
        .transfer_dst_bit = true,
        .sampled_bit = desc.is_shader_resource,
        .storage_bit = desc.is_uav,
        .fragment_shading_rate_attachment_bit_khr = desc.is_shading_rate_surface,
        .depth_stencil_attachment_bit = desc.is_render_target and
            (format_info.has_depth or format_info.has_stencil),
        .color_attachment_bit = desc.is_render_target and
            !(format_info.has_depth or format_info.has_stencil),
    };
}

inline fn pickImageSampleCount(desc: *const interface.TextureDesc) vulkan.SampleCountFlags {
    return switch (desc.sample_count) {
        1 => .{ .@"1_bit" = true },
        2 => .{ .@"2_bit" = true },
        4 => .{ .@"4_bit" = true },
        8 => .{ .@"8_bit" = true },
        16 => .{ .@"16_bit" = true },
        32 => .{ .@"32_bit" = true },
        64 => .{ .@"64_bit" = true },
        else => @panic("invalid sample_count value"),
    };
}

inline fn pickImageCreateFlags(desc: *const interface.TextureDesc) vulkan.ImageCreateFlags {
    return .{
        .cube_compatible_bit = desc.dimension == .texture_cube or
            desc.dimension == .texture_cube_array,
        .mutable_format_bit = desc.is_typeless,
        .extended_usage_bit = desc.is_typeless,
        .sparse_binding_bit = desc.is_tiled,
        .sparse_residency_bit = desc.is_tiled,
    };
}

fn convertResourceStateToMapping(state: interface.ResourceStates) constants.ResourceStateMapEntry {
    var res_rhi_state = interface.ResourceStates{};
    var res_stage_flags = vulkan.PipelineStageFlags2{};
    var res_access_mask = vulkan.AccessFlags2{};
    var res_image_layout = vulkan.ImageLayout.undefined;
    const num_state_bits = constants.resource_state_map.len;
    var tmp_state: u32 = @bitCast(state);
    var bit_index: u32 = 0;

    while (tmp_state != 0 and bit_index < num_state_bits) : (bit_index += 1) {
        const bit: u32 = @as(u32, 1) << @intCast(bit_index);

        if ((tmp_state & bit) != 0) {
            const mapping_rhi_state, const mapping_stage_flags, const mapping_access_mask, const mapping_image_layout = constants.resource_state_map[bit_index];
            std.debug.assert(@as(u32, @bitCast(mapping_rhi_state)) == bit);
            std.debug.assert(
                res_image_layout == .undefined or
                    mapping_image_layout == .undefined or
                    res_image_layout == mapping_image_layout,
            );

            res_rhi_state = @bitCast(
                @as(u32, @bitCast(res_rhi_state)) | @as(u32, @bitCast(mapping_rhi_state)),
            );
            res_access_mask = res_access_mask.merge(mapping_access_mask);
            res_stage_flags = res_stage_flags.merge(mapping_stage_flags);

            if (mapping_image_layout != .undefined)
                res_image_layout = mapping_image_layout;

            tmp_state &= ~bit;
        }
    }

    std.debug.assert(@as(u32, @bitCast(res_rhi_state)) == @as(u32, @bitCast(state)));

    return .{
        res_rhi_state,
        res_stage_flags,
        res_access_mask,
        res_image_layout,
    };
}

inline fn convertResourceState(state: interface.ResourceStates) constants.ResourceStateMapping {
    return constants.ResourceStateMapping.fromEntry(
        convertResourceStateToMapping(state),
    );
}

pub inline fn convertFormat(format: interface.Format) vulkan.Format {
    std.debug.assert(@intFromEnum(format) < @typeInfo(interface.Format).Enum.fields.len);
    const from, const to = constants.format_map[@intFromEnum(format)];
    std.debug.assert(from == format);

    return to;
}

const constants = struct {
    const ResourceStateMapping = struct { // for use with KHR_synchronization2
        rhi_state: interface.ResourceStates,
        stage_flags: vulkan.PipelineStageFlags2,
        access_mask: vulkan.AccessFlags2,
        image_layout: vulkan.ImageLayout,

        fn fromEntry(entry: ResourceStateMapEntry) ResourceStateMapping {
            const rhi_state, const stage_flags, const access_mask, const image_layout = entry;

            return .{
                .rhi_state = rhi_state,
                .stage_flags = stage_flags,
                .access_mask = access_mask,
                .image_layout = image_layout,
            };
        }
    };

    const ResourceStateMapEntry = struct {
        interface.ResourceStates,
        vulkan.PipelineStageFlags2,
        vulkan.AccessFlags2,
        vulkan.ImageLayout,
    };
    const resource_state_map = [_]ResourceStateMapEntry{
        .{
            .{ .common = true },
            .{ .top_of_pipe_bit = true },
            .{},
            .undefined,
        },
        .{
            .{ .constant_buffer = true },
            .{ .all_commands_bit = true },
            .{ .uniform_read_bit = true },
            .undefined,
        },
        .{
            .{ .vertex_buffer = true },
            .{ .vertex_input_bit = true },
            .{ .vertex_attribute_read_bit = true },
            .undefined,
        },
        .{
            .{ .index_buffer = true },
            .{ .vertex_input_bit = true },
            .{ .index_read_bit = true },
            .undefined,
        },
        .{
            .{ .indirect_argument = true },
            .{ .draw_indirect_bit = true },
            .{ .indirect_command_read_bit = true },
            .undefined,
        },
        .{
            .{ .shader_resource = true },
            .{ .all_commands_bit = true },
            .{ .shader_read_bit = true },
            .shader_read_only_optimal,
        },
        .{
            .{ .unordered_access = true },
            .{ .all_commands_bit = true },
            .{ .shader_read_bit = true, .shader_write_bit = true },
            .general,
        },
        .{
            .{ .render_target = true },
            .{ .color_attachment_output_bit = true },
            .{ .color_attachment_read_bit = true, .color_attachment_write_bit = true },
            .color_attachment_optimal,
        },
        .{
            .{ .depth_write = true },
            .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
            .{ .depth_stencil_attachment_read_bit = true, .depth_stencil_attachment_write_bit = true },
            .depth_stencil_attachment_optimal,
        },
        .{
            .{ .depth_read = true },
            .{ .early_fragment_tests_bit = true, .late_fragment_tests_bit = true },
            .{ .depth_stencil_attachment_read_bit = true },
            .depth_stencil_read_only_optimal,
        },
        .{
            .{ .stream_out = true },
            .{ .transform_feedback_bit_ext = true },
            .{ .transform_feedback_write_bit_ext = true },
            .undefined,
        },
        .{
            .{ .copy_dest = true },
            .{ .all_transfer_bit = true },
            .{ .transfer_write_bit = true },
            .transfer_dst_optimal,
        },
        .{
            .{ .copy_source = true },
            .{ .all_transfer_bit = true },
            .{ .transfer_read_bit = true },
            .transfer_src_optimal,
        },
        .{
            .{ .resolve_dest = true },
            .{ .all_transfer_bit = true },
            .{ .transfer_write_bit = true },
            .transfer_dst_optimal,
        },
        .{
            .{ .resolve_source = true },
            .{ .all_transfer_bit = true },
            .{ .transfer_read_bit = true },
            .transfer_src_optimal,
        },
        .{
            .{ .present = true },
            .{ .all_commands_bit = true },
            .{ .memory_read_bit = true },
            .present_src_khr,
        },
        .{
            .{ .accel_struct_read = true },
            .{ .ray_tracing_shader_bit_khr = true, .compute_shader_bit = true },
            .{ .acceleration_structure_read_bit_khr = true },
            .undefined,
        },
        .{
            .{ .accel_struct_write = true },
            .{ .acceleration_structure_build_bit_khr = true },
            .{ .acceleration_structure_write_bit_khr = true },
            .undefined,
        },
        .{
            .{ .accel_struct_build_input = true },
            .{ .acceleration_structure_build_bit_khr = true },
            .{ .acceleration_structure_read_bit_khr = true },
            .undefined,
        },
        .{
            .{ .accel_struct_build_blas = true },
            .{ .acceleration_structure_build_bit_khr = true },
            .{ .acceleration_structure_read_bit_khr = true },
            .undefined,
        },
        .{
            .{ .shading_rate_surface = true },
            .{ .fragment_shading_rate_attachment_bit_khr = true },
            .{ .fragment_shading_rate_attachment_read_bit_khr = true },
            .fragment_shading_rate_attachment_optimal_khr,
        },
        .{
            .{ .opacity_micromap_write = true },
            .{ .micromap_build_bit_ext = true },
            .{ .micromap_write_bit_ext = true },
            .undefined,
        },
        .{
            .{ .opacity_micromap_build_input = true },
            .{ .micromap_build_bit_ext = true },
            .{ .shader_read_bit = true },
            .undefined,
        },
    };

    const FormatMapEntry = struct { interface.Format, vulkan.Format };
    const format_map = [_]FormatMapEntry{
        .{ .unknown, .undefined },
        .{ .r8_uint, .r8_uint },
        .{ .r8_sint, .r8_sint },
        .{ .r8_unorm, .r8_unorm },
        .{ .r8_snorm, .r8_snorm },
        .{ .rg8_uint, .r8g8_uint },
        .{ .rg8_sint, .r8g8_sint },
        .{ .rg8_unorm, .r8g8_unorm },
        .{ .rg8_snorm, .r8g8_snorm },
        .{ .r16_uint, .r16_uint },
        .{ .r16_sint, .r16_sint },
        .{ .r16_unorm, .r16_unorm },
        .{ .r16_snorm, .r16_snorm },
        .{ .r16_float, .r16_sfloat },
        .{ .bgra4_unorm, .b4g4r4a4_unorm_pack16 },
        .{ .b5g6r5_unorm, .b5g6r5_unorm_pack16 },
        .{ .b5g5r5a1_unorm, .b5g5r5a1_unorm_pack16 },
        .{ .rgba8_uint, .r8g8b8a8_uint },
        .{ .rgba8_sint, .r8g8b8a8_sint },
        .{ .rgba8_unorm, .r8g8b8a8_unorm },
        .{ .rgba8_snorm, .r8g8b8a8_snorm },
        .{ .bgra8_unorm, .b8g8r8a8_unorm },
        .{ .srgba8_unorm, .r8g8b8a8_srgb },
        .{ .sbgra8_unorm, .b8g8r8a8_srgb },
        .{ .r10g10b10a2_unorm, .a2b10g10r10_unorm_pack32 },
        .{ .r11g11b10_float, .b10g11r11_ufloat_pack32 },
        .{ .rg16_uint, .r16g16_uint },
        .{ .rg16_sint, .r16g16_sint },
        .{ .rg16_unorm, .r16g16_unorm },
        .{ .rg16_snorm, .r16g16_snorm },
        .{ .rg16_float, .r16g16_sfloat },
        .{ .r32_uint, .r32_uint },
        .{ .r32_sint, .r32_sint },
        .{ .r32_float, .r32_sfloat },
        .{ .rgba16_uint, .r16g16b16a16_uint },
        .{ .rgba16_sint, .r16g16b16a16_sint },
        .{ .rgba16_float, .r16g16b16a16_sfloat },
        .{ .rgba16_unorm, .r16g16b16a16_unorm },
        .{ .rgba16_snorm, .r16g16b16a16_snorm },
        .{ .rg32_uint, .r32g32_uint },
        .{ .rg32_sint, .r32g32_sint },
        .{ .rg32_float, .r32g32_sfloat },
        .{ .rgb32_uint, .r32g32b32_uint },
        .{ .rgb32_sint, .r32g32b32_sint },
        .{ .rgb32_float, .r32g32b32_sfloat },
        .{ .rgba32_uint, .r32g32b32a32_uint },
        .{ .rgba32_sint, .r32g32b32a32_sint },
        .{ .rgba32_float, .r32g32b32a32_sfloat },
        .{ .d16, .d16_unorm },
        .{ .d24s8, .d24_unorm_s8_uint },
        .{ .x24g8_uint, .d24_unorm_s8_uint },
        .{ .d32, .d32_sfloat },
        .{ .d32s8, .d32_sfloat_s8_uint },
        .{ .x32g8_uint, .d32_sfloat_s8_uint },
        .{ .bc1_unorm, .bc1_rgba_unorm_block },
        .{ .bc1_unorm_srgb, .bc1_rgba_srgb_block },
        .{ .bc2_unorm, .bc2_unorm_block },
        .{ .bc2_unorm_srgb, .bc2_srgb_block },
        .{ .bc3_unorm, .bc3_unorm_block },
        .{ .bc3_unorm_srgb, .bc3_srgb_block },
        .{ .bc4_unorm, .bc4_unorm_block },
        .{ .bc4_snorm, .bc4_snorm_block },
        .{ .bc5_unorm, .bc5_unorm_block },
        .{ .bc5_snorm, .bc5_snorm_block },
        .{ .bc6h_ufloat, .bc6h_ufloat_block },
        .{ .bc6h_sfloat, .bc6h_sfloat_block },
        .{ .bc7_unorm, .bc7_unorm_block },
        .{ .bc7_unorm_srgb, .bc7_srgb_block },
    };
};

fn undefinedInit(T: type) T {
    const struct_info = @typeInfo(T).Struct;

    var value: T = if (struct_info.layout == .@"extern") std.mem.zeroes(T) else undefined;

    inline for (struct_info.fields) |field| {
        if (field.is_comptime) {
            continue;
        }

        if (field.default_value) |default_value_ptr| {
            const default_value = @as(*align(1) const field.type, @ptrCast(default_value_ptr)).*;
            @field(value, field.name) = default_value;
        } else {
            @field(value, field.name) = undefined;
        }
    }

    return value;
}
