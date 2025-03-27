const std = @import("std");
const CVec3 = @import("../math/vector.zig").CVec3;
const key_input = @import("key_input.zig");

pub const CommandString = extern struct {
    string: [*:0]const u8,
    button: Button,
};

pub const Command = extern struct {
    // synced
    angles: [3]i16 = .{ 0, 0, 0 },
    forward_move: i8 = 0,
    right_move: i8 = 0,
    buttons: u8 = 0,
    client_time_ms: u32 = 0,
    server_time_ms: u32 = 0,
    fire_count: u16 = 0,

    // not synced
    impulse: u8 = 0,
    impulse_sequence: u8 = 0,
    mouse_dx: i16 = 0,
    mouse_dy: i16 = 0,

    // client auth
    pos: CVec3 = .{},
    speed_squared: f32 = 0,
};

pub const Button = enum(c_int) {
    none,
    moveup,
    movedown,
    lookleft,
    lookright,
    moveforward,
    moveback,
    lookup,
    lookdown,
    moveleft,
    moveright,
    attack,
    speed,
    zoom,
    showscores,
    use,
    impulse0,
    impulse1,
    impulse2,
    impulse3,
    impulse4,
    impulse5,
    impulse6,
    impulse7,
    impulse8,
    impulse9,
    impulse10,
    impulse11,
    impulse12,
    impulse13,
    impulse14,
    impulse15,
    impulse16,
    impulse17,
    impulse18,
    impulse19,
    impulse20,
    impulse21,
    impulse22,
    impulse23,
    impulse24,
    impulse25,
    impulse26,
    impulse27,
    impulse28,
    impulse29,
    impulse30,
    impulse31,
};

pub const ButtonState = extern struct {
    on: i32 = 0,
    held: bool = false,
};

pub const Generator = extern struct {
    vptr: *anyopaque = undefined,
    view_angles: CVec3 = .{},
    impulse_sequence: i32 = 0,
    impuse: i32 = 0,
    toggled_crouch: ButtonState = .{},
    toggled_run: ButtonState = .{},
    toggled_zoom: ButtonState = .{},

    button_state: [@typeInfo(Button).@"enum".fields.len]i32 = std.mem.zeroes([@typeInfo(Button).@"enum".fields.len]i32),
    key_state: [@intCast(@intFromEnum(key_input.KeyNum.last_key))]bool = std.mem.zeroes([@intCast(@intFromEnum(key_input.KeyNum.last_key))]bool),
    inhibit_commands: i32 = @intFromBool(false), // bool
    initialized: bool = false,
    command: Command = .{},
    continuous_mouse_x: i32 = 0,
    continuous_mouse_y: i32 = 0,
    mouse_button: i32 = 0,
    mouse_down: bool = false,
    mouse_dx: i32 = 0,
    mouse_dy: i32 = 0,
    joystick_axis: [@typeInfo(key_input.JoystickAxis).@"enum".fields.len]f32 = std.mem.zeroes([@typeInfo(key_input.JoystickAxis).@"enum".fields.len]f32),
    poll_time: i32 = 0,
    last_poll_time: i32 = 0,
    last_look_value_pitch: f32 = 0,
    last_look_value_yaw: f32 = 0,

    pub fn init(generator: *Generator) void {
        generator.initialized = true;
    }

    pub fn shutdown(generator: *Generator) void {
        generator.initialized = false;
    }

    pub fn clear(generator: *Generator) void {
        generator.button_state = std.mem.zeroes(std.meta.FieldType(Generator, .button_state));
        generator.key_state = std.mem.zeroes(std.meta.FieldType(Generator, .key_state));
        generator.joystick_axis = std.mem.zeroes(std.meta.FieldType(Generator, .joystick_axis));
        generator.inhibit_commands = @intFromBool(false);
        generator.mouse_dx = 0;
        generator.mouse_dy = 0;
        generator.mouse_button = 0;
        generator.mouse_down = false;
    }
};

pub const generator_instance = @extern(*Generator, .{ .name = "localUsercmdGen" });
