const std = @import("std");
const Bounds = @import("bounding_volume/bounds.zig");
const CBounds = Bounds.CBounds;
const Winding = @import("geometry/winding.zig").Winding;
const Plane = @import("math/plane.zig").Plane;
const RenderWorld = @import("renderer/render_world.zig");
const Allocator = std.mem.Allocator;

const max_current_pvs: usize = 64;

pub const PVSType = enum(u32) {
    normal,
    all_portals_open,
    connected_areas,
};

pub const Handle = extern struct {
    index: i32 = -1,
    handle: u32 = 0,
};

pub const Current = extern struct {
    handle: Handle = .{},
    pvs: ?[*]u8 = null,
};

pub const Portal = extern struct {
    area_num: u32 = 0,
    winding: ?*Winding = null,
    bounds: CBounds = .{},
    plane: Plane = .{},
    passages: ?[*]Passage = null,
    done: bool = false,
    vis: ?[*]u8 = null,
    might_see: ?[*]u8 = null,
};

pub const Area = extern struct {
    num_portals: u32 = 0,
    bounds: CBounds = .{},
    portals: ?[*]*Portal = null,
};

pub const Passage = extern struct {
    can_see: ?[*]u8 = null,
};

pub const PotentialVisibleSet = extern struct {
    num_areas: u32 = 0,
    num_portals: u32 = 0,
    connected_areas: ?[*]bool = null,
    area_queue: ?[*]u32 = null,
    area_pvs: ?[*]u8 = null,
    current_pvs: [max_current_pvs]Current = [_]Current{.{}} ** max_current_pvs,
    portal_vis_bytes: u32 = 0,
    portal_vis_longs: u32 = 0,
    area_vis_bytes: u32 = 0,
    area_vis_longs: u32 = 0,
    pvs_portals: ?[*]Portal = null,
    pvs_areas: ?[*]Area = null,

    pub fn init(
        pvs: *PotentialVisibleSet,
        render_world: *const RenderWorld,
        allocator: Allocator,
    ) Allocator.Error!void {
        pvs.shutdown(allocator);

        pvs.num_areas = if (render_world.portal_areas) |areas|
            @intCast(areas.len)
        else
            0;

        if (pvs.num_areas == 0) return;

        const connected_areas = try allocator.alloc(bool, pvs.num_areas);
        errdefer allocator.free(connected_areas);
        pvs.connected_areas = connected_areas.ptr;
        const area_queue = try allocator.alloc(u32, pvs.num_areas);
        errdefer allocator.free(area_queue);
        pvs.area_queue = area_queue.ptr;

        pvs.area_vis_bytes = ((pvs.num_areas + 31) & ~@as(u32, 31)) >> 3;
        pvs.area_vis_longs = pvs.area_vis_bytes / @sizeOf(u32);

        const area_pvs = try allocator.alloc(u8, pvs.num_areas * pvs.area_vis_bytes);
        errdefer allocator.free(area_pvs);
        pvs.area_pvs = area_pvs.ptr;
        @memset(area_pvs, 0xFF);

        pvs.num_portals = getPortalCount(render_world);
        pvs.portal_vis_bytes = ((pvs.num_portals + 31) & ~@as(u32, 31)) >> 3;
        pvs.portal_vis_longs = pvs.portal_vis_bytes / @sizeOf(u32);

        for (&pvs.current_pvs) |*current| {
            current.* = .{};
            const current_pvs = try allocator.alloc(u8, pvs.area_vis_bytes);
            @memset(current_pvs, 0);
            current.pvs = current_pvs.ptr;
        }

        try pvs.createPVSData(render_world, allocator);
        defer pvs.destroyPVSData(allocator);

        pvs.frontPortalPVS();
        pvs.copyPortalPVSToMightSee();
        pvs.passagePVS();

        const total_visible_areas = pvs.areaPVSFromPortalPVS();
        std.debug.print("[PVS] total visible areas: {}\n", .{total_visible_areas});
    }

    pub fn shutdown(pvs: *PotentialVisibleSet, allocator: Allocator) void {
        if (pvs.connected_areas) |connected_areas_ptr| {
            allocator.free(connected_areas_ptr[0..pvs.num_areas]);
            pvs.connected_areas = null;
        }

        if (pvs.area_queue) |area_queue_ptr| {
            allocator.free(area_queue_ptr[0..pvs.num_areas]);
            pvs.area_queue = null;
        }

        if (pvs.area_pvs) |area_pvs_ptr| {
            allocator.free(area_pvs_ptr[0 .. pvs.num_areas * pvs.area_vis_bytes]);
            pvs.area_pvs = null;
        }

        for (&pvs.current_pvs) |*current| {
            if (current.pvs) |pvs_ptr| {
                allocator.free(pvs_ptr[0..pvs.area_vis_bytes]);
                current.pvs = null;
            }
        }
    }

    fn createPVSData(
        pvs: *PotentialVisibleSet,
        render_world: *const RenderWorld,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (pvs.num_portals == 0) return;

        const pvs_portals = try allocator.alloc(Portal, pvs.num_portals);
        errdefer allocator.free(pvs_portals);
        for (pvs_portals) |*pvs_portal| pvs_portal.* = .{};
        pvs.pvs_portals = pvs_portals.ptr;

        const pvs_areas = try allocator.alloc(Area, pvs.num_areas);
        errdefer allocator.free(pvs_areas);
        for (pvs_areas) |*area| area.* = .{};
        pvs.pvs_areas = pvs_areas.ptr;

        var current_portal: u32 = 0;
        var portal_ptrs = try allocator.alloc(*Portal, pvs.num_portals);

        for (pvs_areas, 0..) |*area, area_num| {
            area.bounds = CBounds.fromBounds(Bounds.cleared);
            const portals = portal_ptrs[current_portal..];
            area.portals = portals.ptr;

            const num_portals_in_area = render_world.numPortalsInArea(
                area_num,
            ) catch unreachable;
            for (0..num_portals_in_area) |portal_num| {
                const exit_portal = render_world.getPortal(
                    area_num,
                    portal_num,
                ) catch unreachable;
                const pvs_portal = &pvs_portals[current_portal];
                current_portal += 1;

                const winding = try Winding.create(allocator);
                errdefer winding.destroy(allocator);
                try winding.copyFrom(exit_portal.winding, allocator);
                pvs_portal.winding = winding;
                // area[1] is always the area the portal leads to
                pvs_portal.area_num = @intCast(exit_portal.areas[1]);

                const pvs_portal_vis_bytes = try allocator.alloc(u8, pvs.portal_vis_bytes);
                errdefer allocator.free(pvs_portal_vis_bytes);
                @memset(pvs_portal_vis_bytes, 0);
                pvs_portal.vis = pvs_portal_vis_bytes.ptr;

                const pvs_portal_might_see = try allocator.alloc(u8, pvs.portal_vis_bytes);
                errdefer allocator.free(pvs_portal_might_see);
                @memset(pvs_portal_might_see, 0);
                pvs_portal.might_see = pvs_portal_might_see.ptr;

                pvs_portal.bounds = winding.getBounds();
                pvs_portal.plane = winding.getPlane();

                pvs_portal.plane = pvs_portal.plane.flip();
                pvs_portal.done = false;

                portals[area.num_portals] = pvs_portal;
                area.num_portals += 1;

                {
                    var bounds = area.bounds.toBounds();
                    _ = bounds.addBounds(&pvs_portal.bounds.toBounds());
                    area.bounds = CBounds.fromBounds(bounds);
                }
            }
        }
    }

    fn destroyPVSData(pvs: *PotentialVisibleSet, allocator: Allocator) void {
        const pvs_areas = if (pvs.pvs_areas) |ptr|
            ptr[0..pvs.num_areas]
        else
            return;

        if (pvs_areas[0].portals) |portal_ptrs| {
            allocator.free(portal_ptrs[0..pvs.num_portals]);
            pvs_areas[0].portals = null;
        }

        allocator.free(pvs_areas);
        pvs.pvs_areas = null;

        const pvs_portals = if (pvs.pvs_portals) |ptr|
            ptr[0..pvs.num_portals]
        else
            return;

        for (pvs_portals) |*portal| {
            if (portal.winding) |winding_ptr| {
                winding_ptr.destroy(allocator);
                portal.winding = null;
            }

            if (portal.vis) |vis_ptr| {
                allocator.free(vis_ptr[0..pvs.portal_vis_bytes]);
                portal.vis = null;
            }

            if (portal.might_see) |might_see_ptr| {
                allocator.free(might_see_ptr[0..pvs.portal_vis_bytes]);
                portal.might_see = null;
            }
        }

        allocator.free(pvs_portals);
        pvs.pvs_portals = null;
    }

    fn getPortalCount(render_world: *const RenderWorld) u32 {
        const num_areas: u32 = if (render_world.portal_areas) |areas|
            @intCast(areas.len)
        else
            0;

        var num_portal_areas: u32 = 0;
        for (0..num_areas) |area_num| {
            num_portal_areas += @intCast(
                render_world.numPortalsInArea(area_num) catch unreachable,
            );
        }

        return num_portal_areas;
    }

    // TODO: port
    extern fn c_pvs_frontPortalPVS(pvs: *PotentialVisibleSet) void;
    extern fn c_pvs_copyPortalPVSToMightSee(pvs: *PotentialVisibleSet) void;
    extern fn c_pvs_passagePVS(pvs: *PotentialVisibleSet) void;
    extern fn c_pvs_areaPVSFromPortalPVS(pvs: *PotentialVisibleSet) c_int;
    extern fn c_pvs_setupCurrentPVS(
        *const PotentialVisibleSet,
        [*]const c_int,
        c_int,
        PVSType,
        *const anyopaque,
    ) Handle;

    fn frontPortalPVS(pvs: *PotentialVisibleSet) void {
        c_pvs_frontPortalPVS(pvs);
    }

    fn copyPortalPVSToMightSee(pvs: *PotentialVisibleSet) void {
        c_pvs_copyPortalPVSToMightSee(pvs);
    }

    fn passagePVS(pvs: *PotentialVisibleSet) void {
        c_pvs_passagePVS(pvs);
    }

    fn areaPVSFromPortalPVS(pvs: *PotentialVisibleSet) u32 {
        return @intCast(c_pvs_areaPVSFromPortalPVS(pvs));
    }

    pub fn setupCurrentPVS(
        pvs: *const PotentialVisibleSet,
        source_areas: []const u32,
        pvs_type: PVSType,
        render_world: *const RenderWorld,
    ) Handle {
        return c_pvs_setupCurrentPVS(
            pvs,
            @ptrCast(source_areas.ptr),
            @intCast(source_areas.len),
            pvs_type,
            @ptrCast(render_world),
        );
    }

    pub fn freeCurrentPVS(pvs: *PotentialVisibleSet, handle: Handle) void {
        if (handle.index < 0 or
            handle.index >= max_current_pvs or
            handle.handle != pvs.current_pvs[@intCast(handle.index)].handle.handle)
        {
            @panic("[PVS] invalid handle");
        }

        pvs.current_pvs[@intCast(handle.index)].handle.index = -1;
    }
};
