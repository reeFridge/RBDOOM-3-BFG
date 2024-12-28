//! @exportCVars
const std = @import("std");
const idlib = @import("../idlib.zig");
const cvar = @import("cvar_system.zig");
const global = @import("../global.zig");
const ResourceContainer = @import("file_resource.zig");
const CVar = cvar.CVar;
const Allocator = std.mem.Allocator;

pub const SearchPath = extern struct {
    path: idlib.Str = .{},
    gamedir: idlib.Str = .{},
    resourceFiles: idlib.List(*ResourceContainer) = .{},
    zipFiles: idlib.List(*idlib.ZipContainer) = .{},
};

pub const max_os_path: usize = 256;
pub const not_found_time: idlib.Time = -1;

pub var fs_basepath: CVar = CVar.init(
    "fs_basepath",
    "",
    cvar.CVarFlags.CVAR_SYSTEM | cvar.CVarFlags.CVAR_INIT,
    "",
);

pub const FsMode = enum(c_int) {
    FS_READ = 0,
    FS_WRITE = 1,
    FS_APPEND = 2,
};

pub const FileSystem = extern struct {
    vptr: *anyopaque,
    searchPaths: idlib.List(SearchPath),
    loadCount: u32,
    loadStack: u32,
    gameFolder: idlib.Str,
    manifestName: idlib.Str,
    fileManifest: idlib.StrList,
    preloadList: idlib.PreloadManifest,
    resourceBufferPtr: ?[*]u8,
    resourceBufferSize: u32,
    resourceBufferAvailable: u32,
    numFilesOpenedAsCached: u32,
    resourceFilesFound: bool,
    zipFilesFound: bool,
    doom2004Found: bool,
    doom2019Found: bool,

    pub fn isInitialized(fs: *const FileSystem) void {
        return fs.searchPaths.num != 0;
    }

    pub inline fn usingResourceFiles(_: *const FileSystem) bool {
        return true;
    }

    pub inline fn inProductionMode(_: *const FileSystem) bool {
        return false;
    }

    pub fn init(fs: *FileSystem, allocator: Allocator) AddDirectoryError!void {
        try cvar.setCVarsFromArgs("fs_basepath", allocator);
        try cvar.setCVarsFromArgs("fs_savepath", allocator);
        try cvar.setCVarsFromArgs("fs_game", allocator);
        try cvar.setCVarsFromArgs("fs_game_base", allocator);
        try cvar.setCVarsFromArgs("fs_copyfiles", allocator);

        //TODO: set default fs_basepath
        //TODO: set default fs_savepath

        try fs.startup(allocator);
    }

    const BASE_GAMEDIR: []const u8 = "base";
    fn startup(fs: *FileSystem, allocator: Allocator) AddDirectoryError!void {
        fs.numFilesOpenedAsCached = 0;

        try fs.setupGameDirectories(BASE_GAMEDIR, allocator);

        // TODO: setupGameDirectories(fs_game_base);
        // TODO: setupGameDirectories(fs_game);

        try cmd.instance.addCommand(
            "path",
            cmd_printSearchPaths,
            cmd.CmdFlags.CMD_FL_SYSTEM,
            "lists search paths",
            null,
            allocator,
        );
        // TODO: addCommand dir
        // TODO: addCommand dirtree
        // TODO: addCommand touchFile
        // TODO: addCommand touchFileList
        // TODO: addCommand buildGame
        // TODO: addCommand writeResourceFile
        // TODO: addCommand extractResourceFile
        // TODO: addCommand updateResourceFile
        // TODO: addCommand generateResourceCRCs

        // print the current search paths
        cmd_printSearchPaths(&.{});
    }

    fn setupGameDirectories(
        fs: *FileSystem,
        game_name: []const u8,
        allocator: Allocator,
    ) AddDirectoryError!void {
        // setup basepath
        if (fs_basepath.getString().len > 0) {
            try fs.addGameDirectory(fs_basepath.getString(), game_name, allocator);
        }

        // TODO: setup savepath
        //if (fs_savepath.getString().len > 0) {
        //    try fs.addGameDirectory(fs_savepath.getString(), game_name);
        //}
    }

    const AddDirectoryError = Allocator.Error || std.fs.File.OpenError;
    fn addGameDirectory(
        fs: *FileSystem,
        path: []const u8,
        dir: []const u8,
        allocator: Allocator,
    ) AddDirectoryError!void {
        for (fs.searchPaths.constSlice()) |*search_path| {
            if (std.mem.eql(u8, search_path.path.constSlice(), path) and
                std.mem.eql(u8, search_path.gamedir.constSlice(), dir))
            {
                return;
            }
        }

        try fs.gameFolder.assignSlice(dir, allocator);

        const search = try fs.searchPaths.allocOne(allocator);
        search.* = SearchPath{};

        try search.path.assignSlice(path, allocator);
        try search.gamedir.assignSlice(dir, allocator);

        // TODO: support .pk4/zip files

        var resources_path = idlib.Str{};
        defer resources_path.deinit(allocator);

        const resources_os_path = buildOSPath(path, dir, "") catch return error.OutOfMemory;
        // strip trailing sep: slice[0 .. len - 1]
        try resources_path.assignSlice(
            resources_os_path[0 .. resources_os_path.len - 1],
            allocator,
        );

        var resources_dir = try std.fs.openDirAbsolute(
            resources_path.constSlice(),
            .{ .iterate = true },
        );
        var dir_iterator = resources_dir.iterate();
        defer resources_dir.close();

        var file_list = std.ArrayList([]const u8).init(allocator);
        var arena = std.heap.ArenaAllocator.init(allocator);
        const file_list_allocator = arena.allocator();
        defer {
            arena.deinit();
            file_list.deinit();
        }

        while (try dir_iterator.next()) |entry| {
            if (entry.kind == .directory) continue;

            const ext = std.fs.path.extension(entry.name);

            if (std.mem.eql(u8, ext, ".resources")) {
                try file_list.append(try file_list_allocator.dupe(u8, entry.name));
            }
        }

        const file_list_slice = file_list.items;
        std.mem.sort([]const u8, file_list_slice, {}, sliceLessThan);

        for (file_list_slice) |filename| {
            const rc = try allocator.create(ResourceContainer);
            rc.* = .{};
            if (rc.init(filename, allocator)) {
                _ = try search.resourceFiles.append(rc, allocator);
                fs.resourceFilesFound = true;
            }
        }
    }

    const MAX_FILE_SIZE = 1000 * 1024;
    pub const ReadFileAnyAllocError =
        ReadInnerResourceFileError ||
        OpenOSFileError ||
        std.fs.File.Reader.Error ||
        Allocator.Error ||
        error{StreamTooLong};

    pub fn readFileAnyAlloc(
        fs: *FileSystem,
        filename: []const u8,
        allocator: Allocator,
    ) ReadFileAnyAllocError![]u8 {
        return if (fs.openFileRead(filename)) |file| buffer: {
            defer file.close();
            var reader = file.reader();
            break :buffer try reader.readAllAlloc(
                allocator,
                MAX_FILE_SIZE,
            );
        } else |err| switch (err) {
            error.FileNotFound => buffer: {
                const inner_file = try fs.readInnerResourceFile(
                    filename,
                    allocator,
                ) orelse return error.FileNotFound;

                break :buffer inner_file.resource_buffer orelse unreachable;
            },
            else => |left_err| return left_err,
        };
    }

    pub fn getFileTimestamp(
        fs: *const FileSystem,
        path: []const u8,
    ) idlib.Time {
        var file = fs.openFileRead(path) catch return not_found_time;
        defer file.close();

        const file_stat = file.stat() catch return not_found_time;

        return @intCast(file_stat.mtime);
    }

    pub const OpenFileReadAnyError =
        OpenOSFileError ||
        std.fs.File.GetSeekPosError;
    pub fn openFileReadAny(
        fs: *const FileSystem,
        filename: []const u8,
    ) OpenFileReadAnyError!struct { bool, std.fs.File } {
        return if (fs.openFileRead(filename)) |file|
            .{ true, file }
        else |err| switch (err) {
            error.FileNotFound => result: {
                const cache_entry = fs.getResourceCacheEntry(
                    filename,
                ) orelse break :result error.FileNotFound;

                var inner_file = InnerResourceFile{
                    .name = cache_entry.filename.constSlice(),
                    .offset = cache_entry.offset,
                    .length = cache_entry.length,
                    .resource_file = cache_entry.owner.resource_file orelse unreachable,
                    .internal_file_pos = 0,
                };

                // resource file is open by default
                const offset = inner_file.offset + inner_file.internal_file_pos;
                if (try inner_file.resource_file.getPos() != offset) {
                    try inner_file.resource_file.seekTo(offset);
                }

                break :result .{ false, inner_file.resource_file };
            },
            else => |left_err| return left_err,
        };
    }

    pub fn openFileRead(fs: *const FileSystem, filename: []const u8) OpenOSFileError!std.fs.File {
        var paths_iterator = std.mem.reverseIterator(fs.searchPaths.constSlice());
        while (paths_iterator.nextPtr()) |search| {
            const abs_path = try buildOSPath(
                search.path.constSlice(),
                search.gamedir.constSlice(),
                filename,
            );

            return openOSFile(abs_path, .FS_READ) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => |leftover_err| return leftover_err,
            };
        }

        return error.FileNotFound;
    }

    pub const OpenOSFileError = std.fs.File.OpenError || std.fs.File.SeekError;
    pub fn openOSFile(filename: []const u8, mode: FsMode) OpenOSFileError!std.fs.File {
        return switch (mode) {
            .FS_READ => try std.fs.openFileAbsolute(filename, .{ .mode = .read_only }),
            .FS_WRITE => try std.fs.openFileAbsolute(filename, .{ .mode = .write_only }),
            .FS_APPEND => file: {
                var file = try std.fs.openFileAbsolute(filename, .{ .mode = .write_only });
                try file.seekFromEnd(0);

                break :file file;
            },
        };
    }

    const MAX_STRING_CHARS: usize = 1024;
    var os_path: [MAX_STRING_CHARS]u8 = std.mem.zeroes([MAX_STRING_CHARS]u8);
    fn buildOSPath(
        base_path: []const u8,
        game_dir: []const u8,
        relative_path: []const u8,
    ) std.fmt.BufPrintError![]const u8 {
        if (isOSPath(relative_path)) return relative_path;

        var path_part_1 = os_path[0..base_path.len];
        std.mem.copyForwards(u8, path_part_1, base_path);

        path_part_1 = stripTrailingSep(path_part_1);

        const path_part_2 = try std.fmt.bufPrint(
            os_path[path_part_1.len..],
            "/{s}/{s}",
            .{ game_dir, relative_path },
        );

        const os_path_slice = os_path[0 .. path_part_1.len + path_part_2.len];
        replaceSeparatorsByNative(os_path_slice);

        return os_path_slice;
    }

    fn stripTrailingSep(path: []u8) []u8 {
        var slice = path[0..];
        while (slice.len > 0 and
            (slice[slice.len - 1] == std.fs.path.sep_windows or
            slice[slice.len - 1] == std.fs.path.sep_posix))
        {
            slice = slice[0 .. slice.len - 1];
        }

        return slice;
    }

    fn replaceSeparatorsByNative(path: []u8) void {
        for (path) |*char| {
            if (char.* == std.fs.path.sep_windows or char.* == std.fs.path.sep_posix) {
                char.* = std.fs.path.sep;
            }
        }
    }

    pub const InnerResourceFile = struct {
        name: []const u8,
        offset: usize,
        length: usize,
        resource_file: std.fs.File,
        internal_file_pos: usize = 0,
        resource_buffer: ?[]u8 = null,

        pub const ReadBufferError =
            std.fs.File.GetSeekPosError ||
            std.fs.File.ReadError;
        pub fn readBuffer(
            res: *InnerResourceFile,
            dest: []u8,
        ) ReadBufferError!usize {
            const len = if (res.internal_file_pos + dest.len > res.length)
                res.length - res.internal_file_pos
            else
                dest.len;

            var read: usize = 0;
            if (read != len) {
                if (res.resource_buffer) |resource_buffer| {
                    const src = resource_buffer[res.internal_file_pos .. res.internal_file_pos + len];
                    std.mem.copyForwards(u8, dest[0..len], src);
                    read = len;
                } else {
                    const offset = res.offset + res.internal_file_pos;
                    if (try res.resource_file.getPos() != offset) {
                        try res.resource_file.seekTo(offset);
                    }

                    read = try res.resource_file.read(dest[0..len]);
                }
            }

            res.internal_file_pos += read;

            return read;
        }
    };

    const ReadInnerResourceFileError =
        Allocator.Error ||
        InnerResourceFile.ReadBufferError;
    fn readInnerResourceFile(
        fs: *FileSystem,
        filename: []const u8,
        allocator: Allocator,
    ) ReadInnerResourceFileError!?InnerResourceFile {
        const cache_entry = fs.getResourceCacheEntry(filename) orelse return null;

        var inner_file = InnerResourceFile{
            .name = cache_entry.filename.constSlice(),
            .offset = cache_entry.offset,
            .length = cache_entry.length,
            .resource_file = cache_entry.owner.resource_file orelse unreachable,
            .internal_file_pos = 0,
        };

        const buffer = try allocator.alloc(u8, cache_entry.length);
        _ = try inner_file.readBuffer(buffer);
        inner_file.resource_buffer = buffer;

        // TODO: cache resources while level load

        return inner_file;
    }

    fn getResourceCacheEntry(
        fs: *const FileSystem,
        filename: []const u8,
    ) ?ResourceContainer.CacheEntry {
        var buffer: [max_os_path]u8 = std.mem.zeroes([max_os_path]u8);
        const canonical_path = buffer[0..filename.len];
        _ = std.mem.replace(u8, filename, "\\", "/", canonical_path);
        for (canonical_path) |*char| {
            char.* = std.ascii.toLower(char.*);
        }

        var paths_iterator = std.mem.reverseIterator(fs.searchPaths.constSlice());
        while (paths_iterator.next()) |search_path| {
            var res_files_iterator = std.mem.reverseIterator(search_path.resourceFiles.constSlice());
            while (res_files_iterator.next()) |res_file| {
                const key = res_file.cache_hash.generateKey(canonical_path, false);

                var cache_index = res_file.cache_hash.first(key);
                while (cache_index != -1) : (cache_index = res_file.cache_hash.next(@intCast(cache_index))) {
                    const index: u32 = @intCast(cache_index);
                    const entry = &res_file.cache_table.constSlice()[index];
                    if (std.ascii.eqlIgnoreCase(
                        entry.filename.constSlice(),
                        canonical_path,
                    )) return entry.*;
                }
            }
        }

        return null;
    }

    fn isOSPath(path: []const u8) bool {
        // why?
        if (path.len >= 4 and std.mem.eql(u8, path[0..4], "mtp:")) return true;

        if (path.len >= 2) {
            if (path[1] == ':') {
                // already an OS path starting with a drive (WIN)
                if ((path[0] > 64 and path[0] < 91) or (path[0] > 96 and path[0] < 123))
                    return true;
            }

            // root path
            if (path[0] == std.fs.path.sep_windows or path[0] == std.fs.path.sep_posix) return true;
        }

        return false;
    }

    pub fn listFilenames(
        fs: *const FileSystem,
        folder: []const u8,
        extensions: []const []const u8,
        allocator: Allocator,
    ) ListOSFilesError![][]u8 {
        if (extensions.len == 0) return &.{};
        if (folder.len == 0) return &.{};

        var list = std.ArrayListUnmanaged([]u8){};
        errdefer {
            for (list.items) |item| allocator.free(item);
            list.deinit(allocator);
        }

        var hash_index = idlib.HashIndex{};
        defer hash_index.free(allocator);

        // TODO: using_zip_files

        var paths_iterator = std.mem.reverseIterator(fs.searchPaths.constSlice());
        while (paths_iterator.next()) |search_path| {
            var res_files_iterator = std.mem.reverseIterator(search_path.resourceFiles.constSlice());
            while (res_files_iterator.next()) |res_container| {
                for (res_container.cache_table.constSlice()) |entry| {
                    const full = entry.filename.constSlice();
                    const dirname = std.fs.path.dirname(full) orelse "";

                    if (!std.ascii.eqlIgnoreCase(dirname, folder)) continue;

                    const filename = std.fs.path.basename(full);
                    const ext = std.fs.path.extension(full);

                    for (extensions) |extension| {
                        if (std.ascii.eqlIgnoreCase(extension, ext)) {
                            _ = try listAppendUnique(
                                filename,
                                &list,
                                &hash_index,
                                allocator,
                            );
                        }
                    }
                }
            }
        }

        paths_iterator = std.mem.reverseIterator(fs.searchPaths.constSlice());
        paths: while (paths_iterator.next()) |search_path| {
            const full_path = buildOSPath(
                search_path.path.constSlice(),
                search_path.gamedir.constSlice(),
                folder,
            ) catch return error.OutOfMemory;

            for (extensions) |extension| {
                const filenames = listOSFiles(
                    full_path,
                    extension,
                    allocator,
                ) catch |err| switch (err) {
                    error.FileNotFound => continue :paths,
                    else => |left_err| return left_err,
                };
                defer {
                    for (filenames) |filename| allocator.free(filename);
                    allocator.free(filenames);
                }

                for (filenames) |filename| {
                    _ = try listAppendUnique(
                        filename,
                        &list,
                        &hash_index,
                        allocator,
                    );
                }
            }
        }

        return list.toOwnedSlice(allocator);
    }

    pub const ListOSFilesError = Allocator.Error || std.fs.Dir.OpenError;
    fn listOSFiles(
        directory: []const u8,
        extension: []const u8,
        allocator: Allocator,
    ) ListOSFilesError![][]u8 {
        var dir = try std.fs.cwd().openDir(
            directory,
            .{ .iterate = true },
        );
        defer dir.close();

        var dir_iterator = dir.iterate();

        var array = std.ArrayListUnmanaged([]u8){};

        while (try dir_iterator.next()) |entry| {
            if (entry.kind == .directory) continue;

            const ext = std.fs.path.extension(entry.name);

            if (!std.ascii.eqlIgnoreCase(ext, extension)) continue;

            const copy = try allocator.dupe(u8, entry.name);
            try array.append(allocator, copy);
        }

        return array.toOwnedSlice(allocator);
    }

    fn listAppendUnique(
        item: []const u8,
        list: *std.ArrayListUnmanaged([]u8),
        hash_index: *idlib.HashIndex,
        allocator: Allocator,
    ) Allocator.Error!usize {
        const hash_key = hash_index.generateKey(item, false);
        var i = hash_index.first(hash_key);
        while (i >= 0) : (i = hash_index.next(@intCast(i))) {
            const index: u32 = @intCast(i);
            if (std.ascii.eqlIgnoreCase(list.items[index], item)) {
                return index;
            }
        }

        const index = list.items.len;
        const copy = try allocator.dupe(u8, item);
        try list.append(allocator, copy);
        try hash_index.add(hash_key, @intCast(index), allocator);

        return index;
    }

    pub fn openFileReadMemory(_: *FileSystem, _: [:0]const u8) ?std.fs.File {
        return null;
    }
};

