const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const RigidBody = @import("rigid_body.zig");
const Static = @import("static.zig");

pub const Transform = struct {
    origin: Vec3(f32),
    axis: Mat3(f32),
};

pub const Physics = union(enum) {
    rigid_body: RigidBody,
    static: Static,

    pub fn getTransform(self: *Physics) Transform {
        return switch (self.*) {
            Physics.rigid_body => |rigid_body| .{
                .origin = rigid_body.current.integration.position,
                .axis = rigid_body.current.integration.orientation,
            },
            Physics.static => |static| .{
                .origin = static.current.origin,
                .axis = static.current.axis,
            },
        };
    }

    pub fn component_init(self: *Physics) void {
        switch (self.*) {
            Physics.rigid_body => |*rigid_body| rigid_body.component_init(),
            Physics.static => |*static| static.component_init(),
        }
    }

    pub fn component_deinit(self: *Physics) void {
        switch (self.*) {
            Physics.rigid_body => |*rigid_body| rigid_body.component_deinit(),
            Physics.static => |*static| static.component_deinit(),
        }
    }
};
