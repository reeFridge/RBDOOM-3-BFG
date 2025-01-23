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
            token.calculateNumberValue();

        return token.int_value;
    }

    pub fn getDoubleValue(token: *Token) f64 {
        if (token.type != .number) return 0;

        if (!token.subtype.values_valid)
            token.calculateNumberValue();

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

    fn calculateNumberValue(token: *Token) void {
        std.debug.assert(token.type == .number);
        const str = token.slice();
        token.float_value = 0;
        token.int_value = 0;

        if (token.subtype.float) {
            if (token.subtype.infinite or
                token.subtype.indefinite or
                token.subtype.nan)
            {
                if (token.subtype.infinite) {
                    var inf: u32 = 0x7f800000;
                    token.float_value = @floatCast(@as([*c]f32, @ptrCast(@alignCast(&inf))).*);
                } else if (token.subtype.indefinite) {
                    var ind: u32 = 0xffc00000;
                    token.float_value = @floatCast(@as([*c]f32, @ptrCast(@alignCast(&ind))).*);
                } else if (token.subtype.nan) {
                    var nan: u32 = 0x7fc00000;
                    token.float_value = @floatCast(@as([*c]f32, @ptrCast(@alignCast(&nan))).*);
                }
            } else {
                var index: u32 = 0;
                while (index < str.len) : (index += 1) {
                    const char = str[index];
                    if (char == '.' or char == 'e') break;

                    token.float_value = token.float_value * 10 + @as(f64, @floatFromInt(char - '0'));
                }

                if (index < str.len and str[index] == '.') {
                    index += 1;

                    var m: f64 = 0.1;
                    while (index < str.len) : (index += 1) {
                        const char = str[index];
                        if (char == 'e') break;

                        token.float_value = token.float_value + @as(f64, @floatFromInt(char - '0')) * m;
                        m *= 0.1;
                    }
                }

                if (index < str.len and str[index] == 'e') {
                    index += 1;

                    var div: bool = false;
                    if (index < str.len and str[index] == '-') {
                        div = true;
                        index += 1;
                    } else if (index < str.len and str[index] == '+') {
                        div = false;
                        index += 1;
                    } else {
                        div = false;
                    }

                    var pow: u32 = 0;

                    while (index < str.len) : (index += 1) {
                        pow = pow * 10 + (str[index] - '0');
                    }
                    var m: f64 = 1.0;
                    for (0..pow) |_| {
                        m *= 10;
                    }

                    if (div)
                        token.float_value /= m
                    else
                        token.float_value *= m;
                }
            }

            token.int_value = @intFromFloat(token.float_value);
        } else if (token.subtype.decimal) {
            for (str) |char| {
                token.int_value = token.int_value * 10 + (char - '0');
            }

            token.float_value = @floatFromInt(token.int_value);
        } else if (token.subtype.ip_address) {
            // TODO
            unreachable;
        } else if (token.subtype.octal) {
            // first is zero
            var index: u32 = 1;
            while (index < str.len) : (index += 1) {
                token.int_value = (token.int_value << 3) + (str[index] - '0');
            }

            token.float_value = @floatFromInt(token.int_value);
        } else if (token.subtype.hex) {
            // TODO
            unreachable;
        } else if (token.subtype.binary) {
            // TODO
            unreachable;
        }

        token.subtype.values_valid = true;
    }
};
