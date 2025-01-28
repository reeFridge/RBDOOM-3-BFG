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
const Allocator = std.mem.Allocator;

pub const CmdDecl = struct {
    name: []const u8,
    function: ?*const CmdFn = null,
    function_with_allocator: ?*const CmdFnWithAllocator = null,
    flags: c_int,
    description: []const u8,
    arg_completion: ?*const ArgCompletionFn = null,
};

pub const CallbackFn = fn () callconv(.C) void;

pub const CmdFlags = struct {
    pub const all: c_int = -1;
    pub const cheat: c_int = bit(0); // command is considered a cheat
    pub const system: c_int = bit(1); // system command
    pub const renderer: c_int = bit(2); // renderer command
    pub const sound: c_int = bit(3); // sound command
    pub const game: c_int = bit(4); // game command
    pub const tool: c_int = bit(5); // tool command
};

pub const CmdArgs = extern struct {
    pub const max_command_args: usize = 64;
    pub const max_string_chars: usize = 1024;
    pub const max_command_string: usize = max_string_chars * 2;

    argc: u32 = 0,
    argv: [max_command_args][*:0]u8 = undefined, // points into tokenized
    tokenized: [max_command_string]u8 = undefined,
    // WARN: @sizeOf([max:0]u8) != @sizeOf([max]u8)

    pub fn copyFrom(args: *CmdArgs, other: *const CmdArgs) void {
        args.argc = other.argc;
        args.tokenized = other.tokenized;

        for (0..args.argc) |i| {
            const tok_addr = @intFromPtr(&args.tokenized);
            const other_tok_addr = @intFromPtr(&other.tokenized);
            const argv_addr = @intFromPtr(other.argv[i]);
            args.argv[i] = @ptrFromInt(tok_addr + (argv_addr - other_tok_addr));
        }
    }

    pub fn tokenizeString(args: *CmdArgs, text: []const u8) error{OutOfMemory}!void {
        if (text.len == 0) return;

        const allocator = global.gpa.allocator();
        const text_sentinel = allocator.dupeZ(u8, text) catch unreachable;
        defer allocator.free(text_sentinel);

        var lexer = Lexer{
            .flags = .{
                .no_errors = true,
                .no_warnings = true,
                .no_string_concat = true,
                .allow_path_names = true,
                .no_string_escape_chars = true,
                .allow_ip_addresses = true,
            },
        };
        defer lexer.deinit(allocator);

        lexer.loadMemory(text_sentinel, "CmdArgs.fromText", 0, allocator) catch return;

        var token = Token{};
        defer token.deinit(allocator);

        var number_token = Token{};
        defer number_token.deinit(allocator);

        var total_len: usize = 0;

        while (true) {
            if (args.argc == CmdArgs.max_command_args) break;
            lexer.readToken(&token, allocator) catch break;

            if (std.mem.eql(u8, token.slice(), "-")) {
                if (try lexer.checkTokenType(.number, .{}, &number_token, allocator)) {
                    var m = idlib.Str{};
                    m.assignSlice("-", allocator) catch unreachable;
                    defer m.deinit(allocator);

                    m.appendSlice(number_token.str.constSlice(), allocator) catch unreachable;

                    token.str.assignSlice(m.constSlice(), allocator) catch unreachable;
                }
            }

            if (std.mem.eql(u8, token.slice(), "$")) {
                lexer.readToken(&token, allocator) catch break;
                //const cvar = cvar_system.instance.getCVarString(token.slice());
                //token.str.assignStr(cvar);
                token.str.assignSlice("<unknown>", allocator) catch unreachable;
            }

            const len = token.slice().len;

            if (total_len + len + 1 > max_command_string) break;

            args.appendArg(token.slice());
            total_len += len + 1;
        }
    }

    pub fn appendArg(cmd_args: *CmdArgs, text: []const u8) void {
        if (cmd_args.argc >= max_command_args) return;

        const argc: usize = @intCast(cmd_args.argc);

        cmd_args.argv[argc] = if (cmd_args.argc == 0)
            // point at the start
            @ptrCast(&cmd_args.tokenized)
        else
            // point at the (end + \0) of previous arg
            cmd_args.argv[argc - 1] + std.mem.len(cmd_args.argv[argc - 1]) + 1;

        std.mem.copyForwards(u8, cmd_args.argv[argc][0..text.len], text);
        const arg = cmd_args.argv[argc][0..text.len :0];
        arg[text.len] = 0;
        cmd_args.argc += 1;
    }
};

