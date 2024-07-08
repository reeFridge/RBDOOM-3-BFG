const std = @import("std");

pub const Package = struct {
    shader_make_blob: *std.Build.Step.Compile,
    shader_make: *std.Build.Step.Compile,

    pub fn link(pkg: Package, exe: *std.Build.Step.Compile) void {
        exe.linkLibrary(pkg.shader_make_blob);
    }
};

pub fn package(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
) !Package {
    const shader_make_blob = b.addStaticLibrary(.{
        .name = "ShaderMakeBlob",
        .target = target,
        .optimize = optimize,
    });

    const blob_src = [_][]const u8{thisDir() ++ "/src/ShaderBlob.cpp"};

    const flags = [_][]const u8{"-fno-sanitize=undefined"};
    const cxxflags = flags ++ [_][]const u8{
        "-std=c++17",
    };

    shader_make_blob.addIncludePath(b.path(thisDir() ++ "/include"));
    shader_make_blob.addCSourceFiles(.{ .files = &blob_src, .flags = &cxxflags });

    shader_make_blob.linkLibC();
    shader_make_blob.linkLibCpp();

    const shader_make = b.addExecutable(.{ .name = "ShaderMake", .target = target, .optimize = optimize });

    const src_cpp = [_][]const u8{
        thisDir() ++ "/src/ShaderMake.cpp",
    };
    const src_c = [_][]const u8{
        thisDir() ++ "/src/argparse.c",
    };

    shader_make.addIncludePath(b.path(thisDir() ++ "/include"));
    shader_make.addIncludePath(b.path(thisDir() ++ "/src"));
    shader_make.addCSourceFiles(.{ .files = &src_c, .flags = &flags });
    shader_make.addCSourceFiles(.{ .files = &src_cpp, .flags = &cxxflags });

    shader_make.linkLibC();
    shader_make.linkLibCpp();
    shader_make.linkLibrary(shader_make_blob);

    return .{ .shader_make_blob = shader_make_blob, .shader_make = shader_make };
}

inline fn thisDir() []const u8 {
    return "extern/ShaderMake";
}
