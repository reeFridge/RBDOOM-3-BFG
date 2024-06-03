const render_entity = @import("renderer/render_entity.zig");
const assertFields = @import("entity.zig").assertFields;
const Physics = @import("physics/physics.zig").Physics;
const Game = @import("game.zig");
const Rotation = @import("math/rotation.zig");
const CMat3 = @import("math/matrix.zig").CMat3;
const CVec3 = @import("math/vector.zig").CVec3;
const Vec3 = @import("math/vector.zig").Vec3;

extern fn c_add_entity_def(*const render_entity.CRenderEntity) callconv(.C) c_int;
extern fn c_update_entity_def(c_int, *const render_entity.CRenderEntity) callconv(.C) void;

pub fn updatePhysics(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        physics: Physics,
    }, T)) return;

    const time_state = Game.c_getTimeState();
    const delta_time_ms = time_state.delta();
    const dt = (@as(f32, @floatFromInt(delta_time_ms)) / 1000.0);

    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
    ) |*physics| {
        switch (physics.*) {
            Physics.rigid_body => |*rigid_body| _ = rigid_body.evaluate(delta_time_ms),
            Physics.static => |*static| {
                var rotation = Rotation.create(
                    static.current.origin,
                    Vec3(f32){ .z = 1.0 },
                    45.0 * dt,
                );

                static.rotate(&rotation);
            },
        }
    }
}

pub fn updateRenderEntityFromPhysics(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        physics: Physics,
        render_entity: render_entity.CRenderEntity,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
        list_slice.items(.render_entity),
    ) |
        *physics,
        *render_entity_ptr,
    | {
        const transform = physics.getTransform();
        render_entity_ptr.axis = CMat3.fromMat3f(&transform.axis);
        render_entity_ptr.origin = CVec3.fromVec3f(&transform.origin);
    }
}

pub fn presentRenderEntity(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        model_def_handle: c_int,
        render_entity: render_entity.CRenderEntity,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.render_entity),
        list_slice.items(.model_def_handle),
    ) |
        *render_entity_ptr,
        *model_def_handle,
    | {
        if (render_entity_ptr.hModel == null) continue;

        // add to refresh list
        if (model_def_handle.* == -1) {
            model_def_handle.* = c_add_entity_def(render_entity_ptr);
        } else {
            c_update_entity_def(model_def_handle.*, render_entity_ptr);
        }
    }
}
