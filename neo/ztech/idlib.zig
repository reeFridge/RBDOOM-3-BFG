const std = @import("std");

extern fn c_memFree(*anyopaque) callconv(.C) void;

pub const ID_TIME_T = i64;

pub const idStr = extern struct {
    const STR_ALLOC_BASE: usize = 20;

    len: c_int,
    data: [*c]u8,
    allocedAndFlag: c_int,
    baseBuffer: [STR_ALLOC_BASE]u8,
};

pub fn idStrStatic(size: usize) type {
    return extern struct {
        base: idStr,
        buffer: [size]c_char,
    };
}

pub fn idList(T: type) type {
    return extern struct {
        const Self = @This();

        num: c_int,
        size: c_int,
        granularity: c_int,
        list: ?[*]T,
        memTag: u8,

        pub inline fn constSlice(self: *const Self) []const T {
            return if (self.list) |list|
                list[0..@intCast(self.num)]
            else
                &.{};
        }

        pub inline fn slice(self: *Self) []T {
            return if (self.list) |list|
                list[0..@intCast(self.num)]
            else
                &.{};
        }

        pub fn clear(self: *Self) void {
            if (self.list) |list| {
                for (list[0..@intCast(self.num)]) |*item| {
                    item.deinit();
                }
                c_memFree(@ptrCast(list));
            }

            self.list = null;
            self.num = 0;
            self.size = 0;
        }
    };
}

pub fn idStaticList(T: type, size: usize) type {
    return extern struct {
        num: c_int,
        list: [size]T,

        const Self = @This();

        pub inline fn slice(self: *Self) []T {
            return self.list[0..@intCast(self.num)];
        }

        pub fn setNum(self: *Self, new_num: usize) void {
            self.num = @intCast(new_num);
        }

        pub inline fn max(_: Self) usize {
            return size;
        }
    };
}

// TODO: const MutexHandle = @import("std").c.pthread_mutex_t;
// Wrong size of std.c.pthread_mutex_t
// https://github.com/ziglang/zig/issues/21229
const pthread = @cImport(@cInclude("pthread.h"));
pub const MutexHandle = pthread.pthread_mutex_t;

pub const idSysMutex = extern struct {
    handle: MutexHandle,

    extern fn c_sysMutex_unlock(*MutexHandle) callconv(.C) void;
    extern fn c_sysMutex_lock(*MutexHandle, bool) callconv(.C) bool;
    extern fn c_sysMutex_create(*MutexHandle) callconv(.C) void;
    extern fn c_sysMutex_destroy(*MutexHandle) callconv(.C) void;

    pub fn init() idSysMutex {
        var handle = MutexHandle{ .data = undefined };
        c_sysMutex_create(&handle);

        return .{ .handle = handle };
    }

    pub fn deinit(mutex: *idSysMutex) void {
        c_sysMutex_destroy(&mutex.handle);
    }

    pub fn lockBlocking(mutex: *idSysMutex) bool {
        return c_sysMutex_lock(&mutex.handle, true);
    }

    pub fn lock(mutex: *idSysMutex) bool {
        return c_sysMutex_lock(&mutex.handle, false);
    }

    pub fn unlock(mutex: *idSysMutex) void {
        c_sysMutex_unlock(&mutex.handle);
    }
};

pub const idHashIndex = extern struct {
    hashSize: c_int,
    hash: ?*c_int,
    indexSize: c_int,
    indexChain: ?*c_int,
    granularity: c_int,
    hashMask: c_int,
    lookupMask: c_int,

    extern fn c_hashIndex_clear(*idHashIndex) callconv(.C) void;

    pub fn clear(hash_index: *idHashIndex) void {
        c_hashIndex_clear(hash_index);
    }
};

pub const idFile = opaque {};

pub const idResourceCacheEntry = extern struct {
    filename: idStrStatic(256),
    offset: c_int,
    length: c_int,
    owner: *idResourceContainer,
};

pub const idDict = extern struct {
    const KeyValue = extern struct {
        key: *const anyopaque,
        value: *const anyopaque,
    };

    args: idList(KeyValue),
    argsHash: idHashIndex,
};

pub const idResourceContainer = extern struct {
    fileName: idStrStatic(256),
    resourceFile: ?*idFile,
    tableOffset: c_int,
    tableLength: c_int,
    resourceMagic: c_int,
    numFileResources: c_int,
    cacheTable: idList(idResourceCacheEntry),
    cacheHash: idHashIndex,
};

pub const idZipCacheEntry = extern struct {
    const MAX_ZIPPED_FILE_NAME: usize = 2048;
    const ZPOS64_T = u64;

    filename: idStrStatic(MAX_ZIPPED_FILE_NAME),
    offset: ZPOS64_T,
    length: ZPOS64_T,
    owner: *idZipContainer,
};

pub const idZipContainer = extern struct {
    const unzFile = opaque {};

    fileName: idStrStatic(256),
    zipFileHandle: ?*unzFile,
    checksum: c_int,
    numFileResources: c_int,
    cacheTable: idList(idZipCacheEntry),
    cacheHash: idHashIndex,
};

pub const idStrList = idList(idStr);

pub const idPreloadManifest = extern struct {
    pub const PreloadType = enum(c_int) {
        PRELOAD_IMAGE,
        PRELOAD_MODEL,
        PRELOAD_SAMPLE,
        PRELOAD_ANIM,
        PRELOAD_COLLISION,
        PRELOAD_PARTICLE,
    };

    pub const ImagePreload = extern struct {
        filter: c_int,
        repeat: c_int,
        usage: c_int,
        cubeMap: c_int,
    };

    pub const PreloadEntry = extern struct {
        resType: PreloadType,
        resourceName: idStr,
        imgData: ImagePreload,
    };

    entries: idList(PreloadEntry),
    filename: idStr,
};
