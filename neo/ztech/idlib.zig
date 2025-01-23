const Vec3 = @import("math/vector.zig").Vec3;
const std = @import("std");
const global = @import("global.zig");
const fs = @import("framework/file_system.zig");

pub const Time = i64;

pub const Str = extern struct {
    const Allocator = std.mem.Allocator;

    const file_hash_size: u32 = 1024;
    const static_buffer_len: u32 = 20;
    const alloc_granularity: u32 = 32;

    const AllocedAndFlag = packed struct(u32) {
        alloced: u31 = static_buffer_len,
        flag: bool = false,
    };

    len: u32 = 0,
    alloced_ptr: ?[*]u8 = null,
    alloced_and_flag: AllocedAndFlag = .{},
    static_buffer: [static_buffer_len]u8 = std.mem.zeroes([static_buffer_len]u8),

    pub fn initStatic(contents: []const u8) Str {
        var str = Str{};
        str.assignStaticAssureSize(contents);

        return str;
    }

    pub inline fn buffer(self: *Str) []u8 {
        return if (self.alloced_ptr) |data_ptr|
            data_ptr[0..self.alloced()]
        else
            &self.static_buffer;
    }

    pub inline fn slice(self: *Str) []u8 {
        return self.buffer()[0..self.len];
    }

    pub inline fn constSlice(self: *const Str) []const u8 {
        return @as(*Str, @constCast(self)).slice();
    }

    pub inline fn constSliceZ(self: *const Str) [:0]const u8 {
        return @as(*Str, @constCast(self)).buffer()[0..self.len :0];
    }

    pub fn empty(self: *Str) void {
        self.len = 0;
    }

    pub fn assignStaticAssureSize(self: *Str, contents: []const u8) void {
        std.mem.copyForwards(u8, &self.static_buffer, contents);
        self.len = @intCast(contents.len);
    }

    pub fn assignSlice(
        self: *Str,
        arg_slice: []const u8,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (arg_slice.len == 0) {
            self.len = 0;
            return;
        }

        if (self.buffer().ptr == arg_slice.ptr) return;

        try self.ensureAlloced(arg_slice.len, false, allocator);
        std.mem.copyForwards(u8, self.buffer(), arg_slice);
        self.len = @intCast(arg_slice.len);
    }

    pub fn assignSliceZ(
        self: *Str,
        arg_slice: []const u8,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (arg_slice.len == 0) {
            self.len = 0;
            return;
        }

        std.debug.assert(self.buffer().ptr != arg_slice.ptr);

        try self.ensureAlloced(arg_slice.len + 1, false, allocator);
        self.buffer()[arg_slice.len] = 0;

        std.mem.copyForwards(u8, self.buffer(), arg_slice);
        self.len = @intCast(arg_slice.len);
    }

    pub fn appendSlice(
        self: *Str,
        arg_slice: []const u8,
        allocator: Allocator,
    ) Allocator.Error!void {
        const new_len: usize = @as(usize, @intCast(self.len)) + arg_slice.len;

        try self.ensureAlloced(new_len, true, allocator);
        const data = self.buffer();

        const start: u32 = self.len;
        for (arg_slice, 0..) |char, i| {
            data[start + i] = char;
        }

        self.len = @intCast(new_len);
    }

    pub fn stripTrailingChar(self: *Str, char: u8) void {
        const data = self.slice();
        var i: usize = @intCast(self.len);
        while (i > 0 and data[i - 1] == char) : (i -= 1) {
            data[i - 1] = 0;
            self.len -= 1;
        }
    }

    pub fn clear(self: *Str, allocator: Allocator) void {
        if (self.isStatic()) {
            self.len = 0;
            return;
        }

        self.deinit(allocator);
        self.* = Str{};
    }

    pub fn deinit(self: *Str, allocator: Allocator) void {
        if (self.isStatic()) return;

        if (self.alloced_ptr) |ptr| {
            allocator.free(ptr[0..self.alloced()]);
        }
    }

    pub fn ensureAlloced(
        self: *Str,
        amount: usize,
        keep_old: bool,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (self.isStatic()) return;

        if (amount > self.alloced()) {
            try self.reallocate(amount, keep_old, allocator);
        }
    }

    fn reallocate(
        self: *Str,
        amount: usize,
        keep_old: bool,
        allocator: Allocator,
    ) Allocator.Error!void {
        std.debug.assert(amount > 0);

        const mod = @mod(amount, alloc_granularity);
        const new_size = if (mod == 0)
            amount
        else
            amount + alloc_granularity - mod;

        const new_buffer = try allocator.alloc(u8, new_size);
        for (new_buffer) |*char| char.* = 0;

        const old_alloced_buffer = if (self.alloced_ptr) |data|
            data[0..self.alloced()]
        else
            null;

        self.setAlloced(new_size);

        if (keep_old) {
            std.mem.copyForwards(u8, new_buffer, self.slice());
        }

        if (old_alloced_buffer) |old_buffer| {
            allocator.free(old_buffer);
        }

        self.alloced_ptr = new_buffer.ptr;
    }

    inline fn setAlloced(self: *Str, size: usize) void {
        self.alloced_and_flag.alloced = @intCast(size);
    }

    inline fn alloced(self: *const Str) usize {
        return self.alloced_and_flag.alloced;
    }

    inline fn setStatic(self: *Str, is_static: bool) void {
        self.alloced_and_flag.flag = is_static;
    }

    inline fn isStatic(self: *const Str) bool {
        return self.alloced_and_flag.flag;
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

        result &= file_hash_size - 1;

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
};

pub fn List(T: type) type {
    return extern struct {
        const Allocator = std.mem.Allocator;
        const Self = @This();
        const default_granularity = 16;

        num: u32 = 0,
        size: u32 = 0,
        granularity: u32 = default_granularity,
        list: ?[*]T = null,
        mem_tag: u8 = 0,

        pub fn removeIndex(self: *Self, index: usize) void {
            std.debug.assert(self.list != null);
            std.debug.assert(index < self.num);

            self.num -= 1;
            for (index..self.num) |i| {
                self.list.?[i] = self.list.?[i + 1];
            }
        }

        pub fn addUnique(
            self: *Self,
            obj: *const T,
            allocator: Allocator,
        ) Allocator.Error!usize {
            return self.findIndex(obj) orelse try self.append(obj.*, allocator);
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

        pub fn allocOne(self: *Self, allocator: Allocator) Allocator.Error!*T {
            if (self.list == null) {
                try self.resize(self.granularity, allocator);
            }

            if (self.num == self.size) {
                try self.resize(self.size + self.granularity, allocator);
            }

            const new_item = &self.list.?[self.num];
            self.num += 1;

            return new_item;
        }

        pub fn setNumAssureSize(self: *Self, num: usize) void {
            std.debug.assert(num <= self.size);
            self.num = @intCast(num);
        }

        pub fn setNum(
            self: *Self,
            num: usize,
            allocator: Allocator,
        ) Allocator.Error!void {
            if (num > self.size) {
                try self.resize(num, allocator);
            }

            self.num = @intCast(num);
        }

        pub fn resizeWithGranularity(
            self: *Self,
            size: usize,
            granularity: usize,
            allocator: Allocator,
        ) Allocator.Error!void {
            self.granularity = @intCast(granularity);
            try self.resize(size, allocator);
        }

        pub fn resize(
            self: *Self,
            size: usize,
            allocator: Allocator,
        ) Allocator.Error!void {
            if (size == 0) {
                self.clear(allocator);
                return;
            }

            if (size == @as(usize, @intCast(self.size))) return;

            const new_list = if (self.list) |_|
                try self.realloc(size, allocator)
            else
                try allocator.alloc(T, size);

            self.list = new_list.ptr;
            self.size = @intCast(size);

            if (self.size < self.num) {
                self.num = self.size;
            }
        }

        pub fn realloc(
            self: *Self,
            size: usize,
            allocator: Allocator,
        ) Allocator.Error![]T {
            const list_ptr = self.list orelse @panic("uninitialzied");
            const list = list_ptr[0..self.size];
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

        pub fn append(self: *Self, obj: T, allocator: Allocator) Allocator.Error!usize {
            if (self.list == null) {
                try self.resize(self.granularity, allocator);
            }

            if (self.num == self.size) {
                if (self.granularity == 0) {
                    self.granularity = 16;
                }

                const size = self.size + self.granularity;
                try self.resize(size - @mod(size, self.granularity), allocator);
            }

            const index: usize = @intCast(self.num);
            self.list.?[index] = obj;
            self.num += 1;

            return index;
        }

        pub fn assureSizeUndef(
            self: *Self,
            size: usize,
            allocator: Allocator,
        ) Allocator.Error!void {
            var new_size = size;
            if (new_size > self.size) {
                if (self.granularity == 0) self.granularity = 16;
            }

            new_size += @intCast(self.granularity - 1);
            new_size -= new_size % @as(usize, @intCast(self.granularity));
            try self.resize(new_size, allocator);

            self.num = @intCast(size);
        }

        pub fn assureSizeInit(
            self: *Self,
            size: usize,
            init_value: T,
            allocator: Allocator,
        ) Allocator.Error!void {
            var new_size = size;
            if (new_size > self.size) {
                if (self.granularity == 0) self.granularity = 16;
            }

            new_size += @intCast(self.granularity - 1);
            new_size -= new_size % @as(usize, @intCast(self.granularity));
            try self.resize(new_size, allocator);

            const len: usize = @intCast(self.num);
            for (len..new_size) |i| {
                self.list.?[i] = init_value;
            }

            self.num = @intCast(size);
        }

        pub inline fn constSlice(self: *const Self) []const T {
            return if (self.list) |list|
                list[0..self.num]
            else
                &.{};
        }

        pub inline fn slice(self: *Self) []T {
            return if (self.list) |list|
                list[0..self.num]
            else
                &.{};
        }

        pub fn clear(self: *Self, allocator: Allocator) void {
            if (self.list) |list| {
                allocator.free(list[0..self.size]);
            }

            self.list = null;
            self.num = 0;
            self.size = 0;
        }
    };
}

pub fn StaticList(T: type, size: usize) type {
    return extern struct {
        num: u32 = 0,
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
            return self.list[0..self.num];
        }

        pub inline fn constSlice(self: *const Self) []const T {
            return self.list[0..self.num];
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

pub const SysMutex = extern struct {
    handle: MutexHandle = std.mem.zeroes(MutexHandle),

    extern fn c_sysMutex_unlock(*MutexHandle) callconv(.C) void;
    extern fn c_sysMutex_lock(*MutexHandle, bool) callconv(.C) bool;
    extern fn c_sysMutex_create(*MutexHandle) callconv(.C) void;
    extern fn c_sysMutex_destroy(*MutexHandle) callconv(.C) void;

    pub fn init() SysMutex {
        var handle = MutexHandle{ .data = undefined };
        c_sysMutex_create(&handle);

        return .{ .handle = handle };
    }

    pub fn deinit(mutex: *SysMutex) void {
        c_sysMutex_destroy(&mutex.handle);
    }

    pub fn lockBlocking(mutex: *SysMutex) bool {
        return c_sysMutex_lock(&mutex.handle, true);
    }

    pub fn lock(mutex: *SysMutex) bool {
        return c_sysMutex_lock(&mutex.handle, false);
    }

    pub fn unlock(mutex: *SysMutex) void {
        c_sysMutex_unlock(&mutex.handle);
    }
};

pub const HashIndex = extern struct {
    const Allocator = std.mem.Allocator;
    const null_index: i32 = -1;
    var invalid_index: [1]i32 = .{-1};
    const default_hash_granularity = 1024;
    const default_hash_size = 1024;

    hash_size: u32 = default_hash_size,
    hash: [*]i32 = &invalid_index,
    index_size: u32 = default_hash_size,
    index_chain: [*]i32 = &invalid_index,
    granularity: u32 = default_hash_granularity,
    hash_mask: i32 = default_hash_size - 1,
    lookup_mask: i32 = 0,

    pub fn init(initial_hash_size: u32, initial_index_size: u32) HashIndex {
        var hash = HashIndex{};

        hash.hash_size = initial_hash_size;
        hash.index_size = initial_index_size;
        hash.hash_mask = @intCast(initial_hash_size - 1);

        return hash;
    }

    pub fn remove(hash_index: *HashIndex, key: u32, index: u32) void {
        const k: usize = @intCast(@as(i32, @intCast(key)) & hash_index.hash_mask);

        if (hash_index.hash == &invalid_index) return;

        if (hash_index.hash[k] == @as(i32, @intCast(index))) {
            hash_index.hash[k] = hash_index.index_chain[index];
        } else {
            var i = hash_index.hash[k];
            while (i != -1) : (i = hash_index.index_chain[@intCast(i)]) {
                const ui: u32 = @intCast(i);
                if (hash_index.index_chain[ui] == @as(i32, @intCast(index))) {
                    hash_index.index_chain[ui] = hash_index.index_chain[index];
                    break;
                }
            }
        }

        hash_index.index_chain[index] = -1;
    }

    pub fn removeIndex(hash_index: *HashIndex, key: u32, index: u32) void {
        _ = hash_index;
        _ = key;
        _ = index;
        @panic("not implemented");
    }

    pub fn add(
        hash_index: *HashIndex,
        key: u32,
        index: u32,
        allocator: Allocator,
    ) Allocator.Error!void {
        std.debug.assert(index >= 0);

        if (hash_index.hash == &invalid_index) {
            try hash_index.allocate(
                hash_index.hash_size,
                if (index >= hash_index.index_size)
                    index + 1
                else
                    hash_index.index_size,
                allocator,
            );
        } else if (index >= hash_index.index_size) {
            try hash_index.resizeIndex(index + 1, allocator);
        }

        const h: usize = @intCast(@as(i32, @intCast(key)) & hash_index.hash_mask);
        hash_index.index_chain[index] = hash_index.hash[h];
        hash_index.hash[h] = @intCast(index);
    }

    pub fn clear(hash_index: *HashIndex) void {
        if (hash_index.hash != &invalid_index) {
            @memset(hash_index.hash[0..hash_index.hash_size], null_index);
        }
    }

    fn allocate(
        hash_index: *HashIndex,
        hash_size: usize,
        index_size: usize,
        allocator: Allocator,
    ) Allocator.Error!void {
        std.debug.assert(std.math.isPowerOfTwo(hash_size));
        hash_index.free(allocator);

        const hash = try allocator.alloc(i32, hash_size);
        errdefer allocator.free(hash);
        @memset(hash, null_index);

        const index_chain = try allocator.alloc(i32, index_size);
        @memset(index_chain, null_index);

        hash_index.hash = hash.ptr;
        hash_index.hash_size = @intCast(hash.len);
        hash_index.index_chain = index_chain.ptr;
        hash_index.index_size = @intCast(index_chain.len);
        hash_index.hash_mask = @intCast(hash_size - 1);
        hash_index.lookup_mask = -1;
    }

    pub fn free(hash_index: *HashIndex, allocator: Allocator) void {
        if (hash_index.hash != &invalid_index) {
            allocator.free(hash_index.hash[0..hash_index.hash_size]);
            hash_index.hash = &invalid_index;
        }

        if (hash_index.index_chain != &invalid_index) {
            allocator.free(hash_index.index_chain[0..hash_index.index_size]);
            hash_index.index_chain = &invalid_index;
        }

        hash_index.lookup_mask = 0;
    }

    pub fn resizeIndex(
        hash_index: *HashIndex,
        index_size: usize,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (index_size <= hash_index.index_size) return;

        const granularity = @as(usize, @intCast(hash_index.granularity));
        const mod: usize = index_size % granularity;

        const new_size = if (mod == 0)
            index_size
        else
            index_size + granularity - mod;

        if (hash_index.index_chain == &invalid_index) {
            hash_index.index_size = @intCast(new_size);
            return;
        }

        const old_index_size: usize = @intCast(hash_index.index_size);
        const old_index_chain = hash_index.index_chain[0..old_index_size];
        const index_chain = try allocator.alloc(i32, new_size);
        @memcpy(index_chain[0..old_index_size], old_index_chain);
        @memset(index_chain[old_index_size..new_size], null_index);

        allocator.free(old_index_chain);
        hash_index.index_chain = index_chain.ptr;
        hash_index.index_size = @intCast(new_size);
    }

    pub fn generateKeyVec3(hash_index: *const HashIndex, vec: *const Vec3(f32)) u32 {
        const x: i32 = @intFromFloat(vec.v[0]);
        const y: i32 = @intFromFloat(vec.v[1]);
        const z: i32 = @intFromFloat(vec.v[2]);

        const vec_sum = x + y + z;
        const hash_signed = vec_sum & hash_index.hash_mask;

        return @intCast(hash_signed);
    }

    pub fn generateKey(
        hash_index: *const HashIndex,
        str: []const u8,
        case_sensetive: bool,
    ) u32 {
        const hash = if (case_sensetive)
            Str.hash(str)
        else
            Str.caseInsensetiveHash(str);

        return @intCast(@as(i32, @intCast(hash)) & hash_index.hash_mask);
    }

    pub fn first(hash_index: *const HashIndex, key: u32) i32 {
        const index: usize = @intCast(
            @as(i32, @intCast(key)) & hash_index.hash_mask & hash_index.lookup_mask,
        );

        return hash_index.hash[index];
    }

    pub fn next(hash_index: *const HashIndex, index: u32) i32 {
        const next_index: usize = @intCast(
            @as(i32, @intCast(index)) & hash_index.lookup_mask,
        );

        return hash_index.index_chain[next_index];
    }
};

pub const File = opaque {};

pub const Dict = extern struct {
    const KeyValue = extern struct {
        key: *const anyopaque,
        value: *const anyopaque,
    };

    args: List(KeyValue) = .{},
    args_hash: HashIndex = .{},
};

pub const ZipCacheEntry = extern struct {
    const max_filename: usize = 2048 - 1;

    filename: [max_filename:0]u8,
    offset: u64,
    length: u64,
    owner: *ZipContainer,
};

pub const ZipContainer = extern struct {
    const UnzFile = opaque {};
    const max_filename = 256 - 1;

    filename: [max_filename:0]u8,
    zip_file_handle: ?*UnzFile,
    checksum: u32,
    num_file_resources: u32,
    cache_table: List(ZipCacheEntry),
    cache_hash: HashIndex,
};

pub const StrList = List(Str);

pub const PreloadManifest = extern struct {
    pub const PreloadType = enum(c_int) {
        image,
        model,
        sample,
        anim,
        collision,
        particle,
    };

    pub const ImagePreload = extern struct {
        filter: u32,
        repeat: u32,
        usage: u32,
        cube_map: u32,
    };

    pub const PreloadEntry = extern struct {
        res_type: PreloadType,
        resource_name: Str,
        img_data: ImagePreload,
    };

    entries: List(PreloadEntry),
    filename: Str,
};

const SignalHandle = @import("sys/threading.zig").SignalHandle;

pub const SysSignal = extern struct {
    handle: SignalHandle = .{},
};

pub const SysThread = extern struct {
    vptr: *anyopaque,
    name: Str,
    thrad_handle: usize,
    is_worker: bool,
    is_running: bool,
    is_terminating: bool,
    more_work_to_do: bool,
    signal_worker_down: SysSignal,
    signal_more_work_to_do: SysSignal,
    signal_mutex: SysMutex,
};
