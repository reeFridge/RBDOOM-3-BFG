//! @exportCVars
const global = @import("../global.zig");
const FrameData = @import("../renderer/frame_data.zig");
const std = @import("std");
const nvrhi = @import("../renderer/nvrhi.zig");
const GLImplParams = @import("../renderer/render_system.zig").GLImplParams;
const vulkan = @import("vulkan");
const vulkan_impl = @import("sdl/vulkan.zig");
const c = @import("c_import.zig").c;

pub var vma_allocator: c.VmaAllocator = null;

const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;
const CFlags = cvar.CVarFlags;

pub var r_vma_device_local_memory_mb = CVar.init(
    "r_vmaDeviceLocalMemoryMB",
    "256",
    CFlags.CVAR_INTEGER | CFlags.CVAR_INIT | CFlags.CVAR_NEW,
    "Size of VMA allocation block for gpu memory.",
);

pub var r_vk_prefer_fast_sync = CVar.init(
    "r_vkPreferFastSync",
    "1",
    CFlags.CVAR_RENDERER | CFlags.CVAR_ARCHIVE | CFlags.CVAR_BOOL | CFlags.CVAR_NEW,
    "Prefer Fast Sync/no-tearing in place of VSync off/tearing",
);

pub const DeviceManager = opaque {
    extern fn c_deviceManager_getDevice(*DeviceManager) *nvrhi.IDevice;
    extern fn c_deviceManager_create(nvrhi.GraphicsAPI) *DeviceManager;
    extern fn c_deviceManager_destroy(*DeviceManager) void;
    extern fn c_deviceManager_present(*DeviceManager) void;
    extern fn c_deviceManager_updateWindowSize(*DeviceManager, GLImplParams) void;
    extern fn c_deviceManager_beginFrame(*DeviceManager) void;
    extern fn c_deviceManager_endFrame(*DeviceManager) void;
    extern fn c_deviceManager_getGraphicsApi(*const DeviceManager) nvrhi.GraphicsAPI;

    pub fn beginFrame(device_manager: *DeviceManager) void {
        c_deviceManager_beginFrame(device_manager);
    }

    pub fn endFrame(device_manager: *DeviceManager) void {
        c_deviceManager_endFrame(device_manager);
    }

    pub fn updateWindowSize(device_manager: *DeviceManager, params: GLImplParams) void {
        c_deviceManager_updateWindowSize(device_manager, params);
    }

    pub fn present(device_manager: *DeviceManager) void {
        c_deviceManager_present(device_manager);
    }

    pub fn getDevice(device_manager: *DeviceManager) *nvrhi.IDevice {
        return c_deviceManager_getDevice(device_manager);
    }

    pub fn create(api: nvrhi.GraphicsAPI) *DeviceManager {
        return c_deviceManager_create(api);
    }

    pub fn destroy(device_manager: *DeviceManager) void {
        c_deviceManager_destroy(device_manager);
    }

    pub fn getGraphicsApi(device_manager: *const DeviceManager) nvrhi.GraphicsAPI {
        return c_deviceManager_getGraphicsApi(device_manager);
    }
};

extern var deviceManager: ?*DeviceManager;

var vk: ?*DeviceManagerVulkan = null;

pub inline fn instance() *DeviceManagerVulkan {
    return vk orelse @panic("DeviceManager.vk is not initialized");
}

pub fn init(api: nvrhi.GraphicsAPI) DeviceManagerVulkan.CreateError!void {
    if (deviceManager != null) @panic("DeviceManager.deviceManager already created");
    if (vk != null) @panic("DeviceManager.vk already created");

    if (api == .VULKAN) {
        vk = try DeviceManagerVulkan.create(global.gpa.allocator());
    } else {
        deviceManager = DeviceManager.create(api);
    }
}

pub fn deinit() void {
    if (deviceManager) |device_manager| {
        device_manager.destroy();
        deviceManager = null;
    }

    if (vk) |device_manager| {
        device_manager.destroy();
        vk = null;
    }
}

pub const DeviceCreationParams = struct {
    start_maximized: bool = false,
    start_fullscreen: bool = false,
    allow_mode_switch: bool = false,
    window_pos_x: ?u32 = null, // null means use default placement
    window_pos_y: ?u32 = null,
    back_buffer_width: u32 = 1280,
    back_buffer_height: u32 = 720,
    back_buffer_sample_count: u32 = 1, // optional HDR Framebuffer MSAA
    refresh_rate: u32 = 0,
    swap_chain_buffer_count: u32 = FrameData.NUM_FRAME_DATA,
    swap_chain_format: nvrhi.Format = .RGBA8_UNORM,
    swap_chain_sample_count: u32 = 1,
    swap_chain_sample_quality: u32 = 0,
    enable_debug_runtime: bool = false,
    enable_nvrhi_validation_layer: bool = false,
    vsync_enabled: bool = false,
    enable_ray_tracing_extensions: bool = false,
    enable_compute_queue: bool = false,
    enable_copy_queue: bool = false,
    enable_per_monitor_dpi: bool = false,
    enable_image_format_d24s8: bool = true,
};

