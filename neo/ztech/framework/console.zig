const std = @import("std");
const getMilliseconds = @import("../main.zig").Sys_Milliseconds;
const idlib = @import("../idlib.zig");
const Vec4 = @import("../math/vector.zig").Vec4;
const CVec4 = @import("../math/vector.zig").CVec4;
const EditField = @import("edit_field.zig").EditField;
const RenderSystem = @import("../renderer/render_system.zig");
const Allocator = std.mem.Allocator;

const CON_TEXTSIZE = 0x30000;
const NUM_CON_TIMES = 4;
const COMMAND_HISTORY = 64;
const CONSOLE_FIRSTREPEAT = 200;

const Justify = enum(c_int) {
    left,
    right,
    center_left,
    center_right,
};

const OverlayText = extern struct {
    text: idlib.Str,
    justify: Justify,
    time: c_int,
};

const DebugGraph = opaque {};

pub const Console = extern struct {
    vptr: *anyopaque,
    local_safe_left: u32,
    local_safe_right: u32,
    local_safe_top: u32,
    local_safe_bottom: u32,
    local_safe_width: u32,
    local_safe_height: u32,
    line_width: u32,
    total_lines: u32,
    key_catching: bool,
    text: [CON_TEXTSIZE]c_short,
    current: u32, // line where next message will be printed
    x: i32, // offset in current line for next print
    display: c_int, // bottom of console displays this line
    last_key_event: c_int, // time of last key event for scroll delay
    next_key_event: c_int, // keyboard repeat rate
    display_frac: f32, // approaches finalFrac at con_speed
    final_frac: f32, // 0.0 to 1.0 lines of console to display
    frac_time: c_int, // time of last display_frac update
    vislines: u32, // in scanlines
    times: [NUM_CON_TIMES]c_int, // cls.realtime time the line was generated
    color: CVec4,
    history_edit_lines: [COMMAND_HISTORY]EditField,

    next_history_line: c_int, // the last line in the history buffer, not masked
    history_line: u32, // the line being displayed from history buffer
    console_field: EditField,

    overlay_text: idlib.List(OverlayText),
    debug_graphs: idlib.List(*DebugGraph),

    last_virtual_screen_width: u32,
    last_virtual_screen_height: u32,

    pub fn init(console: *Console) void {
        console.key_catching = false;

        console.local_safe_left = 0;
        console.local_safe_right = RenderSystem.SCREEN_WIDTH - console.local_safe_left;
        console.local_safe_top = 24;
        console.local_safe_bottom = RenderSystem.SCREEN_HEIGHT - console.local_safe_top;
        console.local_safe_width = console.local_safe_right - console.local_safe_left;
        console.local_safe_height = console.local_safe_bottom - console.local_safe_top;

        console.line_width = @divTrunc(console.local_safe_width, RenderSystem.SMALLCHAR_WIDTH) - 2;
        console.total_lines = @divTrunc(CON_TEXTSIZE, console.line_width);

        console.last_key_event = -1;
        console.next_key_event = CONSOLE_FIRSTREPEAT;

        console.console_field.clear();
        console.console_field.width_in_chars = console.line_width;

        for (&console.history_edit_lines) |*line| {
            line.clear();
            line.width_in_chars = console.line_width;
        }
    }

    fn setDisplayFraction(console: *Console, frac: f32) void {
        console.final_frac = frac;
        console.frac_time = getMilliseconds();
    }

    fn clearNotifyLines(console: *Console) void {
        console.times = std.mem.zeroes([NUM_CON_TIMES]c_int);
    }

    fn updateDisplayFraction(console: *Console) void {
        const speed: f32 = 3;

        if (speed <= 0.1) {
            console.frac_time = getMilliseconds();
            console.display_frac = console.final_frac;
            return;
        }

        const delta_time: f32 = @floatFromInt(getMilliseconds() - console.frac_time);
        const translation = speed * delta_time * 0.001;
        if (console.final_frac < console.display_frac) {
            console.display_frac -= translation;
            if (console.final_frac > console.display_frac) {
                console.display_frac = console.final_frac;
            }

            console.frac_time = getMilliseconds();
        } else if (console.final_frac > console.display_frac) {
            console.display_frac += translation;
            if (console.final_frac < console.display_frac) {
                console.display_frac = console.final_frac;
            }

            console.frac_time = getMilliseconds();
        }
    }

    pub fn draw(console: *Console, allocator: Allocator) Allocator.Error!void {
        console.updateDisplayFraction();
        const render = &RenderSystem.instance;

        // draw console background and bottom-line
        {
            const line_height: f32 = 2;
            const line_color = Vec4(f32){ .v = .{ 0.97, 0.64, 0.11, 1 } };
            const bg_color = Vec4(f32){ .v = .{ 0, 0, 0, 0.75 } };
            const w = @as(f32, @floatFromInt(render.getVirtualWidth()));
            const h = @as(f32, @floatFromInt(render.getVirtualHeight()));
            var y = console.display_frac * h - line_height;
            if (y < 1.0) {
                y = 0;
            } else {
                try render.drawFilled(
                    bg_color,
                    .{ .w = w, .h = y },
                    allocator,
                );
            }

            try render.drawFilled(
                line_color,
                .{ .y = y, .w = w, .h = line_height },
                allocator,
            );
        }

        {
            const str: []const u8 = "ztech [v0.0.1]";
            for (str, 0..) |char, i| {
                try render.drawSmallChar(
                    @intCast(i * RenderSystem.SMALLCHAR_WIDTH + 10),
                    10,
                    char,
                    allocator,
                );
            }
        }
    }

    pub fn open(console: *Console) void {
        if (console.key_catching) return;

        console.console_field.clear();
        console.key_catching = true;
        console.setDisplayFraction(0.5);
    }

    pub fn close(console: *Console) void {
        console.key_catching = false;
        console.setDisplayFraction(0);
        console.display_frac = 0;
        console.clearNotifyLines();
    }
};

pub const instance = @extern(*Console, .{ .name = "localConsole" });
