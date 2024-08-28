const std = @import("std");

extern fn c_memFree(*anyopaque) callconv(.C) void;

pub fn idList(T: type) type {
    return extern struct {
        const Self = @This();

        num: c_int,
        size: c_int,
        granularity: c_int,
        list: ?[*]T,
        memTag: u8,

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
pub const MutexHandle = extern struct {
    data: [40]u8,
};

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

pub const idDict = extern struct {
    const KeyValue = extern struct {
        key: *const anyopaque,
        value: *const anyopaque,
    };

    args: idList(KeyValue),
    argsHash: idHashIndex,
};
