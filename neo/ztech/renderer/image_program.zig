const std = @import("std");
const fs = @import("../framework/file_system.zig");
const lexer_ = @import("../lexer.zig");
const Lexer = lexer_.Lexer;
const token_ = @import("../token.zig");
const Token = token_.Token;
const TextureUsage = @import("image.zig").TextureUsage;
const idlib = @import("../idlib.zig");
const image = @import("image.zig");
const Allocator = std.mem.Allocator;

var parse_buffer = std.BoundedArray(u8, image.max_image_name).init(0) catch unreachable;

fn appendToken(token_slice: []const u8) void {
    if (parse_buffer.constSlice().len > 0) {
        parse_buffer.appendSlice(" ") catch unreachable;
    }

    parse_buffer.appendSlice(token_slice) catch unreachable;
}

fn matchAndAppendToken(lexer: *Lexer, match: []const u8, allocator: Allocator) void {
    lexer.expectTokenString(match, allocator) catch return;
    parse_buffer.appendSlice(match) catch unreachable;
}

extern fn R_HeightmapToNormalMap([*]u8, u32, u32, f32) void;
extern fn R_AddNormalMaps([*]u8, u32, u32, [*]u8, u32, u32) void;
extern fn R_SmoothNormalMap([*]u8, u32, u32) void;
extern fn R_ImageAdd([*]u8, u32, u32, [*]u8, u32, u32) void;
extern fn R_ImageScale([*]u8, u32, u32, *[4]f32) void;
extern fn R_InvertAlpha([*]u8, u32, u32) void;
extern fn R_InvertGreen([*]u8, u32, u32) void;
extern fn R_InvertColor([*]u8, u32, u32) void;
extern fn R_CombineRgba([*]u8, u32, u32, [*]u8, u32, u32, [*]u8, u32, u32) void;

pub const ParseImageProgramError =
    Allocator.Error ||
    Lexer.ReadTokenError;

const LoadImageResult = struct {
    const Image = struct {
        data: []u8,
        width: u32,
        height: u32,
    };

    image: Image,
    timestamp: idlib.Time,
};

pub const ParseAndLoadError =
    LoadImageError ||
    ParseImageProgramError;
