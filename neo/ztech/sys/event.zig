pub const SysEvent = extern struct {
    pub const Type = enum(c_int) {
        NONE, // evTime is still valid
        KEY, // evValue is a key code, evValue2 is the down flag
        CHAR, // evValue is an Unicode UTF-32 char (or non-surrogate UTF-16)
        MOUSE, // evValue and evValue2 are relative signed x / y moves
        MOUSE_ABSOLUTE, // evValue and evValue2 are absolute coordinates in the window's client area.
        MOUSE_LEAVE, // evValue and evValue2 are meaninless, this indicates the mouse has left the client area.
        JOYSTICK, // evValue is an axis number and evValue2 is the current state (-127 to 127)
        CONSOLE, // evPtr is a char*, from typing something at a non-game console
    };

    evType: Type,
    evValue: c_int,
    evValue2: c_int,
    evPtrLength: c_int, // bytes of data pointed to by evPtr, for journaling
    evPtr: ?*anyopaque, // this must be manually freed if not NULL
    inputDevice: c_int,
};
