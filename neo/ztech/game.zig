const std = @import("std");

const CTimeState = extern struct {
    time: c_int,
    previous_time: c_int,

    pub fn delta(state: CTimeState) i32 {
        return state.time - state.previous_time;
    }
};

const KeyValue = extern struct {
    key: *const anyopaque,
    value: *const anyopaque,
};

fn List(T: type) type {
    return extern struct {
        num: c_int,
        size: c_int,
        granularity: c_int,
        list: [*]T,
        memTag: u8,
    };
}

const HashIndex = extern struct {
    hashSize: c_int,
    hash: *c_int,
    indexSize: c_int,
    indexChain: *c_int,
    granularity: c_int,
    hashMask: c_int,
    lookupMask: c_int,
};

pub const Dict = extern struct {
    args: List(KeyValue),
    argsHash: HashIndex,
};

pub const DeclEntityDef = extern struct {
    base: *anyopaque,
    dict: Dict,

    pub fn name(self: DeclEntityDef) []const u8 {
        const c_str = c_declGetName(&self);

        return std.mem.span(c_str);
    }

    pub fn index(self: DeclEntityDef) usize {
        return @intCast(c_declIndex(&self));
    }
};

pub extern fn c_getTimeState() callconv(.C) CTimeState;
pub extern fn c_isNewFrame() callconv(.C) bool;

pub extern fn c_findEntityDef([*c]const u8) callconv(.C) ?*const DeclEntityDef;
pub extern fn c_declByIndex(c_int) callconv(.C) ?*const DeclEntityDef;
pub extern fn c_declGetName(*const anyopaque) callconv(.C) [*c]const u8;
pub extern fn c_declIndex(*const anyopaque) callconv(.C) c_int;
