const interface = @import("interface.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const TextureStateExtension = struct {
    desc_ptr: *const interface.TextureDesc,
    permanent_state: interface.ResourceStates = interface.ResourceStates.unknown,
    state_initialized: bool = false,
    is_sampler_feedback: bool = false,
};

pub const TextureState = struct {
    subresource_states: std.ArrayListUnmanaged(interface.ResourceStates) = .{},
    state: interface.ResourceStates = interface.ResourceStates.unknown,
    enable_uav_barriers: bool = true,
    first_uav_barrier_placed: bool = false,
    permanent_transition: bool = false,
};

pub const BufferStateExtension = struct {
    desc_ptr: *const interface.BufferDesc,
    permanent_state: interface.ResourceStates = interface.ResourceStates.unknown,
};

pub const BufferState = struct {
    state: interface.ResourceStates = interface.ResourceStates.unknown,
    enable_uav_barriers: bool = true,
    first_uav_barrier_placed: bool = false,
    permanent_transition: bool = false,
};

pub const TextureBarrier = struct {
    texture: ?*TextureStateExtension = null,
    mip_level: interface.MipLevel = 0,
    array_slice: interface.ArraySlice = 0,
    entire_texture: bool = false,
    state_before: interface.ResourceStates = interface.ResourceStates.unknown,
    state_after: interface.ResourceStates = interface.ResourceStates.unknown,
};

pub const BufferBarrier = struct {
    buffer: ?*BufferStateExtension = null,
    state_before: interface.ResourceStates = interface.ResourceStates.unknown,
    state_after: interface.ResourceStates = interface.ResourceStates.unknown,
};

