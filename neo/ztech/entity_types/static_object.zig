const std = @import("std");
const idlib = @import("../idlib.zig");
const common = @import("common.zig");
const Transform = @import("../physics/physics.zig").Transform;
const Physics = @import("../physics/physics.zig").Physics;
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const ClipModel = @import("../physics/clip_model.zig").ClipModel;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const PhysicsStatic = @import("../physics/static.zig");
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

const StaticObject = @This();

transform: Transform,
name: common.Name,
// used to present a model to the renderer
render_entity: RenderEntity,
model_def_handle: c_int = -1,
physics: Physics,
clip_model: ClipModel,

pub fn spawn(
    handle: EntityHandle,
    spawn_args: *const idlib.Dict,
    _: std.mem.Allocator,
) !StaticObject {
    var c_render_entity = RenderEntity{};
    c_render_entity.initFromSpawnArgs(spawn_args);

    var clip_model: ClipModel = if (spawn_args.getString("model")) |model_path|
        try ClipModel.fromModel(model_path)
    else
        return error.ClipModelIsUndefined;

    clip_model.origin = c_render_entity.origin;
    clip_model.externalEntityHandle = .{
        .type = @intFromEnum(handle.type),
        .id = handle.id,
    };

    const transform = .{
        .origin = c_render_entity.origin.toVec3f(),
    };

    return .{
        .transform = transform,
        .render_entity = c_render_entity,
        .name = spawn_args.getString("name") orelse "unnamed_" ++ @typeName(@This()),
        .physics = .{
            .static = PhysicsStatic.init(transform),
        },
        .clip_model = clip_model,
    };
}
