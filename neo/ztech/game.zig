const CTimeState = extern struct {
    time: c_int,
    previous_time: c_int,

    pub fn delta(state: CTimeState) i32 {
        return state.time - state.previous_time;
    }
};

pub extern fn c_getTimeState() callconv(.C) CTimeState;
pub extern fn c_isNewFrame() callconv(.C) bool;
