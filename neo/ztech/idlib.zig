const std = @import("std");
const global = @import("global.zig");
const fs = @import("framework/file_system.zig");

pub const ID_TIME_T = i64;

pub const idStr = extern struct {
    const FILE_HASH_SIZE: c_int = 1024;
    const STR_ALLOC_BASE: usize = 20;
    const STR_ALLOC_GRAN: u32 = 32;

    const AllocedAndFlag = packed struct(u32) {
        alloced: u31 = 0,
        flag: bool = false,
    };

    len: u32 = 0,
    data: ?[*]u8 = null,
    allocedAndFlag: AllocedAndFlag = .{},
    baseBuffer: [STR_ALLOC_BASE]u8 = std.mem.zeroes([STR_ALLOC_BASE]u8),

    pub fn initEmptyBuffer(self: *idStr) void {
        self.setStatic(false);
        self.setAlloced(STR_ALLOC_BASE);
        self.data = &self.baseBuffer;
        self.len = 0;
    }

    pub fn move(src: *idStr, dst: *idStr) void {
        dst.* = src.*;

        const data = src.data orelse return;
        if (&src.baseBuffer == data) {
            dst.data = &dst.baseBuffer;
        }
    }

    pub fn empty(self: *idStr) error{OutOfMemory}!void {
        try self.ensureAlloced(1, true);
        self.data.?[0] = 0;
        self.len = 0;
    }

    pub fn assignSlice(self: *idStr, slice: []const u8) error{OutOfMemory}!void {
        if (slice.len == 0) {
            try self.ensureAlloced(1, false);
            const data = self.data orelse unreachable;
            data[0] = 0;
            self.len = 0;
            return;
        }

        if (self.data) |data| {
            if (data == slice.ptr) return;

            const len: usize = @intCast(self.len);
            if (@intFromPtr(slice.ptr) >= @intFromPtr(data) and
                @intFromPtr(slice.ptr) <= @intFromPtr(data + len))
            {
                const diff = @intFromPtr(slice.ptr) - @intFromPtr(data);
                std.debug.assert(slice.len < len);

                for (slice, 0..) |char, i| {
                    data[i] = char;
                }

                data[slice.len] = 0;
                self.len -= @intCast(diff);
                return;
            }
        }

        try self.ensureAlloced(slice.len + 1, false);
        const data = self.data orelse unreachable;
        std.mem.copyForwards(u8, data[0..self.alloced()], slice);
        self.len = @intCast(slice.len);
        data[slice.len] = 0;
    }

    pub fn appendSlice(self: *idStr, slice: []const u8) error{OutOfMemory}!void {
        const new_len: usize = @as(usize, @intCast(self.len)) + slice.len;
        try self.ensureAlloced(new_len + 1, true);
        const data = self.data orelse unreachable;

        const start: usize = @intCast(self.len);
        for (slice, 0..) |char, i| {
            data[start + i] = char;
        }

        self.len = @intCast(new_len);
        data[new_len] = 0;
    }

    pub fn appendStr(self: *idStr, other: *const idStr) error{OutOfMemory}!void {
        self.appendSlice(other.constSlice());
    }

    pub fn stripTrailingChar(self: *idStr, char: u8) void {
        const data_ptr = self.data orelse return;

        var i: usize = @intCast(self.len);
        while (i > 0 and data_ptr[i - 1] == char) : (i -= 1) {
            data_ptr[i - 1] = 0;
            self.len -= 1;
        }
    }

    fn clear(self: *idStr) void {
        if (self.isStatic()) {
            self.len = 0;
            self.data.?[0] = 0;
            return;
        }

        self.freeData();
        self.* = idStr{};
        self.initEmptyBuffer();
    }

    fn freeData(self: *idStr) void {
        if (self.isStatic()) return;

        if (self.data) |data| {
            if (data != &self.baseBuffer) {
                const allocator = global.gpa.allocator();
                const buffer = data[0..self.alloced()];

                allocator.free(buffer);
            }
        }
    }

    pub fn ensureAlloced(self: *idStr, amount: usize, keep_old: bool) error{OutOfMemory}!void {
        if (self.isStatic()) return;

        if (amount > self.alloced()) {
            try self.reallocate(amount, keep_old);
        }
    }

    fn reallocate(self: *idStr, amount: usize, keep_old: bool) error{OutOfMemory}!void {
        std.debug.assert(amount > 0);

        const mod = @mod(amount, STR_ALLOC_GRAN);
        const new_size = if (mod == 0)
            amount
        else
            amount + STR_ALLOC_GRAN - mod;

        const old_buffer = if (self.data) |data| old_buffer: {
            if (data == &self.baseBuffer) break :old_buffer null;

            break :old_buffer data[0..self.alloced()];
        } else null;
        self.setAlloced(new_size);

        const allocator = global.gpa.allocator();

        const new_buffer = try allocator.alloc(u8, self.alloced());
        for (new_buffer) |*char| char.* = 0;

        if (keep_old) {
            if (self.data) |data| {
                data[@intCast(self.len)] = 0;
                const dataz: [*:0]u8 = @ptrCast(data);
                std.mem.copyForwards(u8, new_buffer, std.mem.span(dataz));
            }
        }

        if (old_buffer) |buffer| {
            allocator.free(buffer);
        }

        self.data = new_buffer.ptr;
    }

    inline fn setAlloced(self: *idStr, size: usize) void {
        self.allocedAndFlag.alloced = @intCast(size);
    }

    inline fn alloced(self: *const idStr) usize {
        return self.allocedAndFlag.alloced;
    }

    inline fn setStatic(self: *idStr, is_static: bool) void {
        self.allocedAndFlag.flag = is_static;
    }

    inline fn isStatic(self: *const idStr) bool {
        return self.allocedAndFlag.flag;
    }

    pub fn fileNameHash(str: []const u8) u32 {
        var result: u32 = 0;
        for (str, 0..) |char, i| {
            var letter = std.ascii.toLower(char);
            if (letter == '.') break;
            if (letter == '\\') {
                letter = '/';
            }
            result += letter * @as(u32, @intCast(i + 119));
        }

        result &= FILE_HASH_SIZE - 1;

        return result;
    }

    pub fn hash(str: []const u8) u32 {
        var result: u32 = 0;
        for (str, 0..) |char, i| {
            result += char * @as(u32, @intCast(i + 119));
        }

        return result;
    }

    pub fn caseInsensetiveHash(str: []const u8) u32 {
        var result: u32 = 0;
        for (str, 0..) |char, i| {
            result += std.ascii.toLower(char) * @as(u32, @intCast(i + 119));
        }

        return result;
    }

    pub inline fn constSlice(self: *const idStr) [:0]const u8 {
        return if (self.data) |data|
            std.mem.span(@as([*:0]u8, @ptrCast(data)))
        else
            &.{};
    }

    pub fn deinit(self: *idStr) void {
        self.freeData();
    }
};

