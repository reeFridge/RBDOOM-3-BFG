const std = @import("std");
const getMilliseconds = @import("../main.zig").Sys_Milliseconds;
const idlib = @import("../idlib.zig");
const sys_event = @import("../sys/event.zig");
const Event = sys_event.Event;
const cvar = @import("cvar_system.zig");
const Allocator = @import("std").mem.Allocator;
const cmd_system = @import("cmd_system.zig");

const max_pushed_events = 64;

pub const EventLoop = extern struct {
    journal_file: ?*idlib.File,
    journal_data_file: ?*idlib.File,
    initial_time_offset: c_int,
    pushed_events_head: u32,
    pushed_events_tail: u32,
    pushed_events: [max_pushed_events]Event,

    pub fn init(event_loop: *EventLoop, allocator: Allocator) Allocator.Error!void {
        event_loop.initial_time_offset = getMilliseconds();

        try cvar.setCVarsFromArgs("journal", allocator);
        // TODO journaling events
    }

    pub fn run(event_loop: *EventLoop, command_execution: bool) void {
        while (true) {
            if (command_execution) {
                cmd_system.instance.executeCommandBuffer() catch |err| {
                    std.debug.print(
                        "[CMD] error inside event loop: {s}\n",
                        .{@errorName(err)},
                    );
                };
            }

            const event = event_loop.getEvent() orelse return;
            if (event.type == .none) return;

            processEvent(event);
        }
    }

    fn getEvent(event_loop: *EventLoop) ?Event {
        if (event_loop.pushed_events_head > event_loop.pushed_events_tail) {
            event_loop.pushed_events_tail += 1;
            const valid_index = (event_loop.pushed_events_tail - 1) & (max_pushed_events - 1);
            return event_loop.pushed_events[valid_index];
        }

        return sys_event.getEvent();
    }

    fn processEvent(event: Event) void {
        switch (event.type) {
            .signal => switch (@as(sys_event.Signal, @enumFromInt(event.first_value))) {
                .quit => cmd_system.instance.appendCommandText("quit\n"),
                .vid_restart => cmd_system.instance.appendCommandText("vid_restart\n"),
            },
            else => |event_type| {
                std.debug.print("[EVENT_LOOP] unknown event: {}\n", .{event_type});
            },
        }
    }
};

pub const instance = @extern(*EventLoop, .{ .name = "eventLoopLocal" });
