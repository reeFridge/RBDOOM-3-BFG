const std = @import("std");
const fs = @import("file_system.zig");
const global = @import("../global.zig");
const idlib = @import("../idlib.zig");
const consts = @import("../consts.zig");
const Allocator = std.mem.Allocator;

const Material = @import("../renderer/material.zig").Material;
const DeclSkin = @import("../renderer/common.zig").DeclSkin;
const DeclEntityDef = @import("../game.zig").DeclEntityDef;
const SoundShader = @import("../sound/sound.zig").SoundShader;
const DeclFX = @import("decl_fx.zig").DeclFX;
const DeclAF = @import("decl_af.zig").DeclAF;
const decl_pda = @import("decl_pda.zig");
const DeclParticle = @import("decl_particle.zig").DeclParticle;
const lexer_ = @import("../lexer.zig");
const Lexer = lexer_.Lexer;
const token_ = @import("../token.zig");
const Token = token_.Token;

pub const instance = @extern(*DeclManager, .{ .name = "declManagerLocal" });

pub const decl_lexer_flags = lexer_.Flags{
    .no_string_concat = true,
    .no_string_escape_chars = true,
    .allow_path_names = true,
    .allow_multichar_literals = true,
    .allow_backslash_string_concat = true,
    .no_fatal_errors = true,
};

pub const DeclType = enum(c_int) {
    table = 0,
    material,
    skin,
    sound,
    entitydef,
    modeldef,
    fx,
    particle,
    af,
    pda,
    video,
    audio,
    email,
    modelexport,
    mapdef,
    // new decl types can be added here
    unknown = @intCast(decl_max_types),
};

pub const decl_max_types: usize = 32;

pub const DeclState = enum(c_int) {
    unparsed,
    defaulted,
    parsed,
};

pub const Decl = extern struct {
    vptr: *anyopaque = undefined,
    base: ?*DeclLocal = null,
};

pub const DeclLocal = extern struct {
    vptr: *anyopaque = undefined,
    self: ?*Decl = null,
    name: idlib.Str = .{},
    text_source: ?[*:0]u8 = null,
    text_length: u32 = 0,
    compressed_length: u32 = 0,
    source_file: ?*DeclFile = null,
    source_text_offset: u32 = 0,
    source_text_length: u32 = 0,
    source_line: u32 = 0,
    checksum: u32 = 0,
    decl_type: DeclType,
    decl_state: DeclState,
    index: u32 = 0,
    parsed_outside_level_load: bool = false,
    ever_referenced: bool = false,
    referenced_this_level: bool = false,
    redefined_in_reload: bool = false,
    next_in_file: ?*DeclLocal = null,

    pub fn filename(decl: *const DeclLocal) ?[]const u8 {
        return if (decl.source_file) |sf| sf.filename.constSlice() else null;
    }

    pub fn freeText(decl: *DeclLocal, allocator: Allocator) void {
        if (decl.text_source) |text_source_ptr| {
            allocator.free(text_source_ptr[0..decl.text_length :0]);
            decl.text_source = null;
        }
    }

    pub fn setText(
        decl: *DeclLocal,
        text: []const u8,
        allocator: Allocator,
    ) Allocator.Error!void {
        decl.freeText(allocator);

        decl.checksum = md5BlockChecksum(text);
        decl.compressed_length = @intCast(text.len);
        const copy = try allocator.dupeZ(u8, text);
        decl.text_source = copy.ptr;
        decl.text_length = @intCast(copy.len);
    }

    fn parse(
        decl: *DeclLocal,
        rt_decl_type: *const RuntimeDeclType,
        allocator: Allocator,
    ) (Allocator.Error || DeclParseError)!void {
        var default_text_generated = false;

        const abstract_decl = try decl.allocateSelf(rt_decl_type, allocator);
        rt_decl_type.destroy(abstract_decl, allocator);

        if (decl.text_source == null) {
            default_text_generated = if (rt_decl_type.setDefaultText(abstract_decl, allocator))
                true
            else |_|
                false;
        }

        const text_source = decl.text_source orelse {
            try decl.makeDefault(rt_decl_type, allocator);
            return;
        };

        decl.decl_state = .parsed;
        const decl_text = try allocator.dupe(u8, text_source[0..decl.text_length]);
        defer allocator.free(decl_text);

        try rt_decl_type.parse(abstract_decl, decl_text, true, allocator);

        if (default_text_generated) {
            decl.freeText(allocator);
        }
    }

    var recursion_level: u32 = 0;
    pub const MakeDefaultError =
        Allocator.Error ||
        DeclParseError;
    pub fn makeDefault(
        decl: *DeclLocal,
        rt_decl_type: *const RuntimeDeclType,
        allocator: Allocator,
    ) MakeDefaultError!void {
        decl.decl_state = .defaulted;
        const abstract_decl = try decl.allocateSelf(rt_decl_type, allocator);

        recursion_level += 1;
        if (recursion_level > 100) {
            @panic("[DECL] bad default definition");
        }

        rt_decl_type.destroy(abstract_decl, allocator);

        const allow_binary_version = false;
        try rt_decl_type.parse(
            abstract_decl,
            rt_decl_type.getDefaultDefinition(),
            allow_binary_version,
            allocator,
        );
        recursion_level -= 1;
    }

    fn allocateSelf(
        decl: *DeclLocal,
        rt_decl_type: *const RuntimeDeclType,
        allocator: Allocator,
    ) Allocator.Error!*Decl {
        return decl.self orelse self: {
            const self = try rt_decl_type.create(allocator);
            self.base = decl;
            decl.self = self;

            break :self self;
        };
    }
};

