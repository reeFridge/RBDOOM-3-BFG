const idlib = @import("../idlib.zig");
const CVec4 = @import("../math/vector.zig").CVec4;
const EditField = @import("edit_field.zig").EditField;
const RenderSystem = @import("../renderer/render_system.zig");

const CON_TEXTSIZE = 0x30000;
const NUM_CON_TIMES = 4;
const COMMAND_HISTORY = 64;
const CONSOLE_FIRSTREPEAT = 200;

const Justify = enum(c_int) {
    JUSTIFY_LEFT,
    JUSTIFY_RIGHT,
    JUSTIFY_CENTER_LEFT,
    JUSTIFY_CENTER_RIGHT,
};

const OverlayText = extern struct {
    text: idlib.Str,
    justify: Justify,
    time: c_int,
};

const DebugGraph = opaque {};

pub const Console = extern struct {
    vptr: *anyopaque,
    LOCALSAFE_LEFT: u32,
    LOCALSAFE_RIGHT: u32,
    LOCALSAFE_TOP: u32,
    LOCALSAFE_BOTTOM: u32,
    LOCALSAFE_WIDTH: u32,
    LOCALSAFE_HEIGHT: u32,
    LINE_WIDTH: u32,
    TOTAL_LINES: u32,
    keyCatching: bool,
    text: [CON_TEXTSIZE]c_short,
    current: c_int, // line where next message will be printed
    x: c_int, // offset in current line for next print
    display: c_int, // bottom of console displays this line
    lastKeyEvent: c_int, // time of last key event for scroll delay
    nextKeyEvent: c_int, // keyboard repeat rate
    displayFrac: f32, // approaches finalFrac at con_speed
    finalFrac: f32, // 0.0 to 1.0 lines of console to display
    fracTime: c_int, // time of last displayFrac update
    vislines: c_int, // in scanlines
    times: [NUM_CON_TIMES]c_int, // cls.realtime time the line was generated
    color: CVec4,
    historyEditLines: [COMMAND_HISTORY]EditField,

    nextHistoryLine: c_int, // the last line in the history buffer, not masked
    historyLine: c_int, // the line being displayed from history buffer
    consoleField: EditField,

    overlayText: idlib.List(OverlayText),
    debugGraphs: idlib.List(*DebugGraph),

    lastVirtualScreenWidth: c_int,
    lastVirtualScreenHeight: c_int,

    pub fn init(console: *Console) void {
        console.keyCatching = false;

        console.LOCALSAFE_LEFT = 0;
        console.LOCALSAFE_RIGHT = RenderSystem.SCREEN_WIDTH - console.LOCALSAFE_LEFT;
        console.LOCALSAFE_TOP = 24;
        console.LOCALSAFE_BOTTOM = RenderSystem.SCREEN_HEIGHT - console.LOCALSAFE_TOP;
        console.LOCALSAFE_WIDTH = console.LOCALSAFE_RIGHT - console.LOCALSAFE_LEFT;
        console.LOCALSAFE_HEIGHT = console.LOCALSAFE_BOTTOM - console.LOCALSAFE_TOP;

        console.LINE_WIDTH = @divTrunc(console.LOCALSAFE_WIDTH, RenderSystem.SMALLCHAR_WIDTH) - 2;
        console.TOTAL_LINES = @divTrunc(CON_TEXTSIZE, console.LINE_WIDTH);

        console.lastKeyEvent = -1;
        console.nextKeyEvent = CONSOLE_FIRSTREPEAT;

        console.consoleField.clear();
        console.consoleField.widthInChars = console.LINE_WIDTH;

        for (&console.historyEditLines) |*line| {
            line.clear();
            line.widthInChars = console.LINE_WIDTH;
        }
    }
};

pub const instance = @extern(*Console, .{ .name = "localConsole" });
