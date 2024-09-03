const RenderView = @import("render_world.zig").RenderView;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const RenderWorld = @import("render_world.zig");
const ViewDef = @import("common.zig").ViewDef;
const ViewEntity = @import("common.zig").ViewEntity;
const ParallelJobList = @import("parallel_job_list.zig").ParallelJobList;
const VertexCache = @import("vertex_cache.zig");
const DrawSurface = @import("common.zig").DrawSurface;
const ResolutionScale = @import("resolution_scale.zig");

pub const VENDOR_NVIDIA: c_int = 0;
pub const VENDOR_AMD: c_int = 1;
pub const VENDOR_INTEL: c_int = 2;
pub const VENDOR_APPLE: c_int = 3;
pub const graphicsVendor_t = c_int;

pub const STEREO3D_OFF: c_int = 0;
pub const STEREO3D_SIDE_BY_SIDE_COMPRESSED: c_int = 1;
pub const STEREO3D_TOP_AND_BOTTOM_COMPRESSED: c_int = 2;
pub const STEREO3D_SIDE_BY_SIDE: c_int = 3;
pub const STEREO3D_INTERLACED: c_int = 4;
pub const STEREO3D_QUAD_BUFFER: c_int = 5;
pub const STEREO3D_HDMI_720: c_int = 6;
pub const stereo3DMode_t = c_int;

pub const STEREO_DEPTH_TYPE_NONE: c_int = 0;
pub const STEREO_DEPTH_TYPE_NEAR: c_int = 1;
pub const STEREO_DEPTH_TYPE_MID: c_int = 2;
pub const STEREO_DEPTH_TYPE_FAR: c_int = 3;
pub const sereoDepthType_t = c_int;

pub const glconfig_t = extern struct {
    vendor: graphicsVendor_t,
    uniformBufferOffsetAlignment: c_int,
    timerQueryAvailable: bool,
    stereo3Dmode: stereo3DMode_t,
    nativeScreenWidth: c_int,
    nativeScreenHeight: c_int,
    displayFrequency: c_int,
    isFullscreen: c_int,
    isStereoPixelFormat: bool,
    stereoPixelFormatAvailable: bool,
    multisamples: c_int,
    physicalScreenWidthInCentimeters: f32,
    pixelAspect: f32,
};

pub const glConfig = @extern(*glconfig_t, .{ .name = "glConfig" });

const nvrhi = @import("nvrhi.zig");

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

inline fn initCubemapAxis() [6]Mat3(f32) {
    var axis = std.mem.zeroes([6]Mat3(f32));

    // +X
    axis[0].v[0].v[0] = 1;
    axis[0].v[1].v[2] = 1;
    axis[0].v[2].v[1] = 1;

    // -X
    axis[1].v[0].v[0] = -1;
    axis[1].v[1].v[2] = -1;
    axis[1].v[2].v[1] = 1;

    // +Y
    axis[2].v[0].v[1] = 1;
    axis[2].v[1].v[0] = -1;
    axis[2].v[2].v[2] = -1;

    // -Y
    axis[3].v[0].v[1] = -1;
    axis[3].v[1].v[0] = -1;
    axis[3].v[2].v[2] = 1;

    // +Z
    axis[4].v[0].v[2] = 1;
    axis[4].v[1].v[0] = -1;
    axis[4].v[2].v[1] = 1;

    // -Z
    axis[5].v[0].v[2] = -1;
    axis[5].v[1].v[0] = 1;
    axis[5].v[2].v[1] = 1;

    return axis;
}

inline fn initIdentityMatrix() [16]f32 {
    var identity = std.mem.zeroes([16]f32);
    identity[0 * 4 + 0] = 1.0;
    identity[1 * 4 + 1] = 1.0;
    identity[2 * 4 + 2] = 1.0;
    return identity;
}

inline fn initAmbientLightVector() Vec4(f32) {
    return .{ .v = .{
        0.5,
        0.5 - 0.385,
        0.8925,
        1.0,
    } };
}

const sys_types = @import("../sys/types.zig");
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const Vec3 = @import("../math/vector.zig").Vec3;
const CVec3 = @import("../math/vector.zig").CVec3;

