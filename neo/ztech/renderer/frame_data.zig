const std = @import("std");
const ViewDef = @import("common.zig").ViewDef;
const Image = @import("image.zig").Image;

pub const RenderCommand = enum(u8) {
    nop,
    draw_view_3d, // may be at a reduced resolution, will be upsampled before 2D GUIs
    draw_view_gui, // not resolution scaled
    set_buffer,
    copy_render,
    post_process, // postfx after scene rendering is done but before GUI rendering
    crt_post_process, // CRT simulation after everything has been rendered on the final swapchain image
};

pub const EmptyCommand = extern struct {
    command_id: RenderCommand,
    next: ?*RenderCommand,
};

pub const SetBufferCommand = extern struct {
    command_id: RenderCommand,
    next: ?*RenderCommand,
    buffer: c_int,
};

pub const DrawSurfacesCommand = extern struct {
    command_id: RenderCommand,
    next: ?*RenderCommand,
    view_def: ?*ViewDef,
};

pub const CopyRenderCommand = extern struct {
    command_id: RenderCommand,
    next: ?*RenderCommand,
    x: c_int,
    y: c_int,
    image_width: c_int,
    image_height: c_int,
    image: ?*Image,
    cube_face: c_int,
    clear_color_after_copy: bool,
};

pub const PostProcessCommand = extern struct {
    command_id: RenderCommand,
    next: ?*RenderCommand,
    view_def: ?*ViewDef,
};

pub const CrtPostProcessCommand = extern struct {
    command_id: RenderCommand,
    next: ?*RenderCommand,
    padding: c_int,
};

pub const FrameData = extern struct {
    frame_memory: ?[*]u8,
    cmd_head: ?*EmptyCommand, // may be of other command type based on commandId
    cmd_tail: ?*EmptyCommand,
};

pub var frame_data: ?*FrameData = null;

const max_frame_memory: usize = 64 * 1024 * 1024;
const frame_alloc_alignment: usize = 128;
const frame_memory_alignment: usize = 16;
const cache_line_size: usize = 128;

// SMP = Symmetric multiprocessing / shared-memory multiprocessing
var smp_frame: u32 = 0;
pub const num_frame_data: u32 = 3;
var smp_frame_data: [num_frame_data]FrameData = undefined;
var buffer_allocators: [num_frame_data]std.heap.FixedBufferAllocator = undefined;

pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!void {
    shutdown(allocator);

    for (&smp_frame_data, &buffer_allocators) |*data, *frame_allocator| {
        const mem = try allocator.alignedAlloc(
            u8,
            frame_memory_alignment,
            max_frame_memory,
        );
        frame_allocator.* = std.heap.FixedBufferAllocator.init(mem);
        data.frame_memory = mem.ptr;
    }

    frame_data = &smp_frame_data[0];

    toggleSmpFrame();
}

pub fn shutdown(allocator: std.mem.Allocator) void {
    if (frame_data == null) return;

    frame_data = null;

    for (&smp_frame_data, &buffer_allocators) |*data, *frame_allocator| {
        if (data.frame_memory) |frame_memory| {
            frame_allocator.reset();
            allocator.free(frame_memory[0..max_frame_memory]);
            data.frame_memory = null;
        }
    }
}

pub inline fn bufferAllocator() *std.heap.FixedBufferAllocator {
    return &buffer_allocators[smp_frame % num_frame_data];
}

pub fn toggleSmpFrame() void {
    smp_frame += 1;

    bufferAllocator().reset();

    var empty_command = frameCreate(EmptyCommand);
    empty_command.command_id = .nop;
    empty_command.next = null;

    var current_frame_data = &smp_frame_data[smp_frame % num_frame_data];
    current_frame_data.cmd_tail = empty_command;
    current_frame_data.cmd_head = current_frame_data.cmd_tail;
    frame_data = current_frame_data;
}

pub fn frameAlloc(T: type, n: usize) []T {
    const frame_allocator = bufferAllocator().threadSafeAllocator();
    const byte_count = std.math.mul(usize, @sizeOf(T), n) catch {
        @panic("FrameData.frameAlloc: mul overflow");
    };
    const mem = allocBytes(frame_allocator, byte_count);
    const ptr: [*]T = @ptrCast(@alignCast(mem.ptr));

    return ptr[0..n];
}

pub fn frameCreate(T: type) *T {
    const frame_allocator = bufferAllocator().threadSafeAllocator();
    const mem = allocBytes(frame_allocator, @sizeOf(T));

    return @ptrCast(@alignCast(mem.ptr));
}

pub fn allocBytes(frame_allocator: std.mem.Allocator, bytes: usize) []u8 {
    const slice = frame_allocator.alignedAlloc(u8, frame_alloc_alignment, bytes) catch {
        @panic("FrameData.alloc: ran out of memory!");
    };

    var offset: usize = 0;
    while (offset < bytes) : (offset += cache_line_size) {
        const addr = @intFromPtr(slice.ptr) + offset;
        const aligned_addr = std.mem.alignBackward(usize, addr, cache_line_size);
        const ptr: [*]u8 = @ptrFromInt(aligned_addr);
        @memset(ptr[0..cache_line_size], 0);
    }

    return slice;
}

pub inline fn createCommand(CommandType: type) *CommandType {
    return @ptrCast(@alignCast(createCommandBuffer(@sizeOf(CommandType)).ptr));
}

pub fn createCommandBuffer(bytes: usize) []u8 {
    const frame_allocator = bufferAllocator().threadSafeAllocator();
    const mem = allocBytes(frame_allocator, bytes);
    var cmd: *EmptyCommand = @ptrCast(@alignCast(mem.ptr));
    cmd.next = null;

    var current_frame_data = frame_data orelse unreachable;
    current_frame_data.cmd_tail.?.next = &cmd.command_id;
    current_frame_data.cmd_tail = cmd;

    return mem;
}
