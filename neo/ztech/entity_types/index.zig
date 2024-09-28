const PlayerSpawn = @import("player_spawn.zig");
const StaticObject = @import("static_object.zig");
const MoveableObject = @import("moveable_object.zig");
const Player = @import("player.zig");
const Light = @import("light.zig");
const Animated = @import("animated.zig");
const AnimatedHead = @import("animated_head.zig");
const AnimatedWithHead = @import("animated_with_head.zig");
const AttachableItem = @import("attachable_item.zig");
const AnimatedAttachableItem = @import("animated_attachable_item.zig");
const Emitter = @import("emitter.zig");

pub const ExportedTypes = .{
    StaticObject,
    MoveableObject,
    PlayerSpawn,
    Player,
    Light,
    Animated,
    AnimatedHead,
    AnimatedWithHead,
    AttachableItem,
    Emitter,
    AnimatedAttachableItem,
};
