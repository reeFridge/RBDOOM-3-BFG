const std = @import("std");
const fs = @import("file_system.zig");
const global = @import("../global.zig");
const idlib = @import("../idlib.zig");
const consts = @import("../consts.zig");

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

const decl_lexer_flags = lexer_.Flags{
    .no_string_concat = true,
    .no_string_escape_chars = true,
    .allow_path_names = true,
    .allow_multichar_literals = true,
    .allow_backslash_string_concat = true,
    .no_fatal_errors = true,
};

pub const DeclType = enum(c_int) {
    TABLE = 0,
    MATERIAL,
    SKIN,
    SOUND,
    ENTITYDEF,
    MODELDEF,
    FX,
    PARTICLE,
    AF,
    PDA,
    VIDEO,
    AUDIO,
    EMAIL,
    MODELEXPORT,
    MAPDEF,
    // new decl types can be added here
    unknown = @intCast(DECL_MAX_TYPES),
};

pub const DECL_MAX_TYPES: usize = 32;

pub const DeclState = enum(c_int) {
    UNPARSED,
    DEFAULTED, // set if a parse failed due to an error, or the lack of any source
    PARSED,
};

pub const Decl = extern struct {
    vptr: *anyopaque = undefined,
    base: ?*DeclLocal = null,
};

