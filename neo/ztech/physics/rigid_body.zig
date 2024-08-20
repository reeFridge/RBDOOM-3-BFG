const std = @import("std");
const Vec3 = @import("../math/vector.zig").Vec3;
const Vec6 = @import("../math/vector.zig").Vec6;
const Mat3 = @import("../math/matrix.zig").Mat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const Rotation = @import("../math/rotation.zig");
const ClipModel = @import("clip_model.zig").ClipModel;
const TraceResult = @import("collision_model.zig").TraceResult;
const ContactInfo = @import("collision_model.zig").ContactInfo;
const Clip = @import("clip.zig");
const Game = @import("../game.zig");
const global = @import("../global.zig");
const ImpactInfo = @import("physics.zig").ImpactInfo;
const Transform = @import("physics.zig").Transform;
const MassProperties = @import("physics.zig").MassProperties;

const STOP_SPEED: f32 = 10.0;

const PhysicsRigidBody = @This();

pub const IntegrationState = struct {
    position: Vec3(f32) = .{},
    orientation: Mat3(f32) = Mat3(f32).identity(),
    linear_momentum: Vec3(f32) = .{},
    angular_momentum: Vec3(f32) = .{},
};

pub const State = struct {
    rest_start_time: usize = 0,
    rest: bool = false,
    last_time_step: f32 = 0,
    local_origin: Vec3(f32) = .{},
    local_axis: Mat3(f32) = Mat3(f32).identity(),
    //push_velocity: Vec6(f32) = .{},
    external_force: Vec3(f32) = .{},
    external_torque: Vec3(f32) = .{},
    integration: IntegrationState = .{},
};

current: State = .{},
center_of_mass: Vec3(f32) = .{},
mass: f32 = 1,
inverse_mass: f32 = 1,
bouncyness: f32 = 0.6,
gravity_vector: Vec3(f32) = .{ .v = .{ 0, 0, -global.gravity } },
inertia_tensor: Mat3(f32) = Mat3(f32).identity(),
inverse_inertia_tensor: Mat3(f32) = Mat3(f32).identity(),
linear_friction: f32 = 0.6,
angular_friction: f32 = 0.6,
contact_friction: f32 = 0.05,
// contents the physics object collides with
content_mask: i32 = -1, // MASK_ALL

pub fn init(transform: Transform, mass_props: MassProperties) PhysicsRigidBody {
    return .{
        .mass = mass_props.mass,
        .center_of_mass = mass_props.center_of_mass,
        .inertia_tensor = mass_props.inertia_tensor,
        .current = .{
            .integration = .{
                .position = transform.origin,
                .orientation = transform.axis,
            },
        },
    };
}

const MS2SEC: f32 = 0.001;

const Integrator = struct {
    const Derevatives = struct {
        linear_velocity: Vec3(f32),
        angular_matrix: Mat3(f32),
        force: Vec3(f32),
        torque: Vec3(f32),
    };

    const Parameters = struct {
        external_force: Vec3(f32),
        external_torque: Vec3(f32),
        inverse_inertia_tensor: Mat3(f32),
        linear_friction: f32,
        angular_friction: f32,
        inverse_mass: f32,
    };

    inline fn derive(params: Parameters, state: IntegrationState) Derevatives {
        const inverse_world_inertia_tensor = state.orientation.multiply(
            params.inverse_inertia_tensor.multiply(
                state.orientation.transpose(),
            ),
        );
        const angular_velocity = inverse_world_inertia_tensor.multiplyVec3(state.angular_momentum);

        return .{
            .linear_velocity = state.linear_momentum.scale(params.inverse_mass),
            .angular_matrix = Mat3(f32).skewSymmetric(angular_velocity).multiply(state.orientation),
            .force = state.linear_momentum.scale(-params.linear_friction).add(params.external_force),
            .torque = state.angular_momentum.scale(-params.angular_friction).add(params.external_torque),
        };
    }

    fn evaluate(params: Parameters, state: IntegrationState, next_state: *IntegrationState, delta_time: f32) void {
        const d = Integrator.derive(params, state);

        next_state.position = state.position.add(d.linear_velocity.scale(delta_time));

        for (&next_state.orientation.v, 0..) |*v, i| {
            v.* = state.orientation.v[i].add(d.angular_matrix.v[i].scale(delta_time));
        }

        next_state.linear_momentum = state.linear_momentum.add(d.force.scale(delta_time));
        next_state.angular_momentum = state.angular_momentum.add(d.torque.scale(delta_time));
    }
};

