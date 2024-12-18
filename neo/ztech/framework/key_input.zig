const std = @import("std");
const global = @import("../global.zig");
const idlib = @import("../idlib.zig");
const cmd = @import("cmd_system.zig");
const cvar = @import("cvar_system.zig");
const Allocator = std.mem.Allocator;

fn cmd_unbindAll(_: *const cmd.CmdArgs) callconv(.C) void {
    const size: usize = @intFromEnum(KeyNum.K_LAST_KEY);

    const allocator = global.gpa.allocator();
    for (0..size) |i| {
        setBinding(@intCast(i), "", allocator) catch unreachable;
    }
}

fn cmd_bind(args: *const cmd.CmdArgs) callconv(.C) void {
    const keys = opt_keys orelse return;

    if (args.argc < 2) {
        std.debug.print("bind <key> [command] : attach a command to a key\n", .{});
        return;
    }

    const key_str = std.mem.span(args.argv[1]);
    const key_num = stringToKeyNum(key_str);
    if (key_num == .K_NONE) {
        std.debug.print("[KEY] {s} is not a valid key\n", .{key_str});
        return;
    }

    if (args.argc == 2) {
        const binding = keys[@intCast(@intFromEnum(key_num))].binding.constSlice();
        std.debug.print(
            "[KEY] {s} = {s}\n",
            .{ key_str, if (binding.len > 0) binding else "<not bound>" },
        );
        return;
    }

    var cmd_buffer: [cmd.CmdArgs.MAX_STRING_CHARS]u8 = undefined;
    var len: usize = 0;

    for (2..@intCast(args.argc)) |i| {
        const token_str = std.mem.span(args.argv[i]);
        @memcpy(cmd_buffer[len..][0..token_str.len], token_str);
        len += token_str.len;
        if (i != @as(usize, @intCast(args.argc - 1))) {
            cmd_buffer[len] = ' ';
            len += 1;
        }
    }

    const allocator = global.gpa.allocator();
    setBinding(
        @intFromEnum(key_num),
        cmd_buffer[0..len],
        allocator,
    ) catch unreachable;
}

const KeyName = extern struct {
    keynum: KeyNum = .K_NONE,
    name: ?[*:0]const u8 = null,
    strId: ?[*:0]const u8 = null,
};

fn NAMEKEY(code: [:0]const u8, strId: [:0]const u8) KeyName {
    return .{
        .keynum = std.enums.nameCast(KeyNum, "K_" ++ code),
        .name = code.ptr,
        .strId = strId.ptr,
    };
}

fn NAMEKEY2(code: [:0]const u8) KeyName {
    return .{
        .keynum = std.enums.nameCast(KeyNum, "K_" ++ code),
        .name = code.ptr,
        .strId = code.ptr,
    };
}

fn ALIASKEY(alias: [:0]const u8, code: [:0]const u8) KeyName {
    return .{
        .keynum = std.enums.nameCast(KeyNum, "K_" ++ code),
        .name = alias.ptr,
        .strId = "",
    };
}

