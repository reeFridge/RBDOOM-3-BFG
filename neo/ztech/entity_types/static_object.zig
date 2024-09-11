const std = @import("std");
const common = @import("common.zig");
const Transform = @import("../physics/physics.zig").Transform;
const Physics = @import("../physics/physics.zig").Physics;
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const ClipModel = @import("../physics/clip_model.zig").ClipModel;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const PhysicsStatic = @import("../physics/static.zig");

const StaticObject = @This();

transform: Transform,
name: common.Name,
// used to present a model to the renderer
render_entity: RenderEntity,
model_def_handle: c_int = -1,
physics: Physics,
clip_model: ClipModel,

pub fn spawn(_: std.mem.Allocator, spawn_args: SpawnArgs, c_dict_ptr: ?*anyopaque) !StaticObject {
    var c_render_entity = RenderEntity{};
    if (c_dict_ptr) |ptr| {
        c_render_entity.initFromSpawnArgs(ptr);
    } else return error.CSpawnArgsIsUndefined;

    var clip_model: ClipModel = if (spawn_args.get("model")) |model_path|
        try ClipModel.fromModel(model_path)
    else
        return error.ClipModelIsUndefined;

    clip_model.origin = c_render_entity.origin;

    const transform = .{
        .origin = c_render_entity.origin.toVec3f(),
    };

    return .{
        .transform = transform,
        .render_entity = c_render_entity,
        .name = spawn_args.get("name") orelse "unnamed_" ++ @typeName(@This()),
        .physics = .{
            .static = PhysicsStatic.init(transform),
        },
        .clip_model = clip_model,
    };
}
