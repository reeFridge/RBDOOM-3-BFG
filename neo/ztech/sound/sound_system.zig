const idlib = @import("../idlib.zig");
const getMilliseconds = @import("../main.zig").Sys_Milliseconds;
const alc = @cImport(@cInclude("AL/alc.h"));

const SoundVoice = extern struct {};
const SoundSample = extern struct {};
const SoundWorld = extern struct {};
const SoundHardware = extern struct {
    device: *alc.ALCdevice,
    context: *alc.ALCcontext,
    lastResetTime: c_int,
    voices: idlib.idStaticList(*SoundVoice, max_hardware_voices * 2),
    zombieVoices: idlib.idStaticList(*SoundVoice, max_hardware_voices * 2),
    freeVoices: idlib.idStaticList(*SoundVoice, max_hardware_voices * 2),

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
        bufferNumber: c_int = 0,
    };

    vptr: *anyopaque,
    streamBufferMutex: idlib.idSysMutex,
    freeStreamBufferContexts: idlib.idStaticList(*BufferContext, max_sound_buffers),
    activeStreamBufferContexts: idlib.idStaticList(*BufferContext, max_sound_buffers),
    bufferContexts: idlib.idStaticList(BufferContext, max_sound_buffers),
    currentSoundWorld: ?*SoundWorld = null,
    soundWorlds: idlib.idStaticList(*SoundWorld, 32),
    samples: idlib.idList(*SoundSample),
    sampleHash: idlib.idHashIndex,
    hardware: SoundHardware,
    random: Random,
    soundTime: c_int = 0,
    muted: bool = false,
    musicMuted: bool = false,
    needsRestart: bool = false,
    insideLevelLoad: bool = false,

    pub fn init(sound_system: *SoundSystem) error{}!void {
        sound_system.soundTime = getMilliseconds();
        sound_system.random.seed = @intCast(sound_system.soundTime);

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
