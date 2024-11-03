const job_manager = @import("parallel_job_manager.zig");
const idlib = @import("../idlib.zig");

pub const ParallelJobList = opaque {
    extern fn c_parallelJobList_wait(*ParallelJobList) void;

    pub fn wait(job_list: *ParallelJobList) void {
        c_parallelJobList_wait(job_list);
    }
};

pub const MAX_JOBLISTS = 32;
pub const JobListId = enum(c_int) {
    RENDERER_FRONTEND = 0,
    RENDERER_BACKEND = 1,
    UTILITY = 9,
};

pub const JobListPriority = enum(c_int) {
    NONE = 0,
    LOW = 1,
    MEDIUM = 2,
    HIGH = 3,
};

const InterlockedInt = c_int;
const SysInterlockedInteger = extern struct {
    value: InterlockedInt,
};

const MAX_THREADS = 32;

const ThreadJobList = extern struct {
    const Threads = extern struct {
        const JobRunFn = fn (?*anyopaque) callconv(.C) void;

        const ThreadStats = extern struct {
            numExecutedJobs: c_uint,
            numExecutedSyncs: c_uint,
            submitTime: u64,
            startTime: u64,
            endTime: u64,
            waitTime: u64,
            threadExecTime: [MAX_THREADS]u64,
            threadTotalTime: [MAX_THREADS]u64,
        };

        const Job = extern struct {
            function: *const JobRunFn,
            data: ?*anyopaque,
            executed: c_int,
        };

        const NUM_DONE_GUARDS = 4;

        threaded: bool,
        done: bool,
        hasSignal: bool,
        listId: JobListId,
        listPriority: JobListPriority,
        maxJobs: c_uint,
        maxSyncs: c_uint,
        numSyncs: c_uint,
        lastSignalJob: c_int,
        waitForGuard: ?*SysInterlockedInteger,
        doneGuards: [NUM_DONE_GUARDS]SysInterlockedInteger,
        currentDoneGuard: c_int,
        version: SysInterlockedInteger,
        jobList: idlib.idList(Job),
        signalJobCount: idlib.idList(SysInterlockedInteger),
        currentJob: SysInterlockedInteger,
        fetchLock: SysInterlockedInteger,
        numThreadsExecuting: SysInterlockedInteger,
        deferredThreadStats: ThreadStats,
        threadStats: ThreadStats,
    };

    jobList: ?[*]Threads,
    version: c_int,
};

pub const JobThread = extern struct {
    base: idlib.idSysThread,
    jobLists: [MAX_JOBLISTS]ThreadJobList,
    firstJobList: c_uint,
    lastJobList: c_uint,
    addJobMutex: idlib.idSysMutex,
    threadNum: c_uint,

    pub fn start(_: *JobThread, _: job_manager.Core, _: usize) void {
        // TODO: implement
    }
};