pub const instance = @extern(*FileSystem, .{ .name = "fileSystemLocal" });

fn sliceLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
}

pub fn stripExtension(path: []const u8) []const u8 {
    const dot_index = std.mem.lastIndexOfScalar(u8, path, '.') orelse return path;
    return path[0..dot_index];
}

// commands

const cmd = @import("cmd_system.zig");

fn cmd_printSearchPaths(_: *const cmd.CmdArgs) callconv(.C) void {
    std.debug.print("[FS] Current search paths:\n", .{});

    var paths_iterator = std.mem.reverseIterator(instance.searchPaths.constSlice());
    var i: usize = 0;
    while (paths_iterator.nextPtr()) |search| : (i += 1) {
        std.debug.print("#{} : {s}/{s}\n", .{
            i,
            search.path.constSlice(),
            search.gamedir.constSlice(),
        });

        var zip_files_iterator = std.mem.reverseIterator(search.zipFiles.constSlice());
        while (zip_files_iterator.next()) |zip_container| {
            std.debug.print("\t(zip) {s}/{s}/{s} (contains {} files)\n", .{
                search.path.constSlice(),
                search.gamedir.constSlice(),
                std.mem.sliceTo(&zip_container.filename, 0),
                zip_container.num_file_resources,
            });
        }

        var res_files_iterator = std.mem.reverseIterator(search.resourceFiles.constSlice());
        while (res_files_iterator.next()) |res_container| {
            std.debug.print("\t(resource) {s}/{s}/{s} (contains {} files)\n", .{
                search.path.constSlice(),
                search.gamedir.constSlice(),
                res_container.filename.constSlice(),
                res_container.num_files,
            });
        }
    }
}
