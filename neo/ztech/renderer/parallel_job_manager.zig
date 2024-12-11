//! @exportCVars
const std = @import("std");
const idlib = @import("../idlib.zig");
const job_list = @import("parallel_job_list.zig");
const ParallelJobList = job_list.ParallelJobList;
const JobThread = job_list.JobThread;
const threading = @import("../sys/threading.zig");
const cvar = @import("../framework/cvar_system.zig");
const CVar = cvar.CVar;

pub const Core = enum(c_int) {
    CORE_ANY = -1,
    CORE_0A,
    CORE_0B,
    CORE_1A,
    CORE_1B,
    CORE_2A,
    CORE_2B,
};

const MAX_JOB_THREADS = 32;
const NUM_JOB_THREADS = "2";

pub var jobs_num_threads: CVar = CVar.initMinMax(
    "jobs_numThreads",
    NUM_JOB_THREADS,
    cvar.CVarFlags.CVAR_INTEGER | cvar.CVarFlags.CVAR_NOCHEAT,
    "number of threads used to crunch through jobs",
    0,
    MAX_JOB_THREADS,
);

pub const ParallelJobManager = extern struct {
    vptr: *anyopaque,
    threads: [MAX_JOB_THREADS]JobThread,
    maxThreads: c_uint,
    numPhysicalCpuCores: c_int,
    numLogicalCpuCores: c_int,
    numCpuPackages: c_int,
    jobLists: idlib.idStaticList(*ParallelJobList, job_list.MAX_JOBLISTS),

    extern fn c_parallelJobManager_allocJobList(
        *ParallelJobManager,
        c_int,
        c_int,
        c_uint,
        c_uint,
        ?*const anyopaque,
    ) callconv(.C) *ParallelJobList;
    extern fn c_parallelJobManager_freeJobList(
        *ParallelJobManager,
        *ParallelJobList,
    ) callconv(.C) void;

    pub fn init(job_manager: *ParallelJobManager) threading.GetCPUInfoError!void {
        // TODO: use @splat(.CORE_ANY)
        var cores = [_]Core{.CORE_ANY} ** MAX_JOB_THREADS;

        for (&cores, 0..) |core, i| {
            const thread = &job_manager.threads[i];
            thread.start(core, i);
        }

        job_manager.maxThreads = @intCast(jobs_num_threads.integer_value);

        const cpu_info = try threading.getCpuInfo();
        job_manager.numPhysicalCpuCores = @intCast(cpu_info.physical_cores);
        job_manager.numLogicalCpuCores = @intCast(cpu_info.logical_cores);
        job_manager.numCpuPackages = @intCast(cpu_info.packages);
    }

    pub fn allocJobList(
        manager: *ParallelJobManager,
        id: job_list.JobListId,
        priority: job_list.JobListPriority,
        max_jobs: c_uint,
        max_syncs: c_uint,
        color: ?*const anyopaque,
    ) *ParallelJobList {
        return c_parallelJobManager_allocJobList(
            manager,
            @intFromEnum(id),
            @intFromEnum(priority),
            max_jobs,
            max_syncs,
            color,
        );
    }

    pub fn freeJobList(manager: *ParallelJobManager, list: *ParallelJobList) void {
        c_parallelJobManager_freeJobList(manager, list);
    }
};

pub const instance = @extern(*ParallelJobManager, .{ .name = "parallelJobManagerLocal" });
