const nvrhi = @import("../renderer/nvrhi.zig");

pub const DeviceManager = opaque {
    extern fn c_deviceManager_getDevice(*DeviceManager) callconv(.C) *nvrhi.IDevice;

    pub fn getDevice(device_manager: *DeviceManager) *nvrhi.IDevice {
        return c_deviceManager_getDevice(device_manager);
    }
};

extern var deviceManager: ?*DeviceManager;

pub inline fn instance() *DeviceManager {
    return deviceManager orelse @panic("DeviceManager.instance is not initialized");
}
