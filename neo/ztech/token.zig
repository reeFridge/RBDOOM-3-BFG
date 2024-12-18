const idlib = @import("idlib.zig");
const std = @import("std");

pub const Type = enum(c_int) {
    unknown = 0,
    string = 1,
    literal = 2,
    number = 3,
    name = 4,
    punctuation = 5,
};

pub const Subtype = packed struct(u32) {
    integer: bool = false,
    decimal: bool = false,
    hex: bool = false,
    octal: bool = false,
    binary: bool = false,
    long: bool = false,
    unsigned: bool = false,
    float: bool = false,
    single_precision: bool = false,
    double_precision: bool = false,
    extended_precision: bool = false,
    infinite: bool = false,
    indefinite: bool = false,
    nan: bool = false,
    ip_address: bool = false,
    ip_port: bool = false,
    values_valid: bool = false,
    reserved_: u15 = 0,
};

pub const Token = extern struct {
    const Allocator = std.mem.Allocator;

    str: idlib.Str = .{},
    type: Type = .unknown,
    subtype: Subtype = .{},
    line: u32 = 0,
    lines_crossed: u32 = 0,
    flags: u32 = 0,
    int_value: u32 = 0,
    float_value: f64 = 0,
    white_space_start_p: ?[*]const u8 = null,
    white_space_end_p: ?[*]const u8 = null,
    next: ?*Token = null,

    extern fn c_token_calculateNumberValue(*Token) void;

    pub fn deinit(token: *Token, allocator: Allocator) void {
        token.str.deinit(allocator);
    }

    pub fn slice(token: *const Token) []const u8 {
        return token.str.constSlice();
    }

    pub inline fn ieql(token: *const Token, s: []const u8) bool {
        return std.ascii.eqlIgnoreCase(token.str.constSlice(), s);
    }

    pub inline fn eql(token: *const Token, s: []const u8) bool {
        return std.mem.eql(u8, token.str.constSlice(), s);
    }

    pub fn append(
        token: *Token,
        char: u8,
        allocator: Allocator,
    ) Allocator.Error!void {
        try token.str.ensureAlloced(token.str.len + 1, true, allocator);
        token.str.buffer()[token.str.len] = char;
        token.str.len += 1;
    }

    pub fn assignToken(
        token: *Token,
        from_token: *const Token,
        allocator: Allocator,
    ) Allocator.Error!void {
        token.str.deinit(allocator);

        token.* = from_token.*;
        token.str = .{};

        try token.str.assignSlice(from_token.slice(), allocator);
    }

    pub fn getUintValue(token: *Token) u32 {
        if (token.type != .number) return 0;

        if (!token.subtype.values_valid)
            c_token_calculateNumberValue(token);

        return token.int_value;
    }

    pub fn getDoubleValue(token: *Token) f64 {
        if (token.type != .number) return 0;

        if (!token.subtype.values_valid)
            c_token_calculateNumberValue(token);

        return token.float_value;
    }

    pub fn getFloatValue(token: *Token) f32 {
        return @floatCast(token.getDoubleValue());
    }

    pub fn getIntValue(token: *Token) i32 {
        return @intCast(token.getUintValue());
    }

    pub fn getType(token: *const Token) Type {
        return token.type;
    }

    pub fn getSubtype(token: *const Token) Subtype {
        return token.subtype;
    }
};
