//! @exportConsoleCommands
const std = @import("std");
const RenderWorld = @import("renderer/render_world.zig");
const RenderSystem = @import("renderer/render_system.zig");
const global = @import("global.zig");
const Player = @import("entity_types/player.zig");
const idlib = @import("idlib.zig");
const Decl = @import("framework/decl_manager.zig").Decl;
const DeclType = @import("framework/decl_manager.zig").DeclType;

const cmd = @import("framework/cmd_system.zig");
const CmdDecl = cmd.CmdDecl;

fn cmd_printCurrentTime(_: *const cmd.CmdArgs) callconv(.C) void {
    std.debug.print("Current Game.time: {}\n", .{instance.time});
}
pub const print_current_time: CmdDecl = .{
    .name = "printCurrentTime",
    .function = cmd_printCurrentTime,
    .flags = cmd.CmdFlags.CMD_FL_GAME,
    .description = "prints current game time in microsec",
    .arg_completion = null,
};

fn cmd_printCurrentFrame(_: *const cmd.CmdArgs) callconv(.C) void {
    std.debug.print("Current Game.frame: {}\n", .{instance.frame});
}
pub const print_current_frame = CmdDecl{
    .name = "printCurrentFrame",
    .function = cmd_printCurrentFrame,
    .flags = cmd.CmdFlags.CMD_FL_GAME,
    .description = "prints current game frame",
    .arg_completion = null,
};

pub const DeclEntityDef = extern struct {
    pub const default_definition =
        \\{
        \\  "DEFAULTED" "1"
        \\}
    ;

    base: Decl = .{},
    dict: idlib.idDict = .{},

    pub fn init(self: *DeclEntityDef) void {
        self.* = .{};
    }

    pub fn freeData(decl: *DeclEntityDef, allocator: std.mem.Allocator) void {
        _ = decl;
        _ = allocator;

        @panic("DeclEntityDef.freeData is not implemented");
    }

    pub const ParseError = error{};
    pub fn parse(
        decl: *DeclEntityDef,
        definition_text: []const u8,
        allow_binary_version: bool,
        allocator: std.mem.Allocator,
    ) ParseError!void {
        _ = decl;
        _ = allocator;
        _ = definition_text;
        _ = allow_binary_version;

        @panic("DeclEntityDef.parse is not implemented");
    }

    pub fn setDefaultText(decl: *DeclEntityDef) error{}!void {
        _ = decl;

        @panic("DeclEntityDef.setDefaultText is not implemented");
    }

    pub fn name(self: DeclEntityDef) []const u8 {
        const c_str = c_declGetName(&self);

        return std.mem.span(c_str);
    }

    pub fn index(self: DeclEntityDef) usize {
        return @intCast(c_declIndex(&self));
    }
};

pub extern fn c_findEntityDef([*c]const u8) callconv(.C) ?*const DeclEntityDef;
pub extern fn c_declByIndex(c_int) callconv(.C) ?*const DeclEntityDef;
pub extern fn c_declGetName(*const anyopaque) callconv(.C) [*c]const u8;
pub extern fn c_declIndex(*const anyopaque) callconv(.C) c_int;

const pvs = @import("pvs.zig");

extern fn c_getClientPvs([*]c_int, usize) callconv(.C) pvs.Handle;
extern fn c_freeClientPvs(pvs.Handle) callconv(.C) void;

// Latched version of cvar, updated between map loads
pub const com_engineHz_latched: f32 = 60;
pub const com_engineHz_numerator: u64 = 100 * 1000;
pub const com_engineHz_denominator: u64 = 100 * 60;

inline fn frameToMsec(frame: usize) usize {
    const numerator: f32 = @floatFromInt(frame * com_engineHz_numerator);
    const denominator: f32 = @floatFromInt(com_engineHz_denominator);

    return @intFromFloat(numerator / denominator);
}

num_clients: usize = 0,
frame: usize = 0,
render_world: ?*RenderWorld = null,
// merged pvs of all players
player_pvs: pvs.Handle = .{},
// all areas connected to any player area
player_connected_areas: pvs.Handle = .{},
new_frame: bool = true,
time: usize = 0,
prev_time: usize = 0,

