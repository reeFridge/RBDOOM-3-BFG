const Animator = @import("../anim/animator.zig");
const Game = @import("../game.zig");

pub const Query = struct {
    animator: Animator,
};

pub fn update(list: anytype) void {
    var s = list.slice();

    for (s.items(.animator)) |*animator| {
        const force_update = false;
        _ = animator.createFrame(Game.instance.time, force_update) catch @panic("createFrame failed!");
    }
}
