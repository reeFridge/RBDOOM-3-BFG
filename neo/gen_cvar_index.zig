const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const output_file_path = "static_cvars.zig";
const include_mark = "//! @exportCVars";

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const path = "ztech";
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var dir_walker = try dir.walk(arena);
    defer dir_walker.deinit();

    var output_file = try dir.createFile(output_file_path, .{});
    defer output_file.close();

    var bw = std.io.bufferedWriter(output_file.writer());
    const output_writer = bw.writer();

    try output_writer.print("// WARN: File is generated, do not edit manually!\n", .{});
    try output_writer.print("pub const root = .{{\n", .{});

    while (try dir_walker.next()) |entry| {
        if (entry.kind == .directory) continue;
        if (std.mem.eql(u8, entry.basename, output_file_path)) continue;

        const ext = std.fs.path.extension(entry.basename);
        if (!std.mem.eql(u8, ext, ".zig")) continue;

        const contents = try dir.readFileAllocOptions(
            arena,
            entry.path,
            1000 * 1024,
            0,
            1,
            0,
        );

        var ast = try std.zig.Ast.parse(arena, contents, .zig);
        defer ast.deinit(arena);

        const token_tags = ast.tokens.items(.tag);
        const tokens = ast.tokens.items(.start);

        for (tokens, 0..) |_, i| {
            const tag = token_tags[i];
            if (tag != .container_doc_comment) continue;
            const token_text = ast.tokenSlice(@intCast(i));

            if (std.mem.eql(u8, token_text, include_mark)) {
                try output_writer.print("@import(\"{s}\"),\n", .{entry.path});
                break;
            }
        }
    }

    try output_writer.print("}};\n", .{});
    try bw.flush();
}
