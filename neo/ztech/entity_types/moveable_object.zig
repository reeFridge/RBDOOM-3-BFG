const std = @import("std");
const Vec3 = @import("../math/vector.zig").Vec3;
const SpawnArgs = @import("../entity.zig").SpawnArgs;
const PhysicsRigidBody = @import("../physics/rigid_body.zig");
const TraceModel = @import("../physics/trace_model.zig").TraceModel;
const ContactInfo = @import("../physics/collision_model.zig").ContactInfo;
const Transform = @import("../physics/physics.zig").Transform;
const common = @import("common.zig");
const RenderEntity = @import("../renderer/render_entity.zig").RenderEntity;
const Physics = @import("../physics/physics.zig").Physics;
const ClipModel = @import("../physics/clip_model.zig").ClipModel;
const global = @import("../global.zig");
const EntityHandle = global.Entities.EntityHandle;

pub const Impact = struct {
    apply: bool = false,
    impulse: Vec3(f32) = .{},
    point: Vec3(f32) = .{},

    pub fn set(self: *Impact, point: Vec3(f32), impulse: Vec3(f32)) void {
        self.point = point;
        self.impulse = impulse;
        self.apply = true;
    }

    pub fn clear(self: *Impact) void {
        self.point = .{};
        self.impulse = .{};
        self.apply = false;
    }
};

pub const Contacts = struct {
    const T = std.ArrayList(ContactInfo);

    list: T,

    pub fn init(allocator: std.mem.Allocator) Contacts {
        return .{ .list = T.init(allocator) };
    }

    pub fn component_deinit(self: *Contacts) void {
        self.list.deinit();
    }
};

const MoveableObject = @This();

transform: Transform,
name: common.Name,
// used to present a model to the renderer
render_entity: RenderEntity,
model_def_handle: c_int = -1,
physics: Physics,
clip_model: ClipModel,
contacts: Contacts,
impact: Impact,

inline fn createClipModel(model_path: []const u8) !ClipModel {
    const trace_model = try TraceModel.fromModel(model_path);
    var clip_model = ClipModel.fromTraceModel(trace_model);
    clip_model.contents = 1; // CONTENTS_SOLID
    return clip_model;
}

pub fn spawn(
    allocator: std.mem.Allocator,
    spawn_args: SpawnArgs,
    c_dict_ptr: ?*anyopaque,
) !EntityHandle {
    var c_render_entity = RenderEntity{};
    if (c_dict_ptr) |ptr| {
        c_render_entity.initFromSpawnArgs(ptr);
    } else return error.CSpawnArgsIsUndefined;

    var clip_model: ClipModel = if (spawn_args.get("model")) |model_path|
        try MoveableObject.createClipModel(model_path)
    else
        return error.ClipModelIsUndefined;

    clip_model.origin = c_render_entity.origin;
    const density = 1;

    const transform = .{ .origin = c_render_entity.origin.toVec3f() };

    return try global.entities.register(MoveableObject{
        .transform = transform,
        .render_entity = c_render_entity,
        .name = spawn_args.get("name") orelse "unnamed_" ++ @typeName(@This()),
        .physics = .{
            .rigid_body = PhysicsRigidBody.init(
                transform,
                clip_model.mass_properties(density),
            ),
        },
        .clip_model = clip_model,
        .contacts = Contacts.init(allocator),
        .impact = .{},
    });
}
