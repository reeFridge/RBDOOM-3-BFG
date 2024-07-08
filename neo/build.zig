const std = @import("std");
const builtin = @import("builtin");

const idlib_mod = @import("./build-idlib.zig");
const nvrhi_mod = @import("./build-nvrhi.zig");
const shader_make_mod = @import("./build-shadermake.zig");
const butils = @import("./build-utils.zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const nvrhi_pkg = try nvrhi_mod.package(b, target, optimize);
    const idlib_pkg = try idlib_mod.package(b, target, optimize);
    const shader_make_pkg = try shader_make_mod.package(b, target, optimize);

    const exe = b.addExecutable(.{ .name = "rbdoom3bfg", .target = target, .optimize = optimize });

    exe.defineCMacro("USE_NVRHI", null);
    exe.defineCMacro("USE_AMD_ALLOCATOR", null);
    exe.defineCMacro("VULKAN_USE_PLATFORM_SDL", null);
    exe.defineCMacro("USE_VK", null);
    exe.defineCMacro("USE_BINKDEC", null);
    exe.defineCMacro("USE_OPENAL", null);
    exe.defineCMacro("__DOOM__", null);

    exe.addIncludePath(b.path("extern/nvrhi/include"));
    exe.addIncludePath(b.path("extern/ShaderMake/include"));
    exe.addIncludePath(b.path("idlib"));
    exe.addIncludePath(b.path("libs/stb"));
    exe.addIncludePath(b.path("libs/mikktspace"));
    exe.addIncludePath(b.path("libs/zlib"));
    exe.addIncludePath(b.path("libs/rapidjson/include"));
    exe.addIncludePath(b.path("libs/imgui"));
    exe.addIncludePath(b.path("libs/optick"));
    exe.addIncludePath(b.path("libs/vma/include"));
    exe.addIncludePath(b.path("libs/libbinkdec/include"));
    exe.addIncludePath(b.path("./"));

    // TODO: find_package(Vulkan OPTIONAL_COMPONENTS ${Vulkan_COMPONENTS})
    // include_directories(${Vulkan_INCLUDE_DIRS})

    const exts_cpp = [_][]const u8{".cpp"};
    const exts_c = [_][]const u8{".c"};

    var exe_src_cpp = std.ArrayList([]const u8).init(b.allocator);
    var exe_src_c = std.ArrayList([]const u8).init(b.allocator);
    //${AAS_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "aas", &exts_cpp);
    //${CM_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "cm", &exts_cpp);
    //${FRAMEWORK_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "framework", &exts_cpp);
    //${RENDERER_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "renderer", &exts_cpp);
    //${RENDERER_COLOR_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "renderer/Color", &exts_cpp);
    //${RENDERER_DXT_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "renderer/DXT", &exts_cpp);
    //${RENDERER_PASSES_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "renderer/Passes", &exts_cpp);
    //${IRRXML_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "libs/irrxml/src", &exts_cpp);
    //${FRAMEWORK_IMGUI_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "imgui", &exts_cpp);
    //${IMGUI_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "libs/imgui", &exts_cpp);
    //${MIKKTSPACE_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_c, "libs/mikktspace", &exts_c);
    //${ZLIB_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_c, "libs/zlib", &exts_c);
    //${MINIZIP_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "libs/zlib/minizip", &exts_cpp);
    try butils.addFilesWithExts(b, &exe_src_c, "libs/zlib/minizip", &exts_c);
    //${BINKDEC_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "libs/libbinkdec/src", &exts_cpp);
    try butils.addFilesWithExts(b, &exe_src_c, "libs/libbinkdec/src", &exts_c);
    //${SOUND_SOURCES}
    try exe_src_cpp.appendSlice(&.{
        "sound/snd_decoder.cpp",
        "sound/snd_emitter.cpp",
        "sound/snd_shader.cpp",
        "sound/snd_system.cpp",
        "sound/snd_world.cpp",
        "sound/SoundVoice.cpp",
        "sound/WaveFile.cpp",
    });
    //${OGGVORBIS_SOURCES}
    try exe_src_c.appendSlice(&.{
        "libs/oggvorbis/oggsrc/bitwise.c",
        "libs/oggvorbis/oggsrc/framing.c",
        "libs/oggvorbis/vorbissrc/mdct.c",
        "libs/oggvorbis/vorbissrc/smallft.c",
        "libs/oggvorbis/vorbissrc/block.c",
        "libs/oggvorbis/vorbissrc/envelope.c",
        "libs/oggvorbis/vorbissrc/windowvb.c",
        "libs/oggvorbis/vorbissrc/lsp.c",
        "libs/oggvorbis/vorbissrc/lpc.c",
        "libs/oggvorbis/vorbissrc/analysis.c",
        "libs/oggvorbis/vorbissrc/synthesis.c",
        "libs/oggvorbis/vorbissrc/psy.c",
        "libs/oggvorbis/vorbissrc/info.c",
        "libs/oggvorbis/vorbissrc/floor1.c",
        "libs/oggvorbis/vorbissrc/floor0.c",
        "libs/oggvorbis/vorbissrc/res0.c",
        "libs/oggvorbis/vorbissrc/mapping0.c",
        "libs/oggvorbis/vorbissrc/registry.c",
        "libs/oggvorbis/vorbissrc/codebook.c",
        "libs/oggvorbis/vorbissrc/sharedbook.c",
        "libs/oggvorbis/vorbissrc/lookup.c",
        "libs/oggvorbis/vorbissrc/bitrate.c",
        "libs/oggvorbis/vorbissrc/vorbisfile.c",
    });
    //${OPTICK_SOURCES}
    //${UI_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "ui", &exts_cpp);
    //${SWF_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "swf", &exts_cpp);
    //${COMMON_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "sys/common", &exts_cpp);
    //${COMPILER_AAS_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "tools/compilers/aas", &exts_cpp);
    //${COMPILER_DMAP_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "tools/compilers/dmap", &exts_cpp);
    //${IMGUI_EDITOR_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "tools/imgui", &exts_cpp);
    //${IMGUI_EDITOR_LIGHT_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "tools/imgui/lighteditor", &exts_cpp);
    //${IMGUI_EDITOR_UTIL_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "tools/imgui/util", &exts_cpp);
    //${GAMED3XP_SOURCES}
    try exe_src_cpp.appendSlice(&.{
        "d3xp/Achievements.cpp",
        "d3xp/Actor.cpp",
        "d3xp/AF.cpp",
        "d3xp/AFEntity.cpp",
        "d3xp/AimAssist.cpp",
        "d3xp/BrittleFracture.cpp",
        "d3xp/Camera.cpp",
        "d3xp/Entity.cpp",
        "d3xp/EnvironmentProbe.cpp",
        "d3xp/Fx.cpp",
        "d3xp/GameEdit.cpp",
        "d3xp/Game_local.cpp",
        "d3xp/Game_network.cpp",
        "d3xp/Grabber.cpp",
        "d3xp/IK.cpp",
        "d3xp/Item.cpp",
        "d3xp/Leaderboards.cpp",
        "d3xp/Light.cpp",
        "d3xp/Misc.cpp",
        "d3xp/Moveable.cpp",
        "d3xp/Mover.cpp",
        "d3xp/MultiplayerGame.cpp",
        "d3xp/Player.cpp",
        "d3xp/PlayerIcon.cpp",
        "d3xp/PlayerView.cpp",
        "d3xp/precompiled.cpp",
        "d3xp/Projectile.cpp",
        "d3xp/Pvs.cpp",
        "d3xp/SecurityCamera.cpp",
        "d3xp/SmokeParticles.cpp",
        "d3xp/Sound.cpp",
        "d3xp/Target.cpp",
        "d3xp/Trigger.cpp",
        "d3xp/Weapon.cpp",
        "d3xp/WorldSpawn.cpp",
    });
    //${GAMED3XP_AI_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "d3xp/ai", &exts_cpp);
    //${GAMED3XP_ANIM_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "d3xp/anim", &exts_cpp);
    //${GAMED3XP_GAMESYS_SOURCES}
    try exe_src_cpp.appendSlice(&.{
        "d3xp/gamesys/Class.cpp",
        "d3xp/gamesys/Event.cpp",
        "d3xp/gamesys/SaveGame.cpp",
        "d3xp/gamesys/SysCmds.cpp",
        "d3xp/gamesys/SysCvar.cpp",
    });
    //${GAMED3XP_MENUS_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "d3xp/menus", &exts_cpp);
    //${GAMED3XP_PHYSICS_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "d3xp/physics", &exts_cpp);
    //${GAMED3XP_SCRIPT_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "d3xp/script", &exts_cpp);
    //${POSIX_SOURCES}
    try exe_src_cpp.appendSlice(&.{
        "sys/posix/platform_linux.cpp",
        "sys/posix/posix_main.cpp",
        "sys/posix/posix_signal.cpp",
    });
    //${SDL_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "sys/sdl", &exts_cpp);
    //${SYS_SOURCES}
    try exe_src_cpp.appendSlice(&.{
        "sys/DeviceManager.cpp",
        "sys/DeviceManager_VK.cpp",
        "sys/LightweightCompression.cpp",
        "sys/PacketProcessor.cpp",
        "sys/Snapshot.cpp",
        "sys/SnapshotProcessor.cpp",
        "sys/Snapshot_Jobs.cpp",
        "sys/sys_achievements.cpp",
        "sys/sys_dedicated_server_search.cpp",
        "sys/sys_lobby.cpp",
        "sys/sys_lobby_backend_direct.cpp",
        "sys/sys_lobby_migrate.cpp",
        "sys/sys_lobby_snapshot.cpp",
        "sys/sys_lobby_users.cpp",
        "sys/sys_local.cpp",
        "sys/sys_localuser.cpp",
        "sys/sys_profile.cpp",
        "sys/sys_savegame.cpp",
        "sys/sys_session_callbacks.cpp",
        "sys/sys_session_local.cpp",
        "sys/sys_session_savegames.cpp",
        "sys/sys_signin.cpp",
        "sys/sys_voicechat.cpp",
    });
    //${RENDERER_NVRHI_SOURCES}
    try butils.addFilesWithExts(b, &exe_src_cpp, "renderer/NVRHI", &exts_cpp);
    // afeditor
    try butils.addFilesWithExts(b, &exe_src_cpp, "tools/imgui/afeditor", &exts_cpp);
    //${OPENAL_SOURCES}
    try exe_src_cpp.appendSlice(&.{
        "sound/OpenAL/AL_SoundHardware.cpp",
        "sound/OpenAL/AL_SoundSample.cpp",
        "sound/OpenAL/AL_SoundVoice.cpp",
        "sound/OpenAL/AL_CinematicAudio.cpp",
    });

    const flags = [_][]const u8{"-fno-sanitize=undefined"};

    const cflags = flags ++ [_][]const u8{};

    const cxxflags = flags ++ [_][]const u8{ "-std=c++17", "-Wno-inconsistent-missing-override" };

    exe.addCSourceFiles(.{ .files = exe_src_cpp.items, .flags = &cxxflags });
    exe.addCSourceFiles(.{ .files = exe_src_c.items, .flags = &cflags });

    const ztech_lib = b.addStaticLibrary(.{
        .name = "libztech",
        .root_source_file = b.path("ztech/lib.zig"),
        .optimize = optimize,
        .target = target,
    });
    ztech_lib.linkLibC();

    shader_make_pkg.link(exe);
    nvrhi_pkg.link(exe);
    idlib_pkg.link(exe);
    exe.linkLibrary(ztech_lib);

    exe.linkSystemLibrary("sdl2");
    exe.linkSystemLibrary("vulkan");
    exe.linkSystemLibrary("openal");
    exe.linkLibC();
    exe.linkLibCpp();

    b.installArtifact(exe);

    const shaders_cmd = b.addRunArtifact(shader_make_pkg.shader_make);
    shaders_cmd.addArg("--config=shaders/shaders.cfg");
    shaders_cmd.addArg("--out=../base/renderprogs2/spirv");
    shaders_cmd.addArg("--platform=SPIRV");
    shaders_cmd.addArg("--binaryBlob");
    shaders_cmd.addArg("--outputExt=.bin");
    // ! means config_parent_dir + ./
    shaders_cmd.addArg("-I./");
    shaders_cmd.addArg("-DSPIRV");

    // CFLAGS
    shaders_cmd.addArgs(&.{
        "--vulkanVersion=1.2",
        "--shaderModel=6_0",
        "-O3",
        "--WX",
        "--matrixRowMajor",
        "--tRegShift=0",
        "--sRegShift=128",
        "--bRegShift=256",
        "--uRegShift=384",
    });

    // TODO: locate dxc executable
    // or provide a 'compiler' option for shaders step
    shaders_cmd.addArg("--compiler=/home/fridge/thirdparty/bin/dxc");

    const compile_shaders_step = b.step("shaders", "Compile SPIRV shaders");
    compile_shaders_step.dependOn(&shaders_cmd.step);
}
