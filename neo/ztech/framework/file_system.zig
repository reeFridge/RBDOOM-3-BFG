const std = @import("std");
const idlib = @import("../idlib.zig");
const cvar = @import("cvar_system.zig");
const global = @import("../global.zig");
const ResourceContainer = @import("file_resource.zig");
const CVar = cvar.CVar;

pub const SearchPath = extern struct {
    path: idlib.idStr = .{},
    gamedir: idlib.idStr = .{},
    resourceFiles: idlib.idList(*ResourceContainer) = .{},
    zipFiles: idlib.idList(*idlib.idZipContainer) = .{},

    pub fn initPathStrings(search_path: *SearchPath) void {
        search_path.path.initEmptyBuffer();
        search_path.gamedir.initEmptyBuffer();
    }
};

pub const MAX_OS_PATH: usize = 256;
pub const FILE_NOT_FOUND_TIMESTAMP: idlib.ID_TIME_T = -1;

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
    searchPaths: idlib.idList(SearchPath),
    loadCount: c_int,
    loadStack: c_int,
    gameFolder: idlib.idStr,
    manifestName: idlib.idStr,
    fileManifest: idlib.idStrList,
    preloadList: idlib.idPreloadManifest,
    resourceBufferPtr: ?[*]u8,
    resourceBufferSize: c_int,
    resourceBufferAvailable: c_int,
    numFilesOpenedAsCached: c_int,
    resourceFilesFound: bool,
    zipFilesFound: bool,
    doom2004Found: bool,
    doom2019Found: bool,

    extern fn c_fileSystem_readFile(
        *FileSystem,
        [*:0]const u8,
        ?*?*anyopaque,
        ?*idlib.ID_TIME_T,
    ) c_int;
    extern fn c_fileSystem_freeFile(*FileSystem, ?[*:0]u8) void;

    pub fn isInitialized(fs: *const FileSystem) void {
        return fs.searchPaths.num != 0;
    }

    pub fn init(fs: *FileSystem) AddDirectoryError!void {
        try cvar.setCVarsFromArgs("fs_basepath");
        try cvar.setCVarsFromArgs("fs_savepath");
        try cvar.setCVarsFromArgs("fs_game");
        try cvar.setCVarsFromArgs("fs_game_base");
        try cvar.setCVarsFromArgs("fs_copyfiles");

        //TODO: set default fs_basepath
        //TODO: set default fs_savepath

        try fs.startup();
    }

    const BASE_GAMEDIR: []const u8 = "base";
    fn startup(fs: *FileSystem) AddDirectoryError!void {
        fs.numFilesOpenedAsCached = 0;

        try fs.setupGameDirectories(BASE_GAMEDIR);

        // TODO: setupGameDirectories(fs_game_base);
        // TODO: setupGameDirectories(fs_game);

        try cmd.instance.addCommand(
            "path",
            cmd_printSearchPaths,
            cmd.CmdFlags.CMD_FL_SYSTEM,
            "lists search paths",
            null,
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

    fn setupGameDirectories(fs: *FileSystem, game_name: []const u8) AddDirectoryError!void {
        // setup basepath
        if (fs_basepath.getString().len > 0) {
            try fs.addGameDirectory(fs_basepath.getString(), game_name);
        }

        // TODO: setup savepath
        //if (fs_savepath.getString().len > 0) {
        //    try fs.addGameDirectory(fs_savepath.getString(), game_name);
        //}
    }

    const AddDirectoryError = error{OutOfMemory} || std.fs.File.OpenError;
    fn addGameDirectory(
        fs: *FileSystem,
        path: []const u8,
        dir: []const u8,
    ) AddDirectoryError!void {
        for (fs.searchPaths.constSlice()) |*search_path| {
            if (std.mem.eql(u8, search_path.path.constSlice(), path) and
                std.mem.eql(u8, search_path.gamedir.constSlice(), dir))
            {
                return;
            }
        }

        try fs.gameFolder.assignSlice(dir);

        const search = try fs.searchPaths.allocOne();
        search.* = SearchPath{};
        search.initPathStrings();

        try search.path.assignSlice(path);
        try search.gamedir.assignSlice(dir);

        // TODO: support .pk4/zip files

        var resources_path = idlib.idStr{};
        resources_path.initEmptyBuffer();
        defer resources_path.deinit();

        const resources_os_path = buildOSPath(path, dir, "") catch return error.OutOfMemory;
        // strip trailing sep: slice[0 .. len - 1]
        try resources_path.assignSlice(resources_os_path[0 .. resources_os_path.len - 1]);

        var resources_dir = try std.fs.openDirAbsolute(
            resources_path.constSlice(),
            .{ .iterate = true },
        );
        var dir_iterator = resources_dir.iterate();
        defer resources_dir.close();

        const allocator = global.gpa.allocator();
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
            if (rc.init(filename)) {
                _ = try search.resourceFiles.append(rc);
                fs.resourceFilesFound = true;
            }
        }
    }

    const MAX_FILE_SIZE = 1000 * 1024;
    const ReadFileAnyAllocError =
        OpenOSFileError ||
        std.fs.File.Reader.Error ||
        std.mem.Allocator.Error ||
        error{StreamTooLong};

    pub fn readFileAnyAlloc(
        fs: *const FileSystem,
        filename: []const u8,
    ) ReadFileAnyAllocError!?[]u8 {
        const opt_file = try fs.openFileRead(filename);

        if (opt_file) |file| {
            defer file.close();

            var reader = file.reader();
            const buffer = try reader.readAllAlloc(global.gpa.allocator(), MAX_FILE_SIZE);

            return buffer;
        } else {
            // TODO: search file inside .resource files
        }

        return null;
    }

    pub fn freeFileBuffer(_: *const FileSystem, buffer: []u8) void {
        global.gpa.allocator().free(buffer);
    }

    pub fn openFileRead(fs: *const FileSystem, filename: []const u8) OpenOSFileError!?std.fs.File {
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

        return null;
    }

    const OpenOSFileError = std.fs.File.OpenError || std.fs.File.SeekError;
    fn openOSFile(filename: []const u8, mode: FsMode) OpenOSFileError!std.fs.File {
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

        pub fn readBuffer(
            res: *InnerResourceFile,
            dest: []u8,
        ) std.fs.File.ReadError!usize {
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

    fn getInnerResourceFile(fs: *const FileSystem, filename: []const u8) !?InnerResourceFile {
        const cache_entry = fs.getResourceCacheEntry(filename) orelse return null;

        var inner_file = InnerResourceFile{
            .name = cache_entry.constSlice(),
            .offset = cache_entry.offset,
            .length = cache_entry.length,
            .resource_file = cache_entry.owner.resourceFile,
            .internal_file_pos = 0,
        };

        if ((cache_entry.length <= fs.resourceBufferAvailable) or
            cache_entry.length < 8 * 1024 * 1024)
        {
            const allocator = global.gpa.allocator();
            const buf = if (cache_entry.length < fs.resourceBufferAvailable) buf: {
                fs.resourceBufferAvailable = 0;
                break :buf fs.resourceBufferPtr[0..cache_entry.length];
            } else try allocator.alloc(u8, cache_entry.length);

            try inner_file.readBuffer(buf);

            inner_file.resource_buffer = buf;
            return inner_file;
        }

        return inner_file;
    }

    fn getResourceCacheEntry(fs: *const FileSystem, filename: []const u8) ?ResourceContainer.CacheEntry {
        var buffer: [MAX_OS_PATH]u8 = std.mem.zeroes([MAX_OS_PATH]u8);
        const canonical_path = buffer[0..filename.len];
        _ = std.mem.replace(u8, filename, '\\', '/', canonical_path);
        for (canonical_path) |*char| {
            char.* = std.ascii.toLower(char.*);
        }

        const search_paths = fs.searchPaths.constSlice();
        var search_path_index = if (search_paths.len > 0) search_paths.len - 1 else 0;
        while (search_path_index >= 0) : (search_path_index -= 1) {
            const search_path = &search_paths[search_path_index];
            const resource_files = search_path.resourceFiles.constSlice();

            var resource_file_index = if (resource_files.len > 0) resource_files.len - 1 else 0;
            while (resource_file_index >= 0) : (resource_file_index -= 1) {
                const res_file = &resource_files[resource_file_index];
                const key = res_file.cacheHash.generateKey(canonical_path, false);

                var cache_index = res_file.cacheHash.getFirst(key);

                while (cache_index != idlib.idHashIndex.NULL_INDEX) : (cache_index = res_file.cacheHash.getNext(cache_index)) {
                    if (res_file.cacheTable.getValue(cache_index)) |rt| {
                        if (std.ascii.eqlIgnoreCase(
                            rt.filename.constSlice(),
                            canonical_path,
                        )) return rt;
                    }
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

    pub fn getTimestamp(fs: *FileSystem, relative_path: [:0]const u8) idlib.ID_TIME_T {
        var timestamp = FILE_NOT_FOUND_TIMESTAMP;

        if (relative_path.len == 0)
            return timestamp;

        _ = fs.readFile(relative_path, null, &timestamp);

        return timestamp;
    }

    pub fn readFile(
        fs: *FileSystem,
        relative_path: [:0]const u8,
        buffer: ?*?*anyopaque,
        timestamp: ?*idlib.ID_TIME_T,
    ) c_int {
        return c_fileSystem_readFile(fs, relative_path.ptr, buffer, timestamp);
    }

    pub fn freeFile(fs: *FileSystem, buffer: [:0]u8) void {
        return c_fileSystem_freeFile(fs, @ptrCast(buffer));
    }

    pub fn openFileReadMemory(_: *FileSystem, _: [:0]const u8) ?std.fs.File {
        return null;
    }
};

pub const instance = @extern(*FileSystem, .{ .name = "fileSystemLocal" });

fn sliceLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.order(u8, lhs, rhs) == .lt;
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
                zip_container.fileName.constSlice(),
                zip_container.numFileResources,
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