pub const DeviceManagerVulkan = struct {
    const required_instance_extensions: []const vulkan.ApiInfo = &.{
        vulkan.extensions.khr_surface,
        vulkan.extensions.khr_get_physical_device_properties_2,
    };
    const required_device_extensions: []const vulkan.ApiInfo = &.{
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
        vulkan.extensions.khr_synchronization_2,
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
            },
        },
    };

    const apis = base_api ++
        required_instance_extensions ++
        required_device_extensions ++
        optional_instance_extensions ++
        optional_device_extensions ++
        ray_tracing_device_extensions;

    const BaseDispatch = vulkan.BaseWrapper(apis);
    const InstanceDispatch = vulkan.InstanceWrapper(apis);
    const DeviceDispatch = vulkan.DeviceWrapper(apis);
    const Instance = vulkan.InstanceProxy(apis);
    const Device = vulkan.DeviceProxy(apis);

    const QueueFamily = struct {
        graphics: ?u32 = null,
        compute: ?u32 = null,
        transfer: ?u32 = null,
        present: ?u32 = null,
    };
    const Queue = struct {
        graphics: vulkan.Queue = .null_handle,
        compute: vulkan.Queue = .null_handle,
        transfer: vulkan.Queue = .null_handle,
        present: vulkan.Queue = .null_handle,
    };
    const SwapchainImage = struct {
        image: vulkan.Image,
        handle: nvrhi.TextureHandle,
    };

    vkb: BaseDispatch = undefined,
    instance: Instance = undefined,
    surface: vulkan.SurfaceKHR = .null_handle,
    physical_device: vulkan.PhysicalDevice = .null_handle,
    device: Device = undefined,
    nvrhi_device: nvrhi.DeviceHandle = .{},
    device_params: DeviceCreationParams = .{},
    queue_family: QueueFamily = .{},
    queue: Queue = .{},
    present_modes: struct {
        mailbox: bool = false,
        immediate: bool = false,
        fifo_relaxed: bool = false,
    } = .{},
    vsync_requested: bool = false,
    enabled_device_extensions: [][*:0]const u8 = &.{},
    enabled_instance_extensions: [][*:0]const u8 = &.{},
    swap_chain_format: vulkan.SurfaceFormatKHR = .{
        .format = .undefined,
        .color_space = .srgb_nonlinear_khr,
    },
    swapchain: vulkan.SwapchainKHR = .null_handle,
    swapchain_index: u32 = 0,
    swapchain_images: []SwapchainImage = &.{},
    present_semaphore_queue: []vulkan.Semaphore = &.{},
    present_semaphore: vulkan.Semaphore = .null_handle,
    frame_wait_query: nvrhi.EventQueryHandle = .{},
    allocator: std.mem.Allocator = undefined,

    pub const CreateError = error{
        OutOfMemory,
        CommandLoadFailure,
    };
    pub fn create(allocator: std.mem.Allocator) CreateError!*DeviceManagerVulkan {
        const device_manager = try allocator.create(DeviceManagerVulkan);
        device_manager.* = .{};
        device_manager.vkb = try BaseDispatch.load(vulkan_impl.vkGetInstanceProcAddr);
        device_manager.allocator = allocator;

        return device_manager;
    }

    pub fn destroy(device_manager: *DeviceManagerVulkan) void {
        for (device_manager.enabled_instance_extensions) |str_ptr| {
            device_manager.allocator.free(std.mem.span(str_ptr));
        }
        device_manager.allocator.free(device_manager.enabled_instance_extensions);

        for (device_manager.enabled_device_extensions) |str_ptr| {
            device_manager.allocator.free(std.mem.span(str_ptr));
        }
        device_manager.allocator.free(device_manager.enabled_device_extensions);

        device_manager.allocator.free(device_manager.swapchain_images);

        for (device_manager.present_semaphore_queue) |handle| {
            device_manager.device.destroySemaphore(handle, null);
        }
        device_manager.allocator.free(device_manager.present_semaphore_queue);

        device_manager.device.destroySwapchainKHR(device_manager.swapchain, null);
        device_manager.device.destroyDevice(null);
        device_manager.allocator.destroy(device_manager.device.wrapper);
        device_manager.instance.destroyInstance(null);
        device_manager.allocator.destroy(device_manager.instance.wrapper);
        device_manager.allocator.destroy(device_manager);
    }

    pub const CreateDeviceAndSwapChainError =
        CreateSwapChainError ||
        CreateDeviceError ||
        CreateInstanceError ||
        vulkan_impl.CreateWindowSurfaceError ||
        SelectPhysicalDeviceError;
    pub fn createDeviceAndSwapChain(
        device_manager: *DeviceManagerVulkan,
        params: GLImplParams,
        instance_extensions: []const [*:0]const u8,
    ) CreateDeviceAndSwapChainError!void {
        device_manager.device_params.back_buffer_width = params.width;
        device_manager.device_params.back_buffer_height = params.height;
        device_manager.device_params.vsync_enabled = device_manager.vsync_requested;

        var arena_instance = std.heap.ArenaAllocator.init(device_manager.allocator);
        defer arena_instance.deinit();
        const arena_allocator = arena_instance.allocator();

        try device_manager.createInstance(instance_extensions, arena_allocator);
        device_manager.surface = try vulkan_impl.createWindowSurface(
            device_manager.instance.handle,
        );

        device_manager.device_params.swap_chain_format = switch (device_manager.device_params.swap_chain_format) {
            .SRGBA8_UNORM => .SBGRA8_UNORM,
            .RGBA8_UNORM => .BGRA8_UNORM,
            else => |format| format,
        };

        try device_manager.selectPhysicalDevice(arena_allocator);
        try device_manager.findQueueFamilies(
            device_manager.physical_device,
            device_manager.surface,
            arena_allocator,
        );

        try device_manager.createDevice(arena_allocator);
        device_manager.createNvrhiDevice();
        const nvrhi_device_ptr = device_manager.nvrhi_device.ptr_ orelse @panic("createNvrhiDevice failed");

        // TODO: validation layer

        try device_manager.createSwapChain(arena_allocator);

        device_manager.present_semaphore_queue = try device_manager.allocator.alloc(
            vulkan.Semaphore,
            device_manager.swapchain_images.len,
        );
        errdefer device_manager.allocator.free(device_manager.present_semaphore_queue);
        for (device_manager.swapchain_images, device_manager.present_semaphore_queue) |_, *semaphore| {
            semaphore.* = try device_manager.device.createSemaphore(&.{}, null);
        }
        device_manager.present_semaphore = device_manager.present_semaphore_queue[0];

        device_manager.frame_wait_query = nvrhi_device_ptr.createEventQuery();
        const frame_wait_query_ptr = device_manager.frame_wait_query.ptr_ orelse @panic("createEventQuery failed");
        nvrhi_device_ptr.setEventQuery(frame_wait_query_ptr, .Graphics);
    }

    const CreateSwapChainError =
        Device.CreateSwapchainKHRError ||
        std.mem.Allocator.Error ||
        Instance.GetPhysicalDeviceSurfacePresentModesAllocKHRError;
    fn createSwapChain(device_manager: *DeviceManagerVulkan, allocator: std.mem.Allocator) CreateSwapChainError!void {
        device_manager.swap_chain_format = .{
            .format = @enumFromInt(nvrhi.vulkan.convertFormat(device_manager.device_params.swap_chain_format)),
            .color_space = .srgb_nonlinear_khr,
        };

        const surface_caps = try device_manager.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
            device_manager.physical_device,
            device_manager.surface,
        );

        device_manager.device_params.back_buffer_width = std.math.clamp(
            device_manager.device_params.back_buffer_width,
            surface_caps.min_image_extent.width,
            surface_caps.max_image_extent.width,
        );

        device_manager.device_params.back_buffer_height = std.math.clamp(
            device_manager.device_params.back_buffer_height,
            surface_caps.min_image_extent.height,
            surface_caps.max_image_extent.height,
        );

        const extent = vulkan.Extent2D{
            .width = device_manager.device_params.back_buffer_width,
            .height = device_manager.device_params.back_buffer_height,
        };

        var queue_families = std.BoundedArray(u32, 2)
            .init(0) catch unreachable;

        {
            var unique_queue_families = std.AutoHashMap(u32, void).init(allocator);
            defer unique_queue_families.deinit();

            if (device_manager.queue_family.graphics) |family_index|
                _ = try unique_queue_families.getOrPut(family_index);

            if (device_manager.queue_family.present) |family_index|
                _ = try unique_queue_families.getOrPut(family_index);

            var it = unique_queue_families.keyIterator();
            while (it.next()) |key_ptr| {
                queue_families.append(key_ptr.*) catch unreachable;
            }
        }

        const enable_swap_chain_sharing = queue_families.constSlice().len > 1;

        const present_mode: vulkan.PresentModeKHR = if (device_manager.device_params.vsync_enabled)
            if (device_manager.present_modes.fifo_relaxed) .fifo_relaxed_khr else .fifo_khr
        else if (device_manager.present_modes.mailbox and r_vk_prefer_fast_sync.integerValue != 0)
            .immediate_khr
        else
            .fifo_khr;

        const desc = vulkan.SwapchainCreateInfoKHR{
            .surface = device_manager.surface,
            .min_image_count = device_manager.device_params.swap_chain_buffer_count,
            .image_format = device_manager.swap_chain_format.format,
            .image_color_space = device_manager.swap_chain_format.color_space,
            .image_extent = extent,
            .image_array_layers = 1,
            .image_usage = .{
                .color_attachment_bit = true,
                .transfer_dst_bit = true,
                .sampled_bit = true,
            },
            .image_sharing_mode = if (enable_swap_chain_sharing) .concurrent else .exclusive,
            .queue_family_index_count = if (enable_swap_chain_sharing) @intCast(queue_families.constSlice().len) else 0,
            .p_queue_family_indices = if (enable_swap_chain_sharing) queue_families.constSlice().ptr else null,
            .pre_transform = .{ .identity_bit_khr = true },
            .composite_alpha = .{ .opaque_bit_khr = true },
            .present_mode = present_mode,
            .clipped = vulkan.TRUE,
        };

        device_manager.swapchain = try device_manager.device.createSwapchainKHR(&desc, null);

        // retrieve swap chain images
        const images = try device_manager.device.getSwapchainImagesAllocKHR(device_manager.swapchain, allocator);
        defer allocator.free(images);

        device_manager.swapchain_images = try device_manager.allocator.alloc(SwapchainImage, images.len);

        for (images, device_manager.swapchain_images) |image, *sc_image| {
            sc_image.image = image;
            const texture_desc = nvrhi.TextureDesc{
                .width = device_manager.device_params.back_buffer_width,
                .height = device_manager.device_params.back_buffer_height,
                .format = device_manager.device_params.swap_chain_format,
                .initialState = .Present,
                .keepInitialState = true,
                .isRenderTarget = true,
            };
            sc_image.handle = device_manager.nvrhi_device.ptr_.?.createHandleForNativeTexture(
                nvrhi.ObjectTypes.VK_Image,
                .{ .u = .{ .integer = @intFromEnum(image) } },
                &texture_desc,
            );
        }

        device_manager.swapchain_index = 0;
    }

    inline fn appendDeviceFeatures(features_ptr: anytype, p_next: *?*anyopaque) void {
        features_ptr.p_next = p_next.*;
        p_next.* = @ptrCast(features_ptr);
    }

    inline fn isExtNameEql(name: []const u8, extension: vulkan.ApiInfo) bool {
        return std.mem.eql(u8, name, extension.name);
    }

    fn createNvrhiDevice(device_manager: *DeviceManagerVulkan) void {
        var device_desc = nvrhi.vulkan.DeviceDesc{
            .instance = @ptrFromInt(@intFromEnum(device_manager.instance.handle)),
            .physicalDevice = @ptrFromInt(@intFromEnum(device_manager.physical_device)),
            .device = @ptrFromInt(@intFromEnum(device_manager.device.handle)),
            .graphicsQueue = @ptrFromInt(@intFromEnum(device_manager.queue.graphics)),
            .graphicsQueueIndex = @intCast(device_manager.queue_family.graphics.?),
            .instanceExtensions = device_manager.enabled_instance_extensions.ptr,
            .numInstanceExtensions = device_manager.enabled_instance_extensions.len,
            .deviceExtensions = device_manager.enabled_device_extensions.ptr,
            .numDeviceExtensions = device_manager.enabled_device_extensions.len,
        };

        if (device_manager.device_params.enable_compute_queue) {
            device_desc.computeQueue = @ptrFromInt(@intFromEnum(device_manager.queue.compute));
            device_desc.computeQueueIndex = @intCast(device_manager.queue_family.compute.?);
        }

        if (device_manager.device_params.enable_copy_queue) {
            device_desc.transferQueue = @ptrFromInt(@intFromEnum(device_manager.queue.transfer));
            device_desc.transferQueueIndex = @intCast(device_manager.queue_family.transfer.?);
        }

        device_manager.nvrhi_device = nvrhi.vulkan.createDevice(
            &device_desc,
            @ptrCast(device_manager.vkb.dispatch.vkGetInstanceProcAddr),
        );
        std.debug.assert(device_manager.nvrhi_device.ptr_ != null);
    }

    const CreateDeviceError = error{
        ExtensionNotSupported,
        LayerNotSupported,
        VmaCreateError,
    } ||
        Instance.GetPhysicalDeviceSurfacePresentModesAllocKHRError ||
        Instance.EnumerateDeviceLayerPropertiesAllocError ||
        Instance.EnumerateDeviceExtensionPropertiesAllocError ||
        Instance.CreateDeviceError;
    fn createDevice(
        device_manager: *DeviceManagerVulkan,
        allocator: std.mem.Allocator,
    ) CreateDeviceError!void {
        var required_layers = std.BufSet.init(allocator);
        defer required_layers.deinit();

        var optional_layers = std.BufSet.init(allocator);
        defer optional_layers.deinit();

        var enabled_layers = std.BufSet.init(allocator);
        defer enabled_layers.deinit();

        const available_layers = try device_manager.instance.enumerateDeviceLayerPropertiesAlloc(
            device_manager.physical_device,
            allocator,
        );

        for (available_layers) |layer| {
            const name = std.mem.span(@as(
                [*:0]const u8,
                @ptrCast(&layer.layer_name),
            ));
            if (required_layers.contains(name) or
                optional_layers.contains(name))
            {
                try enabled_layers.insert(name);
                required_layers.remove(name);
                optional_layers.remove(name);
            }
        }

        if (required_layers.count() > 0) {
            std.debug.print(
                "[VULKAN][ERR] following required device layer(s) are not supported:\n",
                .{},
            );

            var it = required_layers.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
            return error.LayerNotSupported;
        }

        if (optional_layers.count() > 0) {
            std.debug.print(
                "[VULKAN][WARN] following optional device layer(s) are not supported:\n",
                .{},
            );

            var it = optional_layers.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
        }

        {
            std.debug.print(
                "[VULKAN] Enabled device layers:\n",
                .{},
            );

            if (enabled_layers.count() > 0) {
                var it = enabled_layers.iterator();
                while (it.next()) |key_ptr| {
                    std.debug.print("{s}\n", .{key_ptr.*});
                }
            } else {
                std.debug.print("none\n", .{});
            }
        }

        var required_extensions = std.BufSet.init(allocator);
        defer required_extensions.deinit();
        for (required_device_extensions) |api_info| {
            try required_extensions.insert(api_info.name);
        }

        var optional_extensions = std.BufSet.init(allocator);
        defer optional_extensions.deinit();
        for (optional_device_extensions) |api_info| {
            try optional_extensions.insert(api_info.name);
        }

        if (device_manager.device_params.enable_ray_tracing_extensions) {
            for (ray_tracing_device_extensions) |api_info| {
                try optional_extensions.insert(api_info.name);
            }
        }

        var enabled_extensions = std.BufSet.init(allocator);
        defer enabled_extensions.deinit();

        const available_extensions = try device_manager.instance.enumerateDeviceExtensionPropertiesAlloc(
            device_manager.physical_device,
            null,
            allocator,
        );

        for (available_extensions) |ext| {
            const name = std.mem.span(@as(
                [*:0]const u8,
                @ptrCast(&ext.extension_name),
            ));
            if (required_extensions.contains(name) or
                optional_extensions.contains(name))
            {
                try enabled_extensions.insert(name);
                required_extensions.remove(name);
                optional_extensions.remove(name);
            }
        }

        if (required_extensions.count() > 0) {
            std.debug.print(
                "[VULKAN][ERR] following required device extension(s) are not supported:\n",
                .{},
            );

            var it = required_extensions.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
            return error.ExtensionNotSupported;
        }

        if (optional_extensions.count() > 0) {
            std.debug.print(
                "[VULKAN][WARN] following optional device extension(s) are not supported:\n",
                .{},
            );

            var it = optional_extensions.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
        }

        var queue_create_infos = std.BoundedArray(vulkan.DeviceQueueCreateInfo, 4)
            .init(0) catch unreachable;

        {
            var unique_queue_families = std.AutoHashMap(u32, void).init(allocator);
            defer unique_queue_families.deinit();

            if (device_manager.queue_family.graphics) |family_index|
                _ = try unique_queue_families.getOrPut(family_index);

            if (device_manager.queue_family.present) |family_index|
                _ = try unique_queue_families.getOrPut(family_index);

            if (device_manager.device_params.enable_compute_queue) {
                if (device_manager.queue_family.compute) |family_index|
                    _ = try unique_queue_families.getOrPut(family_index);
            }

            if (device_manager.device_params.enable_copy_queue) {
                if (device_manager.queue_family.transfer) |family_index|
                    _ = try unique_queue_families.getOrPut(family_index);
            }

            var priority: [1]f32 = .{1};
            var it = unique_queue_families.keyIterator();
            while (it.next()) |key_ptr| {
                queue_create_infos.append(.{
                    .queue_family_index = key_ptr.*,
                    .queue_count = 1,
                    .p_queue_priorities = &priority,
                }) catch unreachable;
            }
        }

        var accel_struct_features = vulkan.PhysicalDeviceAccelerationStructureFeaturesKHR{
            .acceleration_structure = vulkan.TRUE,
        };

        var ray_pipeline_features = vulkan.PhysicalDeviceRayTracingPipelineFeaturesKHR{
            .ray_tracing_pipeline = vulkan.TRUE,
            .ray_traversal_primitive_culling = vulkan.TRUE,
        };

        var ray_query_features = vulkan.PhysicalDeviceRayQueryFeaturesKHR{
            .ray_query = vulkan.TRUE,
        };

        var meshlet_features = vulkan.PhysicalDeviceMeshShaderFeaturesNV{
            .task_shader = vulkan.TRUE,
            .mesh_shader = vulkan.TRUE,
        };

        var actual_device_features = vulkan.PhysicalDeviceFeatures2{
            .features = .{},
        };
        var fragment_shading_rate_features = vulkan.PhysicalDeviceFragmentShadingRateFeaturesKHR{};
        actual_device_features.p_next = &fragment_shading_rate_features;

        device_manager.instance.getPhysicalDeviceFeatures2(
            device_manager.physical_device,
            &actual_device_features,
        );

        var vrs_features = vulkan.PhysicalDeviceFragmentShadingRateFeaturesKHR{
            .pipeline_fragment_shading_rate = fragment_shading_rate_features.pipeline_fragment_shading_rate,
            .primitive_fragment_shading_rate = fragment_shading_rate_features.primitive_fragment_shading_rate,
            .attachment_fragment_shading_rate = fragment_shading_rate_features.attachment_fragment_shading_rate,
        };

        var sync2_features = vulkan.PhysicalDeviceSynchronization2FeaturesKHR{
            .synchronization_2 = vulkan.TRUE,
        };

        var p_next: ?*anyopaque = null;
        var buffer_address_supported: vulkan.Bool32 = vulkan.FALSE;
        {
            std.debug.print(
                "[VULKAN] Enabled device extensions:\n",
                .{},
            );

            if (enabled_extensions.count() > 0) {
                var it = enabled_extensions.iterator();
                const exts = vulkan.extensions;
                while (it.next()) |key_ptr| {
                    const name = key_ptr.*;
                    std.debug.print("{s}\n", .{name});
                    if (isExtNameEql(name, exts.khr_acceleration_structure))
                        appendDeviceFeatures(&accel_struct_features, &p_next);
                    if (isExtNameEql(name, exts.khr_ray_tracing_pipeline))
                        appendDeviceFeatures(&ray_pipeline_features, &p_next);
                    if (isExtNameEql(name, exts.khr_ray_query))
                        appendDeviceFeatures(&ray_query_features, &p_next);
                    if (isExtNameEql(name, exts.nv_mesh_shader))
                        appendDeviceFeatures(&meshlet_features, &p_next);
                    if (isExtNameEql(name, exts.khr_fragment_shading_rate))
                        appendDeviceFeatures(&vrs_features, &p_next);
                    if (isExtNameEql(name, exts.khr_synchronization_2))
                        appendDeviceFeatures(&sync2_features, &p_next);
                    if (isExtNameEql(name, exts.khr_buffer_device_address))
                        buffer_address_supported = vulkan.TRUE;
                }
            } else {
                std.debug.print("none\n", .{});
            }
        }

        const device_features = vulkan.PhysicalDeviceFeatures{
            .shader_image_gather_extended = vulkan.TRUE,
            .shader_storage_image_read_without_format = actual_device_features.features.shader_storage_image_read_without_format,
            .sampler_anisotropy = vulkan.TRUE,
            .tessellation_shader = vulkan.TRUE,
            .texture_compression_bc = vulkan.TRUE,
            .geometry_shader = vulkan.TRUE,
            .fill_mode_non_solid = vulkan.TRUE,
            .image_cube_array = vulkan.TRUE,
            .dual_src_blend = vulkan.TRUE,
        };

        const vulkan12_features = vulkan.PhysicalDeviceVulkan12Features{
            .descriptor_indexing = vulkan.TRUE,
            .runtime_descriptor_array = vulkan.TRUE,
            .descriptor_binding_partially_bound = vulkan.TRUE,
            .descriptor_binding_variable_descriptor_count = vulkan.TRUE,
            .timeline_semaphore = vulkan.TRUE,
            .shader_sampled_image_array_non_uniform_indexing = vulkan.TRUE,
            .buffer_device_address = buffer_address_supported,
            .p_next = p_next,
        };

        const exts_slice = try device_manager.allocator.alloc([*:0]const u8, enabled_extensions.count());
        {
            var it = enabled_extensions.iterator();
            var i: u32 = 0;
            while (it.next()) |key_ptr| : (i += 1) {
                const copy = try device_manager.allocator.dupeZ(u8, key_ptr.*);
                exts_slice[i] = copy.ptr;
            }
        }
        device_manager.enabled_device_extensions = exts_slice;

        const layers_slice = try allocator.alloc([*:0]const u8, enabled_layers.count());
        {
            var it = enabled_layers.iterator();
            var i: u32 = 0;
            while (it.next()) |key_ptr| : (i += 1) {
                const copy = try allocator.dupeZ(u8, key_ptr.*);
                layers_slice[i] = copy.ptr;
            }
        }
        const device_create_info = vulkan.DeviceCreateInfo{
            .p_queue_create_infos = queue_create_infos.constSlice().ptr,
            .queue_create_info_count = @intCast(queue_create_infos.constSlice().len),
            .p_enabled_features = &device_features,
            .enabled_extension_count = @intCast(exts_slice.len),
            .pp_enabled_extension_names = exts_slice.ptr,
            .enabled_layer_count = @intCast(layers_slice.len),
            .pp_enabled_layer_names = layers_slice.ptr,
            .p_next = &vulkan12_features,
        };

        const device_handle = try device_manager.instance.createDevice(
            device_manager.physical_device,
            &device_create_info,
            null,
        );

        const vkd = try device_manager.allocator.create(DeviceDispatch);
        errdefer device_manager.allocator.destroy(vkd);
        vkd.* = DeviceDispatch.loadNoFail(
            device_handle,
            device_manager.instance.wrapper.dispatch.vkGetDeviceProcAddr,
        );
        device_manager.device = Device.init(
            device_handle,
            vkd,
        );
        errdefer device_manager.device.destroyDevice(null);

        if (device_manager.queue_family.graphics) |family_index|
            device_manager.queue.graphics = device_manager.device.getDeviceQueue(family_index, 0);

        if (device_manager.queue_family.present) |family_index|
            device_manager.queue.present = device_manager.device.getDeviceQueue(family_index, 0);

        if (device_manager.device_params.enable_compute_queue) {
            if (device_manager.queue_family.compute) |family_index|
                device_manager.queue.compute = device_manager.device.getDeviceQueue(family_index, 0);
        }

        if (device_manager.device_params.enable_copy_queue) {
            if (device_manager.queue_family.transfer) |family_index|
                device_manager.queue.transfer = device_manager.device.getDeviceQueue(family_index, 0);
        }

        {
            const result = device_manager.instance.getPhysicalDeviceImageFormatProperties(
                device_manager.physical_device,
                .d24_unorm_s8_uint,
                .@"2d",
                .optimal,
                .{ .depth_stencil_attachment_bit = true },
                .{},
            );

            device_manager.device_params.enable_image_format_d24s8 = if (result) |_| true else |_| false;
        }

        const surface_present_modes = try device_manager.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
            device_manager.physical_device,
            device_manager.surface,
            allocator,
        );

        for (surface_present_modes) |present_mode| {
            if (present_mode == .mailbox_khr) {
                device_manager.present_modes.mailbox = true;
            }

            if (present_mode == .immediate_khr) {
                device_manager.present_modes.immediate = true;
            }

            if (present_mode == .fifo_relaxed_khr) {
                device_manager.present_modes.fifo_relaxed = true;
            }
        }

        const vulkan_funcs = c.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = @ptrCast(device_manager.vkb.dispatch.vkGetInstanceProcAddr),
            .vkGetDeviceProcAddr = @ptrCast(device_manager.instance.wrapper.dispatch.vkGetDeviceProcAddr),
        };

        const allocator_create_info = c.VmaAllocatorCreateInfo{
            .vulkanApiVersion = vulkan.API_VERSION_1_2,
            .physicalDevice = @ptrFromInt(@intFromEnum(device_manager.physical_device)),
            .device = @ptrFromInt(@intFromEnum(device_manager.device.handle)),
            .instance = @ptrFromInt(@intFromEnum(device_manager.instance.handle)),
            .flags = if (buffer_address_supported == vulkan.TRUE)
                c.VMA_ALLOCATOR_CREATE_BUFFER_DEVICE_ADDRESS_BIT
            else
                0,
            .preferredLargeHeapBlockSize = @as(u64, @intCast(r_vma_device_local_memory_mb.integerValue)) * 1024 * 1024,
            .pVulkanFunctions = &vulkan_funcs,
        };

        {
            const result = c.vmaCreateAllocator(&allocator_create_info, &vma_allocator);
            if (result != @intFromEnum(vulkan.Result.success)) return error.VmaCreateError;
        }
    }

    pub const CreateInstanceError = error{
        ExtensionNotSupported,
        LayerNotSupported,
    } ||
        std.mem.Allocator.Error ||
        BaseDispatch.EnumerateInstanceExtensionPropertiesAllocError ||
        BaseDispatch.EnumerateInstanceLayerPropertiesAllocError ||
        BaseDispatch.CreateInstanceError;
    fn createInstance(
        device_manager: *DeviceManagerVulkan,
        extensions: []const [*:0]const u8,
        allocator: std.mem.Allocator,
    ) CreateInstanceError!void {
        var required_extensions = std.BufSet.init(allocator);
        defer required_extensions.deinit();

        for (extensions) |ext_name| {
            try required_extensions.insert(std.mem.span(ext_name));
        }

        for (required_instance_extensions) |api_info| {
            try required_extensions.insert(api_info.name);
        }

        var optional_extensions = std.BufSet.init(allocator);
        defer optional_extensions.deinit();

        for (optional_instance_extensions) |api_info| {
            try optional_extensions.insert(api_info.name);
        }

        var enabled_extensions = std.BufSet.init(allocator);
        defer enabled_extensions.deinit();

        const available_extensions = try device_manager.vkb.enumerateInstanceExtensionPropertiesAlloc(
            null,
            allocator,
        );

        for (available_extensions) |ext| {
            const name = std.mem.span(@as(
                [*:0]const u8,
                @ptrCast(&ext.extension_name),
            ));
            if (required_extensions.contains(name) or
                optional_extensions.contains(name))
            {
                try enabled_extensions.insert(name);
                required_extensions.remove(name);
                optional_extensions.remove(name);
            }
        }

        if (required_extensions.count() > 0) {
            std.debug.print(
                "[VULKAN][ERR] following required instance extension(s) are not supported:\n",
                .{},
            );

            var it = required_extensions.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
            return error.ExtensionNotSupported;
        }

        if (optional_extensions.count() > 0) {
            std.debug.print(
                "[VULKAN][WARN] following optional instance extension(s) are not supported:\n",
                .{},
            );

            var it = optional_extensions.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
        }

        {
            std.debug.print(
                "[VULKAN] Enabled instance extensions:\n",
                .{},
            );

            if (enabled_extensions.count() > 0) {
                var it = enabled_extensions.iterator();
                while (it.next()) |key_ptr| {
                    std.debug.print("{s}\n", .{key_ptr.*});
                }
            } else {
                std.debug.print("none\n", .{});
            }
        }

        var required_layers = std.BufSet.init(allocator);
        defer required_layers.deinit();

        var optional_layers = std.BufSet.init(allocator);
        defer optional_layers.deinit();

        var enabled_layers = std.BufSet.init(allocator);
        defer enabled_layers.deinit();

        const available_layers = try device_manager.vkb.enumerateInstanceLayerPropertiesAlloc(
            allocator,
        );

        for (available_layers) |layer| {
            const name = std.mem.span(@as(
                [*:0]const u8,
                @ptrCast(&layer.layer_name),
            ));
            if (required_layers.contains(name) or
                optional_layers.contains(name))
            {
                try enabled_layers.insert(name);
                required_layers.remove(name);
                optional_layers.remove(name);
            }
        }

        if (required_layers.count() > 0) {
            std.debug.print(
                "[VULKAN][ERR] following required instance layer(s) are not supported:\n",
                .{},
            );

            var it = required_layers.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
            return error.LayerNotSupported;
        }

        if (optional_layers.count() > 0) {
            std.debug.print(
                "[VULKAN][WARN] following optional instance layer(s) are not supported:\n",
                .{},
            );

            var it = optional_layers.iterator();
            while (it.next()) |key_ptr| {
                std.debug.print("{s}\n", .{key_ptr.*});
            }
        }

        {
            std.debug.print(
                "[VULKAN] Enabled instance layers:\n",
                .{},
            );

            if (enabled_layers.count() > 0) {
                var it = enabled_layers.iterator();
                while (it.next()) |key_ptr| {
                    std.debug.print("{s}\n", .{key_ptr.*});
                }
            } else {
                std.debug.print("none\n", .{});
            }
        }

        const exts = try device_manager.allocator.alloc([*:0]const u8, enabled_extensions.count());
        {
            var it = enabled_extensions.iterator();
            var i: u32 = 0;
            while (it.next()) |key_ptr| : (i += 1) {
                const copy = try device_manager.allocator.dupeZ(u8, key_ptr.*);
                exts[i] = copy.ptr;
            }
        }
        device_manager.enabled_instance_extensions = exts;

        const layers = try allocator.alloc([*:0]const u8, enabled_layers.count());
        {
            var it = enabled_layers.iterator();
            var i: u32 = 0;
            while (it.next()) |key_ptr| : (i += 1) {
                const copy = try allocator.dupeZ(u8, key_ptr.*);
                layers[i] = copy.ptr;
            }
        }

        const app_info: vulkan.ApplicationInfo = .{
            .p_application_name = "rbdoom3",
            .application_version = vulkan.makeApiVersion(0, 0, 0, 0),
            .p_engine_name = "ztech",
            .engine_version = vulkan.makeApiVersion(0, 0, 0, 0),
            .api_version = vulkan.API_VERSION_1_2,
        };

        const create_info = vulkan.InstanceCreateInfo{
            .p_application_info = &app_info,
            .enabled_extension_count = @intCast(exts.len),
            .pp_enabled_extension_names = exts.ptr,
            .enabled_layer_count = @intCast(layers.len),
            .pp_enabled_layer_names = layers.ptr,
        };

        const instance_handle = try device_manager.vkb.createInstance(&create_info, null);
        const vki = try device_manager.allocator.create(InstanceDispatch);
        errdefer device_manager.allocator.destroy(vki);
        vki.* = InstanceDispatch.loadNoFail(
            instance_handle,
            device_manager.vkb.dispatch.vkGetInstanceProcAddr,
        );

        device_manager.instance = Instance.init(instance_handle, vki);
    }

    const SelectPhysicalDeviceError =
        error{SuitableDeviceNotFound} ||
        FindQueueFamiliesError ||
        Instance.GetPhysicalDeviceSurfacePresentModesAllocKHRError ||
        Instance.EnumeratePhysicalDevicesError ||
        Instance.EnumerateDeviceExtensionPropertiesAllocError ||
        Instance.GetPhysicalDeviceSurfaceCapabilitiesKHRError;
    fn selectPhysicalDevice(
        device_manager: *DeviceManagerVulkan,
        allocator: std.mem.Allocator,
    ) SelectPhysicalDeviceError!void {
        const requested_format: vulkan.Format = @enumFromInt(nvrhi.vulkan.convertFormat(
            device_manager.device_params.swap_chain_format,
        ));

        const max_physical_devices = 32;
        var devices_buffer: [max_physical_devices]vulkan.PhysicalDevice = undefined;
        var physical_device_count: u32 = max_physical_devices;
        _ = try device_manager.instance.enumeratePhysicalDevices(
            &physical_device_count,
            &devices_buffer,
        );
        const devices = devices_buffer[0..physical_device_count];

        var discrete_gpu: ?vulkan.PhysicalDevice = null;
        var other_gpu: ?vulkan.PhysicalDevice = null;
        for (devices) |device| {
            const device_props = device_manager.instance.getPhysicalDeviceProperties(device);

            std.debug.print("[VULKAN] Checking physical device: {s}\n", .{device_props.device_name});

            var required_extensions = std.BufSet.init(allocator);
            defer required_extensions.deinit();

            for (required_device_extensions) |api_info| {
                try required_extensions.insert(api_info.name);
            }

            const available_extensions = try device_manager.instance.enumerateDeviceExtensionPropertiesAlloc(
                device,
                null,
                allocator,
            );

            for (available_extensions) |ext| {
                const name = std.mem.span(@as(
                    [*:0]const u8,
                    @ptrCast(&ext.extension_name),
                ));
                required_extensions.remove(name);
            }

            if (required_extensions.count() > 0) continue;

            const device_features = device_manager.instance.getPhysicalDeviceFeatures(device);
            if (device_features.sampler_anisotropy == vulkan.FALSE) continue;
            if (device_features.texture_compression_bc == vulkan.FALSE) continue;

            const surface_caps = try device_manager.instance.getPhysicalDeviceSurfaceCapabilitiesKHR(
                device,
                device_manager.surface,
            );
            const surface_formats = try device_manager.instance.getPhysicalDeviceSurfaceFormatsAllocKHR(
                device,
                device_manager.surface,
                allocator,
            );
            const surface_present_modes = try device_manager.instance.getPhysicalDeviceSurfacePresentModesAllocKHR(
                device,
                device_manager.surface,
                allocator,
            );

            const min_buffer_count = @max(
                surface_caps.min_image_count,
                device_manager.device_params.swap_chain_buffer_count,
            );
            device_manager.device_params.swap_chain_buffer_count = if (surface_caps.max_image_count > 0)
                @min(min_buffer_count, surface_caps.max_image_count)
            else
                min_buffer_count;

            for (surface_formats) |surf_format| {
                if (surf_format.format == requested_format) break;
            } else continue;

            for (surface_present_modes) |present_mode| {
                if (present_mode == .fifo_khr) break;
            } else continue;

            device_manager.findQueueFamilies(
                device,
                device_manager.surface,
                allocator,
            ) catch |err| {
                if (err == error.QueueFamilyNotFound) {
                    continue;
                } else {
                    return err;
                }
            };

            if (try device_manager.instance.getPhysicalDeviceSurfaceSupportKHR(
                device,
                device_manager.queue_family.graphics.?,
                device_manager.surface,
            ) == vulkan.FALSE)
                continue;

            if (device_props.device_type == .discrete_gpu) {
                discrete_gpu = discrete_gpu orelse device;
            } else {
                other_gpu = other_gpu orelse device;
            }
        }

        device_manager.physical_device = discrete_gpu orelse other_gpu orelse
            return error.SuitableDeviceNotFound;
    }

    const FindQueueFamiliesError =
        error{QueueFamilyNotFound} ||
        std.mem.Allocator.Error ||
        Instance.GetPhysicalDeviceSurfaceSupportKHRError;
    fn findQueueFamilies(
        device_manager: *DeviceManagerVulkan,
        device: vulkan.PhysicalDevice,
        surface: vulkan.SurfaceKHR,
        allocator: std.mem.Allocator,
    ) FindQueueFamiliesError!void {
        const props = try device_manager.instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(
            device,
            allocator,
        );
        const queue_family = &device_manager.queue_family;

        for (props, 0..) |family_props, i| {
            const family_index: u32 = @intCast(i);

            if (queue_family.graphics == null) {
                if (family_props.queue_count > 0 and
                    family_props.queue_flags.graphics_bit)
                {
                    queue_family.graphics = family_index;
                }
            }

            if (queue_family.compute == null) {
                if (family_props.queue_count > 0 and
                    family_props.queue_flags.compute_bit and
                    !family_props.queue_flags.graphics_bit)
                {
                    queue_family.compute = family_index;
                }
            }

            if (queue_family.transfer == null) {
                if (family_props.queue_count > 0 and
                    family_props.queue_flags.transfer_bit and
                    !family_props.queue_flags.compute_bit and
                    !family_props.queue_flags.graphics_bit)
                {
                    queue_family.transfer = family_index;
                }
            }

            if (queue_family.present == null) {
                if (family_props.queue_count > 0 and
                    try device_manager.instance.getPhysicalDeviceSurfaceSupportKHR(
                    device,
                    family_index,
                    surface,
                ) == vulkan.TRUE) {
                    queue_family.present = family_index;
                }
            }
        }

        const required_found = queue_family.graphics != null and queue_family.present != null;
        const enabled_found =
            (!device_manager.device_params.enable_compute_queue or queue_family.compute != null) and
            (!device_manager.device_params.enable_copy_queue or queue_family.transfer != null);

        if (!required_found or !enabled_found) return error.QueueFamilyNotFound;
    }

    pub fn beginFrame(_: *DeviceManagerVulkan) void {
        @panic("beginFrame is not implemented");
    }

    pub fn endFrame(_: *DeviceManagerVulkan) void {
        @panic("endFrame is not implemented");
    }

    pub fn updateWindowSize(_: *DeviceManagerVulkan, _: GLImplParams) void {
        @panic("updateWindowSize is not implemented");
    }

    pub fn present(_: *DeviceManagerVulkan) void {
        @panic("present is not implemented");
    }

    pub fn getDevice(device_manager: *DeviceManagerVulkan) *nvrhi.IDevice {
        return device_manager.nvrhi_device.ptr_.?;
    }

    pub fn getGraphicsApi(_: *const DeviceManagerVulkan) nvrhi.GraphicsAPI {
        return .VULKAN;
    }
};
