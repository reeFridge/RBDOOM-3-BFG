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

const idRenderSystem = opaque {
    extern fn c_renderSystem_isInitialized(*const idRenderSystem) callconv(.C) bool;
    extern fn c_renderSystem_incLightUpdates(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_clearViewDef(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_openCommandList(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_closeCommandList(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_commandList(*idRenderSystem) callconv(.C) *nvrhi.ICommandList;
    extern fn c_renderSystem_incEntityReferences(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_incLightReferences(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_viewCount(*const idRenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_incViewCount(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_incEntityUpdates(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_frameCount(*const idRenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_uncrop(*idRenderSystem) callconv(.C) void;
    extern fn c_renderSystem_cropRenderSize(*idRenderSystem, c_int, c_int) callconv(.C) void;
    extern fn c_renderSystem_getCroppedViewport(*idRenderSystem, *ScreenRect) callconv(.C) void;
    extern fn c_renderSystem_performResolutionScaling(*idRenderSystem, *c_int, *c_int) callconv(.C) void;
    extern fn c_renderSystem_getWidth(*const idRenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_getHeight(*const idRenderSystem) callconv(.C) c_int;
    extern fn c_renderSystem_setPrimaryRenderView(*idRenderSystem, RenderView) callconv(.C) void;
    extern fn c_renderSystem_setPrimaryWorld(*idRenderSystem, *anyopaque) callconv(.C) void;
    extern fn c_renderSystem_setPrimaryView(*idRenderSystem, *ViewDef) callconv(.C) void;
    extern fn c_renderSystem_getView(*idRenderSystem) callconv(.C) *ViewDef;
    extern fn c_renderSystem_setView(*idRenderSystem, *ViewDef) callconv(.C) void;
    extern fn c_renderSystem_getFrontEndJobList(*idRenderSystem) callconv(.C) *ParallelJobList;
    extern fn c_renderSystem_getIdentitySpace(*idRenderSystem) callconv(.C) *ViewEntity;

    pub fn getIdentitySpace(render_system: *idRenderSystem) *ViewEntity {
        return c_renderSystem_getIdentitySpace(render_system);
    }

    pub fn getFrontEndJobList(render_system: *idRenderSystem) *ParallelJobList {
        return c_renderSystem_getFrontEndJobList(render_system);
    }

    pub fn performResolutionScaling(
        render_system: *idRenderSystem,
        width: *c_int,
        height: *c_int,
    ) void {
        c_renderSystem_performResolutionScaling(render_system, width, height);
    }

    pub fn setPrimaryWorld(render_system: *idRenderSystem, render_world: *RenderWorld) void {
        c_renderSystem_setPrimaryWorld(render_system, @ptrCast(render_world));
    }

    pub fn setPrimaryRenderView(render_system: *idRenderSystem, render_view: RenderView) void {
        c_renderSystem_setPrimaryRenderView(render_system, render_view);
    }

    pub fn setPrimaryView(render_system: *idRenderSystem, view_def: *ViewDef) void {
        c_renderSystem_setPrimaryView(render_system, view_def);
    }

    pub fn setView(render_system: *idRenderSystem, view_def: *ViewDef) void {
        c_renderSystem_setView(render_system, view_def);
    }

    pub fn getView(render_system: *idRenderSystem) *ViewDef {
        return c_renderSystem_getView(render_system);
    }

    pub fn uncrop(render_system: *idRenderSystem) void {
        c_renderSystem_uncrop(render_system);
    }

    pub fn getCroppedViewport(render_system: *idRenderSystem, viewport: *ScreenRect) void {
        c_renderSystem_getCroppedViewport(render_system, viewport);
    }

    pub fn cropRenderSize(render_system: *idRenderSystem, width: c_int, height: c_int) void {
        c_renderSystem_cropRenderSize(render_system, width, height);
    }

    pub fn getWidth(render_system: *const idRenderSystem) c_int {
        return c_renderSystem_getWidth(render_system);
    }

    pub fn getHeight(render_system: *const idRenderSystem) c_int {
        return c_renderSystem_getHeight(render_system);
    }

    pub fn incViewCount(render_system: *idRenderSystem) void {
        return c_renderSystem_incViewCount(render_system);
    }

    pub fn viewCount(render_system: *const idRenderSystem) c_int {
        return c_renderSystem_viewCount(render_system);
    }

    pub fn incEntityUpdates(render_system: *idRenderSystem) void {
        c_renderSystem_incEntityUpdates(render_system);
    }

    pub fn frameCount(render_system: *const idRenderSystem) c_int {
        return c_renderSystem_frameCount(render_system);
    }

    pub fn incEntityReferences(render_system: *idRenderSystem) void {
        c_renderSystem_incEntityReferences(render_system);
    }

    pub fn incLightReferences(render_system: *idRenderSystem) void {
        c_renderSystem_incLightReferences(render_system);
    }

    pub fn isInitialized(render_system: *const idRenderSystem) bool {
        return c_renderSystem_isInitialized(render_system);
    }

    pub fn incLightUpdates(render_system: *idRenderSystem) void {
        c_renderSystem_incLightUpdates(render_system);
    }

    pub fn clearViewDef(render_system: *idRenderSystem) void {
        c_renderSystem_clearViewDef(render_system);
    }

    pub fn openCommandList(render_system: *idRenderSystem) void {
        c_renderSystem_openCommandList(render_system);
    }

    pub fn closeCommandList(render_system: *idRenderSystem) void {
        c_renderSystem_closeCommandList(render_system);
    }

    pub fn commandList(render_system: *idRenderSystem) *nvrhi.ICommandList {
        return c_renderSystem_commandList(render_system);
    }
};

const idtech_instance = @extern(*idRenderSystem, .{ .name = "tr" });

const nvrhi = @import("nvrhi.zig");

const PerformanceCounters = struct {
    c_box_cull_in: c_int,
    c_box_cull_out: c_int,
    c_createInteractions: c_int, // number of calls to idInteraction::CreateInteraction
    c_createShadowVolumes: c_int,
    c_generateMd5: c_int,
    c_entityDefCallbacks: c_int,
    c_alloc: c_int, // counts for R_StaticAllc/R_StaticFree
    c_free: c_int,
    c_visibleViewEntities: c_int,
    c_shadowViewEntities: c_int,
    c_viewLights: c_int,
    c_numViews: c_int, // number of total views rendered
    c_deformedSurfaces: c_int, // idMD5Mesh::GenerateSurface
    c_deformedVerts: c_int, // idMD5Mesh::GenerateSurface
    c_deformedIndexes: c_int, // idMD5Mesh::GenerateSurface
    c_tangentIndexes: c_int, // R_DeriveTangents()
    c_entityUpdates: c_int,
    c_lightUpdates: c_int,
    c_envprobeUpdates: c_int,
    c_entityReferences: c_int,
    c_lightReferences: c_int,
    c_guiSurfs: c_int,
    frontEndMicroSec: c_ulonglong, // sum of time in all RE_RenderScene's in a frame
};

const Vec4 = @import("../math/vector.zig").Vec4;
const Mat3 = @import("../math/matrix.zig").Mat3;
const std = @import("std");
const Material = @import("material.zig").Material;
const GuiModel = @import("gui_model.zig").GuiModel;
const Font = @import("font.zig").Font;
const SurfaceTriangles = @import("model.zig").SurfaceTriangles;
const CalcEnvprobeParams = @import("common.zig").CalcEnvprobeParams;
const CalcLightGridPointParams = @import("common.zig").CalcLightGridPointParams;
const RenderBackend = @import("render_backend.zig").RenderBackend;
const MAX_RENDER_CROPS: usize = 8;

const RenderSystem = @This();

command_list: nvrhi.CommandListHandle = .{ .ptr_ = null },
registered: bool = false,
taking_screenshot: bool = false,
taking_envprobe: bool = false,
// incremented every frame
frame_count: usize = 0,
// incremented every view (twice a scene if subviewed)
view_count: usize = 0,
// shader time for all non-world 2D rendering
frame_shader_time: f32 = 0,
// used for "ambient bump mapping"
ambient_light_vector: Vec4(f32) = .{},
worlds: std.ArrayList(*RenderWorld) = undefined,

// for console commands
primary_world: ?*RenderWorld = null,
primary_render_view: ?RenderView = null,
primary_view: ?*ViewDef = null,

white_material: ?*const Material = null,
char_set_material: ?*const Material = null,
img_gui_material: ?*const Material = null,
default_point_light: ?*const Material = null,
default_projected_light: ?*const Material = null,
default_material: ?*const Material = null,
view_def: ?*ViewDef = null,
perf_counters: PerformanceCounters = std.mem.zeroes(PerformanceCounters),
// can use if we don't know viewDef->worldSpace is valid
identity_space: ViewEntity = std.mem.zeroes(ViewEntity),
render_crops: [MAX_RENDER_CROPS]ScreenRect = std.mem.zeroes([MAX_RENDER_CROPS]ScreenRect),
current_render_crop: usize = 0,

// GUI drawing variables for surface creation

// to prevent infinite overruns
gui_recursion_level: usize = 0,
current_color_native_bytes_order: u32 = 0xFFFFFFFF,
current_gl_state: u64 = 0,
gui_model: ?*GuiModel = null,
fonts: std.ArrayList(*Font) = undefined,
gamma_table: [256]c_ushort = std.mem.zeroes([256]c_ushort),
cube_axis: [6]Mat3(f32) = std.mem.zeroes([6]Mat3(f32)),
unit_square_triangles: ?*SurfaceTriangles = null,
zero_one_cube_triangles: ?*SurfaceTriangles = null,
zero_one_sphere_triangles: ?*SurfaceTriangles = null,
test_image_triangles: ?*SurfaceTriangles = null,
front_end_job_list: ?*ParallelJobList = null,
envprobe_job_list: ?*ParallelJobList = null,
envprobe_jobs: std.ArrayList(*CalcEnvprobeParams) = undefined,
light_grid_jobs: std.ArrayList(*CalcLightGridPointParams) = undefined,
backend: RenderBackend = std.mem.zeroes(RenderBackend),
initialized: bool = false,
omit_swap_buffers: bool = false,

pub var instance = RenderSystem{};

pub fn init(render_system: *RenderSystem, allocator: std.mem.Allocator) error{OutOfMemory}!void {
    render_system.view_count = 1;
    render_system.worlds = std.ArrayList(*RenderWorld).init(allocator);
    render_system.fonts = std.ArrayList(*Font).init(allocator);
    render_system.envprobe_jobs = std.ArrayList(*CalcEnvprobeParams).init(allocator);
    render_system.light_grid_jobs = std.ArrayList(*CalcLightGridPointParams).init(allocator);

    render_system.initialized = true;
}

pub fn deinit(render_system: *RenderSystem) void {
    render_system.initialized = false;

    render_system.worlds.deinit();
    render_system.fonts.deinit();
    render_system.envprobe_jobs.deinit();
    render_system.light_grid_jobs.deinit();
}

pub fn getIdentitySpace(_: *RenderSystem) *ViewEntity {
    return idtech_instance.getIdentitySpace();
}

pub fn getFrontEndJobList(_: *RenderSystem) *ParallelJobList {
    return idtech_instance.getFrontEndJobList();
}

pub fn performResolutionScaling(
    _: *RenderSystem,
    width: *c_int,
    height: *c_int,
) void {
    idtech_instance.performResolutionScaling(width, height);
}

pub fn setPrimaryWorld(_: *RenderSystem, render_world: *RenderWorld) void {
    idtech_instance.setPrimaryWorld(render_world);
}

pub fn setPrimaryRenderView(_: *RenderSystem, render_view: RenderView) void {
    idtech_instance.setPrimaryRenderView(render_view);
}

pub fn setPrimaryView(_: *RenderSystem, view_def: *ViewDef) void {
    idtech_instance.setPrimaryView(view_def);
}

pub fn setView(_: *RenderSystem, view_def: *ViewDef) void {
    idtech_instance.setView(view_def);
}

pub fn getView(_: *RenderSystem) *ViewDef {
    return idtech_instance.getView();
}

pub fn uncrop(_: *RenderSystem) void {
    idtech_instance.uncrop();
}

pub fn getCroppedViewport(_: *RenderSystem, viewport: *ScreenRect) void {
    idtech_instance.getCroppedViewport(viewport);
}

pub fn cropRenderSize(_: *RenderSystem, width: c_int, height: c_int) void {
    idtech_instance.cropRenderSize(width, height);
}

pub fn getWidth(_: *const RenderSystem) c_int {
    return idtech_instance.getWidth();
}

pub fn getHeight(_: *const RenderSystem) c_int {
    return idtech_instance.getHeight();
}

pub fn incViewCount(_: *RenderSystem) void {
    return idtech_instance.incViewCount();
}

pub fn viewCount(_: *const RenderSystem) c_int {
    return idtech_instance.viewCount();
}

pub fn incEntityUpdates(_: *RenderSystem) void {
    idtech_instance.incEntityUpdates();
}

pub fn frameCount(_: *const RenderSystem) c_int {
    return idtech_instance.frameCount();
}

pub fn incEntityReferences(_: *RenderSystem) void {
    idtech_instance.incEntityReferences();
}

pub fn incLightReferences(_: *RenderSystem) void {
    idtech_instance.incLightReferences();
}

pub fn isInitialized(_: *const RenderSystem) bool {
    return idtech_instance.isInitialized();
}

pub fn incLightUpdates(_: *RenderSystem) void {
    idtech_instance.incLightUpdates();
}

pub fn clearViewDef(_: *RenderSystem) void {
    idtech_instance.clearViewDef();
}

pub fn openCommandList(_: *RenderSystem) void {
    idtech_instance.openCommandList();
}

pub fn closeCommandList(_: *RenderSystem) void {
    idtech_instance.closeCommandList();
}

pub fn commandList(_: *RenderSystem) *nvrhi.ICommandList {
    return idtech_instance.commandList();
}
