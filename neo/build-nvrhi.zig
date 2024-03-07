const std = @import("std");

pub const Package = struct {
    nvrhi_vk: *std.Build.Step.Compile,

    pub fn link(pkg: Package, exe: *std.Build.Step.Compile) void {
        exe.linkLibrary(pkg.nvrhi_vk);
    }
};

pub fn package(
    b: *std.Build,
    target: std.zig.CrossTarget,
    optimize: std.builtin.Mode,
) !Package {
    const nvrhi = b.addStaticLibrary(.{
        .name = "nvrhi",
        .target = target,
        .optimize = optimize,
    });

    const cxxflags = [_][]const u8{
        "-std=c++17",
    };
    // NVRHI_WITH_VALIDATION
    // NVRHI_WITH_VULKAN
    // TODO: add_subdirectory(thirdparty/Vulkan-Headers)
    nvrhi.addIncludePath(.{ .path = thisDir() ++ "/include" });

    const src_common = [_][]const u8{
        thisDir() ++ "/src/common/format-info.cpp",
        thisDir() ++ "/src/common/misc.cpp",
        thisDir() ++ "/src/common/state-tracking.cpp",
        thisDir() ++ "/src/common/utils.cpp",
    };

    const src_validation = [_][]const u8{
        thisDir() ++ "/src/validation/validation-commandlist.cpp",
        thisDir() ++ "/src/validation/validation-device.cpp",
        thisDir() ++ "/src/common/sparse-bitset.cpp",
    };

    const src_vk = [_][]const u8{
        thisDir() ++ "/src/vulkan/vulkan-allocator.cpp",
        thisDir() ++ "/src/vulkan/vulkan-buffer.cpp",
        thisDir() ++ "/src/vulkan/vulkan-commandlist.cpp",
        thisDir() ++ "/src/vulkan/vulkan-compute.cpp",
        thisDir() ++ "/src/vulkan/vulkan-constants.cpp",
        thisDir() ++ "/src/vulkan/vulkan-device.cpp",
        thisDir() ++ "/src/vulkan/vulkan-graphics.cpp",
        thisDir() ++ "/src/vulkan/vulkan-meshlets.cpp",
        thisDir() ++ "/src/vulkan/vulkan-queries.cpp",
        thisDir() ++ "/src/vulkan/vulkan-queue.cpp",
        thisDir() ++ "/src/vulkan/vulkan-raytracing.cpp",
        thisDir() ++ "/src/vulkan/vulkan-resource-bindings.cpp",
        thisDir() ++ "/src/vulkan/vulkan-shader.cpp",
        thisDir() ++ "/src/vulkan/vulkan-staging-texture.cpp",
        thisDir() ++ "/src/vulkan/vulkan-state-tracking.cpp",
        thisDir() ++ "/src/vulkan/vulkan-texture.cpp",
        thisDir() ++ "/src/vulkan/vulkan-upload.cpp",
    };

    nvrhi.addCSourceFiles(&src_common, &cxxflags);
    nvrhi.addCSourceFiles(&src_validation, &cxxflags);
    nvrhi.addCSourceFiles(&src_vk, &cxxflags);

    nvrhi.linkLibC();
    nvrhi.linkLibCpp();

    return .{ .nvrhi_vk = nvrhi };
}

inline fn thisDir() []const u8 {
    return comptime (std.fs.path.dirname(@src().file) orelse ".") ++ "/extern/nvrhi";
}
