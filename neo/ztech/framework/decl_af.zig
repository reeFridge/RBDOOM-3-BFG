const std = @import("std");
const Decl = @import("decl_manager.zig").Decl;
const idlib = @import("../idlib.zig");
const CVec2 = @import("../math/vector.zig").CVec2;
const CVec3 = @import("../math/vector.zig").CVec3;
const CAngles = @import("../math/angles.zig").CAngles;
const CMat3 = @import("../math/matrix.zig").CMat3;
const ContentFlags = @import("../renderer/material.zig").ContentFlags;

const AFVector = extern struct {
    pub const Type = enum(c_int) {
        VEC_COORDS = 0,
        VEC_JOINT,
        VEC_BONECENTER,
        VEC_BONEDIR,
    };

    type: Type,
    joint1: idlib.idStr,
    joint2: idlib.idStr,
    vec: CVec3,
    negate: bool,
};

const AFJointMod = enum(c_int) {
    AXIS,
    ORIGIN,
    BOTH,
};

const Body = extern struct {
    name: idlib.idStr,
    jointName: idlib.idStr,
    jointMod: AFJointMod,
    modelType: c_int,
    v1: AFVector,
    v2: AFVector,
    numSides: c_int,
    width: f32,
    density: f32,
    origin: AFVector,
    angles: CAngles,
    contents: c_int,
    clipMask: c_int,
    selfCollision: bool,
    inertiaScale: CMat3,
    linearFriction: f32,
    angularFriction: f32,
    contactFriction: f32,
    containedJoints: idlib.idStr,
    frictionDirection: AFVector,
    contactMotorDirection: AFVector,
};

const Constraint = extern struct {
    pub const Type = enum(c_int) {
        INVALID,
        FIXED,
        BALLANDSOCKETJOINT,
        UNIVERSALJOINT,
        HINGE,
        SLIDER,
        SPRING,
    };

    pub const Limit = enum(c_int) {
        NONE = -1,
        CONE,
        PYRAMID,
    };

    name: idlib.idStr,
    body1: idlib.idStr,
    body2: idlib.idStr,
    type: Type,
    friction: f32,
    stretch: f32,
    compress: f32,
    damping: f32,
    restLength: f32,
    minLength: f32,
    maxLength: f32,
    anchor: AFVector,
    anchor2: AFVector,
    shaft: [2]AFVector,
    axis: AFVector,
    limit: Limit,
    limitAxis: AFVector,
    limitAngles: [3]f32,
};

pub const DeclAF = extern struct {
    base: Decl = .{},
    modified: bool = false,
    model: idlib.idStr = .{},
    skin: idlib.idStr = .{},
    defaultLinearFriction: f32 = 0.01,
    defaultAngularFriction: f32 = 0.01,
    defaultContactFriction: f32 = 0.8,
    defaultConstraintFriction: f32 = 0.5,
    totalMass: f32 = -1,
    suspendVelocity: CVec2 = .{ .x = 20, .y = 30 },
    suspendAcceleration: CVec2 = .{ .x = 40, .y = 60 },
    noMoveTime: f32 = 1,
    noMoveTranslation: f32 = 10,
    noMoveRotation: f32 = 10,
    minMoveTime: f32 = -1,
    maxMoveTime: f32 = -1,
    contents: ContentFlags = .{ .corpse = true },
    clipMask: ContentFlags = .{ .solid = true },
    selfCollision: bool = true,
    bodies: idlib.idList(*Body) = .{},
    constraints: idlib.idList(*Constraint) = .{},

    pub fn init(self: *DeclAF) void {
        self.* = .{};
        self.model.initEmptyBuffer();
        self.skin.initEmptyBuffer();
    }
};
