const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const RenderView = @import("../renderer/render_world.zig").RenderView;

extern fn c_calculateRenderView(*RenderView, f32) void;

pub fn update(list: anytype) void {
    var list_slice = list.slice();
    for (
        list_slice.items(.transform),
        list_slice.items(.view),
        list_slice.items(.pvs_areas),
    ) |transform, *view, *pvs_areas| {
        pvs_areas.update(transform.origin);

        view.origin = transform.origin;
        view.axis = transform.axis;
    }

    for (
        list_slice.items(.view),
    ) |*view| {
        c_calculateRenderView(&view.render_view, view.fov);
        view.render_view.vieworg = CVec3.fromVec3f(view.origin);
        view.render_view.viewaxis = CMat3.fromMat3f(view.axis);
    }
}