fn parseRecursiveAndLoad(
    lexer: *Lexer,
    usage: *TextureUsage,
    allocator: Allocator,
) ParseAndLoadError!LoadImageResult {
    var token = Token{};
    defer token.deinit(allocator);

    try lexer.readToken(&token, allocator);

    if (token.eql("_black")) {
        try token.str.assignSlice("textures/black", allocator);
    } else if (token.eql("_white")) {
        try token.str.assignSlice("guis/assets/white", allocator);
    }

    appendToken(token.slice());

    if (token.ieql("heightmap")) {
        matchAndAppendToken(lexer, "(", allocator);
        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg.image.data);
        matchAndAppendToken(lexer, ",", allocator);

        try lexer.readToken(&token, allocator);
        appendToken(token.slice());
        const scale = token.getFloatValue();

        matchAndAppendToken(lexer, ")", allocator);

        R_HeightmapToNormalMap(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
            scale,
        );
        usage.* = .bump;

        return arg;
    }

    if (token.ieql("addnormals")) {
        matchAndAppendToken(lexer, "(", allocator);
        const arg_0 = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg_0.image.data);

        matchAndAppendToken(lexer, ",", allocator);

        const arg_1 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_1.image.data);
        matchAndAppendToken(lexer, ")", allocator);

        R_AddNormalMaps(
            arg_0.image.data.ptr,
            arg_0.image.width,
            arg_0.image.height,
            arg_1.image.data.ptr,
            arg_1.image.width,
            arg_1.image.height,
        );
        usage.* = .bump;

        return arg_0;
    }

    if (token.ieql("smoothnormals")) {
        matchAndAppendToken(lexer, "(", allocator);

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        R_SmoothNormalMap(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );
        usage.* = .bump;

        return arg;
    }

    if (token.ieql("add")) {
        matchAndAppendToken(lexer, "(", allocator);
        const arg_0 = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg_0.image.data);

        matchAndAppendToken(lexer, ",", allocator);

        const arg_1 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_1.image.data);
        matchAndAppendToken(lexer, ")", allocator);

        R_ImageAdd(
            arg_0.image.data.ptr,
            arg_0.image.width,
            arg_0.image.height,
            arg_1.image.data.ptr,
            arg_1.image.width,
            arg_1.image.height,
        );

        return arg_0;
    }

    if (token.ieql("scale")) {
        matchAndAppendToken(lexer, "(", allocator);
        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg.image.data);

        var scale: [4]f32 = undefined;
        for (0..4) |i| {
            matchAndAppendToken(lexer, ",", allocator);
            try lexer.readToken(&token, allocator);
            appendToken(token.slice());

            scale[i] = token.getFloatValue();
        }
        matchAndAppendToken(lexer, ")", allocator);

        R_ImageScale(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
            &scale,
        );

        return arg;
    }

    if (token.ieql("invertAlpha")) {
        matchAndAppendToken(lexer, "(", allocator);

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        R_InvertAlpha(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );

        return arg;
    }

    if (token.ieql("invertGreen")) {
        matchAndAppendToken(lexer, "(", allocator);

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        R_InvertGreen(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );

        return arg;
    }

    if (token.ieql("invertColor")) {
        matchAndAppendToken(lexer, "(", allocator);

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        R_InvertColor(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );

        return arg;
    }

    if (token.ieql("makeIntensity")) {
        matchAndAppendToken(lexer, "(", allocator);

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        var i: u32 = 0;
        while (i < (arg.image.width * arg.image.height * 4)) : (i += 4) {
            arg.image.data[i + 1] = arg.image.data[i];
            arg.image.data[i + 2] = arg.image.data[i];
            arg.image.data[i + 3] = arg.image.data[i];
        }

        return arg;
    }

    if (token.ieql("makeAlpha")) {
        matchAndAppendToken(lexer, "(", allocator);

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        var i: u32 = 0;
        while (i < (arg.image.width * arg.image.height * 4)) : (i += 4) {
            arg.image.data[i + 3] = @divTrunc(
                arg.image.data[i + 0] + arg.image.data[i + 1] + arg.image.data[i + 2],
                3,
            );
            arg.image.data[i + 0] = 255;
            arg.image.data[i + 1] = 255;
            arg.image.data[i + 2] = 255;
        }

        return arg;
    }

    if (token.ieql("combineRgba")) {
        matchAndAppendToken(lexer, "(", allocator);
        const arg_0 = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg_0.image.data);

        matchAndAppendToken(lexer, ",", allocator);

        const arg_1 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_1.image.data);

        matchAndAppendToken(lexer, ",", allocator);

        const arg_2 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_2.image.data);

        matchAndAppendToken(lexer, ")", allocator);

        R_CombineRgba(
            arg_0.image.data.ptr,
            arg_0.image.width,
            arg_0.image.height,
            arg_1.image.data.ptr,
            arg_1.image.width,
            arg_1.image.height,
            arg_2.image.data.ptr,
            arg_2.image.width,
            arg_2.image.height,
        );

        return arg_0;
    }

    return try loadImage(token.slice(), allocator);
}

