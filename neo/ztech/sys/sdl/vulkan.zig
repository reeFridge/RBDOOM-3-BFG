const std = @import("std");
const vulkan = @import("vulkan");
const c = @import("../c_import.zig").c;
const RenderSystem = @import("../../renderer/render_system.zig");
const GLImplParams = RenderSystem.GLImplParams;
const device_manager = @import("../device_manager.zig");

var window: ?*c.SDL_Window = null;

pub const vkGetInstanceProcAddr = @extern(vulkan.PfnGetInstanceProcAddr, .{
    .name = "vkGetInstanceProcAddr",
    .library_name = "vulkan",
});

pub fn beforeInit() void {
    if (c.SDL_WasInit(c.SDL_INIT_VIDEO) != 0) return;

    const success = c.SDL_Init(c.SDL_INIT_VIDEO) == 0;
    if (!success) {
        std.debug.print("[SDL] Error while init: {s}\n", .{c.SDL_GetError()});
        @panic("[FATAL] SDL failed to init video");
    }
}

pub fn setGamma(
    red: *[256]c_ushort,
    green: *[256]c_ushort,
    blue: *[256]c_ushort,
) void {
    const window_ = window orelse @panic("called without window");

    const result = c.SDL_SetWindowGammaRamp(window_, red, green, blue);
    if (result < 0) {
        std.debug.print("[SDL] Couldn't set gamma ramp: {s}\n", .{c.SDL_GetError()});
    }
}

pub const InitError = error{
    NoDisplay,
    NoWindow,
} || device_manager.DeviceManagerVulkan.CreateDeviceAndSwapchainError;
pub fn init(params: GLImplParams) InitError!void {
    std.debug.print("[GL] Initializing Vulkan subsystem\n", .{});
    beforeInit();

    var create_params = params;
    if (params.fullscreen_mode == 0) {
        create_params.x = c.SDL_WINDOWPOS_CENTERED;
        create_params.y = c.SDL_WINDOWPOS_CENTERED;
    } else if (params.fullscreen_mode > 0) {
        if (params.fullscreen_mode > c.SDL_GetNumVideoDisplays()) {
            return error.NoDisplay;
        } else {
            const display_num: u32 = @intCast(params.fullscreen_mode - 1);
            create_params.x = c.SDL_WINDOWPOS_CENTERED_DISPLAY(display_num);
            create_params.y = c.SDL_WINDOWPOS_CENTERED_DISPLAY(display_num);
        }
    } else if (getDisplayIndex(params) == null) {
        create_params.x = c.SDL_WINDOWPOS_CENTERED;
        create_params.y = c.SDL_WINDOWPOS_CENTERED;
        std.debug.print(
            "[GL][WARN] Window position out of bounds, falling back to primary display\n",
            .{},
        );
    }

    window = createWindow(create_params, "[ztech]") orelse return error.NoWindow;
    const manager = device_manager.instance();

    var instance_extensions_count: u32 = 0;
    const max_size = 256;
    _ = c.SDL_Vulkan_GetInstanceExtensions(window, &instance_extensions_count, null);
    var instance_extensions = std.BoundedArray([*:0]const u8, max_size)
        .init(instance_extensions_count) catch return error.OutOfMemory;
    _ = c.SDL_Vulkan_GetInstanceExtensions(
        window,
        &instance_extensions_count,
        @ptrCast(instance_extensions.slice().ptr),
    );

    try manager.createDeviceAndSwapChain(create_params, instance_extensions.constSlice());

    if (params.fullscreen_mode > 0) {
        if (params.display_hz > 0 and params.display_hz != getDisplayFrequency(params)) {
            var mode = c.SDL_DisplayMode{};
            _ = c.SDL_GetWindowDisplayMode(window, &mode);

            mode.refresh_rate = @intCast(params.display_hz);
            if (c.SDL_SetWindowDisplayMode(window, &mode) < 0) {
                std.debug.print("Couldn't set display refresh rate to {} Hz, reason: {s}\n", .{
                    params.display_hz,
                    c.SDL_GetError(),
                });
            }
        }

        if (c.SDL_SetWindowFullscreen(window, c.SDL_WINDOW_FULLSCREEN) < 0) {
            std.debug.print("Couldn't switch to fullscreen mode, reason: {s}\n", .{c.SDL_GetError()});
        }
    } else if (params.fullscreen_mode == -2) {
        if (c.SDL_SetWindowFullscreen(window, c.SDL_WINDOW_FULLSCREEN_DESKTOP) < 0) {
            std.debug.print("Couldn't switch to borderless fullscreen mode, reason: {s}\n", .{c.SDL_GetError()});
        }
    } else if (params.fullscreen_mode == -1) {
        c.SDL_SetWindowPosition(window, @intCast(create_params.x), @intCast(create_params.y));
    }

    const gl_config = RenderSystem.gl_config;

    if (params.fullscreen_mode != 0) {
        c.SDL_GetWindowSize(
            window,
            @ptrCast(&gl_config.nativeScreenWidth),
            @ptrCast(&gl_config.nativeScreenHeight),
        );
    } else {
        manager.getWindowDimensions(
            &gl_config.nativeScreenWidth,
            &gl_config.nativeScreenHeight,
        );
    }

    const is_fullscreen_bit_set = (c.SDL_GetWindowFlags(window) & c.SDL_WINDOW_FULLSCREEN) != 0;
    gl_config.isFullscreen = if (is_fullscreen_bit_set or params.fullscreen_mode == -1)
        params.fullscreen_mode
    else
        0;

    gl_config.displayFrequency = getDisplayFrequency(params);
    gl_config.isStereoPixelFormat = params.stereo;
    gl_config.multisamples = params.multi_samples;
    // FIXME: some monitor modes may be distorted
    gl_config.pixelAspect = 1.0;

    _ = c.SDL_ShowCursor(c.SDL_DISABLE);
}

