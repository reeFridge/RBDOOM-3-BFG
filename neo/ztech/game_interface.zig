const Game = @import("game.zig");
const RenderWorld = @import("renderer/render_world.zig");

export fn ztech_game_draw(_: c_int) callconv(.C) bool {
    return Game.instance.draw();
}

export fn ztech_game_initFromMap(render_world: *RenderWorld) callconv(.C) void {
    Game.instance.render_world = render_world;
}

export fn ztech_game_runFrame() callconv(.C) void {
    Game.instance.runFrame();
}
