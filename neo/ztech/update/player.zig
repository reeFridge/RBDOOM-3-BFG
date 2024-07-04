const std = @import("std");
const assertFields = @import("../entity.zig").assertFields;
const Input = @import("../types.zig").Input;
const UserCmd = @import("../types.zig").UserCmd;
const Transform = @import("../physics/physics.zig").Transform;
const Mat3 = @import("../math/matrix.zig").Mat3;

pub fn update(list: anytype) void {
    var list_slice = list.slice();
    for (
        list_slice.items(.transform),
        list_slice.items(.view),
        list_slice.items(.pvs_areas),
    ) |transform, *view, *pvs_areas| {
        pvs_areas.update(transform.origin);

        view.origin = transform.origin;
        view.axis = transform.axis;

        view.calculateRenderView();
    }
}

extern fn c_hasUserCmdForPlayer(c_int) callconv(.C) bool;
extern fn c_getUserCmdForPlayer(c_int) callconv(.C) UserCmd;

pub fn handleInput(T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        client_id: u8,
        input: Input,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.client_id),
        list_slice.items(.input),
    ) |client_id, *input| {
        if (!c_hasUserCmdForPlayer(@intCast(client_id))) continue;
        input.user_cmd = c_getUserCmdForPlayer(@intCast(client_id));
    }
}

fn angleNormalize360(angle: f32) f32 {
    return if ((angle >= 360.0) or (angle < 0.0))
        angle - @floor(angle * (1.0 / 360.0)) * 360.0
    else
        angle;
}

fn angleNormalize180(angle: f32) f32 {
    const angle_ = angleNormalize360(angle);
    return if (angle_ > 180.0)
        angle_ - 360.0
    else
        angle_;
}

fn sincos(a: f32, s: *f32, c: *f32) void {
    s.* = std.math.sin(a);
    c.* = std.math.cos(a);
}

pub fn updateViewAngles(T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        transform: Transform,
        input: Input,
    }, T)) return;

    var list_slice = list.slice();
    for (
        list_slice.items(.transform),
        list_slice.items(.input),
    ) |*transform, input| {
        var view_angles: [3]f32 = .{0} ** 3; // pitch, yaw, roll
        for (input.user_cmd.angles, 0..) |angle_short, i| {
            view_angles[i] = angleNormalize180(@as(f32, @floatFromInt(angle_short)) * (360.0 / 65536.0));
        }

        const max_view_pitch = 89.0;
        const min_view_pitch = -89.0;
        const restrict = 1.0;
        view_angles[0] = @min(view_angles[0], max_view_pitch * restrict);
        view_angles[0] = @max(view_angles[0], min_view_pitch * restrict);

        var view_axis = Mat3(f32).identity();
        var sr: f32 = 0.0;
        var sp: f32 = 0.0;
        var sy: f32 = 0.0;
        var cr: f32 = 0.0;
        var cp: f32 = 0.0;
        var cy: f32 = 0.0;

        sincos(std.math.degreesToRadians(view_angles[1]), &sy, &cy);
        sincos(std.math.degreesToRadians(view_angles[0]), &sp, &cp);
        sincos(std.math.degreesToRadians(view_angles[2]), &sr, &cr);

        view_axis.v[0] = .{
            .x = cp * cy,
            .y = cp * sy,
            .z = -sp,
        };
        view_axis.v[1] = .{
            .x = sr * sp * cy + cr * -sy,
            .y = sr * sp * sy + cr * cy,
            .z = sr * cp,
        };
        view_axis.v[2] = .{
            .x = cr * sp * cy + -sr * -sy,
            .y = cr * sp * sy + -sr * cy,
            .z = cr * cp,
        };

        transform.axis = view_axis;
    }
}
