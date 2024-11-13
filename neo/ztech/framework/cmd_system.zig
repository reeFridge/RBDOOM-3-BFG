const std = @import("std");
const idlib = @import("../idlib.zig");
const global = @import("../global.zig");
const file_system = @import("file_system.zig");
const lexer_ = @import("../lexer.zig");
const Lexer = lexer_.Lexer;
const LexerFlags = lexer_.Flags;
const token_ = @import("../token.zig");
const TokenType = token_.Type;
const Token = token_.Token;
const cvar_system = @import("cvar_system.zig");
const bit = @import("../math/math.zig").bit;

pub const CmdDecl = struct {
    name: []const u8,
    function: *const CmdFn,
    flags: c_int,
    description: []const u8,
    arg_completion: ?*const ArgCompletionFn,
};

pub const CallbackFn = fn () callconv(.C) void;

pub const CmdExecution = enum(c_int) {
    CMD_EXEC_NOW,
    CMD_EXEC_INSERT,
    CMD_EXEC_APPEND,
};

pub const CmdFlags = struct {
    pub const CMD_FL_ALL: c_int = -1;
    pub const CMD_FL_CHEAT: c_int = bit(0); // command is considered a cheat
    pub const CMD_FL_SYSTEM: c_int = bit(1); // system command
    pub const CMD_FL_RENDERER: c_int = bit(2); // renderer command
    pub const CMD_FL_SOUND: c_int = bit(3); // sound command
    pub const CMD_FL_GAME: c_int = bit(4); // game command
    pub const CMD_FL_TOOL: c_int = bit(5); // tool command
};

