const std = @import("std");
const posix = std.posix;
const common = @import("framework/common.zig");
const cmd = @import("framework/cmd_system.zig");
const console = @import("framework/console.zig");

const c_string = @cImport(@cInclude("string.h"));
const c_signal = @cImport(@cInclude("signal.h"));

usingnamespace @import("lib.zig");

extern var set_exit: c_int;

var sys_time_base: c_uint = 0;
const clock_to_use = posix.CLOCK.MONOTONIC_RAW;
fn initTime() posix.ClockGetTimeError!void {
    const timespec = try posix.clock_gettime(clock_to_use);

    if (sys_time_base == 0) {
        sys_time_base = @intCast(timespec.sec);
    }
}

pub export fn Sys_Milliseconds() c_int {
    if (sys_time_base == 0) @panic("Clock is not initialized");

    const timespec = posix.clock_gettime(clock_to_use) catch unreachable;

    const current_time =
        (timespec.sec - sys_time_base) * 1000 +
        @divTrunc(timespec.nsec, 1000000);
    return @intCast(current_time);
}

pub fn exit(exit_code: u8) noreturn {
    clearSignals();

    if (set_exit != 0) {
        posix.exit(@intCast(set_exit));
    }

    posix.exit(@intCast(exit_code));
}

var double_fault = false;

fn signalHandler(
    signum: i32,
    _: *const posix.siginfo_t,
    _: ?*anyopaque,
) callconv(.C) void {
    const sigstr = c_string.strsignal(signum);
    if (double_fault) {
        std.debug.print("[SIG({}): {s}] double fault, bailing out\n", .{ signum, sigstr });
        exit(@intCast(signum));
    }

    double_fault = true;

    std.debug.print("[SIG({}): {s}]\n", .{ signum, sigstr });
    std.debug.print("Trying to exit gracefully...\n", .{});

    set_exit = @intCast(signum);

    common.instance.quit();
}

fn signalHandlerFPE(
    signum: i32,
    _: *const posix.siginfo_t,
    _: ?*anyopaque,
) callconv(.C) void {
    std.debug.assert(signum == posix.SIG.FPE);
    const sigstr = c_string.strsignal(signum);

    std.debug.print("[SIG({}): {s}]\n", .{ signum, sigstr });
}

const sig_list: []const u6 = &.{
    posix.SIG.HUP,
    posix.SIG.QUIT,
    posix.SIG.ILL,
    posix.SIG.TRAP,
    posix.SIG.IOT,
    posix.SIG.BUS,
    posix.SIG.FPE,
    posix.SIG.SEGV,
    posix.SIG.PIPE,
    posix.SIG.ABRT,
};

fn initSignals() void {
    const action: posix.Sigaction = .{
        .handler = .{ .sigaction = signalHandler },
        .mask = posix.empty_sigset,
        .flags = (posix.SA.SIGINFO | posix.SA.NODEFER),
    };

    for (sig_list) |sig| {
        if (sig == posix.SIG.FPE) {
            var fpe_action = action;
            fpe_action.handler = .{ .sigaction = signalHandlerFPE };
            posix.sigaction(sig, &fpe_action, null);
        } else {
            posix.sigaction(sig, &action, null);
        }
    }

    // if the process is backgrounded (running non interactively)
    // then SIGTTIN or SIGTOU could be emitted, if not caught, turns into a SIGSTP
    _ = c_signal.signal(posix.SIG.TTIN, posix.SIG.IGN);
    _ = c_signal.signal(posix.SIG.TTOU, posix.SIG.IGN);
}

fn clearSignals() void {
    const action: posix.Sigaction = .{
        .handler = .{ .handler = posix.SIG.DFL },
        .mask = posix.empty_sigset,
        .flags = 0,
    };

    for (sig_list) |sig| {
        posix.sigaction(sig, &action, null);
    }
}

fn earlyInit() posix.ClockGetTimeError!void {
    initSignals();
    try initTime();
}

fn lateInit() void {
    // TODO: initConsoleInput
    // TODO: setPid
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    try earlyInit();

    if (args.len > 1) {
        common.Common.parseCommandLine(args[1..]);
    }

    try common.instance.init(allocator);

    // for debug
    console.instance.open();

    //lateInit();

    while (true) try common.instance.frame(allocator);
}
