const Physics = @import("../../physics/physics.zig").Physics;
const Transform = @import("../../physics/physics.zig").Transform;

pub const Query = struct {
    physics: Physics,
    transform: Transform,
};

pub fn update(list: anytype) void {
    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
        list_slice.items(.transform),
    ) |*physics, *transform| {
        transform.* = physics.getTransform();
    }
}
