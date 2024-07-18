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

const Token = @This();

token_ptr: *anyopaque,

extern fn c_token_create() callconv(.C) *anyopaque;
extern fn c_token_destroy(*anyopaque) callconv(.C) void;
extern fn c_token_cStr(*anyopaque) callconv(.C) [*:0]const u8;
extern fn c_token_calculateNumberValue(*anyopaque) callconv(.C) void;
extern fn c_token_type(*anyopaque) callconv(.C) c_int;
extern fn c_token_subtype(*anyopaque) callconv(.C) c_int;
extern fn c_token_intvalue(*anyopaque) callconv(.C) c_uint;
extern fn c_token_floatvalue(*anyopaque) callconv(.C) f64;

pub fn init() Token {
    return .{
        .token_ptr = c_token_create(),
    };
}

pub fn slice(token: Token) []const u8 {
    const c_str = c_token_cStr(token.token_ptr);
    return std.mem.span(c_str);
}

pub fn getUintValue(token: *Token) c_uint {
    if (token.getType() != Token.Type.TT_NUMBER) return 0;

    if ((token.getSubtype() & Token.Subtype.TT_VALUESVALID) == 0)
        c_token_calculateNumberValue(token.token_ptr);

    return c_token_intvalue(token.token_ptr);
}

pub fn getDoubleValue(token: *Token) f64 {
    if (token.getType() != Token.Type.TT_NUMBER) return 0;

    if ((token.getSubtype() & Token.Subtype.TT_VALUESVALID) == 0)
        c_token_calculateNumberValue(token.token_ptr);

    return c_token_floatvalue(token.token_ptr);
}

pub fn getFloatValue(token: *Token) f32 {
    return @floatCast(token.getDoubleValue());
}

pub fn getIntValue(token: *Token) c_int {
    return @intCast(token.getUintValue());
}

pub fn getType(token: Token) c_int {
    return c_token_type(token.token_ptr);
}

pub fn getSubtype(token: Token) c_int {
    return c_token_subtype(token.token_ptr);
}

pub fn deinit(token: *Token) void {
    c_token_destroy(token.token_ptr);
}