pub const CommandListResourceStateTracker = struct {
    message_callback: ?*interface.IMessageCallback,
    texture_states: std.AutoHashMapUnmanaged(*TextureStateExtension, *TextureState) = .{},
    buffer_states: std.AutoHashMapUnmanaged(*BufferStateExtension, *BufferState) = .{},
    permanent_texture_states: std.ArrayListUnmanaged(struct { *TextureStateExtension, interface.ResourceStates }) = .{},
    permanent_buffer_states: std.ArrayListUnmanaged(struct { *BufferStateExtension, interface.ResourceStates }) = .{},
    texture_barriers: std.ArrayListUnmanaged(TextureBarrier) = .{},
    buffer_barriers: std.ArrayListUnmanaged(BufferBarrier) = .{},

    pub fn commandListSubmitted(tracker: *CommandListResourceStateTracker) void {
        for (tracker.permanent_texture_states.items) |pair| {
            const texture, const state = pair;

            if (@as(u32, @bitCast(texture.permanent_state)) != 0 and
                @as(u32, @bitCast(texture.permanent_state)) != @as(u32, @bitCast(state)))
            {
                @panic("attempted to switch permanent state of texture");
            }

            texture.permanent_state = state;
        }
        tracker.permanent_texture_states.clearRetainingCapacity();

        for (tracker.permanent_buffer_states.items) |pair| {
            const buffer, const state = pair;

            if (@as(u32, @bitCast(buffer.permanent_state)) != 0 and
                @as(u32, @bitCast(buffer.permanent_state)) != @as(u32, @bitCast(state)))
            {
                @panic("attempted to switch permanent state of buffer");
            }

            buffer.permanent_state = state;
        }
        tracker.permanent_buffer_states.clearRetainingCapacity();

        var iter = tracker.texture_states.keyIterator();
        while (iter.next()) |key_ptr| {
            const texture = key_ptr.*;

            if (texture.desc_ptr.keep_initial_state and !texture.state_initialized) {
                texture.state_initialized = true;
            }
        }

        tracker.texture_states.clearRetainingCapacity();
        tracker.buffer_states.clearRetainingCapacity();
    }

    pub fn clearBarriers(tracker: *CommandListResourceStateTracker, allocator: Allocator) void {
        tracker.texture_barriers.clearAndFree(allocator);
        tracker.buffer_barriers.clearAndFree(allocator);
    }

    pub fn keepTextureInitialStates(
        tracker: *CommandListResourceStateTracker,
        allocator: Allocator,
    ) Allocator.Error!void {
        var iter = tracker.texture_states.iterator();

        while (iter.next()) |entry| {
            const texture = entry.key_ptr.*;
            const tracking = entry.value_ptr.*;

            if (texture.desc_ptr.keep_initial_state and
                @as(u32, @bitCast(texture.permanent_state)) == 0 and
                !tracking.permanent_transition)
            {
                try tracker.requireTextureState(
                    texture,
                    interface.TextureSubresourceSet.all_subresources,
                    texture.desc_ptr.initial_state,
                    allocator,
                );
            }
        }
    }

    pub fn keepBufferInitialStates(
        tracker: *CommandListResourceStateTracker,
        allocator: Allocator,
    ) Allocator.Error!void {
        var iter = tracker.buffer_states.iterator();

        while (iter.next()) |entry| {
            const buffer = entry.key_ptr.*;
            const tracking = entry.value_ptr.*;

            if (buffer.desc_ptr.keep_initial_state and
                @as(u32, @bitCast(buffer.permanent_state)) == 0 and
                !buffer.desc_ptr.is_volatile and
                !tracking.permanent_transition)
            {
                try tracker.requireBufferState(
                    buffer,
                    buffer.desc_ptr.initial_state,
                    allocator,
                );
            }
        }
    }

    fn verifyPermanentResourceState(
        permanent_state: interface.ResourceStates,
        required_state: interface.ResourceStates,
        is_texture: bool,
        debug_name: [*:0]const u8,
        opt_message_callback: ?*interface.IMessageCallback,
    ) bool {
        _ = opt_message_callback;

        const intersection = @as(u32, @bitCast(permanent_state)) &
            @as(u32, @bitCast(required_state));
        if (intersection != @as(u32, @bitCast(required_state))) {
            // TODO: message callback
            std.debug.print(
                "Permanent {s} [debug_name: {s}] doesn't have the right state bits (required: {}, present: {})\n",
                .{
                    if (is_texture) "texture" else "buffer",
                    debug_name,
                    permanent_state,
                    required_state,
                },
            );
            return false;
        }

        return true;
    }

    fn getOrCreateTextureStateTracking(
        tracker: *CommandListResourceStateTracker,
        texture: *TextureStateExtension,
        allocator: Allocator,
    ) Allocator.Error!*TextureState {
        const opt_texture_state = tracker.texture_states.get(texture);
        if (opt_texture_state) |texture_state| return texture_state;

        const texture_state = try allocator.create(TextureState);
        texture_state.* = .{};

        try tracker.texture_states.putNoClobber(allocator, texture, texture_state);

        if (texture.desc_ptr.keep_initial_state) {
            texture_state.state = if (texture.state_initialized) texture.desc_ptr.initial_state else .{ .common = true };
        }

        return texture_state;
    }

    fn getOrCreateBufferStateTracking(
        tracker: *CommandListResourceStateTracker,
        buffer: *BufferStateExtension,
        allocator: Allocator,
    ) Allocator.Error!*BufferState {
        const opt_buffer_state = tracker.buffer_states.get(buffer);
        if (opt_buffer_state) |buffer_state| return buffer_state;

        const buffer_state = try allocator.create(BufferState);
        buffer_state.* = .{};

        try tracker.buffer_states.putNoClobber(allocator, buffer, buffer_state);

        if (buffer.desc_ptr.keep_initial_state) {
            buffer_state.state = buffer.desc_ptr.initial_state;
        }

        return buffer_state;
    }

    fn requireBufferState(
        tracker: *CommandListResourceStateTracker,
        buffer: *BufferStateExtension,
        state: interface.ResourceStates,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (buffer.desc_ptr.is_volatile) return;
        if (@as(u32, @bitCast(buffer.permanent_state)) != 0) {
            _ = verifyPermanentResourceState(
                buffer.permanent_state,
                state,
                false,
                buffer.desc_ptr.debug_name,
                tracker.message_callback,
            );
            return;
        }

        if (buffer.desc_ptr.cpu_access != .none) {
            return;
        }

        const tracking = try tracker.getOrCreateBufferStateTracking(buffer, allocator);

        if (std.meta.eql(tracking.state, interface.ResourceStates.unknown)) {
            std.debug.print(
                "[RHI][ERR] Unknown prior state of buffer {s}\n",
                .{buffer.desc_ptr.debug_name},
            );

            // TODO: message callback
        }

        const transition_needed = !std.meta.eql(tracking.state, state);
        const uav_needed = state.unordered_access and
            (tracking.enable_uav_barriers or !tracking.first_uav_barrier_placed);

        if (transition_needed) {
            for (tracker.buffer_barriers.items) |*barrier| {
                if (barrier.buffer == buffer) {
                    barrier.state_after = @bitCast(
                        @as(u32, @bitCast(barrier.state_after)) |
                            @as(u32, @bitCast(state)),
                    );
                    tracking.state = barrier.state_after;
                }
            }
        }

        if (transition_needed or uav_needed) {
            try tracker.buffer_barriers.append(allocator, .{
                .buffer = buffer,
                .state_before = tracking.state,
                .state_after = state,
            });
        }

        if (uav_needed and !transition_needed) {
            tracking.first_uav_barrier_placed = true;
        }

        tracking.state = state;
    }

    fn requireTextureState(
        tracker: *CommandListResourceStateTracker,
        texture: *TextureStateExtension,
        in_subresources: interface.TextureSubresourceSet,
        state: interface.ResourceStates,
        allocator: Allocator,
    ) Allocator.Error!void {
        if (@as(u32, @bitCast(texture.permanent_state)) != 0) {
            _ = verifyPermanentResourceState(
                texture.permanent_state,
                state,
                true,
                texture.desc_ptr.debug_name,
                tracker.message_callback,
            );
            return;
        }

        const subresources = in_subresources.resolve(
            texture.desc_ptr,
            false,
        );

        const tracking = try tracker.getOrCreateTextureStateTracking(
            texture,
            allocator,
        );

        if (subresources.isEntireTexture(texture.desc_ptr) and tracking.subresource_states.items.len == 0) {
            const transition_needed = !std.meta.eql(tracking.state, state);
            const uav_needed = state.unordered_access and
                (tracking.enable_uav_barriers or !tracking.first_uav_barrier_placed);

            if (transition_needed or uav_needed) {
                try tracker.texture_barriers.append(allocator, .{
                    .texture = texture,
                    .entire_texture = true,
                    .state_before = tracking.state,
                    .state_after = state,
                });
            }

            if (uav_needed and !transition_needed) {
                tracking.first_uav_barrier_placed = true;
            }

            tracking.state = state;
        } else { // individual
            var state_expanded = false;
            if (tracking.subresource_states.items.len == 0) {
                if (std.meta.eql(tracking.state, interface.ResourceStates.unknown)) {
                    @panic("TODO: print debug message");
                }

                const old_len = tracking.subresource_states.items.len;
                try tracking.subresource_states.resize(
                    allocator,
                    texture.desc_ptr.mip_levels * texture.desc_ptr.array_size,
                );
                for (tracking.subresource_states.items[old_len..]) |*sub_state| {
                    sub_state.* = tracking.state;
                }
                tracking.state = interface.ResourceStates.unknown;
                state_expanded = true;
            }

            var any_uav_barrier = false;

            for (subresources.base_array_slice..(subresources.base_array_slice + subresources.num_array_slices)) |array_slice| {
                for (subresources.base_mip_level..(subresources.base_mip_level + subresources.num_mip_levels)) |mip_level| {
                    const subresource_index = calcSubresource(
                        @intCast(mip_level),
                        @intCast(array_slice),
                        texture.desc_ptr,
                    );

                    const prior_state = tracking.subresource_states.items[subresource_index];
                    if (std.meta.eql(prior_state, interface.ResourceStates.unknown) and !state_expanded) {
                        @panic("TODO: unknown prior state");
                    }

                    const transition_needed = !std.meta.eql(tracking.state, state);
                    const uav_needed = state.unordered_access and
                        !any_uav_barrier and
                        (tracking.enable_uav_barriers or !tracking.first_uav_barrier_placed);
                    if (transition_needed or uav_needed) {
                        try tracker.texture_barriers.append(allocator, .{
                            .texture = texture,
                            .entire_texture = true,
                            .mip_level = @intCast(mip_level),
                            .array_slice = @intCast(array_slice),
                            .state_before = tracking.state,
                            .state_after = state,
                        });
                    }

                    tracking.subresource_states.items[subresource_index] = state;

                    if (uav_needed and !transition_needed) {
                        any_uav_barrier = true;
                        tracking.first_uav_barrier_placed = true;
                    }
                }
            }
        }
    }
};

