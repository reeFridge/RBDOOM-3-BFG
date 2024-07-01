const render_entity = @import("../renderer/render_entity.zig");
const assertFields = @import("../entity.zig").assertFields;
const Physics = @import("../physics/physics.zig").Physics;
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;

extern fn c_add_entity_def(*const render_entity.CRenderEntity) callconv(.C) c_int;
extern fn c_update_entity_def(c_int, *const render_entity.CRenderEntity) callconv(.C) void;

pub fn fromPhysics(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        physics: Physics,
        render_entity: render_entity.CRenderEntity,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
        list_slice.items(.render_entity),
    ) |physics, *render_entity_ptr| {
        const transform = physics.getTransform();
        render_entity_ptr.axis = CMat3.fromMat3f(transform.axis);
        render_entity_ptr.origin = CVec3.fromVec3f(transform.origin);
    }
}

pub fn present(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        model_def_handle: c_int,
        render_entity: render_entity.CRenderEntity,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.render_entity),
        list_slice.items(.model_def_handle),
    ) |*render_entity_ptr, *model_def_handle| {
        if (render_entity_ptr.hModel == null) continue;

        // add to refresh list
        if (model_def_handle.* == -1) {
            model_def_handle.* = c_add_entity_def(render_entity_ptr);
        } else {
            c_update_entity_def(model_def_handle.*, render_entity_ptr);
        }
    }
}