pub const CmdArgs = extern struct {
    pub const MAX_COMMAND_ARGS: usize = 64;
    pub const MAX_STRING_CHARS: usize = 1024;
    pub const MAX_COMMAND_STRING: usize = MAX_STRING_CHARS * 2;

    argc: c_int = 0,
    argv: [MAX_COMMAND_ARGS][*:0]u8 = undefined, // points into tokenized
    tokenized: [MAX_COMMAND_STRING]u8 = undefined,
    // WARN: @sizeOf([max:0]u8) != @sizeOf([max]u8)

    pub fn copy(args: *CmdArgs, other: *const CmdArgs) void {
        args.argc = other.argc;
        args.tokenized = other.tokenized;
        for (0..@intCast(args.argc)) |i| {
            const tok_addr = @intFromPtr(&args.tokenized);
            const other_tok_addr = @intFromPtr(&other.tokenized);
            const argv_addr = @intFromPtr(other.argv[i]);
            args.argv[i] = @ptrFromInt(tok_addr + (argv_addr - other_tok_addr));
        }
    }

    pub fn tokenizeString(args: *CmdArgs, text: []const u8) void {
        if (text.len == 0) return;

        const allocator = global.gpa.allocator();
        const text_sentinel = allocator.dupeZ(u8, text) catch unreachable;
        defer allocator.free(text_sentinel);

        const lexer = Lexer.initEmpty();
        defer lexer.deinit();

        if (!lexer.loadMemory(text_sentinel, "CmdArgs.fromText", 0)) return;

        lexer.flags = LexerFlags.LEXFL_NOERRORS |
            LexerFlags.LEXFL_NOWARNINGS |
            LexerFlags.LEXFL_NOSTRINGCONCAT |
            LexerFlags.LEXFL_ALLOWPATHNAMES |
            LexerFlags.LEXFL_NOSTRINGESCAPECHARS |
            LexerFlags.LEXFL_ALLOWIPADDRESSES;

        const token = Token.init();
        defer token.deinit();
        const number_token = Token.init();
        defer number_token.deinit();

        var total_len: usize = 0;

        while (true) {
            if (args.argc == CmdArgs.MAX_COMMAND_ARGS) break;
            if (!lexer.readToken(token)) break;

            if (std.mem.eql(u8, token.slice(), "-")) {
                if (lexer.checkTokenType(TokenType.TT_NUMBER, 0, number_token)) {
                    var m = idlib.idStr{};
                    m.initEmptyBuffer();
                    m.assignSlice("-") catch unreachable;
                    defer m.deinit();

                    m.appendSlice(number_token.base.constSlice()) catch unreachable;

                    token.base.assignSlice(m.constSlice()) catch unreachable;
                }
            }

            if (std.mem.eql(u8, token.slice(), "$")) {
                if (!lexer.readToken(token)) break;
                //const cvar = cvar_system.instance.getCVarString(token.slice());
                //token.base.assignStr(cvar);
                token.base.assignSlice("<unknown>") catch unreachable;
            }

            const len = token.slice().len;

            if (total_len + len + 1 > MAX_COMMAND_STRING) break;

            args.appendArg(token.slice());
            total_len += len + 1;
        }
    }

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

pub const CmdFn = fn (*const CmdArgs) callconv(.C) void;

pub const CommandDef = extern struct {
    next: ?*CommandDef,
    name: [*:0]u8,
    function: *const CmdFn,
    argCompletion: ?*const ArgCompletionFn,
    flags: c_int,
    description: [*:0]u8,
};

pub const CmdSystem = extern struct {
    pub const MAX_CMD_BUFFER: usize = 0x10000;

    vptr: *anyopaque,
    commands: ?*CommandDef, // linked list
    wait: c_int,
    textLength: c_int,
    textBuf: [MAX_CMD_BUFFER]u8,
    completionString: idlib.idStr,
    completionParms: idlib.idStrList,
    tokenizedCmds: idlib.idList(CmdArgs),
    postReload: CmdArgs,

    pub fn init(cmd_system: *CmdSystem) error{OutOfMemory}!void {
        try cmd_system.addCommand(
            "listCmds",
            cmd_listAllCommands,
            CmdFlags.CMD_FL_SYSTEM,
            "list commands",
            null,
        );

        try cmd_system.addCommand(
            "exec",
            cmd_execFile,
            CmdFlags.CMD_FL_SYSTEM,
            "executes a config file",
            null,
        );

        const cmd_decls = comptime blk: {
            var count: usize = 0;
            const tree = @import("../static_cmds.zig").root;

            for (tree) |mod| {
                for (@typeInfo(mod).Struct.decls) |decl| {
                    if (@TypeOf(@field(mod, decl.name)) == CmdDecl) {
                        count += 1;
                    }
                }
            }

            var array: [count]*const CmdDecl = undefined;
            var i: usize = 0;
            for (tree) |mod| {
                for (@typeInfo(mod).Struct.decls) |decl| {
                    if (@TypeOf(@field(mod, decl.name)) == CmdDecl) {
                        array[i] = &@field(mod, decl.name);
                        i += 1;
                    }
                }
            }

            break :blk array;
        };
        inline for (cmd_decls) |cmd_decl| {
            std.debug.print("[CMD] register: {s}\n", .{cmd_decl.name});
            try cmd_system.addCommand(
                cmd_decl.name,
                cmd_decl.function,
                cmd_decl.flags,
                cmd_decl.description,
                cmd_decl.arg_completion,
            );
        }

        try cmd_system.completionString.assignSlice("*");
        cmd_system.textLength = 0;
    }

    pub fn executeTokenizedString(
        cmd_system: *CmdSystem,
        tokenized_args: *const CmdArgs,
    ) void {
        if (tokenized_args.argc == 0) return;

        const name = std.mem.span(tokenized_args.argv[0]);

        var opt_cmd = cmd_system.commands;
        while (opt_cmd) |cmd| : (opt_cmd = cmd.next) {
            if (std.mem.eql(u8, name, std.mem.span(cmd.name))) {
                cmd.function(tokenized_args);
                return;
            }
        }

        // TODO: check cvars

        std.debug.print("[CMD] Unknown command '{s}'\n", .{name});
    }

    pub fn shutdown(cmd_system: *CmdSystem) void {
        const allocator = global.gpa.allocator();
        var opt_cmd = cmd_system.commands;
        while (opt_cmd) |cmd| : (opt_cmd = cmd_system.commands) {
            cmd_system.commands = cmd.next;

            allocator.free(std.mem.span(cmd.name));
            allocator.free(std.mem.span(cmd.description));
            allocator.destroy(cmd);
        }

        cmd_system.commands = null;
    }

    pub fn addCommand(
        cmd_system: *CmdSystem,
        name: []const u8,
        function: *const CmdFn,
        flags: c_int,
        description: []const u8,
        arg_completion: ?*const ArgCompletionFn,
    ) error{OutOfMemory}!void {
        // check if the command with the same name already exists
        {
            var opt_cmd = cmd_system.commands;
            while (opt_cmd) |cmd| : (opt_cmd = cmd.next) {
                if (std.mem.eql(u8, name, std.mem.span(cmd.name))) {
                    std.debug.print(
                        "[CMD] Command with name = \"{s}\" already defined.\n",
                        .{name},
                    );
                }
            }
        }

        const allocator = global.gpa.allocator();

        const cmd = try allocator.create(CommandDef);
        errdefer allocator.destroy(cmd);
        const cmd_name = try allocator.dupeZ(u8, name);
        errdefer allocator.free(cmd_name);
        const cmd_desc = try allocator.dupeZ(u8, description);
        errdefer allocator.free(cmd_desc);

        cmd.name = cmd_name.ptr;
        cmd.function = function;
        cmd.argCompletion = arg_completion;
        cmd.flags = flags;
        cmd.description = cmd_desc.ptr;
        cmd.next = cmd_system.commands;
        cmd_system.commands = cmd;
    }

    pub fn removeCommand(
        cmd_system: *CmdSystem,
        name: []const u8,
    ) void {
        var last: *?*CommandDef = &cmd_system.commands;
        var opt_cmd = cmd_system.commands;
        while (opt_cmd) |cmd| : (opt_cmd = last.*) {
            if (std.mem.eql(u8, name, std.mem.span(cmd.name))) {
                const allocator = global.gpa.allocator();
                last.* = cmd.next;
                allocator.free(std.mem.span(cmd.name));
                allocator.free(std.mem.span(cmd.description));
                allocator.destroy(cmd);
                return;
            }
            last = &cmd.next;
        }

        std.debug.print(
            "[CMD] Command with name = \"{s}\" is not defined.\n",
            .{name},
        );
    }

    pub fn bufferCommandText(cmd_system: *CmdSystem, exec: CmdExecution, text: []const u8) void {
        switch (exec) {
            .CMD_EXEC_NOW => cmd_system.executeCommandText(text),
            .CMD_EXEC_INSERT => cmd_system.insertCommandText(text),
            .CMD_EXEC_APPEND => cmd_system.appendCommandText(text),
        }
    }

    pub fn executeCommandText(cmd_system: *CmdSystem, text: []const u8) void {
        var args: CmdArgs = .{};
        args.tokenizeString(text);

        cmd_system.executeTokenizedString(&args);
    }

    pub fn executeCommandBuffer(cmd_system: *CmdSystem) void {
        while (cmd_system.textLength != 0) {
            if (cmd_system.wait != 0) {
                cmd_system.wait -= 1;
                break;
            }

            var quotes: usize = 0;
            const text = cmd_system.textBuf[0..@intCast(cmd_system.textLength)];
            const line = for (text, 0..) |char, i| {
                switch (char) {
                    '"' => quotes += 1,
                    ';' => if ((quotes % 2) != 0) break text[0..i],
                    '\n', '\r' => break text[0..i],
                    else => continue,
                }
            } else text;

            var args: CmdArgs = .{};
            if (std.mem.eql(u8, line, "_execTokenized")) {
                args.copy(&(cmd_system.tokenizedCmds.constSlice()[0]));
                cmd_system.tokenizedCmds.removeIndex(0);
            } else {
                args.tokenizeString(line);
            }

            // delete the text from the command buffer and move remaining commands down
            // this is necessary because commands (exec) can insert data at the
            // beginning of the text buffer
            if (line.len == text.len) {
                cmd_system.textLength = 0;
            } else {
                const line_len_with_delimiter = line.len + 1;
                const old_len: usize = @intCast(cmd_system.textLength);
                const len: usize = old_len - line_len_with_delimiter;

                std.mem.copyForwards(
                    u8,
                    cmd_system.textBuf[0..len],
                    cmd_system.textBuf[line_len_with_delimiter..old_len],
                );
                cmd_system.textLength = @intCast(len);
            }

            cmd_system.executeTokenizedString(&args);
        }
    }

    /// Adds command text immediately after the current command
    /// Adds a \n to the text
    pub fn insertCommandText(cmd_system: *CmdSystem, text: []const u8) void {
        const len = text.len + 1;
        const current_len: usize = @intCast(cmd_system.textLength);
        if (len + current_len > MAX_CMD_BUFFER) {
            std.debug.print("[CMD][ERR] cmd_buffer overflow\n", .{});
            return;
        }

        // move the existing command text
        var i = @as(i32, @intCast(current_len)) - 1;
        while (i >= 0) : (i -= 1) {
            const index: usize = @intCast(i);
            cmd_system.textBuf[index + len] = cmd_system.textBuf[index];
        }

        // copy the new text in
        @memcpy(cmd_system.textBuf[0 .. len - 1], text);

        // add a \n
        cmd_system.textBuf[len - 1] = '\n';

        cmd_system.textLength += @intCast(len);
    }

    /// Adds command text at the end of the buffer, does NOT add a final \n
    pub fn appendCommandText(cmd_system: *CmdSystem, text: []const u8) void {
        const len = text.len;
        const current_len: usize = @intCast(cmd_system.textLength);
        if (len + current_len > MAX_CMD_BUFFER) {
            std.debug.print("[CMD][ERR] cmd_buffer overflow\n", .{});
            return;
        }

        @memcpy(cmd_system.textBuf[current_len .. current_len + len], text);

        cmd_system.textLength += @intCast(len);
    }
};

pub const instance = @extern(*CmdSystem, .{ .name = "cmdSystemLocal" });

pub const CommandLink = struct {
    next: ?*const CommandLink,
    name: []const u8,
};

pub fn listCommandsByFlags(flags: c_int) void {
    var opt_cmd = instance.commands;
    while (opt_cmd) |cmd| : (opt_cmd = cmd.next) {
        if ((cmd.flags & flags) != 0) {
            std.debug.print("cmd: {s}, desc: {s}\n", .{ cmd.name, cmd.description });
        }
    }
}

pub fn cmd_listAllCommands(_: *const CmdArgs) callconv(.C) void {
    listCommandsByFlags(CmdFlags.CMD_FL_ALL);
}

pub fn cmd_execFile(args: *const CmdArgs) callconv(.C) void {
    if (args.argc != 2) {
        std.debug.print("[CMD] Usage: exec <filename>\n", .{});
        return;
    }

    const filename = std.mem.span(args.argv[1]);

    const buffer = file_system.instance.readFileAnyAlloc(filename) catch |err| {
        std.debug.print("[CMD][ERR:{s}] While reading file {s}\n", .{
            @errorName(err),
            filename,
        });
        return;
    };
    defer file_system.instance.freeFileBuffer(buffer);

    std.debug.print("[CMD] Execing file: {s}\n", .{filename});

    instance.bufferCommandText(.CMD_EXEC_INSERT, buffer);
}
