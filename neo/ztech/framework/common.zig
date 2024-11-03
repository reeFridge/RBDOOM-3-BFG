const std = @import("std");
const cmd = @import("cmd_system.zig");
const cvar = @import("cvar_system.zig");
const fs = @import("file_system.zig");
const key_input = @import("key_input.zig");
const console = @import("console.zig");
const network = @import("../sys/network.zig");
const localization = @import("../sys/localization.zig");
const decl_manager = @import("decl_manager.zig");
const event_loop = @import("event_loop.zig");
const parallel_job_manager = @import("../renderer/parallel_job_manager.zig");

pub const Common = opaque {
    extern fn c_common_getRendererGPUMicroseconds(*const Common) callconv(.C) u64;
    extern fn c_common_quit(*Common) void;
    extern fn c_common_frame(*Common) void;
    extern fn c_common_init(
        *Common,
        c_uint,
        ?[*]const [*:0]const u8,
    ) void;

    pub fn frame(common: *Common) void {
        c_common_frame(common);
    }

    pub fn init(_: *Common, allocator: std.mem.Allocator) !void {
        try cmd.instance.init();
        cvar.instance.init();
        try key_input.init(allocator);
        console.instance.init();
        // TODO try system.init(); // WINDOWS ONLY!
        try network.init();
        // TODO try common.initSIMD(); // wait for SIMD support
        try fs.instance.init();
        try localization.setDefaultLang();
        try decl_manager.instance.init();
        try event_loop.instance.init();
        try parallel_job_manager.instance.init();
        cmd.instance.bufferCommandText(.CMD_EXEC_APPEND, "exec default.cfg\n");
        cmd.instance.bufferCommandText(.CMD_EXEC_APPEND, "exec autoexec.cfg\n");
        // TODO cmd.instance.executeCommandBuffer();
        // TODO cmd.instance.clearModifiedFlags(.CVAR_ARCHIVE);
        // TODO render_system.instance.initBackend();
        // TODO sound_system.instance.init();
        // TODO render_system.instance.init();
        // TODO image_manager.instance.loadDeferredImages();
        // TODO decl_manager.instance.init2();
        // TODO common.initLanguageDict();
        // TODO gameThread.startWorkerThread("Game/Draw");
        // TODO usercmd_gen.instance.init();
        // TODO system.setRumble(0, 0, 0);
        // TODO ui_manager.instance.init();
        // TODO common.initCommands();
        // TODO game.instance.init();
        // TODO fs.instance.unloadResourceContainer("_ordered");
        // TODO common.render_world = render_system.instance.allocRenderWorld();
        // TODO common.sound_world = sound_system.instance.allocSoundWorld();
        // TODO common.menu_sound_world = sound_system.instance.allocSoundWorld();
        // TODO common.menu_sound_world.placeListener(Vec3.origin, Mat3.identity, 0);
        // TODO session.instance.init();
        // TODO session.instance.initSoundRelatedSystems();
        // TODO common.createMainMenu();
        // TODO common.commonDialog.init();
        // TODO common.addStartupCommands();
        // TODO common.startMenu(true);
        // TODO common.printWarnings();
        // TODO console.instance.clearNotifyLines();
        // TODO common.checkStartupStorageRequirements();
        // TODO common.com_fullyInitialized = true;
        // TODO image_manager.instance.loadDeferredImages();

        // COMPLETE!

        try cvar.setCVarsFromArgs(null);
        //c_common_init(common, 0, null);
    }

    pub fn initWithArgs(common: *Common, args: []const [*:0]const u8) void {
        c_common_init(common, @intCast(args.len), @ptrCast(args));
    }

    pub fn getRendererGPUMicroseconds(common: *const Common) u64 {
        return c_common_getRendererGPUMicroseconds(common);
    }

    pub fn quit(common: *Common) void {
        c_common_quit(common);
    }

    pub fn parseCommandLine(args: [][:0]const u8) void {
        num_console_lines.* = 0;

        for (args) |arg_str| {
            // + symbol declares new console line
            if (arg_str[0] == '+') {
                num_console_lines.* += 1;
                const num: usize = @intCast(num_console_lines.*);
                console_lines[num - 1].appendArg(arg_str[1..]);
            } else {
                if (num_console_lines.* == 0) {
                    num_console_lines.* += 1;
                }
                const num: usize = @intCast(num_console_lines.*);
                console_lines[num - 1].appendArg(arg_str);
            }
        }

        // debug
        {
            const num = num_console_lines;
            const lines = console_lines;
            std.debug.print("Command-line arguments:\n", .{});
            for (0..@intCast(num.*)) |i| {
                std.debug.print("[{}]", .{i});
                for (lines[i].argv[0..@intCast(lines[i].argc)]) |str| {
                    std.debug.print(" {s}", .{str});
                }
                std.debug.print("\n", .{});
            }
        }
    }
};

pub const instance = @extern(*Common, .{ .name = "commonLocal" });

pub const MAX_CONSOLE_LINES = 32;
pub const num_console_lines = @extern(*c_int, .{ .name = "com_numConsoleLines" });
pub const console_lines = @extern(*[MAX_CONSOLE_LINES]cmd.CmdArgs, .{ .name = "com_consoleLines" });
