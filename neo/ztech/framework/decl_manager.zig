const std = @import("std");
const global = @import("../global.zig");
const idlib = @import("../idlib.zig");

const Material = @import("../renderer/material.zig").Material;
const DeclSkin = @import("../renderer/common.zig").DeclSkin;
const DeclEntityDef = @import("../game.zig").DeclEntityDef;
const SoundShader = @import("../sound/sound.zig").SoundShader;

pub const instance = @extern(*DeclManager, .{ .name = "declManagerLocal" });

pub const DeclType = enum(c_int) {
    DECL_TABLE = 0,
    DECL_MATERIAL,
    DECL_SKIN,
    DECL_SOUND,
    DECL_ENTITYDEF,
    DECL_MODELDEF,
    DECL_FX,
    DECL_PARTICLE,
    DECL_AF,
    DECL_PDA,
    DECL_VIDEO,
    DECL_AUDIO,
    DECL_EMAIL,
    DECL_MODELEXPORT,
    DECL_MAPDEF,

    // new decl types can be added here
};

pub const DECL_MAX_TYPES: usize = 32;

pub const DeclState = enum(c_int) {
    DS_UNPARSED,
    DS_DEFAULTED, // set if a parse failed due to an error, or the lack of any source
    DS_PARSED,
};

pub const Decl = extern struct {
    vptr: *anyopaque,
    base: *DeclBase,
};
pub const DeclBase = opaque {};

pub const DeclLocal = extern struct {
    vptr: *anyopaque,
    self: *Decl,
    name: idlib.idStr,
    textSource: ?[*:0]u8,
    textLength: c_int,
    compressedLength: c_int,
    sourceFile: ?*DeclFile,
    sourceTextOffset: c_int,
    sourceTextLength: c_int,
    sourceLine: c_int,
    checksum: c_int,
    declType: DeclType,
    declState: DeclState,
    index: c_int,
    parsedOutsideLevelLoad: bool,
    everReferenced: bool,
    referencedThidLevel: bool,
    redefinedInReload: bool,
    nextInFile: ?*DeclLocal,
};

pub const DeclFile = extern struct {
    fileName: idlib.idStr,
    defaultType: DeclType,
    timestamp: idlib.ID_TIME_T,
    checksum: c_int,
    fileSize: c_int,
    numLines: c_int,
    decls: ?[*]DeclLocal,
};

pub const DeclFolder = extern struct {
    folder: idlib.idStr,
    extension: idlib.idStr,
    defaultType: DeclType,
};

pub const RuntimeDeclType = extern struct {
    pub const AllocatorFn = fn () callconv(.C) *Decl;

    typeName: idlib.idStr,
    declType: DeclType,
    allocator: *const AllocatorFn,
};

const DeclTable = extern struct {
    base: Decl,
    clamp: bool,
    snap: bool,
    values: idlib.idList(f32),
};

fn DeclAllocator(DeclType_: type) type {
    return struct {
        pub fn alloc() callconv(.C) *Decl {
            const allocator = global.gpa.allocator();
            const decl_ = allocator.create(DeclType_) catch unreachable;

            return @ptrCast(decl_);
        }
    };
}

