const idlib = @import("idlib.zig");
const std = @import("std");

pub const Type = struct {
    pub const TT_STRING = @as(c_int, 1);
    pub const TT_LITERAL = @as(c_int, 2);
    pub const TT_NUMBER = @as(c_int, 3);
    pub const TT_NAME = @as(c_int, 4);
    pub const TT_PUNCTUATION = @as(c_int, 5);
};

pub const Subtype = struct {
    pub const TT_INTEGER = @as(c_int, 0x00001);
    pub const TT_DECIMAL = @as(c_int, 0x00002);
    pub const TT_HEX = @as(c_int, 0x00004);
    pub const TT_OCTAL = @as(c_int, 0x00008);
    pub const TT_BINARY = @as(c_int, 0x00010);
    pub const TT_LONG = @as(c_int, 0x00020);
    pub const TT_UNSIGNED = @as(c_int, 0x00040);
    pub const TT_FLOAT = @as(c_int, 0x00080);
    pub const TT_SINGLE_PRECISION = @as(c_int, 0x00100);
    pub const TT_DOUBLE_PRECISION = @as(c_int, 0x00200);
    pub const TT_EXTENDED_PRECISION = @as(c_int, 0x00400);
    pub const TT_INFINITE = @as(c_int, 0x00800);
    pub const TT_INDEFINITE = @as(c_int, 0x01000);
    pub const TT_NAN = @as(c_int, 0x02000);
    pub const TT_IPADDRESS = @as(c_int, 0x04000);
    pub const TT_IPPORT = @import("std").zig.c_translation.promoteIntLiteral(
        c_int,
        0x08000,
        .hex,
    );
    pub const TT_VALUESVALID = @import("std").zig.c_translation.promoteIntLiteral(
        c_int,
        0x10000,
        .hex,
    );
};

pub const Token = extern struct {
    base: idlib.idStr,
    type: c_int,
    subtype: c_int,
    line: c_int,
    linesCrossed: c_int,
    flags: c_int,
    intvalue: c_uint,
    floatvalue: f64,
    whiteSpaceStart_p: ?[*]const u8,
    whiteSpaceEnd_p: ?[*]const u8,
    next: ?*Token,

    extern fn c_token_create() *Token;
    extern fn c_token_destroy(*Token) void;
    extern fn c_token_cStr(*const Token) [*:0]const u8;
    extern fn c_token_calculateNumberValue(*Token) void;
    extern fn c_token_type(*Token) c_int;
    extern fn c_token_subtype(*Token) c_int;
    extern fn c_token_intvalue(*Token) c_uint;
    extern fn c_token_floatvalue(*Token) f64;

    pub fn init() *Token {
        return c_token_create();
    }

    pub fn slice(token: *const Token) [:0]const u8 {
        const c_str = c_token_cStr(token);
        return std.mem.span(c_str);
    }

    pub fn assignToken(token: *Token, tok: *const Token) void {
        var token_str = token.base;
        token_str.assignSlice(tok.slice()) catch unreachable;

        token.* = tok.*;
        token.base = token_str;
    }

    pub fn getUintValue(token: *Token) c_uint {
        if (token.getType() != Type.TT_NUMBER) return 0;

        if ((token.getSubtype() & Subtype.TT_VALUESVALID) == 0)
            c_token_calculateNumberValue(token);

        return c_token_intvalue(token);
    }

    pub fn getDoubleValue(token: *Token) f64 {
        if (token.getType() != Type.TT_NUMBER) return 0;

        if ((token.getSubtype() & Subtype.TT_VALUESVALID) == 0)
            c_token_calculateNumberValue(token);

        return c_token_floatvalue(token);
    }

    pub fn getFloatValue(token: *Token) f32 {
        return @floatCast(token.getDoubleValue());
    }

    pub fn getIntValue(token: *Token) c_int {
        return @intCast(token.getUintValue());
    }

    pub fn getType(token: *Token) c_int {
        return c_token_type(token);
    }

    pub fn getSubtype(token: *Token) c_int {
        return c_token_subtype(token);
    }

    pub fn deinit(token: *Token) void {
        c_token_destroy(token);
    }
};
