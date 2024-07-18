const std = @import("std");
const Token = @import("token.zig");

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

const Lexer = @This();

lexer_ptr: *anyopaque, // idLexer

extern fn c_lexer_create([*:0]const u8, flags: c_int) callconv(.C) *anyopaque;
extern fn c_lexer_destroy(*anyopaque) callconv(.C) void;
extern fn c_lexer_readToken(*anyopaque, *anyopaque) callconv(.C) bool;
extern fn c_lexer_isLoaded(*anyopaque) callconv(.C) bool;
extern fn c_lexer_expectTokenType(*anyopaque, c_int, c_int, *anyopaque) callconv(.C) bool;

pub fn init(path: [:0]const u8, flags: c_int) Lexer {
    return .{
        .lexer_ptr = c_lexer_create(path.ptr, flags),
    };
}

pub fn isLoaded(lexer: Lexer) bool {
    return c_lexer_isLoaded(lexer.lexer_ptr);
}

pub fn readToken(lexer: *Lexer, token: *Token) bool {
    return c_lexer_readToken(lexer.lexer_ptr, token.token_ptr);
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

    if (!lexer.readToken(&token))
        return error.CouldntFindExpectedToken;
    if (!std.mem.eql(u8, token.slice(), string))
        return error.NotExpectedToken;
}

pub fn expectTokenType(lexer: *Lexer, token_type: c_int, token_subtype: c_int, token: *Token) error{NotExpectedToken}!void {
    if (!c_lexer_expectTokenType(
        lexer.lexer_ptr,
        token_type,
        token_subtype,
        token.token_ptr,
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

    if (!lexer.readToken(&token)) return error.CouldntReadToken;
    if (token.getType() == Token.Type.TT_PUNCTUATION and
        std.mem.eql(u8, token.slice(), "-"))
    {
        try lexer.expectTokenType(Token.Type.TT_NUMBER, Token.Subtype.TT_INTEGER, &token);
        return -token.getIntValue();
    } else if (token.getType() != Token.Type.TT_NUMBER)
        return if (token.getSubtype() == Token.Subtype.TT_FLOAT)
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

    if (!lexer.readToken(&token)) return error.CouldntReadToken;
    if (token.getType() == Token.Type.TT_PUNCTUATION and
        std.mem.eql(u8, token.slice(), "-"))
    {
        try lexer.expectTokenType(Token.Type.TT_NUMBER, 0, &token);
        return -token.getFloatValue();
    } else if (token.getType() != Token.Type.TT_NUMBER)
        return error.TokenIsNotANumber;

    return token.getFloatValue();
}

pub fn deinit(lexer: *Lexer) void {
    c_lexer_destroy(lexer.lexer_ptr);
}
