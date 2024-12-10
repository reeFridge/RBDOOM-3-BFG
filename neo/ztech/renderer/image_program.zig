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
        parse_buffer.append(" ") catch unreachable;
    }

    parse_buffer.append(token_slice) catch unreachable;
}

fn matchAndAppendToken(lexer: *Lexer, match: []const u8) void {
    lexer.expectTokenString(match) catch return;

    parse_buffer.append(match) catch unreachable;
}

pub const ParseImageProgramError =
    error{OutOfMemory} ||
    Lexer.ReadTokenError;
fn parseImageProgramRecursive(
    lexer: *Lexer,
    pic: ?[*][*]u8,
    width: ?*u32,
    height: ?*u32,
    timestamps: ?[*]idlib.ID_TIME_T,
    usage: ?*TextureUsage,
) ParseImageProgramError!bool {
    var token = Token{};
    token.initEmpty();
    defer token.deinit();

    var timestamp: idlib.ID_TIME_T = -1;

    try lexer.readToken(&token);

    if (token.eql("_black")) {
        try token.base.assignSlice("textures/black");
    } else if (token.eql("_white")) {
        try token.base.assignSlice("guis/assets/white");
    }

    if (token.ieql("heightmap")) {
        // TODO
        return true;
    }

    if (token.ieql("addnormals")) {
        // TODO
        return true;
    }

    if (token.ieql("smoothnormals")) {
        // TODO
        return true;
    }

    if (token.ieql("add")) {
        // TODO
        return true;
    }

    if (token.ieql("scale")) {
        // TODO
        return true;
    }

    if (token.ieql("invertGreen")) {
        // TODO
        return true;
    }

    if (token.ieql("invertColor")) {
        // TODO
        return true;
    }

    if (token.ieql("makeIntensity")) {
        // TODO
        return true;
    }

    if (token.ieql("makeAlpha")) {
        // TODO
        return true;
    }

    if (token.ieql("combineRgba")) {
        // TODO
        return true;
    }

    if (timestamps == null and pic == null) return true;

    loadImage(
        token.slice(),
        pic,
        width,
        height,
        &timestamp,
        true,
        usage,
    );

    if (timestamp == -1) return false;

    if (timestamps) |timestamps_| {
        if (timestamp > timestamps_[0]) {
            timestamps_[0] = timestamp;
        }
    }

    return true;
}

fn loadImage(
    path: []const u8,
    pic: ?[*][*]u8,
    width: ?*u32,
    height: ?*u32,
    timestamp: *idlib.ID_TIME_T,
    make_power_of_2: bool,
    usage: ?*TextureUsage,
) void {
    _ = path;
    _ = pic;
    _ = width;
    _ = height;
    _ = timestamp;
    _ = make_power_of_2;
    _ = usage;

    return;
}

pub fn parsePastImageProgram(lexer: *Lexer) ParseImageProgramError![]const u8 {
    parse_buffer.len = 0;

    _ = try parseImageProgramRecursive(lexer, null, null, null, null, null);

    return parse_buffer.constSlice();
}
