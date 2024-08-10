const RenderLight = @import("../renderer/render_light.zig").RenderLight;
const assertFields = @import("../entity.zig").assertFields;
const Transform = @import("../physics/physics.zig").Transform;
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;
const RenderWorld = @import("../renderer/render_world.zig");

pub fn fromTransform(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        transform: Transform,
        render_light: RenderLight,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.transform),
        list_slice.items(.render_light),
    ) |transform, *render_light| {
        render_light.axis = CMat3.fromMat3f(transform.axis);
        render_light.origin = CVec3.fromVec3f(transform.origin);
    }
}

pub fn present(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        light_def_handle: c_int,
        render_light: RenderLight,
    }, T)) return;

    var render_world = RenderWorld.instance();

    var list_slice = list.slice();
    for (
        list_slice.items(.render_light),
        list_slice.items(.light_def_handle),
    ) |*render_light, *light_def_handle| {
        // let the renderer apply it to the world
        if (light_def_handle.* == -1) {
            const light_index = render_world.addLightDef(render_light.*) catch @panic("Fail to addLightDef");
            light_def_handle.* = @intCast(light_index);
        } else {
            render_world.updateLightDef(@intCast(light_def_handle.*), render_light.*) catch @panic("Fail to updateLightDef");
        }
    }
}
