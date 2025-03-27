const std = @import("std");
const idlib = @import("../idlib.zig");
const fs = @import("file_system.zig");
const global = @import("../global.zig");
const Allocator = std.mem.Allocator;
const FixedBufferString = @import("../string.zig").FixedBufferString;

pub const CacheEntry = struct {
    filename: FixedBufferString(256),
    offset: u32,
    length: u32,
    owner: *ResourceContainer,
};

const ResourceContainer = @This();

const RESOURCE_FILE_MAGIC: u32 = 0xD000000D;

filename: FixedBufferString(256) = .{},
resource_file: ?std.fs.File = null,
table_offset: u32 = 0,
table_len: u32 = 0,
magic: u32 = 0,
num_files: u32 = 0,
cache_table: idlib.List(CacheEntry) = .{},
cache_hash: idlib.HashIndex = .{},

pub fn init(rc: *ResourceContainer, filename: []const u8, allocator: Allocator) bool {
    const file = fs.instance.openFileRead(filename) catch return false;

    rc.resource_file = file;

    var file_reader = file.reader();
    const magic = file_reader.readInt(@TypeOf(rc.magic), .big) catch
        readFail("magic");

    if (magic != RESOURCE_FILE_MAGIC) {
        @panic("[FATAL] magic != RESOURCE_FILE_MAGIC");
    }

    rc.magic = magic;
    rc.filename.assignSlice(filename) catch @panic("[FATAL] Filename len is too big");

    rc.table_offset = file_reader.readInt(@TypeOf(rc.table_offset), .big) catch
        readFail("table_offset");
    rc.table_len = file_reader.readInt(@TypeOf(rc.table_len), .big) catch
        readFail("table_len");

    file.seekTo(rc.table_offset) catch {
        @panic("[FATAL] Fail to seek");
    };

    var temp_allocator = global.gpa.allocator();
    const buf = temp_allocator.alloc(u8, rc.table_len) catch {
        @panic("[FATAL] Fail to alloc buf for header");
    };
    defer temp_allocator.free(buf);

    _ = file_reader.read(buf) catch readFail("resource_header");

    var header = std.io.fixedBufferStream(buf);
    var header_reader = header.reader();

    rc.num_files = header_reader.readInt(@TypeOf(rc.num_files), .big) catch
        readFail("num_files");

    rc.cache_table.setNum(rc.num_files, allocator) catch {
        @panic("[FATAL] Fail to allocate cache_table");
    };

    for (0..rc.num_files) |i| {
        const entry = &rc.cache_table.slice()[i];

        const filename_len = header_reader.readInt(u32, .little) catch
            readFail("filename_len");

        entry.filename.len = @intCast(filename_len);
        _ = header_reader.read(entry.filename.slice()) catch
            readFail("inner_filename");

        entry.offset = header_reader.readInt(@TypeOf(entry.offset), .big) catch
            readFail("offset");
        entry.length = header_reader.readInt(@TypeOf(entry.length), .big) catch
            readFail("len");

        entry.owner = rc;

        const key = rc.cache_hash.generateKey(entry.filename.constSlice(), false);
        rc.cache_hash.add(
            key,
            @intCast(i),
            allocator,
        ) catch @panic("[FATAL] Fail to add a key to the hash");
    }

    return true;
}

pub fn unpack(rc: *ResourceContainer, out_dir: []const u8, allocator: Allocator) !void {
    const file = &rc.resource_file.?;
    const entries = rc.cache_table.constSlice();

    var dir = try std.fs.openDirAbsolute(out_dir, .{});
    defer dir.close();

    for (entries, 0..) |*entry, i| {
        std.debug.print("{s}\n", .{entry.filename.constSlice()});
        try file.seekTo(entry.offset);
        const buf = try allocator.alloc(u8, entry.length);
        defer allocator.free(buf);

        _ = try file.read(buf);

        if (std.fs.path.dirname(entry.filename.constSlice())) |dirname| {
            try dir.makePath(dirname);
        }

        var out_file_path = std.ArrayList(u8).init(allocator);
        defer out_file_path.deinit();
        try out_file_path.appendSlice(out_dir);
        try out_file_path.append('/');
        try out_file_path.appendSlice(entry.filename.constSlice());

        std.debug.print("-> {s}\n", .{out_file_path.items});

        var out_file = try std.fs.createFileAbsolute(out_file_path.items, .{});
        defer out_file.close();

        try out_file.writeAll(buf);
        std.debug.print("[{}/{}] OK\n", .{ i + 1, entries.len });
    }
}

inline fn readFail(var_name: []const u8) void {
    @panic("[FATAL] Fail to read " ++ var_name ++ " from resource file");
}
