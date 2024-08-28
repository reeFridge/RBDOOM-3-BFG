pub const RenderLog = opaque {
    extern fn c_renderLog_init(*RenderLog) callconv(.C) void;
    extern fn c_renderLog_shutdown(*RenderLog) callconv(.C) void;
    extern fn c_renderLog_endFrame(*RenderLog) callconv(.C) void;

    pub fn endFrame(render_log: *RenderLog) void {
        c_renderLog_endFrame(render_log);
    }

    pub fn init(render_log: *RenderLog) void {
        c_renderLog_init(render_log);
    }

    pub fn shutdown(render_log: *RenderLog) void {
        c_renderLog_shutdown(render_log);
    }
};

pub const instance = @extern(*RenderLog, .{ .name = "renderLog" });