const key_names = [_]KeyName{
    NAMEKEY("ESCAPE", "#str_07020"),
    NAMEKEY2("1"),
    NAMEKEY2("2"),
    NAMEKEY2("3"),
    NAMEKEY2("4"),
    NAMEKEY2("5"),
    NAMEKEY2("6"),
    NAMEKEY2("7"),
    NAMEKEY2("8"),
    NAMEKEY2("9"),
    NAMEKEY2("0"),
    NAMEKEY("MINUS", "-"),
    NAMEKEY("EQUALS", "="),
    NAMEKEY("BACKSPACE", "#str_07022"),
    NAMEKEY("TAB", "#str_07018"),
    NAMEKEY2("Q"),
    NAMEKEY2("W"),
    NAMEKEY2("E"),
    NAMEKEY2("R"),
    NAMEKEY2("T"),
    NAMEKEY2("Y"),
    NAMEKEY2("U"),
    NAMEKEY2("I"),
    NAMEKEY2("O"),
    NAMEKEY2("P"),
    NAMEKEY("LBRACKET", "["),
    NAMEKEY("RBRACKET", "]"),
    NAMEKEY("ENTER", "#str_07019"),
    NAMEKEY("LCTRL", "#str_07028"),
    NAMEKEY2("A"),
    NAMEKEY2("S"),
    NAMEKEY2("D"),
    NAMEKEY2("F"),
    NAMEKEY2("G"),
    NAMEKEY2("H"),
    NAMEKEY2("J"),
    NAMEKEY2("K"),
    NAMEKEY2("L"),
    NAMEKEY("SEMICOLON", "#str_07129"),
    NAMEKEY("APOSTROPHE", "#str_07130"),
    NAMEKEY("GRAVE", "`"),
    NAMEKEY("LSHIFT", "#str_07029"),
    NAMEKEY("BACKSLASH", "\\"),
    NAMEKEY2("Z"),
    NAMEKEY2("X"),
    NAMEKEY2("C"),
    NAMEKEY2("V"),
    NAMEKEY2("B"),
    NAMEKEY2("N"),
    NAMEKEY2("M"),
    NAMEKEY("COMMA", ","),
    NAMEKEY("PERIOD", "."),
    NAMEKEY("SLASH", "/"),
    NAMEKEY("RSHIFT", "#str_bind_RSHIFT"),
    NAMEKEY("KP_STAR", "#str_07126"),
    NAMEKEY("LALT", "#str_07027"),
    NAMEKEY("SPACE", "#str_07021"),
    NAMEKEY("CAPSLOCK", "#str_07034"),
    NAMEKEY("F1", "#str_07036"),
    NAMEKEY("F2", "#str_07037"),
    NAMEKEY("F3", "#str_07038"),
    NAMEKEY("F4", "#str_07039"),
    NAMEKEY("F5", "#str_07040"),
    NAMEKEY("F6", "#str_07041"),
    NAMEKEY("F7", "#str_07042"),
    NAMEKEY("F8", "#str_07043"),
    NAMEKEY("F9", "#str_07044"),
    NAMEKEY("F10", "#str_07045"),
    NAMEKEY("NUMLOCK", "#str_07125"),
    NAMEKEY("SCROLL", "#str_07035"),
    NAMEKEY("KP_7", "#str_07110"),
    NAMEKEY("KP_8", "#str_07111"),
    NAMEKEY("KP_9", "#str_07112"),
    NAMEKEY("KP_MINUS", "#str_07123"),
    NAMEKEY("KP_4", "#str_07113"),
    NAMEKEY("KP_5", "#str_07114"),
    NAMEKEY("KP_6", "#str_07115"),
    NAMEKEY("KP_PLUS", "#str_07124"),
    NAMEKEY("KP_1", "#str_07116"),
    NAMEKEY("KP_2", "#str_07117"),
    NAMEKEY("KP_3", "#str_07118"),
    NAMEKEY("KP_0", "#str_07120"),
    NAMEKEY("KP_DOT", "#str_07121"),
    NAMEKEY("F11", "#str_07046"),
    NAMEKEY("F12", "#str_07047"),
    NAMEKEY2("F13"),
    NAMEKEY2("F14"),
    NAMEKEY2("F15"),
    NAMEKEY2("KANA"),
    NAMEKEY2("CONVERT"),
    NAMEKEY2("NOCONVERT"),
    NAMEKEY2("YEN"),
    NAMEKEY("KP_EQUALS", "#str_07127"),
    //NAMEKEY2("CIRCUMFLEX"),
    NAMEKEY("AT", "@"),
    NAMEKEY("COLON", ":"),
    NAMEKEY("UNDERLINE", "_"),
    NAMEKEY2("KANJI"),
    NAMEKEY2("STOP"),
    NAMEKEY2("AX"),
    NAMEKEY2("UNLABELED"),
    NAMEKEY("KP_ENTER", "#str_07119"),
    NAMEKEY("RCTRL", "#str_bind_RCTRL"),
    NAMEKEY("KP_COMMA", ","),
    NAMEKEY("KP_SLASH", "#str_07122"),
    NAMEKEY("PRINTSCREEN", "#str_07179"),
    NAMEKEY("RALT", "#str_bind_RALT"),
    NAMEKEY("PAUSE", "#str_07128"),
    NAMEKEY("HOME", "#str_07052"),
    NAMEKEY("UPARROW", "#str_07023"),
    NAMEKEY("PGUP", "#str_07051"),
    NAMEKEY("LEFTARROW", "#str_07025"),
    NAMEKEY("RIGHTARROW", "#str_07026"),
    NAMEKEY("END", "#str_07053"),
    NAMEKEY("DOWNARROW", "#str_07024"),
    NAMEKEY("PGDN", "#str_07050"),
    NAMEKEY("INS", "#str_07048"),
    NAMEKEY("DEL", "#str_07049"),
    NAMEKEY("LWIN", "#str_07030"),
    NAMEKEY("RWIN", "#str_07031"),
    NAMEKEY("APPS", "#str_07032"),
    NAMEKEY2("POWER"),
    NAMEKEY2("SLEEP"),
    NAMEKEY2("OEM_102"),
    NAMEKEY2("ABNT_C1"),
    NAMEKEY2("NEXTTRACK"),
    NAMEKEY2("MUTE"),
    NAMEKEY2("CALCULATOR"),
    NAMEKEY2("PLAYPAUSE"),
    NAMEKEY2("MEDIASTOP"),
    NAMEKEY2("VOLUMEDOWN"),
    NAMEKEY2("VOLUMEUP"),
    NAMEKEY2("WEBHOME"),
    NAMEKEY2("WAKE"),
    NAMEKEY2("WEBSEARCH"),
    NAMEKEY2("WEBFAVORITES"),
    NAMEKEY2("WEBREFRESH"),
    NAMEKEY2("WEBSTOP"),
    NAMEKEY2("WEBFORWARD"),
    NAMEKEY2("WEBBACK"),
    NAMEKEY2("MYCOMPUTER"),
    NAMEKEY2("MAIL"),
    NAMEKEY2("MEDIASELECT"),
    NAMEKEY("MOUSE1", "#str_07054"),
    NAMEKEY("MOUSE2", "#str_07055"),
    NAMEKEY("MOUSE3", "#str_07056"),
    NAMEKEY("MOUSE4", "#str_07057"),
    NAMEKEY("MOUSE5", "#str_07058"),
    NAMEKEY("MOUSE6", "#str_07059"),
    NAMEKEY("MOUSE7", "#str_07060"),
    NAMEKEY("MOUSE8", "#str_07061"),
    NAMEKEY2("MOUSE9"),
    NAMEKEY2("MOUSE10"),
    NAMEKEY2("MOUSE11"),
    NAMEKEY2("MOUSE12"),
    NAMEKEY2("MOUSE13"),
    NAMEKEY2("MOUSE14"),
    NAMEKEY2("MOUSE15"),
    NAMEKEY2("MOUSE16"),
    NAMEKEY("MWHEELDOWN", "#str_07132"),
    NAMEKEY("MWHEELUP", "#str_07131"),
    NAMEKEY("JOY1", "#str_07062"),
    NAMEKEY("JOY2", "#str_07063"),
    NAMEKEY("JOY3", "#str_07064"),
    NAMEKEY("JOY4", "#str_07065"),
    NAMEKEY("JOY5", "#str_07066"),
    NAMEKEY("JOY6", "#str_07067"),
    NAMEKEY("JOY7", "#str_07068"),
    NAMEKEY("JOY8", "#str_07069"),
    NAMEKEY("JOY9", "#str_07070"),
    NAMEKEY("JOY10", "#str_07071"),
    NAMEKEY("JOY11", "#str_07072"),
    NAMEKEY("JOY12", "#str_07073"),
    NAMEKEY("JOY13", "#str_07074"),
    NAMEKEY("JOY14", "#str_07075"),
    NAMEKEY("JOY15", "#str_07076"),
    NAMEKEY("JOY16", "#str_07077"),

    NAMEKEY2("JOY_DPAD_UP"),
    NAMEKEY2("JOY_DPAD_DOWN"),
    NAMEKEY2("JOY_DPAD_LEFT"),
    NAMEKEY2("JOY_DPAD_RIGHT"),

    NAMEKEY2("JOY_STICK1_UP"),
    NAMEKEY2("JOY_STICK1_DOWN"),
    NAMEKEY2("JOY_STICK1_LEFT"),
    NAMEKEY2("JOY_STICK1_RIGHT"),

    NAMEKEY2("JOY_STICK2_UP"),
    NAMEKEY2("JOY_STICK2_DOWN"),
    NAMEKEY2("JOY_STICK2_LEFT"),
    NAMEKEY2("JOY_STICK2_RIGHT"),

    NAMEKEY2("JOY_TRIGGER1"),
    NAMEKEY2("JOY_TRIGGER2"),

    //------------------------
    // Aliases to make it easier to bind or to support old configs
    //------------------------
    ALIASKEY("ALT", "LALT"),
    ALIASKEY("RIGHTALT", "RALT"),
    ALIASKEY("CTRL", "LCTRL"),
    ALIASKEY("SHIFT", "LSHIFT"),
    ALIASKEY("MENU", "APPS"),
    ALIASKEY("COMMAND", "LALT"),

    ALIASKEY("KP_HOME", "KP_7"),
    ALIASKEY("KP_UPARROW", "KP_8"),
    ALIASKEY("KP_PGUP", "KP_9"),
    ALIASKEY("KP_LEFTARROW", "KP_4"),
    ALIASKEY("KP_RIGHTARROW", "KP_6"),
    ALIASKEY("KP_END", "KP_1"),
    ALIASKEY("KP_DOWNARROW", "KP_2"),
    ALIASKEY("KP_PGDN", "KP_3"),
    ALIASKEY("KP_INS", "KP_0"),
    ALIASKEY("KP_DEL", "KP_DOT"),
    ALIASKEY("KP_NUMLOCK", "NUMLOCK"),

    ALIASKEY("-", "MINUS"),
    ALIASKEY("=", "EQUALS"),
    ALIASKEY("[", "LBRACKET"),
    ALIASKEY("]", "RBRACKET"),
    ALIASKEY("\\", "BACKSLASH"),
    ALIASKEY("/", "SLASH"),
    ALIASKEY(",", "COMMA"),
    ALIASKEY(".", "PERIOD"),

    .{},
};

