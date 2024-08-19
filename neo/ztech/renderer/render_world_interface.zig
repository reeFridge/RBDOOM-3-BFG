const global = @import("../global.zig");
const std = @import("std");
const RenderWorld = @import("render_world.zig");
const RenderView = @import("render_world.zig").RenderView;
const Interaction = @import("interaction.zig").Interaction;
const RenderEntity = @import("render_entity.zig").RenderEntity;
const RenderLight = @import("render_light.zig").RenderLight;
const CVec3 = @import("../math/vector.zig").CVec3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const RenderSystem = @import("render_system.zig");

pub const RenderWorldOpaque = opaque {};

export fn ztech_renderWorld_getEntityDefsCount(rw: *RenderWorldOpaque) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    return render_world.entity_defs.items.len;
}

export fn ztech_renderWorld_getInteractionEntry(rw: *RenderWorldOpaque, row: usize, column: usize) callconv(.C) ?*Interaction {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    const table = render_world.interaction_table orelse return null;

    const entry = table[row * render_world.interaction_table_width + column];

    return entry;
}

export fn ztech_renderWorld_getInteractionRow(rw: *RenderWorldOpaque, row: usize) ?[*]?*Interaction {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    const table = render_world.interaction_table orelse return null;
    const row_start = row * render_world.interaction_table_width;
    const table_row = table[row_start..(row_start + render_world.interaction_table_width)];

    return table_row.ptr;
}

export fn ztech_renderWorld_boundsInAreas(
    rw: *RenderWorldOpaque,
    bounds: CBounds,
    areas: [*c]c_int,
    max_areas: usize,
) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return render_world.boundsInAreas(bounds.toBounds(), areas[0..max_areas]);
}

export fn ztech_renderWorld_renderScene(rw: *RenderWorldOpaque, view: *const RenderView) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.renderScene(view.*) catch {
        @panic("ztech_renderWorld_renderScene: fails");
    };
}

export fn ztech_renderWorld_generateAllInteractions(rw: *RenderWorldOpaque) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.generateAllInteractions() catch {
        @panic("ztech_renderWorld_generateAllInteractions: fails");
    };
}

export fn ztech_renderWorld_areaBounds(rw: *RenderWorldOpaque, int_area_num: c_int) callconv(.C) CBounds {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    if (int_area_num < 0) @panic("ztech_renderWorld_areaBounds: bad area_num");

    const bounds = render_world.areaBounds(@intCast(int_area_num)) catch {
        @panic("ztech_renderWorld_areaBounds: area_num out of range");
    };

    return CBounds.fromBounds(bounds);
}

export fn ztech_renderWorld_pointInArea(rw: *RenderWorldOpaque, point: *const CVec3) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    const index = render_world.pointInArea(point.toVec3f()) catch return -1;

    return @intCast(index);
}

export fn ztech_renderWorld_areasAreConnected(
    rw: *RenderWorldOpaque,
    int_area_a: c_int,
    int_area_b: c_int,
    connection: c_int,
) callconv(.C) bool {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    if (int_area_a == -1 or int_area_b == -1) return false;

    return render_world.areasAreConnected(@intCast(int_area_a), @intCast(int_area_b), connection) catch {
        @panic("ztech_renderWorld: bad areas params");
    };
}

export fn ztech_renderWorld_freeLightDef(rw: *RenderWorldOpaque, light_index: c_int) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.freeLightDef(@intCast(light_index)) catch |err| {
        std.debug.print("ztech_renderWorld_freeLightIndex: fails, err = {}\n", .{err});
    };
}

export fn ztech_renderWorld_addLightDef(rw: *RenderWorldOpaque, def: *const RenderLight) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    const index = render_world.addLightDef(def.*) catch {
        @panic("ztech_renderWorld: fail to add light");
    };

    return @intCast(index);
}

export fn ztech_renderWorld_updateLightDef(rw: *RenderWorldOpaque, light_index: c_int, def: *const RenderLight) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.updateLightDef(@intCast(light_index), def.*) catch {
        @panic("ztech_renderWorld: fail to update light");
    };
}

export fn ztech_renderWorld_addEntityDef(rw: *RenderWorldOpaque, def: *const RenderEntity) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    const index = render_world.addEntityDef(def.*) catch {
        @panic("ztech_renderWorld: fail to add entity");
    };

    return @intCast(index);
}

export fn ztech_renderWorld_updateEntityDef(rw: *RenderWorldOpaque, entity_index: c_int, def: *const RenderEntity) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.updateEntityDef(@intCast(entity_index), def.*) catch {
        @panic("ztech_renderWorld: fail to update entity");
    };
}

export fn ztech_renderWorld_freeEntityDef(rw: *RenderWorldOpaque, entity_index: c_int) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.freeEntityDef(@intCast(entity_index)) catch |err| {
        std.debug.print("ztech_renderWorld_freeEntityDef: fails, err = {}\n", .{err});
    };
}

export fn ztech_renderWorld_getPortal(
    rw: *RenderWorldOpaque,
    area_num: c_int,
    portal_num: c_int,
) callconv(.C) RenderWorld.ExitPortal {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return render_world.getPortal(@intCast(area_num), @intCast(portal_num)) catch {
        @panic("ztech_renderWorld_getPortal: fails!");
    };
}

export fn ztech_renderWorld_numPortalsInArea(rw: *RenderWorldOpaque, area_index: usize) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return render_world.numPortalsInArea(area_index) catch {
        @panic("ztech_renderWorld: bad area_index");
    };
}

export fn ztech_renderWorld_numAreas(rw: *RenderWorldOpaque) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return if (render_world.area_nodes) |area_nodes|
        area_nodes.len
    else
        0;
}
