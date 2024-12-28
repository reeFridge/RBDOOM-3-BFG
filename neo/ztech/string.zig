const std = @import("std");

pub fn icontains(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;
    var i: usize = 0;
    const end = haystack.len - needle.len;
    while (i <= end) : (i += 1) {
        if (std.ascii.eqlIgnoreCase(haystack[i..][0..needle.len], needle)) return i;
    }
    return null;
}

pub fn contains(haystack: []const u8, needle: []const u8) ?usize {
    if (needle.len > haystack.len) return null;
    var i: usize = 0;
    const end = haystack.len - needle.len;
    while (i <= end) : (i += 1) {
        if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) return i;
    }
    return null;
}
