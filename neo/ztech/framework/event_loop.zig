const getMilliseconds = @import("../main.zig").Sys_Milliseconds;
const idlib = @import("../idlib.zig");
const SysEvent = @import("../sys/event.zig").SysEvent;
const cvar = @import("cvar_system.zig");
const Allocator = @import("std").mem.Allocator;

const MAX_PUSHED_EVENTS = 64;

pub const EventLoop = extern struct {
    com_journalFile: ?*idlib.File,
    com_journalDataFile: ?*idlib.File,
    initialTimeOffset: c_int,
    com_pushedEventsHead: c_int,
    com_pushedEventsTail: c_int,
    com_pushedEvents: [MAX_PUSHED_EVENTS]SysEvent,

    pub fn init(event_loop: *EventLoop, allocator: Allocator) Allocator.Error!void {
        event_loop.initialTimeOffset = getMilliseconds();

        try cvar.setCVarsFromArgs("journal", allocator);
        // TODO journaling events
    }
};

pub const instance = @extern(*EventLoop, .{ .name = "eventLoopLocal" });
