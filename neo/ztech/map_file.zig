const std = @import("std");
const Lexer = @import("lexer.zig").Lexer;
const Token = @import("token.zig").Token;
const idlib = @import("idlib.zig");
const CVec3 = @import("math/vector.zig").CVec3;
const Vec3 = @import("math/vector.zig").Vec3;
const CVec4 = @import("math/vector.zig").CVec4;
const CVec2 = @import("math/vector.zig").CVec2;
const CVec2i = @import("math/vector.zig").CVec2i;
const Plane = @import("math/plane.zig").Plane;
const DrawVertex = @import("geometry/draw_vertex.zig").DrawVertex;
const material = @import("renderer/material.zig");
const Bounds = @import("bounding_volume/bounds.zig");
const CBounds = @import("bounding_volume/bounds.zig").CBounds;
const Allocator = std.mem.Allocator;

const decl_manager = @import("framework/decl_manager.zig");

const old_map_version = 1;
const doom3_map_version = 2;
const current_map_version = 3;
const valve_220_map_version = 220;

pub const MapEntity = extern struct {
    kv_pairs: idlib.Dict = .{},
    origin_offset: CVec3 = .{},
    primitives: idlib.List(*MapPrimitive) = .{},

    pub fn calcGeometryCrc(entity: *const MapEntity) u32 {
        var crc: u32 = 0;

        for (entity.primitives.constSlice()) |primitive| {
            switch (primitive.type) {
                .brush => {
                    crc ^= @as(*const Brush, @ptrCast(primitive)).calcGeometryCrc();
                },
                .patch => {
                    @panic("not implemented");
                },
                .mesh => {
                    @panic("not implemented");
                },
                .invalid => @panic("invalid primitive type"),
            }
        }

        return crc;
    }

    pub const ParseError =
        error{ UnexpectedToken, OriginParse } ||
        std.fmt.ParseFloatError ||
        Lexer.ReadOnLineError ||
        Lexer.ReadTokenError ||
        Brush.ParseError ||
        Allocator.Error;
    pub fn parse(
        lexer: *Lexer,
        is_world_spawn: bool,
        version: u32,
        allocator: Allocator,
    ) ParseError!MapEntity {
        var token = Token{};
        defer token.deinit(allocator);

        try lexer.readToken(&token, allocator);

        if (!token.eql("{")) return error.UnexpectedToken;

        var entity = MapEntity{};

        if (is_world_spawn) {
            try entity.primitives.resizeWithGranularity(1024, 256, allocator);
        }

        var world_ent: bool = false;
        var origin = Vec3(f32){};
        while (true) {
            try lexer.readToken(&token, allocator);
            if (token.eql("}")) break;

            if (token.eql("{")) {
                // parse a brush or patch
                try lexer.readToken(&token, allocator);

                if (world_ent) {
                    origin = .{};
                }

                // if is it a brush: brush, brushDef, brushDef2, brushDef3
                if (std.ascii.startsWithIgnoreCase(
                    token.slice(),
                    "brush",
                )) {
                    const map_brush = try Brush.parse(
                        lexer,
                        origin,
                        (!token.ieql("brushDef2") or !token.ieql("brushDef3")),
                        version,
                        allocator,
                    );
                    _ = try entity.primitives.append(@ptrCast(map_brush), allocator);
                    // if is it a patch: patchDef2, patchDef3
                } else if (std.ascii.startsWithIgnoreCase(token.slice(), "patch")) {
                    @panic("not implemented");
                } else if (std.ascii.startsWithIgnoreCase(token.slice(), "mesh")) {
                    @panic("not implemented");
                } else {
                    // must be an valve220 style brush

                    try lexer.unreadToken(&token, allocator);
                    const map_brush = try Brush.parseValve220(lexer, origin, allocator);
                    _ = try entity.primitives.append(@ptrCast(map_brush), allocator);
                }
            } else {
                // must be an entity definition with kv-pairs

                var key: idlib.Str = .{};
                defer key.deinit(allocator);
                var value: idlib.Str = .{};
                defer value.deinit(allocator);

                try key.assignSlice(token.slice(), allocator);
                try lexer.readTokenOnLine(&token, allocator);
                try value.assignSlice(token.slice(), allocator);

                value.stripTrailingWhitespace();
                key.stripTrailingWhitespace();

                try entity.kv_pairs.set(key.slice(), value.slice(), allocator);

                if (std.ascii.eqlIgnoreCase(key.constSlice(), "origin")) {
                    var iterator = std.mem.splitSequence(u8, value.constSlice(), " ");

                    var i: u32 = 0;
                    while (iterator.next()) |float_literal| : (i += 1) {
                        origin.v[i] = try std.fmt.parseFloat(f32, float_literal);
                    }
                } else if (std.ascii.eqlIgnoreCase(key.constSlice(), "classname") and
                    std.ascii.eqlIgnoreCase(value.constSlice(), "worldspawn"))
                {
                    world_ent = true;
                }
            }
        }

        if (version == valve_220_map_version) {
            try entity.calculateBrushOrigin(allocator);
        }

        return entity;
    }

    fn calculateBrushOrigin(entity: *MapEntity, allocator: Allocator) Allocator.Error!void {
        var origin_brushes = idlib.List(*const Brush){};
        defer origin_brushes.clear(allocator);

        for (entity.primitives.constSlice()) |primitive_ptr| {
            if (primitive_ptr.type == .brush) {
                const brush: *const Brush = @ptrCast(primitive_ptr);
                if (brush.isOriginBrush(allocator)) {
                    _ = try origin_brushes.append(brush, allocator);
                }
            }
        }

        if (origin_brushes.num == 0) return;

        var origin_offset = Vec3(f32){};
        for (origin_brushes.constSlice()) |brush_ptr| {
            var mesh = PolygonMesh{};

            mesh.convertFromBrush(brush_ptr, 0, 0);
            const bounds = mesh.calcBounds();

            origin_offset = origin_offset.add(bounds.getCenter());
        }

        origin_offset = origin_offset.scale(
            1.0 / @as(f32, @floatFromInt(origin_brushes.num)),
        );

        entity.origin_offset = CVec3.fromVec3f(origin_offset);
    }

    pub fn deinit(entity: *MapEntity, allocator: Allocator) void {
        entity.kv_pairs.deinit(allocator);
        for (entity.primitives.slice()) |primitive_ptr| {
            allocator.destroy(primitive_ptr);
        }

        entity.primitives.clear(allocator);
    }
};

