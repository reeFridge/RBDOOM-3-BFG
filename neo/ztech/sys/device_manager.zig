const global = @import("../global.zig");
const std = @import("std");
const nvrhi = @import("../renderer/nvrhi.zig");
const GLImplParams = @import("../renderer/common.zig").GLImplParams;
const vk_mem_alloc = @cImport(@cInclude("vk_mem_alloc.h"));

pub var vma_allocator: vk_mem_alloc.VmaAllocator = null;

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

pub fn init(api: nvrhi.GraphicsAPI) error{OutOfMemory}!void {
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

pub const DeviceManagerVulkan = struct {
    allocator: std.mem.Allocator,

    pub fn create(allocator: std.mem.Allocator) error{OutOfMemory}!*DeviceManagerVulkan {
        const device_manager = try allocator.create(DeviceManagerVulkan);
        device_manager.allocator = allocator;

        return device_manager;
    }

    pub fn destroy(device_manager: *DeviceManagerVulkan) void {
        device_manager.allocator.destroy(device_manager);
    }

    pub fn createDeviceAndSwapChain() void {
        // vulkan-loader getProcAddress
        // vulkan_instance = device_manager.createInstance
        // device_manager.createWidnowSurface (SDL)
        // vulkan_physical_device = device_manager.pickPhysicalDevice
        // device_manager.findQueueFamilies
        // vulkan_device = device_manager.createDevice
        // device_desc = nvrhi.vulkan.DeviceDesc{.insatance = vulkan_instance, .device = vulkan_device, .physicalDevice = vulkan_physical_device};
        // device = nvrhi.vulkan.createDevice(device_desc)
        // device_manager.createSwapChain
        // frame_wait_query = device.createEventQuery
        // device.setEventQuery(frame_wait_query, .Graphics);
    }

    pub fn beginFrame(_: *DeviceManagerVulkan) void {}

    pub fn endFrame(_: *DeviceManagerVulkan) void {}

    pub fn updateWindowSize(_: *DeviceManagerVulkan, _: GLImplParams) void {}

    pub fn present(_: *DeviceManagerVulkan) void {}

    pub fn getDevice(_: *DeviceManagerVulkan) *nvrhi.IDevice {
        @panic("getDevice is not implemented");
    }

    pub fn getGraphicsApi(_: *const DeviceManagerVulkan) nvrhi.GraphicsAPI {
        return .VULKAN;
    }
};