const TestImageTris = struct {
    const num_indexes = 6;
    const num_verts = 4;

    fn makeVerts(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const verts = tri.allocVertices(allocator, num_verts) catch unreachable;

        for (verts) |*vert| {
            vert.* = std.mem.zeroes(DrawVertex);
        }

        verts[1].xyz.x = 1.0;
        verts[1].xyz.y = 0.0;
        verts[1].setTexCoord(1.0, 0.0);

        verts[2].xyz.x = 1.0;
        verts[2].xyz.y = 1.0;
        verts[2].setTexCoord(1.0, 1.0);

        verts[3].xyz.x = 0.0;
        verts[3].xyz.y = 1.0;
        verts[3].setTexCoord(0.0, 1.0);

        inline for (0..num_verts) |i| {
            verts[i].color = [1]u8{0xFF} ** 4;
        }
    }

    fn makeIndexes(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const indexes = tri.allocIndexes(allocator, num_indexes) catch unreachable;

        const indexes_: [num_indexes]sys_types.TriIndex = .{ 3, 0, 2, 2, 0, 1 };
        for (indexes, indexes_) |*index, temp| {
            index.* = temp;
        }
    }
};

const FullScreenTris = struct {
    const num_indexes = 6;
    const num_verts = 4;

    fn makeVerts(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const verts = tri.allocVertices(allocator, num_verts) catch unreachable;

        for (verts) |*vert| {
            vert.* = std.mem.zeroes(DrawVertex);
        }

        verts[0].xyz.x = -1.0;
        verts[0].xyz.y = 1.0;
        verts[0].setTexCoord(0.0, 1.0);

        verts[1].xyz.x = 1.0;
        verts[1].xyz.y = 1.0;
        verts[1].setTexCoord(1.0, 1.0);

        verts[2].xyz.x = 1.0;
        verts[2].xyz.y = -1.0;
        verts[2].setTexCoord(1.0, 0.0);

        verts[3].xyz.x = -1.0;
        verts[3].xyz.y = -1.0;
        verts[3].setTexCoord(0.0, 0.0);

        inline for (0..num_verts) |i| {
            verts[i].color = [1]u8{0xFF} ** 4;
        }
    }

    fn makeIndexes(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const indexes = tri.allocIndexes(allocator, num_indexes) catch unreachable;

        const indexes_: [num_indexes]sys_types.TriIndex = .{ 3, 0, 2, 2, 0, 1 };
        for (indexes, indexes_) |*index, temp| {
            index.* = temp;
        }
    }
};

const ZeroOneCubeTris = struct {
    const num_indexes = 36;
    const num_verts = 8;

    fn makeVerts(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const verts = tri.allocVertices(allocator, num_verts) catch unreachable;

        for (verts) |*vert| {
            vert.* = std.mem.zeroes(DrawVertex);
        }

        const low: f32 = 0;
        const high: f32 = 1;

        const center = Vec3(f32){ .v = .{ 0, 0, 0 } };
        const mx = Vec3(f32){ .v = .{ low, 0, 0 } };
        const px = Vec3(f32){ .v = .{ high, 0, 0 } };
        const my = Vec3(f32){ .v = .{ 0, low, 0 } };
        const py = Vec3(f32){ .v = .{ 0, high, 0 } };
        const mz = Vec3(f32){ .v = .{ 0, 0, low } };
        const pz = Vec3(f32){ .v = .{ 0, 0, high } };

        verts[0].xyz = CVec3.fromVec3f(center.add(mx).add(my).add(mz));
        verts[1].xyz = CVec3.fromVec3f(center.add(px).add(my).add(mz));
        verts[2].xyz = CVec3.fromVec3f(center.add(px).add(py).add(mz));
        verts[3].xyz = CVec3.fromVec3f(center.add(mx).add(py).add(mz));
        verts[4].xyz = CVec3.fromVec3f(center.add(mx).add(my).add(pz));
        verts[5].xyz = CVec3.fromVec3f(center.add(px).add(my).add(pz));
        verts[6].xyz = CVec3.fromVec3f(center.add(px).add(py).add(pz));
        verts[7].xyz = CVec3.fromVec3f(center.add(mx).add(py).add(pz));

        inline for (0..num_verts) |i| {
            verts[i].color = [1]u8{0xFF} ** 4;
        }
    }

    fn makeIndexes(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const indexes = tri.allocIndexes(allocator, num_indexes) catch unreachable;

        for (indexes) |*index| {
            index.* = 0;
        }

        // bottom
        indexes[0 * 3 + 0] = 2;
        indexes[0 * 3 + 1] = 3;
        indexes[0 * 3 + 2] = 0;
        indexes[1 * 3 + 0] = 1;
        indexes[1 * 3 + 1] = 2;
        indexes[1 * 3 + 2] = 0;
        // back
        indexes[2 * 3 + 0] = 5;
        indexes[2 * 3 + 1] = 1;
        indexes[2 * 3 + 2] = 0;
        indexes[3 * 3 + 0] = 4;
        indexes[3 * 3 + 1] = 5;
        indexes[3 * 3 + 2] = 0;
        // left
        indexes[4 * 3 + 0] = 7;
        indexes[4 * 3 + 1] = 4;
        indexes[4 * 3 + 2] = 0;
        indexes[5 * 3 + 0] = 3;
        indexes[5 * 3 + 1] = 7;
        indexes[5 * 3 + 2] = 0;
        // righ
        indexes[6 * 3 + 0] = 1;
        indexes[6 * 3 + 1] = 5;
        indexes[6 * 3 + 2] = 6;
        indexes[7 * 3 + 0] = 2;
        indexes[7 * 3 + 1] = 1;
        indexes[7 * 3 + 2] = 6;
        // fron
        indexes[8 * 3 + 0] = 3;
        indexes[8 * 3 + 1] = 2;
        indexes[8 * 3 + 2] = 6;
        indexes[9 * 3 + 0] = 7;
        indexes[9 * 3 + 1] = 3;
        indexes[9 * 3 + 2] = 6;
        // top
        indexes[10 * 3 + 0] = 4;
        indexes[10 * 3 + 1] = 7;
        indexes[10 * 3 + 2] = 6;
        indexes[11 * 3 + 0] = 5;
        indexes[11 * 3 + 1] = 4;
        indexes[11 * 3 + 2] = 6;
    }
};

