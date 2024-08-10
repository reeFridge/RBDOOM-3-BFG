const std = @import("std");
const ViewDef = @import("common.zig").ViewDef;
const Image = @import("image.zig").Image;

const InterlockedInteger = extern struct {
    value: c_int = 0,
};

const RenderCommand = enum(u8) {
    RC_NOP,
    RC_DRAW_VIEW_3D, // may be at a reduced resolution, will be upsampled before 2D GUIs
    RC_DRAW_VIEW_GUI, // not resolution scaled
    RC_SET_BUFFER,
    RC_COPY_RENDER,
    RC_POST_PROCESS, // postfx after scene rendering is done but before GUI rendering
    RC_CRT_POST_PROCESS, // CRT simulation after everything has been rendered on the final swapchain image
};

const EmptyCommand = extern struct {
    commandId: RenderCommand,
    next: ?*RenderCommand,
};

const SetBufferCommand = extern struct {
    commandId: RenderCommand,
    next: ?*RenderCommand,
    buffer: c_int,
};

const DrawSurfacesCommand = extern struct {
    commandId: RenderCommand,
    next: ?*RenderCommand,
    viewDef: ?*ViewDef,
};

const CopyRenderCommand = extern struct {
    commandId: RenderCommand,
    next: ?*RenderCommand,
    x: c_int,
    y: c_int,
    imageWidth: c_int,
    imageHeight: c_int,
    image: ?*Image,
    cubeFace: c_int,
    clearColorAfterCopy: bool,
};

const PostProcessCommand = extern struct {
    commandId: RenderCommand,
    next: ?*RenderCommand,
    viewDef: ?*ViewDef,
};

const CrtPostProcessCommand = extern struct {
    commandId: RenderCommand,
    next: ?*RenderCommand,
    padding: c_int,
};

pub const FrameData = extern struct {
    frameMemory: ?[*]u8,
    cmdHead: ?*EmptyCommand, // may be of other command type based on commandId
    cmdTail: ?*EmptyCommand,
};

pub var frame_data: ?*FrameData = null;

const MAX_FRAME_MEMORY: usize = 64 * 1024 * 1024;
const FRAME_ALLOC_ALIGNMENT: usize = 128;
const FRAME_MEMORY_ALIGNMENT: usize = 16;
const CACHE_LINE_SIZE: usize = 128;

// SMP = Symmetric multiprocessing / shared-memory multiprocessing
var smp_frame: usize = 0;
const NUM_FRAME_DATA: usize = 3;
var smp_frame_data: [NUM_FRAME_DATA]FrameData = undefined;
var buffer_allocators: [NUM_FRAME_DATA]std.heap.FixedBufferAllocator = undefined;

pub fn init(allocator: std.mem.Allocator) error{OutOfMemory}!void {
    shutdown(allocator);

    for (&smp_frame_data, &buffer_allocators) |*data, *frame_allocator| {
        const mem = try allocator.alignedAlloc(
            u8,
            FRAME_MEMORY_ALIGNMENT,
            MAX_FRAME_MEMORY,
        );
        frame_allocator.* = std.heap.FixedBufferAllocator.init(mem);
        data.frameMemory = mem.ptr;
    }

    frame_data = &smp_frame_data[0];

    toggleSmpFrame();
}

pub fn shutdown(allocator: std.mem.Allocator) void {
    if (frame_data == null) return;

    frame_data = null;

    for (&smp_frame_data, &buffer_allocators) |*data, *frame_allocator| {
        if (data.frameMemory) |frameMemory| {
            frame_allocator.reset();
            allocator.free(frameMemory[0..MAX_FRAME_MEMORY]);
            data.frameMemory = null;
        }
    }
}

pub inline fn bufferAllocator() *std.heap.FixedBufferAllocator {
    return &buffer_allocators[smp_frame % NUM_FRAME_DATA];
}

pub fn toggleSmpFrame() void {
    smp_frame += 1;

    bufferAllocator().reset();

    var empty_command = frameCreate(EmptyCommand);
    empty_command.commandId = .RC_NOP;
    empty_command.next = null;

    var current_frame_data = &smp_frame_data[smp_frame % NUM_FRAME_DATA];
    current_frame_data.cmdTail = empty_command;
    current_frame_data.cmdHead = current_frame_data.cmdTail;
    frame_data = current_frame_data;
}

pub fn frameAlloc(T: type, n: usize) []T {
    const frame_allocator = bufferAllocator().threadSafeAllocator();
    const byte_count = std.math.mul(usize, @sizeOf(T), n) catch {
        @panic("FrameData.frameAlloc: mul overflow");
    };
    const mem = allocBytes(frame_allocator, byte_count);
    const ptr: [*]T = @ptrCast(mem.ptr);

    return ptr[0..n];
}

pub fn frameCreate(T: type) *T {
    const frame_allocator = bufferAllocator().threadSafeAllocator();
    const mem = allocBytes(frame_allocator, @sizeOf(T));

    return @ptrCast(@alignCast(mem.ptr));
}

pub fn allocBytes(frame_allocator: std.mem.Allocator, bytes: usize) []u8 {
    const slice = frame_allocator.alignedAlloc(u8, FRAME_ALLOC_ALIGNMENT, bytes) catch {
        @panic("FrameData.alloc: ran out of memory!");
    };

    var offset: usize = 0;
    while (offset < bytes) : (offset += CACHE_LINE_SIZE) {
        const addr = @intFromPtr(slice.ptr) + offset;
        const aligned_addr = std.mem.alignBackward(usize, addr, CACHE_LINE_SIZE);
        const ptr: [*]u8 = @ptrFromInt(aligned_addr);
        @memset(ptr[0..CACHE_LINE_SIZE], 0);
    }

    return slice;
}

pub fn createCommandBuffer(bytes: usize) []u8 {
    const frame_allocator = bufferAllocator().threadSafeAllocator();
    const mem = allocBytes(frame_allocator, bytes);
    var cmd: *EmptyCommand = @ptrCast(@alignCast(mem.ptr));
    cmd.next = null;

    var current_frame_data = frame_data orelse unreachable;
    current_frame_data.cmdTail.?.next = &cmd.commandId;
    current_frame_data.cmdTail = cmd;

    return mem;
}
