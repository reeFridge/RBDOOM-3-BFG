pub const ParallelJobList = opaque {
    extern fn c_parallelJobList_wait(*ParallelJobList) void;

    pub fn wait(job_list: *ParallelJobList) void {
        c_parallelJobList_wait(job_list);
    }
};

pub const JobListId = struct {
    pub const JOBLIST_RENDERER_FRONTEND: c_int = 0;
    pub const JOBLIST_RENDERER_BACKEND: c_int = 1;
    pub const JOBLIST_UTILITY: c_int = 9;
    pub const MAX_JOBLISTS: c_int = 32;
};

pub const JobListPriority = struct {
    pub const JOBLIST_PRIORITY_NONE: c_int = 0;
    pub const JOBLIST_PRIORITY_LOW: c_int = 1;
    pub const JOBLIST_PRIORITY_MEDIUM: c_int = 2;
    pub const JOBLIST_PRIORITY_HIGH: c_int = 3;
};