const Key = extern struct {
    down: bool = false,
    repeates: c_int = 0,
    binding: idlib.Str = .{},
    usercmdAction: c_int = 0,

    pub fn init(key: *Key) void {
        key.* = .{};
    }

    pub fn deinit(key: *Key, allocator: Allocator) void {
        key.binding.deinit(allocator);
    }
};

var opt_keys: ?[]Key = null;

pub fn init(allocator: Allocator) error{OutOfMemory}!void {
    shutdown(allocator);
    const keys = try allocator.alloc(Key, @intFromEnum(KeyNum.K_LAST_KEY));

    for (keys) |*key_ptr| {
        key_ptr.init();
    }

    opt_keys = keys;

    try cmd.instance.addCommand(
        "unbindall",
        cmd_unbindAll,
        cmd.CmdFlags.CMD_FL_SYSTEM,
        "unbinds any commands from all keys",
        null,
        allocator,
    );

    try cmd.instance.addCommand(
        "bind",
        cmd_bind,
        cmd.CmdFlags.CMD_FL_SYSTEM,
        "binds a command to a key",
        null,
        allocator,
    );

    // TODO: addCommand bindunbindtwo
    // TODO: addCommand unbind
    // TODO: addCommand listBinds
}

pub fn shutdown(allocator: Allocator) void {
    const keys = opt_keys orelse return;

    for (keys) |*key_ptr| {
        key_ptr.deinit(allocator);
    }

    allocator.free(keys);
    opt_keys = null;
}

