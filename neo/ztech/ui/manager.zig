const std = @import("std");
const TokenParser = @import("../framework/token_parser.zig").TokenParser;
const UserInterface = @import("user_interface.zig").UserInterface;
const Material = @import("../renderer/material.zig").Material;
const Font = @import("../renderer/font.zig").Font;
const idlib = @import("../idlib.zig");
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;

const Rectangle = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

const ScrollBarType = enum(c_int) {
    hback,
    vback,
    thumb,
    right,
    left,
    up,
    down,
};

const CursorType = enum(c_int) {
    arrow,
    hand,
    joy1,
    joy2,
    joy3,
    joy4,
};

const DeviceContextLegacy = extern struct {
    vptr: *anyopaque,
    cursor_images: [@typeInfo(CursorType).Enum.fields.len]*const Material,
    scroll_bar_images: [@typeInfo(ScrollBarType).Enum.fields.len]*const Material,
    white_image: *const Material,
    active_font: ?*Font,
    x_scale: f32,
    y_scale: f32,
    x_offset: f32,
    y_offset: f32,
    cursor: u32,
    clip_rects: idlib.List(Rectangle),
    enable_clipping: bool,
    over_strike_mode: bool,
    mat: CMat3,
    mat_is_identity: bool,
    origin: CVec3,
    initialized: bool,
};

const DeviceContext = extern struct {
    base: DeviceContextLegacy,
    clip_x1: f32,
    clip_x2: f32,
    clip_y1: f32,
    clip_y2: f32,
};

pub const UserInterfaceManager = extern struct {
    vptr: *anyopaque,
    screen_rect: Rectangle,
    device_context_legacy: DeviceContextLegacy,
    device_context: DeviceContext,
    guis: idlib.List(?*UserInterface),
    demo_guis: idlib.List(?*UserInterface),
    map_parser: TokenParser,

    pub const FindGuiOrLoadError = error{} || std.mem.Allocator.Error;
    pub fn findGuiOrLoad(
        manager: *const UserInterfaceManager,
        qpath: []const u8,
        allocator: std.mem.Allocator,
    ) FindGuiOrLoadError!*UserInterface {
        return manager.findGui(qpath) orelse try autoloadGui(qpath, allocator);
    }

    fn findGui(manager: *const UserInterfaceManager, qpath: []const u8) ?*UserInterface {
        for (manager.guis.constSlice()) |opt_ui| {
            const gui = opt_ui orelse continue;
            const source_file = gui.source.constSlice();

            if (std.ascii.eqlIgnoreCase(source_file, qpath)) {
                if (gui.refs == 0) {
                    try gui.initFromFile(source_file);
                }

                gui.refs += 1;
                return gui;
            }
        }

        return null;
    }

    const AutoloadGuiError = error{} || std.mem.Allocator.Error;
    fn autoloadGui(qpath: []const u8, allocator: std.mem.Allocator) AutoloadGuiError!*UserInterface {
        const gui = try allocator.create(UserInterface);
        errdefer allocator.destroy(gui);

        try gui.initFromFile(qpath);
        gui.unique = false;

        return gui;
    }
};

pub const instance = @extern(*UserInterfaceManager, .{ .name = "uiManagerLocal" });