fn md5BlockChecksum(data: []const u8) u32 {
    var digest: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(data, &digest, .{});

    const val: u32 =
        (@as(u32, digest[3]) << 24 | @as(u32, digest[2]) << 16 | @as(u32, digest[1]) << 8 | @as(u32, digest[0])) ^
        (@as(u32, digest[7]) << 24 | @as(u32, digest[6]) << 16 | @as(u32, digest[5]) << 8 | @as(u32, digest[4])) ^
        (@as(u32, digest[11]) << 24 | @as(u32, digest[10]) << 16 | @as(u32, digest[9]) << 8 | @as(u32, digest[8])) ^
        (@as(u32, digest[15]) << 24 | @as(u32, digest[14]) << 16 | @as(u32, digest[13]) << 8 | @as(u32, digest[12]));

    return val;
}

pub const DeclFile = extern struct {
    filename: idlib.Str = .{},
    default_type: DeclType = .unknown,
    timestamp: idlib.Time = 0,
    checksum: u32 = 0,
    file_size: u32 = 0,
    num_lines: u32 = 0,
    decls: ?*DeclLocal = null,

    fn create(
        name: []const u8,
        default_type: DeclType,
        allocator: Allocator,
    ) Allocator.Error!*DeclFile {
        var ptr = try allocator.create(DeclFile);
        ptr.* = .{ .default_type = default_type };

        try ptr.filename.assignSlice(name, allocator);

        return ptr;
    }

    fn deinit(decl_file: *DeclFile, allocator: Allocator) void {
        decl_file.filename.deinit(allocator);
    }

    pub const LoadAndParseError =
        DeclParseError ||
        Allocator.Error ||
        fs.FileSystem.ReadFileAnyAllocError ||
        Lexer.LoadMemoryError ||
        DeclManager.FindTypeError;
    fn loadAndParse(
        decl_file: *DeclFile,
        decl_manager: *DeclManager,
        allocator: Allocator,
    ) LoadAndParseError!void {
        const buffer = try fs.instance.readFileAnyAlloc(
            decl_file.filename.constSlice(),
            allocator,
        );
        defer allocator.free(buffer);

        var lexer = Lexer{
            .flags = decl_lexer_flags,
        };
        defer lexer.deinit(allocator);

        try lexer.loadMemory(
            buffer,
            decl_file.filename.constSlice(),
            0,
            allocator,
        );

        {
            var opt_decl: ?*DeclLocal = decl_file.decls;
            while (opt_decl) |decl| : (opt_decl = decl.next_in_file) {
                decl.redefined_in_reload = false;
            }
        }

        decl_file.checksum = md5BlockChecksum(buffer);
        decl_file.file_size = @intCast(buffer.len);

        var token = Token{};
        defer token.deinit(allocator);

        var temp_buffer: [256]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&temp_buffer);

        var start_marker: u32 = 0;
        var source_line: u32 = 0;
        var size: u32 = 0;
        while (true) {
            defer fba.reset();
            var temp_allocator = fba.allocator();

            start_marker = lexer.getFileOffset();
            source_line = lexer.line;

            // decl type name
            lexer.readToken(&token, allocator) catch break;

            const decl_type = for (decl_manager.decl_types.constSlice()) |opt_rt_decl_type| {
                const rt_decl_type = opt_rt_decl_type orelse continue;

                if (std.ascii.eqlIgnoreCase(
                    rt_decl_type.type_name.constSlice(),
                    token.slice(),
                )) {
                    break rt_decl_type.decl_type;
                }
            } else decl_type: {
                if (std.mem.eql(u8, "{", token.slice())) {
                    std.debug.print("[WARN] Missing decl name\n", .{});
                    lexer.skipBracedSection(false, .brace, null, allocator) catch break;
                    continue;
                } else {
                    if (decl_file.default_type == .unknown) {
                        std.debug.print("[WARN] No type\n", .{});
                        continue;
                    }

                    try lexer.unreadToken(&token, allocator);
                    break :decl_type decl_file.default_type;
                }
            };

            // decl name
            lexer.readToken(&token, allocator) catch {
                std.debug.print("[WARN] Type without definition at the end of file\n", .{});
                break;
            };

            if (std.mem.eql(u8, "{", token.slice())) {
                std.debug.print("[WARN] Missing decl name\n", .{});
                lexer.skipBracedSection(false, .brace, null, allocator) catch break;
                continue;
            }

            if (decl_type == .modelexport) {
                lexer.skipBracedSection(true, .brace, null, allocator) catch break;
                continue;
            }

            const name = temp_allocator.dupe(u8, token.slice()) catch unreachable;

            lexer.readToken(&token, allocator) catch {
                std.debug.print("[WARN] Type without definition at end of file\n", .{});
                break;
            };

            if (!std.mem.eql(u8, "{", token.slice())) {
                std.debug.print("[WARN] Expecting '{{' but found '{s}'\n", .{token.slice()});
                continue;
            }

            try lexer.unreadToken(&token, allocator);
            lexer.skipBracedSection(true, .brace, null, allocator) catch break;

            size = lexer.getFileOffset() - start_marker;

            var reparse = false;
            const new_decl = if (try decl_manager.findTypeWithoutParsing(decl_type, name)) |decl| new_decl: {
                if (decl.source_file != decl_file or decl.redefined_in_reload) {
                    continue;
                }
                if (decl.decl_state != .unparsed) {
                    reparse = true;
                }

                break :new_decl decl;
            } else new_decl: {
                const decl = try decl_manager.createDefault(decl_type, name, allocator);
                decl.next_in_file = decl_file.decls;
                decl_file.decls = decl;

                break :new_decl decl;
            };

            new_decl.redefined_in_reload = true;

            new_decl.freeText(allocator);

            try new_decl.setText(buffer[start_marker..][0..size], allocator);
            new_decl.source_file = decl_file;
            new_decl.source_text_offset = start_marker;
            new_decl.source_text_length = size;
            new_decl.source_line = source_line;
            new_decl.decl_state = .unparsed;

            if (reparse) {
                try new_decl.parse(
                    decl_manager.getRuntimeType(new_decl.decl_type),
                    allocator,
                );
            }
        }

        decl_file.num_lines = lexer.line;

        {
            var opt_decl: ?*DeclLocal = decl_file.decls;
            while (opt_decl) |decl| : (opt_decl = decl.next_in_file) {
                if (decl.redefined_in_reload == false) {
                    try decl.makeDefault(
                        decl_manager.getRuntimeType(decl.decl_type),
                        allocator,
                    );
                    decl.source_text_offset = decl.source_file.?.file_size;
                    decl.source_text_length = 0;
                    decl.source_line = decl.source_file.?.num_lines;
                }
            }
        }
    }
};

