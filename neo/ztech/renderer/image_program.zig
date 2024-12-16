const std = @import("std");
const fs = @import("../framework/file_system.zig");
const lexer_ = @import("../lexer.zig");
const Lexer = lexer_.Lexer;
const token_ = @import("../token.zig");
const Token = token_.Token;
const TextureUsage = @import("image.zig").TextureUsage;
const idlib = @import("../idlib.zig");
const image = @import("image.zig");

var parse_buffer = std.BoundedArray(u8, image.max_image_name).init(0) catch unreachable;

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
extern fn R_SmoothNormalMap([*]u8, u32, u32) void;
extern fn R_ImageAdd([*]u8, u32, u32, [*]u8, u32, u32) void;
extern fn R_ImageScale([*]u8, u32, u32, *[4]f32) void;
extern fn R_InvertAlpha([*]u8, u32, u32) void;
extern fn R_InvertGreen([*]u8, u32, u32) void;
extern fn R_InvertColor([*]u8, u32, u32) void;
extern fn R_CombineRgba([*]u8, u32, u32, [*]u8, u32, u32, [*]u8, u32, u32) void;

pub const ParseImageProgramError =
    std.mem.Allocator.Error ||
    Lexer.ReadTokenError;

const LoadImageResult = struct {
    const Image = struct {
        data: []u8,
        width: u32,
        height: u32,
    };

    image: Image,
    timestamp: idlib.ID_TIME_T,
};

pub const ParseAndLoadError =
    LoadImageError ||
    ParseImageProgramError;
fn parseRecursiveAndLoad(
    lexer: *Lexer,
    usage: *TextureUsage,
    allocator: std.mem.Allocator,
) ParseAndLoadError!LoadImageResult {
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
        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg.image.data);
        matchAndAppendToken(lexer, ",");

        try lexer.readToken(&token);
        appendToken(token.slice());
        const scale = token.getFloatValue();

        matchAndAppendToken(lexer, ")");

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
        matchAndAppendToken(lexer, "(");
        const arg_0 = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg_0.image.data);

        matchAndAppendToken(lexer, ",");

        const arg_1 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_1.image.data);
        matchAndAppendToken(lexer, ")");

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
        matchAndAppendToken(lexer, "(");

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")");

        R_SmoothNormalMap(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );
        usage.* = .bump;

        return arg;
    }

    if (token.ieql("add")) {
        matchAndAppendToken(lexer, "(");
        const arg_0 = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg_0.image.data);

        matchAndAppendToken(lexer, ",");

        const arg_1 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_1.image.data);
        matchAndAppendToken(lexer, ")");

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
        matchAndAppendToken(lexer, "(");
        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg.image.data);

        var scale: [4]f32 = undefined;
        for (0..4) |i| {
            matchAndAppendToken(lexer, ",");
            try lexer.readToken(&token);
            appendToken(token.slice());

            scale[i] = token.getFloatValue();
        }
        matchAndAppendToken(lexer, ")");

        R_ImageScale(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
            &scale,
        );

        return arg;
    }

    if (token.ieql("invertAlpha")) {
        matchAndAppendToken(lexer, "(");

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")");

        R_InvertAlpha(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );

        return arg;
    }

    if (token.ieql("invertGreen")) {
        matchAndAppendToken(lexer, "(");

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")");

        R_InvertGreen(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );

        return arg;
    }

    if (token.ieql("invertColor")) {
        matchAndAppendToken(lexer, "(");

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")");

        R_InvertColor(
            arg.image.data.ptr,
            arg.image.width,
            arg.image.height,
        );

        return arg;
    }

    if (token.ieql("makeIntensity")) {
        matchAndAppendToken(lexer, "(");

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")");

        var i: u32 = 0;
        while (i < (arg.image.width * arg.image.height * 4)) : (i += 4) {
            arg.image.data[i + 1] = arg.image.data[i];
            arg.image.data[i + 2] = arg.image.data[i];
            arg.image.data[i + 3] = arg.image.data[i];
        }

        return arg;
    }

    if (token.ieql("makeAlpha")) {
        matchAndAppendToken(lexer, "(");

        const arg = try parseRecursiveAndLoad(lexer, usage, allocator);
        matchAndAppendToken(lexer, ")");

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
        matchAndAppendToken(lexer, "(");
        const arg_0 = try parseRecursiveAndLoad(lexer, usage, allocator);
        errdefer allocator.free(arg_0.image.data);

        matchAndAppendToken(lexer, ",");

        const arg_1 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_1.image.data);

        matchAndAppendToken(lexer, ",");

        const arg_2 = try parseRecursiveAndLoad(lexer, usage, allocator);
        defer allocator.free(arg_2.image.data);

        matchAndAppendToken(lexer, ")");

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
    timestamp: *idlib.ID_TIME_T,
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
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ",");
        try lexer.readToken(&token);
        appendToken(token.slice());
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("addnormals")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ",");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("smoothnormals")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("add")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ",");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("scale")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
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
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("invertGreen")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("invertColor")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("makeIntensity")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("makeAlpha")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    if (token.ieql("combineRgba")) {
        matchAndAppendToken(lexer, "(");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ",");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ",");
        try parseRecursiveAndGetLatestTimestamp(lexer, timestamp);
        matchAndAppendToken(lexer, ")");

        return;
    }

    const image_timestamp = fs.instance.getFileTimestamp(token.slice());

    if (image_timestamp > timestamp.*) {
        timestamp.* = image_timestamp;
    }
}

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

const LoadImageError =
    std.mem.Allocator.Error ||
    fs.FileSystem.ReadFileAnyAllocError;
fn loadImage(
    path: []const u8,
    allocator: std.mem.Allocator,
) LoadImageError!LoadImageResult {
    _ = allocator;
    const buffer = try fs.instance.readFileAnyAlloc(path);
    _ = buffer;

    return std.mem.zeroes(LoadImageResult);
}

pub fn parse(lexer: *Lexer) ParseImageProgramError![]const u8 {
    parse_buffer.len = 0;
    try parseRecursive(lexer);
    return parse_buffer.constSlice();
}

pub fn parseAndGetCubeFileTimestamp(
    program_text: []const u8,
    cube_files: image.CubeFiles,
    cube_map_size: u32,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!idlib.ID_TIME_T {
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

    var timestamp = fs.FILE_NOT_FOUND_TIMESTAMP;
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

            var side_timestamp = fs.FILE_NOT_FOUND_TIMESTAMP;
            side_timestamp = try parseAndGetFileTimestamp(full_name, allocator);

            if (side_timestamp == fs.FILE_NOT_FOUND_TIMESTAMP) break;

            if (side_timestamp > timestamp) {
                timestamp = side_timestamp;
            }
        }
    }

    return timestamp;
}

pub fn parseAndGetFileTimestamp(
    program_text: []const u8,
    allocator: std.mem.Allocator,
) std.mem.Allocator.Error!idlib.ID_TIME_T {
    parse_buffer.len = 0;

    var lexer = Lexer{
        .flags = .{
            .no_fatal_errors = true,
            .no_string_concat = true,
            .no_string_escape_chars = true,
            .allow_path_names = true,
        },
    };
    lexer.initEmpty();
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

    var timestamp = fs.FILE_NOT_FOUND_TIMESTAMP;
    parseRecursiveAndGetLatestTimestamp(&lexer, &timestamp) catch return timestamp;

    return timestamp;
}

pub fn parseAndLoad(
    program_text: []const u8,
    allocator: std.mem.Allocator,
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
    lexer.initEmpty();
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
