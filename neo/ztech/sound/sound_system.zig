const idlib = @import("../idlib.zig");
const getMilliseconds = @import("../main.zig").Sys_Milliseconds;
const c = @import("../sys/c_import.zig").c;

const SoundVoice = extern struct {};
const SoundSample = extern struct {};
const SoundWorld = extern struct {};
const SoundHardware = extern struct {
    device: *c.ALCdevice,
    context: *c.ALCcontext,
    last_reset_time: c_int,
    voices: idlib.StaticList(*SoundVoice, max_hardware_voices * 2),
    zombie_voices: idlib.StaticList(*SoundVoice, max_hardware_voices * 2),
    free_voices: idlib.StaticList(*SoundVoice, max_hardware_voices * 2),

    pub fn init(hw: *SoundHardware) error{}!void {
        _ = hw;
    }
};

const Random = extern struct {
    seed: c_uint,
};

pub const max_hardware_voices = 48;
pub const max_hardware_channels = 64;
pub const max_sound_buffers = max_hardware_voices * 3;
pub const max_channels_per_voice = 8;

pub const SoundSystem = extern struct {
    const BufferContext = extern struct {
        voice: ?*SoundVoice = null,
        sample: ?*SoundSample = null,
        buffer_number: c_int = 0,
    };

    vptr: *anyopaque,
    stream_buffer_mutex: idlib.SysMutex,
    free_stream_buffer_contexts: idlib.StaticList(*BufferContext, max_sound_buffers),
    active_stream_buffer_contexts: idlib.StaticList(*BufferContext, max_sound_buffers),
    buffer_contexts: idlib.StaticList(BufferContext, max_sound_buffers),
    current_sound_world: ?*SoundWorld = null,
    sound_worlds: idlib.StaticList(*SoundWorld, 32),
    samples: idlib.List(*SoundSample),
    sample_hash: idlib.HashIndex,
    hardware: SoundHardware,
    random: Random,
    sound_time: c_int = 0,
    muted: bool = false,
    music_muted: bool = false,
    needs_restart: bool = false,
    inside_level_load: bool = false,

    pub fn init(sound_system: *SoundSystem) error{}!void {
        sound_system.sound_time = getMilliseconds();
        sound_system.random.seed = @intCast(sound_system.sound_time);

        // if (!s_no_sound.getBool()) {
        try sound_system.hardware.init();
        try sound_system.initStreamBuffers();
        // }

        // TODO: addCommand testSound
        // TODO: addCommand s_restart
        // TODO: addCommand listSamples
    }

    fn initStreamBuffers(sound_system: *SoundSystem) error{}!void {
        _ = sound_system;
    }
};

pub const instance = @extern(*SoundSystem, .{ .name = "soundSystemLocal" });