fn makeNameCanonical(name: []const u8, buffer: []u8, max_len: u32) []u8 {
    var opt_last_dot: ?u32 = null;
    var result = buffer[0..];

    var i: u32 = 0;
    while (i < max_len and i < name.len) : (i += 1) {
        const char = name[i];

        if (char == '\\') {
            result[i] = '/';
        } else if (char == '.') {
            opt_last_dot = i;
            result[i] = char;
        } else {
            result[i] = std.ascii.toLower(char);
        }
    }

    if (opt_last_dot) |last_dot| {
        result.len = last_dot;
    } else {
        result.len = i;
    }

    return result;
}

pub const DeclFolder = extern struct {
    folder: idlib.Str = .{},
    extension: idlib.Str = .{},
    default_type: DeclType,

    fn create(
        allocator: Allocator,
        folder: []const u8,
        extension: []const u8,
        default_type: DeclType,
    ) Allocator.Error!*DeclFolder {
        var ptr = try allocator.create(DeclFolder);
        ptr.* = .{ .default_type = default_type };

        try ptr.folder.assignSlice(folder, allocator);
        errdefer ptr.folder.deinit(allocator);

        try ptr.extension.assignSlice(extension, allocator);

        return ptr;
    }

    fn deinit(decl_folder: *DeclFolder, allocator: Allocator) void {
        decl_folder.folder.deinit(allocator);
        decl_folder.extension.deinit(allocator);
    }
};

