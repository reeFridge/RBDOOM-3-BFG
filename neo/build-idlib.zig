const std = @import("std");
const butils = @import("./build-utils.zig");

pub const Package = struct {
    idlib: *std.Build.Step.Compile,

    pub fn link(pkg: Package, exe: *std.Build.Step.Compile) void {
        exe.linkLibrary(pkg.idlib);
    }
};

pub fn package(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.Mode,
) !Package {
    const idlib = b.addStaticLibrary(.{
        .name = "idlib",
        .target = target,
        .optimize = optimize,
    });

    idlib.root_module.addCMacro("RAPIDJSON_HAS_CXX11_RVALUE_REFS", "1");
    idlib.root_module.addCMacro("__IDLIB__", "");
    idlib.root_module.addCMacro("__DOOM_DLL__", "");
    idlib.root_module.addCMacro("USE_NVRHI", "1");

    const flags = [_][]const u8{"-fno-sanitize=undefined"};

    const cxxflags = flags ++ [_][]const u8{
        "-std=c++17",
    };

    var all_sources = std.ArrayList([]const u8).init(b.allocator);
    const exts = [_][]const u8{".cpp"};
    try butils.addFilesWithExts(b, &all_sources, thisDir(), &exts);
    try butils.addFilesWithExts(b, &all_sources, thisDir() ++ "/bv", &exts);
    try butils.addFilesWithExts(b, &all_sources, thisDir() ++ "/containers", &exts);
    try butils.addFilesWithExts(b, &all_sources, thisDir() ++ "/geometry", &exts);
    try butils.addFilesWithExts(b, &all_sources, thisDir() ++ "/hashing", &exts);
    try butils.addFilesWithExts(b, &all_sources, thisDir() ++ "/math", &exts);
    try butils.addFilesWithExts(b, &all_sources, thisDir() ++ "/sys", &exts);
    try butils.addFilesWithExts(b, &all_sources, thisDir() ++ "/sys/posix", &exts);

    idlib.addCSourceFiles(.{ .files = all_sources.items, .flags = &cxxflags });
    idlib.addIncludePath(b.path(thisDir()));
    idlib.addIncludePath(b.path(thisDir() ++ "/../extern/nvrhi/include"));
    idlib.addIncludePath(b.path(thisDir() ++ "/../libs/rapidjson/include"));

    idlib.linkLibC();
    idlib.linkLibCpp();

    return .{
        .idlib = idlib,
    };
}

inline fn thisDir() []const u8 {
    return "idlib";
}
