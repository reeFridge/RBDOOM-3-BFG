pub const Session = opaque {
    extern fn c_session_pump(*Session) callconv(.C) void;

    pub fn pump(session_: *Session) void {
        c_session_pump(session_);
    }
};

pub const instance = @extern(*Session, .{ .name = "sessionLocalWin" });
