const global = @import("../global.zig");
const std = @import("std");
const RenderWorld = @import("render_world.zig");
const RenderView = @import("render_world.zig").RenderView;
const PortalArea = @import("render_world.zig").PortalArea;
const Interaction = @import("interaction.zig").Interaction;
const RenderEntity = @import("render_entity.zig").RenderEntity;
const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderLight = @import("render_light.zig").RenderLight;
const RenderEnvironmentProbe = @import("render_envprobe.zig").RenderEnvironmentProbe;
const CVec3 = @import("../math/vector.zig").CVec3;
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const RenderSystem = @import("render_system.zig");

pub const RenderWorldOpaque = opaque {};

export fn ztech_renderWorld_checkAreaForPortalSky(rw: *RenderWorldOpaque, index: c_int) callconv(.C) bool {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    std.debug.assert(index >= 0);

    return render_world.checkAreaForPortalSky(@intCast(index));
}

export fn ztech_renderWorld_getPortalArea(rw: *RenderWorldOpaque, index: c_int) callconv(.C) ?*PortalArea {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return if (render_world.portal_areas) |portal_areas|
        &portal_areas[@intCast(index)]
    else
        null;
}

export fn ztech_renderWorld_getEntityDef(rw: *RenderWorldOpaque, index: c_int) callconv(.C) ?*RenderEntityLocal {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    return render_world.entity_defs.items[@intCast(index)];
}

export fn ztech_renderWorld_getPortalsCount(
    rw: *RenderWorldOpaque,
) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    return if (render_world.double_portals) |portals| portals.len else 0;
}

export fn ztech_renderWorld_getEntityDefsCount(
    rw: *RenderWorldOpaque,
) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    return render_world.entity_defs.items.len;
}

export fn ztech_renderWorld_getInteractionEntry(
    rw: *RenderWorldOpaque,
    row: usize,
    column: usize,
) callconv(.C) ?*Interaction {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    const table = render_world.interaction_table orelse return null;

    const entry = table[row * render_world.interaction_table_width + column];

    return entry;
}

export fn ztech_renderWorld_boundsInAreas(
    rw: *RenderWorldOpaque,
    bounds: *const CBounds,
    areas: [*c]c_int,
    max_areas: usize,
) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return render_world.boundsInAreas(bounds.toBounds(), areas[0..max_areas]);
}

export fn ztech_renderWorld_renderScene(
    rw: *RenderWorldOpaque,
    view: *const RenderView,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    render_world.renderScene(view.*);
}

export fn ztech_renderWorld_generateAllInteractions(
    rw: *RenderWorldOpaque,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.generateAllInteractions() catch {
        @panic("ztech_renderWorld_generateAllInteractions: fails");
    };
}

export fn ztech_renderWorld_areaBounds(
    rw: *RenderWorldOpaque,
    int_area_num: c_int,
) callconv(.C) CBounds {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    if (int_area_num < 0) @panic("ztech_renderWorld_areaBounds: bad area_num");

    const bounds = render_world.areaBounds(@intCast(int_area_num)) catch {
        @panic("ztech_renderWorld_areaBounds: area_num out of range");
    };

    return CBounds.fromBounds(bounds);
}

export fn ztech_renderWorld_pointInArea(
    rw: *RenderWorldOpaque,
    point: *const CVec3,
) callconv(.C) c_int {
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

export fn ztech_renderWorld_freeLightDef(
    rw: *RenderWorldOpaque,
    light_index: c_int,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.freeLightDefByIndex(@intCast(light_index)) catch |err| {
        std.debug.print("ztech_renderWorld_freeLightIndex: fails, err = {}\n", .{err});
    };
}

export fn ztech_renderWorld_addLightDef(
    rw: *RenderWorldOpaque,
    def: *const RenderLight,
) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    const index = render_world.addLightDef(def.*) catch {
        @panic("ztech_renderWorld: fail to add light");
    };

    return @intCast(index);
}