const ZeroOneSphereTris = struct {
    const radius: f32 = 1.0;
    const rings = 20;
    const sectors = 20;
    const num_verts = rings * sectors;
    const num_indexes = ((rings - 1) * sectors) * 6;

    fn makeIndexes(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const indexes = tri.allocIndexes(allocator, num_indexes) catch unreachable;

        for (indexes) |*index| {
            index.* = 0;
        }

        var num_tris: usize = 0;
        for (0..rings) |r| {
            for (0..sectors) |s| {
                if (r < (rings - 1)) {
                    const cur_row = r * sectors;
                    const next_row = (r + 1) * sectors;
                    const next_s = (s + 1) % sectors;

                    indexes[(num_tris * 3) + 2] = @intCast(cur_row + s);
                    indexes[(num_tris * 3) + 1] = @intCast(next_row + s);
                    indexes[(num_tris * 3) + 0] = @intCast(next_row + next_s);

                    num_tris += 1;

                    indexes[(num_tris * 3) + 2] = @intCast(cur_row + s);
                    indexes[(num_tris * 3) + 1] = @intCast(next_row + next_s);
                    indexes[(num_tris * 3) + 0] = @intCast(cur_row + next_s);

                    num_tris += 1;
                }
            }
        }
    }

    fn makeVerts(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
        const verts = tri.allocVertices(allocator, num_verts) catch unreachable;

        for (verts) |*vert| {
            vert.* = std.mem.zeroes(DrawVertex);
        }

        const R: f32 = 1.0 / @as(f32, @floatFromInt(rings - 1));
        const S: f32 = 1.0 / @as(f32, @floatFromInt(sectors - 1));

        var num_verts_: usize = 0;
        for (0..rings) |r| {
            for (0..sectors) |s| {
                const half_pi = 0.5 * std.math.pi;
                const sf: f32 = @floatFromInt(s);
                const rf: f32 = @floatFromInt(r);
                const y = @sin(-half_pi + std.math.pi * rf * R);
                const x = @cos(2 * std.math.pi * sf * S) * @sin(std.math.pi * rf * R);
                const z = @sin(2 * std.math.pi * sf * S) * @sin(std.math.pi * rf * R);

                verts[num_verts_].setTexCoord(sf * S, rf * R);
                verts[num_verts_].xyz = .{
                    .x = x * radius,
                    .y = y * radius,
                    .z = z * radius,
                };
                verts[num_verts_].setNormal(x, y, z);
                verts[num_verts_].color = [1]u8{0xFF} ** 4;

                num_verts_ += 1;
            }
        }
    }
};

