const std = @import("std");

// Signed because -1 means "File not found" and we don't want that to compare > than any other time
pub const Time = c_longlong;

extern fn c_fs_getTimestamp([*:0]const u8) callconv(.C) Time;
pub fn getTimestamp(relative_path: [:0]const u8) Time {
    return c_fs_getTimestamp(relative_path.ptr);
}

pub fn openFileReadMemory(_: [:0]const u8) ?std.fs.File {
    return null;
}
