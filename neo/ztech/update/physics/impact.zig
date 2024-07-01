const Physics = @import("../../physics/physics.zig").Physics;
const Impact = @import("../../types.zig").Impact;

pub const Query = struct {
    physics: Physics,
    impact: Impact,
};

pub fn update(list: anytype) void {
    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
        list_slice.items(.impact),
    ) |*physics, *impact| {
        if (!impact.apply) continue;

        switch (physics.*) {
            Physics.rigid_body => |*rigid_body| {
                rigid_body.applyImpulse(impact.point, impact.impulse);
                rigid_body.activate();
            },
            else => {},
        }

        impact.clear();
    }
}