pub const ArgCompletionFn = fn (
    *CmdArgs,
    *const CallbackFn,
    [*:0]const u8,
) callconv(.C) void;

pub const CmdFn = fn (*const CmdArgs) callconv(.C) void;
pub const CmdFnWithAllocator = fn (*const CmdArgs, Allocator) void;

pub const CommandDef = extern struct {
    next: ?*CommandDef,
    name: [*:0]u8,
    function: ?*const CmdFn = null,
    function_with_allocator: ?*const CmdFnWithAllocator = null,
    arg_completion: ?*const ArgCompletionFn = null,
    flags: c_int,
    description: [*:0]u8,
};

pub const CmdSystem = struct {
    pub const max_cmd_buffer: usize = 0x10000;

    commands: ?*CommandDef = null, // linked list
    wait: c_int = 0,
    text_length: u32 = 0,
    text_buffer: [max_cmd_buffer]u8 = undefined,
    completion_string: idlib.Str = .{},
    completion_params: idlib.List(idlib.Str) = .{},
    tokenized_cmds: idlib.List(CmdArgs) = .{},
    post_reload: CmdArgs = .{},

    pub fn init(cmd_system: *CmdSystem, allocator: Allocator) Allocator.Error!void {
        try cmd_system.addCommand(
            "listCmds",
            cmd_listAllCommands,
            null,
            CmdFlags.system,
            "list commands",
            null,
            allocator,
        );

        try cmd_system.addCommand(
            "exec",
            cmd_execFile,
            null,
            CmdFlags.system,
            "executes a config file",
            null,
            allocator,
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
                cmd_decl.function_with_allocator,
                cmd_decl.flags,
                cmd_decl.description,
                cmd_decl.arg_completion,
                allocator,
            );
        }

        try cmd_system.completion_string.assignSlice("*", allocator);
        cmd_system.text_length = 0;
    }

    pub fn executeTokenizedString(
        cmd_system: *CmdSystem,
        tokenized_args: *const CmdArgs,
        allocator: Allocator,
    ) void {
        if (tokenized_args.argc == 0) return;

        const name = std.mem.span(tokenized_args.argv[0]);

        var opt_cmd = cmd_system.commands;
        while (opt_cmd) |cmd| : (opt_cmd = cmd.next) {
            if (std.mem.eql(u8, name, std.mem.span(cmd.name))) {
                if (cmd.function_with_allocator) |function| {
                    function(tokenized_args, allocator);
                } else if (cmd.function) |function| {
                    function(tokenized_args);
                } else {
                    std.debug.print(
                        "[CMD][{s}] Cmd function is not bounded\n",
                        .{name},
                    );
                }
                return;
            }
        }

        // TODO: check cvars

        std.debug.print("[CMD] Unknown command '{s}'\n", .{name});
    }

    pub fn shutdown(cmd_system: *CmdSystem, allocator: Allocator) void {
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
        function: ?*const CmdFn,
        function_with_allocator: ?*const CmdFnWithAllocator,
        flags: c_int,
        description: []const u8,
        arg_completion: ?*const ArgCompletionFn,
        allocator: Allocator,
    ) Allocator.Error!void {
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

        const cmd = try allocator.create(CommandDef);
        errdefer allocator.destroy(cmd);
        const cmd_name = try allocator.dupeZ(u8, name);
        errdefer allocator.free(cmd_name);
        const cmd_desc = try allocator.dupeZ(u8, description);
        errdefer allocator.free(cmd_desc);

        cmd.name = cmd_name.ptr;
        cmd.function = function;
        cmd.function_with_allocator = function_with_allocator;
        cmd.arg_completion = arg_completion;
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

    pub fn appendTokenizedString(
        cmd_system: *CmdSystem,
        args: *const CmdArgs,
        allocator: Allocator,
    ) Allocator.Error!void {
        cmd_system.appendCommandText("_execTokenized\n");
        const args_copy = try cmd_system.tokenized_cmds.allocOne(allocator);
        args_copy.copyFrom(args);
    }

    pub fn executeCommandText(
        cmd_system: *CmdSystem,
        text: []const u8,
        allocator: Allocator,
    ) error{OutOfMemory}!void {
        var args: CmdArgs = .{};
        try args.tokenizeString(text);

        cmd_system.executeTokenizedString(&args, allocator);
    }

    pub fn executeCommandBuffer(
        cmd_system: *CmdSystem,
        allocator: Allocator,
    ) error{OutOfMemory}!void {
        var free_tokenized_cmds: u32 = 0;
        while (cmd_system.text_length != 0) {
            if (cmd_system.wait != 0) {
                cmd_system.wait -= 1;
                break;
            }

            var quotes: usize = 0;
            const text = cmd_system.text_buffer[0..cmd_system.text_length];
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
                args.copyFrom(&(cmd_system.tokenized_cmds.constSlice()[free_tokenized_cmds]));
                free_tokenized_cmds += 1;
            } else {
                try args.tokenizeString(line);
            }

            // delete the text from the command buffer and move remaining commands down
            // this is necessary because commands (exec) can insert data at the
            // beginning of the text buffer
            if (line.len == text.len) {
                cmd_system.text_length = 0;
            } else {
                const line_len_with_delimiter = line.len + 1;
                const old_len: usize = cmd_system.text_length;
                const len: usize = old_len - line_len_with_delimiter;

                std.mem.copyForwards(
                    u8,
                    cmd_system.text_buffer[0..len],
                    cmd_system.text_buffer[line_len_with_delimiter..old_len],
                );
                cmd_system.text_length = @intCast(len);
            }

            cmd_system.executeTokenizedString(&args, allocator);
        }

        // remove cmds from queue
        for (0..free_tokenized_cmds) |_| {
            var cmds = &cmd_system.tokenized_cmds;
            cmds.num -= 1;
            for (0..cmds.num) |i| {
                cmds.list.?[i].copyFrom(&cmds.list.?[i + 1]);
            }
        }
    }

    /// Adds command text immediately after the current command
    /// Adds a \n to the text
    pub fn insertCommandText(cmd_system: *CmdSystem, text: []const u8) void {
        const len = text.len + 1;
        const current_len: usize = cmd_system.text_length;
        if (len + current_len > max_cmd_buffer) {
            std.debug.print("[CMD][ERR] cmd_buffer overflow\n", .{});
            return;
        }

        // move the existing command text
        var i = @as(i32, @intCast(current_len)) - 1;
        while (i >= 0) : (i -= 1) {
            const index: usize = @intCast(i);
            cmd_system.text_buffer[index + len] = cmd_system.text_buffer[index];
        }

        // copy the new text in
        @memcpy(cmd_system.text_buffer[0 .. len - 1], text);

        // add a \n
        cmd_system.text_buffer[len - 1] = '\n';

        cmd_system.text_length += @intCast(len);
    }

    /// Adds command text at the end of the buffer, does NOT add a final \n
    pub fn appendCommandText(cmd_system: *CmdSystem, text: []const u8) void {
        const len = text.len;
        const current_len: usize = cmd_system.text_length;
        if (len + current_len > max_cmd_buffer) {
            std.debug.print("[CMD][ERR] cmd_buffer overflow\n", .{});
            return;
        }

        @memcpy(cmd_system.text_buffer[current_len..][0..len], text);

        cmd_system.text_length += @intCast(len);
    }
};

pub var instance = CmdSystem{};

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
    listCommandsByFlags(CmdFlags.all);
}

pub fn cmd_execFile(args: *const CmdArgs) callconv(.C) void {
    if (args.argc != 2) {
        std.debug.print("[CMD] Usage: exec <filename>\n", .{});
        return;
    }

    const filename = std.mem.span(args.argv[1]);

    const allocator = global.gpa.allocator();
    const buffer = file_system.instance.readFileAnyAlloc(filename, allocator) catch |err| {
        std.debug.print("[CMD][ERR:{s}] While reading file {s}\n", .{
            @errorName(err),
            filename,
        });
        return;
    };
    defer allocator.free(buffer);

    std.debug.print("[CMD] Execing file: {s}\n", .{filename});

    instance.insertCommandText(buffer);
}