fn initGlobalTris(params: anytype, allocator: std.mem.Allocator) *SurfaceTriangles {
    var tri = SurfaceTriangles.init(allocator) catch unreachable;
    tri.numVerts = params.num_verts;
    tri.numIndexes = params.num_indexes;
    params.makeIndexes(tri, allocator);
    params.makeVerts(tri, allocator);

    return tri;
}

fn deinitGlobalTris(tri: *SurfaceTriangles, allocator: std.mem.Allocator) void {
    tri.deinit(allocator);
}

command_list: nvrhi.CommandListHandle = .{},
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
ambient_light_vector: Vec4(f32) = initAmbientLightVector(),
worlds: std.ArrayList(*RenderWorld) = undefined,

// for console commands
primary_world: ?*RenderWorld = null,
primary_render_view: ?RenderView = null,
primary_view: ?*ViewDef = null,

white_material: ?*const Material = null,
char_set_material: ?*const Material = null,
imgui_material: ?*const Material = null,
default_point_light: ?*const Material = null,
default_projected_light: ?*const Material = null,
default_material: *const Material = undefined,
view_def: ?*ViewDef = null,
// can use if we don't know viewDef->worldSpace is valid
identity_space: [16]f32 = initIdentityMatrix(),
render_crops: [MAX_RENDER_CROPS]ScreenRect = std.mem.zeroes([MAX_RENDER_CROPS]ScreenRect),
current_render_crop: usize = 0,

// GUI drawing variables for surface creation

// to prevent infinite overruns
gui_recursion_level: usize = 0,
current_color_native_bytes_order: u32 = 0xFFFFFFFF,
current_gl_state: u64 = 0,
gui_model: *GuiModel = undefined,
fonts: std.ArrayList(*Font) = undefined,
gamma_table: [256]c_ushort = std.mem.zeroes([256]c_ushort),
cube_axis: [6]Mat3(f32) = initCubemapAxis(),

unit_square_triangles: *SurfaceTriangles = undefined,
zero_one_cube_triangles: *SurfaceTriangles = undefined,
zero_one_sphere_triangles: *SurfaceTriangles = undefined,
test_image_triangles: *SurfaceTriangles = undefined,

unit_square_surface_: DrawSurface = std.mem.zeroes(DrawSurface),
zero_one_cube_surface_: DrawSurface = std.mem.zeroes(DrawSurface),
zero_one_sphere_surface_: DrawSurface = std.mem.zeroes(DrawSurface),
test_image_surface_: DrawSurface = std.mem.zeroes(DrawSurface),

front_end_job_list: *ParallelJobList = undefined,
envprobe_job_list: *ParallelJobList = undefined,
envprobe_jobs: std.ArrayList(*CalcEnvprobeParams) = undefined,
light_grid_jobs: std.ArrayList(*CalcLightGridPointParams) = undefined,
//backend: RenderBackend = std.mem.zeroes(RenderBackend),
initialized: bool = false,
backend_initialized: bool = false,
omit_swap_buffers: bool = false,

pub var instance = RenderSystem{};
export var backend_ = std.mem.zeroes(RenderBackend);
//pub var backend_ = std.mem.zeroes(RenderBackend);

const DeviceManager = @import("../sys/device_manager.zig");
const ImageManager = @import("image_manager.zig");
const FrameData = @import("frame_data.zig");
const RenderModelManager = @import("render_model_manager.zig");
const ParallelJobManager = @import("parallel_job_manager.zig");
const JobListId = @import("parallel_job_list.zig").JobListId;
const JobListPriority = @import("parallel_job_list.zig").JobListPriority;
const global = @import("../global.zig");

pub fn initBackend(render_system: *RenderSystem, allocator: std.mem.Allocator) error{OutOfMemory}!void {
    if (render_system.initialized) return;
    // also inits FrameData
    // and calls to ztech_renderSystem_setBackendInitialized()
    try backend_.init(allocator);

    const device = DeviceManager.instance().getDevice();

    const command_list_ptr = if (render_system.command_list.ptr_) |ptr|
        ptr
    else command_list: {
        const handle = device.createCommandList(.{});
        render_system.command_list = handle;

        break :command_list handle.ptr_ orelse @panic("Fails to create command-list!");
    };

    command_list_ptr.open();
    ImageManager.instance.reloadImages(true, command_list_ptr);
    command_list_ptr.close();
    device.executeCommandList(command_list_ptr);
}