fn parseRecursiveAndGetLatestTimestamp(
    lexer: *Lexer,
    timestamp: *idlib.Time,
    allocator: Allocator,
) ParseImageProgramError!void {
    var token = Token{};
    defer token.deinit(allocator);

    try lexer.readToken(&token, allocator);

    if (token.eql("_black")) {
        try token.str.assignSlice("textures/black", allocator);
    } else if (token.eql("_white")) {
        try token.str.assignSlice("guis/assets/white", allocator);
    }

    appendToken(token.slice());

    if (token.ieql("heightmap")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try lexer.readToken(&token, allocator);
        appendToken(token.slice());
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("addnormals")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("smoothnormals")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("add")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("scale")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        for (0..4) |_| {
            matchAndAppendToken(lexer, ",", allocator);
            try lexer.readToken(&token, allocator);
            appendToken(token.slice());
        }
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("invertAlpha")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("invertGreen")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("invertColor")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("makeIntensity")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("makeAlpha")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("combineRgba")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    const image_timestamp = fs.instance.getFileTimestamp(token.slice());

    if (image_timestamp > timestamp.*) {
        timestamp.* = image_timestamp;
    }
}

fn parseRecursive(
    lexer: *Lexer,
    allocator: Allocator,
) ParseImageProgramError!void {
    var token = Token{};
    defer token.deinit(allocator);

    try lexer.readToken(&token, allocator);

    if (token.eql("_black")) {
        try token.str.assignSlice("textures/black", allocator);
    } else if (token.eql("_white")) {
        try token.str.assignSlice("guis/assets/white", allocator);
    }

    appendToken(token.slice());

    if (token.ieql("heightmap")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try lexer.readToken(&token, allocator);
        appendToken(token.slice());
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("addnormals")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("smoothnormals")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("add")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("scale")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        for (0..4) |_| {
            matchAndAppendToken(lexer, ",", allocator);
            try lexer.readToken(&token, allocator);
            appendToken(token.slice());
        }
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("invertAlpha")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("invertGreen")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("invertColor")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("makeIntensity")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("makeAlpha")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }

    if (token.ieql("combineRgba")) {
        matchAndAppendToken(lexer, "(", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ",", allocator);
        try parseRecursive(lexer, allocator);
        matchAndAppendToken(lexer, ")", allocator);

        return;
    }
}

const LoadImageError =
    Allocator.Error ||
    fs.FileSystem.ReadFileAnyAllocError;
fn loadImage(
    path: []const u8,
    allocator: Allocator,
) LoadImageError!LoadImageResult {
    const buffer = try fs.instance.readFileAnyAlloc(path, allocator);
    defer allocator.free(buffer);

    return std.mem.zeroes(LoadImageResult);
}

pub fn parse(lexer: *Lexer, allocator: Allocator) ParseImageProgramError![]const u8 {
    parse_buffer.len = 0;
    try parseRecursive(lexer, allocator);
    return parse_buffer.constSlice();
}

pub fn parseAndGetCubeFileTimestamp(
    program_text: []const u8,
    cube_files: image.CubeFiles,
    cube_map_size: u32,
    allocator: Allocator,
) Allocator.Error!idlib.Time {
    const quake_sides = &.{
        "_ft.tga",
        "_bk.tga",
        "_lf.tga",
        "_rt.tga",
        "_up.tga",
        "_dn.tga",
    };

    const camera_sides = &.{
        "_forward.tga",
        "_back.tga",
        "_left.tga",
        "_right.tga",
        "_up.tga",
        "_down.tga",
    };

    const axis_sides = &.{
        "_px.tga",
        "_nx.tga",
        "_py.tga",
        "_ny.tga",
        "_pz.tga",
        "_nz.tga",
    };

    const sides: []const []const u8 = if (cube_files == .camera)
        camera_sides
    else if (cube_files == .quake1)
        quake_sides
    else
        axis_sides;

    var timestamp = fs.not_found_time;
    if (cube_files == .single and cube_map_size != 0) {
        timestamp = try parseAndGetFileTimestamp(program_text, allocator);
    } else {
        var name_buffer: [image.max_image_name]u8 = undefined;
        for (0..6) |side_index| {
            const full_name = std.fmt.bufPrint(
                &name_buffer,
                "{s}{s}",
                .{ program_text, sides[side_index] },
            ) catch unreachable;

            var side_timestamp = fs.not_found_time;
            side_timestamp = try parseAndGetFileTimestamp(full_name, allocator);

            if (side_timestamp == fs.not_found_time) break;

            if (side_timestamp > timestamp) {
                timestamp = side_timestamp;
            }
        }
    }

    return timestamp;
}

pub fn parseAndGetFileTimestamp(
    program_text: []const u8,
    allocator: Allocator,
) Allocator.Error!idlib.Time {
    parse_buffer.len = 0;

    var lexer = Lexer{
        .flags = .{
            .no_fatal_errors = true,
            .no_string_concat = true,
            .no_string_escape_chars = true,
            .allow_path_names = true,
        },
    };
    defer lexer.deinit(allocator);

    lexer.loadMemory(
        program_text,
        program_text,
        0,
        allocator,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };

    var timestamp = fs.not_found_time;
    parseRecursiveAndGetLatestTimestamp(
        &lexer,
        &timestamp,
        allocator,
    ) catch return timestamp;

    return timestamp;
}

pub fn parseAndLoad(
    program_text: []const u8,
    allocator: Allocator,
) ParseAndLoadError!LoadImageResult {
    parse_buffer.len = 0;

    var lexer = Lexer{
        .flags = .{
            .no_fatal_errors = true,
            .no_string_concat = true,
            .no_string_escape_chars = true,
            .allow_path_names = true,
        },
    };
    defer lexer.deinit(allocator);

    lexer.loadMemory(
        program_text,
        program_text,
        0,
        allocator,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => unreachable,
    };

    var usage: image.TextureUsage = .default;
    return try parseRecursiveAndLoad(&lexer, &usage, allocator);
}
