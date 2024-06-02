const SpawnArgs = @import("entity.zig").SpawnArgs;
const assertFields = @import("entity.zig").assertFields;
const std = @import("std");
const render_entity = @import("renderer/render_entity.zig");
const CMat3 = @import("math/matrix.zig").CMat3;
const CVec3 = @import("math/vector.zig").CVec3;
const Vec3 = @import("math/vector.zig").Vec3;
const Rotation = @import("math/rotation.zig");
const ClipModel = @import("physics/clip_model.zig").ClipModel;
const Physics = @import("physics/physics.zig").Physics;
const Game = @import("game.zig");

pub const Name = []const u8;

pub const Position = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
};

pub const Velocity = struct {
    x: i32 = 0,
    y: i32 = 0,
};

pub const Color = enum { Red, Green, Blue };

pub const Player = struct {
    name: Name,
    position: Position,
    velocity: Velocity,
    color: Color,

    pub fn spawn(_: *const SpawnArgs, _: ?*anyopaque) !Player {
        return .{
            .name = "playerInstance",
            .position = .{},
            .velocity = .{},
            .color = Color.Green,
        };
    }
};

pub const Item = struct {
    name: Name,
    color: Color,

    pub fn spawn(spawn_args: *const SpawnArgs, _: ?*anyopaque) !Item {
        const color_str = spawn_args.get("color") orelse "Red";
        const color: Color = blk: {
            inline for (std.meta.fields(Color)) |info| {
                if (std.mem.eql(u8, info.name, color_str)) {
                    break :blk @enumFromInt(info.value);
                }
            }

            unreachable;
        };

        return .{
            .name = spawn_args.get("name") orelse "unknown_item",
            .color = color,
        };
    }
};

pub const Enemy = struct {
    name: Name,
    position: Position,
    velocity: Velocity,

    pub fn spawn(_: *const SpawnArgs, _: ?*anyopaque) !Enemy {
        return .{
            .name = "enemyInstance",
            .position = .{ .x = 10.0, .y = 10.0 },
            .velocity = .{ .x = -1, .y = -1 },
        };
    }
};

extern fn c_parse_spawn_args_to_render_entity(*anyopaque, *render_entity.CRenderEntity) callconv(.C) void;

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
            clip_model_local = ClipModel.fromModel(model_path);
        }

        return .{
            .render_entity = c_render_entity,
            .name = spawn_args.get("name") orelse "unnamed_" ++ @typeName(@This()),
            .physics = .{
                .rigid_body = .{
                    .current = .{ .integration = .{ .position = c_render_entity.origin.toVec3f() } },
                    .clip_model = clip_model_local,
                },
            },
        };
    }
};

extern fn c_add_entity_def(*const render_entity.CRenderEntity) callconv(.C) c_int;
extern fn c_update_entity_def(c_int, *const render_entity.CRenderEntity) callconv(.C) void;

pub fn updatePhysics(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        physics: Physics,
    }, T)) return;

    const time_state = Game.c_getTimeState();
    const delta_time_ms = time_state.delta();
    const dt = (@as(f32, @floatFromInt(delta_time_ms)) / 1000.0);

    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
    ) |*physics| {
        switch (physics.*) {
            Physics.rigid_body => |*rigid_body| _ = rigid_body.evaluate(delta_time_ms),
            Physics.static => |*static| {
                var rotation = Rotation.create(
                    static.current.origin,
                    Vec3(f32){ .z = 1.0 },
                    45.0 * dt,
                );

                static.rotate(&rotation);
            },
        }
    }
}

pub fn updateRenderEntityFromPhysics(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        physics: Physics,
        render_entity: render_entity.CRenderEntity,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.physics),
        list_slice.items(.render_entity),
    ) |
        *physics,
        *render_entity_ptr,
    | {
        const transform = physics.getTransform();
        render_entity_ptr.axis = CMat3.fromMat3f(&transform.axis);
        render_entity_ptr.origin = CVec3.fromVec3f(&transform.origin);
    }
}

pub fn presentRenderEntity(comptime T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        model_def_handle: c_int,
        render_entity: render_entity.CRenderEntity,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.render_entity),
        list_slice.items(.model_def_handle),
    ) |
        *render_entity_ptr,
        *model_def_handle,
    | {
        if (render_entity_ptr.hModel == null) continue;

        // add to refresh list
        if (model_def_handle.* == -1) {
            model_def_handle.* = c_add_entity_def(render_entity_ptr);
        } else {
            c_update_entity_def(model_def_handle.*, render_entity_ptr);
        }
    }
}

pub const ExportedTypes = .{ Player, Item, Enemy, StaticObject, MoveableObject };