pub const MapFile = extern struct {
    version: u32 = current_map_version,
    file_time: idlib.Time = 0,
    geometry_crc: u32 = 0,
    entities: idlib.List(MapEntity) = .{},
    name: idlib.Str = .{},
    has_primitive_data: bool = false,
    use_valve_220_format: bool = false,

    fn setGeometryCrc(map_file: *MapFile) void {
        map_file.geometry_crc = 0;
        for (map_file.entities.constSlice()) |*entity| {
            map_file.geometry_crc ^= entity.calcGeometryCrc();
        }
    }

    pub const ParseError =
        Lexer.LoadFileError ||
        MapEntity.ParseError ||
        Allocator.Error;
    pub fn parse(
        map_file: *MapFile,
        filename: []const u8,
        allocator: Allocator,
    ) ParseError!void {
        var lexer = Lexer{};
        defer lexer.deinit(allocator);
        try lexer.initFromFile(
            filename,
            .{
                .no_string_concat = true,
                .no_string_escape_chars = true,
                .allow_path_names = true,
            },
            allocator,
        );

        map_file.version = old_map_version;
        map_file.file_time = lexer.file_time;
        for (map_file.entities.slice()) |*entity| entity.deinit(allocator);

        var token = Token{};
        defer token.deinit(allocator);

        try lexer.readToken(&token, allocator);

        if (token.eql("Version")) {
            try lexer.readTokenOnLine(&token, allocator);
            map_file.version = token.getUintValue();
        } else {
            try lexer.unreadToken(&token, allocator);
            map_file.use_valve_220_format = true;
            map_file.version = valve_220_map_version;
        }

        // parse all entities
        while (true) {
            const map_entity = MapEntity.parse(
                &lexer,
                map_file.entities.num == 0,
                map_file.version,
                allocator,
            ) catch break;
            _ = try map_file.entities.append(map_entity, allocator);
        }

        map_file.setGeometryCrc();
    }

    pub fn resizeEntities(map_file: *MapFile, allocator: Allocator) Allocator.Error!void {
        try map_file.entities.resizeWithGranularity(1024, 256, allocator);
    }

    pub fn deinit(map_file: *MapFile, allocator: Allocator) void {
        for (map_file.entities.slice()) |*entity| entity.deinit(allocator);
        map_file.entities.clear(allocator);
    }
};

