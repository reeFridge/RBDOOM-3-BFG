const SpawnArgs = @import("entity.zig").SpawnArgs;
const render_entity = @import("renderer/render_entity.zig");
const ClipModel = @import("physics/clip_model.zig").ClipModel;
const Physics = @import("physics/physics.zig").Physics;
const TraceModel = @import("physics/trace_model.zig").TraceModel;
const c_initTraceModelFromModel = @import("physics/trace_model.zig").c_initTraceModelFromModel;

extern fn c_parse_spawn_args_to_render_entity(*anyopaque, *render_entity.CRenderEntity) callconv(.C) void;

const Name = []const u8;

pub const StaticObject = struct {
    name: Name,
    // used to present a model to the renderer
    render_entity: render_entity.CRenderEntity,
    model_def_handle: c_int = -1,
    physics: Physics,

    pub fn spawn(spawn_args: *const SpawnArgs, c_dict_ptr: ?*anyopaque) !StaticObject {
        var c_render_entity = render_entity.CRenderEntity{};
        if (c_dict_ptr) |ptr| {
            c_parse_spawn_args_to_render_entity(ptr, &c_render_entity);
        }

        var clip_model_local: ?ClipModel = null;
        if (spawn_args.get("model")) |model_path| {
            clip_model_local = ClipModel.fromModel(model_path);
        }

        return .{
            .render_entity = c_render_entity,
            .name = spawn_args.get("name") orelse "unnamed_" ++ @typeName(@This()),
            .physics = .{
                .static = .{
                    .current = .{ .origin = c_render_entity.origin.toVec3f() },
                    .clip_model = clip_model_local,
                },
            },
        };
    }
};

pub const MoveableObject = struct {
    name: Name,
    // used to present a model to the renderer
    render_entity: render_entity.CRenderEntity,
    model_def_handle: c_int = -1,
    physics: Physics,

    pub fn spawn(spawn_args: *const SpawnArgs, c_dict_ptr: ?*anyopaque) !MoveableObject {
        var c_render_entity = render_entity.CRenderEntity{};
        if (c_dict_ptr) |ptr| {
            c_parse_spawn_args_to_render_entity(ptr, &c_render_entity);
        }

        var clip_model_local: ?ClipModel = null;
        if (spawn_args.get("model")) |model_path| {
            // TODO: Why it is printed? WARNING: idClipModel::FreeTraceModel: tried to free uncached trace model
            if (TraceModel.fromModel(model_path)) |trace_model| {
                var clip_model = ClipModel.fromTraceModel(&trace_model);
                clip_model.contents = 1; // CONTENTS_SOLID
                clip_model_local = clip_model;
            }
        }

        return .{
            .render_entity = c_render_entity,
            .name = spawn_args.get("name") orelse "unnamed_" ++ @typeName(@This()),
            .physics = .{
                .rigid_body = .{
                    .current = .{ .integration = .{ .position = c_render_entity.origin.toVec3f() } },
                    .clip_model = clip_model_local,
                    .content_mask = -1, // MASK_ALL
                },
            },
        };
    }
};

pub const ExportedTypes = .{ StaticObject, MoveableObject };
