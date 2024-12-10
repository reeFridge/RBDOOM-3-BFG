const idlib = @import("../idlib.zig");

const BinaryToken = extern struct {
    token: idlib.idStr = .{},
    token_type: i8 = 0,
    token_subtype: i16 = 0,
};

const TokenIndexes = extern struct {
    token_indexes: idlib.idList(u16) = .{},
    filename: idlib.idStr = .{},
};

pub const TokenParser = extern struct {
    tokens: idlib.idList(BinaryToken) = .{},
    gui_token_indexes: idlib.idList(TokenIndexes) = .{},
    current_token: u32 = 0,
    current_token_list: u32 = 0,
    timestamp: idlib.ID_TIME_T = idlib.FILE_NOT_FOUND_TIMESTAMP,
    preloaded: bool = false,
};
