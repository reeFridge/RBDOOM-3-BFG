const std = @import("std");
const Decl = @import("../framework/decl_manager.zig").Decl;
const DeclType = @import("../framework/decl_manager.zig").DeclType;
const idlib = @import("../idlib.zig");

// TODO: OpenAL
pub const SoundSample = opaque {};

pub const SoundShader = extern struct {
    pub const default_definition =
        \\{
        \\  "_default.wav"
        \\}
    ;
    pub const Params = extern struct {
        minDistance: f32 = 0,
        maxDistance: f32 = 0,
        volume: f32 = 0, // in dB.  Negative values get quieter
        shakes: f32 = 0,
        soundShaderFlags: c_int = 0, // SSF_* bit flags
        soundClass: c_int = 0, // for global fading of sounds
    };

    base: Decl = .{},
    parms: Params = .{},
    speakerMask: c_int = 0,
    altSound: ?*const SoundShader = null,
    leadin: bool = false,
    leadinVolume: f32 = 0,
    entries: idlib.List(*SoundSample) = .{},

    pub fn init(self: *SoundShader) void {
        self.* = .{};
    }
};