pub const DeclManager = extern struct {
    vptr: *anyopaque,
    mutex: idlib.idSysMutex,
    declTypes: idlib.idList(?*RuntimeDeclType),
    declFolders: idlib.idList(*DeclFolder),
    loadedFiles: idlib.idList(*DeclFile),
    hashTables: [DECL_MAX_TYPES]idlib.idHashIndex,
    linearLists: [DECL_MAX_TYPES]idlib.idList(*DeclLocal),
    implicitDecls: DeclFile,
    checksum: c_int,
    indent: c_int,
    insideLevelLoad: bool,

    extern fn c_declManager_findMaterial(*DeclManager, [*:0]const u8, bool) callconv(.C) ?*Material;
    extern fn c_declManager_findType(*DeclManager, DeclType, [*:0]const u8, bool) ?*Decl;

    pub fn init(manager: *DeclManager) error{OutOfMemory}!void {
        manager.checksum = 0;

        try manager.registerDeclType(
            "table",
            .DECL_TABLE,
            DeclAllocator(DeclTable).alloc,
        );
        try manager.registerDeclType(
            "material",
            .DECL_MATERIAL,
            DeclAllocator(Material).alloc,
        );
        try manager.registerDeclType(
            "skin",
            .DECL_SKIN,
            DeclAllocator(DeclSkin).alloc,
        );
        try manager.registerDeclType(
            "entityDef",
            .DECL_ENITYDEF,
            DeclAllocator(DeclEntityDef).alloc,
        );
        try manager.registerDeclType(
            "sound",
            .DECL_SOUND,
            DeclAllocator(SoundShader).alloc,
        );
        try manager.registerDeclType(
            "mapDef",
            .DECL_MAPDEF,
            DeclAllocator(DeclEntityDef).alloc,
        );
        try manager.registerDeclType(
            "fx",
            .DECL_FX,
            DeclAllocator(DeclFX).alloc,
        );
        try manager.registerDeclType(
            "particle",
            .DECL_PARTICLE,
            DeclAllocator(DeclParticle).alloc,
        );
        try manager.registerDeclType(
            "articulatedFigure",
            .DECL_AF,
            DeclAllocator(DeclAF).alloc,
        );
        try manager.registerDeclType(
            "pda",
            .DECL_PDA,
            DeclAllocator(DeclPDA).alloc,
        );
        try manager.registerDeclType(
            "email",
            .DECL_EMAIL,
            DeclAllocator(DeclEmail).alloc,
        );
        try manager.registerDeclType(
            "video",
            .DECL_VIDEO,
            DeclAllocator(DeclVideo).alloc,
        );
        try manager.registerDeclType(
            "audio",
            .DECL_VIDEO,
            DeclAllocator(DeclAudio).alloc,
        );

        // TODO: try manager.registerDeclFolder("materials", ".mtr", .DECL_MATERIAL);
    }

    fn registerDeclType(
        manager: *DeclManager,
        type_name: []const u8,
        decl_type: DeclType,
        alloc_fn: *const RuntimeDeclType.AllocatorFn,
    ) error{OutOfMemory}!void {
        if (@intFromEnum(decl_type) < manager.declTypes.num and
            manager.declTypes.getValue(@intCast(@intFromEnum(decl_type))) != null)
        {
            std.debug.print("[DECL] type {s} already exists\n", .{type_name});
            return;
        }

        const allocator = global.gpa.allocator();
        const runtime_decl_type = try allocator.create(RuntimeDeclType);
        errdefer allocator.destroy(runtime_decl_type);
        runtime_decl_type.typeName.initEmptyBuffer();
        try runtime_decl_type.typeName.assignSlice(type_name);
        runtime_decl_type.declType = decl_type;
        runtime_decl_type.allocator = alloc_fn;

        if (@intFromEnum(decl_type) + 1 > manager.declTypes.num) {
            try manager.declTypes.assureSizeInit(@intCast(@intFromEnum(decl_type) + 1), null);
        }

        if (manager.declTypes.getPtr(@intCast(@intFromEnum(decl_type)))) |ptr| {
            ptr.* = runtime_decl_type;
        }
    }

    pub fn findType(
        manager: *DeclManager,
        decl_type: DeclType,
        name: []const u8,
        make_default: bool,
    ) ?*Decl {
        const allocator = global.gpa.allocator();
        const name_sentinel = allocator.dupeZ(u8, name) catch unreachable;
        defer allocator.free(name_sentinel);

        return c_declManager_findType(manager, decl_type, name_sentinel, make_default);
    }

    pub fn findMaterial(manager: *DeclManager, name: []const u8) ?*Material {
        return manager.findMaterial_(name, false);
    }

    pub fn findMaterialDefault(manager: *DeclManager, name: []const u8) ?*Material {
        return manager.findMaterial_(name, true);
    }

    fn findMaterial_(manager: *DeclManager, name: []const u8, make_default: bool) ?*Material {
        const allocator = global.gpa.allocator();
        const name_sentinel = allocator.dupeZ(u8, name) catch unreachable;
        defer allocator.free(name_sentinel);

        return c_declManager_findMaterial(manager, name_sentinel.ptr, make_default);
    }
};
