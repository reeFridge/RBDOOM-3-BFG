const std = @import("std");
const types = @import("types.zig");
const entity = @import("entity.zig");

const PhysicalObj = struct {
    position: types.Position,
    velocity: types.Velocity,
};

fn updatePhysics(comptime T: type, list: anytype) void {
    if (comptime !entity.assertFields(PhysicalObj, T)) return;

    var list_slice = list.slice();
    for (list_slice.items(.velocity), list_slice.items(.position)) |velocity, *position| {
        position.x += @floatFromInt(velocity.x);
        position.y += @floatFromInt(velocity.y);
    }
}

fn printNames(comptime T: type, list: anytype) void {
    if (comptime !entity.assertFields(struct { name: types.Name }, T)) return;

    for (list.items(.name)) |name| {
        std.debug.print("entity: {s}\n", .{name});
    }
}

test "example" {
    const allocator = std.testing.allocator;
    var entities = entity.Entities(.{
        types.Player,
        types.Item,
        types.Enemy,
    }).init(allocator);
    defer entities.deinit();

    try std.testing.expect(entities.size() == @as(usize, 0));

    var players = entities.getByType(types.Player);
    _ = try players.add(.{
        .name = "playerInstance",
        .position = .{},
        .velocity = .{},
        .color = types.Color.Green,
    });

    var items = entities.getByType(types.Item);
    _ = try items.add(.{ .name = "itemInstance", .color = types.Color.Red });

    try std.testing.expect(players.storage.len == @as(usize, 1));
    try std.testing.expect(items.storage.len == @as(usize, 1));
    try std.testing.expect(entities.size() == @as(usize, 2));

    var enemies = entities.getByType(types.Enemy);
    _ = try enemies.add(.{
        .name = "enemyInstance",
        .position = .{ .x = 10.0, .y = 10.0 },
        .velocity = .{ .x = -1, .y = -1 },
    });

    entities.process(printNames);

    var enemy = enemies.storage.get(@as(usize, 0));

    try std.testing.expectEqual(enemy.position, types.Position{ .x = 10.0, .y = 10.0 });

    const ticks = 10;
    var tick: u32 = 0;
    while (tick < ticks) : (tick += 1) {
        entities.process(updatePhysics);
    }

    enemy = enemies.storage.get(@as(usize, 0));

    try std.testing.expectEqual(enemy.position, types.Position{ .x = 0.0, .y = 0.0 });

    // TODO: how to ref to some entity at global index? (e.g. EntityID + Entities.getById())
    // TODO: how to refer to some entities from inside other entity? (e.g. enemy link)
}

test "spawn by SpawnArgs" {
    const allocator = std.testing.allocator;
    var entities = entity.Entities(.{
        types.Item,
    }).init(allocator);
    defer entities.deinit();

    var spawnArgs = entity.SpawnArgs.init(allocator);
    defer spawnArgs.deinit();

    const type_name = "types.Item";
    try spawnArgs.put("name", "dynamic_item0");
    try spawnArgs.put("color", "Green");

    var id = try entities.spawn(type_name, &spawnArgs, null);

    var items = entities.getByType(types.Item);

    const item = items.storage.get(@as(usize, id));
    try std.testing.expect(std.mem.eql(u8, item.name, "dynamic_item0"));
    try std.testing.expect(item.color == types.Color.Green);
}
