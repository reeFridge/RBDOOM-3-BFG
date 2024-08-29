const nvrhi = @import("nvrhi.zig");

pub const Image = opaque {
    extern fn c_image_getTextureID(*Image) callconv(.C) *anyopaque;
    extern fn c_image_getTextureHandle(*Image, *nvrhi.TextureHandle) callconv(.C) void;

    pub fn getTextureHandle(image: *Image) nvrhi.TextureHandle {
        var handle = nvrhi.TextureHandle{};
        c_image_getTextureHandle(image, &handle);

        return handle;
    }

    pub fn getTexturePtr(image: *Image) ?*nvrhi.ITexture {
        var handle = nvrhi.TextureHandle{};
        defer handle.deinit();
        c_image_getTextureHandle(image, &handle);

        return handle.ptr_;
    }

    pub fn getTextureID(image: *Image) *anyopaque {
        return c_image_getTextureID(image);
    }
};

extern fn c_image_emptyGarbage() callconv(.C) void;

pub fn emptyGarbage() void {
    c_image_emptyGarbage();
}
