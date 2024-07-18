const global = @import("../global.zig");
const RenderWorld = @import("render_world.zig");

export fn ztech_renderWorld_numPortalsInArea(rw: *anyopaque, area_index: usize) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return render_world.numPortalsInArea(area_index) catch {
        @panic("ztech_rednerWorld: bad area_index");
    };
}

export fn ztech_allocRenderWorld(rw: **anyopaque) callconv(.C) bool {
    const allocator = global.gpa.allocator();
    const render_world_ptr = allocator.create(RenderWorld) catch
        return false;

    render_world_ptr.* = RenderWorld.init(allocator) catch {
        allocator.destroy(render_world_ptr);
        return false;
    };

    rw.* = @ptrCast(render_world_ptr);

    return true;
}

export fn ztech_freeRenderWorld(rw: *anyopaque) callconv(.C) void {
    const allocator = global.gpa.allocator();
    const render_world_ptr: *RenderWorld = @alignCast(@ptrCast(rw));
    render_world_ptr.deinit();
    allocator.destroy(render_world_ptr);
}

export fn ztech_renderWorld_numAreas(rw: *anyopaque) callconv(.C) usize {
    const render_world: *RenderWorld = @alignCast(@ptrCast(rw));

    return if (render_world.area_nodes) |area_nodes|
        area_nodes.len
    else
        0;
}
