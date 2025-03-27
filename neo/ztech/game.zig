const std = @import("std");
const RenderWorld = @import("renderer/render_world.zig");
const RenderSystem = @import("renderer/render_system.zig");
const global = @import("global.zig");
const Player = @import("entity_types/player.zig");
const idlib = @import("idlib.zig");
const decl_manager = @import("framework/decl_manager.zig");
const Decl = decl_manager.Decl;
const DeclLocal = decl_manager.DeclLocal;
const DeclType = decl_manager.DeclType;
const DeclManager = decl_manager.DeclManager;
const DeclModelDef = @import("anim/animator.zig").DeclModelDef;
const ztech_lib = @import("lib.zig");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const MapFile = @import("map_file.zig").MapFile;
const Allocator = std.mem.Allocator;

pub const DeclEntityDef = extern struct {
    pub const default_definition =
        \\{
        \\  "DEFAULTED" "1"
        \\}
    ;

    base: Decl = .{},
    dict: idlib.Dict = .{},

    pub fn init(self: *DeclEntityDef) void {
        self.* = .{};
    }

    pub fn freeData(self: *DeclEntityDef, allocator: Allocator) void {
        self.dict.deinit(allocator);
    }

    pub const ParseError =
        error{UnexpectedToken} ||
        Lexer.ReadTokenError ||
        Lexer.LoadMemoryError ||
        Allocator.Error;
    pub fn parse(
        self: *DeclEntityDef,
        definition_text: []const u8,
        allow_binary_version: bool,
        allocator: Allocator,
    ) ParseError!void {
        _ = allow_binary_version;

        var lexer = Lexer{ .flags = decl_manager.decl_lexer_flags };
        defer lexer.deinit(allocator);

        const decl_local = self.base.base.?;

        try lexer.loadMemory(
            definition_text,
            decl_local.filename() orelse "*invalid*",
            decl_local.source_line,
            allocator,
        );

        try lexer.skipUntilString("{", allocator);

        var token = Token{};
        defer token.deinit(allocator);
        var token2 = Token{};
        defer token2.deinit(allocator);

        while (true) {
            try lexer.readToken(&token, allocator);
            if (token.ieql("}")) break;

            errdefer self.makeDefault(allocator) catch @panic("makeDefault fails");

            if (token.type != .string) return error.UnexpectedToken;
            try lexer.readToken(&token2, allocator);

            if (self.dict.findKey(token.slice()) != null) {
                std.debug.print("[PARSE] key '{s}' already defined\n", .{token.slice()});
            }

            try self.dict.set(token.slice(), token2.slice(), allocator);
        }

        // always set classname to decl name
        try self.dict.set(
            "classname",
            decl_local.name.constSlice(),
            allocator,
        );

        // TODO: inheritance (extension?) of definitions
    }

    fn makeDefault(
        self: *DeclEntityDef,
        allocator: Allocator,
    ) DeclLocal.MakeDefaultError!void {
        const decl_local = self.base.base.?;
        const rt_decl_type = decl_manager.instance.getRuntimeType(decl_local.decl_type);
        try decl_local.makeDefault(rt_decl_type, allocator);
    }

    pub fn name(self: *const DeclEntityDef) []const u8 {
        return self.base.base.?.name.constSlice();
    }

    pub fn index(self: *const DeclEntityDef) usize {
        return self.base.base.?.index;
    }
};

const pvs_mod = @import("pvs.zig");

// Latched version of cvar, updated between map loads
pub const com_engineHz_latched: f32 = 60;
pub const com_engineHz_numerator: u64 = 100 * 1000;
pub const com_engineHz_denominator: u64 = 100 * 60;

pub inline fn frameToMsec(frame: usize) usize {
    const numerator: f32 = @floatFromInt(frame * com_engineHz_numerator);
    const denominator: f32 = @floatFromInt(com_engineHz_denominator);

    return @intFromFloat(numerator / denominator);
}

num_clients: usize = 0,
frame: usize = 0,
render_world: ?*RenderWorld = null,
pvs: pvs_mod.PotentialVisibleSet = .{},
// merged pvs of all players
player_pvs: pvs_mod.Handle = .{},
// all areas connected to any player area
player_connected_areas: pvs_mod.Handle = .{},
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