pub fn integrate(self: *PhysicsRigidBody, delta_time: f32, next_state: *State) void {
    var i = &self.current.integration;
    const position = i.position;

    i.position = i.position.add(i.orientation.multiplyVec3(self.center_of_mass));
    i.orientation = i.orientation.transpose();

    var i_next = &next_state.integration;

    Integrator.evaluate(
        .{
            .external_force = self.current.external_force,
            .external_torque = self.current.external_torque,
            .inverse_inertia_tensor = self.inverse_inertia_tensor,
            .linear_friction = self.linear_friction,
            .angular_friction = self.angular_friction,
            .inverse_mass = self.inverse_mass,
        },
        i.*,
        i_next,
        delta_time,
    );

    i_next.orientation = i_next.orientation.orthoNormalize();

    // apply gravity
    i_next.linear_momentum = i_next.linear_momentum.add(self.gravity_vector.scale(delta_time * self.mass));

    i.orientation = i.orientation.transpose();
    i_next.orientation = i_next.orientation.transpose();

    i.position = position;
    i_next.position = i_next.position.subtract(i_next.orientation.multiplyVec3(self.center_of_mass));

    next_state.rest_start_time = self.current.rest_start_time;
    next_state.rest = self.current.rest;
}

extern fn c_balanceInertiaTensor(*CMat3) callconv(.C) void;

pub fn initMassProperties(self: *PhysicsRigidBody) void {
    if (self.mass <= 0.0 or std.math.isNan(self.mass)) {
        self.mass = 1.0;
        self.center_of_mass = .{};
        self.inertia_tensor = Mat3(f32).identity();
    }

    var c = CMat3.fromMat3f(self.inertia_tensor);
    c_balanceInertiaTensor(&c);
    self.inertia_tensor = c.toMat3f();

    self.inverse_inertia_tensor = self.inertia_tensor.inverse().multiplyScalar(1.0 / 6.0);
    self.inverse_mass = 1.0 / self.mass;

    self.current.integration.linear_momentum = .{};
    self.current.integration.angular_momentum = .{};
}

pub fn setMass(self: *PhysicsRigidBody, mass: f32) void {
    self.inertia_tensor = self.inertia_tensor.multiplyScalar(mass / self.mass);
    self.inverse_inertia_tensor = self.inertia_tensor.inverse().multiplyScalar(1.0 / 6.0);
    self.mass = mass;
    self.inverse_mass = 1.0 / self.mass;
}

pub fn checkForCollisions(
    self: *PhysicsRigidBody,
    next_position: Vec3(f32),
    next_orientation: Mat3(f32),
    clip_model: *const ClipModel,
) ?TraceResult {
    const i = &self.current.integration;

    const axis: Mat3(f32) = axis: {
        var mat = Mat3(f32).identity();
        Mat3(f32).transposeMultiply(i.orientation, next_orientation, &mat);
        break :axis mat;
    };
    const rotation: Rotation = rot: {
        var rot = axis.toRotation();
        rot.origin = i.position;
        break :rot rot;
    };

    var result: TraceResult = .{};
    // if there was a collision
    return if (Clip.motion(
        &result,
        i.position,
        next_position,
        rotation,
        clip_model,
        i.orientation,
        self.content_mask,
    )) result else null;
}

inline fn linearVelocity(self: PhysicsRigidBody) Vec3(f32) {
    return self.current.integration.linear_momentum.scale(1.0 / self.mass);
}

inline fn velocityAtPosition(
    self: PhysicsRigidBody,
    inverse_world_inertia_tensor: Mat3(f32),
    position: Vec3(f32),
) Vec3(f32) {
    return self.linearVelocity().add(
        self.angularVelocity(inverse_world_inertia_tensor)
            .cross(position),
    );
}

inline fn inverseWorldInertiaTensor(self: *const PhysicsRigidBody) Mat3(f32) {
    const i: *const IntegrationState = &self.current.integration;

    return i.orientation.multiply(
        self.inverse_inertia_tensor.multiply(
            i.orientation.transpose(),
        ),
    );
}

