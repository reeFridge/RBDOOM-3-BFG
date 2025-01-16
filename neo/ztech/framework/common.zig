const std = @import("std");
const cmd = @import("cmd_system.zig");
const cvar = @import("cvar_system.zig");
const fs = @import("file_system.zig");
const key_input = @import("key_input.zig");
const console = @import("console.zig");
const network = @import("../sys/network.zig");
const localization = @import("../sys/localization.zig");
const decl_manager = @import("decl_manager.zig");
const DeclManager = decl_manager.DeclManager;
const event_loop = @import("event_loop.zig");
const parallel_job_manager = @import("../renderer/parallel_job_manager.zig");
const RenderSystem = @import("../renderer/render_system.zig");
const sound_system = @import("../sound/sound_system.zig");
const Vec4 = @import("../math/vector.zig").Vec4;
const Material = @import("../renderer/material.zig").Material;
const Allocator = std.mem.Allocator;
const RenderBackend = @import("../renderer/render_backend.zig").RenderBackend;
const thread = @import("thread.zig");
const user_cmd = @import("user_cmd.zig");
const ui_manager = @import("../ui/manager.zig");
const getMilliseconds = @import("../main.zig").Sys_Milliseconds;
const frameToMsec = @import("../game.zig").frameToMsec;

fn runGameFrameAndDraw(self: *thread.Thread) u8 {
    if (self.allocator) |allocator| {
        console.instance.draw(allocator) catch return 1;
    }

    return 0;
}

var opt_last_frame_time: ?c_int = null;

pub var game_thread: thread.Thread = .{ .payload_fn = runGameFrameAndDraw };
var game_time_residual: f64 = 0;
var sync_next_frame: bool = true;
var game_frame: u64 = 0;
var no_sleep: bool = false;

