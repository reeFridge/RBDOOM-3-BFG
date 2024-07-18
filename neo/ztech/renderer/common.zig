const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;
const RenderEnvprobeLocal = @import("render_envprobe.zig").RenderEnvprobeLocal;
const PortalArea = @import("render_world.zig").PortalArea;

// areas have references to hold all the lights and entities in them
pub const AreaReference = extern struct {
    // chain in the area
    areaNext: ?*AreaReference = null,
    areaPrev: ?*AreaReference = null,
    // chain on either the entityDef or lightDef
    ownerNext: ?*AreaReference = null,
    // only one of entity / light / envprobe will be non-NULL
    entity: ?*RenderEntityLocal = null,
    // only one of entity / light / envprobe will be non-NULL
    light: ?*RenderLightLocal = null,
    // only one of entity / light / envprobe will be non-NULL
    envprobe: ?*RenderEnvprobeLocal = null,
    // so owners can find all the areas they are in
    area: ?*PortalArea = null,
};
