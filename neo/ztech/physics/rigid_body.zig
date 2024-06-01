const render_entity = @import("../render_entity.zig");
const CVec3 = render_entity.CVec3;
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const ClipModel = @import("clip_model.zig").ClipModel;
const TraceResult = @import("collision_model.zig").TraceResult;

const PhysicsRigidBody = @This();

pub const IntegrationState = struct {
    position: Vec3(f32) = .{},
    orientation: Mat3(f32) = Mat3(f32).identity(),
    linear_momentum: Vec3(f32) = .{},
    angular_momentum: Vec3(f32) = .{},
};

pub const State = struct {
    rest_start_time: i32 = -1,
    last_time_step: f32 = 0,
    local_origin: Vec3(f32) = .{},
    local_axis: Mat3(f32) = Mat3(f32).identity(),
    //push_velocity: Vec6(f32) = .{},
    external_force: Vec3(f32) = .{},
    external_torque: Vec3(f32) = .{},
    integration: IntegrationState = .{},
};

current: State = .{},
clip_model: ?ClipModel = null,
no_contact: bool = true, // TODO: implement !no_contact behaviour
center_of_mass: Vec3(f32) = .{},
mass: f32 = 1,
// TODO: g_gravity
gravity_vector: Vec3(f32) = .{ .x = 0, .y = 0, .z = -1 },
inverse_inertia_tensor: Mat3(f32) = Mat3(f32).identity(),
linear_friction: f32 = 0,
angular_friction: f32 = 0,
contact_friction: f32 = 0,

const MS2SEC: f32 = 0.001;

const Integrator = struct {
    const Derevatives = struct {
        linear_velocity: Vec3(f32),
        angular_matrix: Mat3(f32),
        force: Vec3(f32),
        torque: Vec3(f32),
    };

    const Parameters = struct {
        external_force: *const Vec3(f32),
        external_torque: *const Vec3(f32),
        inverse_inertia_tensor: *const Mat3(f32),
        linear_friction: f32,
        angular_friction: f32,
        inverse_mass: f32,
    };

    inline fn derive(params: Parameters, state: *const IntegrationState) Derevatives {
        const inverse_world_inertia_tensor: Mat3(f32) = state.orientation.multiply(&params.inverse_inertia_tensor.multiply(&state.orientation.transpose()));
        const angular_velocity: Vec3(f32) = inverse_world_inertia_tensor.multiplyVec3(&state.angular_momentum);

        return .{
            .linear_velocity = state.linear_momentum.scale(params.inverse_mass),
            .angular_matrix = Mat3(f32).skewSymmetric(&angular_velocity).multiply(&state.orientation),
            .force = state.linear_momentum.scale(-params.linear_friction).add(params.external_force),
            .torque = state.angular_momentum.scale(-params.angular_friction).add(params.external_torque),
        };
    }

    fn evaluate(params: Parameters, state: *const IntegrationState, next_state: *IntegrationState, delta_time: f32) void {
        const d = Integrator.derive(params, state);

        next_state.position = state.position.add(&d.linear_velocity.scale(delta_time));

        var next_axis = &next_state.orientation;
        next_axis.rows[0] = next_axis.rows[0].add(&d.angular_matrix.rows[0].scale(delta_time));
        next_axis.rows[1] = next_axis.rows[1].add(&d.angular_matrix.rows[1].scale(delta_time));
        next_axis.rows[2] = next_axis.rows[2].add(&d.angular_matrix.rows[2].scale(delta_time));

        next_state.linear_momentum = state.linear_momentum.add(&d.force.scale(delta_time));
        next_state.angular_momentum = state.angular_momentum.add(&d.torque.scale(delta_time));
    }
};

