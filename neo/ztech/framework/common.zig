pub const Common = opaque {
    extern fn c_common_getRendererGPUMicroseconds(*const Common) callconv(.C) u64;
    extern fn c_common_quit(*Common) void;
    extern fn c_common_frame(*Common) void;
    extern fn c_common_init(
        *Common,
        c_uint,
        ?[*]const [*:0]const u8,
    ) void;

    pub fn frame(common: *Common) void {
        c_common_frame(common);
    }

    pub fn init(common: *Common, opt_args: ?[]const [*:0]const u8) void {
        if (opt_args) |args| {
            c_common_init(common, @intCast(args.len), @ptrCast(args));
        } else {
            c_common_init(common, 0, null);
        }
    }

    pub fn getRendererGPUMicroseconds(common: *const Common) u64 {
        return c_common_getRendererGPUMicroseconds(common);
    }

    pub fn quit(common: *Common) void {
        c_common_quit(common);
    }
};

pub const instance = @extern(*Common, .{ .name = "commonLocal" });
