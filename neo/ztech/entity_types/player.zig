const std = @import("std");
const CVec3 = @import("../math/vector.zig").CVec3;
const CMat3 = @import("../math/matrix.zig").CMat3;
const Vec3 = @import("../math/vector.zig").Vec3;
const RenderView = @import("../renderer/render_world.zig").RenderView;
const Mat3 = @import("../math/matrix.zig").Mat3;
const Transform = @import("../physics/physics.zig").Transform;
const Angles = @import("../math/angles.zig");
const pvs = @import("../pvs.zig");
const Bounds = @import("../bounding_volume/bounds.zig");

extern fn c_calculateRenderView(*RenderView, f32) void;

pub const View = struct {
    origin: Vec3(f32),
    axis: Mat3(f32),
    fov: f32 = 80,
    render_view: RenderView = std.mem.zeroes(RenderView),

    pub fn calculateRenderView(self: *View) void {
        c_calculateRenderView(&self.render_view, self.fov);
        self.render_view.vieworg = CVec3.fromVec3f(self.origin);
        self.render_view.viewaxis = CMat3.fromMat3f(self.axis);
    }
};

pub const PlayerSpawnError = error{
    PlayerSpawnNotFound,
};

const MAX_PVS_AREAS: usize = 4;

pub const PVSAreas = struct {
    updated: bool,
    len: usize,
    ids: [MAX_PVS_AREAS]c_int,

    pub fn update(self: *PVSAreas, position: Vec3(f32)) void {
        var count = pvs.getPVSAreas(Bounds.fromVec3(position), &self.ids);
        self.len = count;

        while (count < MAX_PVS_AREAS) {
            self.ids[count] = 0;
            count += 1;
        }

        self.updated = true;
    }
};

pub const byte = u8;
pub const uint16 = c_ushort;

pub const UserCmd = extern struct {
    angles: [3]c_short,
    forwardmove: i8,
    rightmove: i8,
    buttons: byte,
    clientGameMilliseconds: c_int,
    serverGameMilliseconds: c_int,
    fireCount: uint16,
    impulse: byte,
    impulseSequence: byte,
    mx: c_short,
    my: c_short,
    pos: CVec3,
    speedSquared: f32,
};

pub const Input = struct {
    user_cmd: UserCmd = std.mem.zeroes(UserCmd),
};

const Player = @This();

client_id: u8,
input: Input,
transform: Transform,
view: View,
delta_view_angles: Angles = .{},
pvs_areas: PVSAreas = std.mem.zeroes(PVSAreas),

pub fn init(client_id: u8, transform: Transform) Player {
    return .{
        .client_id = client_id,
        .input = .{},
        .transform = transform,
        .view = .{
            .origin = transform.origin,
            .axis = transform.axis,
        },
    };
}