pub const DeclParseError = error{ParseFailed};

fn DeclInterface(Type: type) type {
    return struct {
        pub fn create(allocator: Allocator) Allocator.Error!*Decl {
            if (!std.meta.hasMethod(Type, "init")) @panic("not implemented");

            const decl_typed = try allocator.create(Type);
            decl_typed.init();

            return @ptrCast(decl_typed);
        }

        pub fn destroy(decl: *Decl, allocator: Allocator) void {
            if (!std.meta.hasMethod(Type, "freeData")) @panic("not implemented");

            const decl_typed: *Type = @ptrCast(decl);
            decl_typed.freeData(allocator);
        }

        pub fn setDefaultText(
            decl: *Decl,
            allocator: Allocator,
        ) Allocator.Error!void {
            if (!std.meta.hasMethod(Type, "setDefaultText")) @panic("not implemented");

            const decl_typed: *Type = @ptrCast(decl);
            try decl_typed.setDefaultText(allocator);
        }

        pub fn getDefaultDefinition() []const u8 {
            if (!@hasDecl(Type, "default_definition")) @panic("not implemented");

            return Type.default_definition;
        }

        pub fn parse(
            decl: *Decl,
            definition_text: []const u8,
            allow_binary_version: bool,
            allocator: Allocator,
        ) DeclParseError!void {
            if (!std.meta.hasMethod(Type, "parse")) @panic("not implemented");

            const decl_typed: *Type = @ptrCast(decl);

            decl_typed.parse(
                definition_text,
                allow_binary_version,
                allocator,
            ) catch return error.ParseFailed;
        }
    };
}

