const fs = @import("../framework/file_system.zig");
const std = @import("std");
const image = @import("image.zig");
const idlib = @import("../idlib.zig");
const Allocator = std.mem.Allocator;

pub const bimage_version: u32 = 10;
pub const bimage_magic: u32 =
    ('B' << @as(u32, 0)) |
    ('I' << @as(u32, 8)) |
    ('M' << @as(u32, 16)) |
    (bimage_version << @as(u32, 24));

pub const BinaryImage = struct {
    const FileHeader = extern struct {
        source_file_time: idlib.Time align(1),
        header_magic: u32 align(1),
        texture_type: image.TextureType align(1),
        format: image.TextureFormat align(1),
        color_format: image.TextureColor align(1),
        width: u32 align(1),
        height: u32 align(1),
        num_levels: u32 align(1),
    };

    const Image = struct {
        const Header = extern struct {
            // mip
            level: u32,
            // array slice
            dest_z: u32,
            width: u32,
            height: u32,
            // data size bytes follow
            data_size: u32,
        };

        header: Header,
        data: ?[]u8 = null,
    };

    name: idlib.Str = .{},
    header: FileHeader = std.mem.zeroes(FileHeader),
    images: idlib.List(Image) = .{},

    pub fn init(
        bin_image: *BinaryImage,
        name: []const u8,
        allocator: Allocator,
    ) Allocator.Error!void {
        try bin_image.name.assignSlice(name, allocator);
    }

    pub fn deinit(bin_image: *BinaryImage, allocator: Allocator) void {
        bin_image.name.deinit(allocator);
        for (bin_image.images.slice()) |*level_image| {
            if (level_image.data) |data| {
                allocator.free(data);
            }
        }

        bin_image.images.clear(allocator);
    }

    pub fn loadFromGenerated(
        bin_image: *BinaryImage,
        source_file_time: idlib.Time,
        allocator: Allocator,
    ) idlib.Time {
        var buffer: [fs.max_os_path]u8 = undefined;
        const binary_filename = formatGeneratedName(
            &buffer,
            bin_image.name.constSlice(),
        );

        const owns_file, const file = fs.instance.openFileReadAny(
            binary_filename,
        ) catch return fs.not_found_time;
        defer if (owns_file) file.close();

        bin_image.loadFromGeneratedFile(file, source_file_time, allocator) catch
            return fs.not_found_time;

        const file_stat = file.stat() catch unreachable;

        return @intCast(file_stat.mtime);
    }

    fn loadFromGeneratedFile(
        bin_image: *BinaryImage,
        file: std.fs.File,
        source_file_time: idlib.Time,
        allocator: Allocator,
    ) !void {
        const reader = file.reader();
        const bimage_header = try reader.readStructEndian(FileHeader, .big);

        if (bimage_header.header_magic != bimage_magic) return error.MagicNotMatch;

        bin_image.header = bimage_header;

        if (!fs.instance.inProductionMode() and
            source_file_time != fs.not_found_time and
            source_file_time != 0 and
            source_file_time != bimage_header.source_file_time)
            return error.TimestampNotMatch;

        const num_images = if (bimage_header.texture_type == .cubic)
            bimage_header.num_levels * 6
        else
            bimage_header.num_levels;

        try bin_image.images.setNum(num_images, allocator);

        for (bin_image.images.slice()) |*level_image| {
            const header = try reader.readStructEndian(Image.Header, .big);
            std.debug.assert(header.level >= 0 and header.level < bimage_header.num_levels);
            std.debug.assert(header.dest_z == 0 or bimage_header.texture_type == .cubic);
            std.debug.assert(header.data_size > 0);
            // DXT images need to be padded to 4x4 block sizes, but the original image
            // sizes are still retained, so the stored data size may be larger than
            // just the multiplication of dimensions
            std.debug.assert(header.data_size >= header.width * header.height *
                @divTrunc(image.bitsForFormat(bimage_header.format), 8));

            level_image.header = header;

            const data_size = if (bimage_header.format == .rgb565)
                header.data_size * 2
            else if (bimage_header.format == .dxt1 or bimage_header.format == .dxt5) data_size: {
                const row_pitch = image.getRowPitch(bimage_header.format, header.width);
                const temp = (bimage_header.height + 3) & ~@as(u32, 3);
                const mip_rows = @divTrunc(
                    (temp >> @intCast(header.level)) + 3,
                    4,
                );
                break :data_size @max(header.data_size, row_pitch * mip_rows);
            } else header.data_size;

            const data = try allocator.alloc(u8, data_size);
            errdefer allocator.free(data);
            level_image.header.data_size = data_size;

            if (try reader.read(data[0..header.data_size]) == 0)
                return error.EndOfStream;

            if (bimage_header.format == .rgb565) {
                std.debug.assert(@mod(level_image.header.data_size, 4) == 0);
                var pixel_index: i32 = @as(
                    i32,
                    @intCast(@divTrunc(level_image.header.data_size, 2)),
                ) - 2;
                while (pixel_index >= 0) : (pixel_index -= 2) {
                    const index: u32 = @intCast(pixel_index);

                    const value: u16 = @as(u16, @intCast(data[index + 0])) << 8 |
                        data[index + 1];
                    data[index * 2 + 0] = @intCast(((value >> 11) * 527 + 23) >> 6);
                    data[index * 2 + 1] = @intCast((((value & 0x07E0) >> 5) * 259 + 33) >> 6);
                    data[index * 2 + 2] = @intCast(((value & 0x001F) * 527 + 23) >> 6);
                    data[index * 2 + 3] = 0xFF;
                }
            }

            level_image.data = data;
        }
    }

    fn formatGeneratedName(buffer: []u8, name: []const u8) []u8 {
        var gen_name = std.fmt.bufPrint(
            buffer,
            "generated/images/{s}.bimage",
            .{name},
        ) catch unreachable;
        _ = std.mem.replace(u8, gen_name, "(", "/", gen_name);
        _ = std.mem.replace(u8, gen_name, ",", "/", gen_name);

        gen_name = replaceAndShrink(gen_name, ")", "");
        gen_name = replaceAndShrink(gen_name, " ", "");

        return gen_name;
    }

    // only if not increase length
    fn replaceAndShrink(buffer: []u8, search: []const u8, replace: []const u8) []u8 {
        const size = std.mem.replacementSize(u8, buffer, search, replace);
        std.debug.assert(size <= buffer.len);

        _ = std.mem.replace(u8, buffer, search, replace, buffer);

        return buffer[0..size];
    }

    pub fn load2DAtlasMipchainFromMemory(
        _: *BinaryImage,
        _: u32,
        _: u32,
        _: []const u8,
        _: u32,
        _: image.TextureFormat,
        _: image.TextureColor,
    ) void {
        @panic("not implemented");
    }

    pub fn load2DFromMemory(
        _: *BinaryImage,
        _: u32,
        _: u32,
        _: []const u8,
        _: u32,
        _: image.TextureFormat,
        _: image.TextureColor,
        _: bool,
    ) void {
        @panic("not implemented");
    }
};
