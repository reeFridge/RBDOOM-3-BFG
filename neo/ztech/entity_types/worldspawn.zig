const std = @import("std");
const Vec3 = @import("../math/vector.zig").Vec3;
const common = @import("common.zig");
const Transform = @import("../physics/physics.zig").Transform;
const EntityHandle = global.Entities.EntityHandle;
const global = @import("../global.zig");
const idlib = @import("../idlib.zig");

const Worldspawn = @This();

transform: Transform,
name: common.Name,

pub fn spawn(
    _: EntityHandle,
    spawn_args: *const idlib.Dict,
    _: std.mem.Allocator,
) !Worldspawn {
    const origin = try common.parseVec3f(spawn_args.getString("origin") orelse "0 0 0");

    return .{
        .transform = .{ .origin = origin },
        .name = spawn_args.getString("name") orelse "unnamed_" ++ @typeName(@This()),
    };
}
