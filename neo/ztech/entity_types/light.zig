const std = @import("std");
const common = @import("common.zig");
const SpawnArgs = @import("../entity.zig").SpawnArgs;
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
    _: std.mem.Allocator,
    spawn_args: SpawnArgs,
    c_dict_ptr: ?*anyopaque,
) !Light {
    var c_render_light = std.mem.zeroes(RenderLight);
    if (c_dict_ptr) |ptr| {
        c_render_light.initFromSpawnArgs(ptr);
    } else return error.CSpawnArgsIsUndefined;

    const origin = if (spawn_args.get("origin")) |origin_str|
        common.c_parseVector(origin_str.ptr).toVec3f()
    else
        Vec3(f32){};

    const rotation = if (spawn_args.get("rotation")) |rotation_str|
        common.c_parseMatrix(rotation_str.ptr).toMat3f()
    else
        Mat3(f32).identity();

    return .{
        .transform = .{ .origin = origin, .axis = rotation },
        .render_light = c_render_light,
    };
}
