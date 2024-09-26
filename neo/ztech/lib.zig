const std = @import("std");
const entity = @import("entity.zig");
const Game = @import("game.zig");
const global = @import("global.zig");
const CVec3 = @import("math/vector.zig").CVec3;
const CMat3 = @import("math/matrix.zig").CMat3;
const entity_types = @import("entity_types/index.zig");
const PlayerSpawn = @import("entity_types/player_spawn.zig");
const Player = @import("entity_types/player.zig");
const RenderSystem = @import("renderer/render_system.zig");

usingnamespace @import("renderer/model_interface.zig");
usingnamespace @import("game_interface.zig");
usingnamespace @import("renderer/render_system_interface.zig");
usingnamespace @import("renderer/render_world_interface.zig");
usingnamespace @import("renderer/frame_data_interface.zig");

export fn ztech_init() callconv(.C) void {
    const global_allocator = global.gpa.allocator();

    global.entities = global.Entities.init(global_allocator);

    std.debug.print("[ztech] init: OK\n", .{});
}

export fn ztech_entities_deinit() void {
    global.entities.deinit();
}

export fn ztech_deinit() callconv(.C) void {
    if (global.gpa.deinit() == std.heap.Check.leak) @panic("[ztech] allocator leak!");

    std.debug.print("[ztech] deinit: OK\n", .{});
}

export fn ztech_clearEntities() callconv(.C) void {
    global.entities.clear();

    std.debug.print("[ztech] clear: OK\n", .{});
}

pub const CopySpawnArgs = struct {
    var target: *entity.SpawnArgs = undefined;
    var dict_ptr: *anyopaque = undefined;

    fn putKeyValue(c_key: [*c]const u8, c_value: [*c]const u8) callconv(.C) void {
        const key: [:0]const u8 = std.mem.span(c_key);
        const value: [:0]const u8 = std.mem.span(c_value);

        target.put(key, value) catch return;
    }

    pub fn init(b: *anyopaque, a: *entity.SpawnArgs) void {
        CopySpawnArgs.target = a;
        CopySpawnArgs.dict_ptr = b;
    }

    pub fn copy() void {
        c_copy_dict_to_zig(dict_ptr, CopySpawnArgs.putKeyValue);
    }
};

extern fn c_copy_dict_to_zig(*anyopaque, *const fn ([*c]const u8, [*c]const u8) callconv(.C) void) void;

export fn ztech_spawnPlayer(client_num: c_int) callconv(.C) bool {
    std.debug.print("Spawn Player: {d}\n", .{client_num});

    const spots = global.entities.getByType(PlayerSpawn).field_storage.items(.transform);

    if (spots.len == 0) return false;

    _ = global.entities.register(Player.init(@intCast(client_num), spots[0])) catch |err| {
        std.debug.print("[error] {?}\n", .{err});
        return false;
    };

    return true;
}

const pvs = @import("pvs.zig");

export fn ztech_getPlayerHandle(c_handle: *global.Entities.ExternEntityHandle) callconv(.C) bool {
    const len = global.entities.getByType(Player).field_storage.len;

    if (len == 0) return false;

    const handle = global.Entities.EntityHandle.fromType(Player, 0);
    c_handle.* = .{
        .id = handle.id,
        .type = @intFromEnum(handle.type),
    };

    return true;
}

const RenderView = @import("renderer/render_world.zig").RenderView;

export fn ztech_getSpawnTransform(origin: *CVec3, axis: *CMat3) callconv(.C) bool {
    const spots = global.entities.getByType(PlayerSpawn).field_storage.items(.transform);

    if (spots.len == 0) return false;

    const first_spot = spots[0];

    origin.* = CVec3.fromVec3f(first_spot.origin);
    axis.* = CMat3.fromMat3f(first_spot.axis);

    return true;
}

export fn ztech_spawnExternal(c_type_name: [*c]const u8, c_dict_ptr: *anyopaque) callconv(.C) bool {
    std.debug.print("[ztech] spawnExternal: {s}\n", .{c_type_name});

    var spawn_args = entity.SpawnArgs.init(global.gpa.allocator());
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

const QueryField = @import("entity.zig").QueryField;
const Physics = @import("physics/physics.zig").Physics;
const Capture = @import("entity.zig").Capture;

export fn ztech_entityApplyImpulse(
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
