const std = @import("std");

const MAX_EDIT_LINE = 256;

const AutoComplete = extern struct {
    valid: bool,
    length: u32,
    completion_string: [MAX_EDIT_LINE]u8,
    current_match: [MAX_EDIT_LINE]u8,
    match_count: c_int,
    match_index: c_int,
    find_match_index: c_int,
};

pub const EditField = extern struct {
    cursor: c_int = 0,
    scroll: c_int = 0,
    width_in_chars: u32 = 0,
    buffer: [MAX_EDIT_LINE]u8 = undefined,
    auto_complete: AutoComplete = std.mem.zeroes(AutoComplete),

    pub fn init() EditField {
        var edit_field = EditField{};
        edit_field.clear();

        return edit_field;
    }

    pub fn clear(edit_field: *EditField) void {
        edit_field.buffer[0] = 0;
        edit_field.cursor = 0;
        edit_field.scroll = 0;
        edit_field.auto_complete.length = 0;
        edit_field.auto_complete.valid = false;
    }
};
