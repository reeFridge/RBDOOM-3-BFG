const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const assertFields = @import("../entity.zig").assertFields;
const Transform = @import("../physics/physics.zig").Transform;
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const RenderWorld = @import("../renderer/render_world.zig");

pub fn fromTransform(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        transform: Transform,
        render_entity: RenderEntity,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.transform),
        list_slice.items(.render_entity),
    ) |transform, *render_entity| {
        render_entity.axis = CMat3.fromMat3f(transform.axis);
        render_entity.origin = CVec3.fromVec3f(transform.origin);
    }
}

pub fn present(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        model_def_handle: c_int,
        render_entity: RenderEntity,
    }, T)) return;

    var render_world = RenderWorld.instance();

    var list_slice = list.slice();
    for (
        list_slice.items(.render_entity),
        list_slice.items(.model_def_handle),
    ) |*render_entity, *model_def_handle| {
        if (render_entity.hModel == null) continue;

        // add to refresh list
        if (model_def_handle.* == -1) {
            const entity_index = render_world.addEntityDef(render_entity.*) catch @panic("Fail to addEntityDef");
            model_def_handle.* = @intCast(entity_index);
        } else {
            render_world.updateEntityDef(@intCast(model_def_handle.*), render_entity.*) catch @panic("Fail to updateEntityDef");
        }
    }
}
