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
    entries: idlib.idList(*SoundSample) = .{},

    pub fn init(self: *SoundShader) void {
        self.* = .{};
    }

    pub const ParseError = error{};
    pub fn parse(
        sound_shader: *SoundShader,
        definition_text: []const u8,
        allow_binary_version: bool,
        allocator: std.mem.Allocator,
    ) ParseError!void {
        _ = sound_shader;
        _ = allocator;
        _ = definition_text;
        _ = allow_binary_version;

        @panic("SoundShader.parse is not implemented");
    }

    pub fn setDefaultText(sound_shader: *SoundShader) error{}!void {
        _ = sound_shader;

        @panic("SoundShader.setDefaultText is not implemented");
    }

    pub fn freeData(sound_shader: *SoundShader, allocator: std.mem.Allocator) void {
        _ = sound_shader;
        _ = allocator;

        @panic("SoundShader.freeData is not implemented");
    }
};