pub fn idStrStatic(size: usize) type {
    return extern struct {
        const Self = @This();

        base: idStr = .{},
        buffer: [size]u8,

        pub fn constSlice(self: *const Self) [:0]const u8 {
            return std.mem.span(@as([*:0]const u8, @ptrCast(&self.buffer)));
        }
    };
}

pub fn idList(T: type) type {
    return extern struct {
        const Self = @This();
        const DEFAULT_GRANULARITY = 16;

        num: u32 = 0,
        size: u32 = 0,
        granularity: u32 = DEFAULT_GRANULARITY,
        list: ?[*]T = null,
        memTag: u8 = 0,

        pub fn removeIndex(self: *Self, index: usize) void {
            std.debug.assert(self.list != null);
            std.debug.assert(index < self.num);

            self.num -= 1;
            for (index..@intCast(self.num)) |i| {
                self.list.?[i] = self.list.?[i + 1];
            }
        }

        pub fn addUnique(self: *Self, obj: *const T) error{OutOfMemory}!usize {
            return self.findIndex(obj) orelse try self.append(obj.*);
        }

        pub fn remove(self: *Self, obj: *const T) bool {
            if (self.findIndex(obj)) |index| {
                removeIndex(index);
                return true;
            }

            return false;
        }

        pub fn findIndex(self: *const Self, obj: *const T) ?usize {
            return for (self.constSlice(), 0..) |*item_ptr, i| {
                if (item_ptr.* == obj.*) break i;
            } else null;
        }

        pub fn allocOne(self: *Self) error{OutOfMemory}!*T {
            if (self.list == null) {
                try self.resize(@intCast(self.granularity));
            }

            if (self.num == self.size) {
                try self.resize(@intCast(self.size + self.granularity));
            }

            const new_item = &self.list.?[@intCast(self.num)];
            self.num += 1;

            return new_item;
        }

        pub fn setNum(self: *Self, num: usize) error{OutOfMemory}!void {
            if (num > self.size) {
                try self.resize(num);
            }

            self.num = @intCast(num);
        }

        pub fn resizeWithGranularity(
            self: *Self,
            size: usize,
            granularity: usize,
        ) error{OutOfMemory}!void {
            self.granularity = @intCast(granularity);
            try self.resize(size);
        }

        pub fn resize(self: *Self, size: usize) error{OutOfMemory}!void {
            if (size == 0) {
                self.clear();
                return;
            }

            if (size == @as(usize, @intCast(self.size))) return;

            const allocator = global.gpa.allocator();

            const new_list = if (self.list) |_|
                try self.realloc(allocator, size)
            else
                try allocator.alloc(T, size);

            self.list = new_list.ptr;
            self.size = @intCast(size);

            if (self.size < self.num) {
                self.num = self.size;
            }
        }

        pub fn realloc(self: *Self, allocator: std.mem.Allocator, size: usize) error{OutOfMemory}![]T {
            const list_ptr = self.list orelse @panic("uninitialzied");
            const list = list_ptr[0..@intCast(self.size)];
            if (!std.meta.hasMethod(T, "move"))
                return try allocator.realloc(list, size);

            defer allocator.free(list);

            const new_list = try allocator.alloc(T, size);
            errdefer allocator.free(new_list);

            const current_len: usize = @intCast(self.num);
            const current_list = list[0..@min(current_len, size)];
            for (current_list, new_list[0..current_list.len]) |*old_item, *new_item| {
                old_item.move(new_item);
            }

            return new_list;
        }

        pub fn append(self: *Self, obj: T) error{OutOfMemory}!usize {
            if (self.list == null) {
                try self.resize(@intCast(self.granularity));
            }

            if (self.num == self.size) {
                if (self.granularity == 0) {
                    self.granularity = 16;
                }

                const size = self.size + self.granularity;
                try self.resize(@intCast(size - @mod(size, self.granularity)));
            }

            const index: usize = @intCast(self.num);
            self.list.?[index] = obj;
            self.num += 1;

            return index;
        }

        pub fn assureSizeUndef(self: *Self, size: usize) error{OutOfMemory}!void {
            var new_size = size;
            if (new_size > self.size) {
                if (self.granularity == 0) self.granularity = 16;
            }

            new_size += @intCast(self.granularity - 1);
            new_size -= new_size % @as(usize, @intCast(self.granularity));
            try self.resize(new_size);

            self.num = @intCast(size);
        }

        pub fn assureSizeInit(self: *Self, size: usize, init_value: T) error{OutOfMemory}!void {
            var new_size = size;
            if (new_size > self.size) {
                if (self.granularity == 0) self.granularity = 16;
            }

            new_size += @intCast(self.granularity - 1);
            new_size -= new_size % @as(usize, @intCast(self.granularity));
            try self.resize(new_size);

            const len: usize = @intCast(self.num);
            for (len..new_size) |i| {
                self.list.?[i] = init_value;
            }

            self.num = @intCast(size);
        }

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
            const allocator = global.gpa.allocator();

            if (self.list) |list| {
                allocator.free(list[0..@intCast(self.size)]);
            }

            self.list = null;
            self.num = 0;
            self.size = 0;
        }
    };
}

