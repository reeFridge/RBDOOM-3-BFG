const std = @import("std");
const TokenParser = @import("../framework/token_parser.zig").TokenParser;
const UserInterface = @import("user_interface.zig").UserInterface;
const material = @import("../renderer/material.zig");
const Material = material.Material;
const Font = @import("../renderer/font.zig").Font;
const idlib = @import("../idlib.zig");
const CVec3 = @import("../math/vector.zig").CVec3;
const CVec4 = @import("../math/vector.zig").CVec4;
const CMat3 = @import("../math/matrix.zig").CMat3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const RenderSystem = @import("../renderer/render_system.zig");
const Allocator = std.mem.Allocator;
const DeclManager = @import("../framework/decl_manager.zig").DeclManager;

const Rectangle = extern struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

const ScrollBarType = enum(u32) {
    hback,
    vback,
    thumb,
    right,
    left,
    up,
    down,
};

const CursorType = enum(u32) {
    arrow,
    hand,
    hand_joy1,
    hand_joy2,
    hand_joy3,
    hand_joy4,
};

const Colors = struct {
    pub const purple: CVec4 = .{ .x = 1, .y = 0, .z = 1, .w = 1 };
    pub const orange: CVec4 = .{ .x = 1, .y = 1, .z = 0, .w = 1 };
    pub const yellow: CVec4 = .{ .x = 0, .y = 1, .z = 1, .w = 1 };
    pub const green: CVec4 = .{ .x = 0, .y = 1, .z = 0, .w = 1 };
    pub const blue: CVec4 = .{ .x = 0, .y = 0, .z = 1, .w = 1 };
    pub const red: CVec4 = .{ .x = 1, .y = 0, .z = 0, .w = 1 };
    pub const white: CVec4 = .{ .x = 1, .y = 1, .z = 1, .w = 1 };
    pub const black: CVec4 = .{ .x = 0, .y = 0, .z = 0, .w = 1 };
    pub const none: CVec4 = .{};
};

const DeviceContextLegacy = extern struct {
    vptr: *anyopaque,
    cursor_images: [@typeInfo(CursorType).Enum.fields.len]*Material,
    scroll_bar_images: [@typeInfo(ScrollBarType).Enum.fields.len]*Material,
    white_image: *Material,
    active_font: ?*Font,
    x_scale: f32,
    y_scale: f32,
    x_offset: f32,
    y_offset: f32,
    cursor: CursorType,
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

    pub fn init(
        device_context: *DeviceContext,
        render_system: *RenderSystem,
        decl_manager: *DeclManager,
        allocator: Allocator,
    ) DeclManager.FindDeclError!void {
        device_context.base.x_scale = 1;
        device_context.base.y_scale = 1;
        device_context.base.x_offset = 0;
        device_context.base.y_offset = 0;

        device_context.base.white_image = try decl_manager.findMaterialOrDefault(
            "_white",
            allocator,
        );

        device_context.base.white_image.sort = material.MaterialSort.gui;

        _ = render_system;
        // TODO: render_system.registerFont("")

        device_context.base.cursor_images[@intFromEnum(CursorType.arrow)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/guicursor_arrow.tga",
            allocator,
        );
        device_context.base.cursor_images[@intFromEnum(CursorType.hand)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/guicursor_hand.tga",
            allocator,
        );
        device_context.base.cursor_images[@intFromEnum(CursorType.hand_joy1)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/guicursor_hand_cross.tga",
            allocator,
        );
        device_context.base.cursor_images[@intFromEnum(CursorType.hand_joy2)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/guicursor_hand_circle.tga",
            allocator,
        );
        device_context.base.cursor_images[@intFromEnum(CursorType.hand_joy3)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/guicursor_hand_square.tga",
            allocator,
        );
        device_context.base.cursor_images[@intFromEnum(CursorType.hand_joy4)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/guicursor_hand_triangle.tga",
            allocator,
        );

        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.hback)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/scrollbarh.tga",
            allocator,
        );
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.vback)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/scrollbarv.tga",
            allocator,
        );
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.thumb)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/scrollbar_thumb.tga",
            allocator,
        );
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.right)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/scrollbar_right.tga",
            allocator,
        );
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.left)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/scrollbar_left.tga",
            allocator,
        );
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.up)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/scrollbar_up.tga",
            allocator,
        );
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.down)] = try decl_manager.findMaterialOrDefault(
            "ui/assets/scrollbar_down.tga",
            allocator,
        );

        device_context.base.cursor_images[@intFromEnum(CursorType.arrow)].sort = material.MaterialSort.gui;
        device_context.base.cursor_images[@intFromEnum(CursorType.hand)].sort = material.MaterialSort.gui;
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.hback)].sort = material.MaterialSort.gui;
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.vback)].sort = material.MaterialSort.gui;
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.thumb)].sort = material.MaterialSort.gui;
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.right)].sort = material.MaterialSort.gui;
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.left)].sort = material.MaterialSort.gui;
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.up)].sort = material.MaterialSort.gui;
        device_context.base.scroll_bar_images[@intFromEnum(ScrollBarType.down)].sort = material.MaterialSort.gui;

        device_context.base.cursor = .arrow;
        device_context.base.enable_clipping = true;
        device_context.base.over_strike_mode = true;

        device_context.base.mat = CMat3.fromMat3f(Mat3(f32).identity());
        device_context.base.mat_is_identity = true;
        device_context.base.origin = .{};
        device_context.base.initialized = true;
    }
};

pub const UserInterfaceManager = extern struct {
    vptr: *anyopaque,
    screen_rect: Rectangle,
    device_context_legacy: DeviceContextLegacy, // unused
    device_context: DeviceContext,
    guis: idlib.List(?*UserInterface),
    demo_guis: idlib.List(?*UserInterface),
    map_parser: TokenParser,

    pub fn init(
        manager: *UserInterfaceManager,
        render_system: *RenderSystem,
        decl_manager: *DeclManager,
        allocator: Allocator,
    ) DeclManager.FindDeclError!void {
        manager.screen_rect = .{ .x = 0, .y = 0, .w = 640, .h = 480 };
        try manager.device_context.init(render_system, decl_manager, allocator);
    }

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
