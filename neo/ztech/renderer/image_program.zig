const std = @import("std");
const lexer_ = @import("../lexer.zig");
const Lexer = lexer_.Lexer;
const token_ = @import("../token.zig");
const Token = token_.Token;
const TextureUsage = @import("image.zig").TextureUsage;
const idlib = @import("../idlib.zig");
const max_image_name = @import("image.zig").max_image_name;

var parse_buffer = std.BoundedArray(u8, max_image_name).init(0) catch unreachable;

fn appendToken(token_slice: []const u8) void {
    if (parse_buffer.constSlice().len > 0) {
        parse_buffer.appendSlice(" ") catch unreachable;
    }

    parse_buffer.appendSlice(token_slice) catch unreachable;
}

fn matchAndAppendToken(lexer: *Lexer, match: []const u8) void {
    lexer.expectTokenString(match) catch return;
    parse_buffer.appendSlice(match) catch unreachable;
}

extern fn R_HeightmapToNormalMap([*]u8, u32, u32, f32) void;
extern fn R_AddNormalMaps([*]u8, u32, u32, [*]u8, u32, u32) void;

pub const ParseImageProgramError =
    std.mem.Allocator.Error ||
    Lexer.ReadTokenError;

const ParseState = struct {
    const Image = struct {
        data: []u8,
        width: u32,
        height: u32,
    };

    opt_image: ?Image = null,
    opt_timestamp: ?idlib.ID_TIME_T = null,
    opt_usage: ?TextureUsage = null,
};

fn parseRecursive(
    lexer: *Lexer,
) ParseImageProgramError!void {
    var token = Token{};
    token.initEmpty();
    defer token.deinit();

    try lexer.readToken(&token);

    if (token.eql("_black")) {
        try token.base.assignSlice("textures/black");
    } else if (token.eql("_white")) {
        try token.base.assignSlice("guis/assets/white");
    }

    appendToken(token.slice());

    if (token.ieql("heightmap")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ",");
        try lexer.readToken(&token);
        appendToken(token.slice());
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("addnormals")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ",");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("smoothnormals")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("add")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ",");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("scale")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        for (0..4) |_| {
            matchAndAppendToken(lexer, ",");
            try lexer.readToken(&token);
            appendToken(token.slice());
        }
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("invertAlpha")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("invertGreen")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("invertColor")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("makeIntensity")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("makeAlpha")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("combineRgba")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ",");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ",");
        try parseRecursive(lexer);
        matchAndAppendToken(lexer, ")");

        return;
    }
}

const ImageData = struct {
    data: []u8,
    width: u32,
    height: u32,
    timestamp: idlib.ID_TIME_T,
    usage: TextureUsage,
};

const LoadImageError = error{};
fn loadImage(
    path: []const u8,
    make_power_of_2: bool,
) LoadImageError!ImageData {
    _ = path;
    _ = make_power_of_2;

    return std.mem.zeroes(ImageData);
}

pub fn parse(lexer: *Lexer) ParseImageProgramError![]const u8 {
    parse_buffer.len = 0;
    try parseRecursive(lexer);
    return parse_buffer.constSlice();
}
