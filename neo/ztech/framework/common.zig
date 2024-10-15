const std = @import("std");
const cmd = @import("cmd_system.zig");

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

    pub fn init(common: *Common) void {
        c_common_init(common, 0, null);
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