inline fn calcSubresource(
    mip_level: interface.MipLevel,
    array_slice: interface.ArraySlice,
    desc: *const interface.TextureDesc,
) u32 {
    return mip_level + array_slice * desc.mip_levels;
}

pub inline fn getFormatInfo(format: interface.Format) *const FormatInfo {
    std.debug.assert(@intFromEnum(format) < @typeInfo(interface.Format).Enum.fields.len);

    return &format_info[@intFromEnum(format)];
}

pub const FormatInfo = struct {
    const Kind = enum(u8) {
        integer,
        normalized,
        float,
        depth_stencil,
    };

    format: interface.Format,
    name: [*:0]const u8,
    bytes_per_block: u8,
    block_size: u8,
    kind: Kind,
    has_red: bool,
    has_green: bool,
    has_blue: bool,
    has_alpha: bool,
    has_depth: bool,
    has_stencil: bool,
    is_signed: bool,
    is_srgb: bool,
};

const format_info = [_]FormatInfo{
    .{
        .format = .unknown,
        .name = "UNKNOWN",
        .bytes_per_block = 0,
        .block_size = 0,
        .kind = .integer,
        .has_red = false,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r8_uint,
        .name = "R8_UINT",
        .bytes_per_block = 1,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r8_sint,
        .name = "R8_SINT",
        .bytes_per_block = 1,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .r8_unorm,
        .name = "R8_UNORM",
        .bytes_per_block = 1,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r8_snorm,
        .name = "R8_SNORM",
        .bytes_per_block = 1,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rg8_uint,
        .name = "RG8_UINT",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rg8_sint,
        .name = "RG8_SINT",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rg8_unorm,
        .name = "RG8_UNORM",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rg8_snorm,
        .name = "RG8_SNORM",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .r16_uint,
        .name = "R16_UINT",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r16_sint,
        .name = "R16_SINT",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .r16_unorm,
        .name = "R16_UNORM",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r16_snorm,
        .name = "R16_SNORM",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .r16_float,
        .name = "R16_FLOAT",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .bgra4_unorm,
        .name = "BGRA4_UNORM",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .b5g6r5_unorm,
        .name = "B5G6R5_UNORM",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .b5g5r5a1_unorm,
        .name = "B5G5R5A1_UNORM",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rgba8_uint,
        .name = "RGBA8_UINT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rgba8_sint,
        .name = "RGBA8_SINT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgba8_unorm,
        .name = "RGBA8_UNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rgba8_snorm,
        .name = "RGBA8_SNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .bgra8_unorm,
        .name = "BGRA8_UNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .srgba8_unorm,
        .name = "SRGBA8_UNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = true,
    },
    .{
        .format = .sbgra8_unorm,
        .name = "SBGRA8_UNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r10g10b10a2_unorm,
        .name = "R10G10B10A2_UNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r11g11b10_float,
        .name = "R11G11B10_FLOAT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rg16_uint,
        .name = "RG16_UINT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rg16_sint,
        .name = "RG16_SINT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rg16_unorm,
        .name = "RG16_UNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rg16_snorm,
        .name = "RG16_SNORM",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rg16_float,
        .name = "RG16_FLOAT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .r32_uint,
        .name = "R32_UINT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .r32_sint,
        .name = "R32_SINT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .r32_float,
        .name = "R32_FLOAT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgba16_uint,
        .name = "RGBA16_UINT",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rgba16_sint,
        .name = "RGBA16_SINT",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgba16_float,
        .name = "RGBA16_FLOAT",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgba16_unorm,
        .name = "RGBA16_UNORM",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rgba16_snorm,
        .name = "RGBA16_SNORM",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rg32_uint,
        .name = "RG32_UINT",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rg32_sint,
        .name = "RG32_SINT",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rg32_float,
        .name = "RG32_FLOAT",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgb32_uint,
        .name = "RGB32_UINT",
        .bytes_per_block = 12,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rgb32_sint,
        .name = "RGB32_SINT",
        .bytes_per_block = 12,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgb32_float,
        .name = "RGB32_FLOAT",
        .bytes_per_block = 12,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgba32_uint,
        .name = "RGBA32_UINT",
        .bytes_per_block = 16,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .rgba32_sint,
        .name = "RGBA32_SINT",
        .bytes_per_block = 16,
        .block_size = 1,
        .kind = .integer,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .rgba32_float,
        .name = "RGBA32_FLOAT",
        .bytes_per_block = 16,
        .block_size = 1,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .d16,
        .name = "D16",
        .bytes_per_block = 2,
        .block_size = 1,
        .kind = .depth_stencil,
        .has_red = false,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = true,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .d24s8,
        .name = "D24S8",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .depth_stencil,
        .has_red = false,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = true,
        .has_stencil = true,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .x24g8_uint,
        .name = "X24G8_UINT",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .integer,
        .has_red = false,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = true,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .d32,
        .name = "D32",
        .bytes_per_block = 4,
        .block_size = 1,
        .kind = .depth_stencil,
        .has_red = false,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = true,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .d32s8,
        .name = "D32S8",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .depth_stencil,
        .has_red = false,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = true,
        .has_stencil = true,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .x32g8_uint,
        .name = "X32G8_UINT",
        .bytes_per_block = 8,
        .block_size = 1,
        .kind = .integer,
        .has_red = false,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = true,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc1_unorm,
        .name = "BC1_UNORM",
        .bytes_per_block = 8,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc1_unorm_srgb,
        .name = "BC1_UNORM_SRGB",
        .bytes_per_block = 8,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = true,
    },
    .{
        .format = .bc2_unorm,
        .name = "BC2_UNORM",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc2_unorm_srgb,
        .name = "BC2_UNORM_SRGB",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = true,
    },
    .{
        .format = .bc3_unorm,
        .name = "BC3_UNORM",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc3_unorm_srgb,
        .name = "BC3_UNORM_SRGB",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = true,
    },
    .{
        .format = .bc4_unorm,
        .name = "BC4_UNORM",
        .bytes_per_block = 8,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc4_snorm,
        .name = "BC4_SNORM",
        .bytes_per_block = 8,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = false,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .bc5_unorm,
        .name = "BC5_UNORM",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc5_snorm,
        .name = "BC5_SNORM",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = false,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .bc6h_ufloat,
        .name = "BC6H_UFLOAT",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc6h_sfloat,
        .name = "BC6H_SFLOAT",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .float,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = false,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = true,
        .is_srgb = false,
    },
    .{
        .format = .bc7_unorm,
        .name = "BC7_UNORM",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = false,
    },
    .{
        .format = .bc7_unorm_srgb,
        .name = "BC7_UNORM_SRGB",
        .bytes_per_block = 16,
        .block_size = 4,
        .kind = .normalized,
        .has_red = true,
        .has_green = true,
        .has_blue = true,
        .has_alpha = true,
        .has_depth = false,
        .has_stencil = false,
        .is_signed = false,
        .is_srgb = true,
    },
};