pub const RuntimeDeclType = struct {
    type_name: idlib.Str,
    decl_type: DeclType,
    create: *const fn (Allocator) Allocator.Error!*Decl,
    destroy: *const fn (*Decl, Allocator) void,
    parse: *const fn (*Decl, []const u8, bool, Allocator) DeclParseError!void,
    setDefaultText: *const fn (*Decl, Allocator) Allocator.Error!void,
    getDefaultDefinition: *const fn () []const u8,
};

pub const DeclTable = extern struct {
    pub const default_definition = "{ { 0 } }";

    base: Decl = .{},
    clamp: bool = false,
    snap: bool = false,
    values: idlib.List(f32) = .{},

    pub fn init(self: *DeclTable) void {
        self.* = .{};
    }

    pub fn freeData(table: *DeclTable, allocator: Allocator) void {
        table.snap = false;
        table.clamp = false;
        table.values.clear(allocator);
    }

    pub const ParseError =
        DeclLocal.MakeDefaultError ||
        Allocator.Error ||
        Lexer.LoadMemoryError ||
        Lexer.ReadTokenError;
    pub fn parse(
        table: *DeclTable,
        definition_text: []const u8,
        allow_binary_version: bool,
        allocator: Allocator,
    ) ParseError!void {
        _ = allow_binary_version;

        var lexer = Lexer{ .flags = decl_lexer_flags };
        defer lexer.deinit(allocator);

        const decl_local = table.base.base.?;

        try lexer.loadMemory(
            definition_text,
            decl_local.filename() orelse "*invalid*",
            decl_local.source_line,
            allocator,
        );

        try lexer.skipUntilString("{", allocator);

        var token = Token{};
        defer token.deinit(allocator);

        while (true) {
            lexer.readToken(&token, allocator) catch break;
            if (token.eql("}")) break;
            if (token.ieql("snap")) {
                table.snap = true;
            } else if (token.ieql("clamp")) {
                table.clamp = true;
            } else if (token.eql("{")) {
                while (true) {
                    const v = lexer.parseFloat(allocator) catch {
                        try table.makeDefault(allocator);
                        return;
                    };

                    _ = try table.values.append(v, allocator);

                    lexer.readToken(&token, allocator) catch {};

                    if (token.eql("}")) break;
                    if (token.eql(",")) continue;
                    std.debug.print("[DeclTable] expected , or }}\n", .{});

                    try table.makeDefault(allocator);
                    return;
                }
            } else {
                std.debug.print("[DeclTable] unknown token {s}\n", .{token.slice()});
                try table.makeDefault(allocator);
                return;
            }
        }

        const val = table.values.constSlice()[0];
        _ = try table.values.append(val, allocator);
    }

    fn makeDefault(
        table: *DeclTable,
        allocator: Allocator,
    ) DeclLocal.MakeDefaultError!void {
        const decl_local = table.base.base.?;
        const rt_decl_type = instance.getRuntimeType(decl_local.decl_type);
        try decl_local.makeDefault(rt_decl_type, allocator);
    }

    pub fn tableLookup(table: *const DeclTable, arg_findex: f32) f32 {
        const values = table.values.constSlice();
        const domain = @as(i32, @intCast(values.len)) - 1;
        if (domain <= 1) return 1;

        var iindex: u32 = 0;
        var ifrac: f32 = 0;

        var findex = arg_findex;
        if (table.clamp) {
            findex *= @floatFromInt(domain - 1);

            if (findex >= @as(f32, @floatFromInt(domain - 1))) {
                return values[@intCast(domain - 1)];
            } else if (findex <= 0) {
                return values[0];
            }

            iindex = @intFromFloat(findex);
            ifrac = findex - @as(f32, @floatFromInt(iindex));
        } else {
            findex *= @floatFromInt(domain - 1);

            if (findex < 0) {
                findex += @as(f32, @floatFromInt(domain)) * @ceil(-findex / @as(f32, @floatFromInt(domain)));
            }

            iindex = @intFromFloat(findex);
            ifrac = findex - @as(f32, @floatFromInt(iindex));
            iindex = @mod(iindex, @as(u32, @intCast(domain)));
        }

        if (table.snap) {
            return values[iindex] * (1 - ifrac) + values[iindex + 1] * ifrac;
        }

        return values[iindex];
    }
};

