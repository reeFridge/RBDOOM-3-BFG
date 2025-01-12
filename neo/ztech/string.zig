const std = @import("std");

pub fn FixedBufferString(size: comptime_int) type {
    return struct {
        buffer: [size]u8 = undefined,
        len: std.math.IntFittingRange(0, size - 1) = 0,

        const Self = @This();

        pub fn assignSlice(self: *Self, s: []const u8) error{OutOfMemory}!void {
            if (s.len > size) return error.OutOfMemory;

            std.mem.copyForwards(u8, &self.buffer, s);
            self.len = @intCast(s.len);
        }

        pub fn constSlice(self: *const Self) []const u8 {
            return self.buffer[0..self.len];
        }

        pub fn slice(self: *Self) []u8 {
            return self.buffer[0..self.len];
        }
    };
}

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