pub fn integrate(self: *PhysicsRigidBody, delta_time: f32, next_state: *State) void {
    var i = &self.current.integration;
    const position = i.position;

    i.position = i.position.add(&i.orientation.multiplyVec3(&self.center_of_mass));
    i.orientation = i.orientation.transpose();

    var i_next = &next_state.integration;

    Integrator.evaluate(
        .{
            .external_force = &self.current.external_force,
            .external_torque = &self.current.external_torque,
            .inverse_inertia_tensor = &self.inverse_inertia_tensor,
            .linear_friction = self.linear_friction,
            .angular_friction = self.angular_friction,
            .inverse_mass = 1.0 / self.mass,
        },
        i,
        i_next,
        delta_time,
    );

    i_next.orientation = i_next.orientation.orthoNormalize();

    // apply gravity
    i_next.linear_momentum = i_next.linear_momentum.add(&self.gravity_vector.scale(delta_time * self.mass));

    i.orientation = i.orientation.transpose();
    i_next.orientation = i_next.orientation.transpose();

    i.position = position;
    i_next.position = i_next.position.subtract(&i_next.orientation.multiplyVec3(&self.center_of_mass));

    next_state.rest_start_time = self.current.rest_start_time;
}

pub fn check_for_collisions(_: *PhysicsRigidBody, _: f32, _: *State, _: *TraceResult) bool {
    return false;
}

pub fn collision_impulse(_: *PhysicsRigidBody, _: *const TraceResult, _: *const Vec3(f32)) bool {
    return false;
}

pub fn evaluate(self: *PhysicsRigidBody, time_step_ms: i32) bool {
    const time_step = @as(f32, @floatFromInt(time_step_ms)) * MS2SEC;
    self.current.last_time_step = time_step;

    if (self.atRest() or time_step <= 0.0) {
        return false;
    }

    if (self.clip_model) |*clip_model| clip_model.unlink();

    var next_step = self.current;

    // calculate next position and orientation
    self.integrate(time_step, &next_step);

    // check for collisions from the current to the next state
    var collision_result: TraceResult = .{};
    const collided = self.check_for_collisions(time_step, &next_step, &collision_result);

    self.current = next_step;

    var impulse_vec: Vec3(f32) = .{};
    // apply collision impulse
    if (collided and self.collision_impulse(&collision_result, &impulse_vec)) {
        // TODO: set to = gameLocal.time
        self.current.rest_start_time = 1;
    }

    self.linkClipModel();

    if (!self.no_contact) {
        // self.evaluate_contacts();
        // if (self.testIfAtRest()) {
        // self.rest();
        // } else {
        // self.contact_friction(time_step);
        // }
    }

    if (!self.atRest()) {
        // self.activate_contact_entities();
    }

    if (collided) {
        // if (c_getEntity(collision_result.c.entityNum)) |ent| {
        // c_entityApplyImpulse(null, collision_result.c.id, collision_result.c.point, impulse.negate());
        // }
    }

    //self.current.push_velocity = .{};
    self.current.last_time_step = time_step;
    self.current.external_force = .{};
    self.current.external_torque = .{};

    return true;
}

pub inline fn atRest(self: *PhysicsRigidBody) bool {
    return self.current.rest_start_time >= 0;
}

pub fn rest(self: *PhysicsRigidBody) void {
    // TODO: set to = gameLocal.time
    self.current.rest_start_time = 1;
    self.current.integration.linear_momentum = .{};
    self.current.integration.angular_momentum = .{};
}

pub fn activate(self: *PhysicsRigidBody) void {
    self.rest_start_time = -1;
}

pub fn component_init(self: *PhysicsRigidBody) void {
    self.linkClipModel();
}

pub fn component_deinit(self: *PhysicsRigidBody) void {
    if (self.clip_model) |*clip_model| {
        clip_model.deinit();
    }
}

inline fn linkClipModel(self: *PhysicsRigidBody) void {
    if (self.clip_model) |*clip_model| {
        clip_model.linkWithNewTransform(
            clip_model.id,
            &self.current.integration.position,
            &self.current.integration.orientation,
        );
    }
}