inline fn relativeCollisionPoint(self: PhysicsRigidBody, point: Vec3(f32)) Vec3(f32) {
    const i: *const IntegrationState = &self.current.integration;

    return point.subtract(
        i.position.add(
            i.orientation.multiplyVec3(self.center_of_mass),
        ),
    );
}

inline fn angularVelocity(
    self: PhysicsRigidBody,
    inverse_world_inertia_tensor: Mat3(f32),
) Vec3(f32) {
    return inverse_world_inertia_tensor
        .multiplyVec3(self.current.integration.angular_momentum);
}

pub fn getImpactInfo(self: PhysicsRigidBody, point: Vec3(f32)) ImpactInfo {
    const inverse_world_inertia_tensor = self.inverseWorldInertiaTensor();
    const position = self.relativeCollisionPoint(point);

    return .{
        .invMass = 1.0 / self.mass,
        .invInertiaTensor = CMat3.fromMat3f(inverse_world_inertia_tensor),
        .position = CVec3.fromVec3f(position),
        .velocity = CVec3.fromVec3f(
            self.velocityAtPosition(inverse_world_inertia_tensor, position),
        ),
    };
}

pub fn willMove(self: *PhysicsRigidBody, time_step_ms: usize) bool {
    const time_step = @as(f32, @floatFromInt(time_step_ms)) * MS2SEC;

    return !self.atRest() and time_step > 0.0;
}

pub fn atMomentOfImpact(self: PhysicsRigidBody, collision_result: TraceResult, next_state: *State) void {
    var next_i = &next_state.integration;
    next_i.position = collision_result.endpos.toVec3f();
    next_i.orientation = collision_result.endAxis.toMat3f();
    next_i.linear_momentum = self.current.integration.linear_momentum;
    next_i.angular_momentum = self.current.integration.angular_momentum;
}

pub fn collisionImpulse(self: *PhysicsRigidBody, collision: TraceResult, impact: ImpactInfo) Vec3(f32) {
    const inverse_world_inertia_tensor = self.inverseWorldInertiaTensor();
    const r = self.relativeCollisionPoint(collision.c.point.toVec3f());
    const velocity = self.velocityAtPosition(inverse_world_inertia_tensor, r)
        .subtract(impact.velocity.toVec3f());
    const normal_velocity = velocity.dot(collision.c.normal.toVec3f());
    const numerator = if (normal_velocity > -STOP_SPEED)
        STOP_SPEED
    else
        (-1.0 + self.bouncyness) * normal_velocity;

    const a = inverse_world_inertia_tensor.multiplyVec3(
        r.cross(collision.c.normal.toVec3f()),
    ).cross(
        r,
    );
    var denominator = self.inverse_mass + a.dot(collision.c.normal.toVec3f());
    if (impact.invMass != 0.0) {
        const b = impact.invInertiaTensor.toMat3f().multiplyVec3(
            impact.position.toVec3f().cross(collision.c.normal.toVec3f()),
        ).cross(
            impact.position.toVec3f(),
        );

        denominator += impact.invMass + b.dot(collision.c.normal.toVec3f());
    }

    return collision.c.normal.toVec3f().scale(numerator / denominator);
}

pub fn applyImpulse(self: *PhysicsRigidBody, point: Vec3(f32), impulse: Vec3(f32)) void {
    const i: *IntegrationState = &self.current.integration;

    i.linear_momentum = i.linear_momentum.add(impulse);
    i.angular_momentum = i.angular_momentum.add(
        self.relativeCollisionPoint(point).cross(impulse),
    );
}

pub fn scaleMomentum(self: *PhysicsRigidBody, factor: f32) void {
    const i: *IntegrationState = &self.current.integration;

    i.linear_momentum = i.linear_momentum.scale(factor);
    i.angular_momentum = i.angular_momentum.scale(factor);
}

pub fn evaluateContacts(
    self: *PhysicsRigidBody,
    contacts: *std.ArrayList(ContactInfo),
    clip_model: *const ClipModel,
) !void {
    try contacts.resize(10);
    const i = &self.current.integration;

    const direction = .{
        .v = std.simd.join(
            i.linear_momentum.add(
                self.gravity_vector
                    .scale(self.current.last_time_step)
                    .scale(self.mass),
            ).normalize().v,
            i.angular_momentum.normalize().v,
        ),
    };

    const CONTACT_EPSILON = 0.25;

    const contacts_count = Clip.contacts(
        contacts.items.ptr,
        10,
        clip_model.origin.toVec3f(),
        direction,
        CONTACT_EPSILON,
        clip_model,
        clip_model.axis.toMat3f(),
        self.content_mask,
    );

    contacts.resize(contacts_count) catch unreachable;
}

