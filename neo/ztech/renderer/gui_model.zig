const std = @import("std");
const RenderSystem = @import("render_system.zig");
const StereoDepthType = RenderSystem.StereoDepthType;
const idlib = @import("../idlib.zig");
const Framebuffer = @import("framebuffer.zig").Framebuffer;
const DrawVertex = @import("../geometry/draw_vertex.zig").DrawVertex;
const TriIndex = @import("../sys/types.zig").TriIndex;
const Material = @import("material.zig").Material;
const vertex_cache = @import("vertex_cache.zig");
const VertexCacheHandle = vertex_cache.VertexCacheHandle;
const max_entity_shader_params = @import("render_entity.zig").max_entity_shader_params;
const ScreenRect = @import("screen_rect.zig").ScreenRect;
const Allocator = std.mem.Allocator;
const FrameData = @import("frame_data.zig");
const ViewDef = @import("common.zig").ViewDef;
const DrawSurface = @import("common.zig").DrawSurface;
const ViewEntity = @import("common.zig").ViewEntity;
const writeIndexPair = @import("model_decal.zig").writeIndexPair;
const RenderMatrix = @import("matrix.zig").RenderMatrix;
const initial_draw_surfaces = @import("common.zig").initial_draw_surfaces;

const Surface = extern struct {
    material: ?*const Material = null,
    gl_state: u64 = 0,
    first_index: u32 = 0,
    num_indexes: u32 = 0,
    stereo_type: StereoDepthType = .none,
    clip_rect: ScreenRect = std.mem.zeroes(ScreenRect),
};

