const std = @import("std");
const image = @import("image.zig");
const idlib = @import("../idlib.zig");

pub const BinaryImage = extern struct {
    const FileInfo = extern struct {
        sourceFileTime: idlib.ID_TIME_T,
        headerMagic: c_int,
        textureType: c_int,
        format: c_int,
        colorFormat: c_int,
        width: u32,
        height: u32,
        numLevels: c_int,
    };

    const Image = extern struct {
        const Header = extern struct {
            // mip
            level: u32,
            // array slice
            destZ: u32,
            width: u32,
            height: u32,
            // data size bytes follow
            dataSize: c_int,
        };

        header: Header,
        data: ?[*]u8 = null,
    };

    imgName: idlib.idStr = .{},
    fileData: FileInfo = std.mem.zeroes(FileInfo),
    images: idlib.idList(Image) = .{},

    pub fn init(bin_image: *BinaryImage, name: []const u8) error{OutOfMemory}!void {
        bin_image.imgName.initEmptyBuffer();
        try bin_image.imgName.assignSlice(name);
    }

    pub fn load2DAtlasMipchainFromMemory(
        _: *BinaryImage,
        _: u32,
        _: u32,
        _: [*]const u8,
        _: u32,
        _: image.TextureFormat,
        _: image.TextureColor,
    ) void {
        // TODO
    }

    pub fn load2DFromMemory(
        _: *BinaryImage,
        _: u32,
        _: u32,
        _: [*]const u8,
        _: u32,
        _: image.TextureFormat,
        _: image.TextureColor,
        _: bool,
    ) void {

        // TODO
    }
};
