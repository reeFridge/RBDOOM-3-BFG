const RenderLight = @import("../renderer/render_world.zig").RenderLight;
const assertFields = @import("../entity.zig").assertFields;
const Transform = @import("../physics/physics.zig").Transform;
const CMat3 = @import("../math/matrix.zig").CMat3;
const CVec3 = @import("../math/vector.zig").CVec3;

extern fn c_addLightDef(*const RenderLight) callconv(.C) c_int;
extern fn c_updateLightDef(c_int, *const RenderLight) callconv(.C) void;

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

    var list_slice = list.slice();
    for (
        list_slice.items(.render_light),
        list_slice.items(.light_def_handle),
    ) |*render_light, *light_def_handle| {
        // let the renderer apply it to the world
        if (light_def_handle.* == -1) {
            light_def_handle.* = c_addLightDef(render_light);
        } else {
            c_updateLightDef(light_def_handle.*, render_light);
        }
    }
}