export fn ztech_renderWorld_updateLightDef(
    rw: *RenderWorldOpaque,
    light_index: c_int,
    def: *const RenderLight,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.updateLightDef(@intCast(light_index), def.*) catch {
        @panic("ztech_renderWorld: fail to update light");
    };
}

export fn ztech_renderWorld_addEntityDef(
    rw: *RenderWorldOpaque,
    def: *const RenderEntity,
) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    const index = render_world.addEntityDef(def.*) catch {
        @panic("ztech_renderWorld: fail to add entity");
    };

    return @intCast(index);
}

export fn ztech_renderWorld_addEnvprobeDef(
    rw: *RenderWorldOpaque,
    def: *const RenderEnvironmentProbe,
) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    const index = render_world.addEnvprobeDef(def.*) catch {
        @panic("ztech_renderWorld_addEnvprobeDef: fail to add envprobe");
    };

    return @intCast(index);
}

export fn ztech_renderWorld_updateEntityDef(
    rw: *RenderWorldOpaque,
    entity_index: c_int,
    def: *const RenderEntity,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.updateEntityDef(@intCast(entity_index), def.*) catch {
        @panic("ztech_renderWorld: fail to update entity");
    };
}

export fn ztech_renderWorld_updateEnvprobeDef(
    rw: *RenderWorldOpaque,
    envprobe_index: c_int,
    def: *const RenderEnvironmentProbe,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.updateEnvprobeDef(@intCast(envprobe_index), def.*) catch {
        @panic("ztech_renderWorld_updateEnvprobeDef: fail to update envprobe");
    };
}

export fn ztech_renderWorld_freeEntityDef(
    rw: *RenderWorldOpaque,
    entity_index: c_int,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.freeEntityDefByIndex(@intCast(entity_index)) catch |err| {
        std.debug.print("ztech_renderWorld_freeEntityDef: fails, err = {}\n", .{err});
    };
}

export fn ztech_renderWorld_freeEnvprobeDef(
    rw: *RenderWorldOpaque,
    envprobe_index: c_int,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.freeEnvprobeDefByIndex(@intCast(envprobe_index)) catch |err| {
        std.debug.print("ztech_renderWorld_freeEnvprobeDef: fails, err = {}\n", .{err});
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

export fn ztech_renderWorld_numPortalsInArea(
    rw: *RenderWorldOpaque,
    area_index: usize,
) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return render_world.numPortalsInArea(area_index) catch {
        @panic("ztech_renderWorld: bad area_index");
    };
}

export fn ztech_renderWorld_numAreas(rw: *RenderWorldOpaque) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return if (render_world.portal_areas) |portal_areas|
        portal_areas.len
    else
        0;
}

export fn ztech_renderWorld_initFromMap(
    rw: *RenderWorldOpaque,
    c_map_name: [*c]const u8,
) callconv(.C) bool {
    const render_world_ptr: *RenderWorld = @alignCast(@ptrCast(rw));
    const map_name: [:0]const u8 = std.mem.span(c_map_name);

    render_world_ptr.initFromMap(map_name) catch return false;

    return true;
}

export fn ztech_renderWorld_findPortal(rw: *RenderWorldOpaque, b: CBounds) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return @intCast(render_world.findPortal(b.toBounds()));
}

export fn ztech_renderWorld_setPortalState(
    rw: *RenderWorldOpaque,
    index: c_int,
    block_types: c_int,
) callconv(.C) void {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    render_world.setPortalState(@intCast(index), block_types);
}

export fn ztech_renderWorld_getPortalState(
    rw: *RenderWorldOpaque,
    index: c_int,
) callconv(.C) c_int {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    return render_world.getPortalState(@intCast(index));
}

export fn ztech_renderWorld_getRenderEntity(
    rw: *RenderWorldOpaque,
    index: c_int,
) callconv(.C) ?*const RenderEntity {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    return render_world.getRenderEntity(@intCast(index));
}

export fn ztech_renderWorld_getRenderLight(
    rw: *RenderWorldOpaque,
    index: c_int,
) callconv(.C) ?*const RenderLight {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));
    return render_world.getRenderLight(@intCast(index));
}