pub const GuiModel = extern struct {
    const stereo_depth_near = 0;
    const stereo_depth_mid = 0.5;
    const stereo_depth_far = 1;

    const max_indexes = 20000 * 6;
    const max_verts = 20000 * 4;

    surface: ?*Surface = null,
    shader_params: [max_entity_shader_params]f32 = [_]f32{1.0} ** max_entity_shader_params,
    vertex_block: VertexCacheHandle = .{},
    index_block: VertexCacheHandle = .{},
    vertex_ptr: ?[*]DrawVertex = null,
    index_ptr: ?[*]TriIndex = null,
    num_verts: u32 = 0,
    num_indexes: u32 = 0,
    surfaces: idlib.List(Surface) = .{},

    pub fn create(allocator: Allocator) Allocator.Error!*GuiModel {
        const gui_model = try allocator.create(GuiModel);
        gui_model.* = .{};

        return gui_model;
    }

    pub fn destroy(gui_model: *GuiModel, allocator: Allocator) void {
        allocator.destroy(gui_model);
    }

    pub fn clear(gui_model: *GuiModel, allocator: Allocator) Allocator.Error!void {
        gui_model.surfaces.setNumAssureSize(0);
        _ = try gui_model.advanceSurface(allocator);
    }

    fn advanceSurface(
        gui_model: *GuiModel,
        allocator: Allocator,
    ) Allocator.Error!*Surface {
        var s = Surface{};
        if (gui_model.surfaces.num != 0) {
            s.material = gui_model.surface.?.material;
            s.gl_state = gui_model.surface.?.gl_state;
        } else {
            s.material = RenderSystem.instance.default_material;
            s.gl_state = 0;
        }

        gui_model.num_indexes = std.mem.alignForward(u32, gui_model.num_indexes, 8);
        s.num_indexes = 0;
        s.first_index = gui_model.num_indexes;

        const index = try gui_model.surfaces.append(s, allocator);
        const surface = &(gui_model.surfaces.slice()[index]);
        gui_model.surface = surface;

        return surface;
    }

    pub fn emitFullScreen(
        gui_model: *GuiModel,
        opt_render_target: ?*Framebuffer,
        allocator: Allocator,
    ) EmitSurfacesError!void {
        if (gui_model.surfaces.constSlice()[0].num_indexes == 0) return;
        var view_def = FrameData.frameCreate(ViewDef);
        view_def.* = std.mem.zeroes(ViewDef);
        view_def.is2Dgui = true;

        if (opt_render_target) |render_target| {
            view_def.targetRender = render_target;
            view_def.viewport.x1 = 0;
            view_def.viewport.y1 = 0;
            view_def.viewport.x2 = @intCast(render_target.width);
            view_def.viewport.y2 = @intCast(render_target.height);
        } else {
            view_def.viewport = RenderSystem.instance.getCroppedViewport();
        }

        const stereo_enabled = false;
        if (stereo_enabled) {
            // TODO stereo_3d
        }

        var screen_size_x: u32 = @intCast(RenderSystem.instance.getVirtualWidth());
        var screen_size_y: u32 = @intCast(RenderSystem.instance.getVirtualHeight());
        if (opt_render_target) |render_target| {
            screen_size_x = render_target.width;
            screen_size_y = render_target.height;
        }

        const x_scale: f32 = 1.0 / @as(f32, @floatFromInt(screen_size_x));
        const y_scale: f32 = -1.0 / @as(f32, @floatFromInt(screen_size_y));
        const z_scale: f32 = -1.0;

        view_def.scissor.x1 = 0;
        view_def.scissor.y1 = 0;
        view_def.scissor.x2 = view_def.viewport.x2 - view_def.viewport.x1;
        view_def.scissor.y2 = view_def.viewport.y2 - view_def.viewport.y1;

        view_def.projectionMatrix[0 * 4 + 0] = 2 * x_scale;
        view_def.projectionMatrix[0 * 4 + 1] = 0.0;
        view_def.projectionMatrix[0 * 4 + 2] = 0.0;
        view_def.projectionMatrix[0 * 4 + 3] = 0.0;

        view_def.projectionMatrix[1 * 4 + 0] = 0.0;
        view_def.projectionMatrix[1 * 4 + 1] = 2 * y_scale;
        view_def.projectionMatrix[1 * 4 + 2] = 0.0;
        view_def.projectionMatrix[1 * 4 + 3] = 0.0;

        view_def.projectionMatrix[2 * 4 + 0] = 0.0;
        view_def.projectionMatrix[2 * 4 + 1] = 0.0;
        view_def.projectionMatrix[2 * 4 + 2] = z_scale;
        view_def.projectionMatrix[2 * 4 + 3] = 0.0;

        view_def.projectionMatrix[3 * 4 + 0] = -(@as(f32, @floatFromInt(screen_size_x)) * x_scale);
        view_def.projectionMatrix[3 * 4 + 1] = -(@as(f32, @floatFromInt(screen_size_y)) * y_scale);
        view_def.projectionMatrix[3 * 4 + 2] = 0.0;
        view_def.projectionMatrix[3 * 4 + 3] = 1.0;

        const projection_matrix: *RenderMatrix = @ptrCast(&view_def.projectionMatrix);
        view_def.projectionRenderMatrix = projection_matrix.transpose();

        view_def.worldSpace.modelMatrix[0 * 4 + 0] = 1.0;
        view_def.worldSpace.modelMatrix[1 * 4 + 1] = 1.0;
        view_def.worldSpace.modelMatrix[2 * 4 + 2] = 1.0;
        view_def.worldSpace.modelMatrix[3 * 4 + 3] = 1.0;

        view_def.worldSpace.modelViewMatrix[0 * 4 + 0] = 1.0;
        view_def.worldSpace.modelViewMatrix[1 * 4 + 1] = 1.0;
        view_def.worldSpace.modelViewMatrix[2 * 4 + 2] = 1.0;
        view_def.worldSpace.modelViewMatrix[3 * 4 + 3] = 1.0;

        view_def.maxDrawSurfs = @intCast(gui_model.surfaces.num);
        const draw_surfs = FrameData.frameAlloc(*DrawSurface, view_def.maxDrawSurfs);
        view_def.drawSurfs = draw_surfs.ptr;
        view_def.numDrawSurfs = 0;

        const shader_time = RenderSystem.instance.frame_shader_time;
        view_def.renderView.time[0] = @intFromFloat(shader_time);
        view_def.renderView.time[1] = @intFromFloat(shader_time);

        const old_view_def = RenderSystem.instance.view_def;
        view_def.superView = old_view_def;

        RenderSystem.instance.view_def = view_def;

        try gui_model.emitSurfacesToView(
            view_def,
            &view_def.worldSpace.modelMatrix,
            &view_def.worldSpace.modelViewMatrix,
            false, // depth_hack
            stereo_enabled,
            false, // link as entity
            allocator,
        );

        RenderSystem.instance.view_def = old_view_def;

        view_def.addDrawCommand(true);
    }

    pub const EmitSurfacesError = Material.EvaluateRegistersError;
    fn emitSurfacesToView(
        gui_model: *GuiModel,
        view_def: *ViewDef,
        model_matrix: *[16]f32,
        model_view_matrix: *[16]f32,
        depth_hack: bool,
        allow_full_screen_stereo_depth: bool,
        link_as_entity: bool,
        allocator: Allocator,
    ) EmitSurfacesError!void {
        var gui_space = FrameData.frameCreate(ViewEntity);
        gui_space.* = std.mem.zeroes(ViewEntity);
        gui_space.modelMatrix = model_matrix.*;
        gui_space.modelViewMatrix = model_view_matrix.*;
        gui_space.weaponDepthHack = depth_hack;
        gui_space.isGuiSurface = true;

        if (link_as_entity) {
            gui_space.next = view_def.viewEntitys;
            view_def.viewEntitys = gui_space;
        }

        const view_mat = @as(*RenderMatrix, @ptrCast(model_view_matrix)).transpose();
        gui_space.mvp = view_def.projectionRenderMatrix.multiply(
            view_mat,
        );

        if (depth_hack) {
            gui_space.mvp.applyDepthHack();
        }

        const default_stereo_depth: f32 = 0;

        for (gui_model.surfaces.constSlice()) |*surface| {
            if (surface.num_indexes == 0) continue;
            const shader = surface.material orelse continue;
            var draw_surface = FrameData.frameCreate(DrawSurface);

            draw_surface.numIndexes = surface.num_indexes;
            draw_surface.ambientCache = gui_model.vertex_block;
            draw_surface.indexCache = index_cache: {
                var index_cache = gui_model.index_block;
                index_cache.offset += @intCast(surface.first_index * @sizeOf(TriIndex));
                break :index_cache index_cache;
            };
            draw_surface.jointCache = .{};
            draw_surface.frontEndGeo = null;
            draw_surface.space = gui_space;
            draw_surface.material = shader;
            draw_surface.extraGLState = surface.gl_state;
            draw_surface.scissorRect = view_def.scissor;
            if (!surface.clip_rect.isEmpty()) {
                draw_surface.scissorRect.intersect(surface.clip_rect);
            }
            draw_surface.sort = shader.sort;

            if (shader.constant_registers) |const_regs| {
                draw_surface.shaderRegisters = const_regs;
            } else {
                const regs = FrameData.frameAlloc(f32, shader.num_registers);
                draw_surface.shaderRegisters = regs.ptr;
                try shader.evaluateRegisters(
                    regs,
                    &gui_model.shader_params,
                    &view_def.renderView.shader_params,
                    @as(f32, @floatFromInt(view_def.renderView.time[1])) * 0.001,
                    null,
                    allocator,
                );
            }

            linkDrawSurfaceToView(
                draw_surface,
                view_def,
            );

            if (allow_full_screen_stereo_depth) {
                draw_surface.sort = switch (surface.stereo_type) {
                    .near => stereo_depth_near,
                    .mid => stereo_depth_mid,
                    .far => stereo_depth_far,
                    else => default_stereo_depth,
                };
            }
        }
    }

    fn linkDrawSurfaceToView(draw_surface: *DrawSurface, view_def: *ViewDef) void {
        if (view_def.numDrawSurfs == view_def.maxDrawSurfs) {
            // resize
            const opt_old = view_def.drawSurfs;
            var count: u32 = 0;

            if (view_def.maxDrawSurfs == 0) {
                view_def.maxDrawSurfs = initial_draw_surfaces;
                count = 0;
            } else {
                count = view_def.maxDrawSurfs;
                view_def.maxDrawSurfs *= 2;
            }

            const draw_surfs = FrameData.frameAlloc(
                *DrawSurface,
                view_def.maxDrawSurfs,
            );
            view_def.drawSurfs = draw_surfs.ptr;
            if (opt_old) |old_draw_surfaces| {
                @memcpy(draw_surfs[0..count], old_draw_surfaces[0..count]);
            }
        }

        view_def.drawSurfs.?[@intCast(view_def.numDrawSurfs)] = draw_surface;
        view_def.numDrawSurfs += 1;
    }

    pub fn beginFrame(gui_model: *GuiModel, allocator: Allocator) Allocator.Error!void {
        gui_model.vertex_block = vertex_cache.instance.allocVertex(
            null,
            max_verts,
            @sizeOf(DrawVertex),
            null,
        );
        gui_model.index_block = vertex_cache.instance.allocIndex(
            null,
            max_indexes,
            @sizeOf(TriIndex),
            null,
        );

        const vertex_ptr: [*]DrawVertex = @ptrCast(@alignCast(vertex_cache.instance.mappedVertexBuffer(
            gui_model.vertex_block,
        )));
        const index_ptr: [*]TriIndex = @ptrCast(@alignCast(vertex_cache.instance.mappedIndexBuffer(
            gui_model.index_block,
        )));

        gui_model.vertex_ptr = vertex_ptr;
        gui_model.index_ptr = index_ptr;

        gui_model.num_verts = 0;
        gui_model.num_indexes = 0;

        try gui_model.clear(allocator);
    }

    pub fn allocTrisWithClip(
        gui_model: *GuiModel,
        num_verts: usize,
        temp_indexes: []const TriIndex,
        opt_material: ?*const Material,
        gl_state: u64,
        stereo_type: StereoDepthType,
        clip_rect: ScreenRect,
        allocator: Allocator,
    ) Allocator.Error!?[]align(16) DrawVertex {
        const material = opt_material orelse return null;

        if (gui_model.num_indexes + temp_indexes.len > max_indexes) {
            // TODO: warn
            return null;
        }

        if (gui_model.num_verts + num_verts > max_verts) {
            // TODO: warn
            return null;
        }

        // change surface if we are changin to a new material or we can't
        // fit the data into our allocated block
        var surface = gui_model.surface orelse @panic("current gui surface is null");
        if (material != surface.material.? or
            gl_state != surface.gl_state or
            stereo_type != surface.stereo_type or
            !std.meta.eql(clip_rect, surface.clip_rect))
        {
            if (surface.num_indexes != 0) {
                surface = try gui_model.advanceSurface(allocator);
            }

            surface.material = material;
            surface.gl_state = gl_state;
            surface.stereo_type = stereo_type;
            surface.clip_rect = clip_rect;
        }

        const vertex_ptr = gui_model.vertex_ptr orelse @panic("vertex pointer is null");
        const index_ptr = gui_model.index_ptr orelse @panic("index pointer is null");

        const start_vert: u16 = @intCast(gui_model.num_verts);
        const start_index = gui_model.num_indexes;

        gui_model.num_verts += @intCast(num_verts);
        gui_model.num_indexes += @intCast(temp_indexes.len);

        surface.num_indexes += @intCast(temp_indexes.len);

        if ((start_index & 1) != 0 or (temp_indexes.len & 1) != 0) {
            for (0..temp_indexes.len) |i| {
                index_ptr[start_index + i] = start_vert + temp_indexes[i];
            }
        } else {
            var i: u32 = 0;
            while (i < temp_indexes.len) : (i += 2) {
                writeIndexPair(
                    index_ptr + start_index + i,
                    start_vert + temp_indexes[i],
                    start_vert + temp_indexes[i + 1],
                );
            }
        }

        return @alignCast((vertex_ptr + start_vert)[0..num_verts]);
    }

    pub fn allocTris(
        gui_model: *GuiModel,
        num_verts: usize,
        indexes: []const TriIndex,
        opt_material: ?*const Material,
        gl_state: u64,
        stereo_type: StereoDepthType,
        allocator: Allocator,
    ) Allocator.Error!?[]align(16) DrawVertex {
        var clip_rect = std.mem.zeroes(ScreenRect);
        clip_rect.clear();

        return try gui_model.allocTrisWithClip(
            num_verts,
            indexes,
            opt_material,
            gl_state,
            stereo_type,
            clip_rect,
            allocator,
        );
    }
};
