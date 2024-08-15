const nvrhi = @import("nvrhi.zig");

pub const ImageManager = opaque {
    extern fn c_imageManager_reloadImages(*ImageManager, bool, *nvrhi.ICommandList) callconv(.C) void;
    extern fn c_imageManager_init(*ImageManager) callconv(.C) void;
    extern fn c_imageManager_shutdown(*ImageManager) callconv(.C) void;
    extern fn c_imageManager_purgeAllImages(*ImageManager) callconv(.C) void;

    pub fn reloadImages(image_manager: *ImageManager, all: bool, command_list_ptr: *nvrhi.ICommandList) void {
        c_imageManager_reloadImages(image_manager, all, command_list_ptr);
    }

    pub fn init(image_manager: *ImageManager) void {
        c_imageManager_init(image_manager);
    }

    pub fn shutdown(image_manager: *ImageManager) void {
        c_imageManager_shutdown(image_manager);
    }

    pub fn purgeAllImages(image_manager: *ImageManager) void {
        c_imageManager_purgeAllImages(image_manager);
    }
};

pub const instance = @extern(*ImageManager, .{ .name = "imageManager" });
