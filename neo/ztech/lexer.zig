const idlib = @import("idlib.zig");
const std = @import("std");
const token_ = @import("token.zig");
const Token = token_.Token;
const TokenType = token_.Type;
const TokenSubtype = token_.Subtype;

pub const Flags = struct {
    pub const LEXFL_NOERRORS: c_int = 1;
    pub const LEXFL_NOWARNINGS: c_int = 2;
    pub const LEXFL_NOFATALERRORS: c_int = 4;
    pub const LEXFL_NOSTRINGCONCAT: c_int = 8;
    pub const LEXFL_NOSTRINGESCAPECHARS: c_int = 16;
    pub const LEXFL_NODOLLARPRECOMPILE: c_int = 32;
    pub const LEXFL_NOBASEINCLUDES: c_int = 64;
    pub const LEXFL_ALLOWPATHNAMES: c_int = 128;
    pub const LEXFL_ALLOWNUMBERNAMES: c_int = 256;
    pub const LEXFL_ALLOWIPADDRESSES: c_int = 512;
    pub const LEXFL_ALLOWFLOATEXCEPTIONS: c_int = 1024;
    pub const LEXFL_ALLOWMULTICHARLITERALS: c_int = 2048;
    pub const LEXFL_ALLOWBACKSLASHSTRINGCONCAT: c_int = 4096;
    pub const LEXFL_ONLYSTRINGS: c_int = 8192;
};

pub const Punctuation = extern struct {
    p: ?[*]const u8,
    n: c_int,
};

pub const Lexer = extern struct {
    loaded: c_int,
    filename: idlib.idStr,
    allocated: c_int,
    buffer: [*:0]const u8,
    script_p: [*]const u8,
    end_p: [*]const u8,
    lastScript_p: [*]const u8,
    whiteSpaceStart_p: [*]const u8,
    whiteSpaceEnd_p: [*]const u8,
    fileTime: idlib.ID_TIME_T,
    length: c_int,
    line: c_int,
    lastline: c_int,
    initialLine: c_int,
    tokenavailable: c_int,
    flags: c_int,
    punctuations: ?[*]Punctuation,
    punctuationtable: ?[*]c_int,
    nextpunctuation: ?*c_int,
    token: Token,
    next: ?*Lexer,
    hadError: bool,

    extern fn c_lexer_create() *Lexer;
    extern fn c_lexer_createFromFile([*:0]const u8, flags: c_int) *Lexer;
    extern fn c_lexer_destroy(*Lexer) void;
    extern fn c_lexer_readToken(*Lexer, *Token) bool;
    extern fn c_lexer_isLoaded(*Lexer) bool;
    extern fn c_lexer_expectTokenType(*Lexer, c_int, c_int, *Token) bool;
    extern fn c_lexer_loadMemory(*Lexer, [*:0]const u8, c_int, [*:0]const u8, c_int) bool;

    pub fn loadMemory(
        lexer: *Lexer,
        text: [:0]const u8,
        name: [:0]const u8,
        start_line: usize,
    ) bool {
        return c_lexer_loadMemory(
            lexer,
            text.ptr,
            @intCast(text.len),
            name.ptr,
            @intCast(start_line),
        );
    }

    pub fn initEmpty() *Lexer {
        return c_lexer_create();
    }

    pub fn init(path: [:0]const u8, flags: c_int) *Lexer {
        return c_lexer_createFromFile(path.ptr, flags);
    }

    pub fn deinit(lexer: *Lexer) void {
        c_lexer_destroy(lexer);
    }

    pub fn isLoaded(lexer: *Lexer) bool {
        return c_lexer_isLoaded(lexer);
    }

    pub fn readToken(lexer: *Lexer, token: *Token) bool {
        return c_lexer_readToken(lexer, token);
    }

    pub const ExpectTokenError = error{
        CouldntFindExpectedToken,
        NotExpectedToken,
    };

    pub fn expectAnyToken(lexer: *Lexer, token: *Token) error{CouldntFindExpectedToken}!void {
        if (!lexer.readToken(token))
            return error.CouldntFindExpectedToken;
    }

    pub fn expectTokenString(lexer: *Lexer, string: []const u8) ExpectTokenError!void {
        var token = Token.init();
        defer token.deinit();

        if (!lexer.readToken(token))
            return error.CouldntFindExpectedToken;
        if (!std.mem.eql(u8, token.slice(), string))
            return error.NotExpectedToken;
    }

    pub fn expectTokenType(lexer: *Lexer, token_type: c_int, token_subtype: c_int, token: *Token) error{NotExpectedToken}!void {
        if (!c_lexer_expectTokenType(
            lexer,
            token_type,
            token_subtype,
            token,
        )) return error.NotExpectedToken;
    }

    const ParseSizeError = ParseIntError || error{IntLtZero};

    pub fn parseSize(lexer: *Lexer) ParseSizeError!usize {
        const count = try lexer.parseInt();
        if (count < 0) return error.IntLtZero;

        return @intCast(count);
    }

    pub fn parse1DMatrix(lexer: *Lexer, slice: []f32) !void {
        try lexer.expectTokenString("(");

        for (slice) |*elem| {
            elem.* = try lexer.parseFloat();
        }

        try lexer.expectTokenString(")");
    }

    const ParseIntError = error{
        CouldntReadToken,
        TokenIsNotANumber,
        TokenIsNotAnInteger,
        NotExpectedToken,
    };

    pub fn parseInt(lexer: *Lexer) ParseIntError!c_int {
        var token = Token.init();
        defer token.deinit();

        if (!lexer.readToken(token)) return error.CouldntReadToken;
        if (token.getType() == TokenType.TT_PUNCTUATION and
            std.mem.eql(u8, token.slice(), "-"))
        {
            try lexer.expectTokenType(
                TokenType.TT_NUMBER,
                TokenSubtype.TT_INTEGER,
                token,
            );
            return -token.getIntValue();
        } else if (token.getType() != TokenType.TT_NUMBER)
            return if (token.getSubtype() == TokenSubtype.TT_FLOAT)
                error.TokenIsNotAnInteger
            else
                error.TokenIsNotANumber;

        return token.getIntValue();
    }

    const ParseFloatError = error{
        CouldntReadToken,
        TokenIsNotANumber,
        NotExpectedToken,
    };

    pub fn parseFloat(lexer: *Lexer) ParseFloatError!f32 {
        var token = Token.init();
        defer token.deinit();

        if (!lexer.readToken(token)) return error.CouldntReadToken;
        if (token.getType() == TokenType.TT_PUNCTUATION and
            std.mem.eql(u8, token.slice(), "-"))
        {
            try lexer.expectTokenType(TokenType.TT_NUMBER, 0, token);
            return -token.getFloatValue();
        } else if (token.getType() != TokenType.TT_NUMBER)
            return error.TokenIsNotANumber;

        return token.getFloatValue();
    }

    pub fn checkTokenType(
        lexer: *Lexer,
        token_type: c_int,
        token_subtype: c_int,
        token: *Token,
    ) bool {
        const tok = Token.init();
        defer tok.deinit();

        if (!lexer.readToken(tok)) return false;
        // if the type matches
        if (tok.type == token_type and (tok.subtype & token_subtype) == token_subtype) {
            token.assignToken(tok);
            return true;
        }

        // unread token
        lexer.script_p = lexer.lastScript_p;
        lexer.line = lexer.lastline;
        return false;
    }
};
