const decl = @import("decl_manager.zig");
const Decl = decl.Decl;
const DeclTable = decl.DeclTable;

const idlib = @import("../idlib.zig");
const CBounds = @import("../bounding_volume/bounds.zig").CBounds;
const Material = @import("../renderer/material.zig").Material;
const CVec3 = @import("../math/vector.zig").CVec3;
const CVec4 = @import("../math/vector.zig").CVec4;

const Param = extern struct {
    table: ?*const DeclTable,
    from: f32,
    to: f32,
};

const ParticleStage = extern struct {
    const Distribution = enum(c_int) {
        RECT, // ( sizeX sizeY sizeZ )
        CYLINDER, // ( sizeX sizeY sizeZ )
        SPHERE, // ( sizeX sizeY sizeZ ringFraction )
    };

    const Direction = enum(c_int) {
        CONE, // parm0 is the solid cone angle
        OUTWARD, // direction is relative to offset from origin, parm0 is an upward bias
    };

    const CustomPath = enum(c_int) {
        STANDARD,
        HELIX, // ( sizeX sizeY sizeZ radialSpeed climbSpeed )
        FLIES,
        ORBIT,
        DRIP,
    };

    const Orientation = enum(c_int) {
        VIEW,
        AIMED, // angle and aspect are disregarded
        X,
        Y,
        Z,
    };

    material: ?*const Material,
    totalParticles: c_int, // total number of particles, although some may be invisible at a given time
    cycles: f32, // allows things to oneShot ( 1 cycle ) or run for a set number of cycles on a per stage basis
    cycleMsec: c_int, // ( particleLife + deadTime ) in msec
    spawnBunching: f32, // 0.0 = all come out at first instant, 1.0 = evenly spaced over cycle time
    particleLife: f32, // total seconds of life for each particle
    timeOffset: f32, // time offset from system start for the first particle to spawn
    deadTime: f32, // time after particleLife before respawning
    // standard path parms
    distributionType: Distribution,
    distributionParms: [4]f32,
    directionType: Direction,
    directionParms: [4]f32,
    speed: Param,
    gravity: f32, // can be negative to float up
    worldGravity: bool, // apply gravity in world space
    randomDistribution: bool, // randomly orient the quad on emission ( defaults to true )
    entityColor: bool, // force color from render entity ( fadeColor is still valid )
    // custom path will completely replace the standard path calculations
    customPathType: CustomPath, // use custom C code routines for determining the origin
    customPathParms: [8]f32,
    offset: CVec3, // offset from origin to spawn all particles, also applies to customPath
    animationFrames: c_int, // if > 1, subdivide the texture S axis into frames and crossfade
    animationRate: f32, // frames per second
    initialAngle: f32, // in degrees, random angle is used if zero ( default )
    rotationSpeed: Param, // half the particles will have negative rotation speeds
    orientation: Orientation, // view, aimed, or axis fixed
    orientationParms: [4]f32,
    size: Param,
    aspect: Param, // greater than 1 makes the T axis longer
    color: CVec4,
    fadeColor: CVec4, // either 0 0 0 0 for additive, or 1 1 1 0 for blended materials
    fadeInFraction: f32, // in 0.0 to 1.0 range
    fadeOutFraction: f32, // in 0.0 to 1.0 range
    fadeIndexFraction: f32, // in 0.0 to 1.0 range, causes later index smokes to be more faded
    hidden: bool, // for editor use
    boundsExpansion: f32, // user tweak to fix poorly calculated bounds
    bounds: CBounds, // derived
};

pub const DeclParticle = extern struct {
    base: Decl,
    stages: idlib.idList(*ParticleStage),
    bounds: CBounds,
    depthHack: f32,
};
