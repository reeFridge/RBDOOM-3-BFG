const std = @import("std");

const MAX_EDIT_LINE = 256;

const AutoComplete = extern struct {
    valid: bool,
    length: c_int,
    completionString: [MAX_EDIT_LINE]u8,
    currentMatch: [MAX_EDIT_LINE]u8,
    matchCount: c_int,
    matchIndex: c_int,
    findMatchIndex: c_int,
};

pub const EditField = extern struct {
    cursor: c_int = 0,
    scroll: c_int = 0,
    widthInChars: c_int = 0,
    buffer: [MAX_EDIT_LINE]u8 = undefined,
    autoComplete: AutoComplete = std.mem.zeroes(AutoComplete),

    pub fn init() EditField {
        var edit_field = EditField{};
        edit_field.clear();

        return edit_field;
    }

    pub fn clear(edit_field: *EditField) void {
        edit_field.buffer[0] = 0;
        edit_field.cursor = 0;
        edit_field.scroll = 0;
        edit_field.autoComplete.length = 0;
        edit_field.autoComplete.valid = false;
    }
};
