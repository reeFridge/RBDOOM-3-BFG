const fs = @import("file_system.zig");
const idlib = @import("../idlib.zig");

const BinaryToken = extern struct {
    token: idlib.Str = .{},
    token_type: i8 = 0,
    token_subtype: i16 = 0,
};

const TokenIndexes = extern struct {
    token_indexes: idlib.List(u16) = .{},
    filename: idlib.Str = .{},
};

pub const TokenParser = extern struct {
    tokens: idlib.List(BinaryToken) = .{},
    gui_token_indexes: idlib.List(TokenIndexes) = .{},
    current_token: u32 = 0,
    current_token_list: u32 = 0,
    timestamp: idlib.Time = fs.not_found_time,
    preloaded: bool = false,
};
