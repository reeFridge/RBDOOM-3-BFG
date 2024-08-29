const idStr = @import("common.zig").idStr;

pub const ResolutionScale = extern struct {
    extern fn c_resolutionScale_initForMap(*ResolutionScale) callconv(.C) void;
    extern fn c_resolutionScale_getCurrentResolutionScale(*ResolutionScale, *f32, *f32) callconv(.C) void;
    extern fn c_resolutionScale_setCurrentGPUFrameTime(*ResolutionScale, c_int) callconv(.C) void;
    extern fn c_resolutionScale_getConsoleText(*ResolutionScale, *idStr) callconv(.C) void;

    dropMilliseconds: f32 = 15,
    raiseMilliseconds: f32 = 13,
    framesAboveRaise: c_int = 0,
    currentResolution: f32 = 1,

    pub fn initForMap(resolution_scale: *ResolutionScale) void {
        c_resolutionScale_initForMap(resolution_scale);
    }

    pub fn getCurrentResolutionScale(resolution_scale: *ResolutionScale, x: *f32, y: *f32) void {
        c_resolutionScale_getCurrentResolutionScale(
            resolution_scale,
            x,
            y,
        );
    }

    pub fn resetToFullResolution(resolution_scale: *ResolutionScale) void {
        resolution_scale.currentResolution = 1;
    }

    pub fn setCurrentGPUFrameTime(resolution_scale: *ResolutionScale, time: c_int) void {
        c_resolutionScale_setCurrentGPUFrameTime(resolution_scale, time);
    }
};

pub const instance = @extern(*ResolutionScale, .{ .name = "resolutionScale" });
