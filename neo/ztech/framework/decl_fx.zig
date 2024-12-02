const std = @import("std");
const Decl = @import("decl_manager.zig").Decl;
const idlib = @import("../idlib.zig");
const CVec3 = @import("../math/vector.zig").CVec3;

const FXActionType = enum(c_int) {
    FX_LIGHT,
    FX_PARTICLE,
    FX_DECAL,
    FX_MODEL,
    FX_SOUND,
    FX_SHAKE,
    FX_ATTACHLIGHT,
    FX_ATTACHENTITY,
    FX_LAUNCH,
    FX_SHOCKWAVE,
};

const FXSingleAction = extern struct {
    type: FXActionType,
    sibling: c_int,

    data: idlib.idStr,
    name: idlib.idStr,
    fire: idlib.idStr,

    delay: f32,
    duration: f32,
    restart: f32,
    size: f32,
    fadeInTime: f32,
    fadeOutTime: f32,
    shakeTime: f32,
    shakeAmplitude: f32,
    shakeDistance: f32,
    shakeImpulse: f32,
    lightRadius: f32,
    rotate: f32,
    random1: f32,
    random2: f32,

    lightColor: CVec3,
    offset: CVec3,
    axis: CVec3,

    soundStarted: bool,
    shakeStarted: bool,
    shakeFalloff: bool,
    shakeIgnoreMaster: bool,
    bindParticles: bool,
    explicitAxis: bool,
    noshadows: bool,
    particleTrackVelocity: bool,
    trackOrigin: bool,
};

pub const DeclFX = extern struct {
    base: Decl = .{},
    events: idlib.idList(FXSingleAction) = .{},
    joint: idlib.idStr = .{},

    pub fn init(self: *DeclFX) void {
        self.* = .{};
        self.joint.initEmptyBuffer();
    }
};
