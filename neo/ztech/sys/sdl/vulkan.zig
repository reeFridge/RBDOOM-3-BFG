const std = @import("std");
const sdl = @cImport(@cInclude("SDL.h"));
const sdl_vulkan = @cImport(@cInclude("SDL_vulkan.h"));
const vulkan = @cImport(@cInclude("vulkan/vulkan.h"));
const GLImplParams = @import("../../renderer/render_system.zig").GLImplParams;
const device_manager = @import("../device_manager.zig");

var window: ?*sdl.SDL_Window = null;

pub fn beforeInit() void {
    if (sdl.SDL_WasInit(sdl.SDL_INIT_VIDEO) != 0) return;

    const success = sdl.SDL_Init(sdl.SDL_INIT_VIDEO) == 0;
    if (!success) {
        std.debug.print("[SDL] Error while init: {s}\n", .{sdl.SDL_GetError()});
        @panic("[FATAL] SDL failed to init video");
    }
}

pub const InitError = error{
    NoDisplay,
    NoWindow,
};
pub fn init(params: GLImplParams) InitError!void {
    std.debug.print("[GL] Initializing Vulkan subsystem\n", .{});
    beforeInit();

    var create_params = params;
    if (params.fullscreen_mode == 0) {
        create_params.x = sdl.SDL_WINDOWPOS_CENTERED;
        create_params.y = sdl.SDL_WINDOWPOS_CENTERED;
    } else if (params.fullscreen_mode > 0) {
        if (params.fullscreen_mode > sdl.SDL_GetNumVideoDisplays()) {
            return error.NoDisplay;
        } else {
            const display_num: u32 = @intCast(params.fullscreen_mode - 1);
            create_params.x = sdl.SDL_WINDOWPOS_CENTERED_DISPLAY(display_num);
            create_params.y = sdl.SDL_WINDOWPOS_CENTERED_DISPLAY(display_num);
        }
    } else if (getDisplayIndex(params) == null) {
        create_params.x = sdl.SDL_WINDOWPOS_CENTERED;
        create_params.y = sdl.SDL_WINDOWPOS_CENTERED;
        std.debug.print(
            "[GL][WARN] Window position out of bounds, falling back to primary display\n",
            .{},
        );
    }

    window = createWindow(create_params, "[zTech]") orelse return error.NoWindow;
    //const manager = device_manager.instance();
    //try manager.createDeviceAndSwapChain(create_params);
}

pub fn setScreenParams(_: GLImplParams) error{}!void {}

fn createWindow(params: GLImplParams, window_title: [:0]const u8) ?*sdl.SDL_Window {
    var flags = sdl.SDL_WINDOW_VULKAN | sdl.SDL_WINDOW_RESIZABLE;
    if (params.fullscreen_mode == -1) {
        flags |= sdl.SDL_WINDOW_BORDERLESS;
    }

    return sdl.SDL_CreateWindow(
        window_title.ptr,
        @intCast(params.x),
        @intCast(params.y),
        @intCast(params.width),
        @intCast(params.height),
        @intCast(flags),
    );
}

fn getDisplayIndex(params: GLImplParams) ?usize {
    if (params.fullscreen_mode > 0) {
        if (params.fullscreen_mode <= sdl.SDL_GetNumVideoDisplays()) {
            return @intCast(params.fullscreen_mode - 1);
        }
    }

    const window_pos_x = params.x + params.width / 2;
    const window_pos_y = params.y + params.height / 2;

    const num_displays: usize = @intCast(sdl.SDL_GetNumVideoDisplays());
    for (0..num_displays) |i| {
        var rect: sdl.SDL_Rect = undefined;
        _ = sdl.SDL_GetDisplayBounds(@intCast(i), &rect);
        const inside_bounds = window_pos_x >= rect.x and
            window_pos_x < (rect.x + rect.w) and
            window_pos_y >= rect.y and
            window_pos_y < (rect.y + rect.h);
        const centered = params.x == sdl.SDL_WINDOWPOS_CENTERED_DISPLAY(i) and
            params.y == sdl.SDL_WINDOWPOS_CENTERED_DISPLAY(i);

        if (inside_bounds or centered) return i;
    }

    return null;
}