pub const MapPrimitive = extern struct {
    pub const Type = enum(i32) {
        invalid = -1,
        brush,
        patch,
        mesh,
    };

    vptr: *anyopaque = undefined,
    kv_pairs: idlib.Dict = .{},
    type: Type = .invalid,
};

pub const BrushSide = extern struct {
    const ProjectionType = enum(u32) {
        bp,
        valve220,
    };

    material: idlib.Str = .{},
    plane: Plane = .{},
    tex_mat: [2]CVec3 = [_]CVec3{.{}} ** 2,
    origin: CVec3 = .{},
    plane_points: [3]CVec3 = [_]CVec3{.{}} ** 3,
    projection: ProjectionType = .bp,
    tex_valve: [2]CVec4 = [_]CVec4{.{}} ** 2,
    tex_scale: CVec2 = .{},
    tex_size: CVec2i = .{},
};

pub const Brush = extern struct {
    base: MapPrimitive = .{ .type = .brush },
    num_sides: u32 = 0,
    sides: idlib.List(BrushSide) = .{},

    pub fn calcGeometryCrc(brush: *const Brush) u32 {
        var crc: u32 = 0;

        for (brush.sides.constSlice()) |*side| {
            for (side.plane.constSlice()) |plane_component| {
                crc ^= floatCrc(plane_component);
            }
            crc ^= stringCrc(side.material.constSlice());
        }

        return crc;
    }

    pub fn isOriginBrush(brush: *const Brush, allocator: Allocator) bool {
        for (brush.sides.constSlice()) |*side| {
            const side_material = decl_manager.instance.findMaterialOrDefault(
                side.material.constSlice(),
                allocator,
            ) catch return false;

            if (side_material.content_flags.origin) {
                return true;
            }
        }

        return false;
    }

    pub const ParseError =
        error{ UnexpectedToken, ValueStringNotFound } ||
        Lexer.Parse1DMatrixError ||
        Lexer.ReadOnLineError ||
        Lexer.ReadTokenError ||
        Lexer.ExpectTokenStringError ||
        Allocator.Error;
    pub fn parse(
        lexer: *Lexer,
        origin: Vec3(f32),
        new_format: bool,
        version: u32,
        allocator: Allocator,
    ) ParseError!*Brush {
        try lexer.expectTokenString("{", allocator);

        var token = Token{};
        defer token.deinit(allocator);

        var kv_pairs = idlib.Dict{};
        defer kv_pairs.deinit(allocator);

        var sides = idlib.List(BrushSide){};
        defer sides.clear(allocator);

        var plane_points: [3]CVec3 = undefined;

        while (true) {
            try lexer.readToken(&token, allocator);
            if (token.eql("}")) break;

            // brush key-values
            while (true) {
                if (token.eql("(")) break;
                if (token.type != .string) return error.UnexpectedToken;

                var key: idlib.Str = .{};
                defer key.deinit(allocator);
                try key.assignSlice(token.slice(), allocator);

                try lexer.readTokenOnLine(&token, allocator);
                if (token.type != .string) return error.ValueStringNotFound;

                try kv_pairs.set(key.constSlice(), token.slice(), allocator);

                try lexer.readToken(&token, allocator);
            }

            try lexer.unreadToken(&token, allocator);

            var side = try sides.allocOne(allocator);
            side.* = .{};

            if (new_format) {
                var vec = std.mem.zeroes([4]f32);
                try lexer.parse1DMatrix(&vec, allocator);
                side.plane = Plane.fromSlice(&vec);
            } else {
                try lexer.parse1DMatrix(plane_points[0].slice(), allocator);
                try lexer.parse1DMatrix(plane_points[1].slice(), allocator);
                try lexer.parse1DMatrix(plane_points[2].slice(), allocator);

                side.plane = .{};
                side.plane.fromPoints(
                    plane_points[0].toVec3f().subtract(origin),
                    plane_points[1].toVec3f().subtract(origin),
                    plane_points[2].toVec3f().subtract(origin),
                    true,
                ) catch |err| {
                    std.debug.print("[Plane][WARN] {s}\n", .{@errorName(err)});
                };
            }

            // read the texture matrix
            try lexer.parse2DMatrix(2, 3, @as(*[6]f32, @ptrCast(&side.tex_mat)), allocator);
            side.origin = CVec3.fromVec3f(origin);

            if (version < 2) {
                try side.material.assignSlice("textures/", allocator);
                try side.material.appendSlice(token.slice(), allocator);
            } else {
                try side.material.assignSlice(token.slice(), allocator);
            }

            // skip Q2
            if (lexer.readTokenOnLineOk(&token, allocator)) {
                if (lexer.readTokenOnLineOk(&token, allocator)) {
                    if (lexer.readTokenOnLineOk(&token, allocator)) {}
                }
            }
        }

        try lexer.expectTokenString("}", allocator);

        var brush = try allocator.create(Brush);
        brush.* = .{};
        errdefer allocator.destroy(brush);

        for (sides.constSlice()) |side| {
            _ = try brush.sides.append(side, allocator);
            brush.num_sides += 1;
        }

        try brush.base.kv_pairs.copyFrom(&kv_pairs, allocator);

        return brush;
    }

    pub fn parseValve220(
        lexer: *Lexer,
        origin: Vec3(f32),
        allocator: Allocator,
    ) ParseError!*Brush {
        var token = Token{};
        defer token.deinit(allocator);

        var kv_pairs = idlib.Dict{};
        defer kv_pairs.deinit(allocator);

        var sides = idlib.List(BrushSide){};
        defer sides.clear(allocator);

        var plane_points: [3]CVec3 = undefined;

        while (true) {
            if (try lexer.checkTokenString("}", allocator)) break;

            var side = try sides.allocOne(allocator);
            side.* = .{};

            try lexer.parse1DMatrix(plane_points[0].slice(), allocator);
            try lexer.parse1DMatrix(plane_points[1].slice(), allocator);
            try lexer.parse1DMatrix(plane_points[2].slice(), allocator);

            side.plane_points[0] = plane_points[0];
            side.plane_points[1] = plane_points[1];
            side.plane_points[2] = plane_points[2];

            side.plane = .{};
            side.plane.fromPoints(
                plane_points[0].toVec3f().subtract(origin),
                plane_points[1].toVec3f().subtract(origin),
                plane_points[2].toVec3f().subtract(origin),
                true,
            ) catch |err| {
                std.debug.print("[Plane][WARN] {s}\n", .{@errorName(err)});
            };

            // material
            try lexer.readTokenOnLine(&token, allocator);

            var mat_prefix = Token{};
            var number_token = Token{};
            defer {
                number_token.deinit(allocator);
                mat_prefix.deinit(allocator);
            }

            if (token.eql("*") or token.eql("+") or token.type == .number) {
                try mat_prefix.assignToken(&token, allocator);

                if (token.eql("+")) {
                    try lexer.readTokenOnLine(&number_token, allocator);
                    if (number_token.type == .number) {
                        try lexer.readTokenOnLine(&token, allocator);
                    }
                } else {
                    try lexer.readTokenOnLine(&token, allocator);
                }
            }

            if (number_token.type == .number) {
                try side.material.assignSlice("textures/", allocator);
                try side.material.appendSlice(number_token.slice(), allocator);
                try side.material.appendSlice(token.slice(), allocator);
            } else {
                try side.material.assignSlice("textures/", allocator);
                try side.material.appendSlice(token.slice(), allocator);
            }

            side.projection = .valve220;

            for (0..2) |axis| {
                try lexer.expectTokenString("[", allocator);
                for (0..4) |component| {
                    var vec4: []f32 = @as(*[4]f32, @ptrCast(&side.tex_valve[axis]));
                    vec4[component] = try lexer.parseFloat(allocator);
                }
                try lexer.expectTokenString("]", allocator);
            }

            const rotate = try lexer.parseFloat(allocator);
            _ = rotate;
            side.tex_scale.x = try lexer.parseFloat(allocator);
            side.tex_scale.y = try lexer.parseFloat(allocator);
            side.tex_mat[0] = .{ .x = 0.3125 };
            side.tex_mat[1] = .{ .y = 0.3125 };
            side.origin = CVec3.fromVec3f(origin);

            // skip Q2
            if (lexer.readTokenOnLineOk(&token, allocator)) {
                if (lexer.readTokenOnLineOk(&token, allocator)) {
                    if (lexer.readTokenOnLineOk(&token, allocator)) {}
                }
            }
        }

        var brush = try allocator.create(Brush);
        brush.* = .{};
        errdefer allocator.destroy(brush);

        for (sides.constSlice()) |side| {
            _ = try brush.sides.append(side, allocator);
            brush.num_sides += 1;
        }

        return brush;
    }

    pub fn parseQ3(
        lexer: *Lexer,
        origin: Vec3(f32),
        allocator: Allocator,
    ) ParseError!*Brush {
        var token = Token{};
        defer token.deinit(allocator);

        var kv_pairs = idlib.Dict{};
        defer kv_pairs.deinit(allocator);

        var sides = idlib.List(BrushSide){};
        defer sides.clear(allocator);

        var plane_points: [3]CVec3 = undefined;

        while (true) {
            if (try lexer.checkTokenString("}", allocator)) break;

            var side = try sides.allocOne(allocator);
            side.* = .{};

            try lexer.parse1DMatrix(plane_points[0].slice(), allocator);
            try lexer.parse1DMatrix(plane_points[1].slice(), allocator);
            try lexer.parse1DMatrix(plane_points[2].slice(), allocator);

            side.plane = .{};
            side.plane.fromPoints(
                plane_points[0].toVec3f().subtract(origin),
                plane_points[1].toVec3f().subtract(origin),
                plane_points[2].toVec3f().subtract(origin),
                true,
            ) catch |err| {
                std.debug.print("[Plane][WARN] {s}\n", .{@errorName(err)});
            };

            // material
            try lexer.readTokenOnLine(&token, allocator);
            try side.material.assignSlice("textures/", allocator);
            try side.material.appendSlice(token.slice(), allocator);

            const shift0 = try lexer.parseFloat(allocator);
            _ = shift0;
            const shift1 = try lexer.parseFloat(allocator);
            _ = shift1;
            const rotate = try lexer.parseFloat(allocator);
            _ = rotate;
            side.tex_scale.x = try lexer.parseFloat(allocator);
            side.tex_scale.y = try lexer.parseFloat(allocator);
            side.tex_mat[0] = .{ .x = 0.3125 };
            side.tex_mat[1] = .{ .y = 0.3125 };
            side.origin = CVec3.fromVec3f(origin.*);

            // skip Q2
            if (lexer.readTokenOnLineOk(&token, allocator)) {
                if (lexer.readTokenOnLineOk(&token, allocator)) {
                    if (lexer.readTokenOnLineOk(&token, allocator)) {}
                }
            }
        }

        var brush = try allocator.create(Brush);
        brush.* = .{};
        errdefer allocator.destroy(brush);

        for (sides.constSlice()) |side| {
            _ = try brush.sides.append(side);
            brush.num_sides += 1;
        }

        return brush;
    }
};

pub const PolygonMesh = extern struct {
    pub const Polygon = extern struct {
        material: idlib.Str = .{},
        indexes: idlib.List(u32) = .{},
    };

    base: MapPrimitive = .{ .type = .mesh },
    original_type: MapPrimitive.Type = .mesh,
    vertices: idlib.List(DrawVertex) = .{},
    polygons: idlib.List(Polygon) = .{},
    surface_flags: material.ContentFlags = .{ .solid = true },
    is_opaque: bool = true,

    pub fn convertFromBrush(
        mesh: *PolygonMesh,
        brush: *const Brush,
        entity_num: u32,
        primitive_num: u32,
    ) void {
        _ = mesh;
        _ = brush;
        _ = entity_num;
        _ = primitive_num;
        @panic("not implemented");
    }

    pub fn calcBounds(mesh: *const PolygonMesh) Bounds {
        _ = mesh;
        @panic("not implemented");
    }
};

fn floatCrc(float: f32) u32 {
    return @bitCast(float);
}

fn stringCrc(string: []const u8) u32 {
    var crc: u32 = 0;
    for (string, 0..) |char, i| {
        crc ^= char << (@as(u3, @truncate(i)) & 3);
    }

    return crc;
}
