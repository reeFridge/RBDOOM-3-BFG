const std = @import("std");
const math = @import("../math/math.zig");
const assertFields = @import("../entity.zig").assertFields;
const Input = @import("../types.zig").Input;
const UserCmd = @import("../types.zig").UserCmd;
const Transform = @import("../physics/physics.zig").Transform;
const Mat3 = @import("../math/matrix.zig").Mat3;
const Game = @import("../game.zig");

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

const Angles = @import("../math/angles.zig");

inline fn shortToAngle(angle_short: c_short) f32 {
    return @as(f32, @floatFromInt(angle_short)) * (360.0 / 65536.0);
}

pub fn updateTransformByInput(T: type, list: anytype) void {
    if (comptime !assertFields(struct {
        delta_view_angles: Angles,
        transform: Transform,
        input: Input,
    }, T)) return;

    const dt = Game.instance.deltaTime();

    var list_slice = list.slice();
    for (
        list_slice.items(.delta_view_angles),
        list_slice.items(.transform),
        list_slice.items(.input),
    ) |*delta_view_angles, *transform, input| {
        var view_angles = Angles{
            .pitch = math.angleNormalize180(
                shortToAngle(input.user_cmd.angles[0]) + delta_view_angles.pitch,
            ),
            .yaw = math.angleNormalize180(
                shortToAngle(input.user_cmd.angles[1]) + delta_view_angles.yaw,
            ),
            .roll = math.angleNormalize180(
                shortToAngle(input.user_cmd.angles[2]) + delta_view_angles.roll,
            ),
        };

        const max_view_pitch = 89.0;
        const min_view_pitch = -89.0;
        const restrict = 1.0;
        view_angles.pitch = @min(view_angles.pitch, max_view_pitch * restrict);
        view_angles.pitch = @max(view_angles.pitch, min_view_pitch * restrict);

        // update delta_view_angles
        // docs: Prevents snapping at max and min angles
        delta_view_angles.pitch = view_angles.pitch - shortToAngle(input.user_cmd.angles[0]);
        delta_view_angles.yaw = view_angles.yaw - shortToAngle(input.user_cmd.angles[1]);
        delta_view_angles.roll = view_angles.roll - shortToAngle(input.user_cmd.angles[2]);

        // update transform
        transform.axis = view_angles.toMat3();

        const forward = transform.axis.v[0].normalize();
        const wishvel = forward.scale(@floatFromInt(input.user_cmd.forwardmove));

        transform.origin = transform.origin.add(wishvel.scale(dt));
    }
}