pub const DeclLocal = extern struct {
    vptr: *anyopaque = undefined,
    self: ?*Decl = null,
    name: idlib.idStr = .{},
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

    fn freeText(decl: *DeclLocal, allocator: std.mem.Allocator) void {
        if (decl.text_source) |text_source_ptr| {
            allocator.free(text_source_ptr[0..decl.text_length :0]);
            decl.text_source = null;
        }
    }

    fn setText(
        decl: *DeclLocal,
        text: []const u8,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}!void {
        decl.freeText(allocator);

        decl.checksum = md5BlockChecksum(text);
        decl.compressed_length = @intCast(text.len);
        const copy = try allocator.dupeZ(u8, text);
        decl.text_source = copy.ptr;
        decl.text_length = @intCast(copy.len);
    }

    fn parse(
        decl: *DeclLocal,
        Type: type,
        rt_decl_type: *const RuntimeDeclType,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}!void {
        var default_text_generated = false;

        const abstract_decl = decl.allocateSelf(rt_decl_type);
        const decl_typed: *Type = @ptrCast(abstract_decl);

        decl_typed.freeData(allocator);

        if (decl.text_source == null) {
            default_text_generated = try decl_typed.setDefaultText();
        }

        const text_source = decl.text_source orelse {
            try decl.makeDefault(Type, rt_decl_type, allocator);
            return;
        };

        decl.decl_state = .PARSED;
        const decl_text = try allocator.dupe(u8, text_source[0..decl.text_length]);
        defer allocator.free(decl_text);

        try decl_typed.parse(decl_text, true, allocator);

        if (default_text_generated) {
            decl.freeText(allocator);
        }
    }

    var recursion_level: u32 = 0;
    fn makeDefault(
        decl: *DeclLocal,
        Type: type,
        rt_decl_type: *const RuntimeDeclType,
        allocator: std.mem.Allocator,
    ) error{OutOfMemory}!void {
        decl.decl_state = .DEFAULTED;
        const abstract_decl = decl.allocateSelf(rt_decl_type);
        const decl_typed: *Type = @ptrCast(abstract_decl);

        recursion_level += 1;
        if (recursion_level > 100) {
            @panic("[DECL] bad default definition");
        }

        decl_typed.freeData(allocator);

        const allow_binary_version = false;
        try decl_typed.parse(
            Type.default_definition,
            allow_binary_version,
            allocator,
        );
        recursion_level -= 1;
    }

    fn allocateSelf(decl: *DeclLocal, rt_decl_type: *const RuntimeDeclType) *Decl {
        return decl.self orelse self: {
            const self = rt_decl_type.allocator();
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
    filename: idlib.idStr = .{},
    default_type: DeclType = .unknown,
    timestamp: idlib.ID_TIME_T = 0,
    checksum: u32 = 0,
    file_size: u32 = 0,
    num_lines: u32 = 0,
    decls: ?*DeclLocal = null,

    fn create(
        allocator: std.mem.Allocator,
        name: []const u8,
        default_type: DeclType,
    ) error{OutOfMemory}!*DeclFile {
        var ptr = try allocator.create(DeclFile);
        ptr.* = .{ .default_type = default_type };

        ptr.filename.initEmptyBuffer();
        try ptr.filename.assignSlice(name);

        return ptr;
    }

    fn deinit(decl_file: *DeclFile) void {
        decl_file.filename.deinit();
    }

    pub const LoadAndParseError =
        std.mem.Allocator.Error ||
        fs.FileSystem.ReadFileAnyAllocError ||
        Lexer.LoadMemoryError ||
        DeclManager.FindTypeError;
    fn loadAndParse(
        decl_file: *DeclFile,
        decl_manager: *DeclManager,
        allocator: std.mem.Allocator,
        Type: type,
    ) LoadAndParseError!void {
        const buffer = try fs.instance.readFileAnyAlloc(decl_file.filename.constSlice());
        defer fs.instance.freeFileBuffer(buffer);

        var lexer = Lexer{
            .flags = decl_lexer_flags,
        };
        lexer.initEmpty();
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
        token.initEmpty();
        defer token.deinit();

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
            lexer.readToken(&token) catch break;

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
                    lexer.skipBracedSection(false, .brace, null) catch break;
                    continue;
                } else {
                    if (decl_file.default_type == .unknown) {
                        std.debug.print("[WARN] No type\n", .{});
                        continue;
                    }

                    try lexer.unreadToken(&token);
                    break :decl_type decl_file.default_type;
                }
            };

            // decl name
            lexer.readToken(&token) catch {
                std.debug.print("[WARN] Type without definition at end of file\n", .{});
                break;
            };

            if (std.mem.eql(u8, "{", token.slice())) {
                std.debug.print("[WARN] Missing decl name\n", .{});
                lexer.skipBracedSection(false, .brace, null) catch break;
                continue;
            }

            if (decl_type == .MODELEXPORT) {
                lexer.skipBracedSection(true, .brace, null) catch break;
                continue;
            }

            const name = temp_allocator.dupe(u8, token.slice()) catch unreachable;

            lexer.readToken(&token) catch {
                std.debug.print("[WARN] Type without definition at end of file\n", .{});
                break;
            };

            if (!std.mem.eql(u8, "{", token.slice())) {
                std.debug.print("[WARN] Expecting '{{' but found '{s}'\n", .{token.slice()});
                continue;
            }

            try lexer.unreadToken(&token);
            lexer.skipBracedSection(true, .brace, null) catch break;

            size = lexer.getFileOffset() - start_marker;

            var reparse = false;
            const new_decl = if (try decl_manager.findTypeWithoutParsing(decl_type, name)) |decl| new_decl: {
                if (decl.source_file != decl_file or decl.redefined_in_reload) {
                    continue;
                }
                if (decl.decl_state != .UNPARSED) {
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
            new_decl.decl_state = .UNPARSED;

            if (reparse) {
                const decl_index: u32 = @intCast(@intFromEnum(new_decl.decl_type));
                const rt_decl_type = decl_manager.decl_types.constSlice()[decl_index] orelse
                    @panic("decl_type is not registered");
                try new_decl.parse(Type, rt_decl_type, allocator);
            }
        }

        decl_file.num_lines = lexer.line;

        {
            var opt_decl: ?*DeclLocal = decl_file.decls;
            while (opt_decl) |decl| : (opt_decl = decl.next_in_file) {
                if (decl.redefined_in_reload == false) {
                    const decl_index: u32 = @intCast(@intFromEnum(decl.decl_type));
                    const rt_decl_type = decl_manager.decl_types.constSlice()[decl_index] orelse
                        @panic("decl_type is not registered");
                    try decl.makeDefault(Type, rt_decl_type, allocator);
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
    folder: idlib.idStr = .{},
    extension: idlib.idStr = .{},
    default_type: DeclType,

    fn create(
        allocator: std.mem.Allocator,
        folder: []const u8,
        extension: []const u8,
        default_type: DeclType,
    ) error{OutOfMemory}!*DeclFolder {
        var ptr = try allocator.create(DeclFolder);
        ptr.* = .{ .default_type = default_type };

        ptr.folder.initEmptyBuffer();
        try ptr.folder.assignSlice(folder);
        errdefer ptr.folder.deinit();

        ptr.extension.initEmptyBuffer();
        try ptr.extension.assignSlice(extension);

        return ptr;
    }

    fn deinit(decl_folder: *DeclFolder) void {
        decl_folder.folder.deinit();
        decl_folder.extension.deinit();
    }
};

pub const RuntimeDeclType = extern struct {
    pub const AllocatorFn = fn () callconv(.C) *Decl;

    type_name: idlib.idStr,
    decl_type: DeclType,
    allocator: *const AllocatorFn,
};

pub const DeclTable = extern struct {
    base: Decl = .{},
    clamp: bool = false,
    snap: bool = false,
    values: idlib.idList(f32) = .{},

    pub fn init(self: *DeclTable) void {
        self.* = .{};
    }
};

fn DeclAllocator(DeclType_: type) type {
    return struct {
        pub fn alloc() callconv(.C) *Decl {
            const allocator = global.gpa.allocator();
            const decl_typed = allocator.create(DeclType_) catch @panic("decl alloc");
            decl_typed.init();

            return @ptrCast(decl_typed);
        }
    };
}

pub const DeclManager = extern struct {
    vptr: *anyopaque = undefined,
    mutex: idlib.idSysMutex = undefined, // TODO: initMutex
    decl_types: idlib.idList(?*RuntimeDeclType) = .{},
    decl_folders: idlib.idList(*DeclFolder) = .{},
    loaded_files: idlib.idList(*DeclFile) = .{},
    hash_tables: [DECL_MAX_TYPES]idlib.idHashIndex = [_]idlib.idHashIndex{.{}} ** DECL_MAX_TYPES,
    linear_lists: [DECL_MAX_TYPES]idlib.idList(*DeclLocal) = [_]idlib.idList(*DeclLocal){.{}} ** DECL_MAX_TYPES,
    implicit_decls: DeclFile = .{},
    checksum: u32 = 0,
    indent: u32 = 0,
    inside_level_load: bool = false,

    pub const InitError = error{OutOfMemory} || RegisterDeclFolderError;
    pub fn init(manager: *DeclManager, allocator: std.mem.Allocator) InitError!void {
        manager.* = .{};

        try manager.registerDeclType(
            "table",
            .TABLE,
            DeclAllocator(DeclTable).alloc,
        );
        try manager.registerDeclType(
            "material",
            .MATERIAL,
            DeclAllocator(Material).alloc,
        );
        try manager.registerDeclType(
            "skin",
            .SKIN,
            DeclAllocator(DeclSkin).alloc,
        );
        try manager.registerDeclType(
            "entityDef",
            .ENTITYDEF,
            DeclAllocator(DeclEntityDef).alloc,
        );
        try manager.registerDeclType(
            "sound",
            .SOUND,
            DeclAllocator(SoundShader).alloc,
        );
        try manager.registerDeclType(
            "mapDef",
            .MAPDEF,
            DeclAllocator(DeclEntityDef).alloc,
        );
        try manager.registerDeclType(
            "fx",
            .FX,
            DeclAllocator(DeclFX).alloc,
        );
        try manager.registerDeclType(
            "particle",
            .PARTICLE,
            DeclAllocator(DeclParticle).alloc,
        );
        try manager.registerDeclType(
            "articulatedFigure",
            .AF,
            DeclAllocator(DeclAF).alloc,
        );
        try manager.registerDeclType(
            "pda",
            .PDA,
            DeclAllocator(decl_pda.DeclPDA).alloc,
        );
        try manager.registerDeclType(
            "email",
            .EMAIL,
            DeclAllocator(decl_pda.DeclEmail).alloc,
        );
        try manager.registerDeclType(
            "video",
            .VIDEO,
            DeclAllocator(decl_pda.DeclVideo).alloc,
        );
        try manager.registerDeclType(
            "audio",
            .AUDIO,
            DeclAllocator(decl_pda.DeclAudio).alloc,
        );

        try manager.registerDeclFolder(
            "materials",
            ".mtr",
            .MATERIAL,
            allocator,
            Material,
        );
    }

    pub fn postInit(
        manager: *DeclManager,
        allocator: std.mem.Allocator,
    ) RegisterDeclFolderError!void {
        try manager.registerDeclFolder(
            "skins",
            ".skin",
            .SKIN,
            allocator,
            DeclSkin,
        );

        try manager.registerDeclFolder(
            "sound",
            ".sndshd",
            .SOUND,
            allocator,
            SoundShader,
        );
    }

    const RegisterDeclFolderError = error{OutOfMemory} || DeclFile.LoadAndParseError;
    fn registerDeclFolder(
        manager: *DeclManager,
        folder: []const u8,
        extension: []const u8,
        default_type: DeclType,
        allocator: std.mem.Allocator,
        Type: type,
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
                decl_folder.deinit();
                allocator.destroy(decl_folder);
            }

            _ = try manager.decl_folders.append(decl_folder);
            break :df decl_folder;
        };

        const files = try fs.instance.listFilenames(
            allocator,
            df.folder.constSlice(),
            &.{
                df.extension.constSlice(),
            },
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
                    allocator,
                    full_filename,
                    default_type,
                );

                errdefer {
                    decl_file.deinit();
                    allocator.destroy(decl_file);
                }

                _ = try manager.loaded_files.append(decl_file);

                break :file decl_file;
            };

            try decl_file_ptr.loadAndParse(manager, allocator, Type);
        }
    }

    fn registerDeclType(
        manager: *DeclManager,
        type_name: []const u8,
        decl_type: DeclType,
        alloc_fn: *const RuntimeDeclType.AllocatorFn,
    ) error{OutOfMemory}!void {
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
        errdefer {
            runtime_decl_type.type_name.deinit();
            allocator.destroy(runtime_decl_type);
        }
        runtime_decl_type.type_name.initEmptyBuffer();
        try runtime_decl_type.type_name.assignSlice(type_name);
        runtime_decl_type.decl_type = decl_type;
        runtime_decl_type.allocator = alloc_fn;

        const required_size = decl_type_index + 1;
        if (required_size > manager.decl_types.num) {
            try manager.decl_types.assureSizeInit(required_size, null);
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
            type_index >= DECL_MAX_TYPES)
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

    pub const CreateDefaultError = std.mem.Allocator.Error || FindTypeError;
    fn createDefault(
        manager: *DeclManager,
        decl_type: DeclType,
        name: []const u8,
        allocator: std.mem.Allocator,
    ) CreateDefaultError!*DeclLocal {
        const type_index: u32 = @intCast(@intFromEnum(decl_type));

        if (type_index >= manager.decl_types.num or
            manager.decl_types.constSlice()[type_index] == null or
            type_index >= DECL_MAX_TYPES)
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
            .decl_state = .UNPARSED,
        };
        errdefer allocator.destroy(decl);

        decl.name.initEmptyBuffer();
        try decl.name.assignSlice(canonical_name);
        errdefer decl.name.deinit();

        decl.index = manager.linear_lists[type_index].num;
        try manager.hash_tables[type_index].add(
            hash,
            @intCast(try manager.linear_lists[type_index].append(decl)),
        );

        return decl;
    }

    pub const FindDeclError = FindTypeError || std.mem.Allocator.Error;
    pub fn findType(
        manager: *DeclManager,
        Type: type,
        decl_type: DeclType,
        name: []const u8,
        allocator: std.mem.Allocator,
    ) FindDeclError!?*Type {
        // TODO: critical section
        const decl =
            try manager.findTypeWithoutParsing(decl_type, name) orelse return null;

        return try manager.prepareDecl(Type, decl, allocator);
    }

    pub fn findTypeOrDefault(
        manager: *DeclManager,
        Type: type,
        decl_type: DeclType,
        name: []const u8,
        allocator: std.mem.Allocator,
    ) FindDeclError!*Type {
        // TODO: critical section
        const decl =
            try manager.findTypeWithoutParsing(decl_type, name) orelse
            try manager.createDefault(decl_type, name, allocator);

        return try manager.prepareDecl(Type, decl, allocator);
    }

    fn prepareDecl(
        manager: *const DeclManager,
        Type: type,
        decl: *DeclLocal,
        allocator: std.mem.Allocator,
    ) std.mem.Allocator.Error!*Type {
        const decl_index: u32 = @intCast(@intFromEnum(decl.decl_type));
        const rt_decl_type = manager.decl_types.constSlice()[decl_index] orelse
            @panic("decl_type is not registered");

        const self = decl.allocateSelf(rt_decl_type);

        if (decl.decl_state == .UNPARSED) {
            try decl.parse(Type, rt_decl_type, allocator);
            decl.parsed_outside_level_load = !manager.inside_level_load;
        }

        decl.referenced_this_level = true;
        decl.ever_referenced = true;

        return @ptrCast(self);
    }
};