pub fn idStaticList(T: type, size: usize) type {
    return extern struct {
        num: c_int = 0,
        list: [size]T = undefined,

        const Self = @This();

        pub fn fromSlice(init_slice: []const T) Self {
            var static_list = Self{ .num = @intCast(init_slice.len) };
            @memcpy(static_list.slice(), init_slice);

            return static_list;
        }

        pub fn append(self: *Self, obj: T) error{OutOfMemory}!usize {
            if (self.num < size) {
                const len: usize = @intCast(self.num);
                self.list[len] = obj;
                self.num += 1;

                return len;
            }

            return error.OutOfMemory;
        }

        pub inline fn memAllocated(self: *const Self) usize {
            return @sizeOf(@TypeOf(self.list));
        }

        pub inline fn slice(self: *Self) []T {
            return self.list[0..@intCast(self.num)];
        }

        pub inline fn constSlice(self: *const Self) []const T {
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
    const NULL_INDEX: i32 = -1;
    var INVALID_INDEX: [1]i32 = .{-1};
    const DEFAULT_HASH_GRANULARITY = 1024;
    const DEFAULT_HASH_SIZE = 1024;

    hash_size: u32 = DEFAULT_HASH_SIZE,
    hash: [*]i32 = &INVALID_INDEX,
    index_size: u32 = DEFAULT_HASH_SIZE,
    index_chain: [*]i32 = &INVALID_INDEX,
    granularity: u32 = DEFAULT_HASH_GRANULARITY,
    hash_mask: i32 = DEFAULT_HASH_SIZE - 1,
    lookup_mask: i32 = 0,

    pub fn add(hash_index: *idHashIndex, key: u32, index: u32) error{OutOfMemory}!void {
        std.debug.assert(index >= 0);

        if (hash_index.hash == &INVALID_INDEX) {
            try hash_index.allocate(
                hash_index.hash_size,
                if (index >= hash_index.index_size)
                    index + 1
                else
                    hash_index.index_size,
            );
        } else if (index >= hash_index.index_size) {
            try hash_index.resizeIndex(index + 1);
        }

        const h: usize = @intCast(@as(i32, @intCast(key)) & hash_index.hash_mask);
        hash_index.index_chain[index] = hash_index.hash[h];
        hash_index.hash[h] = @intCast(index);
    }

    pub fn clear(hash_index: *idHashIndex) void {
        if (hash_index.hash != &INVALID_INDEX) {
            @memset(hash_index.hash[0..hash_index.hash_size], NULL_INDEX);
        }
    }

    fn allocate(hash_index: *idHashIndex, hash_size: usize, index_size: usize) error{OutOfMemory}!void {
        std.debug.assert(std.math.isPowerOfTwo(hash_size));
        hash_index.free();

        var allocator = global.gpa.allocator();
        const hash = try allocator.alloc(c_int, hash_size);
        errdefer allocator.free(hash);
        @memset(hash, NULL_INDEX);

        const index_chain = try allocator.alloc(c_int, index_size);
        @memset(index_chain, NULL_INDEX);

        hash_index.hash = hash.ptr;
        hash_index.hash_size = @intCast(hash.len);
        hash_index.index_chain = index_chain.ptr;
        hash_index.index_size = @intCast(index_chain.len);
        hash_index.hash_mask = @intCast(hash_size - 1);
        hash_index.lookup_mask = -1;
    }

    pub fn free(hash_index: *idHashIndex) void {
        var allocator = global.gpa.allocator();
        if (hash_index.hash != &INVALID_INDEX) {
            allocator.free(hash_index.hash[0..hash_index.hash_size]);
            hash_index.hash = &INVALID_INDEX;
        }

        if (hash_index.index_chain != &INVALID_INDEX) {
            allocator.free(hash_index.index_chain[0..hash_index.index_size]);
            hash_index.index_chain = &INVALID_INDEX;
        }

        hash_index.lookup_mask = 0;
    }

    pub fn resizeIndex(hash_index: *idHashIndex, index_size: usize) error{OutOfMemory}!void {
        if (index_size <= hash_index.index_size) return;

        const granularity = @as(usize, @intCast(hash_index.granularity));
        const mod: usize = index_size % granularity;

        const new_size = if (mod == 0)
            index_size
        else
            index_size + granularity - mod;

        if (hash_index.index_chain == &INVALID_INDEX) {
            hash_index.index_size = @intCast(new_size);
            return;
        }

        var allocator = global.gpa.allocator();
        const old_index_size: usize = @intCast(hash_index.index_size);
        const old_index_chain = hash_index.index_chain[0..old_index_size];
        const index_chain = try allocator.alloc(c_int, new_size);
        @memcpy(index_chain[0..old_index_size], old_index_chain);
        @memset(index_chain[old_index_size..new_size], NULL_INDEX);

        allocator.free(old_index_chain);
        hash_index.index_chain = index_chain.ptr;
        hash_index.index_size = @intCast(new_size);
    }

    pub fn generateKey(hash_index: *const idHashIndex, str: []const u8, case_sensetive: bool) u32 {
        const hash = if (case_sensetive)
            idStr.hash(str)
        else
            idStr.caseInsensetiveHash(str);

        return @intCast(@as(i32, @intCast(hash)) & hash_index.hash_mask);
    }

    pub fn first(hash_index: *const idHashIndex, key: u32) c_int {
        const index: usize = @intCast(
            @as(i32, @intCast(key)) & hash_index.hash_mask & hash_index.lookup_mask,
        );

        return hash_index.hash[index];
    }

    pub fn next(hash_index: *const idHashIndex, index: u32) c_int {
        const next_index: usize = @intCast(
            @as(i32, @intCast(index)) & hash_index.lookup_mask,
        );

        return hash_index.index_chain[next_index];
    }
};

pub const idFile = opaque {};

pub const idDict = extern struct {
    const KeyValue = extern struct {
        key: *const anyopaque,
        value: *const anyopaque,
    };

    args: idList(KeyValue),
    argsHash: idHashIndex,
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

const SignalHandle = @import("sys/threading.zig").SignalHandle;
pub const idSysThread = extern struct {
    const idSysSignal = extern struct {
        handle: SignalHandle,
    };

    vptr: *anyopaque,
    name: idStr,
    thradHandle: usize,
    isWorker: bool,
    isRunning: bool,
    isTerminating: bool,
    moreWorkToDo: bool,
    signalWorkerDonw: idSysSignal,
    signalMoreWorkToDo: idSysSignal,
    signalMutex: idSysMutex,
};
