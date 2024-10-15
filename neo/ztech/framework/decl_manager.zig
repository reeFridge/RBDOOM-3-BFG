const Material = @import("../renderer/material.zig").Material;
const global = @import("../global.zig");
const idlib = @import("../idlib.zig");

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

pub const Decl = opaque {};
pub const DeclBase = opaque {};

pub const DeclLocal = extern struct {
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
    const AllocatorFn = fn () callconv(.C) *Decl;

    typeName: idlib.idStr,
    declType: DeclType,
    allocator: *const AllocatorFn,
};

pub const DeclManager = extern struct {
    vptr: *anyopaque,
    mutex: idlib.idSysMutex,
    declTypes: idlib.idList(*RuntimeDeclType),
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
