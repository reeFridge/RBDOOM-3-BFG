const std = @import("std");
const FixedBufferString = @import("../string.zig").FixedBufferString;

pub const Signal = struct {
    condition: std.Thread.Condition = .{},
    mutex: std.Thread.Mutex = .{},
    num_waiting_threads: u32 = 0,
    manual_reset: bool = false,
    signaled: bool = false,

    pub fn raise(signal: *Signal) void {
        signal.mutex.lock();

        if (signal.manual_reset) {
            signal.signaled = true;
            // wake all threads waiting on this condition
            signal.condition.broadcast();
        } else {
            if (signal.num_waiting_threads > 0) {
                // unblocks one of them
                signal.condition.signal();
            } else {
                signal.signaled = true;
            }
        }

        signal.mutex.unlock();
    }

    pub fn clear(signal: *Signal) void {
        signal.mutex.lock();
        signal.signaled = false;
        signal.mutex.unlock();
    }

    pub fn waitUntilUnlock(signal: *Signal) void {
        signal.mutex.lock();
        defer signal.mutex.unlock();

        // if there is a signal that hasn't been used yet
        if (signal.signaled) {
            if (!signal.manual_reset) {
                signal.signaled = false;
            }
        } else {
            // we'll have to wait for a signal
            signal.num_waiting_threads += 1;
            defer signal.num_waiting_threads -= 1;

            signal.condition.wait(&signal.mutex);
        }
    }
};

pub const Thread = struct {
    const PayloadFn = fn (*Thread) u8;

    name: FixedBufferString(256) = .{},
    sys_thread: ?std.Thread = null,
    is_worker: bool = false,
    is_running: bool = false,
    is_terminating: bool = false,
    more_work_to_do: bool = false,
    signal_worker_done: Signal = .{ .manual_reset = true },
    signal_more_work_to_do: Signal = .{},
    signal_mutex: std.Thread.Mutex = .{},
    payload_fn: *const PayloadFn,

    pub fn deinit(thread: *Thread) void {
        thread.stop();
        thread.wait();

        if (thread.sys_thread) |sys_thread| {
            sys_thread.join();
            thread.sys_thread = null;
        }
    }

    pub fn spawn(thread: *Thread, name: []const u8, stack_size: usize) bool {
        if (thread.is_running) return false;

        if (thread.sys_thread) |sys_thread| sys_thread.join();

        thread.name.assignSlice(name) catch @panic("thread name is too long");

        const sys_thread = std.Thread.spawn(
            .{ .stack_size = stack_size },
            threadProc,
            .{thread},
        ) catch |err| {
            std.debug.print("[THREAD] error: {s}\n", .{@errorName(err)});
            @panic("can't spawn thread");
        };

        thread.sys_thread = sys_thread;
        thread.is_running = true;

        return true;
    }

    /// do nothing until signalWork fn would be called
    pub fn spawnWorker(thread: *Thread, name: []const u8, stack_size: usize) bool {
        if (thread.is_running) return false;

        thread.is_worker = true;

        const result = thread.spawn(name, stack_size);
        thread.signal_worker_done.waitUntilUnlock();

        return result;
    }

    pub fn signalWork(thread: *Thread) void {
        if (thread.is_worker) {
            thread.signal_mutex.lock();
            thread.more_work_to_do = true;
            thread.signal_worker_done.clear();
            thread.signal_more_work_to_do.raise();
            thread.signal_mutex.unlock();
        }
    }

    pub fn stop(thread: *Thread) void {
        if (!thread.is_running) return;

        if (thread.is_worker) {
            thread.signal_mutex.lock();
            thread.more_work_to_do = true;
            thread.signal_worker_done.clear();
            thread.is_terminating = true;
            thread.signal_more_work_to_do.raise();
            thread.signal_mutex.unlock();
        } else {
            thread.is_terminating = true;
        }
    }

    pub fn wait(thread: *Thread) void {
        if (thread.is_worker) {
            thread.signal_worker_done.waitUntilUnlock();
        } else if (thread.is_running) {
            if (thread.sys_thread) |sys_thread| sys_thread.join();
            thread.sys_thread = null;
        }
    }

    fn threadProc(thread: *Thread) u8 {
        var return_code: u8 = 0;

        if (thread.is_worker) {
            while (true) {
                thread.signal_mutex.lock();
                if (thread.more_work_to_do) {
                    thread.more_work_to_do = false;
                    thread.signal_more_work_to_do.clear();
                    thread.signal_mutex.unlock();
                } else {
                    thread.signal_worker_done.raise();
                    thread.signal_mutex.unlock();
                    thread.signal_more_work_to_do.waitUntilUnlock();
                    continue;
                }

                if (thread.is_terminating) {
                    break;
                }

                return_code = thread.payload_fn(thread);
            }
            thread.signal_worker_done.raise();
        } else {
            return_code = thread.payload_fn(thread);
        }

        thread.is_running = false;

        return return_code;
    }
};
