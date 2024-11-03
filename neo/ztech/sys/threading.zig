const std = @import("std");
const pthread = @cImport(@cInclude("pthread.h"));

pub const SignalHandle = extern struct {
    cond: pthread.pthread_cond_t,
    mutex: pthread.pthread_mutex_t,
    waiting: c_int, // number of threads waiting for a signal
    manualReset: bool,
    signaled: bool, // is it signaled right now?
};

pub const GetCPUInfoError = std.Thread.CpuCountError;

pub const CPUInfo = struct {
    logical_cores: usize,
    physical_cores: usize,
    packages: usize,
};

pub fn getCpuInfo() GetCPUInfoError!CPUInfo {
    return .{
        .logical_cores = try std.Thread.getCpuCount(),
        .physical_cores = 0,
        .packages = 0,
    };
}