pub const DeclManager = extern struct {
    vptr: *anyopaque = undefined,
    mutex: idlib.SysMutex = undefined, // TODO: initMutex
    decl_types: idlib.List(?*RuntimeDeclType) = .{},
    decl_folders: idlib.List(*DeclFolder) = .{},
    loaded_files: idlib.List(*DeclFile) = .{},
    hash_tables: [decl_max_types]idlib.HashIndex = [_]idlib.HashIndex{.{}} ** decl_max_types,
    linear_lists: [decl_max_types]idlib.List(*DeclLocal) = [_]idlib.List(*DeclLocal){.{}} ** decl_max_types,
    implicit_decls: DeclFile = .{},
    checksum: u32 = 0,
    indent: u32 = 0,
    inside_level_load: bool = false,

    pub fn getRuntimeType(manager: *const DeclManager, decl_type: DeclType) *RuntimeDeclType {
        const decl_index: u32 = @intCast(@intFromEnum(decl_type));

        return manager.decl_types.constSlice()[decl_index] orelse @panic("decl_type is not registered");
    }

    pub const InitError = Allocator.Error || RegisterDeclFolderError;
    pub fn init(manager: *DeclManager, allocator: Allocator) InitError!void {
        manager.* = .{};

        try manager.registerDeclType(
            "table",
            .table,
            DeclInterface(DeclTable),
        );
        try manager.registerDeclType(
            "material",
            .material,
            DeclInterface(Material),
        );
        try manager.registerDeclType(
            "skin",
            .skin,
            DeclInterface(DeclSkin),
        );
        try manager.registerDeclType(
            "entityDef",
            .entitydef,
            DeclInterface(DeclEntityDef),
        );
        try manager.registerDeclType(
            "sound",
            .sound,
            DeclInterface(SoundShader),
        );
        try manager.registerDeclType(
            "mapDef",
            .mapdef,
            DeclInterface(DeclEntityDef),
        );
        try manager.registerDeclType(
            "fx",
            .fx,
            DeclInterface(DeclFX),
        );
        try manager.registerDeclType(
            "particle",
            .particle,
            DeclInterface(DeclParticle),
        );
        try manager.registerDeclType(
            "articulatedFigure",
            .af,
            DeclInterface(DeclAF),
        );
        try manager.registerDeclType(
            "pda",
            .pda,
            DeclInterface(decl_pda.DeclPDA),
        );
        try manager.registerDeclType(
            "email",
            .email,
            DeclInterface(decl_pda.DeclEmail),
        );
        try manager.registerDeclType(
            "video",
            .video,
            DeclInterface(decl_pda.DeclVideo),
        );
        try manager.registerDeclType(
            "audio",
            .audio,
            DeclInterface(decl_pda.DeclAudio),
        );

        try manager.registerDeclFolder(
            "materials",
            ".mtr",
            .material,
            allocator,
        );
    }

    pub fn postInit(
        manager: *DeclManager,
        allocator: Allocator,
    ) RegisterDeclFolderError!void {
        try manager.registerDeclFolder(
            "skins",
            ".skin",
            .skin,
            allocator,
        );

        try manager.registerDeclFolder(
            "sound",
            ".sndshd",
            .sound,
            allocator,
        );
    }

    pub const RegisterDeclFolderError =
        Allocator.Error ||
        DeclFile.LoadAndParseError;
    fn registerDeclFolder(
        manager: *DeclManager,
        folder: []const u8,
        extension: []const u8,
        default_type: DeclType,
        allocator: Allocator,
    ) RegisterDeclFolderError!void {
        const df = for (manager.decl_folders.slice()) |decl_folder| {
            const already_exists =
                std.ascii.eqlIgnoreCase(folder, decl_folder.folder.constSlice()) and
                std.ascii.eqlIgnoreCase(extension, decl_folder.extension.constSlice());

            if (already_exists) break decl_folder;
        } else df: {
            const decl_folder = try DeclFolder.create(
                allocator,
                folder,
                extension,
                default_type,
            );
            errdefer {
                decl_folder.deinit(allocator);
                allocator.destroy(decl_folder);
            }

            _ = try manager.decl_folders.append(decl_folder, allocator);
            break :df decl_folder;
        };

        const files = try fs.instance.listFilenames(
            df.folder.constSlice(),
            &.{
                df.extension.constSlice(),
            },
            allocator,
        );
        defer {
            for (files) |filename| allocator.free(filename);
            allocator.free(files);
        }

        var filename_buffer: [256]u8 = undefined;
        for (files) |filename| {
            const full_filename = std.fmt.bufPrint(
                &filename_buffer,
                "{s}/{s}",
                .{ folder, filename },
            ) catch unreachable;

            const decl_file_ptr = for (manager.loaded_files.slice()) |decl_file| {
                if (std.ascii.eqlIgnoreCase(
                    decl_file.filename.constSlice(),
                    full_filename,
                ))
                    break decl_file;
            } else file: {
                const decl_file = try DeclFile.create(
                    full_filename,
                    default_type,
                    allocator,
                );

                errdefer {
                    decl_file.deinit(allocator);
                    allocator.destroy(decl_file);
                }

                _ = try manager.loaded_files.append(decl_file, allocator);

                break :file decl_file;
            };

            try decl_file_ptr.loadAndParse(manager, allocator);
        }
    }

    fn registerDeclType(
        manager: *DeclManager,
        type_name: []const u8,
        decl_type: DeclType,
        DeclInterfaceType: type,
    ) Allocator.Error!void {
        const decl_type_index: usize = @intCast(@intFromEnum(decl_type));
        {
            const decl_types = manager.decl_types.constSlice();
            if (decl_type_index < decl_types.len and decl_types[decl_type_index] != null) {
                std.debug.print("[DECL] type {s}({}) already exists\n", .{
                    type_name,
                    decl_type_index,
                });
                return;
            }
        }

        const allocator = global.gpa.allocator();
        const runtime_decl_type = try allocator.create(RuntimeDeclType);
        errdefer allocator.destroy(runtime_decl_type);

        runtime_decl_type.* = .{
            .type_name = .{},
            .decl_type = decl_type,
            .create = DeclInterfaceType.create,
            .parse = DeclInterfaceType.parse,
            .destroy = DeclInterfaceType.destroy,
            .setDefaultText = DeclInterfaceType.setDefaultText,
            .getDefaultDefinition = DeclInterfaceType.getDefaultDefinition,
        };

        try runtime_decl_type.type_name.assignSlice(type_name, allocator);
        errdefer runtime_decl_type.type_name.deinit(allocator);

        const required_size = decl_type_index + 1;
        if (required_size > manager.decl_types.num) {
            try manager.decl_types.assureSizeInit(required_size, null, allocator);
        }

        manager.decl_types.slice()[decl_type_index] = runtime_decl_type;
    }

    pub const FindTypeError = error{BadType};
    fn findTypeWithoutParsing(
        manager: *DeclManager,
        decl_type: DeclType,
        name: []const u8,
    ) FindTypeError!?*DeclLocal {
        const type_index: u32 = @intCast(@intFromEnum(decl_type));

        if (type_index >= manager.decl_types.num or
            manager.decl_types.constSlice()[type_index] == null or
            type_index >= decl_max_types)
        {
            return error.BadType;
        }

        var canonical_name_buffer: [consts.max_string_chars]u8 = undefined;
        const canonical_name = makeNameCanonical(
            name,
            &canonical_name_buffer,
            @intCast(canonical_name_buffer.len),
        );

        const hash = manager.hash_tables[type_index].generateKey(canonical_name, false);
        var i = manager.hash_tables[type_index].first(hash);
        while (i >= 0) : (i = manager.hash_tables[type_index].next(@intCast(i))) {
            const index: u32 = @intCast(i);
            const decl_ptr = manager.linear_lists[type_index].slice()[index];
            if (std.ascii.eqlIgnoreCase(decl_ptr.name.constSlice(), canonical_name)) {
                return decl_ptr;
            }
        }

        return null;
    }

    pub const CreateDefaultError = Allocator.Error || FindTypeError;
    fn createDefault(
        manager: *DeclManager,
        decl_type: DeclType,
        name: []const u8,
        allocator: Allocator,
    ) CreateDefaultError!*DeclLocal {
        const type_index: u32 = @intCast(@intFromEnum(decl_type));

        if (type_index >= manager.decl_types.num or
            manager.decl_types.constSlice()[type_index] == null or
            type_index >= decl_max_types)
        {
            return error.BadType;
        }

        var canonical_name_buffer: [consts.max_string_chars]u8 = undefined;
        const canonical_name = makeNameCanonical(
            name,
            &canonical_name_buffer,
            @intCast(canonical_name_buffer.len),
        );

        const hash = manager.hash_tables[type_index].generateKey(canonical_name, false);
        const decl = try allocator.create(DeclLocal);
        decl.* = .{
            .decl_type = decl_type,
            .decl_state = .unparsed,
        };
        errdefer allocator.destroy(decl);

        try decl.name.assignSlice(canonical_name, allocator);
        errdefer decl.name.deinit(allocator);

        decl.index = manager.linear_lists[type_index].num;
        try manager.hash_tables[type_index].add(
            hash,
            @intCast(try manager.linear_lists[type_index].append(decl, allocator)),
            allocator,
        );

        return decl;
    }

    pub const FindDeclError =
        Allocator.Error || DeclParseError || FindTypeError;

    pub fn findType(
        manager: *DeclManager,
        decl_type: DeclType,
        name: []const u8,
        allocator: Allocator,
    ) FindDeclError!?*Decl {
        // TODO: critical section
        const decl = try manager.findTypeWithoutParsing(decl_type, name) orelse return null;
        return try manager.prepareDecl(decl, allocator);
    }

    pub fn findTypeOrDefault(
        manager: *DeclManager,
        decl_type: DeclType,
        name: []const u8,
        allocator: Allocator,
    ) FindDeclError!*Decl {
        // TODO: critical section
        const decl =
            try manager.findTypeWithoutParsing(decl_type, name) orelse
            try manager.createDefault(decl_type, name, allocator);

        return try manager.prepareDecl(decl, allocator);
    }

    fn prepareDecl(
        manager: *const DeclManager,
        decl: *DeclLocal,
        allocator: Allocator,
    ) (Allocator.Error || DeclParseError)!*Decl {
        const rt_decl_type = manager.getRuntimeType(decl.decl_type);
        const self = try decl.allocateSelf(rt_decl_type, allocator);

        if (decl.decl_state == .unparsed) {
            try decl.parse(rt_decl_type, allocator);
            decl.parsed_outside_level_load = !manager.inside_level_load;
        }

        decl.referenced_this_level = true;
        decl.ever_referenced = true;

        return self;
    }

    pub fn declByIndex(
        manager: *DeclManager,
        decl_type: DeclType,
        index: u32,
        force_parse: bool,
        allocator: Allocator,
    ) (Allocator.Error || DeclParseError)!*Decl {
        const type_index: u32 = @intCast(@intFromEnum(decl_type));
        const decl = manager.linear_lists[type_index].slice()[index];
        const rt_decl_type = manager.getRuntimeType(decl_type);

        const self = try decl.allocateSelf(rt_decl_type, allocator);

        if (force_parse and decl.decl_state == .unparsed) {
            try decl.parse(rt_decl_type, allocator);
        }

        return self;
    }
};
