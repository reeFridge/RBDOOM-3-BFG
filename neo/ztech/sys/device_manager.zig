const nvrhi = @import("../renderer/nvrhi.zig");
const GLImplParams = @import("../renderer/common.zig").GLImplParams;

pub const DeviceManager = opaque {
    extern fn c_deviceManager_getDevice(*DeviceManager) callconv(.C) *nvrhi.IDevice;
    extern fn c_deviceManager_create(nvrhi.GraphicsAPI) callconv(.C) *DeviceManager;
    extern fn c_deviceManager_destroy(*DeviceManager) callconv(.C) void;
    extern fn c_deviceManager_present(*DeviceManager) callconv(.C) void;
    extern fn c_deviceManager_updateWindowSize(*DeviceManager, GLImplParams) callconv(.C) void;
    extern fn c_deviceManager_beginFrame(*DeviceManager) callconv(.C) void;
    extern fn c_deviceManager_endFrame(*DeviceManager) callconv(.C) void;

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
};

extern var deviceManager: ?*DeviceManager;

pub inline fn instance() *DeviceManager {
    return deviceManager orelse @panic("DeviceManager.deviceManager is not initialized");
}

pub fn init(api: nvrhi.GraphicsAPI) void {
    if (deviceManager != null) @panic("DeviceManager.deviceManager already created");

    deviceManager = DeviceManager.create(api);
}

pub fn deinit() void {
    if (deviceManager) |device_manager| {
        device_manager.destroy();
        deviceManager = null;
    }
}
