const std = @import("std");
const common = @import("common.zig");
const Transform = @import("../physics/physics.zig").Transform;
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;
const Game = @import("../game.zig");
const MS2SEC = Game.MS2SEC;

const Emitter = @This();

const SHADERPARM_TIMEOFFSET: usize = 4;
const SHADERPARM_PARTICLE_STOPTIME: usize = 8; // don't spawn any more particles after this time

transform: Transform,
name: common.Name,
// used to present a model to the renderer
render_entity: RenderEntity,
model_def_handle: c_int = -1,

pub fn spawn(
    _: EntityHandle,
    _: std.mem.Allocator,
    spawn_args: SpawnArgs,
    c_dict_ptr: ?*anyopaque,
) !Emitter {
    var c_render_entity = RenderEntity{};
    if (c_dict_ptr) |ptr| {
        c_render_entity.initFromSpawnArgs(ptr);
    } else return error.CSpawnArgsIsUndefined;

    c_render_entity.shaderParms[SHADERPARM_PARTICLE_STOPTIME] = 0;
    c_render_entity.shaderParms[SHADERPARM_TIMEOFFSET] = -@as(f32, @floatFromInt(Game.instance.time)) * MS2SEC;

    const transform = .{
        .origin = c_render_entity.origin.toVec3f(),
    };

    return .{
        .transform = transform,
        .render_entity = c_render_entity,
        .name = spawn_args.get("name") orelse "unnamed_" ++ @typeName(@This()),
    };
}
