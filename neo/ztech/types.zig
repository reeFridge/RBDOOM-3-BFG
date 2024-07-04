const std = @import("std");
const SpawnArgs = @import("entity.zig").SpawnArgs;
const CRenderEntity = @import("renderer/render_entity.zig").CRenderEntity;
const ClipModel = @import("physics/clip_model.zig").ClipModel;
const Physics = @import("physics/physics.zig").Physics;
const PhysicsRigidBody = @import("physics/rigid_body.zig");
const PhysicsStatic = @import("physics/static.zig");
const Transform = @import("physics/physics.zig").Transform;
const TraceModel = @import("physics/trace_model.zig").TraceModel;
const ContactInfo = @import("physics/collision_model.zig").ContactInfo;
const Vec3 = @import("math/vector.zig").Vec3;
const Mat3 = @import("math/matrix.zig").Mat3;
const CMat3 = @import("math/matrix.zig").CMat3;
const CVec3 = @import("math/vector.zig").CVec3;

const game = @import("game.zig");

pub const EntityDef = struct {
    index: usize,

    pub fn name(self: EntityDef) []const u8 {
        return if (game.c_declByIndex(@intCast(self.index))) |decl|
            decl.name()
        else
            "*unknown*";
    }
};

const Name = []const u8;

pub const SpawnError = error{
    ClipModelIsUndefined,
    CSpawnArgsIsUndefined,
    EntityDefIsUndefined,
};

extern fn c_parseMatrix([*c]const u8) callconv(.C) CMat3;
extern fn c_parseVector([*c]const u8) callconv(.C) CVec3;

pub const PlayerSpawn = struct {
    def: EntityDef,
    transform: Transform,

    pub fn spawn(_: std.mem.Allocator, spawn_args: SpawnArgs, _: ?*anyopaque) !PlayerSpawn {
        const classname = spawn_args.get("classname") orelse return error.EntityDefIsUndefined;
        const decl = game.c_findEntityDef(classname.ptr) orelse return error.EntityDefIsUndefined;

        const origin = if (spawn_args.get("origin")) |origin_str|
            c_parseVector(origin_str.ptr).toVec3f()
        else
            Vec3(f32){};

        const rotation = if (spawn_args.get("rotation")) |rotation_str|
            c_parseMatrix(rotation_str.ptr).toMat3f()
        else
            Mat3(f32).identity();

        return .{
            .def = EntityDef{ .index = decl.index() },
            .transform = .{
                .axis = rotation,
                .origin = origin,
            },
        };
    }
};

pub const StaticObject = struct {
    transform: Transform,
    name: Name,
    // used to present a model to the renderer
    render_entity: CRenderEntity,
    model_def_handle: c_int = -1,
    physics: Physics,
    clip_model: ClipModel,

    pub fn spawn(_: std.mem.Allocator, spawn_args: SpawnArgs, c_dict_ptr: ?*anyopaque) !StaticObject {
        var c_render_entity = CRenderEntity{};
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
};

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

pub const MoveableObject = struct {
    transform: Transform,
    name: Name,
    // used to present a model to the renderer
    render_entity: CRenderEntity,
    model_def_handle: c_int = -1,
    physics: Physics,
    clip_model: ClipModel,
    contacts: Contacts,
    impact: Impact,

    inline fn createClipModel(model_path: []const u8) !ClipModel {
        // TODO: Why it is printed?
        // WARNING: idClipModel::FreeTraceModel: tried to free uncached trace model
        const trace_model = try TraceModel.fromModel(model_path);
        var clip_model = ClipModel.fromTraceModel(trace_model);
        clip_model.contents = 1; // CONTENTS_SOLID
        return clip_model;
    }

    pub fn spawn(
        allocator: std.mem.Allocator,
        spawn_args: SpawnArgs,
        c_dict_ptr: ?*anyopaque,
    ) !MoveableObject {
        var c_render_entity = CRenderEntity{};
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

        return .{
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
        };
    }
};

const RenderView = @import("renderer/render_world.zig").RenderView;

extern fn c_calculateRenderView(*RenderView, f32) void;

pub const View = struct {
    origin: Vec3(f32),
    axis: Mat3(f32),
    fov: f32 = 80,
    render_view: RenderView = std.mem.zeroes(RenderView),

    pub fn calculateRenderView(self: *View) void {
        c_calculateRenderView(&self.render_view, self.fov);
        self.render_view.vieworg = CVec3.fromVec3f(self.origin);
        self.render_view.viewaxis = CMat3.fromMat3f(self.axis);
    }
};

pub const PlayerSpawnError = error{
    PlayerSpawnNotFound,
};

const MAX_PVS_AREAS: usize = 4;

const pvs = @import("pvs.zig");
const Bounds = @import("bounding_volume/bounds.zig");

pub const PVSAreas = struct {
    updated: bool,
    len: usize,
    ids: [MAX_PVS_AREAS]c_int,

    pub fn update(self: *PVSAreas, position: Vec3(f32)) void {
        var count = pvs.getPVSAreas(Bounds.fromVec3(position), &self.ids);
        self.len = count;

        while (count < MAX_PVS_AREAS) {
            self.ids[count] = 0;
            count += 1;
        }

        self.updated = true;
    }
};

pub const byte = u8;
pub const uint16 = c_ushort;

pub const UserCmd = extern struct {
    angles: [3]c_short,
    forwardmove: i8,
    rightmove: i8,
    buttons: byte,
    clientGameMilliseconds: c_int,
    serverGameMilliseconds: c_int,
    fireCount: uint16,
    impulse: byte,
    impulseSequence: byte,
    mx: c_short,
    my: c_short,
    pos: CVec3,
    speedSquared: f32,
};

pub const Input = struct {
    user_cmd: UserCmd = std.mem.zeroes(UserCmd),
};

pub const Player = struct {
    client_id: u8,
    input: Input,
    transform: Transform,
    view: View,
    pvs_areas: PVSAreas = std.mem.zeroes(PVSAreas),

    pub fn init(client_id: u8, transform: Transform) Player {
        return .{
            .client_id = client_id,
            .input = .{},
            .transform = transform,
            .view = .{
                .origin = transform.origin,
                .axis = transform.axis,
            },
        };
    }
};

const RenderLight = @import("renderer/render_world.zig").RenderLight;

pub const Light = struct {
    transform: Transform,
    light_def_handle: c_int = -1,
    render_light: RenderLight,

    pub fn spawn(_: std.mem.Allocator, spawn_args: SpawnArgs, c_dict_ptr: ?*anyopaque) !Light {
        var c_render_light = std.mem.zeroes(RenderLight);
        if (c_dict_ptr) |ptr| {
            c_render_light.initFromSpawnArgs(ptr);
        } else return error.CSpawnArgsIsUndefined;

        const origin = if (spawn_args.get("origin")) |origin_str|
            c_parseVector(origin_str.ptr).toVec3f()
        else
            Vec3(f32){};

        const rotation = if (spawn_args.get("rotation")) |rotation_str|
            c_parseMatrix(rotation_str.ptr).toMat3f()
        else
            Mat3(f32).identity();

        return .{
            .transform = .{ .origin = origin, .axis = rotation },
            .render_light = c_render_light,
        };
    }
};

// TODO: idRenderWorldLocal::AddWorldModelEntities()

pub const ExportedTypes = .{ StaticObject, MoveableObject, PlayerSpawn, Player, Light };
