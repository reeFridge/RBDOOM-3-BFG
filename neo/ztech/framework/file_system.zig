const std = @import("std");
const idlib = @import("../idlib.zig");

pub const SearchPath = extern struct {
    path: idlib.idStr,
    gamedif: idlib.idStr,
    resourceFiles: idlib.idList(*idlib.idResourceContainer),
    zipFiles: idlib.idList(*idlib.idZipContainer),
};

pub const FILE_NOT_FOUND_TIMESTAMP: idlib.ID_TIME_T = -1;

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
        ?**anyopaque,
        *idlib.ID_TIME_T,
    ) c_int;

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
        buffer: ?**anyopaque,
        timestamp: *idlib.ID_TIME_T,
    ) c_int {
        return c_fileSystem_readFile(fs, relative_path.ptr, buffer, timestamp);
    }

    pub fn openFileReadMemory(_: *FileSystem, _: [:0]const u8) ?std.fs.File {
        return null;
    }
};

pub const instance = @extern(*FileSystem, .{ .name = "fileSystemLocal" });
