const std = @import("std");
const entity = @import("entity.zig");
const Types = @import("types.zig").ExportedTypes;
const Game = @import("game.zig");

const Entities = entity.Entities(Types);

var g_entities: Entities = undefined;
var g_gpa = std.heap.GeneralPurposeAllocator(.{}){};

pub export fn ztech_init() callconv(.C) void {
    g_entities = Entities.init(g_gpa.allocator());
    std.debug.print("[ztech] init: OK\n", .{});
}

pub export fn ztech_deinit() callconv(.C) void {
    g_entities.deinit();
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
    _ = g_entities.spawn(type_name, &spawn_args, c_dict_ptr) catch |err| {
        if (err == entity.EntityError.UnknownEntityType) {
            std.debug.print("[error] UnknownEntityType\n", .{});
        }

        return false;
    };

    std.debug.print("[OK]\n", .{});

    return true;
}

const presentRenderEntity = @import("types.zig").presentRenderEntity;
const updatePhysics = @import("types.zig").updatePhysics;
const updateRenderEntityFromPhysics = @import("types.zig").updateRenderEntityFromPhysics;

pub export fn ztech_processEntities() callconv(.C) void {
    if (!Game.c_isNewFrame()) return;

    g_entities.process(updatePhysics);
    g_entities.process(updateRenderEntityFromPhysics);
    g_entities.process(presentRenderEntity);
}
