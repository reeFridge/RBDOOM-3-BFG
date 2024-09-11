const Animator = @import("../anim/animator.zig");
const Game = @import("../game.zig");

pub const Query = struct {
    animator: Animator,
};

pub fn update(list: anytype) void {
    var s = list.slice();

    for (s.items(.animator)) |*animator| {
        _ = animator.createFrame(Game.instance.time) catch @panic("createFrame failed!");
    }
}
