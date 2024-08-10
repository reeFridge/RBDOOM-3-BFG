const global = @import("../global.zig");
const FrameData = @import("frame_data.zig");

export fn ztech_frameData_get() callconv(.C) ?*FrameData.FrameData {
    return FrameData.frame_data;
}

export fn ztech_frameData_init() callconv(.C) void {
    const allocator = global.gpa.allocator();
    FrameData.init(allocator) catch {
        @panic("ztech_frameData_init: fails!");
    };
}

export fn ztech_frameData_shutdown() callconv(.C) void {
    const allocator = global.gpa.allocator();
    FrameData.shutdown(allocator);
}

export fn ztech_frameData_toggleSmpFrame() callconv(.C) void {
    FrameData.toggleSmpFrame();
}

export fn ztech_frameData_alloc(bytes: c_int, _: c_int) callconv(.C) *anyopaque {
    const frame_allocator = FrameData.bufferAllocator().threadSafeAllocator();
    const mem = FrameData.allocBytes(frame_allocator, @intCast(bytes));

    return @ptrCast(mem.ptr);
}

export fn ztech_frameData_createCommandBuffer(bytes: c_int) callconv(.C) *anyopaque {
    const mem = FrameData.createCommandBuffer(@intCast(bytes));

    return @ptrCast(mem.ptr);
}
