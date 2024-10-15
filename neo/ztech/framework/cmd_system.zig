const std = @import("std");
const idlib = @import("../idlib.zig");

pub const CallbackFn = fn () void;

pub const CmdArgs = extern struct {
    pub const MAX_COMMAND_ARGS: usize = 64;
    pub const MAX_STRING_CHARS: usize = 1024;
    pub const MAX_COMMAND_STRING: usize = MAX_STRING_CHARS * 2;

    argc: c_int,
    argv: [MAX_COMMAND_ARGS][*:0]u8, // points into tokenized
    tokenized: [MAX_COMMAND_STRING]u8,
    // WARN: @sizeOf([max:0]u8) != @sizeOf([max]u8)

    pub fn appendArg(cmd_args: *CmdArgs, text: [:0]const u8) void {
        if (cmd_args.argc >= MAX_COMMAND_ARGS) return;

        const argc: usize = @intCast(cmd_args.argc);

        cmd_args.argv[argc] = if (cmd_args.argc == 0)
            // point at the start
            @ptrCast(&cmd_args.tokenized)
        else
            // point at the (end + \0) of previous arg
            cmd_args.argv[argc - 1] + std.mem.len(cmd_args.argv[argc - 1]) + 1;

        std.mem.copyForwards(u8, cmd_args.argv[argc][0..text.len :0], text);
        cmd_args.argc += 1;
    }
};

pub const ArgCompletionFn = fn (
    *CmdArgs,
    *const CallbackFn,
    [*:0]const u8,
) callconv(.C) void;
pub const CmdFn = fn (*CmdArgs) void;

pub const CommandDef = extern struct {
    next: ?*CommandDef,
    name: ?[*:0]u8,
    function: *const CmdFn,
    argCompletion: *const ArgCompletionFn,
    flags: c_int,
    description: ?[*:0]u8,
};

pub const CmdSystem = extern struct {
    pub const MAX_CMD_BUFFER: usize = 0x10000;

    commands: ?[*]CommandDef,
    wait: c_int,
    textLength: c_int,
    textBuf: [MAX_CMD_BUFFER]u8,
    completionString: idlib.idStr,
    completionParms: idlib.idStrList,
    tokenizedCmds: idlib.idList(CmdArgs),
    postReload: CmdArgs,
};

pub const instance = @extern(*CmdSystem, .{ .name = "cmdSystemLocal" });
