const idlib = @import("../idlib.zig");

const Window = extern struct {};

pub const UserInterface = extern struct {
    active: bool,
    loading: bool,
    interactive: bool,
    unique: bool,
    state: idlib.idDict,
    desktop: Window,
    bind_handler: Window,
    source: idlib.idStr,
    activate_str: idlib.idStr,
    pending_cmd: idlib.idStr,
    return_cmd: idlib.idStr,
    timestampe: idlib.ID_TIME_T,
    cursor_x: f32,
    cursor_y: f32,
    time: u32,
    refs: u32,

    pub fn initFromFile(ui: *UserInterface, path: []const u8) error{}!void {
        _ = ui;
        _ = path;
        @panic("not implemented");
    }
};