extern fn c_renderSystem_initColorMappings([*]c_ushort) callconv(.C) void;
extern fn c_renderSystem_initImgui(?*const Material) callconv(.C) void;
const Framebuffer = @import("framebuffer.zig");

pub fn createRenderWorld(render_system: *RenderSystem, allocator: std.mem.Allocator) !*RenderWorld {
    if (!render_system.initialized) unreachable;

    const render_world_ptr = try allocator.create(RenderWorld);
    errdefer allocator.destroy(render_world_ptr);
    render_world_ptr.* = try RenderWorld.init(allocator);
    errdefer render_world_ptr.deinit();

    try render_system.worlds.append(render_world_ptr);

    return render_world_ptr;
}

pub fn destroyRenderWorld(
    render_system: *RenderSystem,
    allocator: std.mem.Allocator,
    world: *RenderWorld,
) void {
    if (!render_system.initialized) unreachable;

    const index = for (render_system.worlds.items, 0..) |world_ptr, i| {
        if (@intFromPtr(world) == @intFromPtr(world_ptr)) {
            break i;
        }
    } else @panic("World is not registered");

    _ = render_system.worlds.swapRemove(index);

    world.deinit();
    allocator.destroy(world);
}

pub fn init(render_system: *RenderSystem, allocator: std.mem.Allocator) error{OutOfMemory}!void {
    render_system.view_count = 1;
    render_system.worlds = std.ArrayList(*RenderWorld).init(allocator);
    render_system.fonts = std.ArrayList(*Font).init(allocator);
    render_system.envprobe_jobs = std.ArrayList(*CalcEnvprobeParams).init(allocator);
    render_system.light_grid_jobs = std.ArrayList(*CalcLightGridPointParams).init(allocator);

    // Must be allocated on the heap!
    render_system.unit_square_triangles = initGlobalTris(FullScreenTris, allocator);
    render_system.zero_one_cube_triangles = initGlobalTris(ZeroOneCubeTris, allocator);
    render_system.zero_one_sphere_triangles = initGlobalTris(ZeroOneSphereTris, allocator);
    render_system.test_image_triangles = initGlobalTris(TestImageTris, allocator);

    // TODO: UpdateStereo3DMode();
    // TODO: idCinematic::InitCinematic();
    try FrameData.init(allocator);
    var gui_model = GuiModel.heapCreate();
    gui_model.clear();
    render_system.gui_model = gui_model;

    ImageManager.instance.init();
    Framebuffer.init();

    // init materials
    render_system.default_material = global.DeclManager.findMaterial("_default") orelse
        @panic("Default Material not found!");
    render_system.default_point_light = global.DeclManager.findMaterialDefault("lights/defaultPointLight");
    render_system.default_projected_light = global.DeclManager.findMaterialDefault("lights/defaultProjectedLight");
    render_system.white_material = global.DeclManager.findMaterial("_white");
    render_system.char_set_material = global.DeclManager.findMaterial("textures/bigchars");
    render_system.imgui_material = global.DeclManager.findMaterialDefault("_imguiFont");

    c_renderSystem_initImgui(render_system.imgui_material);

    c_renderSystem_initColorMappings((&render_system.gamma_table).ptr);

    RenderModelManager.instance.init();

    render_system.front_end_job_list = ParallelJobManager.instance.allocJobList(
        JobListId.JOBLIST_RENDERER_FRONTEND,
        JobListPriority.JOBLIST_PRIORITY_MEDIUM,
        2048,
        0,
        null,
    );

    render_system.envprobe_job_list = ParallelJobManager.instance.allocJobList(
        JobListId.JOBLIST_UTILITY,
        JobListPriority.JOBLIST_PRIORITY_MEDIUM,
        2048,
        0,
        null,
    );

    render_system.initialized = true;

    // For VULKAN only!
    render_system.omit_swap_buffers = true;
    _ = render_system.swapCommandBuffers();
}

