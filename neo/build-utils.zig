const std = @import("std");

pub fn addFilesWithExts(
    b: *std.Build,
    array: *std.ArrayList([]const u8),
    path: []const u8,
    allowed_exts: []const []const u8,
) !void {
    var dir = try std.fs.cwd().openIterableDir(path, .{});
    var dir_iterator = dir.iterate();

    while (try dir_iterator.next()) |entry| {
        if (entry.kind == .directory) continue;

        const ext = std.fs.path.extension(entry.name);

        const include_file = for (allowed_exts) |e| {
            if (std.mem.eql(u8, ext, e))
                break true;
        } else false;

        if (!include_file) continue;

        const full_path = try std.fmt.allocPrint(
            b.allocator,
            "{s}/{s}",
            .{ path, entry.name },
        );

        try array.append(full_path);
    }
}
