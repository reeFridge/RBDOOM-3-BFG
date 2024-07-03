const Physics = @import("../../physics/physics.zig").Physics;
const ImpactInfo = @import("../../physics/physics.zig").ImpactInfo;
const Game = @import("../../game.zig");
const Rotation = @import("../../math/rotation.zig");
const ClipModel = @import("../../physics/clip_model.zig").ClipModel;
const Impact = @import("../../types.zig").Impact;
const global = @import("../../global.zig");
const Vec3 = @import("../../math/vector.zig").Vec3;
const Capture = @import("../../entity.zig").Capture;

pub const Query = struct {
    physics: Physics,
    clip_model: ClipModel,
};

pub fn update(list: anytype) void {
    const time_state = Game.c_getTimeState();
    const delta_time_ms = time_state.delta();
    const dt = (@as(f32, @floatFromInt(delta_time_ms)) / 1000.0);

    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
        list_slice.items(.clip_model),
    ) |*physics, *clip_model| {
        const moved = switch (physics.*) {
            Physics.rigid_body => |*rigid_body| moved: {
                if (!rigid_body.willMove(delta_time_ms)) break :moved false;

                defer rigid_body.clearExternalForces();

                clip_model.unlink();
                var next_state = rigid_body.evaluate(delta_time_ms);

                // check for collisions from the current to the next state
                const opt_collision_result = rigid_body.checkForCollisions(
                    next_state.integration.position,
                    next_state.integration.orientation,
                    clip_model,
                );

                if (opt_collision_result) |collision_result| {
                    rigid_body.atMomentOfImpact(collision_result, &next_state);
                }

                // update current state
                rigid_body.current = next_state;

                const collision_result = opt_collision_result orelse break :moved true;
                const collision_point = collision_result.c.point.toVec3f();
                const opt_handle = if (collision_result.c.entityNum == -1)
                    global.Entities.EntityHandle.fromExtern(
                        collision_result.c.externalEntityHandle,
                    )
                else
                    null;

                const impact: ImpactInfo = if (opt_handle) |handle| impact: {
                    const query_result = global.entities.queryByHandle(
                        handle,
                        struct { physics: Capture.ref(Physics) },
                    ) orelse break :impact .{};

                    const physics_other = query_result.physics;

                    break :impact physics_other.getImpactInfo(collision_point);
                } else .{};

                const impulse = rigid_body.collisionImpulse(collision_result, impact);
                rigid_body.applyImpulse(collision_point, impulse);

                // if no movement at all don't blow up
                if (collision_result.fraction < 0.0001) {
                    rigid_body.scaleMomentum(0.5);
                }

                if (opt_handle) |handle| {
                    if (global.entities.queryByHandle(
                        handle,
                        struct { impact: Capture.ref(Impact) },
                    )) |query_result| {
                        const impact_other = query_result.impact;

                        impact_other.set(collision_point, impulse.scale(-1));
                    }
                }

                break :moved true;
            },
            Physics.static => |*static| moved: {
                var rotation = Rotation.create(
                    static.current.origin,
                    Vec3(f32){ .z = 1.0 },
                    45.0 * dt,
                );

                static.rotate(&rotation);

                break :moved true;
            },
        };

        if (!moved) continue;

        const transform = physics.getTransform();
        clip_model.linkUpdated(transform.origin, transform.axis);
    }
}