fn getDisplayFrequency(params: GLImplParams) u32 {
    const display_index = getDisplayIndex(params) orelse 0;

    var mode = c.SDL_DisplayMode{};
    if (c.SDL_GetCurrentDisplayMode(@intCast(display_index), &mode) != 0) {
        std.debug.print("Couldn't get display refresh rate, reason: {s}\n", .{c.SDL_GetError()});
        return params.display_hz;
    }

    return @intCast(mode.refresh_rate);
}

pub fn setScreenParams(_: GLImplParams) error{}!void {}

pub const CreateWindowSurfaceError = error{
    SurfaceLost,
};
pub fn createWindowSurface(
    instance: vulkan.Instance,
) CreateWindowSurfaceError!vulkan.SurfaceKHR {
    var handle = vulkan.SurfaceKHR.null_handle;

    if (c.SDL_Vulkan_CreateSurface(
        window,
        @ptrFromInt(@intFromEnum(instance)),
        @ptrCast(&handle),
    ) == c.SDL_FALSE) {
        return error.SurfaceLost;
    }

    return handle;
}

fn createWindow(params: GLImplParams, window_title: [:0]const u8) ?*c.SDL_Window {
    var flags = c.SDL_WINDOW_VULKAN | c.SDL_WINDOW_RESIZABLE;
    if (params.fullscreen_mode == -1) {
        flags |= c.SDL_WINDOW_BORDERLESS;
    }

    return c.SDL_CreateWindow(
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
        if (params.fullscreen_mode <= c.SDL_GetNumVideoDisplays()) {
            return @intCast(params.fullscreen_mode - 1);
        }
    }

    const window_pos_x = params.x + params.width / 2;
    const window_pos_y = params.y + params.height / 2;

    const num_displays: usize = @intCast(c.SDL_GetNumVideoDisplays());
    for (0..num_displays) |i| {
        var rect: c.SDL_Rect = undefined;
        _ = c.SDL_GetDisplayBounds(@intCast(i), &rect);
        const inside_bounds = window_pos_x >= rect.x and
            window_pos_x < (rect.x + rect.w) and
            window_pos_y >= rect.y and
            window_pos_y < (rect.y + rect.h);
        const centered = params.x == c.SDL_WINDOWPOS_CENTERED_DISPLAY(i) and
            params.y == c.SDL_WINDOWPOS_CENTERED_DISPLAY(i);

        if (inside_bounds or centered) return i;
    }

    return null;
}