pub fn stringToKeyNum(str: []const u8) KeyNum {
    if (str.len == 0) return .K_NONE;

    for (&key_names) |key_name| {
        const name_ptr = key_name.name orelse continue;
        const name = std.mem.span(name_ptr);
        if (std.ascii.eqlIgnoreCase(name, str)) {
            return key_name.keynum;
        }
    }

    return .K_NONE;
}

pub fn setBinding(
    keynum: c_int,
    binding: []const u8,
    allocator: Allocator,
) Allocator.Error!void {
    const keys = opt_keys orelse return;
    if (keynum == -1) return;

    const index: usize = @intCast(keynum);

    // TODO user_cmd_gen.instance.clear();

    try keys[index].binding.assignSlice(binding, allocator);

    // TODO keys[index].usercmdAction = user_cmd_gen.instance.commandStringUserCmdData(binding);
    cvar.instance.modifiedFlags |= cvar.CVarFlags.CVAR_ARCHIVE;
}

const KeyNum = enum(c_int) {
    K_NONE,
    K_ESCAPE,
    K_1,
    K_2,
    K_3,
    K_4,
    K_5,
    K_6,
    K_7,
    K_8,
    K_9,
    K_0,
    K_MINUS,
    K_EQUALS,
    K_BACKSPACE,
    K_TAB,
    K_Q,
    K_W,
    K_E,
    K_R,
    K_T,
    K_Y,
    K_U,
    K_I,
    K_O,
    K_P,
    K_LBRACKET,
    K_RBRACKET,
    K_ENTER,
    K_LCTRL,
    K_A,
    K_S,
    K_D,
    K_F,
    K_G,
    K_H,
    K_J,
    K_K,
    K_L,
    K_SEMICOLON,
    K_APOSTROPHE,
    K_GRAVE,
    K_LSHIFT,
    K_BACKSLASH,
    K_Z,
    K_X,
    K_C,
    K_V,
    K_B,
    K_N,
    K_M,
    K_COMMA,
    K_PERIOD,
    K_SLASH,
    K_RSHIFT,
    K_KP_STAR,
    K_LALT,
    K_SPACE,
    K_CAPSLOCK,
    K_F1,
    K_F2,
    K_F3,
    K_F4,
    K_F5,
    K_F6,
    K_F7,
    K_F8,
    K_F9,
    K_F10,
    K_NUMLOCK,
    K_SCROLL,
    K_KP_7,
    K_KP_8,
    K_KP_9,
    K_KP_MINUS,
    K_KP_4,
    K_KP_5,
    K_KP_6,
    K_KP_PLUS,
    K_KP_1,
    K_KP_2,
    K_KP_3,
    K_KP_0,
    K_KP_DOT,
    K_OEM_102 = 0x56, // from dinput: < > | on UK/German keyboards
    K_F11 = 0x57,
    K_F12 = 0x58,
    K_F13 = 0x64,
    K_F14 = 0x65,
    K_F15 = 0x66,
    K_KANA = 0x70,
    K_ABNT_C1 = 0x7E, // from dinput: ? on Portugese (Brazilian) keyboards
    K_CONVERT = 0x79,
    K_NOCONVERT = 0x7B,
    K_YEN = 0x7D,
    K_KP_EQUALS = 0x8D,
    //K_CIRCUMFLEX = 0x90, // this is circumflex on japanese keyboards, ..
    K_PREVTRACK = 0x90, // from dinput: .. but also "Previous Track"
    K_AT = 0x91,
    K_COLON = 0x92,
    K_UNDERLINE = 0x93,
    K_KANJI = 0x94,
    K_STOP = 0x95,
    K_AX = 0x96,
    K_UNLABELED = 0x97,
    K_NEXTTRACK = 0x99, // from dinput
    K_KP_ENTER = 0x9C,
    K_RCTRL = 0x9D,
    // some more from dinput:
    K_MUTE = 0xA0,
    K_CALCULATOR = 0xA1,
    K_PLAYPAUSE = 0xA2,
    K_MEDIASTOP = 0xA4,
    K_VOLUMEDOWN = 0xAE,
    K_VOLUMEUP = 0xB0,
    K_WEBHOME = 0xB2,

    K_KP_COMMA = 0xB3,
    K_KP_SLASH = 0xB5,
    K_PRINTSCREEN = 0xB7, // aka SysRq
    K_RALT = 0xB8,
    K_PAUSE = 0xC5,
    K_HOME = 0xC7,
    K_UPARROW = 0xC8,
    K_PGUP = 0xC9,
    K_LEFTARROW = 0xCB,
    K_RIGHTARROW = 0xCD,
    K_END = 0xCF,
    K_DOWNARROW = 0xD0,
    K_PGDN = 0xD1,
    K_INS = 0xD2,
    K_DEL = 0xD3,
    K_LWIN = 0xDB,
    K_RWIN = 0xDC,
    K_APPS = 0xDD,
    K_POWER = 0xDE,
    K_SLEEP = 0xDF,

    // DG: dinput has some more buttons, let's support them as well
    K_WAKE = 0xE3,
    K_WEBSEARCH = 0xE5,
    K_WEBFAVORITES = 0xE6,
    K_WEBREFRESH = 0xE7,
    K_WEBSTOP = 0xE8,
    K_WEBFORWARD = 0xE9,
    K_WEBBACK = 0xEA,
    K_MYCOMPUTER = 0xEB,
    K_MAIL = 0xEC,
    K_MEDIASELECT = 0xED,

    //------------------------
    // K_JOY codes must be contiguous, too
    //------------------------

    K_JOY1 = 256,
    K_JOY2,
    K_JOY3,
    K_JOY4,
    K_JOY5,
    K_JOY6,
    K_JOY7,
    K_JOY8,
    K_JOY9,
    K_JOY10,
    K_JOY11,
    K_JOY12,
    K_JOY13,
    K_JOY14,
    K_JOY15,
    K_JOY16,

    K_JOY_STICK1_UP,
    K_JOY_STICK1_DOWN,
    K_JOY_STICK1_LEFT,
    K_JOY_STICK1_RIGHT,

    K_JOY_STICK2_UP,
    K_JOY_STICK2_DOWN,
    K_JOY_STICK2_LEFT,
    K_JOY_STICK2_RIGHT,

    K_JOY_TRIGGER1,
    K_JOY_TRIGGER2,

    K_JOY_DPAD_UP,
    K_JOY_DPAD_DOWN,
    K_JOY_DPAD_LEFT,
    K_JOY_DPAD_RIGHT,

    //------------------------
    // K_MOUSE enums must be contiguous (no char codes in the middle)
    //------------------------

    K_MOUSE1,
    K_MOUSE2,
    K_MOUSE3,
    K_MOUSE4,
    K_MOUSE5,
    K_MOUSE6,
    K_MOUSE7,
    K_MOUSE8,
    K_MOUSE9,
    K_MOUSE10,
    K_MOUSE11,
    K_MOUSE12,
    K_MOUSE13,
    K_MOUSE14,
    K_MOUSE15,
    K_MOUSE16,

    K_MWHEELDOWN,
    K_MWHEELUP,

    K_LAST_KEY,
};