const Game = @This();

pub var instance: Game = .{};

pub const DrawError = error{ NoPlayer, NoWorld } || RenderWorld.RenderSceneError;
pub fn draw(game: *Game) DrawError!void {
    const render_world = game.render_world orelse return error.NoWorld;
    const players = global.entities.getByType(Player).field_storage;
    if (players.len == 0) return error.NoPlayer;

    const player_view = &players.items(.view)[0];
    try render_world.renderScene(player_view.render_view);
}

pub fn initFromMap(game: *Game, render_world: *RenderWorld) void {
    game.render_world = render_world;
}

pub const MS2SEC: f32 = 0.001;
// in seconds
pub fn deltaTime(game: Game) f32 {
    return @as(f32, @floatFromInt(game.deltaTimeMs())) * MS2SEC;
}

pub fn deltaTimeMs(game: Game) usize {
    return game.time - game.prev_time;
}

pub fn runFrame(game: *Game) void {
    if (game.render_world == null) return;
    game.prev_time = frameToMsec(game.frame);
    game.frame += 1;
    game.time = frameToMsec(game.frame);

    const players = global.entities.getByType(Player).field_storage;
    if (players.len > 0) {
        // set render_view for current render_world
        const player_view = &players.items(.view)[0];
        RenderSystem.instance.primary_render_view = player_view.render_view;

        game.setupPlayerPvs(&players.items(.pvs_areas)[0]);
    }

    game.processEntities();

    game.freePlayerPvs();
}

fn setupPlayerPvs(game: *Game, player_areas: *Player.PVSAreas) void {
    game.player_pvs = c_getClientPvs(&player_areas.ids, player_areas.len);
    game.player_connected_areas = c_getClientPvs(&player_areas.ids, player_areas.len);
}

fn freePlayerPvs(game: *Game) void {
    if (game.player_pvs.i != -1) {
        c_freeClientPvs(game.player_pvs);
        game.player_pvs.i = -1;
    }

    if (game.player_connected_areas.i != -1) {
        c_freeClientPvs(game.player_connected_areas);
        game.player_connected_areas.i = -1;
    }
}

const UpdatePlayer = @import("update/player.zig");
const UpdateRenderEntity = @import("update/render_entity.zig");
const UpdateRenderLight = @import("update/render_light.zig");
const UpdatePhysicsClip = @import("update/physics/clip.zig");
const UpdatePhysicsContacts = @import("update/physics/contacts.zig");
const UpdatePhysicsImpact = @import("update/physics/impact.zig");
const UpdatePhysicsTransform = @import("update/physics/transform.zig");
const UpdateAnimation = @import("update/animation.zig");
const UpdateBoundedJointTransform = @import("update/joint_bounded.zig");
const CopyJointsToChild = @import("update/copy_joints.zig");

fn processEntities(game: *Game) void {
    if (!game.new_frame) return;

    var ents = &global.entities;

    ents.process(UpdatePlayer.handleInput);
    ents.process(UpdatePlayer.updateTransformByInput);
    ents.processWithQuery(Player, UpdatePlayer.update);

    ents.processWithQuery(UpdatePhysicsClip.Query, UpdatePhysicsClip.update);
    ents.processWithQuery(UpdatePhysicsContacts.Query, UpdatePhysicsContacts.update);
    ents.processWithQuery(UpdatePhysicsImpact.Query, UpdatePhysicsImpact.update);
    ents.processWithQuery(UpdatePhysicsTransform.Query, UpdatePhysicsTransform.update);

    ents.processWithQuery(UpdateAnimation.Query, UpdateAnimation.update);
    ents.processWithQuery(UpdateBoundedJointTransform.Query, UpdateBoundedJointTransform.update);
    ents.processWithQuery(CopyJointsToChild.Query, CopyJointsToChild.update);

    ents.process(UpdateRenderLight.fromTransform);
    ents.process(UpdateRenderLight.present);
    ents.process(UpdateRenderEntity.fromTransform);
    ents.process(UpdateRenderEntity.present);
}
