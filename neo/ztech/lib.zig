const std = @import("std");
const entity = @import("entity.zig");
const Game = @import("game.zig");
const global = @import("global.zig");
const CVec3 = @import("math/vector.zig").CVec3;
const CMat3 = @import("math/matrix.zig").CMat3;
const types = @import("types.zig");

var g_gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub export fn ztech_init() callconv(.C) void {
    global.entities = global.Entities.init(g_gpa.allocator());
    std.debug.print("[ztech] init: OK\n", .{});
}

pub export fn ztech_deinit() callconv(.C) void {
    global.entities.deinit();
    if (g_gpa.deinit() == std.heap.Check.leak) @panic("[ztech] allocator leak!");

    std.debug.print("[ztech] deinit: OK\n", .{});
}

const CopySpawnArgs = struct {
    var target: *entity.SpawnArgs = undefined;
    var dict_ptr: *anyopaque = undefined;

    fn putKeyValue(c_key: [*c]const u8, c_value: [*c]const u8) callconv(.C) void {
        const key: [:0]const u8 = std.mem.span(c_key);
        const value: [:0]const u8 = std.mem.span(c_value);

        target.put(key, value) catch return;
    }

    fn init(b: *anyopaque, a: *entity.SpawnArgs) void {
        CopySpawnArgs.target = a;
        CopySpawnArgs.dict_ptr = b;
    }

    fn copy() void {
        c_copy_dict_to_zig(dict_ptr, CopySpawnArgs.putKeyValue);
    }
};

extern fn c_copy_dict_to_zig(*anyopaque, *const fn ([*c]const u8, [*c]const u8) callconv(.C) void) void;

pub export fn ztech_spawnPlayer(client_num: c_int) callconv(.C) bool {
    std.debug.print("Spawn Player: {d}\n", .{client_num});

    const spots = global.entities.getByType(types.PlayerSpawn).field_storage.items(.transform);

    if (spots.len == 0) return false;

    _ = global.entities.register(types.Player.init(@intCast(client_num), spots[0])) catch |err| {
        std.debug.print("[error] {?}\n", .{err});
        return false;
    };

    return true;
}

const pvs = @import("pvs.zig");

extern fn c_getClientPVS([*]c_int, usize) callconv(.C) pvs.Handle;

pub export fn ztech_getPlayerHandle(c_handle: *global.Entities.ExternEntityHandle) callconv(.C) bool {
    const len = global.entities.getByType(types.Player).field_storage.len;

    if (len == 0) return false;

    const handle = global.Entities.EntityHandle.fromType(types.Player, 0);
    c_handle.* = .{
        .id = handle.id,
        .type = @intFromEnum(handle.type),
    };

    return true;
}

const RenderView = @import("renderer/render_world.zig").RenderView;

pub export fn ztech_getPlayerRenderView(render_view: **const RenderView) callconv(.C) bool {
    const players = global.entities.getByType(types.Player).field_storage;

    if (players.len == 0) return false;

    const player_view = &players.items(.view)[0];

    render_view.* = &player_view.render_view;

    return true;
}

pub export fn ztech_setupPlayerPVS(player_PVS: *pvs.Handle, player_connected_areas: *pvs.Handle) callconv(.C) void {
    const all_areas = global.entities.getByType(types.Player).field_storage.items(.pvs_areas);

    if (all_areas.len == 0) @panic("Player is not spawned yet!");

    const player_areas = &all_areas[0];

    player_PVS.* = c_getClientPVS(&player_areas.ids, player_areas.len);
    player_connected_areas.* = c_getClientPVS(&player_areas.ids, player_areas.len);
}

pub export fn ztech_getSpawnTransform(origin: *CVec3, axis: *CMat3) callconv(.C) bool {
    const spots = global.entities.getByType(types.PlayerSpawn).field_storage.items(.transform);

    if (spots.len == 0) return false;

    const first_spot = spots[0];

    origin.* = CVec3.fromVec3f(first_spot.origin);
    axis.* = CMat3.fromMat3f(first_spot.axis);

    return true;
}

pub export fn ztech_spawnExternal(c_type_name: [*c]const u8, c_dict_ptr: *anyopaque) callconv(.C) bool {
    std.debug.print("[ztech] spawnExternal: {s}\n", .{c_type_name});

    var spawn_args = entity.SpawnArgs.init(g_gpa.allocator());
    defer spawn_args.deinit();

    CopySpawnArgs.init(c_dict_ptr, &spawn_args);
    CopySpawnArgs.copy();

    var it = spawn_args.iterator();
    while (it.next()) |kv| {
        std.debug.print("[spawn_args] key: {s} = \"{s}\"\n", .{ kv.key_ptr.*, kv.value_ptr.* });
    }

    const type_name: [:0]const u8 = std.mem.span(c_type_name);
    _ = global.entities.spawn(type_name, spawn_args, c_dict_ptr) catch |err| {
        std.debug.print("[error] {?}\n", .{err});
        return false;
    };

    std.debug.print("[OK]\n", .{});

    return true;
}

const UpdatePlayer = @import("update/player.zig");
const UpdateRenderEntity = @import("update/render_entity.zig");
const UpdatePhysicsClip = @import("update/physics/clip.zig");
const UpdatePhysicsContacts = @import("update/physics/contacts.zig");
const UpdatePhysicsImpact = @import("update/physics/impact.zig");
const UpdatePhysicsTransform = @import("update/physics/transform.zig");

pub export fn ztech_processEntities() callconv(.C) void {
    if (!Game.c_isNewFrame()) return;

    var ents = &global.entities;

    ents.process(UpdatePlayer.handleInput);
    ents.process(UpdatePlayer.updateViewAngles);
    ents.processWithQuery(types.Player, UpdatePlayer.update);

    ents.processWithQuery(UpdatePhysicsClip.Query, UpdatePhysicsClip.update);
    ents.processWithQuery(UpdatePhysicsContacts.Query, UpdatePhysicsContacts.update);
    ents.processWithQuery(UpdatePhysicsImpact.Query, UpdatePhysicsImpact.update);
    ents.processWithQuery(UpdatePhysicsTransform.Query, UpdatePhysicsTransform.update);

    ents.process(UpdateRenderEntity.fromTransform);
    ents.process(UpdateRenderEntity.present);
}

const QueryField = @import("entity.zig").QueryField;
const Physics = @import("physics/physics.zig").Physics;
const Capture = @import("entity.zig").Capture;

pub export fn ztech_entityApplyImpulse(
    chandle: global.Entities.ExternEntityHandle,
    point: CVec3,
    impulse: CVec3,
) callconv(.C) void {
    const handle = global.Entities.EntityHandle.fromExtern(chandle);
    if (global.entities.queryByHandle(
        handle,
        struct { physics: Capture.ref(Physics) },
    )) |query_result| {
        const physics_other = query_result.physics;

        switch (physics_other.*) {
            Physics.rigid_body => |*rigid_body| {
                rigid_body.applyImpulse(point.toVec3f(), impulse.toVec3f());
                rigid_body.activate();
            },
            else => {},
        }
    }
}
