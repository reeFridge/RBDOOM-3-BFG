pub fn idList(T: type) type {
    return extern struct {
        num: c_int,
        size: c_int,
        granularity: c_int,
        list: ?*T,
        memTag: u8,
    };
}

pub fn idStaticList(T: type, size: usize) type {
    return extern struct {
        num: c_int,
        list: [size]T,
    };
}

pub const idSysMutex = extern struct {
    const MutexHandle = @import("std").c.pthread_mutex_t;
    handle: MutexHandle,
};

pub const idHashIndex = extern struct {
    hashSize: c_int,
    hash: ?*c_int,
    indexSize: c_int,
    indexChain: ?*c_int,
    granularity: c_int,
    hashMask: c_int,
    lookupMask: c_int,
};

pub const idDict = extern struct {
    const KeyValue = extern struct {
        key: *const anyopaque,
        value: *const anyopaque,
    };

    args: idList(KeyValue),
    argsHash: idHashIndex,
};
