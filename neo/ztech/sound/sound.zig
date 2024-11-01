const Decl = @import("../framework/decl_manager.zig").Decl;
const idlib = @import("../idlib.zig");

// TODO: OpenAL
pub const SoundSample = opaque {};

pub const SoundShader = extern struct {
    pub const Params = extern struct {
        minDistance: f32,
        maxDistance: f32,
        volume: f32, // in dB.  Negative values get quieter
        shakes: f32,
        soundShaderFlags: c_int, // SSF_* bit flags
        soundClass: c_int, // for global fading of sounds
    };

    base: Decl,
    parms: Params,
    speakerMask: c_int,
    altSound: ?*const SoundShader,
    leadin: bool,
    leadinVolume: f32,
    entries: idlib.idList(*SoundSample),
};
