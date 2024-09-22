const std = @import("std");
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const RigidBody = @import("rigid_body.zig");
const Static = @import("static.zig");

pub const ImpactInfo = extern struct {
    invMass: f32 = 0.0,
    invInertiaTensor: CMat3 = .{},
    position: CVec3 = .{},
    velocity: CVec3 = .{},
};

pub const Transform = struct {
    origin: Vec3(f32) = .{},
    axis: Mat3(f32) = Mat3(f32).identity(),
};

pub const MassProperties = struct {
    mass: f32,
    center_of_mass: Vec3(f32),
    inertia_tensor: Mat3(f32),
};

pub const Physics = union(enum) {
    rigid_body: RigidBody,
    static: Static,

    pub fn component_init(self: *Physics) void {
        switch (self.*) {
            Physics.rigid_body => |*rigid_body| {
                rigid_body.initMassProperties();
                rigid_body.setMass(10.0);
            },
            else => {},
        }
    }

    pub fn getImpactInfo(self: Physics, point: Vec3(f32)) ImpactInfo {
        return switch (self) {
            Physics.rigid_body => |*rigid_body| rigid_body.getImpactInfo(point),
            else => std.mem.zeroes(ImpactInfo),
        };
    }

    pub fn getTransform(self: Physics) Transform {
        return switch (self) {
            Physics.rigid_body => |rigid_body| .{
                .origin = rigid_body.current.integration.position,
                .axis = rigid_body.current.integration.orientation,
            },
            Physics.static => |static| .{
                .origin = static.current.origin,
                .axis = static.current.axis,
            },
        };
    }
};