pub fn init(
    game: *Game,
    allocator: Allocator,
) DeclManager.RegisterDeclFolderError!void {
    _ = game;
    try decl_manager.instance.registerDeclType(
        "model",
        .modeldef,
        decl_manager.DeclInterface(DeclModelDef),
    );
    try decl_manager.instance.registerDeclType(
        "export",
        .modelexport,
        decl_manager.DeclInterface(Decl),
    );
    try decl_manager.instance.registerDeclFolder(
        "def",
        ".def",
        .entitydef,
        allocator,
    );

    ztech_lib.ztech_init();
}

pub const InitForMapError =
    Allocator.Error ||
    SpawnEntityDefError ||
    MapFile.ParseError;
pub fn initForMap(
    game: *Game,
    map_name: []const u8,
    render_world: *RenderWorld,
    allocator: Allocator,
) InitForMapError!void {
    game.render_world = render_world;

    try game.pvs.init(render_world, allocator);

    var map_file = MapFile{};
    defer map_file.deinit(allocator);
    try map_file.resizeEntities(allocator);

    try map_file.parse(map_name, allocator);
    try mapPopulate(&map_file, allocator);
}

fn mapPopulate(map_file: *MapFile, allocator: Allocator) SpawnEntityDefError!void {
    // world_spawn is always at index 0
    const world_spawn_entity = &map_file.entities.slice()[0];
    try spawnEntityDef(&world_spawn_entity.kv_pairs, allocator);

    for (map_file.entities.slice()[1..]) |*entity| {
        try spawnEntityDef(&entity.kv_pairs, allocator);
    }
}

pub const SpawnEntityDefError =
    DeclManager.FindDeclError ||
    Allocator.Error;
fn spawnEntityDef(
    spawn_args: *idlib.Dict,
    allocator: Allocator,
) SpawnEntityDefError!void {
    const class_name = spawn_args.getString("classname") orelse {
        std.debug.print("[ENTITY] map entity has no classname key-value pair\n", .{});
        return;
    };

    const entity_def = try decl_manager.instance.findEntityDef(
        class_name,
        allocator,
    ) orelse {
        std.debug.print("[ENTITY] entity def '{s}' not found\n", .{
            class_name,
        });
        return;
    };

    try spawn_args.setDefaults(&entity_def.dict, allocator);

    // debug
    std.debug.print("[SPAWN]\n", .{});
    for (spawn_args.args.constSlice()) |kv| {
        std.debug.print("{s} = {s}\n", .{
            kv.key.?.str.constSlice(),
            kv.value.?.str.constSlice(),
        });
    }

    const type_name = spawn_args.getString("spawnexternal") orelse {
        std.debug.print(
            "[ENTITY] map entity has no spawnexternal key-value pair\n",
            .{},
        );
        return;
    };

    _ = global.entities.spawn(type_name, spawn_args) catch |err| {
        std.debug.print("[ERR] {?}\n", .{err});
        return;
    };

    std.debug.print("[OK]\n---\n", .{});
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
    const render_world = game.render_world orelse return;
    game.prev_time = frameToMsec(game.frame);
    game.frame += 1;
    game.time = frameToMsec(game.frame);

    const players = global.entities.getByType(Player).field_storage;
    if (players.len > 0) {
        // set render_view for current render_world
        const player_view = &players.items(.view)[0];
        RenderSystem.instance.primary_render_view = player_view.render_view;

        game.setupPlayerPvs(&players.items(.pvs_areas)[0], render_world);
    }

    game.processEntities();

    game.freePlayerPvs();
}

fn setupPlayerPvs(
    game: *Game,
    player_areas: *Player.PVSAreas,
    render_world: *const RenderWorld,
) void {
    game.player_pvs = game.pvs.setupCurrentPVS(
        &player_areas.ids,
        .normal,
        render_world,
    );
    game.player_connected_areas = game.pvs.setupCurrentPVS(
        &player_areas.ids,
        .normal,
        render_world,
    );
}

fn freePlayerPvs(game: *Game) void {
    if (game.player_pvs.index != -1) {
        game.pvs.freeCurrentPVS(game.player_pvs);
        game.player_pvs.index = -1;
    }

    if (game.player_connected_areas.index != -1) {
        game.pvs.freeCurrentPVS(game.player_connected_areas);
        game.player_connected_areas.index = -1;
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