pub fn deinit(render_system: *RenderSystem, allocator: std.mem.Allocator) void {
    for (render_system.worlds.items) |world_ptr| {
        allocator.destroy(world_ptr);
        world_ptr.deinit();
    }
    render_system.worlds.deinit();
    render_system.fonts.deinit(); // destroy items
    render_system.envprobe_jobs.deinit();
    render_system.light_grid_jobs.deinit();

    deinitGlobalTris(render_system.unit_square_triangles, allocator);
    deinitGlobalTris(render_system.zero_one_cube_triangles, allocator);
    deinitGlobalTris(render_system.zero_one_sphere_triangles, allocator);
    deinitGlobalTris(render_system.test_image_triangles, allocator);

    ImageManager.instance.purgeAllImages();
    RenderModelManager.instance.shutdown();
    ImageManager.instance.shutdown();
    Framebuffer.shutdown();
    render_system.gui_model.heapDestroy();
    FrameData.shutdown(allocator);

    const device = DeviceManager.instance().getDevice();
    device.waitForIdle();

    VertexCache.instance.shutdown();

    ParallelJobManager.instance.freeJobList(render_system.envprobe_job_list);
    ParallelJobManager.instance.freeJobList(render_system.front_end_job_list);

    render_system.command_list.deinit();

    backend_.shutdown();

    render_system.* = RenderSystem{};
}

pub fn swapCommandBuffers(render_system: *RenderSystem) ?*FrameData.EmptyCommand {
    render_system.finishRendering();

    return render_system.finishCommandBuffers();
}

pub fn finishRendering(render_system: *RenderSystem) void {
    if (!render_system.initialized) return;

    // keep capturing envprobes completely in the background
    // and only update the screen when we update the progress bar in the console
    if (!render_system.omit_swap_buffers) {
        // wait for our fence to hit, which means the swap has actually happened
        // We must do this before clearing any resources the GPU may be using
        backend_.swapBuffersBlocking();
    }

    backend_.checkCVars();
    Framebuffer.checkFramebuffers();
}

extern fn R_InitDrawSurfFromTri(*DrawSurface, *SurfaceTriangles, *nvrhi.ICommandList) callconv(.C) void;
extern fn Sys_Milliseconds() callconv(.C) c_int;

pub fn finishCommandBuffers(render_system: *RenderSystem) ?*FrameData.EmptyCommand {
    if (!render_system.initialized) return null;

    render_system.gui_model.emitFullScreen(null);
    render_system.gui_model.clear();

    // unmap the buffer objects so they can be used by the GPU
    VertexCache.instance.beginBackend();

    // save off this command buffer
    const command_buffer_head = if (FrameData.frame_data) |frame_data|
        frame_data.cmdHead
    else
        null;

    // copy the code-used drawsurfs that were
    // allocated at the start of the buffer memory to the backEnd referenced locations
    backend_.unitSquareSurface = render_system.unit_square_surface_;
    backend_.zeroOneCubeSurface = render_system.zero_one_cube_surface_;
    backend_.zeroOneSphereSurface = render_system.zero_one_sphere_surface_;
    backend_.testImageSurface = render_system.test_image_surface_;

    // use the other buffers next frame, because another CPU
    // may still be rendering into the current buffers
    FrameData.toggleSmpFrame();

    // possibly change the stereo3D mode
    // TODO: UpdateStereo3DMode();

    render_system.gui_model.beginFrame();

    // Make sure that geometry used by code is present in the buffer cache.
    // These use frame buffer cache (not static) because they may be used during
    // map loads.
    //
    // It is important to do this first, so if the buffers overflow during
    // scene generation, the basic surfaces needed for drawing the buffers will
    // always be present.
    {
        const command_list = render_system.command_list.ptr_ orelse unreachable;
        R_InitDrawSurfFromTri(
            &render_system.unit_square_surface_,
            render_system.unit_square_triangles,
            command_list,
        );
        R_InitDrawSurfFromTri(
            &render_system.zero_one_cube_surface_,
            render_system.zero_one_cube_triangles,
            command_list,
        );
        R_InitDrawSurfFromTri(
            &render_system.zero_one_sphere_surface_,
            render_system.zero_one_sphere_triangles,
            command_list,
        );
        R_InitDrawSurfFromTri(
            &render_system.test_image_surface_,
            render_system.test_image_triangles,
            command_list,
        );
    }

    // Reset render crop to be the full screen
    render_system.render_crops[0].x1 = 0;
    render_system.render_crops[0].y1 = 0;
    render_system.render_crops[0].x2 = @intCast(render_system.getWidth() - 1);
    render_system.render_crops[0].y2 = @intCast(render_system.getHeight() - 1);
    render_system.current_render_crop = 0;

    // this is the ONLY place this is modified
    render_system.frame_count += 1;

    // just in case we did a common->Error while this was set
    render_system.gui_recursion_level = 0;

    // set the time for shader effects in 2D rendering
    render_system.frame_shader_time = @as(f32, @floatFromInt(Sys_Milliseconds())) * 0.001;

    var cmd2 = FrameData.createCommand(FrameData.SetBufferCommand);
    cmd2.commandId = .RC_SET_BUFFER;
    cmd2.buffer = 0;

    // the old command buffer can now be rendered, while the new one can
    // be built in parallel
    return command_buffer_head;
}

