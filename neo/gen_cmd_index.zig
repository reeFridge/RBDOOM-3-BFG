const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub fn main() !void {
    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const path = "ztech";
    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var dir_walker = try dir.walk(arena);
    defer dir_walker.deinit();

    const output_file_path = "static_cmds.zig";
    var output_file = try dir.createFile(output_file_path, .{});
    defer output_file.close();

    var bw = std.io.bufferedWriter(output_file.writer());
    const output_writer = bw.writer();

    try output_writer.print("// WARN: File is generated, do not edit manually!\n", .{});
    try output_writer.print("pub const root = .{{\n", .{});

    while (try dir_walker.next()) |entry| {
        if (entry.kind == .directory) continue;
        if (std.mem.eql(u8, entry.basename, "static_cmds.zig")) continue;

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

        const root = ast.containerDeclRoot();
        const node_tags = ast.nodes.items(.tag);

        for (root.ast.members) |member_node| {
            switch (node_tags[member_node]) {
                .simple_var_decl => {
                    const full = ast.fullVarDecl(member_node) orelse continue;
                    const visib_token = full.visib_token orelse continue;
                    const name_token = full.ast.mut_token + 1;
                    const mut_token = full.ast.mut_token;

                    const ident_name = ast.tokenSlice(name_token);
                    const mut_spec = ast.tokenSlice(mut_token);
                    const visib_spec = ast.tokenSlice(visib_token);

                    const is_pub = std.mem.eql(u8, "pub", visib_spec);
                    const is_const = std.mem.eql(u8, "const", mut_spec);

                    if (!is_pub or !is_const) continue;

                    const init_tag = node_tags[full.ast.init_node];
                    const is_anon_struct_init = init_tag == .struct_init_dot or init_tag == .struct_init_dot_comma;
                    const is_struct_init = init_tag == .struct_init or init_tag == .struct_init_comma;

                    if (!is_anon_struct_init and !is_struct_init) continue;
                    const type_expr = if (is_struct_init) type_expr: {
                        const struct_init = ast.structInit(full.ast.init_node);
                        break :type_expr struct_init.ast.type_expr;
                    } else full.ast.type_node;

                    const type_tag = node_tags[type_expr];
                    if (type_tag != .identifier) continue;

                    const type_name = ast.tokenSlice(ast.firstToken(type_expr));

                    if (!std.mem.eql(u8, "CmdDecl", type_name)) continue;

                    try output_writer.print("@import(\"{s}\").{s},\n", .{
                        entry.path,
                        ident_name,
                    });
                },
                else => continue,
            }
        }
    }

    try output_writer.print("}};\n", .{});
    try bw.flush();
}
