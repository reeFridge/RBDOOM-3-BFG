const idlib = @import("idlib.zig");
const fs = @import("framework/file_system.zig");
const std = @import("std");
const token_ = @import("token.zig");
const Token = token_.Token;
const TokenType = token_.Type;
const TokenSubtype = token_.Subtype;

pub const BraceSkipMode = enum(c_int) {
    brace,
    bracket,
};

pub const Flags = packed struct(u32) {
    no_errors: bool = false,
    no_warnings: bool = false,
    no_fatal_errors: bool = false,
    no_string_concat: bool = false,
    no_string_escape_chars: bool = false,
    no_dollar_precompile: bool = false,
    no_base_includes: bool = false,
    allow_path_names: bool = false,
    allow_number_names: bool = false,
    allow_ip_addresses: bool = false,
    allow_float_exceptions: bool = false,
    allow_multichar_literals: bool = false,
    allow_backslash_string_concat: bool = false,
    only_strings: bool = false,
    reserved_: u18 = 0,
};

pub const Punctuation = extern struct {
    p: ?[*:0]const u8,
    n: Id,

    pub const Id = enum(c_int) {
        unknown = 0,
        rshift_assign = 1,
        lshift_assign = 2,
        parms = 3,
        precompmerge = 4,
        logic_and = 5,
        logic_or = 6,
        logic_geq = 7,
        logic_leq = 8,
        logic_eq = 9,
        logic_uneq = 10,
        mul_assign = 11,
        div_assign = 12,
        mod_assign = 13,
        add_assign = 14,
        sub_assign = 15,
        inc = 16,
        dec = 17,
        bin_and_assign = 18,
        bin_or_assign = 19,
        bin_xor_assign = 20,
        rshift = 21,
        lshift = 22,
        pointerref = 23,
        cpp1 = 24,
        cpp2 = 25,
        mul = 26,
        div = 27,
        mod = 28,
        add = 29,
        sub = 30,
        assign = 31,
        bin_and = 32,
        bin_or = 33,
        bin_xor = 34,
        bin_not = 35,
        logic_not = 36,
        logic_greater = 37,
        logic_less = 38,
        ref = 39,
        comma = 40,
        semicolon = 41,
        colon = 42,
        questionmark = 43,
        parenthesesopen = 44,
        parenthesesclose = 45,
        braceopen = 46,
        braceclose = 47,
        sqbracketopen = 48,
        sqbracketclose = 49,
        backslash = 50,
        precomp = 51,
        dollar = 52,
    };
};

const default_punctuations: []const Punctuation =
    &.{
    //BINARY OPERATORS
    .{ .p = ">>=", .n = .rshift_assign },
    .{ .p = "<<=", .n = .lshift_assign },
    //
    .{ .p = "...", .n = .parms },
    //DEFINE MERGE OPERATOR
    .{ .p = "##", .n = .precompmerge }, // PRE-COMPILER
    //LOGIC OPERATORS
    .{ .p = "&&", .n = .logic_and }, // PRE-COMPILER
    .{ .p = "||", .n = .logic_or }, // PRE-COMPILER
    .{ .p = ">=", .n = .logic_geq }, // PRE-COMPILER
    .{ .p = "<=", .n = .logic_leq }, // PRE-COMPILER
    .{ .p = "==", .n = .logic_eq }, // PRE-COMPILER
    .{ .p = "!=", .n = .logic_uneq }, // PRE-COMPILER
    //ARITHMATIC OPERATORS
    .{ .p = "*=", .n = .mul_assign },
    .{ .p = "/=", .n = .div_assign },
    .{ .p = "%=", .n = .mod_assign },
    .{ .p = "+=", .n = .add_assign },
    .{ .p = "-=", .n = .sub_assign },
    .{ .p = "++", .n = .inc },
    .{ .p = "--", .n = .dec },
    //BINARY OPERATORS
    .{ .p = "&=", .n = .bin_and_assign },
    .{ .p = "|=", .n = .bin_or_assign },
    .{ .p = "^=", .n = .bin_xor_assign },
    .{ .p = ">>", .n = .rshift }, // PRE-COMPILER
    .{ .p = "<<", .n = .lshift }, // PRE-COMPILER
    //REFERENCE OPERATORS
    .{ .p = "->", .n = .pointerref },
    //c++
    .{ .p = "::", .n = .cpp1 },
    .{ .p = ".*", .n = .cpp2 },
    //ARITHMATIC OPERATORS
    .{ .p = "*", .n = .mul }, // PRE-COMPILER
    .{ .p = "/", .n = .div }, // PRE-COMPILER
    .{ .p = "%", .n = .mod }, // PRE-COMPILER
    .{ .p = "+", .n = .add }, // PRE-COMPILER
    .{ .p = "-", .n = .sub }, // PRE-COMPILER
    .{ .p = "=", .n = .assign },
    //BINARY OPERATORS
    .{ .p = "&", .n = .bin_and }, // PRE-COMPILER
    .{ .p = "|", .n = .bin_or }, // PRE-COMPILER
    .{ .p = "^", .n = .bin_xor }, // PRE-COMPILER
    .{ .p = "~", .n = .bin_not }, // PRE-COMPILER
    //LOGIC OPERATORS
    .{ .p = "!", .n = .logic_not }, // PRE-COMPILER
    .{ .p = ">", .n = .logic_greater }, // PRE-COMPILER
    .{ .p = "<", .n = .logic_less }, // PRE-COMPILER
    //REFERENCE OPERATOR
    .{ .p = ".", .n = .ref },
    //SEPERATORS
    .{ .p = ",", .n = .comma }, // PRE-COMPILER
    .{ .p = ";", .n = .semicolon },
    //LABEL INDICATION
    .{ .p = ":", .n = .colon }, // PRE-COMPILER
    //IF STATEMENT
    .{ .p = "?", .n = .questionmark }, // PRE-COMPILER
    //EMBRACEMENTS
    .{ .p = "(", .n = .parenthesesopen }, // PRE-COMPILER
    .{ .p = ")", .n = .parenthesesclose }, // PRE-COMPILER
    .{ .p = "{", .n = .braceopen }, // PRE-COMPILER
    .{ .p = "}", .n = .braceclose }, // PRE-COMPILER
    .{ .p = "[", .n = .sqbracketopen },
    .{ .p = "]", .n = .sqbracketclose },
    //
    .{ .p = "\\", .n = .backslash },
    //PRECOMPILER OPERATOR
    .{ .p = "#", .n = .precomp }, // PRE-COMPILER
    .{ .p = "$", .n = .dollar },
    .{ .p = null, .n = .unknown },
};