pub const Common = opaque {
    extern fn c_common_getRendererGPUMicroseconds(*const Common) callconv(.C) u64;
    extern fn c_common_quit(*Common) void;
    extern fn c_common_frame(*Common) void;
    extern fn c_common_init(
        *Common,
        c_uint,
        ?[*]const [*:0]const u8,
    ) void;

    pub fn frame(_: *Common, allocator: Allocator) !void {
        const render_commands = try RenderSystem.instance.swapCommandBuffers(allocator);

        // how many frames to run
        var num_frames: u32 = 0;

        while (true) {
            const this_frame_time = getMilliseconds();
            const last_frame_time = opt_last_frame_time orelse this_frame_time;

            const delta_ms = this_frame_time - last_frame_time;
            opt_last_frame_time = this_frame_time;

            const delta_time_clamp = 50;
            const clamped_delta_ms = @min(delta_ms, delta_time_clamp);
            const time_scale: f32 = 1;
            game_time_residual += @as(f32, @floatFromInt(clamped_delta_ms)) * time_scale;

            if (sync_next_frame) {
                sync_next_frame = false;
                game_frame += 1;
                num_frames += 1;
                game_time_residual = 0;
                break;
            }

            while (true) {
                const frame_delay: u32 = @intCast(frameToMsec(game_frame + 1) - frameToMsec(game_frame));
                const frame_delay_float = @as(f32, @floatFromInt(frame_delay));
                if (game_time_residual < frame_delay_float) break;
                game_time_residual -= frame_delay_float;
                game_frame += 1;
                num_frames += 1;
            }

            if (num_frames > 0) break;

            if (no_sleep) {
                num_frames = 1;
                game_frame += num_frames;
                game_time_residual = 0;
                break;
            }

            std.time.sleep(0);
        }

        game_thread.signalWork();

        try RenderSystem.instance.renderCommandBuffers(render_commands, allocator);

        game_thread.wait();
    }

    pub fn init(_: *Common, allocator: Allocator) !void {
        try cmd.instance.init(allocator);
        try cvar.instance.init(allocator);
        try key_input.init(allocator);
        console.instance.init();
        // TODO try system.init(); // WINDOWS ONLY!
        try network.init();
        // TODO try common.initSIMD(); // wait for SIMD support
        try fs.instance.init(allocator);
        try localization.setDefaultLang(allocator);
        try decl_manager.instance.init(allocator);
        try event_loop.instance.init(allocator);
        try parallel_job_manager.instance.init();
        try cmd.instance.bufferCommandText(.CMD_EXEC_APPEND, "exec default.cfg\n");
        try cmd.instance.bufferCommandText(.CMD_EXEC_APPEND, "exec autoexec.cfg\n");
        try cmd.instance.executeCommandBuffer();
        cvar.instance.modifiedFlags &= ~cvar.CVarFlags.CVAR_ARCHIVE;
        try RenderSystem.instance.initBackend(allocator);
        try sound_system.instance.init();
        try RenderSystem.instance.init(allocator);

        try renderSplash(
            &RenderSystem.instance,
            decl_manager.instance,
            allocator,
        );

        try decl_manager.instance.postInit(allocator);

        // TODO common.initLanguageDict();

        // prepare but not run now until .frame()
        game_thread.allocator = allocator;
        _ = game_thread.spawnWorker("game_frame/draw", 0x100000);

        user_cmd.generator_instance.init();

        // TODO system.setRumble(0, 0, 0);

        try ui_manager.instance.init(
            &RenderSystem.instance,
            decl_manager.instance,
            allocator,
        );

        // TODO common.initCommands(); // tools
        //
        // TODO ! game.instance.init();
        // TODO ! fs.instance.unloadResourceContainer("_ordered");
        // TODO ! common.render_world = render_system.instance.allocRenderWorld();

        // TODO common.sound_world = sound_system.instance.allocSoundWorld();
        // TODO common.menu_sound_world = sound_system.instance.allocSoundWorld();
        // TODO common.menu_sound_world.placeListener(Vec3.origin, Mat3.identity, 0);

        // TODO ! session.instance.init();

        // TODO session.instance.initSoundRelatedSystems();

        // TODO ! common.createMainMenu();
        // TODO ! common.commonDialog.init();

        // TODO common.addStartupCommands();

        // TODO ! common.startMenu(true);

        // TODO common.printWarnings();
        // TODO console.instance.clearNotifyLines();

        // TODO ! common.checkStartupStorageRequirements();

        // TODO common.com_fullyInitialized = true;

        // TODO ! image_manager.instance.loadDeferredImages();

        // COMPLETE!

        try cvar.setCVarsFromArgs(null, allocator);
    }

    const RenderError =
        RenderSystem.SwapCommandBuffersError ||
        DeclManager.FindDeclError ||
        RenderBackend.ExecuteCommandsError ||
        RenderBackend.SwapBuffersError;
    fn renderSplash(
        rs: *RenderSystem,
        decl_manager_inst: *DeclManager,
        allocator: Allocator,
    ) RenderError!void {
        const splash_screen: *Material = @ptrCast(try decl_manager_inst.findTypeOrDefault(
            .material,
            "guis/assets/splash/legal_english",
            allocator,
        ));
        const white_material: *Material = @ptrCast(try decl_manager_inst.findTypeOrDefault(
            .material,
            "_white",
            allocator,
        ));

        const width_f = @as(f32, @floatFromInt(rs.getWidth()));
        const height_f = @as(f32, @floatFromInt(rs.getHeight()));
        const virtual_width_f = @as(f32, @floatFromInt(rs.getVirtualWidth()));
        const virtual_height_f = @as(f32, @floatFromInt(rs.getVirtualHeight()));

        const sys_width: f32 = width_f * rs.getPixelAspect();
        const sys_height: f32 = height_f;
        const sys_aspect = sys_width / sys_height;
        const splash_aspect: f32 = 16.0 / 9.0;
        const adjustment: f32 = sys_aspect / splash_aspect;
        const bar_height = if (adjustment >= 1.0)
            0.0
        else
            (1.0 - adjustment) * virtual_height_f * 0.25;

        const bar_width = if (adjustment <= 1.0)
            0.0
        else
            (adjustment - 1.0) * virtual_width_f * 0.25;

        const color_black = Vec4(f32){ .v = .{ 0, 0, 0, 1 } };
        if (bar_height > 0.0) {
            rs.setColor(color_black);
            try rs.drawStretchPicture(
                .{
                    .x = 0,
                    .y = 0,
                    .w = virtual_width_f,
                    .h = bar_height,
                },
                white_material,
                allocator,
            );
            try rs.drawStretchPicture(
                .{
                    .x = 0,
                    .y = virtual_height_f - bar_height,
                    .w = virtual_width_f,
                    .h = bar_height,
                },
                white_material,
                allocator,
            );
        }

        if (bar_width > 0.0) {
            rs.setColor(color_black);
            try rs.drawStretchPicture(
                .{
                    .x = 0,
                    .y = 0,
                    .w = bar_width,
                    .h = virtual_height_f,
                },
                white_material,
                allocator,
            );
            try rs.drawStretchPicture(
                .{
                    .x = virtual_width_f - bar_width,
                    .y = 0,
                    .w = bar_width,
                    .h = virtual_height_f,
                },
                white_material,
                allocator,
            );
        }

        rs.setColor(.{ .v = .{ 1, 1, 1, 1 } });
        try rs.drawStretchPicture(
            .{
                .x = bar_width,
                .y = bar_height,
                .w = virtual_width_f - bar_width * 2.0,
                .h = virtual_height_f - bar_height * 2.0,
            },
            splash_screen,
            allocator,
        );

        try rs.renderCommandBuffers(
            try rs.swapCommandBuffers(allocator),
            allocator,
        );

        // TODO: why we need to call finishRendering to draw splash?
        try rs.finishRendering();
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
