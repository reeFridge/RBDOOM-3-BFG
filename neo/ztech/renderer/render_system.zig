const RenderView = @import("render_world.zig").RenderView;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const RenderWorld = @import("render_world.zig");
const ViewDef = @import("common.zig").ViewDef;
const ViewEntity = @import("common.zig").ViewEntity;

const ParallelJobList = opaque {
    extern fn c_parallelJobList_wait(*ParallelJobList) void;

    pub fn wait(job_list: *ParallelJobList) void {
        c_parallelJobList_wait(job_list);
    }
};

const RenderSystem = opaque {
    extern fn c_renderSystem_isInitialized(*const RenderSystem) callconv(.C) bool;
    extern fn c_renderSystem_incLightUpdates(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_clearViewDef(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_openCommandList(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_closeCommandList(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_commandList(*const RenderSystem) callconv(.C) *anyopaque;
    extern fn c_renderSystem_incEntityReferences(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_incLightReferences(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_viewCount(*const RenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_incViewCount(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_incEntityUpdates(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_frameCount(*const RenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_uncrop(*RenderSystem) callconv(.C) void;
    extern fn c_renderSystem_cropRenderSize(*RenderSystem, c_int, c_int) callconv(.C) void;
    extern fn c_renderSystem_getCroppedViewport(*RenderSystem, *ScreenRect) callconv(.C) void;
    extern fn c_renderSystem_performResolutionScaling(*RenderSystem, *c_int, *c_int) callconv(.C) void;
    extern fn c_renderSystem_getWidth(*const RenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_getHeight(*const RenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_setPrimaryRenderView(*RenderSystem, RenderView) callconv(.C) void;
    extern fn c_renderSystem_setPrimaryWorld(*RenderSystem, *anyopaque) callconv(.C) void;
    extern fn c_renderSystem_setPrimaryView(*RenderSystem, *ViewDef) callconv(.C) void;
    extern fn c_renderSystem_getView(*RenderSystem) callconv(.C) *ViewDef;
    extern fn c_renderSystem_setView(*RenderSystem, *ViewDef) callconv(.C) void;
    extern fn c_renderSystem_getFrontEndJobList(*RenderSystem) callconv(.C) *ParallelJobList;
    extern fn c_renderSystem_getIdentitySpace(*RenderSystem) callconv(.C) *ViewEntity;

    pub fn getIdentitySpace(render_system: *RenderSystem) *ViewEntity {
        return c_renderSystem_getIdentitySpace(render_system);
    }

    pub fn getFrontEndJobList(render_system: *RenderSystem) *ParallelJobList {
        return c_renderSystem_getFrontEndJobList(render_system);
    }

    pub fn performResolutionScaling(
        render_system: *RenderSystem,
        width: *c_int,
        height: *c_int,
    ) void {
        c_renderSystem_performResolutionScaling(render_system, width, height);
    }

    pub fn setPrimaryWorld(render_system: *RenderSystem, render_world: *RenderWorld) void {
        c_renderSystem_setPrimaryWorld(render_system, @ptrCast(render_world));
    }

    pub fn setPrimaryRenderView(render_system: *RenderSystem, render_view: RenderView) void {
        c_renderSystem_setPrimaryRenderView(render_system, render_view);
    }

    pub fn setPrimaryView(render_system: *RenderSystem, view_def: *ViewDef) void {
        c_renderSystem_setPrimaryView(render_system, view_def);
    }

    pub fn setView(render_system: *RenderSystem, view_def: *ViewDef) void {
        c_renderSystem_setView(render_system, view_def);
    }

    pub fn getView(render_system: *RenderSystem) *ViewDef {
        return c_renderSystem_getView(render_system);
    }

    pub fn uncrop(render_system: *RenderSystem) void {
        c_renderSystem_uncrop(render_system);
    }

    pub fn getCroppedViewport(render_system: *RenderSystem, viewport: *ScreenRect) void {
        c_renderSystem_getCroppedViewport(render_system, viewport);
    }

    pub fn cropRenderSize(render_system: *RenderSystem, width: c_int, height: c_int) void {
        c_renderSystem_cropRenderSize(render_system, width, height);
    }

    pub fn getWidth(render_system: *const RenderSystem) c_int {
        return c_renderSystem_getWidth(render_system);
    }

    pub fn getHeight(render_system: *const RenderSystem) c_int {
        return c_renderSystem_getHeight(render_system);
    }

    pub fn incViewCount(render_system: *RenderSystem) void {
        return c_renderSystem_incViewCount(render_system);
    }

    pub fn viewCount(render_system: *const RenderSystem) c_int {
        return c_renderSystem_viewCount(render_system);
    }

    pub fn incEntityUpdates(render_system: *RenderSystem) void {
        c_renderSystem_incEntityUpdates(render_system);
    }

    pub fn frameCount(render_system: *const RenderSystem) c_int {
        return c_renderSystem_frameCount(render_system);
    }

    pub fn incEntityReferences(render_system: *RenderSystem) void {
        c_renderSystem_incEntityReferences(render_system);
    }

    pub fn incLightReferences(render_system: *RenderSystem) void {
        c_renderSystem_incLightReferences(render_system);
    }

    pub fn isInitialized(render_system: *const RenderSystem) bool {
        return c_renderSystem_isInitialized(render_system);
    }

    pub fn incLightUpdates(render_system: *RenderSystem) void {
        c_renderSystem_incLightUpdates(render_system);
    }

    pub fn clearViewDef(render_system: *RenderSystem) void {
        c_renderSystem_clearViewDef(render_system);
    }

    pub fn openCommandList(render_system: *RenderSystem) void {
        c_renderSystem_openCommandList(render_system);
    }

    pub fn closeCommandList(render_system: *RenderSystem) void {
        c_renderSystem_closeCommandList(render_system);
    }

    pub fn commandList(render_system: *const RenderSystem) *anyopaque {
        return c_renderSystem_commandList(render_system);
    }
};

pub const instance = @extern(*RenderSystem, .{ .name = "tr" });