var default_punctuation_table: [256]i32 = undefined;
var default_next_punctuation: [default_punctuations.len]i32 = undefined;
var default_setup: bool = false;

pub const Lexer = struct {
    const Allocator = std.mem.Allocator;

    var base_folder_buffer: [256]u8 = undefined;
    var base_folder: []const u8 = &.{};

    loaded: bool = false,
    filename: idlib.Str = .{},
    allocated: bool = false,
    buffer: ?[*:0]const u8 = null,
    script_p: ?[*]const u8 = null,
    end_p: ?[*]const u8 = null,
    last_script_p: ?[*]const u8 = null,
    white_space_start_p: ?[*]const u8 = null,
    white_space_end_p: ?[*]const u8 = null,
    file_time: idlib.Time = 0,
    length: u32 = 0,
    line: u32 = 0,
    last_line: u32 = 0,
    initial_line: u32 = 0,
    token_available: bool = false,
    flags: Flags = .{},
    punctuations: ?[*]const Punctuation = null,
    punctuation_table: ?[*]i32 = null,
    next_punctuation: ?[*]i32 = null,
    token: Token = .{},
    next_lexer: ?*Lexer = null,
    had_error: bool = false,

    inline fn checkEndOfBuffer(lexer: *const Lexer) bool {
        return lexer.script_p.? == (lexer.buffer.? + lexer.length);
    }

    inline fn checkEndOfStream(lexer: *const Lexer) bool {
        return lexer.checkEndOfBuffer() or lexer.script_p.?[0] == 0;
    }

    inline fn nextN(lexer: *const Lexer, n: u32) u8 {
        return (lexer.script_p.? + n)[0];
    }

    inline fn next(lexer: *const Lexer) u8 {
        return lexer.nextN(1);
    }

    inline fn prevN(lexer: *const Lexer, n: u32) u8 {
        return (lexer.script_p.? - n)[0];
    }

    inline fn prev(lexer: *const Lexer) u8 {
        return lexer.prevN(1);
    }

    inline fn current(lexer: *const Lexer) u8 {
        return lexer.script_p.?[0];
    }

    inline fn consumeN(lexer: *Lexer, n: u32) u8 {
        lexer.script_p.? += n;
        return lexer.current();
    }

    inline fn consume(lexer: *Lexer) u8 {
        return lexer.consumeN(1);
    }

    inline fn consumeBackwardN(lexer: *Lexer, n: u32) u8 {
        lexer.script_p.? -= n;
        return lexer.current();
    }

    inline fn consumeBackward(lexer: *Lexer) u8 {
        return lexer.consumeBackwardN(1);
    }

    inline fn checkNextString(lexer: *const Lexer, str: []const u8) bool {
        for (str, 0..) |char, i| {
            if (lexer.nextN(@intCast(i)) != char) return false;
        }

        return true;
    }

    pub const LoadMemoryError = error{AlreadyLoaded} || Allocator.Error;
    pub fn loadMemory(
        lexer: *Lexer,
        text: []const u8,
        name: []const u8,
        start_line: u32,
        allocator: Allocator,
    ) LoadMemoryError!void {
        if (lexer.isLoaded()) return error.AlreadyLoaded;

        try lexer.createPunctuationTable(null, allocator);
        std.debug.assert(lexer.punctuations != null);

        try lexer.filename.assignSlice(name, allocator);
        lexer.buffer = @ptrCast(text.ptr);
        lexer.length = @intCast(text.len);
        lexer.file_time = 0;
        lexer.script_p = lexer.buffer;
        lexer.last_script_p = lexer.buffer;
        lexer.end_p = lexer.buffer.? + text.len;

        lexer.token_available = false;
        lexer.line = 0;
        lexer.last_line = start_line;
        lexer.initial_line = start_line;
        lexer.allocated = false;
        lexer.loaded = true;
    }

    /// null = default_punctuations
    pub fn createPunctuationTable(
        lexer: *Lexer,
        new_punctuations: ?[]const Punctuation,
        allocator: Allocator,
    ) Allocator.Error!void {
        const punctuations = new_punctuations orelse default_punctuations;
        defer {
            lexer.punctuations = punctuations.ptr;
        }

        {
            const len = if (punctuations.ptr == default_punctuations.ptr) len: {
                lexer.punctuation_table = &default_punctuation_table;
                lexer.next_punctuation = &default_next_punctuation;

                if (default_setup) return;

                default_setup = true;

                break :len default_punctuations.len;
            } else len: {
                if (lexer.punctuation_table == null or
                    lexer.punctuation_table == &default_punctuation_table)
                {
                    const new_table = try allocator.alloc(i32, default_punctuation_table.len);
                    lexer.punctuation_table = new_table.ptr;
                }

                if (lexer.next_punctuation != null and lexer.next_punctuation != &default_next_punctuation) {
                    var next_p_len: u32 = 0;
                    while (lexer.punctuations.?[next_p_len].p != null) : (next_p_len += 1) {}

                    allocator.free(lexer.next_punctuation.?[0..next_p_len]);
                    next_p_len = 0;
                }

                var next_p_len: u32 = 0;
                while (punctuations[next_p_len].p != null) : (next_p_len += 1) {}
                const new_next = try allocator.alloc(i32, next_p_len);
                lexer.punctuation_table = new_next.ptr;

                break :len next_p_len;
            };

            @memset(
                lexer.punctuation_table.?[0..default_punctuation_table.len],
                -1,
            );
            @memset(lexer.next_punctuation.?[0..len], -1);
        }

        var p_index: u32 = 0;
        while (punctuations[p_index].p != null) : (p_index += 1) {
            const new_p = &punctuations[p_index];
            var last_p: i32 = -1;

            var n = lexer.punctuation_table.?[@as(u32, new_p.p.?[0])];
            while (n >= 0) : (n = lexer.next_punctuation.?[@intCast(n)]) {
                const p = &punctuations[@intCast(n)];

                if (std.mem.len(p.p.?) < std.mem.len(new_p.p.?)) {
                    lexer.next_punctuation.?[p_index] = n;

                    if (last_p >= 0) {
                        lexer.next_punctuation.?[@intCast(last_p)] = @intCast(p_index);
                    } else {
                        lexer.punctuation_table.?[@as(u32, new_p.p.?[0])] = @intCast(p_index);
                    }

                    break;
                }

                last_p = n;
            }

            if (n < 0) {
                if (last_p >= 0) {
                    lexer.next_punctuation.?[@intCast(last_p)] = @intCast(p_index);
                } else {
                    lexer.punctuation_table.?[@as(u32, new_p.p.?[0])] = @intCast(p_index);
                }
            }
        }
    }

    pub fn initFromFile(
        lexer: *Lexer,
        path: []const u8,
        flags: Flags,
        allocator: Allocator,
    ) LoadFileError!void {
        lexer.flags = flags;
        try lexer.createPunctuationTable(null, allocator);
        std.debug.assert(lexer.punctuations != null);

        try lexer.loadFile(path, false, allocator);
    }

    const MAX_FILE_SIZE = 1000 * 1024;
    pub const LoadFileError = error{
        OutOfMemory,
        AlreadyLoaded,
        StreamTooLong,
    } || fs.FileSystem.OpenOSFileError || std.fs.File.Reader.Error;
    fn loadFile(
        lexer: *Lexer,
        path: []const u8,
        os_path: bool,
        allocator: Allocator,
    ) LoadFileError!void {
        if (lexer.loaded) return error.AlreadyLoaded;

        var path_buffer: [256]u8 = undefined;
        const path_name: []const u8 = if (!os_path and base_folder.len != 0)
            std.fmt.bufPrint(
                &path_buffer,
                "{s}/{s}",
                .{ base_folder, path },
            ) catch unreachable
        else
            path;

        const file = if (os_path)
            try fs.FileSystem.openOSFile(path_name, .FS_READ)
        else
            try fs.instance.openFileRead(path_name);

        defer file.close();

        const file_stat = file.stat() catch unreachable;

        var reader = file.reader();
        const buffer = try reader.readAllAlloc(allocator, MAX_FILE_SIZE);

        lexer.file_time = @intCast(file_stat.mtime);
        try lexer.filename.assignSlice(path_name, allocator);

        lexer.buffer = @ptrCast(buffer.ptr);
        lexer.length = @intCast(buffer.len);

        lexer.script_p = lexer.buffer;
        lexer.last_script_p = lexer.buffer;
        lexer.end_p = lexer.buffer.? + buffer.len;

        lexer.token_available = false;
        lexer.line = 1;
        lexer.line = 1;
        lexer.last_line = 1;
        lexer.allocated = true;
        lexer.loaded = true;
    }

    pub fn deinit(lexer: *Lexer, allocator: Allocator) void {
        if (lexer.allocated) {
            if (lexer.buffer) |buffer_ptr| {
                allocator.free(buffer_ptr[0..lexer.length]);
            }
        }

        lexer.filename.deinit(allocator);
        lexer.token.deinit(allocator);
    }

    pub fn isLoaded(lexer: *Lexer) bool {
        return lexer.loaded;
    }

    pub fn readTokenOnLineOk(lexer: *Lexer, token: *Token, allocator: Allocator) bool {
        return if (lexer.readTokenOnLine(token, allocator))
            true
        else |_|
            false;
    }

    pub fn readTokenOk(lexer: *Lexer, token: *Token, allocator: Allocator) bool {
        return if (lexer.readToken(token, allocator))
            true
        else |_|
            false;
    }

    pub fn unreadToken(
        lexer: *Lexer,
        token: *const Token,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (lexer.token_available) {
            @panic("unread token twice");
        }

        try lexer.token.assignToken(token, allocator);
        lexer.token_available = true;
    }

    pub fn skipBracedSection(
        lexer: *Lexer,
        parse_first_brace: bool,
        skip_mode: BraceSkipMode,
        opt_skipped: ?*u32,
        allocator: Allocator,
    ) ReadTokenError!void {
        const open_tokens: []const []const u8 = &.{ "{", "[" };
        const close_tokens: []const []const u8 = &.{ "}", "]" };

        if (opt_skipped) |skipped| {
            skipped.* = 0;
        }

        var token = Token{};
        defer token.deinit(allocator);

        var depth: u32 = if (parse_first_brace) 0 else 1;

        var first = true;
        while (depth != 0 or first) {
            first = false;

            try lexer.readToken(&token, allocator);

            if (token.type == .punctuation) {
                if (std.mem.eql(
                    u8,
                    token.slice(),
                    open_tokens[@intCast(@intFromEnum(skip_mode))],
                )) {
                    depth += 1;
                    if (opt_skipped) |skipped| {
                        skipped.* += 1;
                    }
                } else if (std.mem.eql(
                    u8,
                    token.slice(),
                    close_tokens[@intCast(@intFromEnum(skip_mode))],
                )) {
                    depth -= 1;
                }
            }
        }
    }

    pub fn getFileOffset(lexer: *const Lexer) u32 {
        const script_p = lexer.script_p orelse return 0;
        const buffer = lexer.buffer orelse return 0;

        const diff = (@intFromPtr(script_p) - @intFromPtr(buffer)) / @sizeOf(u8);

        return @intCast(diff);
    }

    pub const ReadTokenError = error{
        FileNotLoaded,
        ScriptPIsNull,
        OutOfMemory,
        NotAnEscapeChar,
    } || ReadStringError || ReadNumberError;
    pub fn readToken(
        lexer: *Lexer,
        token: *Token,
        allocator: Allocator,
    ) ReadTokenError!void {
        if (!lexer.loaded) return error.FileNotLoaded;
        if (lexer.script_p == null) return error.ScriptPIsNull;

        if (lexer.token_available) {
            lexer.token_available = false;
            try token.assignToken(&lexer.token, allocator);

            return;
        }

        lexer.last_script_p = lexer.script_p;
        lexer.last_line = lexer.line;

        token.str.empty();
        lexer.white_space_start_p = lexer.script_p;
        lexer.token.white_space_start_p = lexer.script_p;

        try lexer.readWhiteSpace();

        if (lexer.checkEndOfStream()) return error.EndOfStream;

        lexer.white_space_end_p = lexer.script_p;

        token.white_space_end_p = lexer.script_p;
        token.line = lexer.line;
        token.lines_crossed = lexer.line - lexer.last_line;
        token.flags = 0;

        const char = lexer.current();
        const next_char = lexer.next();

        if (lexer.flags.only_strings) {
            if (char == '\"' or char == '\'') {
                try lexer.readString(token, char, allocator);
            } else {
                try lexer.readName(token, allocator);
            }
        } else if ((char >= '0' and char <= '9') or
            (char == '.' and (next_char >= '0' and next_char <= '9')))
        {
            try lexer.readNumber(token, allocator);

            if (lexer.flags.allow_number_names) {
                const c = lexer.current();
                if ((c >= 'a' and c <= 'z') or
                    (c >= 'A' and c <= 'Z') or c == '_')
                {
                    try lexer.readName(token, allocator);
                }
            }
        } else if (char == '\"' or char == '\'') {
            try lexer.readString(token, char, allocator);
        } else if ((char >= 'a' and char <= 'z') or
            (char >= 'A' and char <= 'Z') or char == '_')
        {
            try lexer.readName(token, allocator);
        } else if (lexer.flags.allow_path_names and
            ((char == '/' or char == '\\') or char == '.'))
        {
            try lexer.readName(token, allocator);
        } else {
            try lexer.readPunctuation(token, allocator);
        }
    }

    pub fn readName(
        lexer: *Lexer,
        token: *Token,
        allocator: Allocator,
    ) Allocator.Error!void {
        token.type = .name;

        var first = true;

        var char: u8 = undefined;
        while (first or ((char >= 'a' and char <= 'z') or
            (char >= 'A' and char <= 'Z') or
            (char >= '0' and char <= '9') or
            char == '_' or
            (lexer.flags.only_strings and char == '-') or
            (lexer.flags.allow_path_names and (char == '/' or char == '\\' or char == ':' or char == '.'))))
        {
            first = false;

            try token.append(lexer.current(), allocator);
            char = lexer.consume();
        }

        token.subtype = @bitCast(@as(u32, @intCast(token.slice().len)));
    }

    const ReadStringError = error{
        NotAnEscapeChar,
        OutOfMemory,
        UnmatchedQuote,
        UnexpectedEndOfLine,
        EndOfStream,
    };
    pub fn readString(
        lexer: *Lexer,
        token: *Token,
        quote: u8,
        allocator: Allocator,
    ) ReadStringError!void {
        token.type = if (quote == '\"')
            .string
        else
            .literal;

        _ = lexer.consume();

        while (true) {
            if (lexer.current() == '\\' and !lexer.flags.no_string_escape_chars) {
                const char = try lexer.readEscapeCharacter();
                try token.append(char, allocator);
            } else if (lexer.current() == quote) {
                _ = lexer.consume();

                if (lexer.flags.no_string_concat and
                    (!lexer.flags.allow_backslash_string_concat or quote != '\"'))
                {
                    break;
                }

                const tmp_script_p = lexer.script_p;
                const tmp_line = lexer.line;
                lexer.readWhiteSpace() catch {
                    lexer.script_p = tmp_script_p;
                    lexer.line = tmp_line;
                    break;
                };

                if (lexer.flags.no_string_concat) {
                    if (lexer.current() != '\\') {
                        lexer.script_p = tmp_script_p;
                        lexer.line = tmp_line;
                        break;
                    }

                    _ = lexer.consume();

                    try lexer.readWhiteSpace();
                    if (lexer.current() != quote) return error.UnmatchedQuote;
                }

                if (lexer.current() != quote) {
                    lexer.script_p = tmp_script_p;
                    lexer.line = tmp_line;
                    break;
                }

                _ = lexer.consume();
            } else {
                if (lexer.checkEndOfStream()) return error.EndOfStream;
                if (lexer.current() == '\n') return error.UnexpectedEndOfLine;

                try token.append(lexer.current(), allocator);
                _ = lexer.consume();
            }
        }

        if (token.type == .literal) {
            if (!lexer.flags.allow_multichar_literals) {
                if (token.str.constSlice().len != 1) {
                    std.debug.print("[WARN] literal is not one character long\n", .{});
                }
            }

            token.subtype = @bitCast(@as(u32, token.slice()[0]));
        } else {
            token.subtype = @bitCast(@as(u32, @intCast(token.slice().len)));
        }
    }

    const ReadNumberError = error{
        OutOfMemory,
        FloatExceptionsNotAllowed,
        IpAddressNotAllowed,
        IpAddressParseError,
    };
    pub fn readNumber(
        lexer: *Lexer,
        token: *Token,
        allocator: Allocator,
    ) ReadNumberError!void {
        token.type = .number;
        token.subtype = .{};
        token.int_value = 0;
        token.float_value = 0;

        var char = lexer.current();
        const next_char = lexer.next();

        if (char == '0' and next_char != '.') {
            if (next_char == 'x' or next_char == 'X') {
                try token.append(lexer.current(), allocator);
                char = lexer.consume();
                try token.append(lexer.current(), allocator);
                char = lexer.consume();

                while ((char >= '0' and char <= '9') or
                    (char >= 'a' and char <= 'f') or
                    (char >= 'A' and char <= 'F'))
                {
                    try token.append(char, allocator);
                    char = lexer.consume();
                }

                token.subtype = .{ .hex = true, .integer = true };
            } else if (next_char == 'b' or next_char == 'B') {
                try token.append(lexer.current(), allocator);
                char = lexer.consume();
                try token.append(lexer.current(), allocator);
                char = lexer.consume();

                while (char == '0' or char == '1') {
                    try token.append(char, allocator);
                    char = lexer.consume();
                }

                token.subtype = .{ .binary = true, .integer = true };
            } else {
                try token.append(lexer.current(), allocator);
                char = lexer.consume();

                while (char >= '0' and char <= '7') {
                    try token.append(char, allocator);
                    char = lexer.consume();
                }

                token.subtype = .{ .octal = true, .integer = true };
            }
        } else {
            // decimal integer or floating point number or ip address
            var dot: u32 = 0;
            while (true) {
                if (char >= '0' and char <= '9') {} else if (char == '.') {
                    dot += 1;
                } else break;

                try token.append(char, allocator);
                char = lexer.consume();
            }

            if (char == 'e' and dot == 0) {
                dot += 1;
            }

            if (dot == 1) {
                token.subtype = .{ .decimal = true, .float = true };
                if (char == 'e') {
                    try token.append(char, allocator);
                    char = lexer.consume();

                    if (char == '-') {
                        try token.append(char, allocator);
                        char = lexer.consume();
                    } else if (char == '+') {
                        try token.append(char, allocator);
                        char = lexer.consume();
                    }

                    while (char >= '0' and char <= '9') {
                        try token.append(char, allocator);
                        char = lexer.consume();
                    }
                } else if (char == '#') {
                    var char2: u32 = 4;
                    if (lexer.checkNextString("INF")) {
                        token.subtype.infinite = true;
                    } else if (lexer.checkNextString("IND")) {
                        token.subtype.indefinite = true;
                    } else if (lexer.checkNextString("NAN")) {
                        token.subtype.nan = true;
                    } else if (lexer.checkNextString("QNAN")) {
                        token.subtype.nan = true;
                        char2 += 1;
                    } else if (lexer.checkNextString("SNAN")) {
                        token.subtype.nan = true;
                        char2 += 1;
                    }

                    for (0..char2) |_| {
                        try token.append(char, allocator);
                        char = lexer.consume();
                    }

                    while (char >= '0' and char <= '9') {
                        try token.append(char, allocator);
                        char = lexer.consume();
                    }

                    if (!lexer.flags.allow_float_exceptions) {
                        try token.append(0, allocator);
                        return error.FloatExceptionsNotAllowed;
                    }
                }
            } else if (dot > 1) {
                if (!lexer.flags.allow_ip_addresses) {
                    return error.IpAddressNotAllowed;
                }

                if (dot != 3) {
                    return error.IpAddressParseError;
                }

                token.subtype = .{ .ip_address = true };
            } else {
                token.subtype = .{ .decimal = true, .integer = true };
            }
        }

        if (token.subtype.float) {
            if (char > ' ') {
                if (char == 'f' or char == 'F') {
                    token.subtype.single_precision = true;
                    _ = lexer.consume();
                } else if (char == 'l' or char == 'L') {
                    token.subtype.extended_precision = true;
                    _ = lexer.consume();
                } else {
                    token.subtype.double_precision = true;
                }
            } else {
                token.subtype.double_precision = true;
            }
        } else if (token.subtype.integer) {
            if (char > ' ') {
                for (0..2) |_| {
                    if (char == 'l' or char == 'L') {
                        token.subtype.long = true;
                    } else if (char == 'u' or char == 'U') {
                        token.subtype.unsigned = true;
                    } else break;

                    char = lexer.consume();
                }
            }
        } else if (token.subtype.ip_address) {
            if (char == ':') {
                try token.append(char, allocator);
                char = lexer.consume();
                while (char >= '0' and char <= '9') {
                    try token.append(char, allocator);
                    char = lexer.consume();
                }
                token.subtype.ip_port = true;
            }
        }
    }

    pub fn readEscapeCharacter(lexer: *Lexer) error{NotAnEscapeChar}!u8 {
        // step over the leading '\\'
        _ = lexer.consume();
        // determine the escape character
        const char: u8 = switch (lexer.current()) {
            '\\' => '\\',
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'v' => '\x0b',
            'b' => '\x08',
            'f' => '\x0c',
            'a' => '\x07',
            '\'' => '\'',
            '\"' => '\"',
            '?' => '?',
            'x' => char: {
                _ = lexer.consume();

                var i: u32 = 0;
                var val: u32 = 0;
                while (true) : ({
                    i += 1;
                    _ = lexer.consume();
                }) {
                    var c = lexer.current();
                    c = switch (c) {
                        '0'...'9' => c - '0',
                        'A'...'Z' => c - 'A' + 10,
                        'a'...'z' => c - 'a' + 10,
                        else => break,
                    };

                    val = (val << 4) + c;
                }

                _ = lexer.consumeBackward();
                if (val > 0xFF) {
                    val = 0xFF;
                }

                break :char @intCast(val);
            },
            else => char: {
                if (lexer.current() < '0' or lexer.current() > '9') {
                    return error.NotAnEscapeChar;
                }

                var i: u32 = 0;
                var val: u32 = 0;
                while (true) : ({
                    i += 1;
                    _ = lexer.consume();
                }) {
                    var c = lexer.current();
                    c = switch (c) {
                        '0'...'9' => c - '0',
                        else => break,
                    };
                    val = val * 10 + c;
                }

                _ = lexer.consumeBackward();
                if (val > 0xFF) {
                    val = 0xFF;
                }

                break :char @intCast(val);
            },
        };

        // step over the escape character or the last digit of the number
        _ = lexer.consume();

        return char;
    }

    pub fn readPunctuation(lexer: *Lexer, token: *Token, allocator: Allocator) Allocator.Error!void {
        var n = lexer.punctuation_table.?[@as(u32, lexer.script_p.?[0])];
        while (n >= 0) : (n = lexer.next_punctuation.?[@intCast(n)]) {
            const punct = &(lexer.punctuations.?[@intCast(n)]);
            const p = punct.p orelse unreachable;

            var l: u32 = 0;
            while (p[l] != 0 and lexer.nextN(l) != 0) : (l += 1) {
                if (lexer.nextN(l) != p[l]) break;
            }

            if (p[l] == 0) {
                try token.str.ensureAlloced(l + 1, false, allocator);

                for (0..l + 1) |i| {
                    token.str.buffer()[i] = p[i];
                }
                token.str.len = l;
                _ = lexer.consumeN(l);
                token.type = .punctuation;
                token.subtype = @bitCast(@as(u32, @intCast(@intFromEnum(punct.n))));
            }
        }
    }

    pub fn readWhiteSpace(lexer: *Lexer) error{EndOfStream}!void {
        while (true) {
            // skip white space
            while (lexer.current() <= ' ') {
                if (lexer.checkEndOfStream()) return error.EndOfStream;
                if (lexer.current() == '\n') {
                    lexer.line += 1;
                }

                _ = lexer.consume();
            }

            // skip comments
            if (lexer.current() == '/') {
                // comments //
                if (lexer.next() == '/') {
                    _ = lexer.consume();

                    var first = true;
                    while (lexer.current() != '\n' or first) {
                        first = false;
                        _ = lexer.consume();

                        if (lexer.checkEndOfStream()) return error.EndOfStream;
                    }

                    lexer.line += 1;

                    _ = lexer.consume();
                    if (lexer.checkEndOfStream()) return error.EndOfStream;
                    continue;
                }
                // comments /* */
                else if (lexer.next() == '*') {
                    _ = lexer.consume();

                    while (true) {
                        const char = lexer.consume();
                        if (lexer.checkEndOfStream()) return error.EndOfStream;

                        if (char == '\n') {
                            lexer.line += 1;
                        } else if (char == '/') {
                            if (lexer.prev() == '*') break;
                            if (lexer.next() == '*') {
                                std.debug.print("[WARN] nested comment\n", .{});
                            }
                        }
                    }

                    _ = lexer.consume();
                    if (lexer.checkEndOfStream()) return error.EndOfStream;

                    _ = lexer.consume();
                    if (lexer.checkEndOfStream()) return error.EndOfStream;

                    continue;
                }
            }
            break;
        }
    }

    pub const ExpectTokenStringError = error{
        NotExpectedTokenContent,
    } || ReadTokenError;
    pub fn expectTokenString(
        lexer: *Lexer,
        string: []const u8,
        allocator: Allocator,
    ) ExpectTokenStringError!void {
        var token = Token{};
        defer token.deinit(allocator);

        try lexer.readToken(&token, allocator);

        if (!std.mem.eql(u8, token.slice(), string))
            return error.NotExpectedTokenContent;
    }

    pub const ExpectTokenTypeError = error{
        NotExpectedTokenType,
        NotExpectedTokenSubtype,
    } || ReadTokenError;
    pub fn expectTokenType(
        lexer: *Lexer,
        token_type: TokenType,
        token_subtype: TokenSubtype,
        token: *Token,
        allocator: Allocator,
    ) ExpectTokenTypeError!void {
        try lexer.readToken(token, allocator);

        if (token.type != token_type) return error.NotExpectedTokenType;

        const tok_subtype_u32: u32 = @bitCast(token.subtype);
        const token_subtype_u32: u32 = @bitCast(token_subtype);
        if (token.type == .number) {
            if ((tok_subtype_u32 & token_subtype_u32) != token_subtype_u32)
                return error.NotExpectedTokenSubtype;
        } else if (token.type == .punctuation) {
            if (tok_subtype_u32 != token_subtype_u32)
                return error.NotExpectedTokenSubtype;
        }
    }

    const ParseSizeError = ParseIntError || error{IntLtZero};

    pub fn parseSize(lexer: *Lexer, allocator: Allocator) ParseSizeError!usize {
        const count = try lexer.parseInt(allocator);
        if (count < 0) return error.IntLtZero;

        return @intCast(count);
    }

    pub const Parse1DMatrixError = ExpectTokenStringError || ParseFloatError;
    pub fn parse1DMatrix(
        lexer: *Lexer,
        slice: []f32,
        allocator: Allocator,
    ) Parse1DMatrixError!void {
        try lexer.expectTokenString("(", allocator);

        for (slice) |*elem| {
            elem.* = try lexer.parseFloat(allocator);
        }

        try lexer.expectTokenString(")", allocator);
    }

    pub fn parse2DMatrix(
        lexer: *Lexer,
        y: u32,
        x: u32,
        slice: []f32,
        allocator: Allocator,
    ) Parse1DMatrixError!void {
        try lexer.expectTokenString("(", allocator);

        for (0..y) |i| {
            try lexer.parse1DMatrix(slice[i * x ..][0..x], allocator);
        }

        try lexer.expectTokenString(")", allocator);
    }

    pub const ParseIntError = error{
        TokenIsNotANumber,
        TokenIsNotAnInteger,
    } || ReadTokenError || ExpectTokenTypeError;

    pub fn parseInt(lexer: *Lexer, allocator: Allocator) ParseIntError!i32 {
        var token = Token{};
        defer token.deinit(allocator);

        try lexer.readToken(&token, allocator);
        if (token.getType() == .punctuation and
            std.mem.eql(u8, token.slice(), "-"))
        {
            try lexer.expectTokenType(
                .number,
                .{ .integer = true },
                &token,
                allocator,
            );
            return -token.getIntValue();
        } else if (token.getType() != .number)
            return if (token.getSubtype().float)
                error.TokenIsNotAnInteger
            else
                error.TokenIsNotANumber;

        return token.getIntValue();
    }

    pub const ParseFloatError = error{
        TokenIsNotANumber,
    } || ReadTokenError || ExpectTokenTypeError;

    pub fn parseFloat(lexer: *Lexer, allocator: Allocator) ParseFloatError!f32 {
        var token = Token{};
        defer token.deinit(allocator);

        try lexer.readToken(&token, allocator);
        if (token.getType() == .punctuation and
            std.mem.eql(u8, token.slice(), "-"))
        {
            try lexer.expectTokenType(.number, .{}, &token, allocator);
            return -token.getFloatValue();
        } else if (token.getType() != .number)
            return error.TokenIsNotANumber;

        return token.getFloatValue();
    }

    pub fn checkTokenType(
        lexer: *Lexer,
        token_type: TokenType,
        token_subtype: TokenSubtype,
        token: *Token,
        allocator: Allocator,
    ) Allocator.Error!bool {
        var tok = Token{};
        defer tok.deinit(allocator);

        lexer.readToken(&tok, allocator) catch return false;

        const tok_subtype_u32: u32 = @bitCast(tok.subtype);
        const token_subtype_u32: u32 = @bitCast(token_subtype);
        // if the type matches
        if (tok.type == token_type and
            (tok_subtype_u32 & token_subtype_u32) == token_subtype_u32)
        {
            try token.assignToken(&tok, allocator);
            return true;
        }

        // unread token
        lexer.script_p = lexer.last_script_p;
        lexer.line = lexer.last_line;
        return false;
    }

    pub fn checkTokenString(
        lexer: *Lexer,
        string: []const u8,
        allocator: Allocator,
    ) Allocator.Error!bool {
        var token = Token{};
        defer token.deinit(allocator);

        lexer.readToken(&token, allocator) catch return false;

        if (token.eql(string)) return true;

        // unread token
        lexer.script_p = lexer.last_script_p;
        lexer.line = lexer.last_line;
        return false;
    }

    pub fn skipUntilString(
        lexer: *Lexer,
        str: []const u8,
        allocator: Allocator,
    ) ReadTokenError!void {
        var token = Token{};
        defer token.deinit(allocator);

        while (true) {
            try lexer.readToken(&token, allocator);
            if (std.mem.eql(u8, token.slice(), str)) break;
        }
    }

    pub const ReadOnLineError = error{NoTokenOnLine} || Allocator.Error;
    pub fn readTokenOnLine(
        lexer: *Lexer,
        token: *Token,
        allocator: Allocator,
    ) ReadOnLineError!void {
        var tok = Token{};
        defer tok.deinit(allocator);

        lexer.readToken(&tok, allocator) catch {
            lexer.script_p = lexer.last_script_p;
            lexer.line = lexer.last_line;

            return error.NoTokenOnLine;
        };

        if (tok.lines_crossed != 0) {
            lexer.script_p = lexer.last_script_p;
            lexer.line = lexer.last_line;
            token.str.empty();

            return error.NoTokenOnLine;
        }

        try token.assignToken(&tok, allocator);
    }

    pub fn parseRestOfLine(
        lexer: *Lexer,
        out: *idlib.Str,
        allocator: Allocator,
    ) Allocator.Error!void {
        var tok = Token{};
        defer tok.deinit(allocator);

        out.empty();
        while (true) {
            lexer.readToken(&tok, allocator) catch break;

            if (tok.lines_crossed != 0) {
                lexer.script_p = lexer.last_script_p;
                lexer.line = lexer.last_line;
                break;
            }

            if (out.len != 0) {
                try out.appendSlice(" ", allocator);
            }
            try out.appendSlice(tok.slice(), allocator);
        }
    }

    pub fn skipRestOfLine(
        lexer: *Lexer,
        allocator: Allocator,
    ) ReadTokenError!void {
        var tok = Token{};
        defer tok.deinit(allocator);

        while (true) {
            try lexer.readToken(&tok, allocator);

            if (tok.lines_crossed != 0) {
                lexer.script_p = lexer.last_script_p;
                lexer.line = lexer.last_line;
                return;
            }
        }
    }
};
