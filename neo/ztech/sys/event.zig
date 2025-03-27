const std = @import("std");
const c = @import("c_import.zig").c;
const KeyNum = @import("../framework/key_input.zig").KeyNum;

pub const Signal = enum(u32) {
    quit,
    vid_restart,
};

pub const Event = extern struct {
    pub const Type = enum(c_int) {
        none, // evTime is still valid
        key, // evValue is a key code, evValue2 is the down flag
        char, // evValue is an Unicode UTF-32 char (or non-surrogate UTF-16)
        mouse, // evValue and evValue2 are relative signed x / y moves
        mouse_absolute, // evValue and evValue2 are absolute coordinates in the window's client area.
        mouse_leave, // evValue and evValue2 are meaninless, this indicates the mouse has left the client area.
        joystick, // evValue is an axis number and evValue2 is the current state (-127 to 127)
        console, // evPtr is a char*, from typing something at a non-game console
        signal,
    };

    type: Type,
    first_value: u32,
    second_value: u32 = 0,
    data_len: u32 = 0, // bytes of data pointed to by evPtr, for journaling
    data_ptr: ?*anyopaque = null, // this must be manually freed if not NULL
    input_device: c_int = -1,
};

pub fn generateEvents() void {
    c.SDL_PumpEvents();
}

fn sdlScanCodeToKeyNum(scancode: c.SDL_Scancode) KeyNum {
    const idx: usize = @intCast(scancode);
    std.debug.assert(idx < c.SDL_NUM_SCANCODES);

    return @enumFromInt(c.scanCodeToKeyNum[idx]);
}

var opt_iconv_state: c.SDL_iconv_t = null;
fn convertUtf8toUtf32(utf8str: [*:0]const u8, utf32buf: [*:0]u32) void {
    const iconv_state = opt_iconv_state orelse iconv_state: {
        const from = "UTF-8";
        const to = "UTF-32LE";
        break :iconv_state c.SDL_iconv_open(to, from) orelse {
            std.debug.print("[SDL][WARN] fail to init SDL_iconv\n", .{});
            return;
        };
    };

    const len = std.mem.len(utf8str);
    var in_bytes_left = len;
    var out_bytes_left: usize = 4 * c.SDL_TEXTINPUTEVENT_TEXT_SIZE;
    var out_buffer: [*:0]u8 = @ptrCast(utf32buf);
    const n = c.SDL_iconv(
        iconv_state,
        @constCast(@ptrCast(&utf8str)),
        &in_bytes_left,
        @ptrCast(&out_buffer),
        &out_bytes_left,
    );

    if (n == -1) {
        std.debug.print("[SDL][WARN] Converting utf-8 to utf-32 failed\n", .{});
    }

    _ = c.SDL_iconv(iconv_state, null, &in_bytes_left, null, &out_bytes_left);
}

var uni_str: [c.SDL_TEXTINPUTEVENT_TEXT_SIZE]u32 = [_]u32{0} ** c.SDL_TEXTINPUTEVENT_TEXT_SIZE;
var uni_str_pos: usize = 0;

pub fn getEvent() ?Event {
    if (uni_str[0] != 0) {
        const result_event = Event{
            .type = .char,
            .first_value = uni_str[uni_str_pos],
        };

        uni_str_pos += 1;

        if (uni_str[uni_str_pos] == 0 or uni_str_pos == c.SDL_TEXTINPUTEVENT_TEXT_SIZE) {
            uni_str = std.mem.zeroes([c.SDL_TEXTINPUTEVENT_TEXT_SIZE]u32);
            uni_str_pos = 0;
        }

        return result_event;
    }

    var sdl_event: c.SDL_Event = undefined;

    while (c.SDL_PollEvent(&sdl_event) != 0) {
        switch (sdl_event.type) {
            c.SDL_TEXTINPUT => {
                if (sdl_event.text.text[0] != 0) {
                    convertUtf8toUtf32(@ptrCast(&sdl_event.text.text), @ptrCast(&uni_str));

                    const result_event = Event{
                        .type = .char,
                        .first_value = uni_str[0],
                    };

                    uni_str_pos = 1;

                    if (uni_str[1] == 0) {
                        uni_str[0] = 0;
                        uni_str_pos = 0;
                    }

                    return result_event;
                }
            },
            c.SDL_KEYUP, c.SDL_KEYDOWN => {
                const key: KeyNum = if (sdl_event.key.keysym.scancode == c.SDL_SCANCODE_GRAVE)
                    .K_GRAVE
                else
                    sdlScanCodeToKeyNum(sdl_event.key.keysym.scancode);

                if (key == .K_NONE) continue;

                const result_event = Event{
                    .type = .key,
                    .first_value = @intFromEnum(key),
                    .second_value = @intFromBool(sdl_event.key.state == c.SDL_PRESSED),
                };

                return result_event;
            },
            c.SDL_QUIT => {
                return .{
                    .type = .signal,
                    .first_value = @intFromEnum(Signal.quit),
                };
            },
            else => |event_type| {
                std.debug.print("unknown event: {}\n", .{event_type});
            },
        }
    }

    return null;
}
