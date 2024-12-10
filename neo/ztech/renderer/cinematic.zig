const std = @import("std");
const Image = @import("image.zig").Image;
const idlib = @import("../idlib.zig");
const nvrhi = @import("nvrhi.zig");

const BinkHandle = extern struct {
    is_valid: bool,
    instance_index: c_int,
};

const AudioInfo = extern struct {
    sample_rate: u32,
    n_channels: u32,
    ideal_buffer_size: u32,
};

const ImagePlane = extern struct {
    width: u32,
    height: u32,
    pitch: u32,
    data: ?[*]u8,
};

const YuvBuffer = [3]ImagePlane;

const CinematicStatus = enum(c_int) {
    idle,
    play,
    eof,
    id_blt,
    id_idle,
    looped,
    id_wait,
};

const CinematicAudio = opaque {};

pub const Cinematic = extern struct {
    vptr: *anyopaque,
    bink_handle: BinkHandle,
    yuv_buffer: YuvBuffer,
    has_frame: bool,
    frame_pos: u32,
    num_frames: u32,
    img_y: ?*Image,
    img_cr: ?*Image,
    img_cb: ?*Image,
    audio_tracks: u32,
    track_index: u32,
    bink_info: AudioInfo,
    img: ?*Image,
    is_roq: bool,
    mcomp: [256]usize,
    q_status: ?*?*[2]u8,
    filename: idlib.idStr,
    cin_width: u32,
    cin_height: u32,
    file: ?*anyopaque,
    status: CinematicStatus,
    tfps: u32,
    roq_played: u32,
    roq_size: u32,
    roq_frame_size: u32,
    on_quad: u32,
    num_quads: u32,
    samples_per_line: u32,
    roq_id: u32,
    screen_delta: u32,
    buffer: ?[*]u8,
    samples_per_pixel: u32,
    x_size: u32,
    y_size: u32,
    max_size: u32,
    min_size: u32,
    normal_buffer_0: u32,
    roq_flags: u32,
    roq_f0: u32,
    roq_f1: u32,
    t: [2]u32,
    roq_fps: u32,
    draw_x: u32,
    draw_y: u32,
    animation_length: u32,
    start_time: u32,
    frame_rate: f32,
    image: ?[*]u8,
    looping: bool,
    dirty: bool,
    half: bool,
    smoothed_double: bool,
    in_memory: bool,
    cinematic_audio: ?*CinematicAudio,

    pub fn create(allocator: std.mem.Allocator) std.mem.Allocator.Error!*Cinematic {
        // TODO: init
        return try allocator.create(Cinematic);
    }

    pub fn initFromFile(
        cinematic: *Cinematic,
        qpath: []const u8,
        loop: bool,
        command_list: ?*nvrhi.ICommandList,
    ) error{}!void {
        _ = cinematic;
        _ = qpath;
        _ = loop;
        _ = command_list;
        // TODO: init
    }
};