pub fn renderCommandBuffers(_: *RenderSystem, opt_cmd_head: ?*FrameData.EmptyCommand) void {
    var opt_cmd = opt_cmd_head;
    const cmd_head = opt_cmd orelse return;

    while (opt_cmd) |cmd| : (opt_cmd = @ptrCast(@alignCast(cmd.next))) {
        if (cmd.commandId == .RC_DRAW_VIEW_3D or cmd.commandId == .RC_DRAW_VIEW_GUI)
            break;
    } else return;

    // r_skipBackEnd allows the entire time of the back end
    // to be removed from performance measurements, although
    // nothing will be drawn to the screen.  If the prints
    // are going to a file, or r_skipBackEnd is later disabled,
    // usefull data can be received.

    // r_skipRender is usually more usefull, because it will still
    // draw 2D graphics
    const r_skip_backend = false;
    if (!r_skip_backend) backend_.executeBackendCommands(cmd_head);

    ResolutionScale.instance.initForMap();
}

pub fn performResolutionScaling(
    render_system: *const RenderSystem,
    width: *c_int,
    height: *c_int,
) void {
    var x_scale: f32 = 1;
    var y_scale: f32 = 1;

    ResolutionScale.instance.getCurrentResolutionScale(&x_scale, &y_scale);

    const fwidth: f32 = @floatFromInt(render_system.getWidth());
    const fheight: f32 = @floatFromInt(render_system.getHeight());

    width.* = @intFromFloat(fwidth * x_scale);
    height.* = @intFromFloat(fheight * y_scale);
}

pub fn uncrop(render_system: *RenderSystem) void {
    if (!render_system.initialized) return;

    if (render_system.current_render_crop < 1)
        unreachable;

    render_system.gui_model.emitFullScreen(null);
    render_system.gui_model.clear();

    render_system.current_render_crop -= 1;
}

pub fn getCroppedViewport(render_system: *const RenderSystem) ScreenRect {
    return render_system.render_crops[render_system.current_render_crop];
}

pub fn cropRenderSize(render_system: *RenderSystem, width: c_int, height: c_int) void {
    if (!render_system.initialized) return;

    render_system.gui_model.emitFullScreen(null);
    render_system.gui_model.clear();

    if (width < 1 or height < 1)
        unreachable;

    const prev = &render_system.render_crops[render_system.current_render_crop];
    render_system.current_render_crop += 1;
    var current = &render_system.render_crops[render_system.current_render_crop];
    current.x1 = prev.x1;
    current.x2 = prev.x1 + @as(c_short, @intCast(width)) - 1;
    current.y1 = prev.y2 - @as(c_short, @intCast(height)) + 1;
    current.y2 = prev.y2;
}

pub fn frameCount(render_system: *const RenderSystem) usize {
    return render_system.frame_count;
}

pub fn getWidth(_: *const RenderSystem) c_int {
    if (glConfig.stereo3Dmode == STEREO3D_SIDE_BY_SIDE or
        glConfig.stereo3Dmode == STEREO3D_SIDE_BY_SIDE_COMPRESSED)
    {
        return glConfig.nativeScreenWidth >> @intCast(1);
    }

    return glConfig.nativeScreenWidth;
}

