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

        view.calculateRenderView();
    }
}
