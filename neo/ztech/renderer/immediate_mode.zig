const nvrhi = @import("nvrhi.zig");

extern fn c_immediateMode_init(*nvrhi.ICommandList) callconv(.C) void;
extern fn c_immediateMode_shutdown() callconv(.C) void;

pub const ImmediateMode = opaque {};

pub fn init(command_list: *nvrhi.ICommandList) void {
    c_immediateMode_init(command_list);
}

pub fn shutdown() void {
    c_immediateMode_shutdown();
}