extern fn c_testIfAtRest(
    [*]const ContactInfo,
    usize,
    CVec3,
    CVec3,
    CMat3,
    CVec3,
    CVec3,
    CVec3,
    CMat3,
    f32,
) callconv(.C) bool;

pub fn testIfAtRest(self: PhysicsRigidBody, contacts: []const ContactInfo) bool {
    if (self.atRest()) return true;

    // need at least 3 contact points to come to rest
    if (contacts.len < 3) return false;

    return c_testIfAtRest(
        contacts.ptr,
        contacts.len,
        CVec3.fromVec3f(self.gravity_vector.normalize()),
        CVec3.fromVec3f(self.current.integration.position),
        CMat3.fromMat3f(self.current.integration.orientation),
        CVec3.fromVec3f(self.current.integration.linear_momentum),
        CVec3.fromVec3f(self.current.integration.angular_momentum),
        CVec3.fromVec3f(self.center_of_mass),
        CMat3.fromMat3f(self.inverse_inertia_tensor),
        self.inverse_mass,
    );
}

pub fn contactFriction(
    self: *PhysicsRigidBody,
    contacts: []ContactInfo,
) void {
    const i: *IntegrationState = &self.current.integration;
    const inverse_world_inertia_tensor = self.inverseWorldInertiaTensor();
    const mass_center = i.position.add(
        i.orientation.multiplyVec3(self.center_of_mass),
    );

    for (contacts) |contact| {
        const r = contact.point.toVec3f().subtract(mass_center);
        const velocity = self.velocityAtPosition(
            inverse_world_inertia_tensor,
            r,
        );
        const normal_velocity = contact.normal.toVec3f().scale(
            velocity.dot(contact.normal.toVec3f()),
        );
        var normal, const magnitude = velocity.subtract(normal_velocity)
            .scale(-1)
            .normalizeLen();

        var numerator = self.contact_friction * magnitude;
        const a = inverse_world_inertia_tensor.multiplyVec3(
            r.cross(normal),
        ).cross(
            r,
        );
        var denominator = self.inverse_mass + a.dot(normal);
        var impulse = normal.scale(numerator / denominator);

        // apply friction impulse
        i.linear_momentum = i.linear_momentum.add(impulse);
        i.angular_momentum = i.angular_momentum.add(r.cross(impulse));

        // if moving towards the surface at the contact point
        if (normal_velocity.dot(contact.normal.toVec3f()) < 0.0) {
            normal, numerator = normal_velocity.scale(-1).normalizeLen();
            const b = inverse_world_inertia_tensor.multiplyVec3(
                r.cross(normal),
            ).cross(
                r,
            );
            denominator = self.inverse_mass + b.dot(normal);
            impulse = normal.scale(numerator / denominator);

            // apply impulse
            i.linear_momentum = i.linear_momentum.add(impulse);
            i.angular_momentum = i.angular_momentum.add(r.cross(impulse));
        }
    }
}

pub fn activateContactEntities(_: *PhysicsRigidBody) void {}

pub fn evaluate(self: *PhysicsRigidBody, time_step_ms: usize) State {
    const time_step = @as(f32, @floatFromInt(time_step_ms)) * MS2SEC;
    self.current.last_time_step = time_step;

    var next_state = self.current;
    // calculate next position and orientation
    self.integrate(time_step, &next_state);

    return next_state;
}

pub inline fn clearExternalForces(self: *PhysicsRigidBody) void {
    //self.current.push_velocity = .{};
    self.current.external_force = .{};
    self.current.external_torque = .{};
}

pub inline fn atRest(self: PhysicsRigidBody) bool {
    return self.current.rest;
}

pub fn rest(self: *PhysicsRigidBody) void {
    self.current.rest_start_time = Game.instance.time;
    self.current.rest = true;
    self.current.integration.linear_momentum = .{};
    self.current.integration.angular_momentum = .{};
}

pub fn activate(self: *PhysicsRigidBody) void {
    self.current.rest_start_time = 0;
    self.current.rest = false;
}
