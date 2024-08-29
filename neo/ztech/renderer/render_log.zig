const BackendCounters = @import("render_backend.zig").BackendCounters;
const nvrhi = @import("nvrhi.zig");

pub const RenderLog = opaque {
    extern fn c_renderLog_init(*RenderLog) callconv(.C) void;
    extern fn c_renderLog_shutdown(*RenderLog) callconv(.C) void;
    extern fn c_renderLog_endFrame(*RenderLog) callconv(.C) void;
    extern fn c_renderLog_fetchGPUTimers(*RenderLog, *BackendCounters) callconv(.C) void;
    extern fn c_renderLog_startFrame(*RenderLog, *nvrhi.ICommandList) callconv(.C) void;
    extern fn c_renderLog_openMainBlock(*RenderLog, renderLogMainBlock_t) callconv(.C) void;

    pub fn openMainBlock(render_log: *RenderLog, block: renderLogMainBlock_t) void {
        c_renderLog_openMainBlock(render_log, block);
    }

    pub fn fetchGPUTimers(render_log: *RenderLog, pc: *BackendCounters) void {
        c_renderLog_fetchGPUTimers(render_log, pc);
    }

    pub fn startFrame(render_log: *RenderLog, command_list: *nvrhi.ICommandList) void {
        c_renderLog_startFrame(render_log, command_list);
    }

    pub fn endFrame(render_log: *RenderLog) void {
        c_renderLog_endFrame(render_log);
    }

    pub fn init(render_log: *RenderLog) void {
        c_renderLog_init(render_log);
    }

    pub fn shutdown(render_log: *RenderLog) void {
        c_renderLog_shutdown(render_log);
    }
};

pub const instance = @extern(*RenderLog, .{ .name = "renderLog" });

pub const MRB_GPU_TIME: c_int = 0;
pub const MRB_BEGIN_DRAWING_VIEW: c_int = 1;
pub const MRB_FILL_DEPTH_BUFFER: c_int = 2;
pub const MRB_FILL_GEOMETRY_BUFFER: c_int = 3;
pub const MRB_SSAO_PASS: c_int = 4;
pub const MRB_AMBIENT_PASS: c_int = 5;
pub const MRB_SHADOW_ATLAS_PASS: c_int = 6;
pub const MRB_DRAW_INTERACTIONS: c_int = 7;
pub const MRB_DRAW_SHADER_PASSES: c_int = 8;
pub const MRB_FOG_ALL_LIGHTS: c_int = 9;
pub const MRB_BLOOM: c_int = 10;
pub const MRB_DRAW_SHADER_PASSES_POST: c_int = 11;
pub const MRB_DRAW_DEBUG_TOOLS: c_int = 12;
pub const MRB_CAPTURE_COLORBUFFER: c_int = 13;
pub const MRB_MOTION_VECTORS: c_int = 14;
pub const MRB_TAA: c_int = 15;
pub const MRB_TONE_MAP_PASS: c_int = 16;
pub const MRB_POSTPROCESS: c_int = 17;
pub const MRB_DRAW_GUI: c_int = 18;
pub const MRB_CRT_POSTPROCESS: c_int = 19;
pub const MRB_TOTAL: c_int = 20;
pub const MRB_TOTAL_QUERIES: c_int = 40;
pub const renderLogMainBlock_t = c_int;
