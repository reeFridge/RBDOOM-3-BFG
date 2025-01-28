const std = @import("std");
const common = @import("common.zig");
const idlib = @import("../idlib.zig");
const Transform = @import("../physics/physics.zig").Transform;
const RenderLight = @import("../renderer/render_light.zig").RenderLight;
const Vec3 = @import("../math/vector.zig").Vec3;
const Mat3 = @import("../math/matrix.zig").Mat3;
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

const Light = @This();

transform: Transform,
light_def_handle: c_int = -1,
render_light: RenderLight,

pub fn spawn(
    _: EntityHandle,
    spawn_args: *const idlib.Dict,
    allocator: std.mem.Allocator,
) !Light {
    var render_light = RenderLight{};
    try render_light.initFromSpawnArgs(spawn_args, allocator);

    const origin = if (spawn_args.getString("origin")) |origin_str|
        try common.parseVec3f(origin_str)
    else
        Vec3(f32){};

    const rotation = if (spawn_args.getString("rotation")) |rotation_str|
        try common.parseMat3f(rotation_str)
    else
        Mat3(f32).identity();

    return .{
        .transform = .{ .origin = origin, .axis = rotation },
        .render_light = render_light,
    };
}
