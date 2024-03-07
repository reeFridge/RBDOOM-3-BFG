const std = @import("std");

pub const Package = struct {
    shader_make_blob: *std.Build.Step.Compile,

    pub fn link(pkg: Package, exe: *std.Build.Step.Compile) void {
        exe.linkLibrary(pkg.shader_make_blob);
    }
};

pub fn package(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
) !Package {
    const shader_make_blob = b.addStaticLibrary(.{
        .name = "ShaderMakeBlob",
        .target = target,
        .optimize = optimize,
    });

    const src = [_][]const u8{thisDir() ++ "/src/ShaderBlob.cpp"};

    const flags = [_][]const u8{"-fno-sanitize=undefined"};
    const cxxflags = flags ++ [_][]const u8{
        "-std=c++17",
    };

    shader_make_blob.addIncludePath(.{ .path = thisDir() ++ "/include" });
    shader_make_blob.addCSourceFiles(&src, &cxxflags);

    shader_make_blob.linkLibC();
    shader_make_blob.linkLibCpp();

    return .{ .shader_make_blob = shader_make_blob };
}

inline fn thisDir() []const u8 {
    return comptime (std.fs.path.dirname(@src().file) orelse ".") ++ "/extern/ShaderMake";
}
