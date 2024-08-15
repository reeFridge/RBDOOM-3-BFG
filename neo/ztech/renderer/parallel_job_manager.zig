const ParallelJobList = @import("parallel_job_list.zig").ParallelJobList;

pub const ParallelJobManager = opaque {
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

    pub fn allocJobList(
        manager: *ParallelJobManager,
        id: c_int,
        priority: c_int,
        max_jobs: c_uint,
        max_syncs: c_uint,
        color: ?*const anyopaque,
    ) *ParallelJobList {
        return c_parallelJobManager_allocJobList(
            manager,
            id,
            priority,
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