pub fn getHeight(_: *const RenderSystem) c_int {
    if (glConfig.stereo3Dmode == STEREO3D_HDMI_720) {
        return 720;
    }

    const stereoRender_warp = false;
    if (glConfig.stereo3Dmode == STEREO3D_SIDE_BY_SIDE and stereoRender_warp) {
        // for the Rift, render a square aspect view that will be symetric for the optics
        return glConfig.nativeScreenWidth >> @intCast(1);
    }

    if (glConfig.stereo3Dmode == STEREO3D_INTERLACED or
        glConfig.stereo3Dmode == STEREO3D_TOP_AND_BOTTOM_COMPRESSED)
    {
        return glConfig.nativeScreenHeight >> @intCast(1);
    }

    return glConfig.nativeScreenHeight;
}

pub fn setView(render_system: *RenderSystem, view_def: ?*ViewDef) void {
    render_system.view_def = view_def;
}

pub fn getView(render_system: *RenderSystem) ?*ViewDef {
    return render_system.view_def;
}

pub fn incViewCount(render_system: *RenderSystem) void {
    render_system.view_count += 1;
}

pub fn viewCount(render_system: *const RenderSystem) usize {
    return render_system.view_count;
}

pub fn clearViewDef(render_system: *RenderSystem) void {
    render_system.view_def = null;
}

const quad_pic_indexes: [6]sys_types.TriIndex = .{ 3, 0, 2, 2, 0, 1 };
pub fn drawStretchPicture(
    render_system: *RenderSystem,
    top_left: Vec4(f32),
    top_right: Vec4(f32),
    bottom_right: Vec4(f32),
    bottom_left: Vec4(f32),
    opt_material: ?*const Material,
    z: f32,
) void {
    if (!render_system.initialized) return;
    const material = opt_material orelse return;
    const verts = render_system.gui_model.allocTris(
        4,
        &quad_pic_indexes,
        material,
        render_system.current_gl_state,
        STEREO_DEPTH_TYPE_NONE,
    ) orelse return;

    var local_verts: [4]DrawVertex align(16) = std.mem.zeroes([4]DrawVertex);

    local_verts[0].clear();
    local_verts[0].xyz.x = top_left.x();
    local_verts[0].xyz.y = top_left.y();
    local_verts[0].xyz.z = z;
    local_verts[0].setTexCoord(top_left.z(), top_left.w());
    local_verts[0].setNativeOrderColor(render_system.current_color_native_bytes_order);
    local_verts[0].clearColor2();

    local_verts[1].clear();
    local_verts[1].xyz.x = top_right.x();
    local_verts[1].xyz.y = top_right.y();
    local_verts[1].xyz.z = z;
    local_verts[1].setTexCoord(top_right.z(), top_right.w());
    local_verts[1].setNativeOrderColor(render_system.current_color_native_bytes_order);
    local_verts[1].clearColor2();

    local_verts[2].clear();
    local_verts[2].xyz.x = bottom_right.x();
    local_verts[2].xyz.y = bottom_right.y();
    local_verts[2].xyz.z = z;
    local_verts[2].setTexCoord(bottom_right.z(), bottom_right.w());
    local_verts[2].setNativeOrderColor(render_system.current_color_native_bytes_order);
    local_verts[2].clearColor2();

    local_verts[3].clear();
    local_verts[3].xyz.x = bottom_left.x();
    local_verts[3].xyz.y = bottom_left.y();
    local_verts[3].xyz.z = z;
    local_verts[3].setTexCoord(bottom_left.z(), bottom_left.w());
    local_verts[3].setNativeOrderColor(render_system.current_color_native_bytes_order);
    local_verts[3].clearColor2();

    std.debug.assert(std.mem.isAligned(@intFromPtr(verts.ptr), 16));
    std.debug.assert(std.mem.isAligned(@intFromPtr((&local_verts).ptr), 16));
    @memcpy(verts, &local_verts);
}

const math = @import("../math/math.zig");
// little endian pack
fn packColorLittle(color: Vec4(f32)) u32 {
    const bytes: [4]u8 = .{
        math.ftob(color.x() * 255),
        math.ftob(color.y() * 255),
        math.ftob(color.z() * 255),
        math.ftob(color.w() * 255),
    };

    var out: u32 = 0;
    inline for (bytes, 0..) |byte, i| {
        out |= @as(u32, byte) << @intCast((i * 8));
    }

    return out;
}

pub fn setColor(render_system: *RenderSystem, rgba: Vec4(f32)) void {
    render_system.current_color_native_bytes_order = std.mem.toNative(u32, packColorLittle(rgba), .little);
}
