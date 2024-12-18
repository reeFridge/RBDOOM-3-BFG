const idlib = @import("../idlib.zig");

const Window = extern struct {};

pub const UserInterface = extern struct {
    active: bool,
    loading: bool,
    interactive: bool,
    unique: bool,
    state: idlib.Dict,
    desktop: Window,
    bind_handler: Window,
    source: idlib.Str,
    activate_str: idlib.Str,
    pending_cmd: idlib.Str,
    return_cmd: idlib.Str,
    timestampe: idlib.Time,
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
