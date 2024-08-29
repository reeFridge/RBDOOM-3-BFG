pub const Common = opaque {
    extern fn c_common_getRendererGPUMicroseconds(*const Common) callconv(.C) u64;

    pub fn getRendererGPUMicroseconds(common: *const Common) u64 {
        return c_common_getRendererGPUMicroseconds(common);
    }
};

pub const instance = @extern(*Common, .{ .name = "commonLocal" });
