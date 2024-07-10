const RenderEntityLocal = @import("render_entity.zig").RenderEntityLocal;
const RenderLightLocal = @import("render_light.zig").RenderLightLocal;
const RenderEnvprobeLocal = @import("render_envprobe.zig").RenderEnvprobeLocal;
const PortalArea = @import("render_world.zig").PortalArea;

// areas have references to hold all the lights and entities in them
pub const AreaReference = extern struct {
    // chain in the area
    areaNext: ?*AreaReference,
    areaPrev: ?*AreaReference,
    // chain on either the entityDef or lightDef
    ownerNext: ?*AreaReference,
    // only one of entity / light / envprobe will be non-NULL
    entity: ?*RenderEntityLocal,
    // only one of entity / light / envprobe will be non-NULL
    light: ?*RenderLightLocal,
    // only one of entity / light / envprobe will be non-NULL
    envprobe: ?*RenderEnvprobeLocal,
    // so owners can find all the areas they are in
    area: ?*PortalArea,
};
